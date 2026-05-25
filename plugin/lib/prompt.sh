#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/prompt.sh — TTY per-action prompt loop (Phase 15, Plan 15-01).
#
# Sourced by plugin/bin/agentlinux-install AFTER remediate::flush_bails_or_continue
# and BEFORE run_provisioners — ONLY in TTY mode AND when --yes was NOT passed.
# Per D-15-09 (additive actions never prompt) and D-15-10 (--yes auto-approves
# in TTY too), the call site at main() gates entry; this file owns the loop
# itself + the per-action prompt rendering.
#
# Architectural placement (extends Phase 14 DECIDE-THEN-ACT):
#
#   parse_args                                # --dry-run / --yes / --no-yes
#   detect::run_once                          # read-only (Phase 12)
#   remediate::collect_all_decisions          # RESOLUTIONS + BAILED_COMPONENTS
#                                             # + ACTION_MAP (Plan 15-01)
#   [DRY_RUN_REQUESTED branch — exits 0]
#   remediate::flush_bails_or_continue        # no-op in TTY mode (defers to us)
#   if [[ -t 0 && ! YES_FLAG ]]:
#     prompt::run_all                         # THIS FILE
#   run_provisioners                          # honor reuse-with-warning
#
# DECLINE-REASON TOKEN MAP (D-15-02 — owned here):
#   npm-prefix-chown          → chown-declined
#   npm-prefix-rebase         → chown-declined
#   sudoers-drift-overwrite   → sudoers-drift-declined
#   agent-reinstall           → reinstall-broken-declined
#
# Inherits set -euo pipefail, the ERR trap, the tee redirect. MUST NOT set
# own strict-mode flags. Uses `return` (not `exit`) on misuse paths.
#
# T-15-01-03 mitigation: read -r -n 1 (single-char; no backslash escapes;
# subsequent injected text on the same input is consumed as the next read or
# discarded by the next prompt cycle — never eval'd).
# T-15-01-07 mitigation: re-prompt cap of 3, then default-to-decline (so a
# stdin that closes mid-loop OR a garbage stream cannot wedge the installer).

[[ -n "${AGENTLINUX_PROMPT_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_PROMPT_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'prompt.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Global: associative array of component → decline-reason-token. Populated by
# prompt::run_all on each decline. Consumed by run_provisioners' per-component
# case-arms (which read RESOLUTIONS for the dispatch token + DECLINED_COMPONENTS
# for the decline reason when emitting the [REUSE-WARN] log line). shellcheck
# cannot follow cross-file consumers through sourced fragments, hence SC2034.
# shellcheck disable=SC2034
declare -gA DECLINED_COMPONENTS=()

# _prompt::action_to_decline_reason <action-token>
# Returns the matching decline_reason token. The map mirrors install.ts's
# Sentinel.decline_reason enum (D-15-02).
_prompt::action_to_decline_reason() {
  case "$1" in
    npm-prefix-chown | npm-prefix-rebase) printf 'chown-declined' ;;
    sudoers-drift-overwrite) printf 'sudoers-drift-declined' ;;
    agent-reinstall) printf 'reinstall-broken-declined' ;;
    *) printf 'unknown-declined' ;;
  esac
}

# _prompt::action_to_req_marker <action-token>
# Returns the REMEDIATE-NN marker name for the [REMEDIATE-NN] DECLINED log
# line (D-15-11 grep-stable convention).
_prompt::action_to_req_marker() {
  case "$1" in
    npm-prefix-chown | npm-prefix-rebase) printf 'REMEDIATE-01' ;;
    sudoers-drift-overwrite) printf 'REMEDIATE-03' ;;
    agent-reinstall) printf 'REMEDIATE-04' ;;
    *) printf 'REMEDIATE-??' ;;
  esac
}

# _prompt::describe_action <action-token>
# Human-readable description of the action, rendered inside the prompt body
# so the operator knows what they are being asked to approve.
_prompt::describe_action() {
  case "$1" in
    npm-prefix-chown) printf 'chown ~agent/.npm-global to agent:agent' ;;
    npm-prefix-rebase) printf 'rebase npm-global to ~agent/.npm-global' ;;
    sudoers-drift-overwrite) printf 'overwrite /etc/sudoers.d/agentlinux with canonical ADR-012 line' ;;
    agent-reinstall) printf 'uninstall + reinstall broken catalog agent (preserves user data per CAT-04)' ;;
    *) printf '%s' "$1" ;;
  esac
}

