#!/usr/bin/env bash
set -euo pipefail
# gsd uninstall.sh — symmetric inverse. npm uninstall -g is idempotent.
# CAT-04: AGENTLINUX_PRESERVE_PATHS preserves user workflow state
# (.gsd, .config/get-shit-done) across REMEDIATE-04 reinstall.

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

# _rm_path — wraps rm with the _should_remove gate.
_rm_path() {
  local mode=$1 target=$2
  if _should_remove "$target"; then
    rm "$mode" -- "$target"
  else
    echo "gsd uninstall: preserving ${target} (AGENTLINUX_PRESERVE_PATHS)"
  fi
}

echo "gsd: removing get-shit-done-cc"

# Step 1: ask the bootstrapper to undo what install.sh wired into every agent.
# Mirrors the install path's `--global --claude --opencode --gemini --codex
# --qwen` invocation (WIRE-01). Failure is non-fatal — the bootstrapper may be
# a future version that drops a flag, or the user may have already removed bits
# manually; the defensive cleanup below catches whatever remains.
if command -v get-shit-done-cc >/dev/null 2>&1; then
  get-shit-done-cc --global --claude --opencode --gemini --codex --qwen --uninstall \
    || echo "gsd uninstall: bootstrapper --uninstall returned non-zero (continuing)" >&2
fi

# Step 2: defensive cleanup of GSD-installed state across ALL shipped agents
# (WIRE-01). The bootstrapper's `--uninstall` is best-effort, so sweep the GSD
# surfaces ourselves: each agent's gsd-* command/skill entries plus the
# per-tool `get-shit-done/` payload dir. Looping (not find -exec) so every match
# runs through _should_remove; none of these live under a preserved root, so the
# gate lets rm proceed. Anchored on `gsd-*`/`get-shit-done` so unrelated
# user-authored commands/skills are never collateral damage. Each sweep root is
# a (dir, find-args) pair.
_sweep() {
  local root=$1
  shift
  [[ -d $root ]] || return 0
  local match
  while IFS= read -r -d '' match; do
    if _should_remove "$match"; then
      rm -rf -- "$match" 2>/dev/null || true
    else
      echo "gsd uninstall: preserving ${match} (AGENTLINUX_PRESERVE_PATHS)"
    fi
  done < <(find "$root" "$@" -print0 2>/dev/null)
}

H="${AGENTLINUX_AGENT_HOME}"
_sweep "${H}/.claude/skills" -maxdepth 1 -type d -name 'gsd-*'
_sweep "${H}/.config/opencode/command" -maxdepth 1 -type f -name 'gsd-*.md'
_sweep "${H}/.config/opencode" -maxdepth 1 -type d -name 'get-shit-done'
# -maxdepth 2 mirrors the install-side assertion (gsd/install.sh) so a deeper
# namespacing by a future GSD pin is torn down symmetrically, not orphaned.
_sweep "${H}/.gemini/commands" -maxdepth 2 -type d -name 'gsd'
_sweep "${H}/.gemini" -maxdepth 1 -type d -name 'get-shit-done'
_sweep "${H}/.codex/skills" -maxdepth 1 -type d -name 'gsd-*'
_sweep "${H}/.codex" -maxdepth 1 -type d -name 'get-shit-done'
_sweep "${H}/.qwen/skills" -maxdepth 1 -type d -name 'gsd-*'
_sweep "${H}/.qwen" -maxdepth 1 -type d -name 'get-shit-done'

# Step 3: npm uninstall -g on a missing package exits 0 with "up to date"
# — idempotent. Real truth check is `command -v` below.
npm uninstall -g get-shit-done-cc --no-fund --no-audit >/dev/null 2>&1 || true

# Verify removal. `hash -r` clears bash's command-name cache — without it,
# the prior `get-shit-done-cc --uninstall` invocation hashed the binary's
# path and `command -v` reports it as still-resolvable even after npm
# uninstall -g has deleted the file from disk.
hash -r
if command -v get-shit-done-cc >/dev/null 2>&1; then
  echo "gsd uninstall: get-shit-done-cc still on PATH after npm uninstall -g" >&2
  exit 1
fi

echo "gsd: uninstall complete"
