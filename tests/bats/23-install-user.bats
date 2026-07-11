#!/usr/bin/env bats
# tests/bats/23-install-user.bats — INST-07 (AL-50): configurable target
# install username at install time.
#
# Every @test name starts with `INST-07:` (TST-07 grep gate).
#
# Covers the five AL-50 acceptance criteria + the AL-59 hollow-install closure:
#   AC1 — default install provisions user `agent` (no flag, non-TTY).
#   AC2 — --user=NAME and AGENTLINUX_USER=NAME provision under NAME; a
#         pre-existing uid>=1000 NAME is ADOPTED, not recreated.
#   AC3 — an interactive install prompts and provisions under the typed name.
#   AC4 — sudoers, PATH wiring, the catalog CLI guard + recipe DISPATCH user,
#         and the Node prefix all reference NAME; no leftover `agent`.
#   AC5 — invalid usernames (root / reserved / non-POSIX) are rejected with
#         exit 64 BEFORE any host mutation.
#
# Harness contract: tests/docker/run.sh has already run the DEFAULT installer
# (user `agent`) before bats, staging the sources at /opt/agentlinux-src. The
# alt-user assertions re-invoke the staged installer with --user=claude (mirror
# 10-installer.bats's INST-02 re-run pattern). Because the canonical artefacts
# (/etc/sudoers.d/agentlinux, /etc/agentlinux.env, /etc/profile.d/agentlinux.sh,
# the /opt/agentlinux state dir) are single shared files, this file MUST restore
# the agent baseline in teardown_file so downstream bats files (30-runtime,
# 40-registry-cli, 50-agents, ...) see the same shape the harness staged.

load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install
TTY_DRIVER=/opt/agentlinux-src/tests/bats/helpers/tty-driver.py
ALT_USER=claude

# Pre-create the alt user as a regular login (uid>=1000) BEFORE any install so
# the AC2 adoption assertion has a stable uid/home to compare against. The
# install must ADOPT (not recreate) it.
setup_file() {
  if ! id "$ALT_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$ALT_USER" >/dev/null 2>&1 || true
  fi
  # Record uid + home for the adoption assertion (shared across @tests in file).
  id -u "$ALT_USER" >"${BATS_FILE_TMPDIR}/alt_uid" 2>/dev/null || true
  getent passwd "$ALT_USER" | cut -d: -f6 >"${BATS_FILE_TMPDIR}/alt_home" 2>/dev/null || true
}

# Restore the canonical agent baseline. Purge the alt user (removes it + the
# shared installer-placed files), then re-run the default installer to recreate
# the agent-owned artefacts. Mirrors 15-preflight-ux.bats's teardown_file.
teardown_file() {
  bash "$INSTALLER" --purge --user="$ALT_USER" >/dev/null 2>&1 || true
  rm -f /tmp/agentlinux-test-dummy.marker || true
  bash "$INSTALLER" >/dev/null 2>&1 || true
  # SSH keypair recovery (mirrors 50-agents.bats): the AC3 test runs
  # `--purge` (no --user) to reach a greenfield state, and that `userdel -r
  # agent` deletes /home/agent including ~/.ssh/authorized_keys. The reinstall
  # above recreates the agent user but does NOT re-authorize the keypair (that's
  # harness setup, not installer scope), so downstream ssh-mode tests
  # (30-runtime, 40-registry-cli) would fail to log in. Restore it when absent;
  # /root/.ssh/id_ed25519 survives --purge (root's $HOME is untouched).
  if [[ -f /root/.ssh/id_ed25519.pub ]] \
    && [[ ! -f /home/agent/.ssh/authorized_keys ]]; then
    install -d -m 0700 -o agent -g agent /home/agent/.ssh
    install -m 0600 -o agent -g agent \
      /root/.ssh/id_ed25519.pub /home/agent/.ssh/authorized_keys
    systemctl start ssh >/dev/null 2>&1 || true
  fi
}

# Run the alt-user install once; idempotent re-runs are harmless. Tests that
# need the alt-user state call this first. `--yes` is required: the harness has
# already installed the default `agent`, so switching the shared artefacts
# (sudoers line, /etc/agentlinux.env, npm prefix) to the alt user is a
# state-changing remediation that the v0.3.4 aware installer gates behind
# explicit consent (it otherwise bails exit 65). AL-50 adds --user; it does not
# relax that consent gate.
_install_alt_user() {
  run bash "$INSTALLER" --user="$ALT_USER" --yes
  assert_exit_zero "INST-07"
}

