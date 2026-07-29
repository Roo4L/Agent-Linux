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
# PROV-02 SINGLE RETAINED SOURCE (Phase 57, plan-check B-1). Post-Phase-57 the
# AUTHORITATIVE per-agent enumerator is the RUST canonical_path map
# (rust/crates/agentlinux/src/main.rs::CANONICAL_IDS): the Rust `provision` flow
# iterates it IN-PROCESS and never consults a Bash map. This Bash map is
# DELIBERATELY RETAINED as the ONE sanctioned Bash definition — it is NOT a
# duplicate:
#   - tests/bats/13-reuse.bats (20 @tests) source `reuse::agent_decision` +
#     `reuse::_agent_decision_bash` directly and read this map (ADR-002 spec).
#   - tests/bats/73-phase51-gsd-codex.bats greps this file for the canonical
#     surfaces (gsd-core).
#   - the shim below is master's GATE-05 Bash-fallback rollback (unset
#     AGENTLINUX_RUST_BIN → the in-shell decision body).
#   - remediate.sh + prompt.sh iterate `${!REUSE_AGENT_CANONICAL_PATHS[@]}` for
#     the Bash-entrypoint provisioner path (14-remediate.bats:406 asserts
#     RESOLUTIONS[agents.<id>] populated). Those iterators stay on the retained
#     Bash-provisioner path; they are retired only at the Phase-59 cutover (when
#     the Bash entrypoint is removed).
# The scripts/check-no-bash-canonical-map.sh gate enforces exactly ONE Bash
# DEFINITION of each symbol, HERE — it does NOT require deleting this shim.
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
# v0.4.0 Rust-rewrite spike (Phase 53, RUST-03 / GATE-01): PREFER the `agentlinux`
# Rust binary (agentlinux-core::reuse) when it is available and produces a valid
# token; otherwise FALL BACK to the original in-shell logic
# (reuse::_agent_decision_bash). This keeps the brownfield-reuse install path AND
# CI green in environments where the binary is not (yet) staged — the real
# staging lands in Phase 56/57. Same env-var-in / stdout-token-out contract, so
# every 13-reuse.bats @test and the remediate.sh:288 call site work verbatim.
#
# Binary resolution (security L1): only an ABSOLUTE, executable `AGENTLINUX_RUST_BIN`
# is honoured — a bare relative name is rejected so a poisoned PATH entry can't be
# resolved. Failing that, `command -v agentlinux` is tried. The call is bounded by
# a `timeout` and its stdout is validated to be exactly one known token before it
# is trusted; anything else logs a specific error and falls through to bash.
#
# NB: REUSE_AGENT_CANONICAL_PATHS + REUSE_GSD_SYSTEM_PATH above are DELIBERATELY
# retained — remediate.sh:288 iterates the map's keys to enumerate per-agent
# decisions, and the bash fallback below reads both.
reuse::agent_decision() {
  local id=${1:-}

  # Resolve a usable Rust binary. Honour AGENTLINUX_RUST_BIN ONLY if it is an
  # absolute path AND executable (reject bare relative names — poisoned PATH).
  local bin=""
  local override=${AGENTLINUX_RUST_BIN:-}
  if [[ -n "$override" && "${override:0:1}" == "/" && -x "$override" ]]; then
    bin=$override
  else
    bin=$(command -v agentlinux 2>/dev/null || true)
  fi

  if [[ -n "$bin" && -x "$bin" ]]; then
    local token status
    token=$(timeout 10s "$bin" reuse-decision "$id" 2>/dev/null)
    status=$?
    if [[ $status -eq 0 ]]; then
      case "$token" in
        reuse | remediate | create)
          printf '%s' "$token"
          return 0
          ;;
      esac
    fi
    # Non-zero exit, timeout, or an unrecognised token: name the failing bin,
    # id, and exit code, then fall through to the in-shell fallback.
    log_error "reuse::agent_decision: Rust bin '$bin' failed for id='$id' (exit=$status, token='$token'); using bash fallback"
  fi

  reuse::_agent_decision_bash "$id"
  return $?
}

# reuse::_agent_decision_bash <id>
# The original in-shell decision body (verbatim from master) — predicates 1 + 2.
# Used when the Rust binary is unavailable or returns an invalid/failed result,
# so environments without the staged binary behave exactly as master did.
reuse::_agent_decision_bash() {
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
    # GSD's deployed-system form (npx install) lives at the VERSION file rather
    # than the bootstrapper binary path — also a valid canonical presence, so
    # reuse instead of treating it as a wrong-path reinstall.
    if [[ "$id" == "gsd" && "$detected_path" == "$REUSE_GSD_SYSTEM_PATH" ]]; then
      printf 'reuse'
      return 0
    fi
    # Healthy but wrong path → reinstall at the canonical path.
    printf 'remediate'
    return 0
  fi

  # Healthy + path-match. The CLI re-checks version-in-window before acting.
  printf 'reuse'
  return 0
}
