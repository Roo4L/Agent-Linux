#!/usr/bin/env bash
set -euo pipefail
# codex uninstall.sh — symmetric inverse of install.sh. npm uninstall -g is
# idempotent (exits 0 "up to date" on a missing package). User state under
# ~/.codex/ (config.toml + auth credentials) is deliberately NOT removed —
# preserve_paths.json lists it so it survives a REMEDIATE-04 reinstall (CAT-04).

echo "codex: removing @openai/codex"

npm uninstall -g @openai/codex --no-fund --no-audit >/dev/null 2>&1 || true

# `hash -r` clears bash's command-name cache so `command -v` reflects the
# on-disk truth after npm deleted the shim (mirrors the gsd recipe).
hash -r
if command -v codex >/dev/null 2>&1; then
  echo "codex uninstall: codex still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "codex: uninstall complete (user config under ~/.codex preserved per CAT-04)"
