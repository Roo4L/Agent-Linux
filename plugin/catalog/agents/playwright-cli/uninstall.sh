#!/usr/bin/env bash
set -euo pipefail
# playwright-cli uninstall.sh — symmetric inverse of install.sh.
# Order: tear down the wired Claude Code skill → npm uninstall -g → hash -r.
# CAT-04: AGENTLINUX_PRESERVE_PATHS keeps ~/.cache/ms-playwright (browser
# binaries are hundreds of MB to re-download) across REMEDIATE-04.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# _should_remove <abs-path> — returns 0 (proceed with rm) unless <abs-path> is
# in or under any AGENTLINUX_PRESERVE_PATHS entry. The env var is a
# colon-separated list of HOME-relative paths (normalized by the loader); empty
# means "no preserves". Descendant rule: a preserved root protects everything
# beneath it.
_should_remove() {
  local target=$1
  [[ -z "${AGENTLINUX_PRESERVE_PATHS:-}" ]] && return 0
  local t_strip="${target%/}"
  local IFS=:
  local preserved
  for preserved in $AGENTLINUX_PRESERVE_PATHS; do
    local p_strip="${preserved%/}"
    if [[ "$t_strip" == "${AGENTLINUX_AGENT_HOME}/${p_strip}" \
       || "$t_strip" == "${AGENTLINUX_AGENT_HOME}/${p_strip}/"* ]]; then
      return 1
    fi
  done
  return 0
}

echo "playwright-cli: removing @playwright/cli + Claude Code skill"

# Step 1: best-effort skill teardown via the bootstrapper. If it's absent or
# fails we still proceed with the npm uninstall + defensive cleanup below.
# stderr is not swallowed so the transcript keeps any upstream error.
if command -v playwright-cli >/dev/null 2>&1; then
  playwright-cli install --skills --uninstall \
    || playwright-cli uninstall --skills \
    || echo "playwright-cli uninstall: bootstrapper teardown returned non-zero (continuing)" >&2
fi

# Step 2: defensive removal of the playwright-cli skill dirs under
# ~/.claude/skills/. The match is anchored on `playwright-cli` so an unrelated
# user-authored dir isn't collateral damage. Looping (not find -exec) so each
# entry runs through _should_remove; these dirs aren't in the preserve set, so
# rm proceeds.
# WIRE-01: also tear down the cross-agent mirror under ~/.agents/skills/
# (codex/opencode shared skill scan path) that install.sh created. Same
# `playwright-cli`-anchored match + preserve gate as the ~/.claude/skills sweep.
while IFS= read -r -d '' skill_dir; do
  if _should_remove "$skill_dir"; then
    rm -rf -- "$skill_dir" || true
  else
    echo "playwright-cli uninstall: preserving ${skill_dir} (AGENTLINUX_PRESERVE_PATHS)"
  fi
done < <(find "${AGENTLINUX_AGENT_HOME}/.claude/skills" "${AGENTLINUX_AGENT_HOME}/.agents/skills" -maxdepth 1 -type d -name 'playwright-cli*' -print0 2>/dev/null)

# Step 3: npm uninstall -g. Idempotent on missing package.
npm uninstall -g @playwright/cli --no-fund --no-audit >/dev/null 2>&1 || true

# Step 4: clear bash's command hash so command -v reflects on-disk state.
hash -r

if command -v playwright-cli >/dev/null 2>&1; then
  echo "playwright-cli uninstall: playwright-cli still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "playwright-cli: uninstall complete"
