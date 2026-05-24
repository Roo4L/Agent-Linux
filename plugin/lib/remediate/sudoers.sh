#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/sudoers.sh — REMEDIATE-03 sudoers Remediate stubs.
#
# Phase 14 Plan 14-01 ships ONLY the stubs; Plan 14-02 lands the real bodies.
# Two distinct actions per CONTEXT.md Area 1 Q1:
#   - sudoers-missing-install  — additive write of /etc/sudoers.d/agentlinux
#                                when absent (no consent gate consulted).
#   - sudoers-drift-overwrite  — overwrite a present-but-drifted sudoers
#                                drop-in with the canonical ADR-012 line
#                                (state-overwriting; consent gate enforced
#                                in collect_all_decisions before dispatch).
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/remediate.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_SUDOERS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_SUDOERS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/sudoers.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::sudoers::install_stub
#
# Additive missing-file install. Plan 14-02 replaces with the body that
# installs /etc/sudoers.d/agentlinux when DETECT_SUDOERS_PRESENT=false. No
# --yes consent gate consulted — writing a new file in a controlled directory
# is not state-overwriting per CONTEXT.md Area 1 Q1.
remediate::sudoers::install_stub() {
  log_info "[REMEDIATE-03] component=sudoers action=stub (Plan 14-02 replaces with install body)"
  return 0
}

# remediate::sudoers::overwrite_stub
#
# State-overwriting drift overwrite. Plan 14-02 replaces with the body that
# atomically replaces a drifted /etc/sudoers.d/agentlinux with the canonical
# ADR-012 line (`agent ALL=(ALL) NOPASSWD: ALL`). The consent gate in
# remediate.sh has already enforced --yes by the time this stub is dispatched.
remediate::sudoers::overwrite_stub() {
  log_info "[REMEDIATE-03] component=sudoers action=stub (Plan 14-02 replaces with overwrite body)"
  return 0
}
