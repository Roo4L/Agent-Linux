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

# Plan 14-03 (REMEDIATE-04 PATH-MISMATCH): also tear down the npm-installed
# variant at ~/.npm-global/bin/claude. The native installer is canonical (per
# CANONICAL_PATHS in plugin/cli/src/commands/install.ts) but operators on
# brownfield hosts may have installed via `npm install -g @anthropic-ai/
# claude-code` (PATH-MISMATCH at ~/.npm-global/bin/claude). REMEDIATE-04
# expects this uninstall.sh to teardown BOTH variants so the post-uninstall
# T-14-05 verification passes (canonical AND detected_path absent).
#
# `npm uninstall -g` is idempotent (silent no-op when package not installed)
# and uses the agent-owned ~/.npm-global prefix (NPM_CONFIG_PREFIX inherited
# from runner.ts dispatchRecipe env). The package name matches the upstream
# Anthropic package; if the package isn't installed via npm, this is a no-op.
if command -v npm >/dev/null 2>&1; then
  npm uninstall -g @anthropic-ai/claude-code --no-fund --no-audit >/dev/null 2>&1 || true
fi
# Clear bash command-name cache so subsequent `command -v claude` reflects
# on-disk state, not the path bash hashed before this uninstall.
hash -r 2>/dev/null || true

# CLI-04 symmetric removal of the DISABLE_AUTOUPDATER stamp: strip our
# key only, drop the file iff nothing of the user's remains. Malformed
# JSON is left alone (idempotent + non-fatal).
settings_file="${AGENTLINUX_AGENT_HOME}/.claude/settings.json"
if [[ -f "${settings_file}" ]]; then
  tmp="${settings_file}.tmp.$$"
  if jq 'if (.env | type) == "object" then .env = (.env | del(.DISABLE_AUTOUPDATER)) else . end | if (.env == {}) then del(.env) else . end' "${settings_file}" > "${tmp}" 2>/dev/null; then
    if jq -e 'length == 0' "${tmp}" >/dev/null 2>&1; then
      rm -f "${settings_file}" "${tmp}"
    else
      mv "${tmp}" "${settings_file}"
    fi
  else
    rm -f "${tmp}"
  fi
fi

# Intentionally NOT removed (user data; matches Anthropic's uninstall-config
# warning): ~/.claude/, ~/.claude.json. Users wanting a full wipe run the
# documented steps manually; INST-04 --purge sweeps the entire agent home.

echo "claude-code: uninstall complete (user config at ~/.claude/ preserved)"
