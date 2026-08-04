#!/usr/bin/env bash
set -euo pipefail
# test-dummy install.sh — exercises the CLI dispatch path without network.
# Honors AGENTLINUX_PINNED_VERSION so bats can assert the version wiring.
# Requirement IDs: CLI-03 (install dispatch), CAT-04 (pinned version honored), CAT-03 (recipe shape).

readonly MARKER="/tmp/agentlinux-test-dummy.marker"
printf 'version=%s\ninstalled_at=%s\n' \
  "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"$MARKER"
echo "test-dummy: wrote ${MARKER}"
