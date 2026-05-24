#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/agents.sh — REMEDIATE-04 catalog-agent reinstall stub.
#
# Phase 14 Plan 14-01 ships ONLY the bash-side stub; Plan 14-03 wires the real
# REMEDIATE-04 path through the TypeScript CLI (install.ts), which is the
# canonical reinstall surface for catalog agents — see CONTEXT.md Area 3
# (preserve_paths + uninstall→install order + sentinel handling). The
# bash-side stub here exists so the orchestrator surface in remediate.sh has a
# named target for future bash-driven reinstall paths (currently none — every
# catalog-agent install runs via the CLI's runner.ts dispatcher).
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/remediate.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::agents::reinstall_stub
#
# Stub for REMEDIATE-04 broken-agent reinstall. Plan 14-03 wires the real
# reinstall flow through plugin/cli/src/commands/install.ts (preserve_paths
# filtering + uninstall → install order + sentinel rewrite). The bash-side
# stub here is a no-op placeholder.
remediate::agents::reinstall_stub() {
  log_info "[REMEDIATE-04] component=agents action=stub (Plan 14-03 wires real CLI install.ts path)"
  return 0
}
