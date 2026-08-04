#!/usr/bin/env bash
set -euo pipefail
# playwright uninstall.sh — symmetric inverse.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "playwright: removing playwright CLI and browser cache"

npm uninstall -g playwright --no-fund --no-audit >/dev/null 2>&1 || true

# Browser cache is large; removal is part of the uninstall contract. Phase 5
# uninstall recipes follow the Phase 4 pattern: first-install artifacts
# cleaned; user config (if any) preserved. ms-playwright cache is purely
# a cached download — removing it is pure space reclamation, not data loss.
rm -rf "${AGENTLINUX_AGENT_HOME}/.cache/ms-playwright"

if command -v playwright >/dev/null 2>&1; then
  echo "playwright uninstall: playwright still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "playwright: uninstall complete"
