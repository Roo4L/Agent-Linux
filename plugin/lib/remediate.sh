#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate.sh — remediate-decision orchestrator + DECIDE-THEN-ACT
# policy gate.
#
# DECIDE-THEN-ACT: collect_all_decisions populates RESOLUTIONS +
# BAILED_COMPONENTS with ZERO mutation; flush_bails_or_continue exits 65 if any
# bail is registered; only then does run_provisioners run. main() MUST keep
# flush before run_provisioners so a bail leaves the host byte-identical.
#
# --yes gates state-overwriting Remediates only; additive paths (PATH wiring,
# missing-file sudoers install) run unconditionally. Exit codes: 64 EX_USAGE,
# 65 EX_DATAERR, 1 runtime, 0 success.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh/as_user.sh
# from the entrypoint; MUST NOT set its own strict-mode flags. Uses `return 1`
# on misuse paths. flush_bails_or_continue deliberately uses `exit 65` — it is
# the terminal sink that short-circuits main() before any provisioner runs.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Split declare/assign per SC2155 so a cmdsub failure surfaces as non-zero.
REMEDIATE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/remediate" && pwd)
readonly REMEDIATE_LIB_DIR

# Per-component handlers (own source-once guards; safe to re-source).
# shellcheck source=remediate/user.sh
. "$REMEDIATE_LIB_DIR/user.sh"
# shellcheck source=remediate/nodejs.sh
. "$REMEDIATE_LIB_DIR/nodejs.sh"
# shellcheck source=remediate/sudoers.sh
. "$REMEDIATE_LIB_DIR/sudoers.sh"
# shellcheck source=remediate/agents.sh
. "$REMEDIATE_LIB_DIR/agents.sh"

# Global aggregation arrays. `-g` is critical — without it these become
# function-local when remediate.sh is sourced inside a function (bats @tests).
#   BAILED_COMPONENTS: pipe-separated "component|reason|hint" entries.
#   RESOLUTIONS: keyed by canonical component name (`user`, `npm-prefix`,
#     `sudoers`, `agents.<id>`) → {reuse, create, remediate, bail}. Provisioners
#     dispatch on RESOLUTIONS[<component>], not reuse::*_decision directly.
declare -ga BAILED_COMPONENTS=()
declare -gA RESOLUTIONS=()

# ACTION_MAP maps component → action-token; consumed by plugin/lib/prompt.sh in
# TTY mode to render the per-action prompt + decline_reason token.
declare -gA ACTION_MAP=()

# remediate::find_alt_user_name
# Prints the lowest free `agent<N>` (N≥2) and returns 0; on exhaustion
# (agent2..agent99 all taken) prints "" and returns 1. Pure read (getent, so
# NSS sources are consulted); safe during the DECIDE phase.
remediate::find_alt_user_name() {
  local n
  for ((n = 2; n <= 99; n++)); do
    if ! getent passwd "agent${n}" >/dev/null 2>&1; then
      printf 'agent%d' "$n"
      return 0
    fi
  done
  printf ''
  return 1
}

# Reserved / system account denylist (D-AL50 AC5). Names that match the POSIX
# charset but must NEVER be provisioned-or-adopted as the install user: granting
# NOPASSWD: ALL sudo to root or a daemon account is an elevation hole, and
# colliding with a system account corrupts the host. Matched case-insensitively;
# any name beginning `systemd-` is also rejected (covers systemd-network,
# systemd-resolve, systemd-timesync, … without enumerating every variant).
readonly -a AGENTLINUX_RESERVED_USER_NAMES=(
  root daemon bin sys sync games man lp mail news uucp proxy www-data backup
  list irc gnats nobody _apt systemd-network systemd-resolve systemd-timesync
  messagebus sshd
)

# remediate::validate_user_name <name>
# Returns 0 for a POSIX-friendly name (first char lowercase a-z, remainder
# [a-z0-9_-]) that is NOT a reserved/system account name, 1 otherwise (including
# empty). Rejecting all shell metachars is the documented contract every
# downstream component depends on, even though the name is later passed to
# useradd argv-literally (no shell eval). PURE (no getent) so it stays usable
# during the DECIDE phase — adoption of an EXISTING system account (UID < 1000)
# is a separate runtime check (remediate::user_adoptable).
remediate::validate_user_name() {
  local name=${1:-}
  [[ -n "$name" ]] || return 1
  [[ "$name" =~ ^[a-z][a-z0-9_-]*$ ]] || return 1
  # Case-insensitive reserved-name rejection (AC5). Lowercase once for the
  # compare; the charset regex already forbids uppercase, but normalize anyway
  # so the denylist is robust if the charset ever loosens.
  local lower=${name,,}
  # Any `systemd-*` account is a system identity — reject the whole prefix.
  [[ "$lower" == systemd-* ]] && return 1
  local reserved
  for reserved in "${AGENTLINUX_RESERVED_USER_NAMES[@]}"; do
    [[ "$lower" == "$reserved" ]] && return 1
  done
  return 0
}

