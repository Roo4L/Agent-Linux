#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/nodejs.sh — DET-02 Node.js multi-source discovery probe.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, and the log.sh dependency from the
# entrypoint. MUST NOT set its own strict-mode flags. Uses `return 1` (not
# `exit 1`) on any error path — sourced fragment.
#
# WAVE-0 STUB (Plan 12-01). Symbol set is the locked Phase 12→13 contract;
# bodies fill in Plan 12-02 (8-source detection: NodeSource APT, distro APT,
# nvm, fnm, volta, mise, asdf-node, pnpm-managed, manual /usr/local/bin/node).
# Stub emits an empty array and returns null/false-equivalent values from the
# reader functions so the orchestrator + renderer + JSON merge are end-to-end
# exercisable today.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_NODEJS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_NODEJS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/nodejs.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect::nodejs_probe <user> <home> <fragment_path>
#
# STUB: emits an empty `{nodejs: []}` array. Plan 12-02 replaces the body with
# canonical-path file-existence enumeration across 8 manager sources (no
# shell-init sourcing — Pitfall 1 territory).
detect::nodejs_probe() {
  local user=$1 home=$2 fragment_path=$3
  # shellcheck disable=SC2034
  # user / home are part of the locked symbol contract; Plan 12-02 uses both
  # to scope find -maxdepth probes under $home/.nvm, $home/.local/share/fnm
  # etc. and to invoke `as_user "$user" "$bin_path" --version` for per-binary
  # version capture. Deliberately unused in this stub.
  : "$user" "$home"
  jq -n '{nodejs: []}' >"$fragment_path"
  export DETECT_NODEJS_COUNT=0
  export DETECT_NODEJS_SECTION_STATUS=stub
}

# --- Phase 13 reader functions (CONTEXT.md "Phase 12 → Phase 13 contract") ---
# Stubs return false-equivalent values until Plan 12-02 wires the probe body.

detect::nodejs_satisfies_pin() { return 1; }   # stub: never satisfies until Plan 12-02
detect::nodejs_prefix_writable() { return 1; } # stub
