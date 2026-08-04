#!/usr/bin/env bash
set -euo pipefail
# test-dummy uninstall.sh — symmetric inverse of install.sh.
# Idempotent: rm -f is a no-op on missing file.
readonly MARKER="/tmp/agentlinux-test-dummy.marker"
rm -f -- "$MARKER"
echo "test-dummy: removed ${MARKER}"
