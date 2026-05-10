#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/npm_prefix.sh — DET-03 npm global prefix discovery probe.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, and the log.sh / as_user.sh
# dependencies from the entrypoint. MUST NOT set its own strict-mode flags.
# Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# WAVE-0 STUB (Plan 12-01). Symbol set is the locked Phase 12→13 contract;
# bodies fill in Plan 12-02 (per-user prefix from ~/.npmrc + system fallback +
# effective-resolved + writability — three-way report per Pitfall 2). The real
# probe MUST use as_user_login (NOT as_user) so the install user's
# NPM_CONFIG_PREFIX export from ~/.bashrc is honored — Pitfall 7 territory.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_NPM_PREFIX_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_NPM_PREFIX_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/npm_prefix.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect::npm_prefix_probe <user> <fragment_path>
#
# STUB: emits an `{npm_prefix: {npm_present: false, ...nulls...}}` object.
# Plan 12-02 replaces the body with the three-way per-user / system / effective
# probe via `as_user_login` (Pitfall 7).
detect::npm_prefix_probe() {
  local user=$1 fragment_path=$2
  jq -n --arg user "$user" \
    '{npm_prefix: {npm_present: false, user_prefix: null, system_prefix: null, effective_prefix: null}}' \
    >"$fragment_path"
  export DETECT_NPM_PREFIX_PATH=""
  export DETECT_NPM_PREFIX_USER_WRITABLE=false
  export DETECT_NPM_PREFIX_SECTION_STATUS=stub
}

# --- Phase 13 reader functions (CONTEXT.md "Phase 12 → Phase 13 contract") ---
# Stubs return empty / false-equivalent values until Plan 12-02 wires the
# probe body.

detect::npm_prefix_path() { printf '%s' "${DETECT_NPM_PREFIX_PATH:-}"; }
detect::npm_prefix_writable_by_install_user() {
  [[ "${DETECT_NPM_PREFIX_USER_WRITABLE:-false}" == "true" ]]
}
