#!/usr/bin/env bash
set -euo pipefail
# antigravity-cli uninstall.sh — remove only AgentLinux's binary.
#
# Antigravity's settings, keyring-backed session metadata, skills, and MCP
# configuration live under ~/.gemini and are user-owned state. The catalog
# preserve_paths contract keeps that state through a normal remove/reinstall;
# --purge is the explicit destructive operation.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

target="${AGENTLINUX_AGENT_HOME}/.local/bin/agy"
rm -f -- "$target"
hash -r

if [[ -e "$target" || -L "$target" ]]; then
  echo "antigravity-cli uninstall: owned binary still exists after removal" >&2
  exit 1
fi

echo 'antigravity-cli: uninstall complete (preserved ~/.gemini user state)'
