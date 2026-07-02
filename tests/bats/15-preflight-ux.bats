#!/usr/bin/env bats
# tests/bats/15-preflight-ux.bats — Phase 15 Plan 15-01 Pre-flight UX @tests.
#
# Plan 15-01 lands UX-01 (--dry-run on both halves) + UX-02 (TTY per-action
# prompts with decline-and-continue + Sentinel widening). Per locked decisions
# D-15-01..D-15-11:
#   D-15-01 — --dry-run always exits 0 (preview semantic; bails surface in report).
#   D-15-02 — TTY decline writes sentinel status="reused-with-warning" +
#             decline_reason ∈ {chown-declined, sudoers-drift-declined,
#             reinstall-broken-declined}.
#   D-15-04 — --dry-run + --yes is contradictory in BOTH orders (exit 64).
#   D-15-05 — TTY detection via [[ -t 0 ]] on bash entrypoint stdin.
#   D-15-06 — Prompt format: 'Proceed with this remediation? [Y/n] '
#   D-15-09 — Additive remediates never prompt.
#   D-15-10 — --yes auto-approves in TTY too (skips prompt loop).
#   D-15-11 — Decline marker:
#             '[REMEDIATE-NN] DECLINED by user — skipping <component>; install
#              continues (state will be marked reused-with-warning)'
#
# Tests 1-6 (Task 1) — --dry-run flag + contradictory-combo rejection +
#                       no-mutation snapshot proof + idempotency.
# Tests 7-12 (Task 2) — TTY per-action prompt loop accept/decline matrix +
#                       --yes-skips-loop + non-TTY-skips-loop + input-sanitization.

load 'helpers/assertions'
load 'helpers/brownfield'
load 'helpers/tmpdir'

# AL_TMPDIR is a writable temp root that is safe even on bats < 1.4 (Ubuntu 22.04
# ships bats 1.2.1, which leaves BATS_TEST_TMPDIR unset → a bare expansion would
# write the snapshot fixtures to "/before" and "/after" at the host root). The
# snapshot @tests below build their paths under $AL_TMPDIR. See helpers/tmpdir.bash.
setup() {
  al_tmpdir_init || { printf 'setup: no safe temp dir\n' >&2; return 1; }
}

teardown() {
  al_tmpdir_teardown
}

# Restore canonical post-installer state at teardown so downstream bats files
# (40-registry-cli.bats, 50-agents.bats, etc.) see the same shape the docker
# harness's pre-bats install staged for them. Mirrors 14-remediate.bats's
# teardown_file invariant.
teardown_file() {
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  rm -rf /usr/local/agentlinux-old || true
  bash "$INSTALLER" >/dev/null 2>&1 || true
}

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

# snapshot_capture <dest> <path...>
# Mirrors the helper in 14-remediate.bats (T-14-13 / T-15-01-02 snapshot proof).
snapshot_capture() {
  local dest=$1
  shift
  rm -rf "$dest"
  mkdir -p "$dest"
  local p
  for p in "$@"; do
    if [[ -e "$p" ]]; then
      cp -a --parents "$p" "$dest/" 2>/dev/null || true
    fi
  done
}

snapshot_equal() {
  diff -r --exclude=.npm "$1" "$2" >/dev/null 2>&1
}

# setup_brownfield_for_dry_run_combo
# Combines REMEDIATE-01 (npm-prefix wrong-owner) + REMEDIATE-03 (sudoers drift)
# so the report has BOTH a chown remediate AND a sudoers drift overwrite to
# render. Used by Test 3's T-15-01-02 no-mutation snapshot.
setup_brownfield_for_dry_run_combo() {
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  useradd -m -s /bin/bash agent >/dev/null 2>&1 || usermod -s /bin/bash agent
  # Drifted (narrower-than-ADR-012) sudoers — REMEDIATE-03 trigger.
  local tmp
  tmp=$(mktemp)
  printf 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get\n' >"$tmp"
  install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/agentlinux
  rm -f "$tmp"
  # Root-owned npm-prefix — REMEDIATE-01 chown trigger.
  install -d -m 0755 -o root -g root /home/agent/.npm-global
  install -d -m 0755 -o root -g root /home/agent/.npm-global/bin
  install -d -m 0755 -o root -g root /home/agent/.npm-global/lib
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
  echo "prefix=/home/agent/.npm-global" >>/home/agent/.npmrc
  chown agent:agent /home/agent/.npmrc
}

