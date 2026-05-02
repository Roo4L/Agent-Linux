#!/usr/bin/env bash
set -euo pipefail
# gsd uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.

echo "gsd: removing get-shit-done-cc"

# Step 1: ask the bootstrapper to undo what install.sh wired into ~/.claude/.
# Mirrors the install path's `--global --claude` invocation. Failure is
# non-fatal — the bootstrapper may be a future version that drops the flag
# or the user may have already removed bits manually; the npm uninstall
# below still runs.
if command -v get-shit-done-cc >/dev/null 2>&1; then
  get-shit-done-cc --global --claude --uninstall 2>&1 || \
    echo "gsd uninstall: bootstrapper --uninstall returned non-zero (continuing)" >&2
fi

# Step 2: npm uninstall -g on a missing package exits 0 with "up to date"
# — idempotent. Real truth check is `command -v` below.
npm uninstall -g get-shit-done-cc --no-fund --no-audit >/dev/null 2>&1 || true

# Verify removal. `hash -r` clears bash's command-name cache — without it,
# the prior `get-shit-done-cc --uninstall` invocation hashed the binary's
# path and `command -v` reports it as still-resolvable even after npm
# uninstall -g has deleted the file from disk.
hash -r
if command -v get-shit-done-cc >/dev/null 2>&1; then
  echo "gsd uninstall: get-shit-done-cc still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "gsd: uninstall complete"
