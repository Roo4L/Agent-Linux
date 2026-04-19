#!/usr/bin/env bash
set -euo pipefail
# claude-code uninstall.sh — Phase 4 SCAFFOLD; real body lands Phase 5.
#
# Phase 5 body will execute (for native install):
#   rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/claude"
#   rm -rf "${AGENTLINUX_AGENT_HOME}/.local/share/claude"
#   rm -rf "${AGENTLINUX_AGENT_HOME}/.config/claude"
# Idempotent: every rm is a no-op on missing target.

echo "claude-code: SCAFFOLD — would remove native Claude Code install in Phase 5"
exit 0