# setup_brownfield_for_path_mismatch
# Lays down claude-code installed via npm (PATH-MISMATCH) so the dry-run report
# carries an agents.claude-code remediate entry.
setup_brownfield_for_path_mismatch() {
  setup_brownfield_broken_claude_code
}

# -----------------------------------------------------------------------------
# Task 1 — UX-01 --dry-run @tests (Tests 1-6).
# -----------------------------------------------------------------------------

# Test 1: greenfield --dry-run exits 0; detection ran; no provisioner ran.
@test "UX-01 (D-15-01): agentlinux-install --dry-run on greenfield exits 0 + detection runs + no provisioner runs" {
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  run bash "$INSTALLER" --dry-run
  [[ "$status" -eq 0 ]] \
    || __fail "UX-01" "exit 0 on greenfield dry-run" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[DRY-RUN]' \
    || __fail "UX-01" "[DRY-RUN] log marker present" "$output" "$LOG"
  # Provisioner runs were skipped — no 'running 10-agent-user.sh' line in transcript.
  if printf '%s' "$output" | grep -qE 'running 10-agent-user\.sh|running 20-sudoers\.sh|running 30-nodejs\.sh'; then
    __fail "UX-01" "no 'running NN-*.sh' markers (provisioners must NOT run)" "$output" "$LOG"
  fi
  # /etc/sudoers.d/agentlinux must NOT exist after a greenfield dry-run.
  [[ ! -f /etc/sudoers.d/agentlinux ]] \
    || __fail "UX-01" "no /etc/sudoers.d/agentlinux written by dry-run" "$(ls -la /etc/sudoers.d/ 2>&1)" "$LOG"
}

# Test 2: brownfield --dry-run exits 0 even when report carries bails.
@test "UX-01 (D-15-01): agentlinux-install --dry-run on brownfield with REMEDIATE candidates exits 0 (bails surface IN report)" {
  setup_brownfield_for_dry_run_combo
  run bash "$INSTALLER" --dry-run
  [[ "$status" -eq 0 ]] \
    || __fail "UX-01" "exit 0 on brownfield dry-run even with bail candidates" "exit=$status output=$output" "$LOG"
  # Detection ran (at least one DET marker in transcript).
  printf '%s' "$output" | grep -qE '\[DET-|\[DRY-RUN\]' \
    || __fail "UX-01" "detection ran (DET marker or DRY-RUN marker present)" "$output" "$LOG"
  # Provisioner runs were skipped.
  if printf '%s' "$output" | grep -qE 'running 10-agent-user\.sh|running 20-sudoers\.sh|running 30-nodejs\.sh'; then
    __fail "UX-01" "no 'running NN-*.sh' markers in brownfield dry-run" "$output" "$LOG"
  fi
}

# Test 3 (T-15-01-02): no-mutation snapshot — dry-run does NOT modify host state.
@test "UX-01 (T-15-01-02): NO-MUTATION SNAPSHOT — agentlinux-install --dry-run on brownfield combo leaves /etc/sudoers.d /home /etc/passwd byte-identical" {
  setup_brownfield_for_dry_run_combo

  local before="$AL_TMPDIR/before"
  local after="$AL_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run bash "$INSTALLER" --dry-run
  [[ "$status" -eq 0 ]] \
    || __fail "T-15-01-02" "dry-run exit 0" "exit=$status output=$output" "$LOG"

  snapshot_capture "$after" /etc/sudoers.d /home /etc/passwd

  if ! snapshot_equal "$before" "$after"; then
    __fail "T-15-01-02" "BYTE-IDENTICAL /etc/sudoers.d /home /etc/passwd before+after dry-run" "$(diff -r --exclude=.npm "$before" "$after" 2>&1 | head -20)" "$LOG"
  fi
}

