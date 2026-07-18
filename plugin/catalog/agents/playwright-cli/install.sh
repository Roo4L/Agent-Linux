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
# @playwright/cli's VERY FIRST invocation in a pristine environment (cold npm
# install, no prior run) can print an empty line before it settles and reports
# the real version on the next call — observed with 0.1.15 on fresh CI runners.
# Probe a few times so a cold first-run empty does not fail the whole install;
# the version is stable by the second call.
pw_version=""
for _ in 1 2 3 4 5; do
  # `|| true`: under `set -euo pipefail` a cold `--version` that exits non-zero
  # (or SIGPIPEs `head`) would otherwise abort the script on iteration 1 before
  # the retry can help — and bypass the informative `!= pin` diagnostic below.
  # The loop owns retry/failure; a persistent miss still fails closed at the pin
  # check with a clear message.
  pw_version=$(playwright-cli --version 2>&1 | head -1 | tr -d '[:space:]') || true
  [[ -n "$pw_version" ]] && break
  sleep 1
done
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
#
# Must run from a writable CWD: `playwright-cli install` calls
# initWorkspace() which mkdirs ./.playwright in the current directory.
# AgentLinux dispatches recipes from /opt/agentlinux-src/ (read-only repo
# copy in Docker / read-only workspace in QEMU), so a bare invocation
# crashes with EACCES on .playwright. Anchor CWD to agent-home (always
# writable, agent-owned) so the workspace dir lives at
# /home/agent/.playwright — a per-user side-effect that purge cleans via
# `userdel -r agent`.
( cd "${AGENTLINUX_AGENT_HOME}" && playwright-cli install --skills ) \
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

# WIRE-01 (cross-agent skill wiring): the Claude-format skill the bootstrapper
# just dropped is portable as-is to the other coding agents AgentLinux ships —
# its SKILL.md (a directory with YAML `name`/`description` frontmatter) is the
# same shape codex and opencode read. We mirror it into the cross-tool
# `~/.agents/skills/` convention, which BOTH codex and opencode scan for
# user-level skills. opencode additionally reads `~/.claude/skills/` directly,
# so it is already covered; the copy is what lights the skill up inside codex.
# The copy is UNCONDITIONAL (independent of whether codex/opencode are installed
# yet) so the wiring is install-order-independent: a codex installed later finds
# the skill already present. gemini-cli and qwen-code have no skill host (only
# prompt-style commands), so Playwright is not-applicable there — a multi-file
# skill with a references/ tree does not round-trip to a single command prompt.
wire_agents_skills_dir="${AGENTLINUX_AGENT_HOME}/.agents/skills"
mkdir -p "$wire_agents_skills_dir"
while IFS= read -r -d '' pw_skill; do
  dest="${wire_agents_skills_dir}/$(basename "$pw_skill")"
  # Refresh idempotently: drop a stale copy, then re-copy the current skill so a
  # pin bump (newer SKILL.md / references/) propagates on reinstall.
  rm -rf -- "$dest"
  cp -R -- "$pw_skill" "$dest"
  echo "playwright-cli: mirrored skill into ${dest} (codex/opencode ~/.agents/skills scan)"
done < <(find "$skill_dir" -maxdepth 1 -type d -name 'playwright-cli*' -print0 2>/dev/null)

echo "playwright-cli: install complete (binary at ${bin_path}; skill wired into ${skill_dir}/playwright-cli + ${wire_agents_skills_dir})"
