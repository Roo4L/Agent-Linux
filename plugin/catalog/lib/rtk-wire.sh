#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/catalog/lib/rtk-wire.sh — WIRE-02 shared cross-agent rtk wiring helper.
#
# SOURCED, NOT EXECUTED. rtk's install.sh / uninstall.sh / rewire.sh source it via
#   source "${AGENTLINUX_CATALOG_DIR}/lib/rtk-wire.sh"
# then call al_rtk_wire (install/rewire) or al_rtk_unwire (uninstall). The
# provisioner stages this whole lib/ subdir to /opt/agentlinux/catalog/<ver>/lib/.
#
# Purpose (WIRE-02, #4 dogfood): rtk (Rust Token Killer) is a cross-agent PROXY —
# every coding agent that shells out benefits from rtk's `init` hook written into
# that agent's own config. So wiring fans OUT to each supported agent that is
# PRESENT, and `remove` tears it down. Because the CLI re-runs al_rtk_wire after
# any LATER agent install (rtk's rewire.sh reverse-trigger, dispatched by
# plugin/cli/src/rewire.ts), the end state is install-order-independent.
#
# Supported targets — commands + landing artifacts verified against rtk 0.42.4
# (`rtk init --help` + real inits):
#   claude-code  rtk init -g --auto-patch            -> ~/.claude/RTK.md (+ settings.json hook)
#   codex        rtk init -g --codex                 -> ~/.codex/RTK.md (+ AGENTS.md)
#                (--codex is REJECTED with --auto-patch; the codex path writes
#                 AGENTS.md+RTK.md and never patches settings.json, so it is
#                 already non-interactive — we still close stdin defensively)
#   gemini-cli   rtk init -g --gemini --auto-patch   -> ~/.gemini/GEMINI.md (rtk block)
#   opencode     rtk init -g --opencode --auto-patch -> ~/.config/opencode/plugins/rtk.ts
#   qwen-code    N/A — rtk has no qwen target (absent from `--agent`). Documented,
#                never silently pretended-wired.
#
# Best-effort by design: one agent's wiring failing must NOT roll back a
# freshly-downloaded rtk binary, nor fail an unrelated agent's install in the
# reverse-trigger. Each target logs its own outcome; the functions return 0
# overall (inspect AL_RTK_TARGETS for what landed). Deliberately NOT
# `set -euo pipefail` — sourced into recipes that own their own shell options.

_al_rtk_home() { printf '%s' "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"; }

# rtk itself + each agent launcher, resolved on PATH.
_al_rtk_present() { command -v rtk >/dev/null 2>&1; }
_al_rtk_claude_present() { command -v claude >/dev/null 2>&1; }
_al_rtk_codex_present() { command -v codex >/dev/null 2>&1; }
_al_rtk_gemini_present() { command -v gemini >/dev/null 2>&1; }
_al_rtk_opencode_present() { command -v opencode >/dev/null 2>&1; }
_al_rtk_gemini_artifact_present() {
  grep -qF -- '# RTK - Rust Token Killer' \
    "${1}/.gemini/GEMINI.md" 2>/dev/null
}
_al_rtk_gemini_hook_present() {
  [[ -f "${1}/.gemini/hooks/rtk-hook-gemini.sh" ]] \
    || [[ -f "${1}/.gemini/hooks/.rtk-hook.sha256" ]]
}

# RTK's Gemini uninstall removes GEMINI.md wholesale. When Gemini itself has
# already been removed, clean only RTK's uniquely named hook and settings entry
# so a user-edited GEMINI.md remains intact.
_al_rtk_unwire_stale_gemini_hook() {
  local home=$1
  rm -f -- "${home}/.gemini/hooks/rtk-hook-gemini.sh" \
    "${home}/.gemini/hooks/.rtk-hook.sha256"

  local settings="${home}/.gemini/settings.json"
  [[ -f $settings ]] || return 0
  AGENTLINUX_GEMINI_SETTINGS=$settings node <<'NODE' >/dev/null 2>&1 || true
const fs = require("fs");
const file = process.env.AGENTLINUX_GEMINI_SETTINGS;
let settings;
try {
  settings = JSON.parse(fs.readFileSync(file, "utf8"));
} catch {
  process.exit(0);
}
const before = settings?.hooks?.BeforeTool;
if (!Array.isArray(before)) process.exit(0);
const kept = before.filter((entry) => {
  const command = entry?.hooks?.[0]?.command;
  return typeof command !== "string" || !command.includes("rtk-hook-gemini");
});
if (kept.length === before.length) process.exit(0);
if (kept.length === 0) delete settings.hooks.BeforeTool;
const mode = fs.statSync(file).mode & 0o777;
const tmp = `${file}.agentlinux.tmp`;
fs.writeFileSync(tmp, `${JSON.stringify(settings, null, 2)}\n`, { mode });
fs.chmodSync(tmp, mode);
fs.renameSync(tmp, file);
NODE
}

