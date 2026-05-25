#!/usr/bin/env bash
set -euo pipefail
# playwright-cli uninstall.sh — symmetric inverse of install.sh.
#
# Order matters:
#   1. Tear down the wired Claude Code skill (mirror of `--skills` install)
#   2. npm uninstall -g @playwright/cli
#   3. hash -r so command -v reflects on-disk state, not bash's cache
#
# Plan 14-03 (REMEDIATE-04 CAT-04): AGENTLINUX_PRESERVE_PATHS contains
# `.cache/ms-playwright` for this agent — Playwright browser binaries are
# expensive to re-download (hundreds of MB) so they survive REMEDIATE-04.
# Bats Test 50 verifies the preserve via a small fixture.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# _should_remove <abs-path>
#
# Returns 0 (true → proceed with rm) iff <abs-path> is NOT in or under any
# entry of AGENTLINUX_PRESERVE_PATHS. The env var is a colon-separated list
# of HOME-relative paths (already normalized + traversal-rejected by the
# loader). Empty env var means "no preserves" → always return 0.
#
# Descendant rule: if a preserved entry P is the target T, OR T is anywhere
# beneath P (T starts with "${HOME}/${P}/"), the rm is skipped.
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
# Per-match loop so each entry runs through _should_remove. Skill dirs under
# ~/.claude/skills/playwright-cli* are NOT in the playwright preserve set
# (~/.cache/ms-playwright/), so the gate proceeds with rm — matching the
# pre-Plan-14-03 behavior. Plan 14-03 only gates the cache dir.
while IFS= read -r -d '' skill_dir; do
  if _should_remove "$skill_dir"; then
    rm -rf -- "$skill_dir" || true
  else
    echo "playwright-cli uninstall: preserving ${skill_dir} (AGENTLINUX_PRESERVE_PATHS)"
  fi
done < <(find "${AGENTLINUX_AGENT_HOME}/.claude/skills" -maxdepth 1 -type d -name 'playwright-cli*' -print0 2>/dev/null)

# Step 3: npm uninstall -g. Idempotent on missing package.
npm uninstall -g @playwright/cli --no-fund --no-audit >/dev/null 2>&1 || true

# Step 4: clear bash's command hash so command -v reflects on-disk state.
hash -r

if command -v playwright-cli >/dev/null 2>&1; then
  echo "playwright-cli uninstall: playwright-cli still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "playwright-cli: uninstall complete"
