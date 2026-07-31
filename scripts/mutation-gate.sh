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

# Every line this script renders into the job summary carries a VERDICT. An
# earlier revision appended the `mutants: N tested, …` line before the remaining
# die-checks, so a job that failed on one of them left a count with no verdict
# next to it as the only rendered output — a reader had to open the log to learn
# whether it passed. Now the count is only ever emitted together with PASS,
# WARN or (via `die`) FAIL.
step_summary() {
  echo "- \`${mode:-mutation gate}\`: $*" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

die() {
  echo "MUTATION GATE FAIL: $*" >&2
  # Only the first line: the messages below are multi-line explanations, and a
  # markdown list item that swallows the rest renders as one run-on paragraph.
  step_summary "**FAIL** — ${1%%$'\n'*}"
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
# The --in-diff file, if one was given. The gate's expectation is derived from
# the TOOL, not from inspecting the argument vector — see verify_expectation.
diff_file=""

check_diff_file() {
  local f="$1"
  [[ -f $f ]] || die "--in-diff file '$f' does not exist (the caller's git diff failed)"
  if [[ ! -s $f ]]; then
    echo "mutation gate: diff is empty — no Rust lines changed, nothing to mutate."
    step_summary "SKIPPED (empty diff)"
    exit 0
  fi

  # The file must actually PARSE as a diff before "found no .rs paths" can mean
  # "nothing to check". Without this the extraction below is a fail-OPEN
  # whitelist: anything it cannot parse yields zero matches and is waved through
  # as verified.
  grep -qE '^(diff --git |--- |\+\+\+ )' "$f" || die "--in-diff file '$f' is not
  a diff — no 'diff --git' or '---/+++' header found. Refusing to treat an
  unparseable file as 'nothing to check'."

  # Every `.rs` path named in a `+++` header must resolve from the directory
  # this runs in. cargo-mutants matches --in-diff paths against the WORKSPACE
  # root, so a diff carrying repo-root-relative paths (a missing --relative, or
  # a step moved out of working-directory: rust) matches NOTHING and exits 0 —
  # indistinguishable from an honest "nothing here is mutable" unless checked.
  #
  # Tolerant of: CRLF; a trailing tab+timestamp (GNU `diff -u` headers); a
  # one-letter prefix
  # (`a/`, `i/`, git's diff.srcPrefix/dstPrefix); `diff.noprefix` (no prefix at
  # all); and spaces in paths. `/dev/null` (a deletion) is skipped.
  #
  # The prefix strip is an ALTERNATION, not two independently-optional pieces:
  # `[a-z]\{0,1\}/\{0,1\}` turned `+++ src/lib.rs` into `rc/lib.rs`, which
  # would hard-fail every legitimate PR under a runner with diff.noprefix set
  # while a comment claimed the opposite.
  # A `core.quotePath` header (git's default) octal-escapes non-ASCII bytes:
  # `+++ "b/src/caf\303\251.rs"`. Decoding that correctly in sed is more
  # trouble than it is worth, and guessing wrong means hard-failing an honest
  # PR — so refuse the diff and say what to do instead. An earlier comment
  # claimed this shape was tolerated; it was not.
  if grep -qE '^\+\+\+ ".*\\[0-7]{3}' "$f"; then
    die "--in-diff file '$f' contains a core.quotePath-escaped path, which this
  gate cannot verify. Regenerate the diff with -c core.quotePath=false."
  fi

  local p
  while read -r p; do
    [[ -f $p ]] || die "--in-diff names '$p', which does not exist relative to
  $(pwd). The diff's paths do not resolve against the workspace, so
  cargo-mutants would match nothing and exit 0 — a green gate that scored
  nothing. Check --relative and the step's working-directory."
  done < <(sed -n 's/\r$//; s/\t.*$//; s|^+++ ||p' "$f" |
    sed 's|^"||; s|"$||; s|^[a-z]/||' |
    grep -E '\.rs$' | grep -v '^dev/null$')

}

# Find the --in-diff file. That is ALL this loop does now.
#
# Four rounds of this script tried to decide, by reading argv, whether the
# caller had narrowed the mutant set — first a denylist of filter flags, then an
# allowlist of benign ones. Both are hand-copies of clap's grammar and both
# leaked: eleven flag spellings walked through the denylist, and the allowlist
# still blessed `--verbose`/`-q` (which do not exist) and `--jobs` (which
# `--in-place` forbids) while rejecting `-t`, `--baseline` and `-- --test-threads`.
# Worse, `.cargo/mutants.toml` narrows the set with NO argv evidence at all, so
# no argument rule can see it, by construction.
#
# So stop guessing and ask the tool. See verify_expectation below.
want_diff_file=0
for arg in "$@"; do
  if [[ $want_diff_file -eq 1 ]]; then
    check_diff_file "$arg"
    diff_file="$arg"
    want_diff_file=0
    continue
  fi
  case "$arg" in
    --in-diff | -D) want_diff_file=1 ;;
    --in-diff=*)
      check_diff_file "${arg#*=}"
      diff_file="${arg#*=}"
      ;;
    -D?*)
      check_diff_file "${arg#-D}"
      diff_file="${arg#-D}"
      ;;
    --list | --list-files)
      die "'$arg' produces no mutation score; the gate cannot run against it"
      ;;
  esac
