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

  local before="$BATS_TEST_TMPDIR/before"
  local after="$BATS_TEST_TMPDIR/after"
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
  printf '%s' "$output" | grep -qF 'contradictory flags' \
    || __fail "D-15-04" "log_error 'contradictory flags'" "$output" "$INSTALLER"
  printf '%s' "$output" | grep -qF '--dry-run forbids --yes' \
    || __fail "D-15-04" "literal '--dry-run forbids --yes' diagnostic" "$output" "$INSTALLER"
}

# Test 5 (D-15-04 symmetric): --yes --dry-run also exits 64.
@test "UX-01 (D-15-04 symmetric): agentlinux-install --yes --dry-run ALSO exits 64 (symmetric contradictory-flags rejection)" {
  run bash "$INSTALLER" --yes --dry-run
  [[ "$status" -eq 64 ]] \
    || __fail "D-15-04" "exit 64 on --yes --dry-run" "exit=$status output=$output" "$INSTALLER"
  printf '%s' "$output" | grep -qF '--dry-run forbids --yes' \
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

# script(1) is part of the bsdutils package on Ubuntu — preinstalled on the
# Docker test images. We use it to allocate a pty for the bash installer so
# `[[ -t 0 ]]` returns true and the prompt loop fires.

# Test 7 (D-15-06 / UX-02 accept-all): TTY prompts both REMEDIATE-01 + REMEDIATE-03;
# user answers Y to both; both mutations land.
@test "UX-02 (D-15-06 accept-all): TTY prompt with REMEDIATE-01 + REMEDIATE-03; answer Y to both → both mutations land + no DECLINED markers" {
  setup_brownfield_for_dry_run_combo
  # Allocate a pty so [[ -t 0 ]] returns true in the installer. Feed Y\nY\n on
  # the pty's stdin via printf piped through script's -c command.
  run bash -c 'printf "Y\nY\n" | script -q -e -c "bash '"$INSTALLER"'" /dev/null'
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
  run bash -c 'printf "n\nY\n" | script -q -e -c "bash '"$INSTALLER"'" /dev/null'
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
  run bash -c 'printf "Y\n" | script -q -e -c "bash '"$INSTALLER"'" /dev/null'
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
  run bash -c 'script -q -e -c "bash '"$INSTALLER"' --yes" /dev/null </dev/null'
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
  run bash -c 'printf "n; rm -rf /tmp/poison\nY\n" | script -q -e -c "bash '"$INSTALLER"'" /dev/null'
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
