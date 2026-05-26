#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/user.sh — REMEDIATE-02 (PATH wiring on existing user).
#
# Phase 14 Plan 14-02 lands the [REMEDIATE-02] log marker. The actual additive
# PATH wiring happens unconditionally in 40-path-wiring.sh via
# ensure_marker_block + write_file_atomic primitives — REMEDIATE-02 is the
# canonical additive remediate (CONTEXT.md Area 1 Q1: never overwrites user
# content outside the AGENTLINUX-managed marker block, no --yes gate consulted).
# This file just emits the transcript marker when the user was REUSED so the
# operator can distinguish "re-attaching PATH wiring to a pre-existing user"
# from "creating PATH wiring for a fresh user".
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

# remediate::user::log_path_wiring_remediated
#
# Emits the [REMEDIATE-02] transcript marker that fires when the user was
# REUSED (REUSED_USER=true sentinel set by 10-agent-user.sh's REUSE branch).
# Called from 40-path-wiring.sh near the top so the marker appears BEFORE the
# additive ensure_marker_block / write_file_atomic calls do their work — gives
# the operator a clear hand-off in the log between "user was created from
# scratch" and "user was already there, we're attaching wiring additively".
#
# This is the ONLY mutation-distinguished marker in REMEDIATE-02. The actual
# wiring is identical to the CREATE branch because the additive primitives
# (ensure_marker_block, write_file_atomic) converge regardless of whether
# the target already exists. CONTEXT.md Area 1 Q1: "no interactive consent
# required for PATH wiring (additive, idempotent, never overwrites user
# content)" — the gate in remediate.sh's remediate_action_overwrites_state
# returns FALSE for `path-wiring`, so this path runs unconditionally.
remediate::user::log_path_wiring_remediated() {
  log_info "[REMEDIATE-02] component=user action=path-wiring-additive user=${INSTALL_USER:-agent} (ensure_marker_block + write_file_atomic; user content outside markers preserved)"
}

# remediate::user::path_wiring_stub (LEGACY symbol kept for source compat).
remediate::user::path_wiring_stub() {
  remediate::user::log_path_wiring_remediated
}

# remediate::user::log_alt_user_accepted
#
# Plan 15-02 (UX-04). Emits a stable [ALT-USER] marker line for transcript
# visibility when main()'s alt-user gate accepts an alternate install user.
# Called by main() AFTER prompt::alt_user_or_bail returns 0 (TTY mode) and
# AFTER detect::run_once is re-run against the new user — at which point
# INSTALL_USER + DETECT_USER_NAME both reflect the alt user.
#
# The marker is grep-stable for the bats @tests and audit-doc cross-refs.
remediate::user::log_alt_user_accepted() {
  log_info "[ALT-USER] component=user action=alt-user-accepted new_user=${INSTALL_USER:-agent} reason=${DETECT_USER_BAIL_REASON:-unknown}"
}
