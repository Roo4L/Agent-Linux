#!/usr/bin/env bats
# tests/bats/14-remediate.bats — Phase 14 Plan 14-01 remediate-foundation @tests.
#
# Plan 14-01 covers UX-03 (--yes consent flag + DECIDE-THEN-ACT atomicity) +
# UX-05 (structured exit codes 64/65/0/1 + --help "Exit codes:" section). Per
# CONTEXT.md Area 1 Q1-Q4 the locked contracts are:
#   - [BAIL] line format: `[BAIL] component=<n> reason=<r> hint=<h>`
#   - Exit code mapping: 64 EX_USAGE | 65 EX_DATAERR | 1 runtime | 0 success
#   - --help carries "Exit codes:" section listing 0/1/64/65 with mnemonics
#   - Consent surface: --yes ONLY (no AGENTLINUX_YES / ALWAYS_YES env var
#     equivalents — T-14-01 mitigation)
#
# The eleven Bash-library @tests this file opened with (sourcing remediate.sh,
# register_bail, flush_bails_or_continue, the per-component stubs) went away with
# the Bash provisioner at the Rust cutover. Their successors are Rust unit tests:
# `provision::remediate`'s gate/decide_sudoers/decide_npm_prefix tables and
# `flush_tests` (the [BAIL] aggregation + exit 65). What REMAINS here is what
# only a real host can show — the end-to-end brownfield remediation behaviour.
#
# Thirteen `# Test NN — …` headers were left behind above nothing when those
# tests were deleted. They have been removed rather than left as an index of
# coverage that does not exist; the most misleading read "visudo-fail gate
# UPHELD" above no code, while the behaviour it named — install_or_overwrite
# refusing to install when visudo -cf rejects the tmpfile, both the pre-install
# gate and the post-install re-verify — had no test anywhere. It now has one:
# `visudo_gates_the_install_before_the_file_is_ever_written` and
# `a_failed_post_install_verify_is_a_hard_error` in
# rust/crates/agentlinux/src/provision/sudoers.rs.

load 'helpers/assertions'
load 'helpers/detection'
load 'helpers/brownfield'
load 'helpers/tmpdir'

# AL_TMPDIR is a writable temp root that is safe even on bats < 1.4 (Ubuntu 22.04
# ships bats 1.2.1, which leaves BATS_TEST_TMPDIR unset → a bare expansion would
# write fixture state like "/home/.npm-global" and "/shims" into the real host
# root). The @tests below build all per-test paths under $AL_TMPDIR instead.
# See helpers/tmpdir.bash.
setup() {
  al_tmpdir_init || { printf 'setup: no safe temp dir\n' >&2; return 1; }
}

teardown() {
  al_tmpdir_teardown
}

# Plan 14-02 teardown_file invariant. The brownfield-running @tests in this
# file (REMEDIATE-01/02/03 E2E paths) call `bash $INSTALLER --purge` + manual
# fixture overlays, then `bash $INSTALLER --yes` to exercise the remediation
# paths. They can leave the host in a remediated-but-quirky state (e.g. a
# stale /usr/local/agentlinux-old/ residue from the rebase @tests, or a
# lodash polluting ~agent/.npm-global). Downstream bats files
# (40-registry-cli.bats, 50-agents.bats, 51-*.bats) depend on the SAME
# canonical post-installer state that tests/docker/run.sh sets up before
# bats fires — 40-registry-cli.bats's setup_file has no re-provision recovery
# (it trusts the docker harness's pre-bats install). Re-establish that
# canonical state here: --purge wipes our residue, then a clean greenfield
# `bash $INSTALLER` re-provisions everything (no remediations needed — purge
# is the cleanest possible baseline).
teardown_file() {
  "$INSTALLER" provision --purge >/dev/null 2>&1 || true
  # Best-effort residue cleanup of fixture artefacts --purge does not own.
  # The /usr/local/agentlinux-old/ tree is created by Tests 32-34 rebase
  # fixtures and lives outside --purge's scope.
  rm -rf /usr/local/agentlinux-old || true
  # Restore the canonical post-installer state so downstream bats files see
  # the host shape tests/docker/run.sh staged for them. The greenfield path
  # has no remediations, so no --yes flag needed.
  "$INSTALLER" provision >/dev/null 2>&1 || true
}

# LOG + INSTALLER are referenced by Task 2 @tests (full-installer runs); Task 1
# @tests use lib-source paths directly. shellcheck SC2034 suppression covers
# the Task-1-only file slice — the Task 2 add land introduces the actual uses.
# shellcheck disable=SC2034
LOG=/var/log/agentlinux-install.log
# shellcheck disable=SC2034
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux

# Helper: source the lib chain through reuse + remediate so @tests can call
# remediate::* / reuse::* directly. Mirrors the order plugin/bin/agentlinux-install
# uses: log.sh → distro_detect.sh → as_user.sh → idempotency.sh → detect.sh →
# reuse.sh → remediate.sh.

# Clear bail-aggregation state between @tests so register_bail / flush behavior
# tests are isolated. Bash arrays declared with `-g` persist across function
# calls in the same shell; @tests that mutate them must reset.

# ---- Task 1: remediate.sh orchestrator + per-component stubs -----------------












# ---- Task 2: --yes/--no-yes parsing + EX_USAGE/EX_DATAERR + DECIDE-THEN-ACT  ---

# Snapshot helpers (Task 2). Captures contents of targeted paths into a tarball-
# like cp -a tree under <dest> so subsequent `snapshot_equal` compares with
# `diff -r`. Used by the no-mutation @tests to byte-prove DECIDE-THEN-ACT
# atomicity.
snapshot_capture() {
  local dest=$1
  shift
  rm -rf "$dest"
  mkdir -p "$dest"
  local p
  for p in "$@"; do
    if [[ -e "$p" ]]; then
      # cp -a --parents preserves the full path under dest so /etc/passwd
      # lands at <dest>/etc/passwd; allows diff -r to compare like-for-like.
      cp -a --parents "$p" "$dest/" 2>/dev/null || true
    fi
  done
}

snapshot_equal() {
  # `--exclude=.npm` ignores npm's per-user cache dir, which `npm config get`
  # bootstraps on first invocation regardless of `npm_config_logs_max=0` and
  # `npm_config_loglevel=silent` (the cache dir itself, not log files, is
  # what npm creates lazily). This is npm's own ephemeral state — NOT user
  # data, NOT installer-managed config, NOT a UX-03 contract violation. The
  # T-14-13 atomicity claim is about /etc/sudoers.d, /etc/passwd, and user
  # state files; the bootstrap of an empty ~/.npm cache directory falls
  # outside the protected surface.
  diff -r --exclude=.npm "$1" "$2" >/dev/null 2>&1
}

