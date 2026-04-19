#!/usr/bin/env bash
set -euo pipefail
# playwright install.sh — Phase 4 SCAFFOLD; real body lands Phase 5 (AGT-05).
#
# npm_package_name: playwright (verified 1.59.1 via npm registry 2026-04-18)
# source_kind: npm
#
# Phase 5 body will execute:
#   npm install -g "playwright@${AGENTLINUX_PINNED_VERSION}"
#   npx playwright install             # downloads browser binaries to ~/.cache/ms-playwright
# WITHOUT privilege escalation; browser cache goes under the agent user's home (ADR-004 + AGT-05).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
echo "playwright: SCAFFOLD — would install playwright@${AGENTLINUX_PINNED_VERSION} + browsers in Phase 5"
exit 0