done
[[ $want_diff_file -eq 0 ]] || die "--in-diff given with no file argument"

# `#[mutants::skip]` is the ONE narrowing channel the tool-derived expectation
# below cannot see. A skipped function is absent from both `cargo mutants --list`
# and `mutants.json`, so the two sets still match and the gate still says PASS.
# In the enforcing per-PR gate that is self-licensing: the author of a red mutant
# can grant themselves the exemption inside the very diff being scored, and both
# the expectation and the scored set shrink together.
#
# ADR-020 §4 already requires a written reason at every skip site. This is the
# mechanical half of that rule, and it is deliberately narrow:
#
#   scope   only files whose diff ADDS a skip line — a PR is not answerable for
#           skips somebody else left behind.
#   check   made against the FILE, not the diff, because a unified diff does not
#           say which occurrence a `+` line became. So once a file is in scope,
#           every skip in it must be justified. That over-reaches by exactly the
#           skips already in a file the PR is adding another one to, which is
#           the case worth reading anyway.
#   rule    a comment line within the three lines above. That is a shape check,
#           not a judgement: it makes an UNANNOTATED skip impossible to merge,
#           and leaves "is the reason any good" to the reviewer, where it
#           belongs. ADR-020 §4's back-reference requirement is likewise a
#           human call.
check_added_skips() {
  local offenders
  if ! offenders=$(python3 -c '
import re, sys

paths, cur = set(), None
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n").rstrip("\r")
    if line.startswith("+++ "):
        p = re.sub(r"^[a-z]/", "", line[4:].split("\t")[0].strip().strip("\""))
        cur = p if p.endswith(".rs") else None
    elif cur and line.startswith("+") and "mutants::skip" in line:
        paths.add(cur)

bad = []
for path in sorted(paths):
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    for i, l in enumerate(lines):
        if "mutants::skip" not in l:
            continue
        above = [x.strip() for x in lines[max(0, i - 3):i]]
        if not any(x.startswith("//") for x in above):
            bad.append("  %s:%d: %s" % (path, i + 1, l.strip()))
print("\n".join(bad))
' "$1"); then
    die "could not check the diff for added #[mutants::skip] annotations. The
  gate cannot confirm the PR did not exempt itself, so it will not pass."
  fi

  [[ -z $offenders ]] && return 0

  echo "$offenders" >&2
  die "this diff adds a #[mutants::skip] with no comment above it (see above).
  A skip is invisible to every other check here — the skipped function drops out
  of the expectation AND the scored set together — so it is the one exemption an
  author can grant themselves inside the diff being scored. Put the reason on the
  line above it, per ADR-020 §4."
}

[[ -n $diff_file ]] && check_added_skips "$diff_file"

# A killed --in-place run leaves mutated source behind. Warn if the tree is
# already dirty so a developer cannot mistake cargo-mutants' residue for their
# own edits (CI checkouts are always clean, so this is silent there).
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1 &&
  ! git diff --quiet; then
  echo "mutation gate: NOTE — working tree is dirty before the run; --in-place" >&2
  echo "  mutates in place, so check 'git diff' for '~ changed by cargo-mutants ~'" >&2
  echo "  residue if this run is interrupted." >&2
fi

# ---------------------------------------------------------------------------
# The expectation, asked of the tool BEFORE anything runs.
#
# `--list` performs cargo-mutants' own filtering, so it accounts for every flag
# spelling, every flag a future release adds, and `.cargo/mutants.toml` — which
# narrows the set with no argument-vector evidence at all. `--no-config` makes
# the expectation the honest one: what this scope SHOULD contain, not what a
# config file left behind. `--list` builds nothing and writes no `mutants.out`,
# so it is cheap to run first — and running it first means a scope mismatch is
# reported before paying for the run, and before `--in-place` has rewritten the
# tree the query would otherwise parse.
#
# A FAILED query is fatal. It used to be swallowed (`2>/dev/null … || true`),
# which produced `expected=0` and took the skip below — silently disabling the
# outcomes check, both completeness checks, the accounting identity and the
# survivor check in one step. `cargo mutants --list` failing is a broken gate,
# not an empty scope.
expected_file="$(mktemp)"
list_err="$(mktemp)"
trap 'rm -f "$expected_file" "$list_err"' EXIT

list_args=(--no-config --list)
[[ -n $diff_file ]] && list_args+=(--in-diff "$diff_file")

if ! cargo mutants "${list_args[@]}" >"$expected_file" 2>"$list_err"; then
  echo "--- cargo mutants --list stderr ---" >&2
  cat "$list_err" >&2 || true
  die "could not ask cargo-mutants what this scope contains. The gate's
  expectation is unknown, so nothing it observes afterwards can be trusted.
  (A common cause is running from a directory with no Cargo.toml.)"
fi

expected=$(grep -c . "$expected_file" || true)

# Zero expected is the ONE legitimate skip: this scope genuinely contains
# nothing mutable. Derived from the tool, so no filter flag or config file can
# manufacture it — and reached only when the query SUCCEEDED.
if [[ $expected -eq 0 ]]; then
  echo "mutation gate: nothing mutable in scope — cargo-mutants lists 0 mutants,"
  echo "  so there is nothing to score."
  step_summary "SKIPPED (no mutants in scope)"
  exit 0
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
# `planned` is a length when mutants.json reads as a JSON array, and otherwise a
# sentinel naming HOW it failed. An earlier revision collapsed every failure into
# -1 and skipped the check, which made a schema change (`{"mutants": […]}`) come
# out as `len == 1` — reported as "the run did not finish", the one diagnosis
# guaranteed to send a reader looking at the runner instead of at the tool.
readonly NO_FILE=-1 UNPARSEABLE=-2 NOT_A_LIST=-3
if ! read -r total missed caught timeout unviable finished planned < <(
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
try:
    m = json.load(open(sys.argv[2]))
except FileNotFoundError:
    planned = -1
except Exception:
    planned = -2
else:
    planned = len(m) if isinstance(m, list) else -3
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

# mutants.json is not optional: the set comparison below is the check that
# catches a narrowed or padded run, and it has no fallback.
case $planned in
  "$NO_FILE") die "cargo-mutants left no $OUT_DIR/mutants.json, so what it planned
  to test is unknown and the scored set cannot be checked." ;;
  "$UNPARSEABLE") die "$OUT_DIR/mutants.json is not readable as JSON. The run's
  planned mutant set is unknown, so neither the completeness check nor the set
  comparison below can be trusted." ;;
  "$NOT_A_LIST") die "$OUT_DIR/mutants.json is valid JSON but not an array —
  cargo-mutants has changed its results schema. Update this gate and
  tests/bats/80-mutation-gate.bats MUT-14 (the contract test that pins it)
  together; do NOT read this as an interrupted run." ;;
