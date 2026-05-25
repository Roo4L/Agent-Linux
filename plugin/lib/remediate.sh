#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate.sh — remediate-decision orchestrator + DECIDE-THEN-ACT
# policy gate (Phase 14, Plan 14-01).
#
# Sourced by plugin/bin/agentlinux-install AFTER plugin/lib/reuse.sh (which
# itself is sourced AFTER plugin/lib/detect.sh + detect::run_once). This file
# owns the bail-aggregation policy gate AND the DECIDE-THEN-ACT orchestration
# that lets the Phase 14 contract enforce UX-03's "non-TTY without --yes never
# overwrites user state" guarantee atomically.
#
# Per CONTEXT.md Area 1:
#   Q1 (--yes scope): state-overwriting Remediates only — additive paths
#       (PATH wiring, missing-file sudoers install) run unconditionally.
#   Q2 ([BAIL] line format): LOCKED at
#         [BAIL] component=<name> reason=<token> hint=<short message>
#       The header + footer wrap the per-component lines.
#   Q3 (exit code mapping): 64 EX_USAGE | 65 EX_DATAERR | 1 runtime | 0 success.
#   Q4 (--help surface): "Exit codes:" section in usage().
#
# DECIDE-THEN-ACT contract (the architectural shape Plan 14-01 establishes):
#
#   parse_args                                # --yes / --no-yes; EX_USAGE on bad flags
#   detect::run_once                          # read-only (Phase 12)
#   . remediate.sh                            # source THIS file
#   remediate::collect_all_decisions          # populate RESOLUTIONS + BAILED_COMPONENTS; ZERO mutation
#   remediate::flush_bails_or_continue        # exit 65 here if any bail; ZERO mutation done
#   run_provisioners                          # each provisioner reads RESOLUTIONS[<component>]
#
# Verified by tests/bats/14-remediate.bats no-mutation snapshot @tests:
# snapshot /etc/sudoers.d + /home + /etc/passwd BEFORE bail run; snapshot AFTER;
# assert byte-equality via diff. A regression that re-orders main() to put
# run_provisioners BEFORE flush_bails_or_continue would be caught immediately.
#
# Inherits `set -euo pipefail`, the ERR trap, the tee redirect, and the log.sh
# / as_user.sh dependencies from the entrypoint. MUST NOT set its own
# strict-mode flags. Uses `return 1` (not `exit 1`) on misuse paths — sourced
# fragment (pattern from plugin/lib/reuse.sh). The flush_bails_or_continue
# function DOES use `exit 65` deliberately: it is the terminal sink that
# short-circuits main() out before any provisioner runs.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Resolve the per-component dir relative to this file. Split declare/assign per
# SC2155 so a cmdsub failure surfaces as non-zero rather than being masked by
# the readonly wrapper. Same idiom as plugin/lib/reuse.sh REUSE_LIB_DIR.
REMEDIATE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/remediate" && pwd)
readonly REMEDIATE_LIB_DIR

# Source per-component handler stubs. (Caller — agentlinux-install — has
# already sourced log.sh + as_user.sh + detect.sh + reuse.sh.) Per-component
# files have their own source-once guards; safe to re-source.
# shellcheck source=remediate/user.sh
. "$REMEDIATE_LIB_DIR/user.sh"
# shellcheck source=remediate/nodejs.sh
. "$REMEDIATE_LIB_DIR/nodejs.sh"
# shellcheck source=remediate/sudoers.sh
. "$REMEDIATE_LIB_DIR/sudoers.sh"
# shellcheck source=remediate/agents.sh
. "$REMEDIATE_LIB_DIR/agents.sh"

# Global aggregation arrays. The `-g` flag is critical — otherwise these
# become function-local when remediate.sh is sourced from inside a function
# context (bats @tests source via __source_lib_chain functions).
#
# BAILED_COMPONENTS: pipe-separated "component|reason|hint" entries; flushed
# as [BAIL] lines by flush_bails_or_continue.
#
# RESOLUTIONS: associative array keyed by canonical component name (`user`,
# `npm-prefix`, `sudoers`, `agents.<id>`) with values from the four-token
# enumeration {reuse, create, remediate, bail}. Provisioners dispatch on
# RESOLUTIONS[<component>] rather than calling reuse::*_decision themselves.
declare -ga BAILED_COMPONENTS=()
declare -gA RESOLUTIONS=()

