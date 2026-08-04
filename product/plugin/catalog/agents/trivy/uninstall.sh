#!/usr/bin/env bash
set -euo pipefail
# trivy uninstall.sh — symmetric inverse of install.sh (Phase 31, DEVT-04).
#
# Removes the binary AgentLinux installed plus trivy's own cache dir
# (~/.cache/trivy, where trivy stores its downloaded vulnerability DB). Every step
# is guarded / idempotent, so a second remove on a missing install exits 0.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "trivy: removing trivy"

rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/trivy"
rm -rf "${AGENTLINUX_AGENT_HOME}/.cache/trivy"

hash -r
if [[ -e "${AGENTLINUX_AGENT_HOME}/.local/bin/trivy" ]]; then
  echo "trivy uninstall: ${AGENTLINUX_AGENT_HOME}/.local/bin/trivy still present after removal" >&2
  exit 1
fi

echo "trivy: uninstall complete"
