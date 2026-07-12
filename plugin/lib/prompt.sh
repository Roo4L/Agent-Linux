#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/prompt.sh — TTY per-action prompt loop.
#
# Sourced by agentlinux-install after remediate::flush_bails_or_continue and
# before run_provisioners — only in TTY mode and when --yes was NOT passed
# (main() gates entry). Additive actions never prompt; --yes auto-approves.
#
# Inherits set -euo pipefail, the ERR trap, the tee redirect — MUST NOT set its
# own strict-mode flags. Uses `return` (not `exit`) on misuse paths.
#
# Input handling: read -r -n 1 (single char, no backslash escapes; never
# eval'd), with a re-prompt cap of 3 then default-to-decline so a closed or
# garbage stdin cannot wedge the installer.

[[ -n "${AGENTLINUX_PROMPT_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_PROMPT_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'prompt.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# component → decline-reason-token, populated by prompt::run_all on each decline
# and consumed by provisioner case-arms via cross-file source (hence SC2034).
# shellcheck disable=SC2034
declare -gA DECLINED_COMPONENTS=()

# _prompt::action_to_decline_reason <action-token> — decline_reason token,
# mirroring install.ts's Sentinel.decline_reason enum.
_prompt::action_to_decline_reason() {
  case "$1" in
    npm-prefix-chown | npm-prefix-rebase) printf 'chown-declined' ;;
    sudoers-drift-overwrite) printf 'sudoers-drift-declined' ;;
    agent-reinstall) printf 'reinstall-broken-declined' ;;
    *) printf 'unknown-declined' ;;
  esac
}

# _prompt::action_to_req_marker <action-token> — REMEDIATE-NN marker for the
# grep-stable [REMEDIATE-NN] DECLINED log line.
_prompt::action_to_req_marker() {
  case "$1" in
    npm-prefix-chown | npm-prefix-rebase) printf 'REMEDIATE-01' ;;
    sudoers-drift-overwrite) printf 'REMEDIATE-03' ;;
    agent-reinstall) printf 'REMEDIATE-04' ;;
    *) printf 'REMEDIATE-??' ;;
  esac
}

# _prompt::describe_action <action-token> — human-readable description rendered
# in the prompt body.
_prompt::describe_action() {
  case "$1" in
    npm-prefix-chown) printf 'chown ~agent/.npm-global to agent:agent' ;;
    npm-prefix-rebase) printf 'rebase npm-global to ~agent/.npm-global' ;;
    sudoers-drift-overwrite) printf 'overwrite /etc/sudoers.d/agentlinux with canonical ADR-012 line' ;;
    agent-reinstall) printf 'uninstall + reinstall broken catalog agent (preserves user data per CAT-04)' ;;
    *) printf '%s' "$1" ;;
  esac
}

# prompt::confirm_remediate <component> <description>
# Renders "Proceed with this remediation? [Y/n] (<component> — <description>)".
# Returns 0 on accept (Y/y/Enter), 1 on decline (N/n). Re-prompts on other
# chars up to 3 times, then defaults to decline.
prompt::confirm_remediate() {
  local component=$1 description=$2
  local response tries=0
  while [[ $tries -lt 3 ]]; do
    # Prompt on stderr so capture-stdout consumers (jq) are unaffected.
    printf 'Proceed with this remediation? [Y/n] (%s — %s) ' "$component" "$description" >&2
    # -r: no backslash escapes. -n 1: single char. IFS=: no leading-whitespace
    # stripping. EOF falls back to default-decline.
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
        # Drain the rest of the buffered line so the next `read -n 1` doesn't
        # pick up its trailing newline as an Enter (= default-accept), which
        # would flip a deliberate garbage response to an accept. Not eval'd.
        local _discard
        # shellcheck disable=SC2034  # _discard is intentionally unused
        IFS= read -r _discard || true
        ;;
    esac
  done
  log_warn "prompt: 3 invalid responses — defaulting to decline for $component"
  return 1
}

