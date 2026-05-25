#!/usr/bin/env bash
set -euo pipefail
# claude-code uninstall.sh — symmetric inverse of install.sh.
# Follows Anthropic's documented uninstall (code.claude.com/docs/en/setup#uninstall):
#   rm -f ~/.local/bin/claude
#   rm -rf ~/.local/share/claude
#
# CAT-04 BEHAVIOR SHIFT (Plan 14-03):
#   Previously this script unconditionally removed ~/.claude/downloads (the
#   bootstrap's scratch dir). With Plan 14-03's AGENTLINUX_PRESERVE_PATHS
#   mechanism, ~/.claude/ is on the preserve list (REMEDIATE-04 must not lose
#   credentials/session state), and the _should_remove helper's descendant
#   rule preserves ANY path under a preserved root — including
#   ~/.claude/downloads. This is intentional: avoid re-downloading bootstrap
#   content on REMEDIATE-04 reinstall. See 14-AUDIT.md "CAT-04 behavior shift".
#   Operators wanting a fresh scratch dir can `rm -rf ~/.claude/downloads`
#   manually.

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
#
# Plan 14-03 (REMEDIATE-04 CAT-04). Verified by bats Test 48.
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

# _rm helper — wraps `rm -rf` / `rm -f` with _should_remove gate. Emits a
# transcript line when a path is preserved so REMEDIATE-04 reinstall logs are
# auditable.
_rm() {
  local mode=$1 target=$2
  if _should_remove "$target"; then
    rm "$mode" -- "$target"
  else
    echo "claude-code uninstall: preserving ${target} (AGENTLINUX_PRESERVE_PATHS)"
  fi
}

echo "claude-code: removing native Claude Code install"

# rm -f / rm -rf are idempotent on missing targets. _rm wraps the _should_remove
# gate. Plan 14-03 (REMEDIATE-04 CAT-04): ~/.claude/downloads is now preserved
# by virtue of being a descendant of preserved ~/.claude/.
_rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/claude"
_rm -rf "${AGENTLINUX_AGENT_HOME}/.local/share/claude"
_rm -rf "${AGENTLINUX_AGENT_HOME}/.claude/downloads"

# Intentionally NOT removed (user data; matches Anthropic's uninstall-config
# warning): ~/.claude/, ~/.claude.json. Users wanting a full wipe run the
# documented steps manually; INST-04 --purge sweeps the entire agent home.

echo "claude-code: uninstall complete (user config at ~/.claude/ preserved)"
