#!/usr/bin/env bats
# tests/bats/68-catalog-hermes-agent.bats — v0.3.6 Phase 48 (hermes-agent) the second
# AI-assistant daemon, reusing the ENABLE-04 lifecycle helper: ASST-02 (Hermes Agent
# installs via its OFFICIAL installer pinned to an immutable commit — no root, no
# /usr/local shim, zero EACCES — version-locks, and runs its Gateway) + an OPS-01
# real-operation smoke (`hermes doctor` actually exercises the installed venv/config,
# credential-free) + CAT-04 (the user's ~/.hermes data/secrets survive a remove; only the
# code checkout + launcher are stripped).
#
# THE DOCKER-vs-REAL SPLIT (see plugin/catalog/lib/daemon-lifecycle.sh): the Gateway is a
# systemd --user service, which the CI container cannot run (masked logind). So @test 1
# verifies the Docker-testable path (install → real-op → surgical CAT-04 remove) and @test
# 2 self-gates with `skip` and runs the systemd Gateway lifecycle under QEMU (ADR-007).
#
# NOTE: the install clones a repo and builds a Python venv + Node deps, so this @test's
# install step is minutes-long (by design — it is a real end-to-end install).
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - the version pin is read from the provisioned catalog via jq — NEVER hardcoded
#   - installs run as the agent user through a login shell (PATH + ~/.local/bin)
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)
#
# Refs:
#   - tests/bats/67-catalog-openclaw.bats (daemon lifecycle driver shape; ENABLE-04 helper)
#   - plugin/catalog/agents/hermes-agent/{install,uninstall}.sh
#   - .planning/REQUIREMENTS.md (ASST-02, ENABLE-04, OPS-01 + Appendix C: no cred)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

# Absolute agent-owned paths (hermes installs the launcher under ~/.local/bin and the code
# checkout + user data under ~/.hermes).
HERMES_BIN=/home/agent/.local/bin/hermes
HERMES_CODE=/home/agent/.hermes/hermes-agent
HERMES_ENV=/home/agent/.hermes/.env
DAEMON_MARKER=/home/agent/.local/share/agentlinux/hermes-agent.daemon

_scrub_hermes() {
  sudo -u agent -H bash --login -c '
    command -v hermes >/dev/null 2>&1 && hermes gateway stop </dev/null >/dev/null 2>&1 || true
    rm -rf /home/agent/.hermes
    rm -f  /home/agent/.local/bin/hermes
    rm -f  /home/agent/.local/share/agentlinux/hermes-agent.daemon /home/agent/.local/share/agentlinux/linger.managed
    # Revert any AgentLinux-enabled linger so @test 2 (QEMU) starts from a pristine host and
    # its linger-revert assertion is meaningful on a reused guest.
    sudo loginctl disable-linger agent >/dev/null 2>&1 || true
  ' >/dev/null 2>&1 || true
}

_user_systemd_up() {
  sudo -u agent -H bash --login -c \
    'export XDG_RUNTIME_DIR="/run/user/$(id -u)"; systemctl --user show-environment >/dev/null 2>&1'
}

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  _scrub_hermes
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force hermes-agent' >/dev/null 2>&1 || true
  fi
  _scrub_hermes
}

_hermes_pin() {
  local req=$1 pinned
  pinned=$(jq -r '.agents[] | select(.id=="hermes-agent") | .pinned_version' "$CATALOG")
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "$req" "non-empty pinned_version from catalog" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"
  fi
  printf '%s' "$pinned"
}

