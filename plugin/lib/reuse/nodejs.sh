#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse/nodejs.sh — REUSE-02 Node.js-compatibility decision.
#
# REUSE if at least one DETECT_NODEJS_* entry satisfies BOTH version /^v?22\./
# AND install_user_can_write_prefix=true. Returns {reuse, create} only — no
# remediate branch (REMEDIATE-01 lives in the npm-prefix layer); otherwise the
# 30-nodejs.sh CREATE path installs a fresh Node 22 LTS.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags; uses `return 1` on error.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_NODEJS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_NODEJS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse/nodejs.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# reuse::nodejs_decision
# Returns `reuse` if detect::nodejs_satisfies_pin AND
# detect::nodejs_prefix_writable both hold, else `create`. NB the two readers
# may match DIFFERENT entries — this looser ANY-satisfies semantics matches the
# dominant brownfield happy path (Node 22 from NodeSource + a writable prefix).
reuse::nodejs_decision() {
  if detect::nodejs_satisfies_pin && detect::nodejs_prefix_writable; then
    printf 'reuse'
    return 0
  fi
  printf 'create'
  return 0
}

# reuse::log_nodejs_reuse
# Emits the [REUSE-02] marker for the first Node-22 + writable-prefix entry.
# Falls back to the first Node-22 entry alone when no full match is found, so
# the log stays useful for diagnostic readers.
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
  # Fallback — emit a marker even when no writable entry was found, rather than
  # going silent.
  if [[ -n "$fallback_v" ]]; then
    log_info "[REUSE-02] nodejs reused: version=${fallback_v} source=${fallback_s} prefix=${fallback_r} prefix_writable=unknown"
  else
    log_info "[REUSE-02] nodejs reused: no Node 22 entry surfaced (count=${count})"
  fi
}

# reuse::npm_prefix_decision
# npm-prefix is a separate layer from Node install: it decides whether the
# global prefix (where `npm install -g` writes) is already correctly-owned.
# Returns {reuse, remediate, create}:
#   create    — DETECT_NPM_PREFIX_SECTION_STATUS=absent (no npm yet)
#   reuse     — DETECT_NPM_PREFIX_USER_WRITABLE=true (install user can write)
#   remediate — otherwise (prefix exists but unwritable; REMEDIATE-01 fixes it)
reuse::npm_prefix_decision() {
  if [[ "${DETECT_NPM_PREFIX_SECTION_STATUS:-absent}" == "absent" ]]; then
    printf 'create'
    return 0
  fi
  if [[ "${DETECT_NPM_PREFIX_USER_WRITABLE:-false}" == "true" ]]; then
    printf 'reuse'
    return 0
  fi
  printf 'remediate'
  return 0
}

# reuse::log_npm_prefix_reuse
# Emits the [REUSE-03b] marker. The `-03b` suffix distinguishes it from
# REUSE-03 (catalog agents) — same slot number, different surface.
reuse::log_npm_prefix_reuse() {
  log_info "[REUSE-03b] npm-prefix reused: path=${DETECT_NPM_PREFIX_PATH:-} owner=${DETECT_NPM_PREFIX_EFFECTIVE_OWNER:-} mode=${DETECT_NPM_PREFIX_EFFECTIVE_MODE:-} install_user_writable=true"
}