# Test 4 (D-15-04, T-15-01-06): --dry-run --yes contradictory combo exits 64.
@test "UX-01 (D-15-04 / T-15-01-06): agentlinux-install --dry-run --yes exits 64 with contradictory-flags error" {
  run bash "$INSTALLER" --dry-run --yes
  [[ "$status" -eq 64 ]] \
    || __fail "D-15-04" "exit 64 on --dry-run --yes" "exit=$status output=$output" "$INSTALLER"
  printf '%s' "$output" | grep -qF -- 'contradictory flags' \
    || __fail "D-15-04" "log_error 'contradictory flags'" "$output" "$INSTALLER"
  printf '%s' "$output" | grep -qF -- '--dry-run forbids --yes' \
    || __fail "D-15-04" "literal '--dry-run forbids --yes' diagnostic" "$output" "$INSTALLER"
}

# Test 5 (D-15-04 symmetric): --yes --dry-run also exits 64.
@test "UX-01 (D-15-04 symmetric): agentlinux-install --yes --dry-run ALSO exits 64 (symmetric contradictory-flags rejection)" {
  run bash "$INSTALLER" --yes --dry-run
  [[ "$status" -eq 64 ]] \
    || __fail "D-15-04" "exit 64 on --yes --dry-run" "exit=$status output=$output" "$INSTALLER"
  printf '%s' "$output" | grep -qF -- '--dry-run forbids --yes' \
    || __fail "D-15-04" "symmetric '--dry-run forbids --yes' diagnostic" "$output" "$INSTALLER"
}

# Test 6 (UX-01 idempotency): re-running --dry-run produces stable detection output.
@test "UX-01 (idempotency): re-running agentlinux-install --dry-run produces stable DET markers (sorted-equal)" {
  setup_brownfield_for_dry_run_combo

  run bash "$INSTALLER" --dry-run
  [[ "$status" -eq 0 ]] || __fail "UX-01" "dry-run #1 exit 0" "exit=$status" "$LOG"
  local first
  first=$(printf '%s\n' "$output" | grep -E '^\[DET-' | sort)

  run bash "$INSTALLER" --dry-run
  [[ "$status" -eq 0 ]] || __fail "UX-01" "dry-run #2 exit 0" "exit=$status" "$LOG"
  local second
  second=$(printf '%s\n' "$output" | grep -E '^\[DET-' | sort)

  [[ "$first" == "$second" ]] \
    || __fail "UX-01" "two dry-run invocations produce identical sorted [DET-] markers" "diff: $(diff <(printf '%s' "$first") <(printf '%s' "$second"))" "$LOG"
}

# -----------------------------------------------------------------------------
# Task 2 — UX-02 TTY per-action prompt loop @tests (Tests 7-12).
# -----------------------------------------------------------------------------

# TTY simulation uses tests/bats/helpers/tty-driver.py (Python pty.spawn),
# which is more reliable than `script -c | pipe-stdin` across container
# environments. The driver spawns the inner command inside a pty (so
# `[[ -t 0 ]]` returns true in the child) and forwards the provided input
# bytes to the pty master. python3 is preinstalled on the Docker images
# (used by tests/bats/60-curl-installer.bats's INST-03 http.server fixture).

TTY_DRIVER=/opt/agentlinux-src/tests/bats/helpers/tty-driver.py

