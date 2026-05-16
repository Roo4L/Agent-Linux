#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse.sh — reuse-decision orchestrator (Phase 13).
#
# Sourced by plugin/bin/agentlinux-install AFTER plugin/lib/detect.sh +
# detect::run_once, BEFORE run_provisioners. The per-component decision
# functions (reuse::user_decision, reuse::nodejs_decision, …) live in the
# sibling files under plugin/lib/reuse/ and consume the in-process DETECT_*
# env exports populated by detect::run_once.
#
# Each decision function returns ONE of {reuse, create, remediate, bail} on
# stdout. The provisioner-side `case "$(reuse::<X>_decision)" in` block is the
# dispatcher; Phase 14 will extend the remediate / bail branches into real
# handlers WITHOUT changing the dispatch shape (CONTEXT.md "Phase 13 → Phase
# 14 contract" — binding).
#
# Inherits `set -euo pipefail`, the ERR trap, the tee redirect, and the log.sh
# / as_user.sh dependencies from the entrypoint. MUST NOT set its own
# strict-mode flags. Uses `return 1` (not `exit 1`) on any error path —
# sourced fragment (pattern from plugin/provisioner/30-nodejs.sh:71).
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Resolve the per-component dir relative to this file. Split declare/assign per
# SC2155 so a cmdsub failure surfaces as non-zero rather than being masked by
# the readonly wrapper. Same idiom as plugin/lib/detect.sh DETECT_LIB_DIR.
REUSE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/reuse" && pwd)
readonly REUSE_LIB_DIR

# Source per-component decision functions. (Caller — agentlinux-install — has
# already sourced log.sh + as_user.sh + detect.sh.) Per-component files have
# their own source-once guards; safe to re-source.
# shellcheck source=reuse/user.sh
. "$REUSE_LIB_DIR/user.sh"
# shellcheck source=reuse/nodejs.sh
. "$REUSE_LIB_DIR/nodejs.sh"

# Plan 13-02 will append a `. "$REUSE_LIB_DIR/agents.sh"` line here for the
# REUSE-03 catalog-agent decision; the dispatch surface stays unchanged.
