#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/nodejs.sh — REMEDIATE-01 npm-prefix Remediate stubs.
#
# Phase 14 Plan 14-01 ships ONLY the stubs; Plan 14-02 lands the real
# chown / rebase bodies per CONTEXT.md Area 2 (npm-prefix strategy selection
# + trivially-salvageable predicate + module-migration loop). Both
# `npm-prefix-chown` and `npm-prefix-rebase` are state-overwriting actions —
# the consent gate in remediate.sh has already enforced --yes (or registered
# a bail) before this stub is dispatched.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/remediate.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_NODEJS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_NODEJS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/nodejs.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::nodejs::npm_prefix_stub
#
# Stub for REMEDIATE-01 npm-prefix layer. Plan 14-02 replaces with the real
# strategy-selection algorithm (chown when under home + trivially salvageable;
# rebase to ~user/.npm-global otherwise). Plan 14-01 emits the [REMEDIATE-01]
# marker line so dispatch-shape @tests can grep-verify the stub is reachable
# after the gate passes.
remediate::nodejs::npm_prefix_stub() {
  log_info "[REMEDIATE-01] component=npm-prefix action=stub (Plan 14-02 replaces with chown/rebase strategy)"
  return 0
}