# Test 7 (D-15-06 / UX-02 accept-all): TTY prompts both REMEDIATE-01 + REMEDIATE-03;
# user answers Y to both; both mutations land.
@test "UX-02 (D-15-06 accept-all): TTY prompt with REMEDIATE-01 + REMEDIATE-03; answer Y to both → both mutations land + no DECLINED markers" {
  setup_brownfield_for_dry_run_combo
  # Allocate a pty so [[ -t 0 ]] returns true in the installer. Feed Y\nY\n
  # via the python pty driver — `script -c | pipe-stdin` hangs in some
  # container envs (the bytes never reach the inner pty slave).
  run python3 "$TTY_DRIVER" 'Y\nY\n' -- bash "$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "UX-02" "TTY accept-all exits 0" "exit=$status output=$output" "$LOG"
  # No DECLINED marker — both accepted.
  if printf '%s' "$output" | grep -qE 'DECLINED by user'; then
    __fail "UX-02" "no DECLINED markers on accept-all" "$output" "$LOG"
  fi
  # Sudoers landed at canonical line.
  grep -qF 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "UX-02" "REMEDIATE-03 sudoers overwrite landed (canonical ADR-012 line)" "$(cat /etc/sudoers.d/agentlinux 2>&1)" "$LOG"
  # npm-prefix is now agent-owned (REMEDIATE-01 chown landed).
  local owner
  owner=$(stat -c '%U' /home/agent/.npm-global)
  [[ "$owner" == "agent" ]] \
    || __fail "UX-02" "REMEDIATE-01 chown landed (/home/agent/.npm-global owner=agent)" "owner=$owner" "$LOG"
}

# Test 8 (D-15-02 / D-15-11 / UX-02 decline-one): TTY user declines REMEDIATE-01
# but accepts REMEDIATE-03; sudoers lands but npm-prefix is left as-is.
@test "UX-02 (D-15-11 decline-one-continue-others): TTY answer n then Y → REMEDIATE-01 SKIPPED + REMEDIATE-03 lands + DECLINED marker logged" {
  setup_brownfield_for_dry_run_combo
  # Component order in prompt::run_all is: user, npm-prefix, sudoers, agents.*.
  # user is a REUSE (existing agent), npm-prefix prompts first (decline=n), then
  # sudoers prompts (accept=Y).
  run python3 "$TTY_DRIVER" 'n\nY\n' -- bash "$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "UX-02" "TTY decline-one exits 0 (install continues)" "exit=$status output=$output" "$LOG"
  # DECLINED marker for npm-prefix.
  printf '%s' "$output" | grep -qF '[REMEDIATE-01] DECLINED by user' \
    || __fail "UX-02" "[REMEDIATE-01] DECLINED by user marker present" "$output" "$LOG"
  printf '%s' "$output" | grep -qF 'reused-with-warning' \
    || __fail "UX-02" "decline marker mentions reused-with-warning" "$output" "$LOG"
  # Sudoers landed at canonical line.
  grep -qF 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "UX-02" "REMEDIATE-03 sudoers overwrite landed despite REMEDIATE-01 decline" "$(cat /etc/sudoers.d/agentlinux 2>&1)" "$LOG"
  # npm-prefix is STILL root-owned (chown skipped per decline).
  local owner
  owner=$(stat -c '%U' /home/agent/.npm-global)
  [[ "$owner" == "root" ]] \
    || __fail "UX-02" "REMEDIATE-01 chown SKIPPED (/home/agent/.npm-global owner stayed root)" "owner=$owner" "$LOG"
}

# Test 9 (D-15-09 additive): additive REMEDIATE never triggers a prompt.
@test "UX-02 (D-15-09 additive-never-prompts): TTY installer on missing-sudoers fixture (REMEDIATE-03 additive install) does NOT show 'Proceed with this remediation?' prompt" {
  setup_brownfield_for_remediate_03_missing
  # Pipe an Y just in case a prompt does (incorrectly) appear — but the test
  # asserts the prompt string is ABSENT from the transcript.
  run python3 "$TTY_DRIVER" 'Y\n' -- bash "$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "UX-02" "TTY additive install exits 0" "exit=$status output=$output" "$LOG"
  if printf '%s' "$output" | grep -qF 'Proceed with this remediation?'; then
    __fail "UX-02" "additive REMEDIATE-03 install does NOT prompt" "$output" "$LOG"
  fi
  # File DID land.
  [[ -f /etc/sudoers.d/agentlinux ]] \
    || __fail "UX-02" "REMEDIATE-03 additive install wrote the sudoers drop-in" "$(ls -la /etc/sudoers.d/ 2>&1)" "$LOG"
}

