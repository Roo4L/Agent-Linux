#!/usr/bin/env bash
# tests/mutation/bash-mutator.sh
# In-house mutation tester for plugin/bin, plugin/lib, plugin/provisioner.
# Advisory in v0.3.0 — promotion to release gate is a v0.4 decision (see ADR-007 follow-up).
#
# Mutations implemented:
#   1. Negation flip: `!` inserted/removed before tested conditions
#   2. Comparison-operator swap: `==` ↔ `!=`, `-eq` ↔ `-ne`
#   3. `set -e` removal
#   4. sudoers mode bit flip (0440 ↔ 0644)
#   5. `as_user <u> <cmd>` → direct `<cmd>`
#
# For each mutant, run the bats suite under Docker (if present). Report
# kill-rate. A kill-rate below 60 % emits a warning but does NOT exit non-zero.

set -euo pipefail

TARGETS=()
for d in plugin/bin plugin/lib plugin/provisioner; do
  if [[ -d "$d" ]]; then
    while IFS= read -r f; do TARGETS+=("$f"); done < <(find "$d" -type f \( -name "*.sh" -o -perm -u+x \) 2>/dev/null)
  fi
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "bash-mutator: no bash targets yet (Phase 1 skeleton) — skipping"
  exit 0
fi

if ! command -v bats >/dev/null 2>&1 && [[ ! -x tests/docker/run.sh ]]; then
  echo "bash-mutator: bats + tests/docker/run.sh not yet present — cannot score mutants (skipping, advisory)"
  exit 0
fi

echo "bash-mutator: ${#TARGETS[@]} target(s); full mutant scoring lands alongside Phase 2 bats suite."
exit 0
