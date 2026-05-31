#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/user.sh — REMEDIATE-02 (PATH wiring on existing user).
#
# The actual PATH wiring is additive and happens unconditionally in
# 40-path-wiring.sh (ensure_marker_block + write_file_atomic — never touches
# user content outside the managed marker block, no --yes gate). This file just
# emits the transcript marker when the user was REUSED.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags; uses `return 1` on error.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::user::log_path_wiring_remediated
# Emits the [REMEDIATE-02] marker when the user was REUSED — a log hand-off
# between "fresh user" and "existing user, attaching wiring additively". The
# wiring itself is identical to CREATE (the additive primitives converge), and
# runs unconditionally since path-wiring is non-overwriting.
remediate::user::log_path_wiring_remediated() {
  log_info "[REMEDIATE-02] component=user action=path-wiring-additive user=${INSTALL_USER:-agent} (ensure_marker_block + write_file_atomic; user content outside markers preserved)"
}

# remediate::user::log_alt_user_accepted
# Emits the grep-stable [ALT-USER] marker when main()'s alt-user gate accepts
# an alternate install user (called after detect::run_once re-runs against the
# new user, so INSTALL_USER + DETECT_USER_NAME both reflect it).
remediate::user::log_alt_user_accepted() {
  log_info "[ALT-USER] component=user action=alt-user-accepted new_user=${INSTALL_USER:-agent} reason=${DETECT_USER_BAIL_REASON:-unknown}"
}