# Brownfield-bail fixture helpers. Each fixture targets ONE bail class; all
# OTHER components remain REUSE-compatible so the @test asserts only the
# targeted bail surfaces (Warning #3 — fixture isolation invariant).

# setup_brownfield_for_bail_user_wrongshell
# Targets: REUSE-01 predicate 2 (wrong shell — irreconcilable). User exists
# with /bin/dash; otherwise REUSE-compatible (canonical sudoers via the
# post-installer host state already in place, Node 22 already installed,
# no broken catalog agents).
setup_brownfield_for_bail_user_wrongshell() {
  # Idempotent --purge to clear prior state.
  "$INSTALLER" provision --purge >/dev/null 2>&1 || true
  # Create agent with the WRONG shell. useradd -m creates ~agent.
  useradd -m -s /bin/dash agent >/dev/null 2>&1 || usermod -s /bin/dash agent
  # Install the canonical sudoers drop-in so the sudoers component is
  # REUSE-compatible (isolation invariant — only the user component bails).
  local tmp
  tmp=$(mktemp)
  printf 'agent ALL=(ALL) NOPASSWD: ALL\n' >"$tmp"
  install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/agentlinux
  rm -f "$tmp"
}

# setup_brownfield_for_bail_sudoers_drift
# Targets: REMEDIATE-03 sudoers drift overwrite. /etc/sudoers.d/agentlinux
# exists with a non-ADR-012 line; agent user OK; otherwise REUSE-compatible.
setup_brownfield_for_bail_sudoers_drift() {
  "$INSTALLER" provision --purge >/dev/null 2>&1 || true
  useradd -m -s /bin/bash agent >/dev/null 2>&1 || usermod -s /bin/bash agent
  # DRIFTED sudoers: not the canonical ADR-012 line. Use a narrower scope
  # (still valid sudoers syntax so visudo -cf passes) so the file is
  # PRESENT but NOPASSWD_OK=false → triggers remediate token.
  local tmp
  tmp=$(mktemp)
  printf 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get\n' >"$tmp"
  install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/agentlinux
  rm -f "$tmp"
}

# Test 12: --help carries "Exit codes:" section.

# Test 13: greenfield --yes succeeds.
@test "UX-03: agentlinux-install --yes on post-installer (greenfield-ish) host completes with no [BAIL] / no [REMEDIATE-NN] lines" {
  run "$INSTALLER" provision --yes
  assert_exit_zero "UX-03"
  # No bail lines.
  printf '%s' "$output" | grep -qE '^\[BAIL\]' \
    && __fail "UX-03" "no [BAIL] lines on greenfield --yes" "$output" "$LOG"
  # No REMEDIATE marker lines (Plan 14-02/14-03 land real handlers; Plan
  # 14-01 stubs emit [REMEDIATE-NN] only when the dispatch case fires, which
  # requires a brownfield trigger).
  printf '%s' "$output" | grep -qE '^\[REMEDIATE-' \
    && __fail "UX-03" "no [REMEDIATE-NN] lines on greenfield --yes" "$output" "$LOG"
  true
}

# Test 14: greenfield --no-yes succeeds (default, same as no flag).
@test "UX-03: agentlinux-install --no-yes on post-installer host completes (default; explicit-no opposite of --yes)" {
  run "$INSTALLER" provision --no-yes
  assert_exit_zero "UX-03"
}

# Test 15: contradictory flags --yes --no-yes exits 64 (T-14-02 mitigation).
@test "UX-05 (T-14-02): agentlinux-install --yes --no-yes exits 64 with contradictory-flags error" {
  run "$INSTALLER" provision --yes --no-yes
  [[ "$status" -eq 64 ]] \
    || __fail "UX-05" "exit 64 on --yes --no-yes" "exit=$status" "$INSTALLER"
  printf '%s' "$output" | grep -qF 'contradictory flags' \
    || __fail "UX-05" "log_error 'contradictory flags'" "$output" "$INSTALLER"
}

# Test 16: reverse order --no-yes --yes ALSO exits 64 (no last-flag-wins).
@test "UX-05 (T-14-02): agentlinux-install --no-yes --yes ALSO exits 64 (no 'last flag wins' silent acceptance)" {
  run "$INSTALLER" provision --no-yes --yes
  [[ "$status" -eq 64 ]] \
    || __fail "UX-05" "exit 64 on --no-yes --yes" "exit=$status" "$INSTALLER"
  printf '%s' "$output" | grep -qF 'contradictory flags' \
    || __fail "UX-05" "log_error 'contradictory flags' both orders" "$output" "$INSTALLER"
}

# Test 17: unknown flag exits 64.
@test "UX-05: agentlinux provision --frobnicate (unknown flag) is rejected non-zero" {
  # Post-cutover the arg parser is clap (Rust), not the Bash getopts. clap rejects
  # an unknown flag with its own diagnostic ("unexpected argument … found") and
  # exit 2 — a non-zero rejection, which is the behavior contract that matters
  # (an unknown flag never silently proceeds). The exact code/text is clap's, not
  # the Bash EX_USAGE=64 / "unknown argument".
  run "$INSTALLER" provision --frobnicate
  [[ "$status" -ne 0 ]] \
    || __fail "UX-05" "non-zero exit on unknown flag" "exit=$status" "$INSTALLER"
  printf '%s' "$output" | grep -qiE 'unexpected argument|unrecognized|error:' \
    || __fail "UX-05" "clap unknown-flag diagnostic" "$output" "$INSTALLER"
}

# Test 18: T-14-01 grep — no env-var consent spoof variables.

