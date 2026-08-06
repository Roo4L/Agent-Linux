#!/usr/bin/env bash
set -euo pipefail
# sentry-cli uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.
# @sentry/cli's bundled binary lives inside the npm package dir, so removing the
# global package removes it too. sentry-cli keeps no separate per-user config dir
# of its own (auth is env-var or an in-repo .sentryclirc the user owns), so there
# is nothing else to clean up.

echo "sentry-cli: removing sentry-cli"

npm uninstall -g @sentry/cli --no-fund --no-audit >/dev/null 2>&1 || true

hash -r
if command -v sentry-cli >/dev/null 2>&1; then
  echo "sentry-cli uninstall: sentry-cli still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "sentry-cli: uninstall complete"
