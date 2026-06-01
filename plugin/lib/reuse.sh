#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse.sh — reuse-decision orchestrator.
#
# Sourced after detect::run_once, before run_provisioners. The per-component
# decision functions (reuse::user_decision, reuse::nodejs_decision, …) live in
# the sibling files under reuse/ and consume the DETECT_* exports. Each returns
# ONE of {reuse, create, remediate, bail} on stdout; the provisioner-side
# `case "$(reuse::<X>_decision)" in` block is the dispatcher.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh/as_user.sh
# from the entrypoint; MUST NOT set its own strict-mode flags; uses `return 1`.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Split declare/assign per SC2155 so a cmdsub failure surfaces as non-zero.
REUSE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/reuse" && pwd)
readonly REUSE_LIB_DIR

# Per-component decision functions (own source-once guards; safe to re-source).
# shellcheck source=reuse/user.sh
. "$REUSE_LIB_DIR/user.sh"
# shellcheck source=reuse/nodejs.sh
. "$REUSE_LIB_DIR/nodejs.sh"
# shellcheck source=reuse/agents.sh
. "$REUSE_LIB_DIR/agents.sh"