# prompt::run_all
# Iterate RESOLUTIONS in canonical order (user, npm-prefix, sudoers, then
# agents.<id> sorted by id — same order as the report). For each component
# whose action is state-overwriting, prompt the operator. On accept: leave
# RESOLUTIONS[<c>]=remediate. On decline: convert to reuse-with-warning, record
# DECLINED_COMPONENTS[<c>]=<reason>, emit the [REMEDIATE-NN] DECLINED marker.
prompt::run_all() {
  local -a components=("user" "npm-prefix" "sudoers")
  # Append agents.<id> in stable id-sorted order. declare -p guard avoids
  # tripping set -u when no agent map is populated.
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
    if prompt::confirm_remediate "$component" "$description"; then
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

# prompt::choose_install_user
# AL-50 AC3 — general install-time prompt fired BEFORE detection (unlike
# prompt::alt_user_or_bail, which fires AFTER detection only on an incompatible
# existing user). Prints a short 3-line context block (what the account is, that
# it gets passwordless sudo, create-vs-adopt, and a docs URL) once, then renders
# `Install AgentLinux under which user? [default: <name>] ` on STDERR and reads a
# line (IFS= read -r, line-based — names are >1 char, so NOT the single-char
# -n 1 form used by prompt::confirm_remediate). `[default: <name>]` (not bare
# `[<name>]`) reads as the Enter-to-accept default. The `Install AgentLinux under
# which user?` substring is the tty-driver.py PROMPT_SENTINELS gate — keep it
# verbatim (check-tty-sentinels.sh).
#
# Return-by-stdout contract (NOT export): on accept the function PRINTS the
# chosen name to STDOUT (a single printf) and the caller assigns it via
# `INSTALL_USER="$(prompt::choose_install_user)"`. The real call site and the
# test both invoke it through a pipe, where a pipe subshell would discard any
# exported/assigned variable — so stdout is the only reliable channel. ALL
# prompts/warnings go to STDERR so stdout carries ONLY the chosen name.
#
# Default: empty input keeps the default (`${INSTALL_USER:-agent}`). A typed
# name is validated via remediate::validate_user_name; on invalid, re-prompt up
# to 3 times then fall back to the default.
prompt::choose_install_user() {
  local default_user="${INSTALL_USER:-agent}"
  local response chosen="" tries=0
  # STDERR only — STDOUT is the return channel and must carry ONLY the chosen
  # name (see the return-by-stdout contract above).
  {
    printf 'This account runs your coding agents and is granted passwordless sudo.\n'
    printf 'A name that does not exist yet is created; an existing compatible user is adopted.\n'
    printf 'Details: https://agentlinux.org/docs/install-user\n'
  } >&2
  while [[ $tries -lt 3 ]]; do
    printf 'Install AgentLinux under which user? [default: %s] ' "$default_user" >&2
    # Line-based read (no -n N). EOF / closed stdin → fall back to default.
    if ! IFS= read -r response; then
      printf '\n' >&2
      log_warn "prompt: stdin closed (EOF) — using default install user '${default_user}'"
      printf '%s\n' "$default_user"
      return 0
    fi
    # Empty (bare Enter) accepts the default.
    if [[ -z "$response" ]]; then
      chosen="$default_user"
      break
    fi
    if remediate::validate_user_name "$response"; then
      chosen="$response"
      break
    fi
    tries=$((tries + 1))
    printf 'invalid name: %q — must match ^[a-z][a-z0-9_-]*$ and not be root/a reserved account\n' "$response" >&2
  done

  # 3 invalid responses → fall back to the default rather than wedging.
  if [[ -z "$chosen" ]]; then
    log_warn "prompt: 3 invalid responses — using default install user '${default_user}'"
    chosen="$default_user"
  fi

  printf '%s\n' "$chosen"
  return 0
}

# prompt::alt_user_or_bail
# Called from main() when reuse::user_decision returned 'bail' and
# DETECT_USER_BAIL_REASON is set (wrong-shell, home-unwritable, name-mismatch).
#   TTY: prompt for an alternate user name (suggested via
#        remediate::find_alt_user_name); on accept export INSTALL_USER and
#        return 0; on EOF exit 65; on 3 invalid names exit 64.
#   Non-TTY: emit the hint message and exit 65.
# Uses `exit` (not return) on bail paths — main() relies on this being a
# terminal sink; the accept path returns 0 so main() can re-run detection.
#
# NOTE: the former AL-59 partial-provisioning limitation is closed (AL-50).
# 30-nodejs.sh, 40-path-wiring.sh, 50-registry-cli.sh, and the sudoers content
# all derive from INSTALL_USER now, so an accepted alternate name is fully
# provisioned — npm prefix, PATH wiring, passwordless sudo, and the registry CLI
# land on the chosen user. This bail path stays the detection-failure fallback;
# the primary configurable-user entry point is prompt::choose_install_user above.
prompt::alt_user_or_bail() {
  local existing_user="${INSTALL_USER:-agent}"
  local reason="${DETECT_USER_BAIL_REASON:-unknown}"
  local suggested
  # find_alt_user_name returns non-zero on exhaustion; `|| true` lets us emit a
  # graceful "no suggestion" message instead of tripping set -e.
  suggested=$(remediate::find_alt_user_name) || true

  # Non-TTY: bail-with-hint, exit 65.
  if [[ ! -t 0 ]]; then
    if [[ -n "$suggested" ]]; then
      log_error "agentlinux: existing user \"${existing_user}\" is incompatible (${reason}). Re-run with --user=${suggested} or fix the existing user manually."
    else
      log_error "agentlinux: existing user \"${existing_user}\" is incompatible (${reason}). Re-run with --user=NAME (no auto-suggested name available — agent2..agent99 all taken) or fix the existing user manually."
    fi
    exit 65
  fi

  # TTY: render the alt-user prompt. Header on stderr so capture-stdout
  # consumers (jq) are unaffected.
  {
    printf 'pre-flight: existing user "%s" has %s (DET-01 requires bash + writable home).\n' "$existing_user" "$reason"
    printf 'AgentLinux can create a new install user instead.\n'
    if [[ -n "$suggested" ]]; then
      printf 'Suggested alternate name: %s\n' "$suggested"
    else
      printf 'No auto-suggested name available (agent2..agent99 all taken).\n'
    fi
  } >&2

  local response chosen=""
  local tries=0
  while [[ $tries -lt 3 ]]; do
    if [[ -n "$suggested" ]]; then
      printf 'Press Enter to use "%s", or type another name: ' "$suggested" >&2
    else
      printf 'Type a name for the new install user: ' >&2
    fi
    # -r: no backslash escapes. Line-based read (no -n N) — names are >1 char.
    if ! IFS= read -r response; then
      printf '\n' >&2
      log_error "[ALT-USER] declined — exiting 65 (EOF on prompt)"
      exit 65
    fi
    # Accept Enter as "use suggested" iff suggested is set.
    if [[ -z "$response" && -n "$suggested" ]]; then
      chosen="$suggested"
      break
    fi
    if remediate::validate_user_name "$response"; then
      chosen="$response"
      break
    fi
    tries=$((tries + 1))
    printf 'invalid name: %q — must match ^[a-z][a-z0-9_-]*$\n' "$response" >&2
  done

  if [[ -z "$chosen" ]]; then
    log_error "[ALT-USER] 3 invalid responses — exiting 64 EX_USAGE"
    exit 64
  fi

  log_info "[ALT-USER] accepted: ${chosen}"
  export INSTALL_USER="$chosen"
  return 0
}
