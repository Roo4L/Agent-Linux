#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/agents.sh — REMEDIATE-04 marker (no bash-side handler).
#
# There is deliberately NO agent-reinstall function here. Catalog agents are
# installed/reinstalled by the TypeScript registry CLI (install.ts — it owns
# preserve_paths, the uninstall→install order, and sentinel handling), not by a
# provisioner during `agentlinux-install`. The bash decision layer only computes
# RESOLUTIONS[agents.<id>] and gates a bail when --yes is absent; the actual
# REMEDIATE-04 reinstall happens later via `agentlinux install <name>`.
#
# This file exists as the documented placeholder for the agents component so a
# reader looking for the handler finds the CLI pointer above.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi
