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
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

echo "rtk: removing rtk"

# Capture whether rtk's hook was wired BEFORE we revert it. rtk's `init` installs
# ~/.claude/RTK.md, so its presence is the proof that rtk (not a hand-edit or some
# other tool) wired the Claude Code hook — and therefore that rtk is the owner of
# the generically-named settings.json.bak in the shared ~/.claude dir (step 4).
hook_was_present=0
[[ -e "${AGENTLINUX_AGENT_HOME}/.claude/RTK.md" ]] && hook_was_present=1

# 1. Revert rtk's wiring from EVERY agent it was wired into (WIRE-02) BEFORE
#    deleting the binary — rtk's own `--uninstall` needs the binary to run. This
#    mirrors al_rtk_wire's fan-out; each step is a no-op if that agent was never
#    wired. Non-interactive throughout (see lib/rtk-wire.sh).
if command -v rtk >/dev/null 2>&1; then
  # shellcheck source=../../lib/rtk-wire.sh
  source "${AGENTLINUX_CATALOG_DIR}/lib/rtk-wire.sh"
  al_rtk_unwire
fi

# 2. Delete the binary.
rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/rtk"

# 3. Delete rtk's own config + cache (the ENABLE-01 "deletes config/cache" clause;
#    the hook-revert step above leaves these behind — RESEARCH Pitfall 5).
rm -rf "${AGENTLINUX_AGENT_HOME}/.config/rtk" \
  "${AGENTLINUX_AGENT_HOME}/.local/share/rtk"

# 4. Remove rtk's own backup residue — but ONLY when rtk actually wired the hook.
#    settings.json.bak is a generically-named file in the SHARED ~/.claude dir that
#    another tool or a hand-edit could legitimately own; rtk only creates it when
#    `rtk init` patches settings.json (the same step that writes RTK.md). Gating on
#    hook_was_present means we never delete a .bak rtk did not create. Do NOT touch
#    ~/.claude/settings.json itself — it is user-owned; the hook revert leaves an
#    empty PreToolUse scaffold.
if [[ $hook_was_present -eq 1 ]]; then
  rm -f "${AGENTLINUX_AGENT_HOME}/.claude/settings.json.bak"
fi

# 5. Truth check: refresh the command hash table and assert rtk is gone.
hash -r
if command -v rtk >/dev/null 2>&1; then
  echo "rtk uninstall: still on PATH after removal" >&2
  exit 1
fi

echo "rtk: uninstall complete"
