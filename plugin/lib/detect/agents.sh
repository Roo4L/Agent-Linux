#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/agents.sh — DET-04 catalog agent discovery probe.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, and the log.sh / as_user.sh
# dependencies from the entrypoint. MUST NOT set its own strict-mode flags.
# Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# WAVE-0 STUB (Plan 12-01). Symbol set is the locked Phase 12→13 contract;
# bodies fill in Plan 12-02. The real probe targets the catalog-truth binary
# names (per the DET-04 amendment in REQUIREMENTS.md): catalog ids
# `claude-code` / `gsd` / `playwright-cli` map to binaries `claude` /
# `get-shit-done-cc` / `playwright-cli` respectively. Stub emits an empty array
# so the orchestrator + JSON merge are end-to-end exercisable today.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect::agents_probe <user> <fragment_path>
#
# STUB: emits an empty `{agents: []}` array. Plan 12-02 replaces the body with
# per-agent probes that resolve binaries via `as_user "$user" command -v <bin>`
# (Pitfall 4 PATH-visibility mitigation), capture version + ownership + health,
# and classify each entry as healthy / broken / absent.
detect::agents_probe() {
  local user=$1 fragment_path=$2
  # shellcheck disable=SC2034
  # user is part of the locked symbol contract; Plan 12-02 uses it for
  # `as_user "$user" command -v <bin>` and `as_user "$user" "$bin" --version`.
  : "$user"
  jq -n '{agents: []}' >"$fragment_path"
  export DETECT_AGENTS_SECTION_STATUS=stub
}

# --- Phase 13 reader functions (CONTEXT.md "Phase 12 → Phase 13 contract") ---
# Stubs return "absent" for every catalog id until Plan 12-02 wires the probe
# body. Phase 13's REUSE-03 short-circuit only fires when this returns
# "healthy", so the stub is safe — Phase 13 sees every agent as needing the
# greenfield Create path.

detect::agent_status() {
  # shellcheck disable=SC2034
  # Plan 12-02 reads $1 to look up DETECT_AGENT_<UPPER>_STATUS exports;
  # stub ignores it and always returns "absent".
  local id=${1:-}
  : "$id"
  printf 'absent'
}
