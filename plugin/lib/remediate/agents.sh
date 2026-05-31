#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/agents.sh — REMEDIATE-04 catalog-agent reinstall stub.
#
# The real reinstall path runs through the TypeScript CLI (install.ts —
# preserve_paths + uninstall→install order + sentinel handling). This bash-side
# stub just gives remediate.sh a named target; no bash-driven reinstall exists.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags; uses `return 1` on error.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::agents::reinstall_stub
# No-op placeholder for REMEDIATE-04 broken-agent reinstall; the real flow runs
# in plugin/cli/src/commands/install.ts.
remediate::agents::reinstall_stub() {
  log_info "[REMEDIATE-04] component=agents action=noop (real reinstall runs in the registry CLI: agentlinux install)"
  return 0
}