# ---------------------------------------------------------------------------
# AC1 — default install provisions `agent` (asserts the pre-bats harness state;
# MUST run before any alt-user install clobbers the shared artefacts).
# ---------------------------------------------------------------------------
@test "INST-07: AC1 default install provisioned user 'agent' (no flag, non-TTY)" {
  getent passwd agent >/dev/null \
    || __fail "INST-07" "user 'agent' exists" "getent passwd agent failed" "$LOG"
  grep -q '^PATH=/home/agent/.npm-global/bin:' /etc/agentlinux.env \
    || __fail "INST-07" "/etc/agentlinux.env PATH under /home/agent" "$(grep '^PATH=' /etc/agentlinux.env)" /etc/agentlinux.env
  grep -Fxq 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "INST-07" "sudoers names agent" "$(cat /etc/sudoers.d/agentlinux)" /etc/sudoers.d/agentlinux
}

# ---------------------------------------------------------------------------
# AC5 — invalid usernames rejected with exit 64 BEFORE any mutation. Runs
# before the alt-user install so the asserted "no mutation" baseline is the
# intact agent state. Non-mutating by contract (validation precedes require_root
# and every provisioner).
# ---------------------------------------------------------------------------
@test "INST-07: AC5 invalid usernames rejected with exit 64 and zero mutation" {
  local bad
  for bad in root www-data daemon nobody "Bad" "a b" "../x" "0bad"; do
    run bash "$INSTALLER" --user="$bad"
    [[ "$status" -eq 64 ]] \
      || __fail "INST-07" "exit 64 for --user='${bad}'" "status=${status}; output: ${output}" "$LOG"
    # No NEW user created for the non-existent bad names.
    case "$bad" in
      root | www-data | daemon | nobody) : ;; # pre-existing system accts; skip create check
      *)
        ! getent passwd "$bad" >/dev/null 2>&1 \
          || __fail "INST-07" "no user created for invalid '${bad}'" "getent passwd ${bad} succeeded" "$LOG"
        ;;
    esac
    # The sudoers drop-in was NOT mutated to grant the bad name.
    ! grep -Eq "^${bad}[[:space:]]" /etc/sudoers.d/agentlinux 2>/dev/null \
      || __fail "INST-07" "sudoers not granted to invalid '${bad}'" "$(cat /etc/sudoers.d/agentlinux)" /etc/sudoers.d/agentlinux
  done
}

# ---------------------------------------------------------------------------
# AC5 — an EXISTING system account (uid<1000) is refused adoption with exit 64.
# This exercises remediate::user_adoptable, the runtime gate the charset/reserved
# denylist above never reaches: `svcacct` passes validate_user_name (valid
# charset, not reserved), so user_adoptable is the only thing standing between a
# stray system account and a NOPASSWD: ALL grant / clobbered home. Exit 64 fires
# after require_root but before any provisioner, so no mutation occurs.
# ---------------------------------------------------------------------------
@test "INST-07: AC5 existing system account (uid<1000) refused adoption with exit 64" {
  if ! id svcacct >/dev/null 2>&1; then
    useradd -r svcacct >/dev/null 2>&1 || true
  fi
  [[ "$(id -u svcacct)" -lt 1000 ]] \
    || __fail "INST-07" "svcacct is a uid<1000 system account" "uid=$(id -u svcacct)" "$LOG"
  run bash "$INSTALLER" --user=svcacct
  [[ "$status" -eq 64 ]] \
    || __fail "INST-07" "exit 64 adopting uid<1000 svcacct" "status=${status}; output: ${output}" "$LOG"
  # The gate fires before mutation: sudoers was not granted to svcacct.
  ! grep -Eq '^svcacct[[:space:]]' /etc/sudoers.d/agentlinux 2>/dev/null \
    || __fail "INST-07" "sudoers not granted to svcacct" "$(cat /etc/sudoers.d/agentlinux)" /etc/sudoers.d/agentlinux
}

