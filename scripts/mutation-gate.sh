#!/usr/bin/env bash
# scripts/mutation-gate.sh — run cargo-mutants and report a verdict from its
# RESULTS FILE, never from its exit code alone.
#
# Why a script instead of a `run:` one-liner: the previous inline gate was
#
#   cargo mutants --in-place --jobs 4 || echo "::warning::surviving mutants"
#
# and cargo-mutants rejects that flag pair outright ("the argument '--in-place'
# cannot be used with '--jobs'"). The `||` turned the usage error into a success,
# `continue-on-error: true` turned the job green, and the warning text read like a
# real result — so the nightly reported a mutation score while generating zero
# mutants. A gate that cannot distinguish "nothing survived" from "nothing ran"
# is not a gate.
#
# So the verdict here comes from `mutants.out/outcomes.json`, which only exists if
# cargo-mutants actually completed a run. No file, or a run that tested zero
# mutants when mutants were expected, is a HARD FAILURE in both modes.
#
# Usage:
#   mutation-gate.sh enforce --in-diff <diff-file> [extra cargo-mutants args...]
#   mutation-gate.sh advisory --shard 1/4        [extra cargo-mutants args...]
#
# Modes differ ONLY in what a surviving mutant means:
#   enforce  — surviving mutants fail (the per-PR merge gate)
#   advisory — surviving mutants warn (the nightly full-workspace score)
# Neither mode tolerates a run that did not happen.
set -euo pipefail

readonly OUT_DIR="${MUTANTS_OUT_DIR:-mutants.out}"

die() {
  echo "MUTATION GATE FAIL: $*" >&2
  exit 1
}

[[ $# -ge 1 ]] || die "usage: $0 <enforce|advisory> [cargo-mutants args...]"
mode="$1"
shift
case "$mode" in
  enforce | advisory) ;;
  *) die "unknown mode '$mode' (want enforce|advisory)" ;;
esac

# `--in-diff <file>` with an EMPTY file is cargo-mutants' documented no-op: it
# logs "Diff file is empty" and exits 0. That is a legitimate outcome (a PR that
# touches no Rust), but it must be visible rather than indistinguishable from a
# clean pass, so name it here and skip the run.
want_diff_file=0
for arg in "$@"; do
  if [[ $want_diff_file -eq 1 ]]; then
    [[ -f $arg ]] || die "--in-diff file '$arg' does not exist (the caller's git diff failed)"
    if [[ ! -s $arg ]]; then
      echo "mutation gate: diff is empty — no Rust lines changed, nothing to mutate."
      echo "- \`$mode\`: SKIPPED (empty diff)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
      exit 0
    fi
    want_diff_file=0
    continue
  fi
  [[ $arg == "--in-diff" ]] && want_diff_file=1
done
[[ $want_diff_file -eq 0 ]] || die "--in-diff given with no file argument"

rm -rf "$OUT_DIR"

# Run it. A non-zero exit is NOT interpreted here: cargo-mutants exits non-zero
# both for "mutants survived" (a finding) and for "bad flags / baseline failed"
# (a broken gate), and conflating those is the bug this script exists to prevent.
# The outcomes file below is what tells them apart.
set +e
cargo mutants --output . "$@"
cargo_status=$?
set -e

outcomes="$OUT_DIR/outcomes.json"
[[ -f $outcomes ]] || die "no $outcomes after cargo-mutants exited $cargo_status.
  cargo-mutants did not complete a run — usually a rejected flag combination or a
  failing baseline. Fix the invocation; do NOT mask this as 'surviving mutants'."

read -r total missed caught timeout unviable < <(
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d["total_mutants"], d["missed"], d["caught"], d["timeout"], d["unviable"])
' "$outcomes"
)

summary="mutants: ${total} tested, ${caught} caught, ${missed} missed, ${timeout} timeout, ${unviable} unviable"
echo "mutation gate ($mode): $summary"
echo "- \`$mode\`: $summary" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

if [[ $total -eq 0 ]]; then
  die "cargo-mutants tested 0 mutants. Either the filter matched nothing (check
  --in-diff --relative path rewriting) or the run aborted. A zero-mutant run is
  never a pass."
fi

if [[ $timeout -gt 0 ]]; then
  echo "mutation gate: ${timeout} mutant(s) timed out — treated as surviving." >&2
fi

survivors=$((missed + timeout))
if [[ $survivors -eq 0 ]]; then
  echo "mutation gate ($mode): PASS — every mutant was caught."
  exit 0
fi

echo "--- surviving mutants ---" >&2
cat "$OUT_DIR/missed.txt" "$OUT_DIR/timeout.txt" 2>/dev/null >&2 || true

if [[ $mode == advisory ]]; then
  echo "::warning::${survivors} surviving mutant(s) — $summary"
  exit 0
fi

die "${survivors} mutant(s) survived. Add a test that kills them, or annotate a
  genuinely unobservable mutant with #[mutants::skip] AND a comment saying why."
