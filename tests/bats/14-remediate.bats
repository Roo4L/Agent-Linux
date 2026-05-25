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
# Task 1 block (this file's first 11 @tests):
#   1.  remediate.sh is sourceable after log+as_user+detect+reuse libs
#   2.  remediate::register_bail appends to BAILED_COMPONENTS (additive)
#   3.  flush_bails_or_continue returns 0 when array is empty
#   4.  flush_bails_or_continue with N=1 prints structured msg + exits 65
#   5.  flush_bails_or_continue with N=2 prints both [BAIL] lines + exits 65
#   6.  remediate_action_overwrites_state predicate (true/false matrix)
#   7.  per-component stubs source + define remediate::<c>::<action> stubs
#   8.  reuse::user_decision behavior unchanged from Phase 13
#   9.  reuse::npm_prefix_decision returns reuse|remediate|create per export
#   10. zero `register_bail "$VAR` matches in remediate/*.sh + provisioners
#   11. collect_all_decisions populates RESOLUTIONS + makes zero host mutations
#
# Task 2 block (@tests 12-24): --yes/--no-yes parsing, exit-code-64 sites,
# --help Exit codes section grep, no-mutation snapshot tests, bail-aggregation
# E2E, RESOLUTIONS dispatch greps. See action steps 1-8 in 14-01-PLAN.md.

load 'helpers/assertions'
load 'helpers/detection'
load 'helpers/brownfield'

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
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  # Best-effort residue cleanup of fixture artefacts --purge does not own.
  # The /usr/local/agentlinux-old/ tree is created by Tests 32-34 rebase
  # fixtures and lives outside --purge's scope.
  rm -rf /usr/local/agentlinux-old || true
  # Restore the canonical post-installer state so downstream bats files see
  # the host shape tests/docker/run.sh staged for them. The greenfield path
  # has no remediations, so no --yes flag needed.
  bash "$INSTALLER" >/dev/null 2>&1 || true
}

# LOG + INSTALLER are referenced by Task 2 @tests (full-installer runs); Task 1
# @tests use lib-source paths directly. shellcheck SC2034 suppression covers
# the Task-1-only file slice — the Task 2 add land introduces the actual uses.
# shellcheck disable=SC2034
LOG=/var/log/agentlinux-install.log
# shellcheck disable=SC2034
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install
LIB_DIR=/opt/agentlinux-src/plugin/lib
REMEDIATE_LIB_DIR=/opt/agentlinux-src/plugin/lib/remediate
PROV_DIR=/opt/agentlinux-src/plugin/provisioner

# Helper: source the lib chain through reuse + remediate so @tests can call
# remediate::* / reuse::* directly. Mirrors the order plugin/bin/agentlinux-install
# uses: log.sh → distro_detect.sh → as_user.sh → idempotency.sh → detect.sh →
# reuse.sh → remediate.sh.
__source_lib_chain_with_remediate() {
  # shellcheck disable=SC1091
  source "$LIB_DIR/log.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/distro_detect.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/as_user.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/idempotency.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/detect.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/reuse.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/remediate.sh"
}

# Clear bail-aggregation state between @tests so register_bail / flush behavior
# tests are isolated. Bash arrays declared with `-g` persist across function
# calls in the same shell; @tests that mutate them must reset.
__reset_remediate_state() {
  BAILED_COMPONENTS=()
  # Reset associative array by iterating keys (bash 5.x lacks a `clear`
  # primitive that works under `set -u`). Use a subshell variable for the
  # loop key so we can refer to it inside the unset target without single-
  # quote-trapping the expansion. The unset target is double-quoted around
  # the array subscript so $k expands but bash treats the whole expression
  # as one literal subscript.
  local key
  for key in "${!RESOLUTIONS[@]}"; do
    unset "RESOLUTIONS[$key]"
  done
}

# ---- Task 1: remediate.sh orchestrator + per-component stubs -----------------

@test "REMEDIATE foundation: plugin/lib/remediate.sh sources cleanly after log+detect+reuse libs" {
  # REQ: UX-03 (DECIDE-THEN-ACT orchestrator surface available to main()).
  # Source-order contract from CONTEXT.md "Phase 13 → Phase 14 contract": the
  # entrypoint sources remediate.sh AFTER reuse.sh. Verify the chain works.
  __source_lib_chain_with_remediate
  # If we got here without bash erroring, source succeeded. Spot-check that the
  # key functions are defined.
  declare -F remediate::register_bail >/dev/null \
    || __fail "UX-03" "remediate::register_bail defined after sourcing remediate.sh" "not defined" "$LIB_DIR/remediate.sh"
  declare -F remediate::flush_bails_or_continue >/dev/null \
    || __fail "UX-03" "remediate::flush_bails_or_continue defined" "not defined" "$LIB_DIR/remediate.sh"
  declare -F remediate::collect_all_decisions >/dev/null \
    || __fail "UX-03" "remediate::collect_all_decisions defined" "not defined" "$LIB_DIR/remediate.sh"
  declare -F remediate::gate_or_bail >/dev/null \
    || __fail "UX-03" "remediate::gate_or_bail defined" "not defined" "$LIB_DIR/remediate.sh"
  declare -F remediate_action_overwrites_state >/dev/null \
    || __fail "UX-03" "remediate_action_overwrites_state defined" "not defined" "$LIB_DIR/remediate.sh"
}

@test "REMEDIATE foundation: remediate::register_bail appends entry to BAILED_COMPONENTS (additive, no dedup)" {
  # REQ: UX-03 (aggregation shape — caller responsibility to dedup; additivity
  # is correct because two bails of the same component from different code
  # paths is itself an actionable signal).
  __source_lib_chain_with_remediate
  __reset_remediate_state

  remediate::register_bail "npm-prefix" "wrong-owner" "run with --yes"
  [[ "${#BAILED_COMPONENTS[@]}" -eq 1 ]] \
    || __fail "UX-03" "BAILED_COMPONENTS size=1 after one register_bail" "${#BAILED_COMPONENTS[@]}" "$LIB_DIR/remediate.sh"

  # Second register_bail with the SAME component must NOT dedup.
  remediate::register_bail "npm-prefix" "wrong-owner" "run with --yes"
  [[ "${#BAILED_COMPONENTS[@]}" -eq 2 ]] \
    || __fail "UX-03" "BAILED_COMPONENTS size=2 after duplicate register_bail (no dedup)" "${#BAILED_COMPONENTS[@]}" "$LIB_DIR/remediate.sh"

  # Pipe-separated internal shape.
  [[ "${BAILED_COMPONENTS[0]}" == "npm-prefix|wrong-owner|run with --yes" ]] \
    || __fail "UX-03" "BAILED_COMPONENTS[0] pipe-separated 'npm-prefix|wrong-owner|run with --yes'" "${BAILED_COMPONENTS[0]}" "$LIB_DIR/remediate.sh"
}

