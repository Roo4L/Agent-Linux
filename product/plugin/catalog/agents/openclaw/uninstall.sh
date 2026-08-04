#!/usr/bin/env bash
set -euo pipefail
# openclaw uninstall.sh — symmetric inverse of install.sh (Phase 47, ASST-01 / ENABLE-04).
#
# Tears down the per-user Gateway daemon and removes the AgentLinux-installed CLI, then
# reverts linger if (and only if) AgentLinux enabled it and no other daemon tool needs it.
# openclaw's per-user state dir (~/.openclaw — the Gateway token, the agent workspace/
# persona, conversation sessions, and any provider credential the user added in-tool) is
# routed through the CAT-04 preserve gate: catalog.json lists it in preserve_paths.json,
# so the CLI injects it into AGENTLINUX_PRESERVE_PATHS on every uninstall and this gate
# keeps it — matching every other authenticated agent (codex ~/.codex, gh ~/.config/gh,
# claude-code ~/.claude). A `remove` never destroys the user's assistant data or keys;
# only `agentlinux --purge` wipes the whole agent home. The DAEMON/service artifacts
# (systemd --user unit, /tmp/openclaw logs) are ephemeral and always torn down.
#
# Every destructive step is guarded / best-effort, so a second remove on a missing install
# exits 0 (idempotent). Truth check asserts on the concrete agent-owned binary rather than
# PATH-wide `command -v`, so an openclaw elsewhere on PATH cannot mask a correct removal.

: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/daemon-lifecycle.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/daemon-lifecycle.sh"

# _should_remove <abs-path> — 0 (proceed) unless <abs-path> is in/under any
# AGENTLINUX_PRESERVE_PATHS entry (colon-separated, HOME-relative; empty → no preserves).
# A preserved root protects everything beneath it. Mirrors gh/claude-code uninstall.sh.
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

echo "openclaw: removing openclaw"

# --- 1. tear down the per-user daemon (best-effort; skip cleanly when no user systemd) ---
if command -v openclaw >/dev/null 2>&1 && al_daemon_user_systemd_available; then
  openclaw daemon stop >/dev/null 2>&1 || true
  openclaw daemon uninstall >/dev/null 2>&1 || true
fi
# Ephemeral file logs the daemon wrote outside the state dir — never user data.
rm -rf /tmp/openclaw 2>/dev/null || true

# --- 2. remove the AgentLinux-installed CLI (agent-owned npm prefix; re-created on
# reinstall — always removed) ---
npm rm -g openclaw >/dev/null 2>&1 || true

# --- 3. per-user state (~/.openclaw): preserved on remove per CAT-04 (it is in
# AGENTLINUX_PRESERVE_PATHS). The gate keeps the mechanism explicit — if a future catalog
# drops the preserve entry, this same code deletes it. --purge wipes the agent home. ---
if _should_remove "${AGENTLINUX_AGENT_HOME}/.openclaw"; then
  rm -rf "${AGENTLINUX_AGENT_HOME}/.openclaw"
else
  echo "openclaw uninstall: preserving ${AGENTLINUX_AGENT_HOME}/.openclaw (AGENTLINUX_PRESERVE_PATHS)"
fi

# --- 4. drop the daemon marker + revert linger only if AgentLinux enabled it and no
# other daemon tool remains ---
al_daemon_unmark openclaw
al_daemon_revert_linger_if_unused

# --- 5. truth check: the agent-owned CLI is gone ---
hash -r
if [[ -e "${AGENTLINUX_AGENT_HOME}/.npm-global/bin/openclaw" ]]; then
  echo "openclaw uninstall: ${AGENTLINUX_AGENT_HOME}/.npm-global/bin/openclaw still present after removal" >&2
  exit 1
fi

echo "openclaw: uninstall complete"