esac

if [[ $finished -eq 0 ]]; then
  die "cargo-mutants exited $cargo_status without writing a final summary
  (outcomes.json has no end_time). The run was interrupted — OOM-killed, timed
  out, or crashed — after testing $total mutant(s). A partial run is not a pass."
fi
if [[ $planned -ne $total ]]; then
  die "cargo-mutants planned $planned mutant(s) but outcomes.json records only
  $total. The run did not finish; a partial result is not a pass."
fi

# Compare the SETS, not their sizes.
#
# `mutants.json`'s `name` field is byte-identical to a `--list` line, so the two
# are directly comparable — and the script already opens both. Counting was not
# enough: `--error VALUE` (and its `error_values` config equivalent) ADDS a
# mutant per Result-returning fn, so one knob could hide the survivors and a
# second refill the count back to the expected number, yielding
# "PASS — every mutant was caught" with no argv evidence at all.
#
# Two rules, matching what the two gates are for:
#   enforce  — the scored set must EQUAL the expectation. A merge gate that
#              skipped part of the change is not a merge gate.
#   advisory — the scored set must be a non-empty SUBSET. Sharding is legitimate
#              narrowing here: each nightly runner scores a slice, and the four
#              together cover the workspace. (This is the one place a narrowing
#              filter is tolerated, and only because the mode is a warning.)
# In BOTH modes, anything scored that is NOT in the expectation fails — that is
# the mutant-adding case, and it means the run was not measuring this code.
# Appended to the reported summary when this run covered only part of the scope
# (an advisory shard). Without it the rendered step summary of a 3%-coverage
# shard was indistinguishable from a clean full-workspace sweep — the original
# "nothing survived vs nothing ran" confusion, one level up in the reporting.
partial=""