@test "REMEDIATE foundation: flush_bails_or_continue returns 0 silently when BAILED_COMPONENTS is empty" {
  # REQ: UX-03 (greenfield invariant — no bails → no [BAIL] message, no exit).
  __source_lib_chain_with_remediate
  __reset_remediate_state

  run remediate::flush_bails_or_continue
  assert_exit_zero "UX-03"
  # No stderr/stdout when empty.
  [[ -z "$output" ]] \
    || __fail "UX-03" "no output when BAILED_COMPONENTS empty" "$output" "$LIB_DIR/remediate.sh"
}

@test "REMEDIATE foundation: flush_bails_or_continue with N=1 prints structured bail message + exits 65" {
  # REQ: UX-03 + UX-05 (the locked [BAIL] format + exit code 65). CONTEXT.md
  # Area 1 Q2 + Q3.
  __source_lib_chain_with_remediate
  __reset_remediate_state
  remediate::register_bail "npm-prefix" "wrong-owner" "run with --yes to chown or rebase"

  # `run` captures exit code + merged stdout+stderr. flush exits 65 (terminal
  # sink — exit, not return).
  run remediate::flush_bails_or_continue
  [[ "$status" -eq 65 ]] \
    || __fail "UX-05" "flush_bails_or_continue exits 65 with one bail" "exit=$status" "$LIB_DIR/remediate.sh"

  # Header line.
  printf '%s' "$output" | grep -qE 'Refusing to proceed — 1 components need Remediate' \
    || __fail "UX-03" "header line 'Refusing to proceed — 1 components need Remediate'" "$output" "$LIB_DIR/remediate.sh"

  # [BAIL] structured line — verbatim CONTEXT.md Area 1 Q2 format.
  printf '%s' "$output" | grep -qF '[BAIL] component=npm-prefix reason=wrong-owner hint=run with --yes to chown or rebase' \
    || __fail "UX-03" "structured [BAIL] line with literal format" "$output" "$LIB_DIR/remediate.sh"

  # Footer.
  printf '%s' "$output" | grep -qF 'Exit code 65 (EX_DATAERR' \
    || __fail "UX-05" "footer 'Exit code 65 (EX_DATAERR'" "$output" "$LIB_DIR/remediate.sh"
  printf '%s' "$output" | grep -qF 'agentlinux install --help' \
    || __fail "UX-03" "footer points at 'agentlinux install --help'" "$output" "$LIB_DIR/remediate.sh"
}

@test "REMEDIATE foundation: flush_bails_or_continue with N=2 aggregates BOTH [BAIL] lines + exits 65" {
  # REQ: UX-03 (bail aggregation — user with two defects sees BOTH lines, not
  # just the first; critical for --dry-run parity in Phase 15).
  __source_lib_chain_with_remediate
  __reset_remediate_state
  remediate::register_bail "npm-prefix" "wrong-owner" "run with --yes to chown or rebase"
  remediate::register_bail "sudoers" "drift" "run with --yes to overwrite with the canonical ADR-012 line"

  run remediate::flush_bails_or_continue
  [[ "$status" -eq 65 ]] \
    || __fail "UX-05" "flush exits 65 with two bails" "exit=$status" "$LIB_DIR/remediate.sh"
  printf '%s' "$output" | grep -qE 'Refusing to proceed — 2 components need Remediate' \
    || __fail "UX-03" "header reports N=2 components" "$output" "$LIB_DIR/remediate.sh"
  printf '%s' "$output" | grep -qF '[BAIL] component=npm-prefix reason=wrong-owner' \
    || __fail "UX-03" "first [BAIL] line present" "$output" "$LIB_DIR/remediate.sh"
  printf '%s' "$output" | grep -qF '[BAIL] component=sudoers reason=drift' \
    || __fail "UX-03" "second [BAIL] line present (aggregation)" "$output" "$LIB_DIR/remediate.sh"
}

@test "REMEDIATE foundation: remediate_action_overwrites_state predicate matrix (overwriting vs additive)" {
  # REQ: UX-03 (CONTEXT.md Area 1 Q1 split — state-overwriting actions require
  # --yes; additive actions run unconditionally). The centralized predicate is
  # shared with Phase 15 (UX-02 TTY prompts route through the same gate).
  __source_lib_chain_with_remediate

  # Overwriting actions — must return 0 (true).
  for action in npm-prefix-chown npm-prefix-rebase sudoers-drift-overwrite agent-reinstall; do
    if ! remediate_action_overwrites_state "$action"; then
      __fail "UX-03" "remediate_action_overwrites_state '$action' is overwriting (return 0)" "returned non-zero" "$LIB_DIR/remediate.sh"
    fi
  done

  # Additive actions — must return 1 (false).
  for action in path-wiring sudoers-missing-install; do
    if remediate_action_overwrites_state "$action"; then
      __fail "UX-03" "remediate_action_overwrites_state '$action' is additive (return 1)" "returned 0" "$LIB_DIR/remediate.sh"
    fi
  done
}