# Test 19: NO-MUTATION SNAPSHOT — wrong-shell bail. The architectural proof
# of UX-03 atomicity: snapshot before, run without --yes, assert exit 65 +
# bail message, snapshot after, assert byte-equality.
#
# Plan 15-02 (UX-04 / D-15-08) refactor: the wrong-shell incompatible-user
# case now routes through main()'s alt-user gate BEFORE
# remediate::collect_all_decisions. In non-TTY mode (this test pipes no TTY)
# prompt::alt_user_or_bail emits the locked hint message and exits 65 — the
# Phase 14 `[BAIL] component=user` line is REPLACED by the D-15-08 hint
# message. The atomicity invariant (zero host mutation) is preserved because
# the gate exits BEFORE any provisioner runs; only the user-facing
# diagnostic surface changes.
@test "UX-03 (T-14-13) / UX-04 (D-15-08): NO-MUTATION SNAPSHOT — wrong-shell user bail leaves /etc/sudoers.d /home /etc/passwd byte-identical" {
  setup_brownfield_for_bail_user_wrongshell

  local before="$AL_TMPDIR/before"
  local after="$AL_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run "$INSTALLER" provision
  [[ "$status" -eq 65 ]] \
    || __fail "UX-03" "exit 65 on wrong-shell bail without --yes" "exit=$status output=$output" "$LOG"
  # Plan 15-02: assert the new D-15-08 bail-with-hint message replaces the
  # Phase 14 `[BAIL] component=user` line for the wrong-shell case.
  printf '%s' "$output" | grep -qF 'agentlinux: existing user "agent" is incompatible (wrong-shell).' \
    || __fail "D-15-08" "wrong-shell bail-with-hint message in stderr" "$output" "$LOG"
  printf '%s' "$output" | grep -qF 'Re-run with --user=' \
    || __fail "D-15-08" "--user= suggestion in bail-with-hint message" "$output" "$LOG"

  snapshot_capture "$after" /etc/sudoers.d /home /etc/passwd

  if ! snapshot_equal "$before" "$after"; then
    __fail "UX-03 (T-14-13)" "BYTE-IDENTICAL /etc/sudoers.d /home /etc/passwd before+after bail" "$(diff -r --exclude=.npm "$before" "$after" 2>&1 | head -20)" "$LOG"
  fi
}

# Test 20: NO-MUTATION SNAPSHOT — sudoers drift bail (byte-equal proof).
@test "UX-03 (T-14-13): NO-MUTATION SNAPSHOT — sudoers drift bail leaves host byte-identical" {
  setup_brownfield_for_bail_sudoers_drift

  local before="$AL_TMPDIR/before"
  local after="$AL_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run "$INSTALLER" provision
  [[ "$status" -eq 65 ]] \
    || __fail "UX-03" "exit 65 on sudoers drift bail without --yes" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[BAIL] component=sudoers reason=drift' \
    || __fail "UX-03" "[BAIL] component=sudoers reason=drift line in bail message" "$output" "$LOG"

  snapshot_capture "$after" /etc/sudoers.d /home /etc/passwd

  if ! snapshot_equal "$before" "$after"; then
    __fail "UX-03 (T-14-13)" "BYTE-IDENTICAL host state before+after sudoers-drift bail" "$(diff -r --exclude=.npm "$before" "$after" 2>&1 | head -20)" "$LOG"
  fi
}

# Test 21: NO-MUTATION SNAPSHOT — npm-prefix wrong-owner bail.
# NOTE: in the Docker container, npm prefix is bootstrapped by 30-nodejs.sh
# at /home/agent/.npm-global and IS agent-writable, so a wrong-owner-prefix
# brownfield needs a fixture that flips the writability. We do this by
# chowning the prefix back to root after the --purge wipe + fresh useradd.
@test "UX-03 (T-14-13): NO-MUTATION SNAPSHOT — wrong-owner npm-prefix bail leaves host byte-identical" {
  # Tear down then build fixture: agent + canonical sudoers + Node already
  # installed (from prior @tests in this run) but ~agent/.npm-global owned
  # by root → DETECT_NPM_PREFIX_USER_WRITABLE=false → remediate token.
  "$INSTALLER" provision --purge >/dev/null 2>&1 || true
  useradd -m -s /bin/bash agent >/dev/null 2>&1 || usermod -s /bin/bash agent
  local tmp
  tmp=$(mktemp)
  printf 'agent ALL=(ALL) NOPASSWD: ALL\n' >"$tmp"
  install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/agentlinux
  rm -f "$tmp"

  # Create a root-owned npm prefix at /home/agent/.npm-global + write a
  # ~/.npmrc pointing at it so npm config get prefix --location=user
  # returns it (DETECT_NPM_PREFIX_SECTION_STATUS=present + EFFECTIVE_OWNER
  # = root → reuse::npm_prefix_decision returns remediate).
  install -d -m 0755 -o root -g root /home/agent/.npm-global
  install -d -m 0755 -o root -g root /home/agent/.npm-global/bin
  install -d -m 0755 -o root -g root /home/agent/.npm-global/lib
  # Write the .npmrc as the agent so DETECT_NPM_PREFIX_DECLARATIONS=1.
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
  echo "prefix=/home/agent/.npm-global" >>/home/agent/.npmrc
  chown agent:agent /home/agent/.npmrc

  local before="$AL_TMPDIR/before"
  local after="$AL_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run "$INSTALLER" provision
  [[ "$status" -eq 65 ]] \
    || __fail "UX-03" "exit 65 on npm-prefix wrong-owner bail without --yes" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[BAIL] component=npm-prefix' \
    || __fail "UX-03" "[BAIL] component=npm-prefix line in bail message" "$output" "$LOG"

  snapshot_capture "$after" /etc/sudoers.d /home /etc/passwd

  if ! snapshot_equal "$before" "$after"; then
    __fail "UX-03 (T-14-13)" "BYTE-IDENTICAL host state before+after npm-prefix bail" "$(diff -r --exclude=.npm "$before" "$after" 2>&1 | head -20)" "$LOG"
  fi
}

