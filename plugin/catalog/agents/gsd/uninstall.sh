#!/usr/bin/env bash
set -euo pipefail
# Symmetric Open GSD teardown; only GSD-owned surfaces are swept.
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
bin='gsd-core'

if command -v "$bin" >/dev/null 2>&1; then
  "$bin" --global --claude --opencode --codex --qwen --uninstall \
    || echo "gsd uninstall: upstream cleanup returned non-zero; continuing defensive sweep" >&2
fi

home=${AGENTLINUX_AGENT_HOME}
sweep() {
  local root=$1 kind=$2 name=$3 match
  [[ -d "$root" ]] || return 0
  while IFS= read -r -d '' match; do
    if [[ "$(basename "$match")" == 'gsd-dev-preferences' ]]; then
      echo "gsd uninstall: preserving ${match} (Open GSD user-owned preferences)"
      continue
    fi
    rm -rf -- "$match"
  done < <(find "$root" -maxdepth 2 -type "$kind" -name "$name" -print0 2>/dev/null)
}
sweep "${home}/.claude/skills" d 'gsd-*'
sweep "${home}/.claude" d 'gsd-core'
sweep "${home}/.config/opencode" f 'gsd-*.md'
sweep "${home}/.config/opencode/skills" d 'gsd-*'
sweep "${home}/.config/opencode" d 'get-shit-done'
sweep "${home}/.config/opencode" d 'gsd-core'
sweep "${home}/.agents/skills" d 'gsd-*'
sweep "${home}/.agents" d 'gsd-core'
sweep "${home}/.codex/skills" d 'gsd-*'
sweep "${home}/.codex" d 'gsd-core'
sweep "${home}/.qwen/skills" d 'gsd-*'
sweep "${home}/.qwen" d 'gsd-core'
# ~/.gemini is shared user-owned Antigravity state. Do not sweep it here: any
# legacy GSD command artifacts there are left for explicit user cleanup.

npm uninstall -g '@opengsd/gsd-core' get-shit-done-cc --no-fund --no-audit >/dev/null 2>&1 || true
hash -r
if command -v "$bin" >/dev/null 2>&1; then
  echo "gsd uninstall: ${bin} still on PATH after npm uninstall -g" >&2
  exit 1
fi
echo "gsd: uninstall complete"
