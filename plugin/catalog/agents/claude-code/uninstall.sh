#!/usr/bin/env bash
set -euo pipefail
# claude-code uninstall.sh — symmetric inverse of install.sh.
# Follows Anthropic's documented uninstall (code.claude.com/docs/en/setup#uninstall):
#   rm -f ~/.local/bin/claude; rm -rf ~/.local/share/claude
#
# CAT-04 note: ~/.claude/ is on the preserve list, so ~/.claude/downloads (a
# descendant) now survives uninstall too — intentional, to avoid re-downloading
# bootstrap content on REMEDIATE-04 reinstall. Operators wanting a fresh scratch
# dir can `rm -rf ~/.claude/downloads` manually.

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

# _rm — wraps rm with the _should_remove gate; logs preserved paths for an
# auditable transcript.
_rm() {
  local mode=$1 target=$2
  if _should_remove "$target"; then
    rm "$mode" -- "$target"
  else
    echo "claude-code uninstall: preserving ${target} (AGENTLINUX_PRESERVE_PATHS)"
  fi
}

echo "claude-code: removing native Claude Code install"

# rm is idempotent on missing targets. ~/.claude/downloads is preserved as a
# descendant of ~/.claude/.
_rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/claude"
_rm -rf "${AGENTLINUX_AGENT_HOME}/.local/share/claude"
_rm -rf "${AGENTLINUX_AGENT_HOME}/.claude/downloads"

# PATH-MISMATCH: also tear down the npm-installed variant at
# ~/.npm-global/bin/claude. The native installer is canonical, but brownfield
# hosts may have `npm install -g`'d it. REMEDIATE-04 needs both variants gone so
# the post-uninstall verification passes. `npm uninstall -g` is idempotent.
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