@test "ASST-02: hermes-agent installs via its pinned official installer (no root/shim/EACCES), runs a real op, and removes symmetrically — ~/.hermes user data preserved (CAT-04)" {
  local pinned
  pinned=$(_hermes_pin "ASST-02") || return 1

  # --- install: official installer, pinned to an immutable commit, non-interactive ---
  run sudo -u agent -H bash --login -c 'agentlinux install hermes-agent'
  assert_exit_zero "ASST-02 (install)"
  assert_no_eacces "ASST-02 (install)" "$output"

  # hermes resolves under the agent-owned ~/.local/bin — never a /usr/local shim.
  run sudo -u agent -H bash --login -c 'command -v hermes'
  assert_exit_zero "ASST-02 (resolve)"
  case "${output}" in
    "$HERMES_BIN") : ;;
    *) __fail "ASST-02" "hermes resolves at ${HERMES_BIN} (agent-owned, no /usr/local shim)" "${output:-<empty>}" "$LOG" ;;
  esac
  run sudo -u agent -H bash --login -c 'test -e /usr/local/bin/hermes'
  [[ "${status}" -ne 0 ]] \
    || __fail "ASST-02" "no /usr/local/bin/hermes shim (anti-pattern avoided)" "shim exists" "$LOG"

  # ASST-02 version-lock: hermes --version carries the catalog pin (jq-derived).
  run sudo -u agent -H bash --login -c 'hermes --version'
  assert_exit_zero "ASST-02 (version)"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "ASST-02" "hermes --version contains pinned ${pinned}" "${output:-<empty>}" "$LOG"
  fi

  # OPS-01 real operation (assistant category, credential-free per Appendix C): `hermes
  # doctor` runs the installed Python venv and checks config + dependencies — a genuine
  # operation, not just a file/version probe. Assert exit 0 AND that it produced a real
  # diagnostic (non-empty, no EACCES) so a stub that silently `exit 0`s cannot pass.
  run sudo -u agent -H bash --login -c 'hermes doctor </dev/null'
  assert_exit_zero "OPS-01 (hermes doctor real op)"
  assert_no_eacces "OPS-01 (hermes doctor)" "$output"
  [[ -n "${output// /}" ]] \
    || __fail "OPS-01" "hermes doctor emits a real diagnostic (non-empty)" "empty output" "$LOG"

  # CAT-04 durability: seed a test-controlled sentinel under ~/.hermes (alongside the code
  # checkout) BEFORE remove, so the preserve assertion proves the recipe keeps USER data
  # regardless of what the installer itself wrote — not coupled to an installer side-effect.
  run sudo -u agent -H bash --login -c 'printf CAT04-SENTINEL > /home/agent/.hermes/al-sentinel.txt'
  assert_exit_zero "CAT-04 (seed sentinel)"

  # --- symmetric remove: launcher + code checkout gone, ~/.hermes user data preserved ---
  run sudo -u agent -H bash --login -c 'agentlinux remove --force hermes-agent'
  assert_exit_zero "ASST-02 (remove)"
  assert_no_eacces "ASST-02 (remove)" "$output"

  run sudo -u agent -H bash --login -c 'test -e '"$HERMES_BIN"
  [[ "${status}" -ne 0 ]] \
    || __fail "ASST-02" "hermes launcher removed from the agent prefix" "${HERMES_BIN} still exists" "$LOG"
  run sudo -u agent -H bash --login -c 'test -e '"$HERMES_CODE"
  [[ "${status}" -ne 0 ]] \
    || __fail "ASST-02" "code checkout removed on uninstall" "${HERMES_CODE} still exists" "$LOG"

  # CAT-04 (durable proof): the test-controlled sentinel MUST survive with its exact content
  # — remove keeps user data, stripping only the code checkout + launcher.
  run sudo -u agent -H bash --login -c 'cat /home/agent/.hermes/al-sentinel.txt 2>/dev/null'
  if [[ "${output}" != "CAT04-SENTINEL" ]]; then
    __fail "ASST-02" "test-controlled sentinel under ~/.hermes preserved on remove (CAT-04)" "${output:-<gone>}" "$LOG"
  fi
  # And the installer-written user data survives too (corroborating).
  run sudo -u agent -H bash --login -c 'test -f '"$HERMES_ENV"
  [[ "${status}" -eq 0 ]] \
    || __fail "ASST-02" "user data ${HERMES_ENV} preserved on remove (CAT-04)" "was deleted by remove" "$LOG"

  run sudo -u agent -H bash --login -c 'test -e '"$DAEMON_MARKER"
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-04" "daemon marker removed on uninstall" "${DAEMON_MARKER} still exists" "$LOG"

  # Idempotent re-remove (uninstall.sh guards every step / best-effort).
  run sudo -u agent -H bash --login -c 'agentlinux remove --force hermes-agent'
  assert_exit_zero "ASST-02 (idempotent remove)"
}