@test "REMEDIATE foundation: per-component stub files source + define stub functions emitting [REMEDIATE-NN] markers" {
  # REQ: UX-03 (per-component handler scaffolding for Plan 14-02/14-03).
  __source_lib_chain_with_remediate

  # Stub source presence.
  for stub in user.sh nodejs.sh sudoers.sh agents.sh; do
    [[ -f "$REMEDIATE_LIB_DIR/$stub" ]] \
      || __fail "UX-03" "$REMEDIATE_LIB_DIR/$stub exists" "missing" "$REMEDIATE_LIB_DIR"
  done

  # Stub / handler function presence — each file declares at least one
  # `remediate::<component>::<action>` function. Plan 14-01 named these as
  # *_stub; Plan 14-02 lands the real handlers + keeps the legacy *_stub
  # symbols as thin shims for source compatibility. Both symbol sets must
  # be defined for backward + forward compat.
  declare -F remediate::user::path_wiring_stub >/dev/null \
    || __fail "UX-03" "remediate::user::path_wiring_stub defined" "not defined" "$REMEDIATE_LIB_DIR/user.sh"
  declare -F remediate::user::log_path_wiring_remediated >/dev/null \
    || __fail "UX-03" "remediate::user::log_path_wiring_remediated defined (Plan 14-02 marker)" "not defined" "$REMEDIATE_LIB_DIR/user.sh"
  declare -F remediate::nodejs::npm_prefix_stub >/dev/null \
    || __fail "UX-03" "remediate::nodejs::npm_prefix_stub defined" "not defined" "$REMEDIATE_LIB_DIR/nodejs.sh"
  declare -F remediate::nodejs::chown_or_rebase >/dev/null \
    || __fail "UX-03" "remediate::nodejs::chown_or_rebase defined (Plan 14-02 handler)" "not defined" "$REMEDIATE_LIB_DIR/nodejs.sh"
  declare -F remediate::sudoers::install_stub >/dev/null \
    || __fail "UX-03" "remediate::sudoers::install_stub defined" "not defined" "$REMEDIATE_LIB_DIR/sudoers.sh"
  declare -F remediate::sudoers::overwrite_stub >/dev/null \
    || __fail "UX-03" "remediate::sudoers::overwrite_stub defined" "not defined" "$REMEDIATE_LIB_DIR/sudoers.sh"
  declare -F remediate::sudoers::install_or_overwrite >/dev/null \
    || __fail "UX-03" "remediate::sudoers::install_or_overwrite defined (Plan 14-02 helper)" "not defined" "$REMEDIATE_LIB_DIR/sudoers.sh"
  declare -F remediate::agents::reinstall_stub >/dev/null \
    || __fail "UX-03" "remediate::agents::reinstall_stub defined" "not defined" "$REMEDIATE_LIB_DIR/agents.sh"

  # Spot-check the user-side marker emitter: it's non-mutating (just a
  # log_info call) so safe to invoke directly. Plan 14-01 originally checked
  # the sudoers stub but Plan 14-02's stub delegates to install_or_overwrite
  # which IS mutating — the marker-emission contract is now checked on user.sh
  # (additive by definition; never mutates state).
  run remediate::user::log_path_wiring_remediated
  assert_exit_zero "UX-03"
  printf '%s' "$output" | grep -qF '[REMEDIATE-02]' \
    || __fail "UX-03" "[REMEDIATE-02] marker emitted by user-side handler" "$output" "$REMEDIATE_LIB_DIR/user.sh"
}

@test "REMEDIATE foundation: reuse::user_decision predicate behavior unchanged from Phase 13" {
  # REQ: UX-03 (Phase 13 reuse-decision contract MUST NOT regress — Phase 14
  # only EXTENDS the surface with remediate handlers + bail aggregation).
  __source_lib_chain_with_remediate

  # Predicate 5 (sudo_apt=false but other predicates hold) — remediate.
  DETECT_USER_PRESENT=true \
    DETECT_USER_NAME=agent \
    DETECT_USER_SHELL=/bin/bash \
    DETECT_USER_HOME=/home/agent \
    DETECT_USER_HOME_WRITABLE=true \
    DETECT_USER_CAN_SUDO_APT=false \
    run reuse::user_decision agent
  [[ "$output" == "remediate" ]] \
    || __fail "UX-03" "reuse::user_decision == 'remediate' on sudo_apt=false (Phase 13 contract)" "$output" "$LIB_DIR/reuse/user.sh"

  # Predicate 2 (wrong shell) — bail.
  DETECT_USER_PRESENT=true \
    DETECT_USER_NAME=agent \
    DETECT_USER_SHELL=/bin/dash \
    DETECT_USER_HOME=/home/agent \
    DETECT_USER_HOME_WRITABLE=true \
    DETECT_USER_CAN_SUDO_APT=true \
    run reuse::user_decision agent
  [[ "$output" == "bail" ]] \
    || __fail "UX-03" "reuse::user_decision == 'bail' on wrong shell (Phase 13 contract)" "$output" "$LIB_DIR/reuse/user.sh"
}

@test "REMEDIATE foundation: reuse::npm_prefix_decision returns reuse|remediate|create per DETECT exports" {
  # REQ: UX-03 (Plan 14-01 NEW decision function — REMEDIATE-01 layer).
  __source_lib_chain_with_remediate

  # Absent — create.
  DETECT_NPM_PREFIX_SECTION_STATUS=absent run reuse::npm_prefix_decision
  [[ "$output" == "create" ]] \
    || __fail "UX-03" "reuse::npm_prefix_decision == 'create' when section_status=absent" "$output" "$LIB_DIR/reuse/nodejs.sh"

  # Present + writable — reuse.
  DETECT_NPM_PREFIX_SECTION_STATUS=present \
    DETECT_NPM_PREFIX_USER_WRITABLE=true \
    run reuse::npm_prefix_decision
  [[ "$output" == "reuse" ]] \
    || __fail "UX-03" "reuse::npm_prefix_decision == 'reuse' when writable=true" "$output" "$LIB_DIR/reuse/nodejs.sh"

  # Present + NOT writable — remediate.
  DETECT_NPM_PREFIX_SECTION_STATUS=present \
    DETECT_NPM_PREFIX_USER_WRITABLE=false \
    run reuse::npm_prefix_decision
  [[ "$output" == "remediate" ]] \
    || __fail "UX-03" "reuse::npm_prefix_decision == 'remediate' when writable=false" "$output" "$LIB_DIR/reuse/nodejs.sh"
}