# prompt::confirm_remediate <component> <action> <human-description>
# Renders the locked prompt format (D-15-06):
#   Proceed with this remediation? [Y/n] (<component> — <description>)
# Returns 0 on accept (Y/y/<Enter>), 1 on decline (N/n).
# Re-prompts on other chars up to 3 times, then defaults to decline (T-15-01-07).
prompt::confirm_remediate() {
  local component=$1 action=$2 description=$3
  local response tries=0
  while [[ $tries -lt 3 ]]; do
    # Render to stderr so capture-stdout consumers (jq pipelines) are
    # unaffected. The prompt is operator-facing.
    printf 'Proceed with this remediation? [Y/n] (%s — %s) ' "$component" "$description" >&2
    # -r: no backslash escapes (T-15-01-03 mitigation against \-injection)
    # -n 1: single char — bytes past the first are left on the input stream
    #   for the next read OR are simply ignored when stdin is the TTY (the
    #   user's shell does not re-execute the buffered chars on our behalf).
    # Falls back to default-decline on EOF (T-15-01-07).
    # IFS= prevents bash from consuming leading whitespace.
    if ! IFS= read -r -n 1 response; then
      printf '\n' >&2
      log_warn "prompt: stdin closed (EOF) — defaulting to decline for $component"
      return 1
    fi
    printf '%s\n' "$response" >&2
    case "$response" in
      '' | Y | y) return 0 ;;
      N | n) return 1 ;;
      *)
        tries=$((tries + 1))
        printf 'invalid response: %q — please answer Y or n\n' "$response" >&2
        # Consume the rest of the buffered line so the next iteration's
        # `read -n 1` doesn't pick up leftover garbage from the same line.
        # The trailing newline left in the buffer by previous read -n 1
        # would otherwise be consumed as an Enter (= default-accept) — that
        # would FLIP the user's deliberate garbage response to an accept.
        # T-15-01-03 belt-and-braces: we do NOT eval the discarded line.
        local _discard
        # shellcheck disable=SC2034  # _discard is intentionally unused
        IFS= read -r _discard || true
        action=$action # silence unused-arg lint (action used only via description above)
        ;;
    esac
  done
  log_warn "prompt: 3 invalid responses — defaulting to decline for $component"
  return 1
}

# prompt::run_all
# Iterate RESOLUTIONS in canonical component order. For each component whose
# action is state-overwriting (per remediate_action_overwrites_state), prompt
# the operator. On accept: leave RESOLUTIONS[<c>]=remediate (provisioner
# mutates). On decline: convert to reuse-with-warning + record
# DECLINED_COMPONENTS[<c>]=<reason> + emit [REMEDIATE-NN] DECLINED log marker
# (D-15-11).
#
# Canonical order: user, npm-prefix, sudoers, then agents.<id> (sorted by id).
# Matches collect_all_decisions populate order so the operator sees prompts
# in the same order as the report.
prompt::run_all() {
  local -a components=("user" "npm-prefix" "sudoers")
  # Append agents.<id> in stable id-sorted order. Existence guard via
  # `declare -p` so we do not trip set -u when no agent map is populated.
  if declare -p REUSE_AGENT_CANONICAL_PATHS >/dev/null 2>&1; then
    local agent_id
    while IFS= read -r agent_id; do
      [[ -n "$agent_id" ]] && components+=("agents.$agent_id")
    done < <(printf '%s\n' "${!REUSE_AGENT_CANONICAL_PATHS[@]}" | sort)
  fi

  local component action req_marker reason description
  for component in "${components[@]}"; do
    [[ "${RESOLUTIONS[$component]:-}" == "remediate" ]] || continue
    action="${ACTION_MAP[$component]:-}"
    [[ -n "$action" ]] || continue
    remediate_action_overwrites_state "$action" || continue

    description=$(_prompt::describe_action "$action")
    if prompt::confirm_remediate "$component" "$action" "$description"; then
      # Accept: RESOLUTIONS stays "remediate"; provisioner mutates.
      log_info "[PROMPT] $component: ACCEPTED ($action)"
    else
      reason=$(_prompt::action_to_decline_reason "$action")
      req_marker=$(_prompt::action_to_req_marker "$action")
      RESOLUTIONS[$component]="reuse-with-warning"
      # shellcheck disable=SC2034  # consumed by provisioner case-arms via cross-file source
      DECLINED_COMPONENTS[$component]="$reason"
      log_warn "[$req_marker] DECLINED by user — skipping $component; install continues (state will be marked reused-with-warning)"
    fi
  done
  return 0
}
