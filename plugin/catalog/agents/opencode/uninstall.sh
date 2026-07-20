#!/usr/bin/env bash
set -euo pipefail
# opencode uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.
# User state under ~/.config/opencode/ and ~/.local/share/opencode/ (config +
# stored provider auth) is preserved per preserve_paths.json (CAT-04).

echo "opencode: removing opencode-ai"

npm uninstall -g opencode-ai --no-fund --no-audit >/dev/null 2>&1 || true

hash -r
if command -v opencode >/dev/null 2>&1; then
  echo "opencode uninstall: opencode still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "opencode: uninstall complete (user config preserved per CAT-04)"
