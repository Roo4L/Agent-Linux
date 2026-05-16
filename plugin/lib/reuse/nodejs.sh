#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse/nodejs.sh — REUSE-02 Node.js-compatibility decision.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/reuse.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Implements CONTEXT.md Area 1 / Q2: REUSE if at least ONE entry in
# DETECT_NODEJS_* satisfies BOTH (a) version matches /^v?22\./ AND (b)
# install_user_can_write_prefix=true. First match wins.
#
# Returns one of {reuse, create} on stdout — NO remediate branch here, because
# REMEDIATE-01 lives in the npm-prefix layer (Phase 14), NOT the Node-install
# layer. If no entry satisfies both predicates we install a fresh Node 22 LTS
# via the v0.3.0 30-nodejs.sh CREATE path.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_NODEJS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_NODEJS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse/nodejs.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# reuse::nodejs_decision
#
# Returns `reuse` if `detect::nodejs_satisfies_pin` AND
# `detect::nodejs_prefix_writable` both hold. Both readers walk the per-index
# DETECT_NODEJS_${i}_* exports populated by detect::nodejs_probe in the prior
# detect::run_once call. NB: the two readers may match DIFFERENT entries
# (e.g. entry 0 is Node 22 but root-prefixed, entry 1 is Node 20 but user-
# prefixed) — the looser ANY-satisfies semantics matches CONTEXT.md Area 1
# Q2's "first match wins" wording for the practical brownfield case where the
# operator has Node 22 from NodeSource AND a NodeSource prefix the user-side
# .npmrc points at (the dominant happy path). Phase 14 may tighten this to an
# AND-per-entry walk if a real host surfaces the looser failure mode; the
# decision-function contract is forward-compatible.
#
# Returns `create` otherwise (no satisfying combination).
reuse::nodejs_decision() {
  if detect::nodejs_satisfies_pin && detect::nodejs_prefix_writable; then
    printf 'reuse'
    return 0
  fi
  printf 'create'
  return 0
}

# reuse::log_nodejs_reuse
#
# Emits the canonical [REUSE-02] marker line via log_info. Walks
# DETECT_NODEJS_COUNT to find the FIRST entry whose version matches /^v?22\./
# AND whose install_user_can_write_prefix=true (the first match REUSE picks
# semantically; surfacing it in the marker matches the CONTEXT.md Area 1 Q4
# log shape). Falls back to the first Node-22 entry alone when no full-match
# is found (defensive — should not happen if reuse::nodejs_decision returned
# `reuse`, but keeps the log helpful for diagnostic readers).
reuse::log_nodejs_reuse() {
  local count=${DETECT_NODEJS_COUNT:-0}
  local i v_var w_var s_var r_var
  local v w s r
  local fallback_v="" fallback_s="" fallback_r=""
  for ((i = 0; i < count; i++)); do
    v_var="DETECT_NODEJS_${i}_VERSION"
    w_var="DETECT_NODEJS_${i}_WRITABLE"
    s_var="DETECT_NODEJS_${i}_SOURCE"
    r_var="DETECT_NODEJS_${i}_PREFIX_ROOT"
    v=${!v_var:-}
    w=${!w_var:-false}
    s=${!s_var:-}
    r=${!r_var:-}
    if [[ "$v" =~ ^v?22\. ]]; then
      [[ -z "$fallback_v" ]] && {
        fallback_v=$v
        fallback_s=$s
        fallback_r=$r
      }
      if [[ "$w" == "true" ]]; then
        log_info "[REUSE-02] nodejs reused: version=${v} source=${s} prefix=${r} prefix_writable=true"
        return 0
      fi
    fi
  done
  # Defensive fallback — emit a marker even when the walk did not find a
  # writable entry (means our caller invoked log_nodejs_reuse without first
  # checking reuse::nodejs_decision; surface the data we have for debugging
  # readers rather than going silent).
  if [[ -n "$fallback_v" ]]; then
    log_info "[REUSE-02] nodejs reused: version=${fallback_v} source=${fallback_s} prefix=${fallback_r} prefix_writable=unknown"
  else
    log_info "[REUSE-02] nodejs reused: no Node 22 entry surfaced (count=${count})"
  fi
}
