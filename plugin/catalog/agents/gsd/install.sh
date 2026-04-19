#!/usr/bin/env bash
set -euo pipefail
# gsd install.sh — Phase 4 SCAFFOLD; real body lands Phase 5 (AGT-04).
#
# npm_package_name: get-shit-done-cc (verified via npm registry 2026-04-18)
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix
#
# Phase 5 body will execute:
#   npm install -g "get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"
# WITHOUT privilege escalation (ADR-004 keystone); the CLI dispatcher already runs this as agent.
# npm auto-uses NPM_CONFIG_PREFIX=/home/agent/.npm-global from /etc/agentlinux.env.
#
# Phase 4 invariant: THIS FILE MUST EXIT 0 WHEN INVOKED WITH A VALID
# AGENTLINUX_PINNED_VERSION — stub dispatch-path testing only.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
echo "gsd: SCAFFOLD — would install get-shit-done-cc@${AGENTLINUX_PINNED_VERSION} in Phase 5"
exit 0
