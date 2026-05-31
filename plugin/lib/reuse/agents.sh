#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse/agents.sh — REUSE-03 catalog-agent compatibility decision.
#
# Three predicates, ALL required for REUSE:
#   1. detect::agent_status <id> == "healthy"
#   2. detected binary path == catalog canonical path (map below)
#   3. detected version satisfies the catalog compatibility_window (semver)
#
# Predicate 3 is NOT done here — semver-range satisfaction is non-trivial in
# bash. The CLI (plugin/cli/src/commands/install.ts) runs semver.satisfies()
# and treats a path-matched, healthy, out-of-window agent as `remediate`. This
# bash function returns {reuse, remediate, create} on predicates 1 + 2 only.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags; uses `return 1` on error.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Canonical binary path map — MUST stay byte-identical to the CANONICAL_PATHS
# object in plugin/cli/src/commands/install.ts (drift flips reuse→remediate).
# `-g` forces global scope so the array stays visible when this library is
# sourced from inside a function (as bats @tests do).
declare -gA REUSE_AGENT_CANONICAL_PATHS=(
  [claude-code]="/home/agent/.local/bin/claude"
  [gsd]="/home/agent/.npm-global/bin/get-shit-done-cc"
  [playwright-cli]="/home/agent/.npm-global/bin/playwright-cli"
)

# reuse::agent_decision <id>
# Returns {reuse, remediate, create} per predicates 1 + 2 (predicate 3 layered
# on by the CLI).
reuse::agent_decision() {
  local id=${1:-}
  if [[ -z "$id" ]]; then
    printf 'create'
    return 0
  fi

  # Predicate 1: status.
  local status
  status=$(detect::agent_status "$id")

  if [[ "$status" == "absent" ]]; then
    printf 'create'
    return 0
  fi

  # Predicate 2: canonical path lookup. Unknown id falls through to install
  # rather than incorrectly REUSE (future catalog ids aren't in the map).
  local canonical=${REUSE_AGENT_CANONICAL_PATHS[$id]:-}
  if [[ -z "$canonical" ]]; then
    printf 'create'
    return 0
  fi

  if [[ "$status" == "broken" ]]; then
    printf 'remediate'
    return 0
  fi

  # healthy — compare binary path. ${id^^//-/_} → CLAUDE_CODE etc.
  local upper=${id^^}
  upper=${upper//-/_}
  local path_var="DETECT_AGENT_${upper}_PATH"
  local detected_path=${!path_var:-}

  if [[ "$detected_path" != "$canonical" ]]; then
    # Healthy but wrong path → reinstall at the canonical path.
    printf 'remediate'
    return 0
  fi

  # Healthy + path-match. The CLI re-checks version-in-window before acting.
  printf 'reuse'
  return 0
}