# al_rtk_wire — fan `rtk init` out to every supported agent present now. Sets
# AL_RTK_TARGETS to the space-separated wired-agent list. Always returns 0
# (best-effort). Idempotent: rtk's init is a rewrite, so re-running is a no-op
# beyond touching mtimes.
al_rtk_wire() {
  AL_RTK_TARGETS=""
  local home
  home=$(_al_rtk_home)

  if ! _al_rtk_present; then
    echo "rtk-wire: rtk not on PATH — nothing to wire" >&2
    return 0
  fi

  if _al_rtk_claude_present; then
    # rtk's claude wire writes into ~/.claude but does NOT mkdir it; claude-code's
    # own install.sh creates ~/.claude, so it exists whenever `claude` is on PATH.
    # If a future refactor drops that mkdir, the landing check below reports
    # "did not land (skipped)" rather than failing the install (best-effort).
    if rtk init -g --auto-patch >/dev/null 2>&1 && [[ -f "${home}/.claude/RTK.md" ]]; then
      AL_RTK_TARGETS+="claude-code "
      echo "rtk: wired into claude-code (~/.claude/RTK.md + settings.json hook)"
    else
      echo "rtk-wire: claude-code wiring did not land (skipped)" >&2
    fi
  fi

  if _al_rtk_codex_present; then
    if rtk init -g --codex </dev/null >/dev/null 2>&1 && [[ -f "${home}/.codex/RTK.md" ]]; then
      AL_RTK_TARGETS+="codex "
      echo "rtk: wired into codex (~/.codex/RTK.md + AGENTS.md)"
    else
      echo "rtk-wire: codex wiring did not land (skipped)" >&2
    fi
  fi

  if _al_rtk_gemini_present; then
    if rtk init -g --gemini --auto-patch >/dev/null 2>&1 \
      && _al_rtk_gemini_artifact_present "$home"; then
      AL_RTK_TARGETS+="gemini-cli "
      echo "rtk: wired into gemini-cli (~/.gemini/GEMINI.md)"
    else
      echo "rtk-wire: gemini-cli wiring did not land (skipped)" >&2
    fi
  fi

  if _al_rtk_opencode_present; then
    if rtk init -g --opencode --auto-patch >/dev/null 2>&1 \
      && [[ -f "${home}/.config/opencode/plugins/rtk.ts" ]]; then
      AL_RTK_TARGETS+="opencode "
      echo "rtk: wired into opencode (~/.config/opencode/plugins/rtk.ts)"
    else
      echo "rtk-wire: opencode wiring did not land (skipped)" >&2
    fi
  fi

  # qwen-code: rtk ships no qwen integration — surface it, never fake it.
  if command -v qwen >/dev/null 2>&1; then
    echo "rtk: qwen-code present but rtk has no qwen target — skipped (N/A)"
  fi

  AL_RTK_TARGETS="${AL_RTK_TARGETS% }"
  if [[ -n "$AL_RTK_TARGETS" ]]; then
    echo "rtk: wired into: ${AL_RTK_TARGETS}"
  else
    echo "rtk: no supported coding agent present yet — rtk wires in automatically when you install one"
  fi
  return 0
}

# al_rtk_unwire — revert rtk's wiring from every supported agent present (or
# from an agent whose RTK-owned artifact remains after that agent was removed).
# Uses rtk's own `--uninstall` (which needs the rtk binary), so callers run it
# BEFORE deleting the rtk binary. Best-effort; always returns 0. The artifact
# checks close an order-dependent gap: a provider removed after its consumer
# must still clean the consumer's preserved config.
al_rtk_unwire() {
  _al_rtk_present || return 0
  local home
  home=$(_al_rtk_home)
  if _al_rtk_claude_present || [[ -f "${home}/.claude/RTK.md" ]]; then
    rtk init -g --uninstall --auto-patch >/dev/null 2>&1 || true
  fi
  if _al_rtk_codex_present || [[ -f "${home}/.codex/RTK.md" ]]; then
    rtk init -g --codex --uninstall </dev/null >/dev/null 2>&1 || true
  fi
  if _al_rtk_gemini_present; then
    rtk init -g --gemini --uninstall --auto-patch >/dev/null 2>&1 || true
  elif _al_rtk_gemini_hook_present "$home"; then
    _al_rtk_unwire_stale_gemini_hook "$home"
  fi
  if _al_rtk_opencode_present || [[ -f "${home}/.config/opencode/plugins/rtk.ts" ]]; then
    rtk init -g --opencode --uninstall --auto-patch >/dev/null 2>&1 || true
  fi
  return 0
}