# ---------------------------------------------------------------------------
# AC2 + AC4 — --user=claude provisions every artefact under claude.
# ---------------------------------------------------------------------------
@test "INST-07: AC2/AC4 --user=claude provisions every artefact under claude" {
  _install_alt_user

  # User exists (adopted) + Node prefix dirs + symlink resolve under /home/claude.
  getent passwd "$ALT_USER" >/dev/null \
    || __fail "INST-07" "user ${ALT_USER} exists" "missing" "$LOG"
  run readlink "/home/${ALT_USER}/.npm-global/bin/agentlinux"
  assert_exit_zero "INST-07"
  [[ -n "$output" ]] \
    || __fail "INST-07" "agentlinux symlink under /home/${ALT_USER}" "dangling/missing" "$LOG"

  # sudoers names claude, visudo-clean, 0440 root:root.
  grep -Fxq "${ALT_USER} ALL=(ALL) NOPASSWD: ALL" /etc/sudoers.d/agentlinux \
    || __fail "INST-07" "sudoers names ${ALT_USER}" "$(cat /etc/sudoers.d/agentlinux)" /etc/sudoers.d/agentlinux
  visudo -cf /etc/sudoers.d/agentlinux >/dev/null \
    || __fail "INST-07" "sudoers visudo-clean" "visudo -cf failed" /etc/sudoers.d/agentlinux
  [[ "$(stat -c '%a %U:%G' /etc/sudoers.d/agentlinux)" == "440 root:root" ]] \
    || __fail "INST-07" "sudoers 0440 root:root" "$(stat -c '%a %U:%G' /etc/sudoers.d/agentlinux)" /etc/sudoers.d/agentlinux

  # /etc/agentlinux.env carries AGENTLINUX_USER=claude + claude PATH.
  grep -Fxq "AGENTLINUX_USER=${ALT_USER}" /etc/agentlinux.env \
    || __fail "INST-07" "agentlinux.env AGENTLINUX_USER=${ALT_USER}" "$(cat /etc/agentlinux.env)" /etc/agentlinux.env
  grep -q "^PATH=/home/${ALT_USER}/.npm-global/bin:" /etc/agentlinux.env \
    || __fail "INST-07" "agentlinux.env PATH under /home/${ALT_USER}" "$(grep '^PATH=' /etc/agentlinux.env)" /etc/agentlinux.env

  # `sudo -u claude -H agentlinux list` succeeds (guard accepts claude; CLI on PATH).
  run sudo -u "$ALT_USER" -H bash --login -c 'agentlinux list'
  assert_exit_zero "INST-07"
  assert_no_eacces "INST-07" "$output"
}

# ---------------------------------------------------------------------------
# AC2 — pre-existing uid>=1000 user is ADOPTED, not recreated.
# ---------------------------------------------------------------------------
@test "INST-07: AC2 pre-existing user is adopted (uid + home unchanged)" {
  _install_alt_user
  local uid_before home_before
  uid_before=$(cat "${BATS_FILE_TMPDIR}/alt_uid" 2>/dev/null || echo "")
  home_before=$(cat "${BATS_FILE_TMPDIR}/alt_home" 2>/dev/null || echo "")
  [[ -n "$uid_before" ]] \
    || __fail "INST-07" "recorded pre-install uid for ${ALT_USER}" "missing" "$LOG"
  [[ "$(id -u "$ALT_USER")" == "$uid_before" ]] \
    || __fail "INST-07" "uid unchanged (adopted, not recreated)" "before=${uid_before} after=$(id -u "$ALT_USER")" "$LOG"
  [[ "$(getent passwd "$ALT_USER" | cut -d: -f6)" == "$home_before" ]] \
    || __fail "INST-07" "home unchanged (adopted)" "before=${home_before} after=$(getent passwd "$ALT_USER" | cut -d: -f6)" "$LOG"
}

# ---------------------------------------------------------------------------
# AC2 — AGENTLINUX_USER=NAME env (no flag) honored identically.
# ---------------------------------------------------------------------------
@test "INST-07: AC2 AGENTLINUX_USER env (no flag) honored identically to --user" {
  run env AGENTLINUX_USER="$ALT_USER" bash "$INSTALLER" --yes
  assert_exit_zero "INST-07"
  grep -Fxq "AGENTLINUX_USER=${ALT_USER}" /etc/agentlinux.env \
    || __fail "INST-07" "env-driven install wrote AGENTLINUX_USER=${ALT_USER}" "$(cat /etc/agentlinux.env)" /etc/agentlinux.env
  grep -Fxq "${ALT_USER} ALL=(ALL) NOPASSWD: ALL" /etc/sudoers.d/agentlinux \
    || __fail "INST-07" "env-driven install sudoers names ${ALT_USER}" "$(cat /etc/sudoers.d/agentlinux)" /etc/sudoers.d/agentlinux
}

