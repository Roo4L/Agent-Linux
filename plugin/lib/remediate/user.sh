#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/user.sh — REMEDIATE-02 (PATH wiring) user-side stubs.
#
# Phase 14 Plan 14-01 ships ONLY the stubs; Plan 14-02 lands real bodies. The
# REMEDIATE-02 PATH-wiring action is additive (ensure_marker_block — never
# touches user content outside the marker), so it does NOT consult the --yes
# consent gate (remediate_action_overwrites_state returns false for
# `path-wiring`). The bash-side handler here exists so the dispatch surface in
# 40-path-wiring.sh has a target name to call; Plan 14-02 may expand this.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/remediate.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::user::path_wiring_stub
#
# Stub for REMEDIATE-02 PATH wiring. Plan 14-02 replaces with the real body
# that re-asserts the AGENTLINUX-managed marker block in ~user/.bashrc when
# the existing block is missing or drifted. The action is additive — no --yes
# consent gate is consulted (CONTEXT.md Area 1 Q1).
remediate::user::path_wiring_stub() {
  log_info "[REMEDIATE-02] component=user action=stub (Plan 14-02 replaces with real body)"
  return 0
}
