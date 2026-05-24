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

  # Stub function presence — each file declares at least one
  # `remediate::<component>::<action>` function.
  declare -F remediate::user::path_wiring_stub >/dev/null \
    || __fail "UX-03" "remediate::user::path_wiring_stub defined" "not defined" "$REMEDIATE_LIB_DIR/user.sh"
  declare -F remediate::nodejs::npm_prefix_stub >/dev/null \
    || __fail "UX-03" "remediate::nodejs::npm_prefix_stub defined" "not defined" "$REMEDIATE_LIB_DIR/nodejs.sh"
  declare -F remediate::sudoers::install_stub >/dev/null \
    || __fail "UX-03" "remediate::sudoers::install_stub defined" "not defined" "$REMEDIATE_LIB_DIR/sudoers.sh"
  declare -F remediate::sudoers::overwrite_stub >/dev/null \
    || __fail "UX-03" "remediate::sudoers::overwrite_stub defined" "not defined" "$REMEDIATE_LIB_DIR/sudoers.sh"
  declare -F remediate::agents::reinstall_stub >/dev/null \
    || __fail "UX-03" "remediate::agents::reinstall_stub defined" "not defined" "$REMEDIATE_LIB_DIR/agents.sh"

  # Stub emits a [REMEDIATE-NN] marker line via log_info. Spot-check sudoers.
  run remediate::sudoers::overwrite_stub
  assert_exit_zero "UX-03"
  printf '%s' "$output" | grep -qF '[REMEDIATE-03] component=sudoers action=stub' \
    || __fail "UX-03" "[REMEDIATE-03] marker emitted by sudoers stub" "$output" "$REMEDIATE_LIB_DIR/sudoers.sh"
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
