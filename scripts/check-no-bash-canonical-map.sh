#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check-no-bash-canonical-map.sh — PROV-02 single-source gate.
#
# PROV-02 keeps EXACTLY ONE Bash source of the catalog canonical-path map, in the
# sanctioned file plugin/lib/reuse/agents.sh. That file is DELIBERATELY RETAINED
# (plan-check B-1): tests/bats/13-reuse.bats (20 @tests) source
# `reuse::agent_decision` directly, tests/bats/73-*.bats greps it, and it is
# master's GATE-05 rollback fallback. So the map is NOT deleted — instead this
# gate enforces there is exactly ONE Bash DEFINITION of each map symbol and that
# it lives ONLY in plugin/lib/reuse/agents.sh. It FAILS (exit 1) if a second
# Bash definition is re-introduced anywhere else under plugin/, or if the count in
# the sanctioned file exceeds one each.
#
# This guards the real PROV-02 duplication risk (a copy of the map drifting from
# the Rust-authoritative source). The Rust-authoritative-source assertion — that
# provision.rs iterates the Rust `canonical_path` map in-process — lives in 57-06
# (a POSITIVE grep). This gate is GREEN from Wave 0: it is a REGRESSION GUARD
# against re-duplication, NOT a two-phase "armed to fail" gate.
#
# Definitions targeted (assignment forms, NOT `${!…[@]}` reads or comments):
#   declare -gA REUSE_AGENT_CANONICAL_PATHS=(
#   REUSE_GSD_SYSTEM_PATH=           (bare or `readonly REUSE_GSD_SYSTEM_PATH=`)
#
# SELF-TEST (proves this gate has teeth). Inject a second definition into any
# other plugin/ *.sh file and re-run — the gate MUST exit non-zero:
#   $ printf 'declare -gA REUSE_AGENT_CANONICAL_PATHS=(\n  [x]="/y"\n)\n' \
#       > plugin/lib/_gate_selftest.sh
#   $ bash scripts/check-no-bash-canonical-map.sh; echo "exit=$?"
#   FAIL: canonical-map definition outside the sanctioned file: ...
#   exit=1
#   $ rm plugin/lib/_gate_selftest.sh   # gate returns to exit 0
# Conversely, injecting a SECOND copy INTO the sanctioned file (two `declare -gA
# REUSE_AGENT_CANONICAL_PATHS=` lines) also trips it via the per-file count check.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
SANCTIONED="plugin/lib/reuse/agents.sh"
PLUGIN_DIR="$REPO_ROOT/plugin"

if [[ ! -d $PLUGIN_DIR ]]; then
  printf 'check-no-bash-canonical-map: plugin/ not found at %s\n' "$PLUGIN_DIR" >&2
  exit 2
fi

# The two DEFINITION forms (assignment), anchored so a `${!REUSE_AGENT_CANONICAL_PATHS[@]}`
# read (remediate.sh:288) is NOT matched. The map: `declare -gA REUSE_AGENT_CANONICAL_PATHS=`.
# The system-path const: an assignment to REUSE_GSD_SYSTEM_PATH (optionally
# `readonly`), i.e. `REUSE_GSD_SYSTEM_PATH=` at a word boundary, but NOT
# `$REUSE_GSD_SYSTEM_PATH` / `${REUSE_GSD_SYSTEM_PATH}` reads.
MAP_DEF='declare -gA REUSE_AGENT_CANONICAL_PATHS='
SYSPATH_DEF='(^|[[:space:]]|readonly[[:space:]])REUSE_GSD_SYSTEM_PATH='

# Grep every plugin/ shell file, filtering out comment lines FIRST (a line whose
# first non-space char is `#`) so a doc mention of the symbol is never a hit.
# `grep -rn` prints file:line:content; the comment filter matches that prefix.
scan() {
  local pattern=$1
  grep -rInE --include='*.sh' -- "$pattern" "$PLUGIN_DIR" 2>/dev/null \
    | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true
}

rc=0

check_symbol() {
  local label=$1 pattern=$2
  local hits
  hits=$(scan "$pattern")

  # Any hit whose file is NOT the sanctioned file is a violation.
  local outside
  outside=$(printf '%s\n' "$hits" | grep -v '^$' \
    | grep -vF "$REPO_ROOT/$SANCTIONED:" || true)
  if [[ -n $outside ]]; then
    printf 'FAIL: %s definition outside the sanctioned file (%s):\n' "$label" "$SANCTIONED" >&2
    # Print repo-relative file:line for readability.
    printf '%s\n' "$outside" | sed "s#^$REPO_ROOT/##" >&2
    rc=1
  fi

  # The sanctioned file must hold EXACTLY ONE definition of this symbol.
  local in_sanctioned count
  in_sanctioned=$(printf '%s\n' "$hits" | grep -v '^$' \
    | grep -F "$REPO_ROOT/$SANCTIONED:" || true)
  count=$(printf '%s\n' "$in_sanctioned" | grep -c . || true)
  if [[ $count -ne 1 ]]; then
    printf 'FAIL: expected exactly ONE %s definition in %s, found %d\n' \
      "$label" "$SANCTIONED" "$count" >&2
    rc=1
  fi
}

check_symbol "REUSE_AGENT_CANONICAL_PATHS" "$MAP_DEF"
check_symbol "REUSE_GSD_SYSTEM_PATH" "$SYSPATH_DEF"

if [[ $rc -eq 0 ]]; then
  printf 'OK: exactly one Bash canonical-map definition, in %s (PROV-02 single-source)\n' \
    "$SANCTIONED"
fi
exit "$rc"
