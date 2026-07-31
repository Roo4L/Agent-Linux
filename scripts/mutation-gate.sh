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

# Fixed, not configurable: the run below always passes `--output .`, so this is
# where cargo-mutants writes. An override would only ever point the checks at a
# directory the tool never wrote.
readonly OUT_DIR="mutants.out"

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
# Set once an --in-diff file has been seen and validated. Guards the
# "no mutants in the diff" skip below: without it, that skip also swallows every
# OTHER way cargo-mutants exits 0 with no results file.
saw_diff_file=0

check_diff_file() {
  local f="$1"
  [[ -f $f ]] || die "--in-diff file '$f' does not exist (the caller's git diff failed)"
  if [[ ! -s $f ]]; then
    echo "mutation gate: diff is empty — no Rust lines changed, nothing to mutate."
    echo "- \`$mode\`: SKIPPED (empty diff)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    exit 0
  fi

  # Every `+++ b/<path>.rs` in the diff must resolve from the directory this
  # runs in. cargo-mutants matches --in-diff paths against the WORKSPACE root,
  # so a diff carrying repo-root-relative paths (i.e. a missing --relative, or a
  # step moved out of working-directory: rust) matches NOTHING and exits 0 —
  # which is indistinguishable from an honest "nothing here is mutable" unless
  # it is checked here. That failure is the one `test.yml` names as the reason
  # --relative is load-bearing.
  local p
  while read -r p; do
    [[ -f $p ]] || die "--in-diff names '$p', which does not exist relative to
  $(pwd). The diff's paths do not resolve against the workspace, so
  cargo-mutants would match nothing and exit 0 — a green gate that scored
  nothing. Check --relative and the step's working-directory."
  done < <(grep -oE '^\+\+\+ b/[^[:space:]]+\.rs$' "$f" | sed 's|^+++ b/||')

  saw_diff_file=1
}

want_diff_file=0
for arg in "$@"; do
  if [[ $want_diff_file -eq 1 ]]; then
    check_diff_file "$arg"
    want_diff_file=0
    continue
  fi
  case "$arg" in
    # Both spellings: cargo-mutants accepts `--in-diff F` and `--in-diff=F`, and
    # matching only the first left the equals form skipping this check entirely.
    --in-diff) want_diff_file=1 ;;
    --in-diff=*) check_diff_file "${arg#--in-diff=}" ;;
  esac
done
[[ $want_diff_file -eq 0 ]] || die "--in-diff given with no file argument"

# A killed --in-place run leaves mutated source behind. Warn if the tree is
# already dirty so a developer cannot mistake cargo-mutants' residue for their
# own edits (CI checkouts are always clean, so this is silent there).
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1 &&
  ! git diff --quiet; then
  echo "mutation gate: NOTE — working tree is dirty before the run; --in-place" >&2
  echo "  mutates in place, so check 'git diff' for '~ changed by cargo-mutants ~'" >&2
  echo "  residue if this run is interrupted." >&2
fi

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

# A non-empty --in-diff whose lines yield no mutants — a test-only change, or a
# manifest edit now that the pathspec is the whole rust/ tree — is a legitimate
# outcome and must be NAMED: a gate that hard-fails on a PR the contributor
# cannot fix is how the previous one earned its bypass.
#
# But `exit 0` with no results file is NOT unique to that case. cargo-mutants
# also exits 0 writing nothing when a --file filter matches nothing, when a
# --shard is empty, on --list, and — the dangerous one — when --in-diff's paths
# do not resolve against the workspace. Skipping on the bare status therefore
# turned the canonical missing---relative bug into a permanent green, on the
# ENFORCING gate, with a step-summary line that read like a real outcome.
#
# So the skip requires an --in-diff file that was supplied, non-empty, and whose
# paths resolve (checked in check_diff_file). Every other absent-outcomes case
# falls through to the hard failure below.
if [[ ! -f $outcomes && $cargo_status -eq 0 && $saw_diff_file -eq 1 ]]; then
  echo "mutation gate: the diff produced no mutants — nothing in it is mutable"
  echo "  (test-only lines, comments, or manifest edits). Nothing to score."
  echo "- \`$mode\`: SKIPPED (no mutants in diff)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 0
fi

[[ -f $outcomes ]] || die "no $outcomes after cargo-mutants exited $cargo_status.
  cargo-mutants did not complete a run — usually a rejected flag combination or a
  failing baseline. Fix the invocation; do NOT mask this as 'surviving mutants'."

# cargo-mutants rewrites outcomes.json after EVERY scenario, so a run killed
# partway leaves a well-formed file describing only the mutants it reached. A
# SIGKILL after 13 of 78 leaves {"total_mutants":13,"missed":0,"caught":13} —
# which reads exactly like a clean sweep. Two independent completeness checks:
#
#   end_time      set only by the final summary write; null on every incremental one.
#   mutants.json  written once, AFTER all filtering and sharding, so its length
#                 is the number of mutants this run was supposed to test.
#
# Verified against cargo-mutants 27.1.0 by SIGKILLing a real run.
if ! read -r total missed caught timeout unviable finished planned < <(
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
try:
    planned = len(json.load(open(sys.argv[2])))
except Exception:
    planned = -1
print(
    d["total_mutants"], d["missed"], d["caught"], d["timeout"], d["unviable"],
    0 if d.get("end_time") is None else 1, planned,
)
' "$outcomes" "$OUT_DIR/mutants.json"
); then
  die "could not read $outcomes — malformed JSON, a missing key, or no python3.
  cargo-mutants may have changed its results schema; see tests/bats/80-mutation-gate.bats
  MUT-14, the contract test that pins it."
fi

if [[ $finished -eq 0 ]]; then
  die "cargo-mutants exited $cargo_status without writing a final summary
  (outcomes.json has no end_time). The run was interrupted — OOM-killed, timed
  out, or crashed — after testing $total mutant(s). A partial run is not a pass."
fi
if [[ $planned -ge 0 && $planned -ne $total ]]; then
  die "cargo-mutants planned $planned mutant(s) but outcomes.json records only
  $total. The run did not finish; a partial result is not a pass."
fi

summary="mutants: ${total} tested, ${caught} caught, ${missed} missed, ${timeout} timeout, ${unviable} unviable"
echo "mutation gate ($mode): $summary"
echo "- \`$mode\`: $summary" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

if [[ $total -eq 0 ]]; then
  die "cargo-mutants tested 0 mutants. Either the filter matched nothing (check
  --in-diff --relative path rewriting) or the run aborted. A zero-mutant run is
  never a pass."
fi

# An unviable mutant is one that did not compile, so no test ran against it.
# A run where EVERY mutant is unviable exercised nothing — the same hole as
# total == 0, one step in.
viable=$((total - unviable))
if [[ $viable -le 0 ]]; then
  die "all $total mutant(s) were unviable (none compiled), so no test was
  exercised. Not a pass. Check that the filtered lines can actually be mutated."
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
