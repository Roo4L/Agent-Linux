#!/usr/bin/env bash
set -euo pipefail
# claude-code install.sh — Phase 4 SCAFFOLD; real native-installer body lands Phase 5 (AGT-02 / AGT-02b).
#
# Runs as the `agent` user via as_user dispatch from the Node CLI.
# Expected env (injected by the dispatcher):
#   AGENTLINUX_PINNED_VERSION  — e.g. 2.1.98
#   AGENTLINUX_SOURCE_KIND     — "script" for this entry
#   AGENTLINUX_AGENT_HOME      — /home/agent
#   PATH/HOME/NPM_CONFIG_PREFIX — inherited from /etc/agentlinux.env shape
#
# Phase 5 body will execute:
#   curl -fsSL https://claude.ai/install.sh | bash -s "${AGENTLINUX_PINNED_VERSION}"
#   # Pitfall 8: check PIPESTATUS to catch curl-404 swallowed by bash -s
#   for ec in "${PIPESTATUS[@]}"; do
#     [[ $ec -eq 0 ]] || { echo "claude install failed (codes: ${PIPESTATUS[*]})" >&2; exit 1; }
#   done
# See docs/decisions/011-stability-first-version-pinning.md + RESEARCH §Pitfall 8.
#
# Phase 4 invariant: THIS FILE MUST EXIT 0 WHEN INVOKED WITH A VALID
# AGENTLINUX_PINNED_VERSION, so Plan 04-03's dispatch unit tests can
# stub-execute it without installing anything. The real body lands in Phase 5.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
echo "claude-code: SCAFFOLD — would install version ${AGENTLINUX_PINNED_VERSION} via native installer in Phase 5"
exit 0
