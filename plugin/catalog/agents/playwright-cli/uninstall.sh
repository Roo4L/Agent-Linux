#!/usr/bin/env bash
set -euo pipefail
# playwright-cli uninstall.sh — symmetric inverse of install.sh.
#
# Order matters:
#   1. Tear down the wired Claude Code skill (mirror of `--skills` install)
#   2. npm uninstall -g @playwright/cli
#   3. hash -r so command -v reflects on-disk state, not bash's cache

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "playwright-cli: removing @playwright/cli + Claude Code skill"

# Step 1: best-effort skill teardown via the bootstrapper itself. Some
# upstream versions support a symmetric --uninstall flag; if absent or it
# returns non-zero, we still proceed with the npm uninstall + manual skill
# directory cleanup below.
if command -v playwright-cli >/dev/null 2>&1; then
  playwright-cli install --skills --uninstall 2>/dev/null \
    || playwright-cli uninstall --skills 2>/dev/null \
    || true
fi

# Step 2: remove any lingering playwright skill dirs under ~/.claude/skills/
# (defensive — the bootstrapper's --uninstall coverage may not match
#  whatever version is installed).
find "${AGENTLINUX_AGENT_HOME}/.claude/skills" -maxdepth 2 -iname '*playwright*' \
  -exec rm -rf {} + 2>/dev/null || true

# Step 3: npm uninstall -g. Idempotent on missing package.
npm uninstall -g @playwright/cli --no-fund --no-audit >/dev/null 2>&1 || true

# Step 4: clear bash's command hash so command -v reflects on-disk state.
hash -r

if command -v playwright-cli >/dev/null 2>&1; then
  echo "playwright-cli uninstall: playwright-cli still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "playwright-cli: uninstall complete"