# Test 22: BAIL AGGREGATION + atomicity — two components bail, both surface,
# AND host stays byte-identical.
@test "UX-03 (T-14-13): NO-MUTATION SNAPSHOT — aggregated bail (sudoers drift + npm-prefix wrong-owner) prints BOTH [BAIL] lines + leaves host byte-identical" {
  "$INSTALLER" provision --purge >/dev/null 2>&1 || true
  useradd -m -s /bin/bash agent >/dev/null 2>&1 || usermod -s /bin/bash agent
  # Drifted sudoers (narrower than ADR-012 — visudo-valid but not canonical).
  local tmp
  tmp=$(mktemp)
  printf 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get\n' >"$tmp"
  install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/agentlinux
  rm -f "$tmp"
  # Wrong-owner npm prefix.
  install -d -m 0755 -o root -g root /home/agent/.npm-global
  install -d -m 0755 -o root -g root /home/agent/.npm-global/bin
  install -d -m 0755 -o root -g root /home/agent/.npm-global/lib
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
  echo "prefix=/home/agent/.npm-global" >>/home/agent/.npmrc
  chown agent:agent /home/agent/.npmrc

  local before="$AL_TMPDIR/before"
  local after="$AL_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run "$INSTALLER" provision
  [[ "$status" -eq 65 ]] \
    || __fail "UX-03" "exit 65 on aggregated bail without --yes" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[BAIL] component=sudoers' \
    || __fail "UX-03" "[BAIL] component=sudoers line present (aggregation)" "$output" "$LOG"
  printf '%s' "$output" | grep -qF '[BAIL] component=npm-prefix' \
    || __fail "UX-03" "[BAIL] component=npm-prefix line present (aggregation)" "$output" "$LOG"

  snapshot_capture "$after" /etc/sudoers.d /home /etc/passwd

  if ! snapshot_equal "$before" "$after"; then
    __fail "UX-03 (T-14-13)" "BYTE-IDENTICAL host state before+after aggregated bail" "$(diff -r --exclude=.npm "$before" "$after" 2>&1 | head -20)" "$LOG"
  fi
}

# Test 23: --yes on drifted-sudoers fixture passes the gate; stub fires.
@test "UX-03: agentlinux-install --yes on drifted-sudoers brownfield host passes the gate (stub fires; installer exits 0)" {
  setup_brownfield_for_bail_sudoers_drift

  run "$INSTALLER" provision --yes
  # Plan 14-01 ships the stub; the installer should NOT exit 65. The stub
  # emits [REMEDIATE-03] component=sudoers action=stub, then 20-sudoers.sh's
  # CREATE machinery overwrites the drifted file with the canonical line.
  assert_exit_zero "UX-03"
  printf '%s' "$output" | grep -qF '[REMEDIATE-03] component=sudoers' \
    || __fail "UX-03" "[REMEDIATE-03] component=sudoers stub fired with --yes" "$output" "$LOG"
  # Drift overwritten (the CREATE machinery in 20-sudoers.sh installs the
  # canonical ADR-012 line via install -m 0440).
  grep -qFx 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "UX-03" "drift overwritten with canonical ADR-012 line after --yes" "$(cat /etc/sudoers.d/agentlinux)" "$LOG"
}

# Test 24: literal grep — exit-code constants in source.

# DECIDE-THEN-ACT ordering check (grep-shape — defends against a future
# refactor that puts run_provisioners before flush_bails_or_continue).

# RESOLUTIONS dispatch grep — verify provisioners 10/20/30 read pre-resolved
# tokens instead of calling reuse::*_decision directly.

# ---- Plan 14-02 Task 1: REMEDIATE-01 chown/rebase strategy + module migration -----

# Test 31 — BROWNFIELD chown happy path E2E.
@test "REMEDIATE-01: BROWNFIELD chown E2E — under-home + empty prefix → chown -R; prefix becomes agent:agent" {
  setup_brownfield_for_remediate_01_chown

  run "$INSTALLER" provision --yes
  assert_exit_zero "REMEDIATE-01"
  # Strategy marker.
  printf '%s' "$output" | grep -qF '[REMEDIATE-01] strategy=chown' \
    || __fail "REMEDIATE-01" "strategy=chown marker in transcript" "$output" "$LOG"
  # Prefix now agent-owned.
  local owner
  owner=$(stat -c '%U:%G' /home/agent/.npm-global)
  [[ "$owner" == "agent:agent" ]] \
    || __fail "REMEDIATE-01" "/home/agent/.npm-global owner=agent:agent post-chown" "$owner" "$LOG"
}

# Test 32 — BROWNFIELD rebase happy path E2E.
@test "REMEDIATE-01: BROWNFIELD rebase E2E — prefix outside home → ~user/.npm-global created; OLD prefix UNTOUCHED" {
  setup_brownfield_for_remediate_01_rebase

  # Snapshot the OLD prefix so we can prove it was not deleted.
  local old_before
  old_before=$(stat -c '%U:%G %a' /usr/local/agentlinux-old)

  run "$INSTALLER" provision --yes
  assert_exit_zero "REMEDIATE-01"
  # Strategy marker.
  printf '%s' "$output" | grep -qF '[REMEDIATE-01] strategy=rebase' \
    || __fail "REMEDIATE-01" "strategy=rebase marker in transcript" "$output" "$LOG"
  # New prefix created agent-owned.
  [[ -d /home/agent/.npm-global ]] \
    || __fail "REMEDIATE-01" "/home/agent/.npm-global exists after rebase" "missing" "$LOG"
  local new_owner
  new_owner=$(stat -c '%U:%G' /home/agent/.npm-global)
  [[ "$new_owner" == "agent:agent" ]] \
    || __fail "REMEDIATE-01" "/home/agent/.npm-global owner=agent:agent" "$new_owner" "$LOG"
  # .npmrc has prefix= line.
  grep -qFx "prefix=/home/agent/.npm-global" /home/agent/.npmrc \
    || __fail "REMEDIATE-01" "~agent/.npmrc has prefix=/home/agent/.npm-global" "$(cat /home/agent/.npmrc)" "$LOG"
  # OLD prefix NEVER deleted (CONTEXT Area 2 Q4).
  [[ -d /usr/local/agentlinux-old ]] \
    || __fail "REMEDIATE-01" "OLD prefix /usr/local/agentlinux-old NOT deleted (user cleanup)" "missing" "$LOG"
  local old_after
  old_after=$(stat -c '%U:%G %a' /usr/local/agentlinux-old)
  [[ "$old_before" == "$old_after" ]] \
    || __fail "REMEDIATE-01" "OLD prefix stat unchanged (before=$old_before)" "after=$old_after" "$LOG"
}

# Test 33 — BROWNFIELD rebase WITH module migration.
@test "REMEDIATE-01: BROWNFIELD rebase migrates pre-existing global modules via npm install -g" {
  setup_brownfield_for_remediate_01_rebase_with_module

  run "$INSTALLER" provision --yes
  assert_exit_zero "REMEDIATE-01"
  # Either migrated successfully OR logged as partial — both are acceptable
  # for the best-effort contract (network may be unavailable). The marker
  # MUST surface either way so the operator can act on the partial list.
  if ! printf '%s' "$output" | grep -qE '\[REMEDIATE-01:(migrated|partial)\] module=lodash'; then
    __fail "REMEDIATE-01" "[REMEDIATE-01:migrated|partial] module=lodash line in transcript" "$output" "$LOG"
  fi
}