# Read through a command substitution, NOT `mapfile < <(…)`: a process
# substitution discards python's exit status, so a crash here used to surface as
# `verdict[0]: unbound variable` from `set -u` — a bash diagnostic for a
# cargo-mutants problem, on the line that decides whether the run measured this
# code.
if ! set_diff=$(
  python3 -c '
import json, sys
expected = {l.rstrip("\n") for l in open(sys.argv[1]) if l.strip()}
scored = {m.get("name", "") for m in json.load(open(sys.argv[2]))}
missing = sorted(expected - scored)
extra = sorted(scored - expected)
print(len(missing))
print(len(extra))
for m in missing[:10]:
    print("  unscored: " + m)
for m in extra[:10]:
    print("  unexpected: " + m)
' "$expected_file" "$OUT_DIR/mutants.json"
); then
  die "could not compare the expected mutant set against $OUT_DIR/mutants.json.
  Whether this run scored the code it claims to have scored is unknown, which is
  the question this gate exists to answer."
fi

mapfile -t verdict <<<"$set_diff"
[[ ${#verdict[@]} -ge 2 ]] || die "the set comparison produced no counts, so the
  scored set could not be checked against the expectation."
unscored_n="${verdict[0]}"
unexpected_n="${verdict[1]}"
detail=$(printf '%s\n' "${verdict[@]:2}")

if [[ $unexpected_n -gt 0 ]]; then
  echo "$detail" >&2
  die "the run scored $unexpected_n mutant(s) this scope does not contain. Something
  ADDED mutants (--error, or error_values in .cargo/mutants.toml), so the score
  does not describe this code."
fi

if [[ $unscored_n -gt 0 ]]; then
  if [[ $mode == enforce ]]; then
    echo "$detail" >&2
    die "$unscored_n mutant(s) in scope were never scored. Something narrowed the
  set — a filter flag, a --shard, or an exclusion in .cargo/mutants.toml. Scoring
  a subset is not scoring the change: the unscored mutants may be exactly the
  surviving ones. Run the enforcing gate over the whole scope; shard the DIFF,
  not the mutant set."
  else
    # Advisory: a shard is a legal subset. Say how much of the scope this run
    # covered so a reader is never misled about what the score means.
    partial=" — $total of $expected in scope ($unscored_n not in this slice)"
  fi
fi

# Every mutant must land in exactly one bucket. `--check` builds each mutant
# without running any test, leaving total=10 with all four counters at 0 — so
# the gate printed "0 caught" and "every mutant was caught" on consecutive
# lines. An accounting identity costs one comparison and closes it.
accounted=$((caught + missed + timeout + unviable))
if [[ $accounted -ne $total ]]; then
  die "cargo-mutants reports $total mutant(s) but only $accounted are accounted
  for (caught=$caught missed=$missed timeout=$timeout unviable=$unviable). No
  test was run against the remainder — a --check run builds mutants without
  testing them, which is not a mutation score."
fi

summary="mutants: ${total} tested, ${caught} caught, ${missed} missed, ${timeout} timeout, ${unviable} unviable${partial}"
echo "mutation gate ($mode): $summary"

# Nothing is written to the job summary until the checks below have run: see
# step_summary's comment. A count on its own is not a verdict.
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
  if [[ -n $partial ]]; then
    echo "mutation gate ($mode): every mutant IN THIS SLICE was caught$partial."
    step_summary "PARTIAL PASS — every mutant in this slice was caught; $summary"
  else
    echo "mutation gate ($mode): PASS — every mutant was caught."
    step_summary "PASS — $summary"
  fi
  exit 0
fi

echo "--- surviving mutants ---" >&2
cat "$OUT_DIR/missed.txt" "$OUT_DIR/timeout.txt" 2>/dev/null >&2 || true

if [[ $mode == advisory ]]; then
  echo "::warning::${survivors} surviving mutant(s) — $summary"
  step_summary "**WARN** — ${survivors} surviving mutant(s); $summary"
  exit 0
fi

die "${survivors} of ${total} mutant(s) survived (see the list above).
  Add a test that kills them, or annotate a genuinely unobservable mutant with
  #[mutants::skip] AND a comment saying why."