# Plan 15-01 (Phase 15, UX-02): ACTION_MAP maps component → action-token for
# the prompt loop. Populated by collect_all_decisions (via gate_or_bail)
# alongside RESOLUTIONS. Consumed by plugin/lib/prompt.sh::run_all so the
# prompt knows which action token to render + which decline_reason token to
# record on a decline.
declare -gA ACTION_MAP=()

# remediate::register_bail <component> <reason> <hint>
#
# Appends one entry to BAILED_COMPONENTS for later flush. Caller responsibility
# to dedup if needed — additive shape is correct (two bails of the same
# component from different code paths is itself an actionable signal).
#
# Pipe separator is used internally; component/reason/hint must not contain
# pipes. T-14-06 mitigation: all in-tree register_bail callers pass hardcoded
# literal strings (verified by bats grep @test); no $VAR-driven values.
remediate::register_bail() {
  if [[ $# -lt 3 ]]; then
    log_error "remediate::register_bail: argc=$# (expected 3: <component> <reason> <hint>)"
    return 64
  fi
  local component=$1 reason=$2 hint=$3
  BAILED_COMPONENTS+=("${component}|${reason}|${hint}")
  log_warn "remediate: registered bail — component=${component} reason=${reason}"
  return 0
}

# remediate::flush_bails_or_continue
#
# DECIDE-THEN-ACT terminal sink. Called from main() AFTER
# remediate::collect_all_decisions and BEFORE run_provisioners. If
# BAILED_COMPONENTS is non-empty, prints the LOCKED structured bail message
# (CONTEXT.md Area 1 Q2) and exits 65 — no provisioner has run, host is
# byte-identical to its pre-call state (verified by tests/bats/14-remediate.bats
# no-mutation snapshot @tests).
#
# When empty (greenfield, or all decisions resolved without bails), returns 0
# silently and main() proceeds to run_provisioners.
#
# Exits 65 (NOT return) — deliberate terminal sink. The bail message is
# stderr-only so `agentlinux-install | downstream-consumer` does not feed
# operator-facing diagnostics into a JSON parser.
remediate::flush_bails_or_continue() {
  if [[ ${#BAILED_COMPONENTS[@]} -eq 0 ]]; then
    return 0
  fi

  local n=${#BAILED_COMPONENTS[@]}
  {
    printf 'Refusing to proceed — %d components need Remediate (run with --yes to apply, or --dry-run to preview):\n' "$n"
    printf '\n'
    local entry component reason hint
    for entry in "${BAILED_COMPONENTS[@]}"; do
      IFS='|' read -r component reason hint <<<"$entry"
      printf '[BAIL] component=%s reason=%s hint=%s\n' "$component" "$reason" "$hint"
    done
    printf '\n'
    printf 'Exit code 65 (EX_DATAERR — incompatible host state). See agentlinux install --help.\n'
  } >&2

  exit 65
}

# remediate_action_overwrites_state <action>
#
# Predicate returning 0 (true) for state-overwriting Remediate actions that
# require --yes consent per CONTEXT.md Area 1 Q1, 1 (false) for additive
# actions that run unconditionally.
#
# Centralized here so Phase 15 (TTY-interactive prompts) doesn't duplicate the
# policy — Phase 15's confirm_remediate routes through this same predicate.
#
# Overwriting (require --yes when non-TTY):
#   npm-prefix-chown      — REMEDIATE-01 chown -R agent:agent <prefix>
#   npm-prefix-rebase     — REMEDIATE-01 rebase to ~user/.npm-global
#   sudoers-drift-overwrite — REMEDIATE-03 replace non-canonical sudoers
#   agent-reinstall       — REMEDIATE-04 uninstall + reinstall catalog agent
#
# Additive (run unconditionally):
#   path-wiring           — REMEDIATE-02 ensure_marker_block (additive)
#   sudoers-missing-install — REMEDIATE-03 missing-file install (not overwriting)
remediate_action_overwrites_state() {
  local action=${1:-}
  case "$action" in
    npm-prefix-chown | npm-prefix-rebase | sudoers-drift-overwrite | agent-reinstall)
      return 0
      ;;
    path-wiring | sudoers-missing-install)
      return 1
      ;;
    *)
      # Unknown action: default to false (additive) so an unrecognized token
      # does not silently gate a critical Remediate. Caller should be explicit.
      return 1
      ;;
  esac
}

# remediate::gate_or_bail <component> <action> <reason> <hint>
#
# Phase 14 policy gate. For state-overwriting actions: if --yes was passed,
# returns 0 (consent granted, caller may proceed to mutation). Otherwise
# registers a bail and returns 1. Additive actions short-circuit to return 0
# without consulting --yes.
#
# Phase 15 will extend this with a TTY-interactive branch (`[ -t 0 ] &&
# confirm_remediate "$action"`); Phase 14 ships the non-TTY branch only.
remediate::gate_or_bail() {
  if [[ $# -lt 4 ]]; then
    log_error "remediate::gate_or_bail: argc=$# (expected 4: <component> <action> <reason> <hint>)"
    return 64
  fi
  local component=$1 action=$2 reason=$3 hint=$4

  if ! remediate_action_overwrites_state "$action"; then
    return 0
  fi

  # Plan 15-01 (UX-02): record the action regardless of consent outcome —
  # plugin/lib/prompt.sh consults ACTION_MAP in TTY mode to know which action
  # token to render in the per-action prompt + which decline_reason to record.
  # shellcheck disable=SC2034  # consumed by plugin/lib/prompt.sh via cross-file source
  ACTION_MAP[$component]="$action"

  if [[ "${YES_FLAG:-false}" == "true" ]]; then
    return 0
  fi

  # Plan 15-01 (D-15-05, D-15-10): TTY mode defers consent to the prompt loop
  # (which runs AFTER flush_bails_or_continue). In TTY mode we do NOT register
  # a bail here — the prompt loop will ask the operator and either approve
  # (proceed with mutation) or decline (convert RESOLUTIONS[<c>] to
  # reuse-with-warning so the provisioner skips the mutation). The DRY_RUN
  # branch likewise wants a populated ACTION_MAP without bails — but it short-
  # circuits in main() before flush_bails_or_continue runs anyway, so the
  # bail register here would never reach the operator. In dry-run we ALWAYS
  # register the bail so the printed report carries the [BAIL] line per
  # D-15-01 ("bails surface IN the report, not via exit code").
  if [[ "${DRY_RUN_REQUESTED:-false}" != "true" ]] && [[ -t 0 ]]; then
    return 0
  fi

  # Non-TTY without --yes (or dry-run): Phase 14 bail-aggregation path.
  remediate::register_bail "$component" "$reason" "$hint"
  return 1
}

# remediate::collect_all_decisions
#
# DECIDE-THEN-ACT entry point. Calls EVERY reuse::*_decision function exactly
# once, populates RESOLUTIONS[<component>]=<token>, and (where the token maps
# to a state-overwriting Remediate AND --yes was not passed) registers a bail.
#
# Invariant: this function makes NO host mutation. It only reads detect::*
# exports and calls reuse::*_decision functions which themselves are pure
# readers. Verified by tests/bats/14-remediate.bats Test 11 (filesystem-
# mutation shim records zero invocations after this returns).
#
# After this returns, downstream consumers (run_provisioners) read
# RESOLUTIONS[<component>] and dispatch — they do NOT call reuse::*_decision
# themselves (decisions are pre-resolved here).
#
# Components populated (canonical keys):
#   user           — REUSE-01 / unfixable bails (wrong shell, home unwritable)
#   node           — REUSE-02 (reuse|create only; no remediate token here)
#   npm-prefix     — REMEDIATE-01 (reuse|create|remediate per writability)
#   sudoers        — REMEDIATE-03 (reuse|create|remediate per drift)
#   agents.<id>    — REMEDIATE-04 (one per REUSE_AGENT_CANONICAL_PATHS key)
remediate::collect_all_decisions() {
  local user=${INSTALL_USER:-agent}

  # 1. User decision (REUSE-01).
  RESOLUTIONS[user]=$(reuse::user_decision "$user")
  case "${RESOLUTIONS[user]}" in
    bail)
      # T-14-06 mitigation: hardcoded literal component/reason/hint strings,
      # no $VAR substitution into register_bail args.
      remediate::register_bail \
        "user" "incompatible" \
        "use --user=NAME with a compatible user, or fix shell/home of existing user"
      ;;
    remediate)
      # The user-decision "remediate" token maps to REMEDIATE-03 (sudoers fix
      # — agent exists but lacks NOPASSWD-for-apt). That fix is OWNED by the
      # sudoers component below, NOT by the user component. We record the
      # resolution but do NOT register a bail here — the sudoers branch handles
      # gating. This keeps the responsibility for sudoers state in one place.
      :
      ;;
  esac

  # 2. Node decision (Phase 13 — returns reuse|create only; no remediate
  # token at the Node-install layer per CONTEXT.md Area 1 Q2).
  RESOLUTIONS[node]=$(reuse::nodejs_decision)

  # 3. npm-prefix decision (Plan 14-01 NEW — REMEDIATE-01).
  RESOLUTIONS[npm-prefix]=$(reuse::npm_prefix_decision)
  if [[ "${RESOLUTIONS[npm-prefix]}" == "remediate" ]]; then
    # gate_or_bail returns 1 when it registers a bail; `|| true` keeps the
    # collect-all loop moving so we aggregate every bail rather than
    # short-circuiting on the first one.
    remediate::gate_or_bail \
      "npm-prefix" "npm-prefix-chown" "wrong-owner" \
      "run with --yes to chown or rebase" \
      || true
  fi

  # 4. Sudoers decision (inline — small enough; see CONTEXT.md Area 1 Q1).
  # Per detect/sudoers.sh exports:
  #   DETECT_SUDOERS_PRESENT      true iff /etc/sudoers.d/agentlinux exists
  #   DETECT_SUDOERS_NOPASSWD_OK  true iff the canonical ADR-012 line is present
  local sudoers_token=create
  if [[ "${DETECT_SUDOERS_PRESENT:-false}" == "true" ]]; then
    if [[ "${DETECT_SUDOERS_NOPASSWD_OK:-false}" == "true" ]]; then
      sudoers_token=reuse
    else
      sudoers_token=remediate
    fi
  fi
  RESOLUTIONS[sudoers]=$sudoers_token
  if [[ "$sudoers_token" == "remediate" ]]; then
    remediate::gate_or_bail \
      "sudoers" "sudoers-drift-overwrite" "drift" \
      "run with --yes to overwrite with the canonical ADR-012 line" \
      || true
  fi

  # 5. Per-agent decisions (Phase 13 — iterate the canonical-path map).
  # Each agent decides independently; keys are namespaced as `agents.<id>` so
  # the operator can see exactly which agent is in which state.
  local agent_id
  if declare -p REUSE_AGENT_CANONICAL_PATHS >/dev/null 2>&1; then
    for agent_id in "${!REUSE_AGENT_CANONICAL_PATHS[@]}"; do
      RESOLUTIONS[agents.$agent_id]=$(reuse::agent_decision "$agent_id")
      if [[ "${RESOLUTIONS[agents.$agent_id]}" == "remediate" ]]; then
        remediate::gate_or_bail \
          "$agent_id" "agent-reinstall" "broken-or-path-mismatch" \
          "run with --yes to uninstall and reinstall (preserves user data per CAT-04)" \
          || true
      fi
    done
  fi

  return 0
}
