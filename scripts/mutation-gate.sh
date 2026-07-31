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

# Everything the gate checks about the diff file, in ONE pass.
#
# Both halves — the `.rs` paths that must resolve, and the `#[mutants::skip]`
# lines the PR adds — parse `+++` headers, and they used to do it twice: once in
# sed, once in python, with the prefix-stripping rule written out in each. One
# reader means one grammar to be wrong about.
check_diff() {
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

  # A `core.quotePath` header (git's default) octal-escapes non-ASCII bytes:
  # `+++ "b/src/caf\303\251.rs"`. Decoding that correctly is more trouble than it
  # is worth, and guessing wrong means hard-failing an honest PR — so refuse the
  # diff and say what to do instead.
  if grep -qE '^\+\+\+ ".*\\[0-7]{3}' "$f"; then
    die "--in-diff file '$f' contains a core.quotePath-escaped path, which this
  gate cannot verify. Regenerate the diff with -c core.quotePath=false."
  fi

  # Reported as two sections so one reader answers both questions:
  #
  #   PATHS   every `.rs` file named in a `+++` header. cargo-mutants matches
  #           --in-diff paths against the WORKSPACE root, so a diff carrying
  #           repo-root-relative paths (a missing --relative, or a step moved out
  #           of `working-directory: rust`) matches NOTHING and exits 0 —
  #           indistinguishable from an honest "nothing here is mutable".
  #           Tolerant of CRLF, a trailing tab+timestamp (GNU `diff -u`), a
  #           one-letter prefix (`a/`, `i/`, diff.srcPrefix), `diff.noprefix`,
  #           and spaces in paths. `/dev/null` (a deletion) is skipped.
  #
  #   SKIPS   `#[mutants::skip]` is the ONE narrowing channel the tool-derived
  #           expectation below cannot see: a skipped function is absent from
  #           both `cargo mutants --list` and `mutants.json`, so the two sets
  #           still match and the gate still says PASS. In the enforcing per-PR
  #           gate that is self-licensing — the author of a red mutant can grant
  #           themselves the exemption inside the very diff being scored.
  #
  #           ADR-020 §4 already requires a written reason at every skip site;
  #           this is the mechanical half, deliberately narrow. Only files whose
  #           diff ADDS a skip are in scope (a PR is not answerable for skips
  #           somebody else left behind), the check is then made against the FILE
  #           because a unified diff does not say which occurrence a `+` line
  #           became, and the rule is "a comment line within the three above".
  #           That is a shape check, not a judgement: it makes an UNANNOTATED
  #           skip unmergeable and leaves "is the reason any good" — and ADR-020
  #           §4's back-reference requirement — to the reviewer.
  #
  #           Recognising the annotation is the one place this DOES model Rust,
  #           and a plain substring match was not enough: Rust tolerates
  #           whitespace and comments around `::`, cargo-mutants resolves the
  #           attribute through `syn` rather than textually, and
  #           `#[cfg_attr(test, mutants :: skip)]` really does suppress every
  #           mutant — one extra space bought the whole exemption back, in a
  #           spelling that looks MORE idiomatic to a reviewer skimming the diff.
  #           So the line is normalised (block comments dropped, whitespace
  #           removed) and must be an ATTRIBUTE. ADR-020 §2 rules out
  #           hand-copied grammars after the argv denylist leaked eleven flag
  #           spellings; this one is knowingly small, and the difference is that
  #           clap's flag grammar is large and grows every release while
  #           "optional whitespace or a block comment around `::`" is closed and
  #           has not changed since Rust 1.0. Requiring `#[` also stops a `//`
  #           comment that merely MENTIONS the attribute — every justification
  #           comment does — from being read as a skip.
  local report
  if ! report=$(python3 -c '
import re, sys


def is_skip_attr(line):
    """A Rust attribute applying mutants::skip, whitespace-insensitive."""
    n = re.sub(r"\s+", "", re.sub(r"/\*.*?\*/", "", line))
    return n.startswith("#[") and "mutants::skip" in n


paths, cur, adds_skip = [], None, set()
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n").rstrip("\r")
    if line.startswith("+++ "):
        p = re.sub(r"^[a-z]/", "", line[4:].split("\t")[0].strip().strip("\""))
        # No dev/null special case: a deletion header names /dev/null, whose
        # leading slash the prefix strip above does not touch, and which does
        # not end in .rs either way. The conjunct that used to be here was
        # unreachable — and an unreachable check is worse than none, because a
        # case can be written that appears to cover it.
        cur = p if p.endswith(".rs") else None
        if cur:
            paths.append(cur)
    elif cur and line.startswith("+") and is_skip_attr(line[1:]):
        adds_skip.add(cur)

for p in paths:
    print("path\t" + p)

for path in sorted(adds_skip):
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue  # reported by the path check above
    for i, l in enumerate(lines):
        if not is_skip_attr(l):
            continue
        above = [x.strip() for x in lines[max(0, i - 3):i]]
        if not any(x.startswith("//") for x in above):
            print("skip\t%s:%d: %s" % (path, i + 1, l.strip()))
' "$f"); then
    die "could not read the --in-diff file '$f'. The gate cannot confirm its
  paths resolve, nor that the PR did not exempt itself with #[mutants::skip], so
  it will not pass."
  fi

  local kind value
  local -a offenders=()
  while IFS=$'\t' read -r kind value; do
    case "$kind" in
      path)
        [[ -f $value ]] || die "--in-diff names a path that does not exist relative
  to $(pwd): '$value'. The diff's paths do not resolve against the workspace, so
  cargo-mutants would match nothing and exit 0 — a green gate that scored
  nothing. Check --relative and the step's working-directory."
        ;;
      skip) offenders+=("$value") ;;
    esac
  done <<<"$report"

  if [[ ${#offenders[@]} -gt 0 ]]; then
    printf '  %s\n' "${offenders[@]}" >&2
    die "this diff adds a #[mutants::skip] with no comment above it (see above).
  A skip is invisible to every other check here — the skipped function drops out
  of the expectation AND the scored set together — so it is the one exemption an
  author can grant themselves inside the diff being scored. Put the reason on the
  line above it, per ADR-020 §4."
  fi
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
#
# All four spellings clap accepts for the same option are recognised, and the
# LAST one wins, as it does in clap — so what `check_diff` inspects is the file
# the run will actually use.
want_diff_file=0
for arg in "$@"; do
  if [[ $want_diff_file -eq 1 ]]; then
    diff_file="$arg"
    want_diff_file=0
    continue
  fi
  case "$arg" in
    --in-diff | -D) want_diff_file=1 ;;
    --in-diff=*) diff_file="${arg#*=}" ;;
    -D?*) diff_file="${arg#-D}" ;;
    --list | --list-files)
      die "'$arg' produces no mutation score; the gate cannot run against it"
      ;;
  esac