# Test 34 — Catalog agent exclusion from migration loop (Area 2 Q3).
@test "REMEDIATE-01: rebase migration loop EXCLUDES catalog agents (get-shit-done-cc not migrated via REMEDIATE-01)" {
  setup_brownfield_for_remediate_01_rebase_with_catalog_module

  run "$INSTALLER" provision --yes
  assert_exit_zero "REMEDIATE-01"
  # Confirm get-shit-done-cc is NOT in the migration transcript (neither
  # migrated nor partial — it should be filtered out before the loop).
  printf '%s' "$output" | grep -qE '\[REMEDIATE-01:(migrated|partial)\] module=get-shit-done-cc' \
    && __fail "REMEDIATE-01" "catalog agent get-shit-done-cc NOT in migration loop" "$output" "$LOG"
  true
}

# Test 37 — chown-blocked-by-allowlist E2E (T-14-03 end-to-end).
@test "REMEDIATE-01 (T-14-03): BROWNFIELD chown REFUSED when prefix has non-allowlist entry → falls back to rebase" {
  setup_brownfield_for_remediate_01_chown_blocked

  run "$INSTALLER" provision --yes
  assert_exit_zero "REMEDIATE-01"
  # Strategy MUST be rebase (NOT chown) because lib/node_modules/some-user-pkg
  # blocks the allowlist check.
  printf '%s' "$output" | grep -qF '[REMEDIATE-01] strategy=rebase' \
    || __fail "REMEDIATE-01 (T-14-03)" "strategy=rebase when prefix has user-installed module" "$output" "$LOG"
  printf '%s' "$output" | grep -qF '[REMEDIATE-01] strategy=chown' \
    && __fail "REMEDIATE-01 (T-14-03)" "strategy=chown MUST NOT fire when non-allowlist entry present" "$output" "$LOG"
  # The pre-existing user-installed module was preserved (NOT clobbered).
  [[ -f /home/agent/.npm-global/lib/node_modules/some-user-pkg/package.json ]] \
    || __fail "REMEDIATE-01 (T-14-03)" "pre-existing user-installed module preserved" "missing" "$LOG"
}

# ---- Plan 14-02 Task 2: REMEDIATE-02 + REMEDIATE-03 helpers + refactor -----

# Test 40 — install_or_overwrite OVERWRITES a pre-existing drifted file.
@test "REMEDIATE-03: install_or_overwrite OVERWRITES drifted sudoers with canonical ADR-012 line" {
  setup_brownfield_for_remediate_03_drift

  # Drift overwrite is state-overwriting → requires --yes.
  run "$INSTALLER" provision --yes
  assert_exit_zero "REMEDIATE-03"
  grep -qFx 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "REMEDIATE-03" "drift overwritten with canonical ADR-012 line" "$(cat /etc/sudoers.d/agentlinux)" "$LOG"
  # Marker line confirming the OVERWRITE arm fired.
  printf '%s' "$output" | grep -qF '[REMEDIATE-03] component=sudoers action=overwrite' \
    || __fail "REMEDIATE-03" "[REMEDIATE-03] action=overwrite marker in transcript" "$output" "$LOG"
}

# Test 42 — BROWNFIELD missing-file install is ADDITIVE (no --yes needed).
@test "REMEDIATE-03: missing sudoers — additive install fires WITHOUT --yes (no consent gate consulted)" {
  setup_brownfield_for_remediate_03_missing

  # No --yes flag — additive action per CONTEXT.md Area 1 Q1 (sudoers-missing-install
  # is in the additive set; remediate_action_overwrites_state returns false).
  run "$INSTALLER" provision
  assert_exit_zero "REMEDIATE-03"
  [[ -f /etc/sudoers.d/agentlinux ]] \
    || __fail "REMEDIATE-03" "/etc/sudoers.d/agentlinux exists after additive install" "missing" "$LOG"
  printf '%s' "$output" | grep -qF '[REMEDIATE-03] component=sudoers action=install' \
    || __fail "REMEDIATE-03" "[REMEDIATE-03] action=install marker in transcript" "$output" "$LOG"
  # NO bail line on additive path.
  printf '%s' "$output" | grep -qE '^\[BAIL\] component=sudoers' \
    && __fail "REMEDIATE-03" "no [BAIL] component=sudoers on missing-file (additive)" "$output" "$LOG"
  true
}

# Test 43 — BROWNFIELD drift overwrite BAILS without --yes.
@test "REMEDIATE-03: drifted sudoers + NO --yes → exit 65 + [BAIL] component=sudoers reason=drift" {
  setup_brownfield_for_remediate_03_drift

  # Snapshot drifted file to prove it was NOT overwritten.
  local pre_sha
  pre_sha=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)

  run "$INSTALLER" provision
  [[ "$status" -eq 65 ]] \
    || __fail "REMEDIATE-03" "exit 65 on drift without --yes" "exit=$status" "$LOG"
  printf '%s' "$output" | grep -qF '[BAIL] component=sudoers reason=drift' \
    || __fail "REMEDIATE-03" "[BAIL] component=sudoers reason=drift in bail message" "$output" "$LOG"
  # Drifted file UNCHANGED (DECIDE-THEN-ACT atomicity).
  local post_sha
  post_sha=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)
  [[ "$pre_sha" == "$post_sha" ]] \
    || __fail "REMEDIATE-03" "drifted sudoers UNCHANGED after bail" "pre=$pre_sha post=$post_sha" "$LOG"
}

