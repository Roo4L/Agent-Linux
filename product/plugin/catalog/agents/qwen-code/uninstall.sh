#!/usr/bin/env bash
set -euo pipefail
# qwen-code uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.
# User state under ~/.qwen/ (settings + cached credentials) is preserved per
# preserve_paths.json (CAT-04).

echo "qwen-code: removing @qwen-code/qwen-code"

npm uninstall -g @qwen-code/qwen-code --no-fund --no-audit >/dev/null 2>&1 || true

hash -r
if command -v qwen >/dev/null 2>&1; then
  echo "qwen-code uninstall: qwen still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "qwen-code: uninstall complete (user config under ~/.qwen preserved per CAT-04)"