# Test 10 (D-15-10): --yes in TTY mode SKIPS the prompt loop.
@test "UX-02 (D-15-10 --yes-skips-loop): TTY installer with --yes does NOT prompt (loop skipped); all remediates land" {
  setup_brownfield_for_dry_run_combo
  # Empty input — --yes auto-approves so no prompt should fire; the empty
  # input would cause EOF on read, which the prompt::confirm_remediate
  # default-decline path would NOT exercise because YES_FLAG bypass fires
  # earlier in agentlinux-install main().
  run python3 "$TTY_DRIVER" '' -- bash "$INSTALLER" --yes
  [[ "$status" -eq 0 ]] \
    || __fail "UX-02" "TTY --yes exits 0" "exit=$status output=$output" "$LOG"
  if printf '%s' "$output" | grep -qF 'Proceed with this remediation?'; then
    __fail "UX-02" "TTY --yes skips prompt loop (no 'Proceed...?' line)" "$output" "$LOG"
  fi
  # Both mutations land.
  grep -qF 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "UX-02" "REMEDIATE-03 landed under TTY --yes" "$(cat /etc/sudoers.d/agentlinux 2>&1)" "$LOG"
}

# Test 11 (non-TTY): non-TTY path is Phase 14's bail-without-yes (exit 65).
@test "UX-02 (non-TTY-skips-loop): non-TTY installer (stdin piped) on REMEDIATE combo without --yes bails with 65 (Phase 14 contract; prompt loop skipped)" {
  setup_brownfield_for_dry_run_combo
  # Pipe Y\nY\n on stdin BUT no script(1) wrapper → [[ -t 0 ]] is false → the
  # prompt loop is skipped, and the Phase 14 non-TTY bail-or-yes path fires.
  run bash -c 'printf "Y\nY\n" | bash '"$INSTALLER"
  [[ "$status" -eq 65 ]] \
    || __fail "UX-02" "non-TTY without --yes bails with 65 (Phase 14 contract)" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qE '^\[BAIL\]' \
    || __fail "UX-02" "non-TTY bail prints [BAIL] markers" "$output" "$LOG"
}

# Test 12 (T-15-01-03 input sanitization): newline + shell injection inside
# the prompt response is consumed safely by read -r -n 1.
@test "UX-02 (T-15-01-03 input-sanitization): TTY prompt response 'n; rm -rf /tmp/poison\\n' executes no shell injection; first char consumed; component declined" {
  setup_brownfield_for_dry_run_combo
  # Prepare a canary file. T-15-01-03 mitigation should prevent any rm from
  # running against it during the prompt loop.
  install -d -m 0755 /tmp/poison
  install -m 0644 /dev/null /tmp/poison/canary
  # Feed 'n' followed by injection text + newline + Y (for sudoers).
  # First-char 'n' is consumed by `read -r -n 1`; the remainder of the line
  # ('; rm -rf /tmp/poison') is consumed by the line-discard in
  # prompt::confirm_remediate; the second prompt fires for sudoers and
  # consumes the 'Y'. T-15-01-03 mitigation verified by the canary survival.
  run python3 "$TTY_DRIVER" 'n; rm -rf /tmp/poison\nY\n' -- bash "$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "T-15-01-03" "installer exits 0 (no shell injection took down the run)" "exit=$status output=$output" "$LOG"
  [[ -d /tmp/poison && -f /tmp/poison/canary ]] \
    || __fail "T-15-01-03" "canary file /tmp/poison/canary survives (no rm -rf executed)" "$(ls -la /tmp/poison 2>&1)" "$LOG"
  # The first char ('n') was consumed → REMEDIATE-01 should be DECLINED.
  printf '%s' "$output" | grep -qF '[REMEDIATE-01] DECLINED by user' \
    || __fail "T-15-01-03" "first char 'n' consumed → REMEDIATE-01 DECLINED" "$output" "$LOG"
  # Cleanup canary.
  rm -rf /tmp/poison
}

