#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse/agents.sh — REUSE-03 catalog-agent compatibility decision.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/reuse.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Implements CONTEXT.md Area 1 / Q3: three predicates — ALL must hold for
# REUSE.
#   1. detect::agent_status <id> == "healthy"
#   2. detected binary path == catalog canonical path (hardcoded map below)
#   3. detected version satisfies catalog compatibility_window (semver range)
#
# TWO-LAYER CHECK: predicate (3) is intentionally NOT performed here in bash
# because semver-range-satisfaction is non-trivial in bash; the CLI install.ts
# (plugin/cli/src/commands/install.ts) already depends on the `semver` npm
# package and runs the semver.satisfies(detected_version, compatibility_window)
# check in TypeScript before treating any `reuse` decision as actionable. This
# bash function returns one of {reuse, remediate, create} based on predicates
# 1 + 2 only; the CLI layers predicate 3 on top.
#
# If predicate (3) fails on the CLI side, the CLI treats the decision as
# `remediate` (path-match + healthy but version-out-of-window — Phase 14
# REMEDIATE-04 reinstalls at catalog pin).
#
# Returns:
#   - "create"    — status=absent OR unknown catalog id (defensive)
#   - "remediate" — status=broken OR (healthy + path-mismatch)
#   - "reuse"     — status=healthy + path-match (CLI re-checks version-in-window
#                   before acting on the token)
#
# Canonical path map (LOCKED — verbatim from plugin/catalog/agents/*/install.sh):
#   claude-code:    ~agent/.local/bin/claude          (native installer; NOT npm-global)
#   gsd:            ~agent/.npm-global/bin/get-shit-done-cc
#   playwright-cli: ~agent/.npm-global/bin/playwright-cli
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Canonical binary path map — MUST stay byte-identical to the TypeScript
# CANONICAL_PATHS object in plugin/cli/src/commands/install.ts. Drift surfaces
# immediately in the brownfield E2E smoke @test (REUSE-03 path-match check
# fails → emits `remediate` instead of `reuse`).
declare -A REUSE_AGENT_CANONICAL_PATHS=(
  [claude-code]="/home/agent/.local/bin/claude"
  [gsd]="/home/agent/.npm-global/bin/get-shit-done-cc"
  [playwright-cli]="/home/agent/.npm-global/bin/playwright-cli"
)

# reuse::agent_decision <id>
#
# Returns one of {reuse, remediate, create} on stdout per the three-predicate
# check (predicates 1 + 2 only — predicate 3 (version-in-window) layered on
# top by the CLI).
reuse::agent_decision() {
  local id=${1:-}
  if [[ -z "$id" ]]; then
    printf 'create'
    return 0
  fi

  # Predicate 1: status from Phase 12 readers.
  local status
  status=$(detect::agent_status "$id")

  if [[ "$status" == "absent" ]]; then
    printf 'create'
    return 0
  fi

  # Predicate 2: canonical path lookup. Unknown catalog id is defensive —
  # future catalog ids won't be in the hardcoded map; safer to fall through
  # to install than to incorrectly REUSE.
  local canonical=${REUSE_AGENT_CANONICAL_PATHS[$id]:-}
  if [[ -z "$canonical" ]]; then
    printf 'create'
    return 0
  fi

  if [[ "$status" == "broken" ]]; then
    # Broken catalog agent always → Phase 14 REMEDIATE-04 (uninstall + reinstall).
    printf 'remediate'
    return 0
  fi

  # status == "healthy" — check binary path. Use the DETECT_AGENT_<UPPER>_PATH
  # export populated by detect::agents_probe. ${id^^//-/_} uppercases AND
  # replaces hyphens with underscores so `claude-code` → `CLAUDE_CODE`.
  local upper=${id^^}
  upper=${upper//-/_}
  local path_var="DETECT_AGENT_${upper}_PATH"
  local detected_path=${!path_var:-}

  if [[ "$detected_path" != "$canonical" ]]; then
    # Healthy but at wrong path — Phase 14 REMEDIATE-04 reinstalls at canonical
    # path per CONTEXT Area 1 Q3 fall-through.
    printf 'remediate'
    return 0
  fi

  # Healthy + path-match. CLI install.ts re-checks the version-in-window
  # predicate before acting on this token; if it fails, the CLI treats the
  # decision as `remediate` instead.
  printf 'reuse'
  return 0
}

# reuse::log_agent_reuse <id>
#
# Emits the canonical [REUSE-03] marker line via log_info (tee'd to
# /var/log/agentlinux-install.log). Format mirrors Phase 12's [DET-NN]
# key=value convention; bats greps `[REUSE-03]` reliably.
#
# Phase 13 note: the actual marker line emission for REUSE-03 happens in the
# CLI (install.ts), since REUSE-03 is dispatched via `agentlinux install
# <name>` rather than via a provisioner. This helper exists for symmetry +
# Phase 14 reuse if any bash-side caller needs to surface a [REUSE-03] line.
reuse::log_agent_reuse() {
  local id=${1:-}
  local upper=${id^^}
  upper=${upper//-/_}
  local path_var="DETECT_AGENT_${upper}_PATH"
  local version_var="DETECT_AGENT_${upper}_VERSION"
  log_info "[REUSE-03] ${id} reused: binary=${!path_var:-} version=${!version_var:-} status=healthy"
}
