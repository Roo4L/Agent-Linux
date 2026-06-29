#!/usr/bin/env bash
set -euo pipefail
# gemini-cli uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.
# User state under ~/.gemini/ (settings + cached OAuth creds) is preserved per
# preserve_paths.json (CAT-04) — we never touch it here.

echo "gemini-cli: removing @google/gemini-cli"

npm uninstall -g @google/gemini-cli --no-fund --no-audit >/dev/null 2>&1 || true

hash -r
if command -v gemini >/dev/null 2>&1; then
  echo "gemini-cli uninstall: gemini still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "gemini-cli: uninstall complete (user config under ~/.gemini preserved per CAT-04)"
