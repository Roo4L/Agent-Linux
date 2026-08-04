#!/usr/bin/env bash
set -euo pipefail
# ccusage uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.
# ccusage owns no per-user state (it only reads ~/.claude usage logs, which
# belong to Claude Code, not ccusage), so there is nothing to preserve or
# clean up beyond removing the global package.

echo "ccusage: removing ccusage"

npm uninstall -g ccusage --no-fund --no-audit >/dev/null 2>&1 || true

hash -r
if command -v ccusage >/dev/null 2>&1; then
  echo "ccusage uninstall: ccusage still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "ccusage: uninstall complete"
