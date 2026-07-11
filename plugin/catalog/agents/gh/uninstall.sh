#!/usr/bin/env bash
set -euo pipefail
# gh uninstall.sh — symmetric inverse of install.sh (Phase 29, DEVT-01).
#
# Removes the binary AgentLinux installed. gh's own per-user config dir
# (~/.config/gh, where `gh auth login` stores its host/token state) is routed
# through the CAT-04 preserve gate: catalog.json lists it in preserve_paths.json,
# so the CLI injects it into AGENTLINUX_PRESERVE_PATHS on every uninstall and the
# gate keeps it. This matches every other authenticated agent (codex ~/.codex,
# gemini ~/.gemini, claude-code ~/.claude) — a `remove` never destroys the user's
# credentials, and only `agentlinux --purge` wipes the whole agent home. Every
# destructive step is guarded / idempotent, so a second remove on a missing
# install exits 0. The truth check asserts on the concrete agent-owned binary path
# rather than PATH-wide `command -v`, so a distro-provided gh elsewhere on PATH
# cannot make a correct removal look like a failure.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# _should_remove <abs-path> — returns 0 (proceed) unless <abs-path> is in or under
# any AGENTLINUX_PRESERVE_PATHS entry (colon-separated, HOME-relative; empty means
# "no preserves"). A preserved root protects everything beneath it. Mirrors
# claude-code/uninstall.sh.
_should_remove() {
  local target=$1
  [[ -z "${AGENTLINUX_PRESERVE_PATHS:-}" ]] && return 0
  local t_strip="${target%/}"
  local IFS=:
  local preserved
  for preserved in $AGENTLINUX_PRESERVE_PATHS; do
    local p_strip="${preserved%/}"
    if [[ "$t_strip" == "${AGENTLINUX_AGENT_HOME}/${p_strip}" ||
      "$t_strip" == "${AGENTLINUX_AGENT_HOME}/${p_strip}/"* ]]; then
      return 1
    fi
  done
  return 0
}

echo "gh: removing gh"

# The binary is AgentLinux-owned and re-created on reinstall — always removed.
rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/gh"

# The config dir (auth token) is preserved on remove per CAT-04 (it is in
# AGENTLINUX_PRESERVE_PATHS). The gate keeps the mechanism explicit and future-proof
# — if a future catalog ever drops the preserve entry, this same code deletes it.
if _should_remove "${AGENTLINUX_AGENT_HOME}/.config/gh"; then
  rm -rf "${AGENTLINUX_AGENT_HOME}/.config/gh"
else
  echo "gh uninstall: preserving ${AGENTLINUX_AGENT_HOME}/.config/gh (AGENTLINUX_PRESERVE_PATHS)"
fi

hash -r
if [[ -e "${AGENTLINUX_AGENT_HOME}/.local/bin/gh" ]]; then
  echo "gh uninstall: ${AGENTLINUX_AGENT_HOME}/.local/bin/gh still present after removal" >&2
  exit 1
fi

echo "gh: uninstall complete"