done
[[ $want_diff_file -eq 0 ]] || die "--in-diff given with no file argument"

[[ -n $diff_file ]] && check_diff "$diff_file"

# A killed --in-place run leaves mutated source behind. Warn if the tree is
# already dirty so a developer cannot mistake cargo-mutants' residue for their
# own edits (CI checkouts are always clean, so this is silent there).
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1 \
  && ! git diff --quiet; then
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
#
# `nice`d, and under a SIGTERM-sending timeout, because `--in-place` MUTATES THE
# WORKING TREE: a SIGKILL between "write the mutant" and "restore the file"
# leaves `~ changed by cargo-mutants ~` in the source. cargo-mutants restores on
# SIGTERM; an agent harness or CI step timeout sends SIGKILL. So the inner
# timeout must fire FIRST, which is what makes the kill graceful.
#
# It is also a whole-machine workload — every mutant is a full rustc build plus
# the entire test suite — so it yields to anything interactive. On a dedicated
# CI runner nothing competes and `nice` costs nothing.
# A POSITIVE integer, validated: GNU `timeout 0` means NO timeout, so
# `:-3600 -> :-0` silently removed the containment while every check still
# passed. The default must also be below the CI job cap, or the inner timeout
# provably cannot fire first and the whole SIGTERM-before-SIGKILL argument is
# unreachable in the one path where it matters.
timeout_secs="${MUTATION_GATE_TIMEOUT:-600}"
[[ $timeout_secs =~ ^[1-9][0-9]*$ ]] || die "MUTATION_GATE_TIMEOUT must be a positive
  integer of seconds, got '$timeout_secs'. Zero means NO timeout to timeout(1), which
  removes the containment that keeps a killed --in-place run from leaving mutated
  source behind."