# Test 44 — BROWNFIELD REMEDIATE-02 PATH wiring re-attaches additively.
@test "REMEDIATE-02: PATH wiring re-attaches to brownfield user; pre-existing .bashrc content preserved" {
  setup_brownfield_for_remediate_02_path_wiring

  # No --yes needed — REMEDIATE-02 is the canonical additive action. The
  # ensure_marker_block primitive preserves user content outside the
  # `agentlinux-path begin/end` markers; the post-run assertions below grep
  # for both the marker block AND the pre-existing alias/export lines to
  # prove BOTH coexist.
  run "$INSTALLER" provision
  assert_exit_zero "REMEDIATE-02"
  # All four artefacts present.
  [[ -f /etc/profile.d/agentlinux.sh ]] \
    || __fail "REMEDIATE-02" "/etc/profile.d/agentlinux.sh present" "missing" "$LOG"
  [[ -f /etc/agentlinux.env ]] \
    || __fail "REMEDIATE-02" "/etc/agentlinux.env present" "missing" "$LOG"
  [[ -f /etc/cron.d/agentlinux ]] \
    || __fail "REMEDIATE-02" "/etc/cron.d/agentlinux present" "missing" "$LOG"
  # ~agent/.bashrc has the marker block.
  grep -qF "agentlinux-path begin" /home/agent/.bashrc \
    || __fail "REMEDIATE-02" "agentlinux-path marker block in ~agent/.bashrc" "$(cat /home/agent/.bashrc)" "$LOG"
  # Pre-existing user content OUTSIDE the marker block preserved.
  grep -qF "alias ll=" /home/agent/.bashrc \
    || __fail "REMEDIATE-02" "pre-existing user alias 'alias ll=' preserved" "$(cat /home/agent/.bashrc)" "$LOG"
  grep -qF "export PROJECT_DIR=" /home/agent/.bashrc \
    || __fail "REMEDIATE-02" "pre-existing PROJECT_DIR export preserved" "$(cat /home/agent/.bashrc)" "$LOG"
  # [REMEDIATE-02] marker fires because the user was REUSED.
  printf '%s' "$output" | grep -qF '[REMEDIATE-02] component=user action=path-wiring-additive' \
    || __fail "REMEDIATE-02" "[REMEDIATE-02] marker emitted for REUSED user" "$output" "$LOG"
}

# Test 45 — REMEDIATE-02 idempotent on re-run (marker block converges).
@test "REMEDIATE-02: re-running on a REUSED-user host is byte-stable (additive primitives converge)" {
  setup_brownfield_for_remediate_02_path_wiring

  # First run installs the marker block.
  "$INSTALLER" provision >/dev/null 2>&1
  local sha_first
  sha_first=$(sha256sum /home/agent/.bashrc | cut -d' ' -f1)

  # Second run must produce byte-identical .bashrc (ensure_marker_block converges).
  "$INSTALLER" provision >/dev/null 2>&1
  local sha_second
  sha_second=$(sha256sum /home/agent/.bashrc | cut -d' ' -f1)
  [[ "$sha_first" == "$sha_second" ]] \
    || __fail "REMEDIATE-02" "byte-stable ~agent/.bashrc across re-run" "first=$sha_first second=$sha_second" "$LOG"
}

# Test 47 — BHV-07 regression guard: 20-sudoers.sh refactor preserves byte-stable output.
@test "REMEDIATE-03: 20-sudoers.sh post-refactor produces byte-identical /etc/sudoers.d/agentlinux across re-run (BHV-07)" {
  # Ensure canonical state; both runs should produce a byte-stable file.
  "$INSTALLER" provision --purge >/dev/null 2>&1 || true
  "$INSTALLER" provision >/dev/null 2>&1
  local sha_first
  sha_first=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)

  "$INSTALLER" provision >/dev/null 2>&1
  local sha_second
  sha_second=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)
  [[ "$sha_first" == "$sha_second" ]] \
    || __fail "BHV-07" "/etc/sudoers.d/agentlinux byte-stable post-refactor across re-run" "first=$sha_first second=$sha_second" "$LOG"
}

# =============================================================================
# Plan 14-03 Tests 48-54 — REMEDIATE-04 preserve_paths.json + brownfield E2E.
#
# Tests 48-50: per-agent uninstall.sh _should_remove() helper honors
#   AGENTLINUX_PRESERVE_PATHS (colon-separated, descendant rule). Direct
#   invocation of each uninstall.sh against fixture user-data dirs.
# Tests 51-53: brownfield E2E — claude-code installed via npm (PATH-MISMATCH
#   location), then `agentlinux install claude-code --yes` triggers
#   REMEDIATE-04. Tests cover happy path + uninstall-fail + half-uninstalled.
# Test 54: greenfield invariant retest — full Docker matrix still GREEN after
#   Plan 14-03 changes; preserved_paths.json never fires on greenfield.
# =============================================================================

CATALOG_DIR=/opt/agentlinux-src/plugin/catalog

# Test 48 — claude-code uninstall.sh _should_remove honors AGENTLINUX_PRESERVE_PATHS.
@test "REMEDIATE-04 CAT-04: claude-code uninstall.sh preserves ~/.claude/test-file via AGENTLINUX_PRESERVE_PATHS=.claude" {
  # Pre-stage agent home + user-data marker.
  if ! id -u agent >/dev/null 2>&1; then
    useradd -m -s /bin/bash agent
  fi
  install -d -m 0755 -o agent -g agent /home/agent/.claude
  install -d -m 0755 -o agent -g agent /home/agent/.claude/downloads
  echo "preserve-this" >/home/agent/.claude/test-marker-file
  echo "preserve-downloads" >/home/agent/.claude/downloads/bootstrap-cache
  chown -R agent:agent /home/agent/.claude

  # Pre-stage a fake claude binary that uninstall.sh will try to delete; the
  # _rm helper consults _should_remove before issuing rm.
  install -d -m 0755 -o agent -g agent /home/agent/.local/bin
  echo "#!/bin/sh" >/home/agent/.local/bin/claude
  chmod 0755 /home/agent/.local/bin/claude
  chown agent:agent /home/agent/.local/bin/claude

  # Invoke uninstall.sh with AGENTLINUX_PRESERVE_PATHS containing .claude.
  AGENTLINUX_AGENT_HOME=/home/agent \
    AGENTLINUX_PRESERVE_PATHS=".claude" \
    bash "$CATALOG_DIR/agents/claude-code/uninstall.sh" >/tmp/un48.log 2>&1 || true

  [[ -f /home/agent/.claude/test-marker-file ]] \
    || __fail "REMEDIATE-04" "test-marker survives uninstall.sh under .claude preserve" "deleted" "$(cat /tmp/un48.log)"
  # CAT-04 behavior shift: ~/.claude/downloads now ALSO preserved (descendant rule).
  [[ -f /home/agent/.claude/downloads/bootstrap-cache ]] \
    || __fail "REMEDIATE-04 CAT-04 shift" "agent-home /.claude/downloads is preserved as descendant of agent-home /.claude" "deleted" "$(cat /tmp/un48.log)"
  # Binary at non-preserved path is removed.
  [[ ! -f /home/agent/.local/bin/claude ]] \
    || __fail "REMEDIATE-04" "agent-home /.local/bin/claude (not in preserve list) is removed" "still present" "$(cat /tmp/un48.log)"

  # Cleanup so downstream tests don't see this residue.
  rm -rf /home/agent/.claude/test-marker-file /home/agent/.claude/downloads
}

