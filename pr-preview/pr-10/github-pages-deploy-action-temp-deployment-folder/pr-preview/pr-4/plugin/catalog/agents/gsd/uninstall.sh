#!/usr/bin/env bash
set -euo pipefail
# gsd uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.

echo "gsd: removing get-shit-done-cc"

# npm uninstall -g on a missing package exits 0 with "up to date" — idempotent.
# We don't check npm's exit status aggressively; the post-step `command -v`
# check is the real truth.
npm uninstall -g get-shit-done-cc --no-fund --no-audit >/dev/null 2>&1 || true

# Verify removal.
if command -v get-shit-done-cc >/dev/null 2>&1; then
  echo "gsd uninstall: get-shit-done-cc still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "gsd: uninstall complete"