set +e
kill_grace="${MUTATION_GATE_KILL_GRACE:-60}"
[[ $kill_grace =~ ^[1-9][0-9]*$ ]] || die "MUTATION_GATE_KILL_GRACE must be a positive
  integer of seconds, got '$kill_grace'."
nice -n 19 timeout --signal=TERM --kill-after="${kill_grace}s" "$timeout_secs" \
  cargo mutants --output . "$@"
cargo_status=$?
set -e

if [[ $cargo_status -eq 124 ]]; then
  die "cargo-mutants hit the ${timeout_secs}s gate timeout and was terminated.
  Raise MUTATION_GATE_TIMEOUT if the scope legitimately needs longer, or narrow
  the scope. A timed-out run is not a pass."
fi

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
#
# `baseline` is the THIRD thing read from this file, and it closes the last
# demonstrated way to render "nothing ran" as "nothing survived":
#
#   $ mutation-gate.sh enforce --baseline skip     # with a test suite that fails
#   mutation gate (enforce): PASS — every mutant was caught.
#
# A test command that always fails marks every mutant killed. end_time is set,
# planned == total, the sets match, accounting balances, unviable is 0 — every
# other check in this script passes on a tree where NO test passes. The
# discriminator was already in the file being parsed: a normal run records a
# `"Baseline"` scenario with summary `Success`, and `--baseline skip` records no
# Baseline entry at all. Both verified against cargo-mutants 27.1.0.
readonly NO_FILE=-1 UNPARSEABLE=-2 NOT_A_LIST=-3
if ! read -r total missed caught timeout unviable finished planned baseline < <(
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
runs = [o for o in d.get("outcomes", []) if o.get("scenario") == "Baseline"]
baseline = "missing" if not runs else str(runs[0].get("summary"))
print(
    d["total_mutants"], d["missed"], d["caught"], d["timeout"], d["unviable"],
    0 if d.get("end_time") is None else 1, planned, baseline,
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

case $baseline in
  Success) ;;
  missing) die "this run established no baseline (no \"Baseline\" scenario in
  $outcomes), so 'caught' means nothing: with --baseline skip and a test command
  that fails for its own reasons, EVERY mutant is recorded as caught and every
  other check here passes. Drop --baseline skip." ;;
  *) die "the unmutated baseline did not pass (summary: $baseline). Every verdict
  after that describes a tree whose tests were already broken. Fix the suite
  first; a mutation score against a red baseline is not a score." ;;
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

# No length guard here: the python above either exits non-zero — caught by the
# `if !` — or prints both counts, so `${verdict[0]}` cannot be unbound. A guard
# was added and removed again; it read as defence but was unreachable, and an
# unreachable check is worse than none, because a case can be written that
# appears to cover it.
mapfile -t verdict <<<"$set_diff"
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
# Order matters, and it was wrong: `2>/dev/null >&2` sends stderr to /dev/null
# FIRST, then points stdout at the now-null stderr — so the list was discarded
# every time, and the failure below has always said "see the list above" with
# nothing above it. Redirect stdout to stderr first, then silence cat's own
# complaints about a missing file.
cat "$OUT_DIR/missed.txt" "$OUT_DIR/timeout.txt" >&2 2>/dev/null || true

if [[ $mode == advisory ]]; then
  echo "::warning::${survivors} surviving mutant(s) — $summary"
  step_summary "**WARN** — ${survivors} surviving mutant(s); $summary"
  exit 0
fi

die "${survivors} of ${total} mutant(s) survived (see the list above).
  Add a test that kills them, or annotate a genuinely unobservable mutant with
  #[mutants::skip] AND a comment saying why."
