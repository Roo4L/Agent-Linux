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
# bash. The CLI (plugin/cli/src/detect.ts, shared by install + adopt) runs semver.satisfies()
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
# object in plugin/cli/src/detect.ts (drift flips reuse→remediate).
# `-g` forces global scope so the array stays visible when this library is
# sourced from inside a function (as bats @tests do).
#
# Consumed EXTERNALLY: remediate.sh:288 iterates `${!REUSE_AGENT_CANONICAL_PATHS[@]}`
# to enumerate per-agent decisions. Since the v0.4.0 Rust-rewrite spike (Phase 53)
# moved the decision body into the Rust bin, the map is no longer read inside this
# file — but it MUST stay for that external iterator (consolidating the
# duplication is Phase 57). shellcheck can't see the cross-file use.
# shellcheck disable=SC2034
declare -gA REUSE_AGENT_CANONICAL_PATHS=(
  [claude-code]="/home/agent/.local/bin/claude"
  [gsd]="/home/agent/.npm-global/bin/gsd-core"
  [playwright-cli]="/home/agent/.npm-global/bin/playwright-cli"
)

# GSD second canonical presence — the deployed-system VERSION file. Open GSD's
# runtime payload may remain even when its package-native binary is absent, so a
# healthy gsd detected at this path is ALSO reuse-eligible. MUST stay byte-identical to
# GSD_SYSTEM_PATH in plugin/cli/src/detect.ts.
#
# The Rust bin now owns the gsd-system-path special case (main.rs GSD_SYSTEM_PATH);
# this constant is retained for parity/documentation alongside the map above and
# is no longer read inside this file post-spike (Phase 57 removes the duplication).
# shellcheck disable=SC2034
readonly REUSE_GSD_SYSTEM_PATH="/home/agent/.claude/gsd-core/VERSION"

# reuse::agent_decision <id>
# Returns {reuse, remediate, create} per predicates 1 + 2 (predicate 3 layered
# on by the CLI).
#
# v0.4.0 Rust-rewrite spike (Phase 53, RUST-03 / GATE-01): the decision body is
# now computed by the `agentlinux` Rust binary (agentlinux-core::reuse) — the
# same env-var-in / stdout-token-out contract, so every 13-reuse.bats @test and
# the remediate.sh:288 call site work verbatim with ZERO bats edits. The
# `DETECT_AGENT_<UPPER>_STATUS/_PATH` exports the caller/bats set are read by the
# bin; this function only forwards the id. The binary is resolved via
# `${AGENTLINUX_RUST_BIN:-agentlinux}` (absolute-path env override for tests +
# pinned deploys; bare `agentlinux` PATH fallback otherwise).
#
# NB: REUSE_AGENT_CANONICAL_PATHS + REUSE_GSD_SYSTEM_PATH below are DELIBERATELY
# retained — remediate.sh:288 iterates the map's keys to enumerate per-agent
# decisions. Consolidating the duplication (map now lives in the Rust bin too)
# is Phase 57, not this spike.
reuse::agent_decision() {
  local id=${1:-}
  local bin=${AGENTLINUX_RUST_BIN:-agentlinux}
  "$bin" reuse-decision "$id"
}