# Test 49 — gsd uninstall.sh _should_remove honors AGENTLINUX_PRESERVE_PATHS.
@test "REMEDIATE-04 CAT-04: gsd uninstall.sh preserves ~/.gsd + ~/.config/get-shit-done fixture dirs" {
  if ! id -u agent >/dev/null 2>&1; then
    useradd -m -s /bin/bash agent
  fi
  install -d -m 0755 -o agent -g agent /home/agent/.gsd
  install -d -m 0755 -o agent -g agent /home/agent/.config/get-shit-done
  echo "gsd-workflow-state" >/home/agent/.gsd/marker
  echo "gsd-user-config" >/home/agent/.config/get-shit-done/marker
  chown -R agent:agent /home/agent/.gsd /home/agent/.config/get-shit-done

  # Stage a skill dir that the gsd uninstall.sh defensively removes — NOT in
  # preserve set, so it should still be removed by the helper.
  install -d -m 0755 -o agent -g agent /home/agent/.claude/skills/gsd-test-skill
  chown -R agent:agent /home/agent/.claude

  # Run uninstall.sh (gsd's may try to call npm uninstall -g; tolerate failure).
  AGENTLINUX_AGENT_HOME=/home/agent \
    AGENTLINUX_PRESERVE_PATHS=".gsd:.config/get-shit-done" \
    bash "$CATALOG_DIR/agents/gsd/uninstall.sh" >/tmp/un49.log 2>&1 || true

  [[ -f /home/agent/.gsd/marker ]] \
    || __fail "REMEDIATE-04" "agent-home /.gsd/marker preserved via AGENTLINUX_PRESERVE_PATHS" "deleted" "$(cat /tmp/un49.log)"
  [[ -f /home/agent/.config/get-shit-done/marker ]] \
    || __fail "REMEDIATE-04" "agent-home /.config/get-shit-done/marker preserved" "deleted" "$(cat /tmp/un49.log)"

  # Cleanup
  rm -rf /home/agent/.gsd/marker /home/agent/.config/get-shit-done/marker /home/agent/.claude/skills
}

# Test 50 — playwright-cli uninstall.sh preserves ~/.cache/ms-playwright fixture dir.
@test "REMEDIATE-04 CAT-04: playwright-cli uninstall.sh preserves ~/.cache/ms-playwright fixture" {
  if ! id -u agent >/dev/null 2>&1; then
    useradd -m -s /bin/bash agent
  fi
  install -d -m 0755 -o agent -g agent /home/agent/.cache/ms-playwright/chromium-1234
  echo "expensive-browser-binary-stub" >/home/agent/.cache/ms-playwright/chromium-1234/headless_shell
  chown -R agent:agent /home/agent/.cache

  AGENTLINUX_AGENT_HOME=/home/agent \
    AGENTLINUX_PRESERVE_PATHS=".cache/ms-playwright" \
    bash "$CATALOG_DIR/agents/playwright-cli/uninstall.sh" >/tmp/un50.log 2>&1 || true

  [[ -f /home/agent/.cache/ms-playwright/chromium-1234/headless_shell ]] \
    || __fail "REMEDIATE-04" "agent-home /.cache/ms-playwright/chromium-1234/headless_shell preserved" "deleted" "$(cat /tmp/un50.log)"

  rm -rf /home/agent/.cache/ms-playwright
}

# Pre-populate container with claude-code installed via `npm install -g`
# (~/.npm-global/bin/claude — PATH-MISMATCH vs canonical ~/.local/bin/claude).
# Pre-populate ~/.claude/test-marker-file. Run `agentlinux install claude-code --yes`.
# Assert: exit 0; [REMEDIATE-04] marker; canonical binary present; PATH-MISMATCH
# location removed; user data survives; sentinel status=installed.
@test "REMEDIATE-04 E2E: brownfield PATH-MISMATCH claude-code reinstalls at canonical path; ~/.claude/ user data survives" {
  setup_brownfield_broken_claude_code

  # Run the bash entrypoint first so the canonical baseline (agent user,
  # sudoers, Node, PATH wiring, sentinel dirs) is in place. Use --yes since
  # brownfield baseline has no defects that would bail.
  "$INSTALLER" provision --yes >/dev/null 2>&1 || true

  # Sanity: PATH-MISMATCH binary still present at brownfield location.
  [[ -x /home/agent/.npm-global/bin/claude ]] \
    || skip "npm install -g claude-code didn't populate ~/.npm-global/bin/claude (sandbox npm issue)"

  # Sanity: marker still present after baseline install.
  [[ -f /home/agent/.claude/test-marker-file ]] \
    || __fail "REMEDIATE-04" "test marker survives baseline install" "deleted by baseline" "$LOG"

  # Now run the CLI: agentlinux install claude-code --yes.
  # Use sudo -u agent -H since the CLI's guardAgentUser preActionHook refuses
  # root. The detect cache must be present — bash entrypoint should have run
  # detect:: by now and populated /run/agentlinux-detect.json.
  local cli_out cli_rc
  cli_out=$(sudo -u agent -H bash --login -c 'agentlinux install claude-code --yes' 2>&1) || cli_rc=$?
  cli_rc=${cli_rc:-0}

  [[ "$cli_rc" -eq 0 ]] \
    || __fail "REMEDIATE-04" "agentlinux install claude-code --yes exits 0" "rc=$cli_rc out=$cli_out" "$LOG"

  # The PATH-MISMATCH binary should be GONE after uninstall+install.
  # Note: install.sh restores the canonical path; the npm-global one is what
  # uninstall.sh tears down via npm uninstall -g.
  echo "$cli_out" | grep -qF "[REMEDIATE-04]" \
    || __fail "REMEDIATE-04" "[REMEDIATE-04] marker emitted" "$cli_out" "$LOG"

  # User data preserved.
  [[ -f /home/agent/.claude/test-marker-file ]] \
    || __fail "REMEDIATE-04 CAT-04" "agent-home /.claude/test-marker-file survives uninstall+reinstall" "deleted" "$LOG"

  # Sentinel exists with status=installed.
  [[ -f /opt/agentlinux/state/installed.d/claude-code.json ]] \
    || __fail "REMEDIATE-04" "sentinel written post-REMEDIATE" "missing" "$LOG"
  grep -q '"status": "installed"' /opt/agentlinux/state/installed.d/claude-code.json \
    || __fail "REMEDIATE-04" "sentinel status=installed post-REMEDIATE" "$(cat /opt/agentlinux/state/installed.d/claude-code.json)" "$LOG"

  # Cleanup for downstream tests.
  rm -f /home/agent/.claude/test-marker-file
}

