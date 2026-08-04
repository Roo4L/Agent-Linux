#!/usr/bin/env bash
set -euo pipefail
# gitleaks uninstall.sh — symmetric inverse of install.sh (Phase 32, DEVT-05).
#
# gitleaks is stateless: it reads a repo/dir and an optional in-repo .gitleaks.toml
# the user owns, and writes no per-user config or cache dir of its own. So a
# symmetric remove is just the binary. Guarded / idempotent — a second remove on a
# missing install exits 0.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "gitleaks: removing gitleaks"

rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/gitleaks"

hash -r
if [[ -e "${AGENTLINUX_AGENT_HOME}/.local/bin/gitleaks" ]]; then
  echo "gitleaks uninstall: ${AGENTLINUX_AGENT_HOME}/.local/bin/gitleaks still present after removal" >&2
  exit 1
fi

echo "gitleaks: uninstall complete"