@test "ENABLE-04 (QEMU-gated): hermes-agent brings up a per-user systemd Gateway daemon; remove tears it down + reverts AgentLinux-enabled linger" {
  _user_systemd_up || skip "per-user systemd bus unavailable (Docker masks logind) — QEMU release-gate behavior (ADR-007)"

  run sudo -u agent -H bash --login -c 'agentlinux install hermes-agent'
  assert_exit_zero "ENABLE-04 (systemd install)"
  assert_no_eacces "ENABLE-04 (systemd install)" "$output"

  # The managed Gateway service is installed + reports via `hermes gateway status`.
  run sudo -u agent -H bash --login -c \
    'export XDG_RUNTIME_DIR="/run/user/$(id -u)"; hermes gateway status </dev/null'
  assert_exit_zero "ENABLE-04 (gateway status)"

  # AgentLinux enabled linger and recorded ownership.
  run sudo -u agent -H bash --login -c 'loginctl show-user "$(id -un)" -p Linger'
  if ! printf '%s' "${output}" | grep -q 'Linger=yes'; then
    __fail "ENABLE-04" "linger enabled for the agent user (daemon persists across logout)" "${output:-<empty>}" "$LOG"
  fi
  run sudo -u agent -H bash --login -c 'test -f '"$DAEMON_MARKER"
  [[ "${status}" -eq 0 ]] \
    || __fail "ENABLE-04" "daemon marker dropped on systemd install" "marker absent at ${DAEMON_MARKER}" "$LOG"

  # --- remove tears down the unit + reverts linger (AgentLinux enabled it, none remain) ---
  run sudo -u agent -H bash --login -c 'agentlinux remove --force hermes-agent'
  assert_exit_zero "ENABLE-04 (systemd remove)"
  run sudo -u agent -H bash --login -c 'test -e '"$DAEMON_MARKER"
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-04" "daemon marker removed on uninstall" "${DAEMON_MARKER} still exists" "$LOG"
}

@test "ASST-02: the hermes-agent recipe drives the official installer non-interactively (--skip-setup) so a real interactive install never hangs on the setup wizard" {
  # REGRESSION (dogfood v0.3.6-rc4): the upstream installer's monolithic main() path — the
  # path a plain `bash install.sh` takes — calls run_setup_wizard UNCONDITIONALLY. That
  # function is gated ONLY by RUN_SETUP (set false by --skip-setup) plus a `/dev/tty` probe;
  # it NEVER consults --non-interactive. Because `agentlinux install` runs from a user's
  # terminal, /dev/tty is openable, so WITHOUT --skip-setup the wizard launches and blocks
  # forever on `< /dev/tty`. CI never caught it because bats runs with no controlling tty
  # (the /dev/tty probe fails, wizard self-skips) — only a real interactive install hangs.
  # This offline contract guard asserts the load-bearing flag is present. It is verified
  # end-to-end under a real PTY in the phase QA campaign (see the QA report).
  local recipe=/opt/agentlinux-src/plugin/catalog/agents/hermes-agent/install.sh
  run grep -E 'bash .*install\.sh.*--skip-setup' "$recipe"
  assert_exit_zero "ASST-02 (recipe passes --skip-setup to the official installer)"
  # --non-interactive is still passed (defaults the installer's other prompts); assert both
  # travel together so a future edit can't drop the wizard gate while keeping the rest.
  run grep -E 'bash .*install\.sh.*--non-interactive.*--skip-setup|bash .*install\.sh.*--skip-setup.*--non-interactive' "$recipe"
  assert_exit_zero "ASST-02 (recipe keeps --non-interactive alongside --skip-setup)"
  # The stdin `</dev/null` defense-in-depth (against any stdin-based read, distinct from the
  # /dev/tty wizard) must stay too — guard it so a future editor can't drop it as "redundant".
  run grep -E 'bash .*install\.sh.*</dev/null' "$recipe"
  assert_exit_zero "ASST-02 (recipe redirects the installer's stdin from /dev/null)"
}

@test "ASST-02: the hermes-agent catalog entry is a script-kind, MIT, daemon assistant" {
  # Offline entry-shape assertion — the entry is the contract. Exact tuple guards drift.
  run bash -c "jq -r '.agents[] | select(.id==\"hermes-agent\") | \"\(.source_kind) \(.license) \(.pinned_version) \(.install_recipe_path) \(.uninstall_recipe_path) \(.requires_secret)\"' '$CATALOG'"
  assert_exit_zero "ASST-02 (entry shape)"
  if [[ "${output}" != "script MIT 2026.6.19 install.sh uninstall.sh true" ]]; then
    __fail "ASST-02" "hermes-agent entry = 'script MIT 2026.6.19 install.sh uninstall.sh true'" "${output:-<empty>}" "$LOG"
  fi

  # It carries the assistant + daemon category tags (ENABLE-06 list grouping, Phase 49).
  run bash -c "jq -r '.agents[] | select(.id==\"hermes-agent\") | .tags | index(\"assistant\") // empty' '$CATALOG'"
  if [[ -z "${output}" ]]; then
    __fail "ASST-02" "hermes-agent entry carries the 'assistant' category tag" "tags missing 'assistant'" "$LOG"
  fi
  run bash -c "jq -r '.agents[] | select(.id==\"hermes-agent\") | .tags | index(\"daemon\") // empty' '$CATALOG'"
  if [[ -z "${output}" ]]; then
    __fail "ASST-02" "hermes-agent entry carries the 'daemon' category tag" "tags missing 'daemon'" "$LOG"
  fi
}