# ---------------------------------------------------------------------------
# AC4 — no leftover `agent` in the per-host install artefacts after --user=NAME.
# ---------------------------------------------------------------------------
@test "INST-07: AC4 no leftover 'agent' in install artefacts after --user=claude" {
  _install_alt_user
  local f
  for f in /etc/sudoers.d/agentlinux /etc/agentlinux.env /etc/profile.d/agentlinux.sh \
    /etc/cron.d/agentlinux "/home/${ALT_USER}/.npmrc"; do
    [[ -f "$f" ]] || __fail "INST-07" "artefact ${f} present" "missing" "$LOG"
    # Case-sensitive: the word `agent` (bare) and /home/agent must NOT appear as
    # install wiring. `AgentLinux` / `AGENTLINUX_*` (capitalized) and `agentlinux`
    # (no word boundary) are intentionally NOT matched by \bagent\b. The sudoers
    # header cites ADR `012-agent-user-full-sudo.md` — an immutable documentation
    # reference, not a hardcoded install user — so that one line is whitelisted.
    local leftovers
    leftovers=$(grep -nE '\bagent\b|/home/agent' "$f" | grep -vF 'agent-user-full-sudo.md' || true)
    if [[ -n "$leftovers" ]]; then
      __fail "INST-07" "no leftover 'agent'/'home/agent' in ${f}" "$(printf '%s' "$leftovers" | head -3)" "$f"
    fi
  done
}

# ---------------------------------------------------------------------------
# AC3 — interactive install prompts and provisions under the typed name.
# Drive a real pty via tty-driver.py; feed the alt user at the "[agent]" prompt.
# ---------------------------------------------------------------------------
@test "INST-07: AC3 interactive prompt provisions under the typed name" {
  # The username prompt fires ONLY on a greenfield host (no /etc/agentlinux.env
  # and no pre-existing default `agent` user) — on a brownfield re-run the user
  # is already chosen and prompting would derail the REMEDIATE loop. Purge to
  # greenfield, then drive a TTY with no --user/env so main() fires
  # prompt::choose_install_user; feed the alt name. Greenfield needs no --yes
  # (fresh create, nothing to remediate).
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  run python3 "$TTY_DRIVER" "${ALT_USER}\n" -- bash "$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "INST-07" "interactive install exit 0" "status=${status}; output: ${output}" "$LOG"
  printf '%s' "$output" | grep -q 'Install AgentLinux under which user?' \
    || __fail "INST-07" "prompt rendered" "${output}" "$LOG"
  grep -Fxq "AGENTLINUX_USER=${ALT_USER}" /etc/agentlinux.env \
    || __fail "INST-07" "typed-name install wrote AGENTLINUX_USER=${ALT_USER}" "$(cat /etc/agentlinux.env)" /etc/agentlinux.env
}

# ---------------------------------------------------------------------------
# AC4 — catalog op DISPATCHES recipes as the configured user (closes the
# runner.ts dispatch-user gap). Install a test-dummy recipe as claude and assert
# the recipe ran AS claude (marker owned by claude), traversing dispatchRecipe.
# A regression to dispatcher("agent", …) would run as agent (marker owned by
# agent) or fail with `sudo: unknown user: agent` on an agent-less host.
# ---------------------------------------------------------------------------
@test "INST-07: AC4 catalog op dispatches recipes as the configured user (claude)" {
  _install_alt_user
  rm -f /tmp/agentlinux-test-dummy.marker
  run sudo -u "$ALT_USER" -H bash --login -c 'agentlinux install test-dummy --include-test'
  assert_exit_zero "INST-07"
  if printf '%s' "$output" | grep -q 'unknown user: agent'; then
    __fail "INST-07" "dispatch does not fail with 'unknown user: agent'" "${output}" "$LOG"
  fi
  [[ -f /tmp/agentlinux-test-dummy.marker ]] \
    || __fail "INST-07" "test-dummy recipe ran (marker written)" "marker missing" "$LOG"
  [[ "$(stat -c '%U' /tmp/agentlinux-test-dummy.marker)" == "$ALT_USER" ]] \
    || __fail "INST-07" "recipe dispatched AS ${ALT_USER}" "marker owned by $(stat -c '%U' /tmp/agentlinux-test-dummy.marker)" "$LOG"
}
