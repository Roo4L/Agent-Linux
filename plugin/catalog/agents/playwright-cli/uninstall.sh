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
# returns non-zero, we still proceed with the npm uninstall + defensive
# skill directory cleanup below. We do NOT swallow stderr — the tee
# transcript should preserve the actual upstream error if there is one.
if command -v playwright-cli >/dev/null 2>&1; then
  playwright-cli install --skills --uninstall \
    || playwright-cli uninstall --skills \
    || echo "playwright-cli uninstall: bootstrapper teardown returned non-zero (continuing)" >&2
fi

# Step 2: defensive removal of the playwright-cli skill dirs under
# ~/.claude/skills/. Anchor the match on `playwright-cli` (mirroring the
# install side) so an unrelated user-authored `~/.claude/skills/playwright-
# notes/` is NOT collateral damage. `-name` (not `-iname`) is sufficient
# because upstream's skill dir is conventionally lower-case-kebab.
find "${AGENTLINUX_AGENT_HOME}/.claude/skills" -maxdepth 1 -type d -name 'playwright-cli*' \
  -exec rm -rf {} + \
  || true

# Step 3: npm uninstall -g. Idempotent on missing package.
npm uninstall -g @playwright/cli --no-fund --no-audit >/dev/null 2>&1 || true

# Step 4: clear bash's command hash so command -v reflects on-disk state.
hash -r

if command -v playwright-cli >/dev/null 2>&1; then
  echo "playwright-cli uninstall: playwright-cli still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "playwright-cli: uninstall complete"