# Test 52 — BROWNFIELD uninstall-fail path E2E.
@test "REMEDIATE-04 E2E: brownfield uninstall.sh exit 1 → [REMEDIATE-04:uninstall-fail] + exit 1; install NOT dispatched" {
  setup_brownfield_remediate04_uninstall_fail

  # Run the bash entrypoint baseline first.
  "$INSTALLER" provision --yes >/dev/null 2>&1 || true

  if [[ ! -x /home/agent/.npm-global/bin/claude ]]; then
    teardown_brownfield_remediate04_catalog
    skip "npm install -g claude-code didn't populate brownfield binary"
  fi

  local cli_out cli_rc=0
  cli_out=$(sudo -u agent -H \
    AGENTLINUX_CATALOG_DIR="$BROWNFIELD_TMP_CATALOG" \
    bash --login -c "AGENTLINUX_CATALOG_DIR='$BROWNFIELD_TMP_CATALOG' agentlinux install claude-code --yes" 2>&1) || cli_rc=$?

  # Cleanup before assertions so a fail doesn't leak the overlay.
  teardown_brownfield_remediate04_catalog

  [[ "$cli_rc" -eq 1 ]] \
    || __fail "REMEDIATE-04" "uninstall-fail → exit 1" "rc=$cli_rc out=$cli_out" "$LOG"
  echo "$cli_out" | grep -qF "[REMEDIATE-04:uninstall-fail]" \
    || __fail "REMEDIATE-04" "[REMEDIATE-04:uninstall-fail] marker present" "$cli_out" "$LOG"

  # install.sh should NOT have been dispatched — meaning the
  # ~/.npm-global/bin/claude binary should still be present (since
  # uninstall.sh bailed before doing its work).
  [[ -x /home/agent/.npm-global/bin/claude ]] \
    || __fail "REMEDIATE-04" "binary still present after uninstall-fail (install NOT dispatched)" "deleted" "$LOG"
}

# Test 53 — BROWNFIELD half-uninstalled path E2E.
@test "REMEDIATE-04 E2E: brownfield uninstall OK + install.sh exit 1 → broken-after-remediate sentinel + list suffix" {
  setup_brownfield_remediate04_install_fail_post_uninstall

  "$INSTALLER" provision --yes >/dev/null 2>&1 || true

  if [[ ! -x /home/agent/.npm-global/bin/claude ]]; then
    teardown_brownfield_remediate04_catalog
    skip "npm install -g claude-code didn't populate brownfield binary"
  fi

  local cli_out cli_rc=0
  cli_out=$(sudo -u agent -H \
    bash --login -c "AGENTLINUX_CATALOG_DIR='$BROWNFIELD_TMP_CATALOG' agentlinux install claude-code --yes" 2>&1) || cli_rc=$?

  [[ "$cli_rc" -eq 1 ]] \
    || { teardown_brownfield_remediate04_catalog; __fail "REMEDIATE-04" "half-uninstalled → exit 1" "rc=$cli_rc out=$cli_out" "$LOG"; }
  echo "$cli_out" | grep -qF "[REMEDIATE-04:half-uninstalled]" \
    || { teardown_brownfield_remediate04_catalog; __fail "REMEDIATE-04" "[REMEDIATE-04:half-uninstalled] marker present" "$cli_out" "$LOG"; }

  # Sentinel written with broken-after-remediate status.
  [[ -f /opt/agentlinux/state/installed.d/claude-code.json ]] \
    || { teardown_brownfield_remediate04_catalog; __fail "REMEDIATE-04" "sentinel exists post-half-uninstall" "missing" "$LOG"; }
  grep -q '"status": "broken-after-remediate"' /opt/agentlinux/state/installed.d/claude-code.json \
    || { teardown_brownfield_remediate04_catalog; __fail "REMEDIATE-04" "sentinel status=broken-after-remediate" "$(cat /opt/agentlinux/state/installed.d/claude-code.json)" "$LOG"; }

  # list.ts renders the suffix.
  local list_out
  list_out=$(sudo -u agent -H bash --login -c "AGENTLINUX_CATALOG_DIR='$BROWNFIELD_TMP_CATALOG' agentlinux list" 2>&1)
  teardown_brownfield_remediate04_catalog

  echo "$list_out" | grep -qF "broken — half-uninstalled, manual recovery needed" \
    || __fail "REMEDIATE-04" "agentlinux list renders half-uninstalled suffix" "$list_out" "$LOG"

  # Cleanup the orphaned sentinel for downstream tests.
  rm -f /opt/agentlinux/state/installed.d/claude-code.json
}

# Test 54 — REMEDIATE-04 BAIL without --yes in non-TTY → exit 65.
@test "REMEDIATE-04 E2E: brownfield PATH-MISMATCH WITHOUT --yes in non-TTY → [BAIL] + exit 65" {
  setup_brownfield_broken_claude_code

  "$INSTALLER" provision --yes >/dev/null 2>&1 || true

  if [[ ! -x /home/agent/.npm-global/bin/claude ]]; then
    skip "npm install -g claude-code didn't populate brownfield binary"
  fi

  local cli_out cli_rc=0
  cli_out=$(sudo -u agent -H bash --login -c 'agentlinux install claude-code </dev/null' 2>&1) || cli_rc=$?

  [[ "$cli_rc" -eq 65 ]] \
    || __fail "REMEDIATE-04" "non-TTY without --yes → exit 65" "rc=$cli_rc out=$cli_out" "$LOG"
  echo "$cli_out" | grep -qF "[BAIL]" \
    || __fail "REMEDIATE-04" "[BAIL] marker present" "$cli_out" "$LOG"
  echo "$cli_out" | grep -qF "component=claude-code" \
    || __fail "REMEDIATE-04" "[BAIL] component=claude-code" "$cli_out" "$LOG"

  # Cleanup — PATH-MISMATCH binary should still be present (no mutation).
  [[ -x /home/agent/.npm-global/bin/claude ]] \
    || __fail "REMEDIATE-04" "no-mutation under [BAIL]: binary preserved" "missing" "$LOG"
  rm -f /home/agent/.claude/test-marker-file
}