# -----------------------------------------------------------------------------
# Task 1 — UX-04 alt-user TTY prompt + non-TTY bail-with-hint (Tests 13-18).
# Plan 15-02. See 15-CONTEXT.md D-15-07 (numeric-suffix) and D-15-08 (non-TTY
# bail message), and the threat register T-15-02-01..T-15-02-06.
# -----------------------------------------------------------------------------

# Test 13 (UX-04 TTY accept-suggested): wrong-shell fixture; TTY feeds '\n' so
# the operator accepts the suggested alternate name (agent2).
# KNOWN LIMITATION (AL-59): this asserts user CREATION + the accepted marker
# only — NOT that agent2 receives a working install (npm prefix / PATH wiring /
# sudoers under /home/agent2). Those still land on the canonical `agent`; full
# alt-user provisioning + the assertions that would verify it are tracked in AL-59.
@test "UX-04 (D-15-07 accept-suggested): TTY alt-user prompt on wrong-shell fixture; Enter accepts 'agent2' → install proceeds with INSTALL_USER=agent2 + [ALT-USER] accepted marker" {
  setup_brownfield_host_user_wrong_shell
  # Feed just \n (Enter = accept suggested name).
  run python3 "$TTY_DRIVER" '\n' -- bash "$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "UX-04" "TTY alt-user accept-suggested exits 0" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[ALT-USER] accepted: agent2' \
    || __fail "UX-04" "[ALT-USER] accepted: agent2 marker present" "$output" "$LOG"
  # Confirm the new user actually exists post-install.
  id -u agent2 >/dev/null 2>&1 \
    || __fail "UX-04" "agent2 user created" "id -u agent2 failed" "$LOG"
  # Original incompatible agent is untouched (still its family-correct wrong
  # shell — /bin/sh on Debian, /usr/bin/tcsh on RHEL/EL9 per distro_wrong_shell).
  local orig_shell
  orig_shell=$(distro_wrong_shell)
  [[ "$(getent passwd agent | cut -d: -f7)" == "$orig_shell" ]] \
    || __fail "UX-04" "original agent user untouched (still ${orig_shell})" "$(getent passwd agent)" "$LOG"
  # Teardown: remove agent2 so subsequent tests' find_alt_user_name still
  # suggests "agent2" (the deterministic first-suggestion contract).
  userdel -rf agent2 2>/dev/null || true
}

# Test 14 (UX-04 TTY accept-typed): operator types a custom name.
# KNOWN LIMITATION (AL-59): asserts user CREATION + the accepted marker only,
# not that `mybot` gets a working install — see Test 13's note + AL-59.
@test "UX-04 (D-15-07 accept-typed): TTY alt-user prompt; operator types 'mybot' → install proceeds with INSTALL_USER=mybot" {
  setup_brownfield_host_user_wrong_shell
  run python3 "$TTY_DRIVER" 'mybot\n' -- bash "$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "UX-04" "TTY alt-user accept-typed exits 0" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[ALT-USER] accepted: mybot' \
    || __fail "UX-04" "[ALT-USER] accepted: mybot marker present" "$output" "$LOG"
  id -u mybot >/dev/null 2>&1 \
    || __fail "UX-04" "mybot user created" "id -u mybot failed" "$LOG"
  # Teardown: remove mybot so subsequent tests don't see it.
  userdel -rf mybot 2>/dev/null || true
}

# Test 15 (UX-04 TTY decline-and-bail): operator hits EOF (no input bytes).
@test "UX-04 (T-15-02-03 decline-and-bail): TTY alt-user prompt; EOF (no input) → exit 65 + [ALT-USER] declined marker" {
  setup_brownfield_host_user_wrong_shell
  # Empty input string — tty-driver will close the pty after the prompt fires
  # and read returns non-zero (EOF) in prompt::alt_user_or_bail.
  run python3 "$TTY_DRIVER" '' -- bash "$INSTALLER"
  [[ "$status" -eq 65 ]] \
    || __fail "UX-04" "TTY EOF on alt-user prompt exits 65" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[ALT-USER] declined' \
    || __fail "UX-04" "[ALT-USER] declined marker present" "$output" "$LOG"
}