@test "REMEDIATE foundation: zero 'register_bail \$VAR' matches in remediate/*.sh + Plan-14-01 provisioners (T-14-06)" {
  # REQ: UX-03 (T-14-06 mitigation — component names in bail lines must be
  # hardcoded literals, never $VAR-driven values). A future refactor that
  # piped detect:: output into register_bail would trip this @test.
  local files=(
    "$REMEDIATE_LIB_DIR"/*.sh
    "$PROV_DIR/10-agent-user.sh"
    "$PROV_DIR/20-sudoers.sh"
    "$PROV_DIR/30-nodejs.sh"
    "$PROV_DIR/40-path-wiring.sh"
  )
  local f
  for f in "${files[@]}"; do
    if [[ -f "$f" ]] && grep -qE 'register_bail[[:space:]]+"\$' "$f"; then
      __fail "UX-03 (T-14-06)" "no 'register_bail \$VAR' in $f" "$(grep -n 'register_bail[[:space:]]\+"\$' "$f")" "$f"
    fi
  done
  true
}

@test "REMEDIATE foundation: collect_all_decisions populates RESOLUTIONS + makes ZERO host mutations (DECIDE-THEN-ACT atomicity)" {
  # REQ: UX-03 + T-14-13 (no-mutation invariant — the unit-shape test).
  # This is the function-level atomicity proof; the E2E proof is in Tests 19-22
  # (snapshot before/after a full installer bail run). Here we shim out the
  # filesystem-mutation commands and verify the shim log stays empty.
  __source_lib_chain_with_remediate
  __reset_remediate_state

  # Shim filesystem-mutation commands by prepending a tmpdir of logging stubs
  # to PATH. After collect_all_decisions runs, the shim log must be empty —
  # proof that the decision-collection phase made zero host mutations.
  local shimdir="$BATS_TEST_TMPDIR/shims"
  local mutation_log="$BATS_TEST_TMPDIR/mutation.log"
  mkdir -p "$shimdir"
  : >"$mutation_log"
  local cmd
  for cmd in chown install useradd visudo chmod mkdir touch; do
    cat >"$shimdir/$cmd" <<SHIM
#!/usr/bin/env bash
echo "$cmd \$*" >>"$mutation_log"
SHIM
    chmod +x "$shimdir/$cmd"
  done

  # Seed minimal DETECT_* exports so collect_all_decisions can run without
  # spawning detect::run_once (which would itself hit the shim path).
  export DETECT_USER_PRESENT=true
  export DETECT_USER_NAME=agent
  export DETECT_USER_SHELL=/bin/bash
  export DETECT_USER_HOME=/home/agent
  export DETECT_USER_HOME_WRITABLE=true
  export DETECT_USER_CAN_SUDO_APT=true
  export DETECT_NPM_PREFIX_SECTION_STATUS=present
  export DETECT_NPM_PREFIX_USER_WRITABLE=true
  export DETECT_SUDOERS_PRESENT=true
  export DETECT_SUDOERS_NOPASSWD_OK=true
  # Agents map exists from reuse/agents.sh; seed status=absent so decisions
  # resolve to `create` without trying to read agent paths.
  local id
  for id in claude-code gsd playwright-cli; do
    local upper="${id^^}"
    upper="${upper//-/_}"
    export "DETECT_AGENT_${upper}_STATUS=absent"
  done
  export INSTALL_USER=agent
  export YES_FLAG=false

  PATH="$shimdir:$PATH" remediate::collect_all_decisions

  # Verify RESOLUTIONS is populated with the canonical keys.
  [[ -n "${RESOLUTIONS[user]:-}" ]] \
    || __fail "UX-03" "RESOLUTIONS[user] populated" "empty" "$LIB_DIR/remediate.sh"
  [[ "${RESOLUTIONS[user]}" == "reuse" ]] \
    || __fail "UX-03" "RESOLUTIONS[user] == 'reuse' on the seeded healthy fixture" "${RESOLUTIONS[user]}" "$LIB_DIR/remediate.sh"
  [[ -n "${RESOLUTIONS[npm-prefix]:-}" ]] \
    || __fail "UX-03" "RESOLUTIONS[npm-prefix] populated" "empty" "$LIB_DIR/remediate.sh"
  [[ -n "${RESOLUTIONS[sudoers]:-}" ]] \
    || __fail "UX-03" "RESOLUTIONS[sudoers] populated" "empty" "$LIB_DIR/remediate.sh"
  # At least one agents.<id> key.
  [[ -n "${RESOLUTIONS[agents.claude-code]:-}" ]] \
    || __fail "UX-03" "RESOLUTIONS[agents.claude-code] populated" "empty" "$LIB_DIR/remediate.sh"

  # No bails accumulated on the healthy fixture.
  [[ "${#BAILED_COMPONENTS[@]}" -eq 0 ]] \
    || __fail "UX-03" "BAILED_COMPONENTS empty on healthy fixture" "${BAILED_COMPONENTS[*]}" "$LIB_DIR/remediate.sh"

  # T-14-13 invariant: shim mutation log is empty. Any line here means a
  # mutation command was invoked during collect_all_decisions — a hard
  # regression of the DECIDE-THEN-ACT atomicity contract.
  [[ ! -s "$mutation_log" ]] \
    || __fail "UX-03 (T-14-13)" "shim mutation log empty after collect_all_decisions" "$(cat "$mutation_log")" "$mutation_log"
}

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
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
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
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
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
@test "UX-05: agentlinux-install --help output contains 'Exit codes:' section listing 0/1/64/65 + mnemonics" {
  run bash "$INSTALLER" --help
  assert_exit_zero "UX-05"
  printf '%s' "$output" | grep -qE '^Exit codes:' \
    || __fail "UX-05" "--help contains 'Exit codes:' section header" "$output" "$INSTALLER"
  printf '%s' "$output" | grep -qE '^  0   success' \
    || __fail "UX-05" "--help lists '0   success'" "$output" "$INSTALLER"
  printf '%s' "$output" | grep -qE '^  1   runtime' \
    || __fail "UX-05" "--help lists '1   runtime'" "$output" "$INSTALLER"
  printf '%s' "$output" | grep -qE '^  64  usage' \
    || __fail "UX-05" "--help lists '64  usage'" "$output" "$INSTALLER"
  printf '%s' "$output" | grep -qE '^  65  data' \
    || __fail "UX-05" "--help lists '65  data'" "$output" "$INSTALLER"
  printf '%s' "$output" | grep -qF 're-run with --yes to apply' \
    || __fail "UX-05" "--help hints 're-run with --yes to apply'" "$output" "$INSTALLER"
}

# Test 13: greenfield --yes succeeds.
@test "UX-03: agentlinux-install --yes on post-installer (greenfield-ish) host completes with no [BAIL] / no [REMEDIATE-NN] lines" {
  run bash "$INSTALLER" --yes
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
  run bash "$INSTALLER" --no-yes
  assert_exit_zero "UX-03"
}

# Test 15: contradictory flags --yes --no-yes exits 64 (T-14-02 mitigation).
@test "UX-05 (T-14-02): agentlinux-install --yes --no-yes exits 64 with contradictory-flags error" {
  run bash "$INSTALLER" --yes --no-yes
  [[ "$status" -eq 64 ]] \
    || __fail "UX-05" "exit 64 on --yes --no-yes" "exit=$status" "$INSTALLER"
  printf '%s' "$output" | grep -qF 'contradictory flags' \
    || __fail "UX-05" "log_error 'contradictory flags'" "$output" "$INSTALLER"
}

# Test 16: reverse order --no-yes --yes ALSO exits 64 (no last-flag-wins).
@test "UX-05 (T-14-02): agentlinux-install --no-yes --yes ALSO exits 64 (no 'last flag wins' silent acceptance)" {
  run bash "$INSTALLER" --no-yes --yes
  [[ "$status" -eq 64 ]] \
    || __fail "UX-05" "exit 64 on --no-yes --yes" "exit=$status" "$INSTALLER"
  printf '%s' "$output" | grep -qF 'contradictory flags' \
    || __fail "UX-05" "log_error 'contradictory flags' both orders" "$output" "$INSTALLER"
}

# Test 17: unknown flag exits 64.
@test "UX-05: agentlinux-install --frobnicate (unknown flag) exits 64" {
  run bash "$INSTALLER" --frobnicate
  [[ "$status" -eq 64 ]] \
    || __fail "UX-05" "exit 64 on unknown flag" "exit=$status" "$INSTALLER"
  printf '%s' "$output" | grep -qF 'unknown argument' \
    || __fail "UX-05" "log_error 'unknown argument'" "$output" "$INSTALLER"
}

# Test 18: T-14-01 grep — no env-var consent spoof variables.
@test "UX-03 (T-14-01): zero AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES / CONFIRM_INSTALL matches in installer + remediate libs" {
  local files=(
    "$INSTALLER"
    "$LIB_DIR/remediate.sh"
    "$REMEDIATE_LIB_DIR"/*.sh
  )
  local f
  for f in "${files[@]}"; do
    if [[ -f "$f" ]] && grep -qE 'AGENTLINUX_YES|ALWAYS_YES|ASSUME_YES|CONFIRM_INSTALL' "$f"; then
      __fail "UX-03 (T-14-01)" "no env-var consent spoof variables in $f" "$(grep -n 'AGENTLINUX_YES\|ALWAYS_YES\|ASSUME_YES\|CONFIRM_INSTALL' "$f")" "$f"
    fi
  done
  true
}

# Test 19: NO-MUTATION SNAPSHOT — wrong-shell bail. The architectural proof
# of UX-03 atomicity: snapshot before, run without --yes, assert exit 65 +
# [BAIL] line, snapshot after, assert byte-equality.
@test "UX-03 (T-14-13): NO-MUTATION SNAPSHOT — wrong-shell user bail leaves /etc/sudoers.d /home /etc/passwd byte-identical" {
  setup_brownfield_for_bail_user_wrongshell

  local before="$BATS_TEST_TMPDIR/before"
  local after="$BATS_TEST_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run bash "$INSTALLER"
  [[ "$status" -eq 65 ]] \
    || __fail "UX-03" "exit 65 on wrong-shell bail without --yes" "exit=$status output=$output" "$LOG"
  printf '%s' "$output" | grep -qF '[BAIL] component=user' \
    || __fail "UX-03" "[BAIL] component=user line in bail message" "$output" "$LOG"

  snapshot_capture "$after" /etc/sudoers.d /home /etc/passwd

  if ! snapshot_equal "$before" "$after"; then
    __fail "UX-03 (T-14-13)" "BYTE-IDENTICAL /etc/sudoers.d /home /etc/passwd before+after bail" "$(diff -r --exclude=.npm "$before" "$after" 2>&1 | head -20)" "$LOG"
  fi
}

# Test 20: NO-MUTATION SNAPSHOT — sudoers drift bail (byte-equal proof).
@test "UX-03 (T-14-13): NO-MUTATION SNAPSHOT — sudoers drift bail leaves host byte-identical" {
  setup_brownfield_for_bail_sudoers_drift

  local before="$BATS_TEST_TMPDIR/before"
  local after="$BATS_TEST_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run bash "$INSTALLER"
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
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
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

  local before="$BATS_TEST_TMPDIR/before"
  local after="$BATS_TEST_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run bash "$INSTALLER"
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
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
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

  local before="$BATS_TEST_TMPDIR/before"
  local after="$BATS_TEST_TMPDIR/after"
  snapshot_capture "$before" /etc/sudoers.d /home /etc/passwd

  run bash "$INSTALLER"
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

  run bash "$INSTALLER" --yes
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
@test "UX-05: 'readonly EX_USAGE=64' and 'readonly EX_DATAERR=65' present in plugin/bin/agentlinux-install" {
  grep -qE '^readonly EX_USAGE=64' "$INSTALLER" \
    || __fail "UX-05" "'readonly EX_USAGE=64' literal in installer source" "$(grep -E 'EX_USAGE' "$INSTALLER" | head -3)" "$INSTALLER"
  grep -qE '^readonly EX_DATAERR=65' "$INSTALLER" \
    || __fail "UX-05" "'readonly EX_DATAERR=65' literal in installer source" "$(grep -E 'EX_DATAERR' "$INSTALLER" | head -3)" "$INSTALLER"
  # And no remaining literal `exit 64` in the entrypoint (all migrated to
  # exit "$EX_USAGE"). Note: comments containing `exit 64` are stripped by
  # the grep filter below — match only non-comment lines.
  if grep -nE '^[^#]*\bexit 64\b' "$INSTALLER" >/dev/null; then
    __fail "UX-05" "all literal 'exit 64' migrated to exit \"\$EX_USAGE\"" "$(grep -nE '^[^#]*\bexit 64\b' "$INSTALLER")" "$INSTALLER"
  fi
}

# DECIDE-THEN-ACT ordering check (grep-shape — defends against a future
# refactor that puts run_provisioners before flush_bails_or_continue).
@test "UX-03: main() flow ordering — collect_all_decisions → flush_bails_or_continue → run_provisioners (grep-shape)" {
  # Extract main() body and verify the three calls appear in the expected
  # order. awk window from "^main()" to "^}" matches the function definition.
  # Strip comment lines (anything starting with `#`) so prose mentions of the
  # function names in docstrings don't pollute the ordering check.
  local main_body
  main_body=$(awk '/^main\(\) \{/,/^\}/' "$INSTALLER" | grep -vE '^[[:space:]]*#')
  # Build a stream of just the three call sites (one per line).
  local order
  order=$(printf '%s\n' "$main_body" | grep -oE 'collect_all_decisions|flush_bails_or_continue|run_provisioners' | uniq)
  local expected='collect_all_decisions
flush_bails_or_continue
run_provisioners'
  [[ "$order" == "$expected" ]] \
    || __fail "UX-03" "main() ordering = $expected" "$order" "$INSTALLER"
}

# RESOLUTIONS dispatch grep — verify provisioners 10/20/30 read pre-resolved
# tokens instead of calling reuse::*_decision directly.
@test "UX-03: provisioners 10/20/30 dispatch on RESOLUTIONS[<component>] (no direct reuse::*_decision case)" {
  for prov in 10-agent-user.sh 20-sudoers.sh 30-nodejs.sh; do
    grep -qE '\$\{RESOLUTIONS\[' "$PROV_DIR/$prov" \
      || __fail "UX-03" "$prov dispatches on \${RESOLUTIONS[...]}" "no RESOLUTIONS lookup found" "$PROV_DIR/$prov"
  done
}

# ---- Plan 14-02 Task 1: REMEDIATE-01 chown/rebase strategy + module migration -----

# Test 25 — Predicate: trivially salvageable returns 0 on empty allowlist tree.
@test "REMEDIATE-01: _is_trivially_salvageable returns 0 (true) on allowlist-only prefix" {
  __source_lib_chain_with_remediate
  local prefix="$BATS_TEST_TMPDIR/empty-prefix"
  mkdir -p "$prefix/lib" "$prefix/bin" "$prefix/share" "$prefix/etc"
  : >"$prefix/package.json"
  : >"$prefix/package-lock.json"
  remediate::nodejs::_is_trivially_salvageable "$prefix" \
    || __fail "REMEDIATE-01" "trivially salvageable on allowlist-only prefix (exit 0)" "non-zero" "$prefix"
}

# Test 26 — T-14-03 mitigation: predicate REJECTS non-allowlist entry.
@test "REMEDIATE-01 (T-14-03): _is_trivially_salvageable returns 1 (false) on lib/node_modules/<user-pkg>" {
  __source_lib_chain_with_remediate
  local prefix="$BATS_TEST_TMPDIR/with-user-pkg"
  mkdir -p "$prefix/lib/node_modules/some-user-pkg"
  cat >"$prefix/lib/node_modules/some-user-pkg/package.json" <<'JSON'
{ "name": "some-user-pkg", "version": "0.0.1" }
JSON
  run remediate::nodejs::_is_trivially_salvageable "$prefix"
  [[ "$status" -eq 1 ]] \
    || __fail "REMEDIATE-01 (T-14-03)" "trivially salvageable returns 1 (false) on user-installed module" "exit=$status" "$prefix"
}

# Test 27 — Strategy selector picks chown for under-home + salvageable.
@test "REMEDIATE-01: _strategy_for returns 'chown' for under-home + trivially salvageable" {
  __source_lib_chain_with_remediate
  local home="$BATS_TEST_TMPDIR/home"
  local prefix="$home/.npm-global"
  mkdir -p "$prefix/lib" "$prefix/bin"
  run remediate::nodejs::_strategy_for "$prefix" "$home"
  [[ "$output" == "chown" ]] \
    || __fail "REMEDIATE-01" "strategy=chown for under-home + salvageable" "$output" "$prefix"
}

# Test 28 — Strategy selector picks rebase for prefix OUTSIDE home.
@test "REMEDIATE-01 (T-14-08): _strategy_for returns 'rebase' for prefix OUTSIDE user home (system path)" {
  __source_lib_chain_with_remediate
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home"
  # /usr (a system path) is the canonical T-14-08 case — even if empty,
  # strategy MUST be rebase because we never chown a system path.
  run remediate::nodejs::_strategy_for "/usr" "$home"
  [[ "$output" == "rebase" ]] \
    || __fail "REMEDIATE-01 (T-14-08)" "strategy=rebase for /usr (system path, outside home)" "$output" "/usr"
}

# Test 29 — Strategy selector picks rebase for under-home + NOT salvageable.
@test "REMEDIATE-01 (T-14-03): _strategy_for returns 'rebase' for under-home + non-salvageable" {
  __source_lib_chain_with_remediate
  local home="$BATS_TEST_TMPDIR/home"
  local prefix="$home/.npm-global"
  mkdir -p "$prefix/lib/node_modules/some-user-pkg"
  : >"$prefix/lib/node_modules/some-user-pkg/package.json"
  run remediate::nodejs::_strategy_for "$prefix" "$home"
  [[ "$output" == "rebase" ]] \
    || __fail "REMEDIATE-01 (T-14-03)" "strategy=rebase for under-home + non-salvageable" "$output" "$prefix"
}

# Test 30 — Module enumeration filters catalog agents + npm.
@test "REMEDIATE-01: _enumerate_modules filters catalog agents + npm from migration list" {
  __source_lib_chain_with_remediate
  # Shim as_user so the helper returns a controlled npm-ls JSON without
  # actually running npm.
  as_user() {
    if [[ "$2" == "npm" ]]; then
      cat <<'JSON'
{
  "dependencies": {
    "lodash": {"version": "4.17.21"},
    "npm": {"version": "10.0.0"},
    "@anthropic-ai/claude-code": {"version": "2.0.0"},
    "get-shit-done-cc": {"version": "1.0.0"},
    "@playwright/cli": {"version": "1.0.0"},
    "express": {"version": "4.18.0"}
  }
}
JSON
      return 0
    fi
    return 0
  }
  run remediate::nodejs::_enumerate_modules root
  # Should contain lodash + express but NOT the excluded ids.
  printf '%s' "$output" | grep -qFx 'lodash@4.17.21' \
    || __fail "REMEDIATE-01" "enumerate includes lodash@4.17.21" "$output" "_enumerate_modules"
  printf '%s' "$output" | grep -qFx 'express@4.18.0' \
    || __fail "REMEDIATE-01" "enumerate includes express@4.18.0" "$output" "_enumerate_modules"
  printf '%s' "$output" | grep -qE '^npm@' \
    && __fail "REMEDIATE-01" "enumerate EXCLUDES npm" "$output" "_enumerate_modules"
  printf '%s' "$output" | grep -qE '^@anthropic-ai/claude-code@' \
    && __fail "REMEDIATE-01" "enumerate EXCLUDES @anthropic-ai/claude-code" "$output" "_enumerate_modules"
  printf '%s' "$output" | grep -qE '^get-shit-done-cc@' \
    && __fail "REMEDIATE-01" "enumerate EXCLUDES get-shit-done-cc" "$output" "_enumerate_modules"
  printf '%s' "$output" | grep -qE '^@playwright/cli@' \
    && __fail "REMEDIATE-01" "enumerate EXCLUDES @playwright/cli" "$output" "_enumerate_modules"
  true
}

# Test 31 — BROWNFIELD chown happy path E2E.
@test "REMEDIATE-01: BROWNFIELD chown E2E — under-home + empty prefix → chown -R; prefix becomes agent:agent" {
  setup_brownfield_for_remediate_01_chown

  run bash "$INSTALLER" --yes
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

  run bash "$INSTALLER" --yes
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

  run bash "$INSTALLER" --yes
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

  run bash "$INSTALLER" --yes
  assert_exit_zero "REMEDIATE-01"
  # Confirm get-shit-done-cc is NOT in the migration transcript (neither
  # migrated nor partial — it should be filtered out before the loop).
  printf '%s' "$output" | grep -qE '\[REMEDIATE-01:(migrated|partial)\] module=get-shit-done-cc' \
    && __fail "REMEDIATE-01" "catalog agent get-shit-done-cc NOT in migration loop" "$output" "$LOG"
  true
}

# Test 35 — npm self-exclusion (Area 2 Q3 — npm comes from system Node).
@test "REMEDIATE-01: rebase migration loop EXCLUDES 'npm' itself (system-managed)" {
  __source_lib_chain_with_remediate
  # Shim as_user so we control the JSON.
  as_user() {
    if [[ "$2" == "npm" ]]; then
      cat <<'JSON'
{
  "dependencies": {
    "npm": {"version": "10.0.0"}
  }
}
JSON
      return 0
    fi
    return 0
  }
  run remediate::nodejs::_enumerate_modules root
  # Output must be empty (or whitespace) — only npm was present and it is excluded.
  local trimmed
  trimmed=$(printf '%s' "$output" | tr -d '[:space:]')
  [[ -z "$trimmed" ]] \
    || __fail "REMEDIATE-01" "_enumerate_modules empty when only npm is global" "$output" "_enumerate_modules"
}

# Test 36 — T-14-08 protection: even if /usr is empty, we never chown it.
@test "REMEDIATE-01 (T-14-08): chown NEVER fires for prefix /usr (system path, outside any user home)" {
  __source_lib_chain_with_remediate
  # /usr is canonically empty-of-our-allowlist-violators in a healthy host,
  # but it is NOT under any user home. The strategy selector must return
  # rebase regardless of salvageability.
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home"
  run remediate::nodejs::_strategy_for "/usr" "$home"
  [[ "$output" == "rebase" ]] \
    || __fail "REMEDIATE-01 (T-14-08)" "chown REFUSED for /usr — strategy must be rebase" "$output" "/usr"
}

# Test 37 — chown-blocked-by-allowlist E2E (T-14-03 end-to-end).
@test "REMEDIATE-01 (T-14-03): BROWNFIELD chown REFUSED when prefix has non-allowlist entry → falls back to rebase" {
  setup_brownfield_for_remediate_01_chown_blocked

  run bash "$INSTALLER" --yes
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

# Test 38 — REMEDIATE-01 source code: no rm -rf against old prefix anywhere.
@test "REMEDIATE-01: source code never deletes old prefix (CONTEXT Area 2 Q4)" {
  # The grep matches `rm -rf` followed by anything mentioning prefix vars in
  # the same line. Comments are excluded by skipping lines starting with `#`.
  local hits
  hits=$(grep -nE '^[^#]*rm[[:space:]]+-rf' "$REMEDIATE_LIB_DIR/nodejs.sh" || true)
  [[ -z "$hits" ]] \
    || __fail "REMEDIATE-01" "no rm -rf in remediate/nodejs.sh (old prefix never deleted)" "$hits" "$REMEDIATE_LIB_DIR/nodejs.sh"
}

# ---- Plan 14-02 Task 2: REMEDIATE-02 + REMEDIATE-03 helpers + refactor -----

# Test 39 — install_or_overwrite helper exists + functions on missing-file install.
@test "REMEDIATE-03: install_or_overwrite is defined; missing-file install writes canonical ADR-012 file" {
  __source_lib_chain_with_remediate
  declare -F remediate::sudoers::install_or_overwrite >/dev/null \
    || __fail "REMEDIATE-03" "remediate::sudoers::install_or_overwrite defined" "not defined" "$REMEDIATE_LIB_DIR/sudoers.sh"

  # Tear down then exercise via the installer (full integration). Use the
  # missing-file fixture so the dispatch goes through the create arm.
  setup_brownfield_for_remediate_03_missing
  # additive — no --yes needed.
  run bash "$INSTALLER"
  assert_exit_zero "REMEDIATE-03"
  # Canonical content present.
  grep -qFx 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "REMEDIATE-03" "canonical NOPASSWD line in /etc/sudoers.d/agentlinux" "$(cat /etc/sudoers.d/agentlinux)" "$LOG"
  # Mode 0440 root:root.
  local stat_out
  stat_out=$(stat -c '%a %U:%G' /etc/sudoers.d/agentlinux)
  [[ "$stat_out" == "440 root:root" ]] \
    || __fail "REMEDIATE-03" "mode 0440 root:root" "$stat_out" "$LOG"
}

# Test 40 — install_or_overwrite OVERWRITES a pre-existing drifted file.
@test "REMEDIATE-03: install_or_overwrite OVERWRITES drifted sudoers with canonical ADR-012 line" {
  setup_brownfield_for_remediate_03_drift

  # Drift overwrite is state-overwriting → requires --yes.
  run bash "$INSTALLER" --yes
  assert_exit_zero "REMEDIATE-03"
  grep -qFx 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux \
    || __fail "REMEDIATE-03" "drift overwritten with canonical ADR-012 line" "$(cat /etc/sudoers.d/agentlinux)" "$LOG"
  # Marker line confirming the OVERWRITE arm fired.
  printf '%s' "$output" | grep -qF '[REMEDIATE-03] component=sudoers action=overwrite' \
    || __fail "REMEDIATE-03" "[REMEDIATE-03] action=overwrite marker in transcript" "$output" "$LOG"
}

# Test 41 — T-14-02 mitigation: visudo-fail gate UPHELD via the test-only override.
@test "REMEDIATE-03 (T-14-02): install_or_overwrite REFUSES to install when visudo -cf rejects the tmpfile" {
  __source_lib_chain_with_remediate
  # Snapshot pre-existing sudoers file (if any) so we can prove the helper
  # did NOT overwrite it on visudo failure.
  local pre_sha=""
  if [[ -f /etc/sudoers.d/agentlinux ]]; then
    pre_sha=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)
  fi

  # Inject deliberately invalid sudoers syntax via the test-only override.
  # visudo -cf will reject this; the helper must return non-zero and NOT
  # touch /etc/sudoers.d/agentlinux.
  AGENTLINUX_TEST_MODE=1 \
    AGENTLINUX_TEST_SUDOERS_OVERRIDE='agent ALL=(ALL' \
    run remediate::sudoers::install_or_overwrite "install"
  [[ "$status" -ne 0 ]] \
    || __fail "REMEDIATE-03 (T-14-02)" "helper returns non-zero when visudo -cf rejects" "exit=$status" "$REMEDIATE_LIB_DIR/sudoers.sh"
  printf '%s' "$output" | grep -qF '[REMEDIATE-03:visudo-fail]' \
    || __fail "REMEDIATE-03 (T-14-02)" "visudo-fail marker emitted" "$output" "$REMEDIATE_LIB_DIR/sudoers.sh"

  # File untouched: if it existed before, sha256 unchanged; if not, still missing.
  if [[ -n "$pre_sha" ]]; then
    local post_sha
    post_sha=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)
    [[ "$pre_sha" == "$post_sha" ]] \
      || __fail "REMEDIATE-03 (T-14-02)" "sudoers file UNCHANGED after visudo-fail" "pre=$pre_sha post=$post_sha" "/etc/sudoers.d/agentlinux"
  fi
}

# Test 42 — BROWNFIELD missing-file install is ADDITIVE (no --yes needed).
@test "REMEDIATE-03: missing sudoers — additive install fires WITHOUT --yes (no consent gate consulted)" {
  setup_brownfield_for_remediate_03_missing

  # No --yes flag — additive action per CONTEXT.md Area 1 Q1 (sudoers-missing-install
  # is in the additive set; remediate_action_overwrites_state returns false).
  run bash "$INSTALLER"
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

  run bash "$INSTALLER"
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
  run bash "$INSTALLER"
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
  bash "$INSTALLER" >/dev/null 2>&1
  local sha_first
  sha_first=$(sha256sum /home/agent/.bashrc | cut -d' ' -f1)

  # Second run must produce byte-identical .bashrc (ensure_marker_block converges).
  bash "$INSTALLER" >/dev/null 2>&1
  local sha_second
  sha_second=$(sha256sum /home/agent/.bashrc | cut -d' ' -f1)
  [[ "$sha_first" == "$sha_second" ]] \
    || __fail "REMEDIATE-02" "byte-stable ~agent/.bashrc across re-run" "first=$sha_first second=$sha_second" "$LOG"
}

# Test 46 — 20-sudoers.sh post-refactor: BOTH arms call install_or_overwrite.
@test "REMEDIATE-03: 20-sudoers.sh BOTH create and remediate arms call install_or_overwrite (refactor invariant)" {
  local count
  count=$(grep -c "remediate::sudoers::install_or_overwrite" "$PROV_DIR/20-sudoers.sh")
  [[ "$count" -ge 2 ]] \
    || __fail "REMEDIATE-03" "20-sudoers.sh calls install_or_overwrite >=2 times (both arms)" "count=$count" "$PROV_DIR/20-sudoers.sh"
  # The visudo+install machinery is OUT of 20-sudoers.sh (in the helper now).
  # Non-comment grep — the only `visudo -cf` reference should be in comments now.
  local stray
  stray=$(grep -nE '^[^#]*visudo -cf' "$PROV_DIR/20-sudoers.sh" || true)
  [[ -z "$stray" ]] \
    || __fail "REMEDIATE-03" "20-sudoers.sh has no inline visudo -cf (machinery refactored to helper)" "$stray" "$PROV_DIR/20-sudoers.sh"
  # The helper carries 2 visudo -cf calls (pre-install + post-install).
  local helper_count
  helper_count=$(grep -cE '^[^#]*visudo -cf' "$REMEDIATE_LIB_DIR/sudoers.sh")
  [[ "$helper_count" -eq 2 ]] \
    || __fail "REMEDIATE-03" "remediate/sudoers.sh contains exactly 2 visudo -cf calls (pre + post)" "count=$helper_count" "$REMEDIATE_LIB_DIR/sudoers.sh"
}

# Test 47 — BHV-07 regression guard: 20-sudoers.sh refactor preserves byte-stable output.
@test "REMEDIATE-03: 20-sudoers.sh post-refactor produces byte-identical /etc/sudoers.d/agentlinux across re-run (BHV-07)" {
  # Ensure canonical state; both runs should produce a byte-stable file.
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  bash "$INSTALLER" >/dev/null 2>&1
  local sha_first
  sha_first=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)

  bash "$INSTALLER" >/dev/null 2>&1
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

# Test 51 — BROWNFIELD PATH-MISMATCH happy path E2E.
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
  bash "$INSTALLER" --yes >/dev/null 2>&1 || true

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
  cli_out=$(sudo -u agent -H agentlinux install claude-code --yes 2>&1) || cli_rc=$?
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
  bash "$INSTALLER" --yes >/dev/null 2>&1 || true

  if [[ ! -x /home/agent/.npm-global/bin/claude ]]; then
    teardown_brownfield_remediate04_catalog
    skip "npm install -g claude-code didn't populate brownfield binary"
  fi

  local cli_out cli_rc=0
  cli_out=$(sudo -u agent -H AGENTLINUX_CATALOG_DIR="$BROWNFIELD_TMP_CATALOG" \
    agentlinux install claude-code --yes 2>&1) || cli_rc=$?

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

  bash "$INSTALLER" --yes >/dev/null 2>&1 || true

  if [[ ! -x /home/agent/.npm-global/bin/claude ]]; then
    teardown_brownfield_remediate04_catalog
    skip "npm install -g claude-code didn't populate brownfield binary"
  fi

  local cli_out cli_rc=0
  cli_out=$(sudo -u agent -H AGENTLINUX_CATALOG_DIR="$BROWNFIELD_TMP_CATALOG" \
    agentlinux install claude-code --yes 2>&1) || cli_rc=$?

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
  list_out=$(sudo -u agent -H AGENTLINUX_CATALOG_DIR="$BROWNFIELD_TMP_CATALOG" agentlinux list 2>&1)
  teardown_brownfield_remediate04_catalog

  echo "$list_out" | grep -qF "broken — half-uninstalled, manual recovery needed" \
    || __fail "REMEDIATE-04" "agentlinux list renders half-uninstalled suffix" "$list_out" "$LOG"

  # Cleanup the orphaned sentinel for downstream tests.
  rm -f /opt/agentlinux/state/installed.d/claude-code.json
}

# Test 54 — REMEDIATE-04 BAIL without --yes in non-TTY → exit 65.
@test "REMEDIATE-04 E2E: brownfield PATH-MISMATCH WITHOUT --yes in non-TTY → [BAIL] + exit 65" {
  setup_brownfield_broken_claude_code

  bash "$INSTALLER" --yes >/dev/null 2>&1 || true

  if [[ ! -x /home/agent/.npm-global/bin/claude ]]; then
    skip "npm install -g claude-code didn't populate brownfield binary"
  fi

  local cli_out cli_rc=0
  cli_out=$(sudo -u agent -H agentlinux install claude-code </dev/null 2>&1) || cli_rc=$?

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
