#!/usr/bin/env bash
set -euo pipefail
# rtk uninstall.sh — symmetric inverse of install.sh (Phase 28, WORK-02 / ENABLE-01).
#
# ORDER IS LOAD-BEARING (RESEARCH Pitfall 4): if the user opted into the rtk
# Claude Code hook (`rtk init -g`), that hook lives in ~/.claude/settings.json and
# points at the rtk binary. Deleting the binary FIRST would orphan the hook —
# every Bash tool call in Claude Code would then fail. So we revert the hook with
# rtk's own built-in `--uninstall` (which needs the binary to run) BEFORE removing
# it. `rtk init --uninstall` reverts the ~/.claude artifacts but does NOT remove
# rtk's own config/cache or its settings.json.bak — this script owns those.
#
# Every destructive step is guarded / `|| true`, so a second remove on a missing
# install exits 0 (idempotent — ENABLE-01).

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "rtk: removing rtk"

# 1. Revert the opt-in Claude Code hook BEFORE deleting the binary. No-op if the
#    user never ran `rtk init` (the binary simply reverts an absent hook).
if command -v rtk >/dev/null 2>&1; then
  rtk init --uninstall -g --auto-patch >/dev/null 2>&1 || true
fi

# 2. Delete the binary.
rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/rtk"

# 3. Delete rtk's own config + cache (the ENABLE-01 "deletes config/cache" clause;
#    the hook-revert step above leaves these behind — RESEARCH Pitfall 5).
rm -rf "${AGENTLINUX_AGENT_HOME}/.config/rtk" \
  "${AGENTLINUX_AGENT_HOME}/.local/share/rtk"

# 4. Remove rtk's own backup residue. Do NOT touch ~/.claude/settings.json itself —
#    it is user-owned; the hook revert leaves an empty PreToolUse scaffold.
rm -f "${AGENTLINUX_AGENT_HOME}/.claude/settings.json.bak"

# 5. Truth check: refresh the command hash table and assert rtk is gone.
hash -r
if command -v rtk >/dev/null 2>&1; then
  echo "rtk uninstall: still on PATH after removal" >&2
  exit 1
fi

echo "rtk: uninstall complete"