# remediate::user_adoptable <name>
# Runtime adoption-safety gate (D-AL50 AC5, T-AL50-01). If the name does NOT
# exist, returns 0 (it will be created fresh by 10-agent-user.sh). If it DOES
# exist, returns 0 only when its UID >= 1000 (a regular login account); a system
# account (UID < 1000) returns 1 so the caller refuses to grant it NOPASSWD sudo
# + overwrite its home. Reads getent/id — NOT pure, so call it at runtime (after
# require_root), never during the DECIDE phase.
remediate::user_adoptable() {
  local name=${1:-}
  [[ -n "$name" ]] || return 1
  # Non-existent → safe to create.
  getent passwd "$name" >/dev/null 2>&1 || return 0
  local uid
  uid=$(id -u "$name" 2>/dev/null || echo "")
  [[ "$uid" =~ ^[0-9]+$ ]] || return 1
  [[ "$uid" -ge 1000 ]] || return 1
  return 0
}

# remediate::register_bail <component> <reason> <hint>
# Appends one entry to BAILED_COMPONENTS for later flush. No dedup — two bails
# of the same component from different paths is itself an actionable signal.
# Pipe-separated internally; args must not contain pipes. All in-tree callers
# pass hardcoded literal strings (no $VAR into the message).
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
# DECIDE-THEN-ACT terminal sink: if any bail is registered, print the LOCKED
# structured [BAIL] message and `exit 65` (not return — short-circuits main()
# before run_provisioners, leaving the host byte-identical). Empty → return 0
# silently. The message is stderr-only so it never feeds a downstream JSON
# parser on stdout.
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
# Returns 0 (true) for state-overwriting actions that require --yes consent,
# 1 (false) for additive actions that run unconditionally. Centralized so the
# TTY-interactive prompt path routes through the same policy.
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
      # Unknown action defaults to additive — be explicit at the call site.
      return 1
      ;;
  esac
}

# remediate::gate_or_bail <component> <action> <reason> <hint>
# Policy gate. Additive actions short-circuit to return 0. State-overwriting
# actions: return 0 if --yes (or TTY, deferring to the prompt loop), else
# register a bail and return 1.
remediate::gate_or_bail() {
  if [[ $# -lt 4 ]]; then
    log_error "remediate::gate_or_bail: argc=$# (expected 4: <component> <action> <reason> <hint>)"
    return 64
  fi
  local component=$1 action=$2 reason=$3 hint=$4

  if ! remediate_action_overwrites_state "$action"; then
    return 0
  fi

  # Record the action regardless of consent outcome — prompt.sh consults
  # ACTION_MAP in TTY mode for the per-action prompt + decline_reason token.
  # shellcheck disable=SC2034  # consumed by plugin/lib/prompt.sh via cross-file source
  ACTION_MAP[$component]="$action"

  if [[ "${YES_FLAG:-false}" == "true" ]]; then
    return 0
  fi

  # TTY (non-dry-run) defers consent to the prompt loop, which runs AFTER
  # flush_bails_or_continue — so do NOT register a bail here. Dry-run DOES
  # register so the printed report carries the [BAIL] line.
  if [[ "${DRY_RUN_REQUESTED:-false}" != "true" ]] && [[ -t 0 ]]; then
    return 0
  fi

  # Non-TTY without --yes (or dry-run): aggregate the bail.
  remediate::register_bail "$component" "$reason" "$hint"
  return 1
}

# remediate::collect_all_decisions
# DECIDE-THEN-ACT entry point. Calls every reuse::*_decision once, populates
# RESOLUTIONS[<component>]=<token>, and registers a bail where the token maps to
# a state-overwriting Remediate without consent. Makes NO host mutation —
# downstream run_provisioners reads RESOLUTIONS and dispatches.
# Components: user (REUSE-01), node (REUSE-02), npm-prefix (REMEDIATE-01),
# sudoers (REMEDIATE-03), agents.<id> (REMEDIATE-04).
remediate::collect_all_decisions() {
  local user=${INSTALL_USER:-agent}

  RESOLUTIONS[user]=$(reuse::user_decision "$user")
  case "${RESOLUTIONS[user]}" in
    bail)
      # register_bail uses hardcoded literal strings, no $VAR into the message.
      remediate::register_bail \
        "user" "incompatible" \
        "use --user=NAME with a compatible user, or fix shell/home of existing user"
      ;;
    remediate)
      # user "remediate" maps to the sudoers fix — gating is OWNED by the
      # sudoers branch below, not here, so sudoers state lives in one place.
      :
      ;;
  esac

  RESOLUTIONS[node]=$(reuse::nodejs_decision)

  RESOLUTIONS[npm-prefix]=$(reuse::npm_prefix_decision)
  if [[ "${RESOLUTIONS[npm-prefix]}" == "remediate" ]]; then
    # gate_or_bail returns 1 when it registers a bail; `|| true` keeps the
    # collect loop aggregating every bail rather than short-circuiting.
    remediate::gate_or_bail \
      "npm-prefix" "npm-prefix-chown" "wrong-owner" \
      "run with --yes to chown or rebase" \
      || true
  fi

  # Sudoers decision (inline). detect/sudoers.sh exports:
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

  # Per-agent decisions: iterate the canonical-path map. Keys are namespaced
  # `agents.<id>` so the operator sees which agent is in which state.
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
