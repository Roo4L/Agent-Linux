#!/usr/bin/env bash
set -euo pipefail
# playwright-cli install.sh — Microsoft's @playwright/cli for coding agents.
#
# Two-part install:
#   (1) npm install -g @playwright/cli@$PIN     — bootstrapper binary at
#                                                 ~agent/.npm-global/bin/playwright-cli
#   (2) playwright-cli install --skills          — wires the bundled Claude
#                                                 Code skill into
#                                                 ~/.claude/skills/playwright-cli/
#
# Discovered by user dogfood: npm-installing the package alone leaves the
# binary on PATH but Claude Code sees no /playwright-cli skills. The
# `--skills` invocation is what makes the user-visible intent ("install
# Playwright CLI for the agent") work end-to-end.
#
# References:
#   - https://playwright.dev/agent-cli/installation
#   - https://www.npmjs.com/package/@playwright/cli
#   - npm view @playwright/cli bin → { 'playwright-cli': 'playwright-cli.js' }

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "playwright-cli: installing @playwright/cli@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@playwright/cli@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v playwright-cli || true)
if [[ -z "$bin_path" ]]; then
  echo "playwright-cli install: playwright-cli not on PATH after npm install -g" >&2
  exit 1
fi

# Verify CLI version matches pin before invoking the skill bootstrapper.
pw_version=$(playwright-cli --version 2>&1 | head -1 | tr -d '[:space:]')
if [[ "$pw_version" != "${AGENTLINUX_PINNED_VERSION}" ]]; then
  printf 'playwright-cli install: pinned=%s but --version: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$pw_version" >&2
  exit 1
fi

echo "playwright-cli: CLI at ${bin_path}, version ${pw_version}"
echo "playwright-cli: wiring Claude Code skill via 'playwright-cli install --skills'"

# Bootstrap the bundled Claude Code skill into ~/.claude/skills/.
# Non-fatal: upstream may exit non-zero on re-runs / "already installed"
# paths; what we actually care about is that the skill landed on disk —
# verified below.
playwright-cli install --skills \
  || echo "playwright-cli install: bootstrapper exited non-zero (re-run / partial-state); verifying skill anyway" >&2

# Sanity-check the skill landed where Claude Code looks for it. Anchor
# the match on `playwright-cli` (mirrors install side) — a broader
# `*playwright*` would match unrelated user-installed skills.
skill_dir="${AGENTLINUX_AGENT_HOME}/.claude/skills"
mkdir -p "$skill_dir"
if ! find "$skill_dir" -maxdepth 1 -type d -name 'playwright-cli*' -print -quit 2>/dev/null | grep -q .; then
  printf 'playwright-cli install: no playwright-cli skill found under %s after bootstrapper run\n' "$skill_dir" >&2
  exit 1
fi

echo "playwright-cli: install complete (binary at ${bin_path}; skill wired into ${skill_dir}/playwright-cli)"
