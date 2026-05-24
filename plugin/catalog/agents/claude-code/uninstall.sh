#!/usr/bin/env bash
set -euo pipefail
# claude-code uninstall.sh — symmetric inverse of install.sh.
# Follows Anthropic's documented uninstall (code.claude.com/docs/en/setup#uninstall):
#   rm -f ~/.local/bin/claude
#   rm -rf ~/.local/share/claude
# PLUS we remove ~/.claude/downloads (bootstrap's scratch dir) but NOT ~/.claude/
# itself (contains user state, settings, session history — CAT-04 uninstall
# contract says "binary + first-install artifacts", not user data).

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "claude-code: removing native Claude Code install"

# rm -f / rm -rf are idempotent on missing targets.
rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/claude"
rm -rf "${AGENTLINUX_AGENT_HOME}/.local/share/claude"
rm -rf "${AGENTLINUX_AGENT_HOME}/.claude/downloads"

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