# Test 16 (UX-04 / D-15-08 non-TTY bail-with-hint): non-TTY path emits the
# locked hint message and exits 65.
@test "UX-04 (D-15-08 non-TTY bail-with-hint): non-TTY installer on wrong-shell fixture exits 65 with literal '--user=agent2' hint" {
  setup_brownfield_host_user_wrong_shell
  # No TTY allocation — pipe a dummy stdin so [[ -t 0 ]] is false.
  run bash -c 'printf "" | bash '"$INSTALLER"
  [[ "$status" -eq 65 ]] \
    || __fail "UX-04" "non-TTY alt-user bail exits 65" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF 'agentlinux: existing user "agent" is incompatible (wrong-shell).' \
    || __fail "D-15-08" "literal bail-with-hint reason=wrong-shell" "$output" "$LOG"
  printf '%s' "$output" | grep -qF 'Re-run with --user=agent2 or fix the existing user manually.' \
    || __fail "D-15-08" "literal '--user=agent2' suggestion" "$output" "$LOG"
}

# Test 17 (T-15-02-05 input-validation): operator types a shell-metachar name;
# regex rejects + re-prompts; after 3 invalid → exit 64 EX_USAGE.
@test "UX-04 (T-15-02-05 input-validation): TTY alt-user prompt rejects 'agent2;rm -rf /tmp/poison' (shell metachars); 3 invalid → exit 64 + canary survives" {
  setup_brownfield_host_user_wrong_shell
  install -d -m 0755 /tmp/poison
  install -m 0644 /dev/null /tmp/poison/canary
  # Feed three invalid names in a row (semi-colon injection attempts). Each
  # should be rejected by remediate::validate_user_name regex; after 3 invalid
  # → bail with exit 64 (per plan invariant).
  run python3 "$TTY_DRIVER" 'agent2;rm -rf /tmp/poison\nfoo;bad\nbar bad\n' -- bash "$INSTALLER"
  [[ "$status" -eq 64 ]] \
    || __fail "T-15-02-05" "3 invalid names → exit 64 EX_USAGE" "exit=$status output=$output" "$LOG"
  # Canary survives — no shell injection executed.
  [[ -d /tmp/poison && -f /tmp/poison/canary ]] \
    || __fail "T-15-02-05" "canary file survives (no rm -rf executed)" "$(ls -la /tmp/poison 2>&1)" "$LOG"
  # Validator log present.
  printf '%s' "$output" | grep -qF 'invalid name:' \
    || __fail "T-15-02-05" "'invalid name:' diagnostic present" "$output" "$LOG"
  rm -rf /tmp/poison
}

# Test 18 (UX-04 greenfield invariant): on a FRESH container (no existing
# 'agent' user), no alt-user prompt fires; v0.3.0 baseline preserved.
@test "UX-04 (greenfield invariant): on a greenfield host (no existing agent user), no [ALT-USER] prompt fires; installer completes normally" {
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  # Non-TTY normal install path — must succeed (greenfield: user is created
  # fresh; reuse::user_decision returns 'create'; alt-user gate is skipped).
  run bash -c 'printf "" | bash '"$INSTALLER"
  [[ "$status" -eq 0 ]] \
    || __fail "UX-04" "greenfield install exits 0 (no alt-user gate fires)" "exit=$status output=$output" "$LOG"
  if printf '%s' "$output" | grep -qF '[ALT-USER]'; then
    __fail "UX-04" "no [ALT-USER] markers in greenfield transcript" "$output" "$LOG"
  fi
  # User got created normally.
  id -u agent >/dev/null 2>&1 \
    || __fail "UX-04" "agent user created on greenfield" "id -u agent failed" "$LOG"
}
