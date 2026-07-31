#!/usr/bin/env bash
# scripts/mutation-gate-selftest.sh — score the mutation gate against its own
# bats suite.
#
# ADR-020 §2 says the number to report when changing `scripts/mutation-gate.sh`
# is its OWN mutation score, not its case count. This is the tool that produces
# that number, so the procedure is reviewable instead of being re-invented in a
# shell loop each time. It was re-invented three times, and the third helped
# exhaust a host badly enough that sshd could accept TCP but never fork.
#
# For each mutation in the table below: apply a single edit to the gate, run the
# gate's bats suite, record whether the suite noticed. A mutation the suite does
# not notice is a hole — a decision the gate makes that nothing asserts.
#
# EVERY DESIGN CHOICE HERE IS ABOUT NOT LYING ABOUT THE SCORE. A first revision
# of this script had four separate paths that inflated it toward a false
# perfect, which is a worse failure than having no tool: a fabricated 57/57 is
# quoted in a PR and believed.
#
#   * the record reader is literal and delimiter-checked, so a mutation cannot
#     silently fail to be scored (the first version dropped its LAST record
#     entirely, and three more to backslash-escaping bugs, while printing a
#     confident total);
#   * `NOT APPLIED` counts against the total and fails the run, so drift in a
#     pattern shrinks the score instead of the denominator;
#   * only a suite exit of 1 — bats' "a test failed" — counts as killed.
#     Anything else (timeout, OOM, bats missing, a fork failure under host
#     pressure) ABORTS, because those are the likely failure modes of this very
#     loop and every one of them would otherwise read as "killed";
#   * the baseline runs in the SAME configuration as the scored runs, and again
#     at the end, so an environment that goes red mid-loop cannot turn the
#     remaining mutations into free kills.
#
# Resource discipline, because this is ~60 full suite runs:
#   * `nice -n 5` — enough to yield, and deliberately BELOW the `nice -n 19` the
#     gate applies to its own child, because MUT-43 asserts the gate nices
#     strictly below its parent. Nicing this driver to 19 made that assertion
#     vacuous (the stub inherited 19 and passed either way) and the mutation
#     survived its own test.
#   * one suite at a time, each under `timeout`.
#   * `AGENTLINUX_GATE_SUITE_SKIP_TOOL` so MUT-14/MUT-20 do not invoke the REAL
#     cargo-mutants ~60 times. Nothing in the loop touches cargo-mutants, so its
#     contract cannot change between iterations — but it IS checked once,
#     unguarded, before the loop.
#
# Usage:
#   scripts/mutation-gate-selftest.sh            # score every mutation
#   scripts/mutation-gate-selftest.sh -k skips   # only labels containing "skips"
#
# Exit: 0 all mutations killed · 1 survivors or drift · 2 aborted (score unknown)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly GATE="scripts/mutation-gate.sh"
readonly SUITE="tests/bats/80-mutation-gate.bats"
readonly PRISTINE=".mutation-gate-selftest-pristine"
readonly LOCKDIR=".mutation-gate-selftest-lock"
# Generous: the suite is ~15s, so this only fires on a genuine hang.
readonly RUN_TIMEOUT="${SELFTEST_RUN_TIMEOUT:-300}"
# Below the gate's own `nice -n 19`. See the header.
readonly SELFTEST_NICE=5

# Exit 2, never 1: a caller must be able to tell "the gate has holes" from "this
# never produced a number".
abort() {
  echo "SELFTEST ABORTED: $*" >&2
  exit 2
}

[[ ${RUN_TIMEOUT} =~ ^[0-9]+$ ]] || abort "SELFTEST_RUN_TIMEOUT must be an integer, got '$RUN_TIMEOUT'"
[[ -f $GATE && -f $SUITE ]] || abort "run this from the repo root (or via its own path)"
command -v bats >/dev/null || abort "bats is not on PATH"
command -v python3 >/dev/null || abort "python3 is not on PATH"

# The loop cannot work under CI: it sets AGENTLINUX_GATE_SUITE_SKIP_TOOL, which
# the suite REFUSES under $CI (an env var that disables the only two cases
# holding the cargo-mutants contract must not be usable where that contract
# matters). Refused explicitly — otherwise every scored run is red for that
# reason alone and every mutation is reported killed: a fabricated perfect score.
[[ -z ${CI:-} ]] || abort "this is a local tool; under CI every run would be red for
  the wrong reason and every mutation would read as killed."

filter=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -k)
      [[ $# -ge 2 ]] || abort "-k needs a label substring"
      filter="$2"
      [[ -n $filter ]] || abort "-k needs a non-empty label substring"
      shift 2
      ;;
    *) abort "usage: $0 [-k <label-substring>]" ;;
  esac
done

# One run at a time. Two concurrent runs corrupt the tracked file outright: the
# second sees the first's pristine, "recovers" over the first's in-flight
# mutation, deletes the pristine, then captures a NEW pristine from whatever the
# first has since written — after which both restore a mutant.
mkdir "$LOCKDIR" 2>/dev/null || abort "another selftest is running (or $LOCKDIR is
  stale after a kill -9 — remove it if no process holds it)."

# Recovery from a SIGKILL, which runs no trap. The pristine sits at a FIXED,
# gitignored path so the next invocation can find it — but it is verified before
# use, not trusted: a kill landing inside the non-atomic write below can leave a
# truncated copy, and restoring THAT over the tracked file would be worse than
# leaving the mutant in place.
if [[ -f $PRISTINE ]]; then
  if [[ -f "$PRISTINE.sha256" ]] && sha256sum -c --status "$PRISTINE.sha256" 2>/dev/null; then
    echo "recovering: a previous run was killed without restoring $GATE."
    cp "$PRISTINE" "$GATE"
    rm -f "$PRISTINE" "$PRISTINE.sha256"
  else
    rmdir "$LOCKDIR"
    abort "$PRISTINE exists but does not match its checksum — it may itself be a
  mutant or a truncated copy. Refusing to restore from it. Recover the gate with
  'git checkout -- $GATE' (or your own edits) and delete $PRISTINE."
  fi
fi

cp "$GATE" "$PRISTINE"
sha256sum "$PRISTINE" >"$PRISTINE.sha256"

# Idempotent, and it does NOT delete its own input — the first version did, so a
# Ctrl-C (whose handler returns to the loop rather than exiting) restored once,
# removed the pristine, and then failed on the next iteration's restore, leaving
# the tracked gate mutated with recovery disarmed. Ctrl-C now exits.
restore() {
  [[ -f $PRISTINE ]] && cp "$PRISTINE" "$GATE"
  return 0
}
# shellcheck disable=SC2317  # invoked only via trap
cleanup() {
  restore
  rm -f "$PRISTINE" "$PRISTINE.sha256"
  rmdir "$LOCKDIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Run the suite once. Echoes the verdict; aborts on anything that is not bats
# reporting a result.
#   0 -> suite green   1 -> a test failed   anything else -> could not run
run_suite() {
  local rc=0
  nice -n "$SELFTEST_NICE" timeout "$RUN_TIMEOUT" bats "$SUITE" >"$log" 2>&1 || rc=$?
  case $rc in
    0) echo green ;;
    1) echo red ;;
    124) abort "the suite hit the ${RUN_TIMEOUT}s timeout. Not scoring: a timeout
  is indistinguishable from a kill, and both would otherwise read as 'killed'." ;;
    *) abort "bats exited $rc — it did not run to a verdict (OOM, signal, or a
  broken invocation). Not scoring; see $log." ;;
  esac
}

log="$(mktemp)"
trap 'cleanup; rm -f "$log"' EXIT

# The control must match the experiment: the scored runs all set
# AGENTLINUX_GATE_SUITE_SKIP_TOOL, so the baseline must too. The first version
# baselined WITHOUT it and scored WITH it, which under $CI made every scored run
# red for an unrelated reason and reported a perfect score.
echo "checking the cargo-mutants contract once (MUT-14/MUT-20, unguarded)…"
[[ $(run_suite) == green ]] || abort "the suite is not green before any mutation.
  Every 'killed' verdict below would be meaningless. See $log."

export AGENTLINUX_GATE_SUITE_SKIP_TOOL=1
echo "baseline in the scored configuration…"
[[ $(run_suite) == green ]] || abort "the suite is not green with
  AGENTLINUX_GATE_SUITE_SKIP_TOOL set. See $log."

killed=0
survived=0
drifted=0
survivors=()
drift=()

score_one() {
  local label="$1" old="$2" new="$3"
  if ! MUT_OLD="$old" MUT_NEW="$new" python3 -c '
import os, sys
p = sys.argv[1]
s = open(p).read()
old, new = os.environ["MUT_OLD"], os.environ["MUT_NEW"]
if s.count(old) != 1:
    sys.exit(3)
open(p, "w").write(s.replace(old, new))
' "$GATE"; then
    # The pattern no longer matches exactly one site — it drifted as the gate was
    # edited. Counted, not skipped: excluding it would shrink the denominator and
    # let coverage fall while the printed score stayed perfect.
    drifted=$((drifted + 1))
    drift+=("$label")
    echo "  DRIFTED      $label (pattern matches 0 or >1 sites — update it)"
    restore
    return 0
  fi

  if [[ $(run_suite) == green ]]; then
    survived=$((survived + 1))
    survivors+=("$label")
    echo "  SURVIVED     $label"
  else
    killed=$((killed + 1))
    echo "  killed       $label"
  fi
  restore
}

# ---------------------------------------------------------------------------
# The mutation table.
#
# Written against the SCRIPT — function by function, line by line — and NOT
# against the case list. A list derived from the tests only re-confirms what is
# already covered: an earlier revision scored 32/32 on the author's own list and
# 27/56 on a reviewer's, and every one of those survivors was in a function the
# author's list had not touched. When adding here, read the gate and ask what
# each line decides; do not read the bats file.
#
# Format, deliberately literal — no backslash escaping anywhere:
#
#   <label>
#   @@
#   <text to replace, may span lines>
#   @@
#   <replacement, may span lines>
#   %%
#
# The first version used printf %b and four-line records, which cost three
# mutations to mangled escapes and silently dropped the final record for want of
# a trailing blank line. Both failures were invisible in the output.
# ---------------------------------------------------------------------------
parse_table() {
  python3 -c '
import sys

raw = sys.stdin.read()
records = [r for r in raw.split("\n%%\n") if r.strip()]
out = []
for i, rec in enumerate(records):
    parts = rec.split("\n@@\n")
    if len(parts) != 3:
        sys.stderr.write(
            "malformed record %d (want <label> @@ <old> @@ <new>), starts: %r\n"
            % (i + 1, rec.strip()[:60])
        )
        sys.exit(3)
    label, old, new = parts
    if "\n" in label.strip("\n"):
        sys.stderr.write("record %d: label spans lines: %r\n" % (i + 1, label))
        sys.exit(3)
    out.extend([label.strip("\n"), old.strip("\n"), new.strip("\n")])
sys.stdout.write("\0".join(out) + "\0")
'
}

table="$(mktemp)"
trap 'cleanup; rm -f "$log" "$table"' EXIT

parse_table >"$table" <<'TABLE'
baseline: accept a missing one
@@
case $baseline in
  Success) ;;
@@
case $baseline in
  Success | missing) ;;
%%
baseline: accept a failed one
@@
case $baseline in
  Success) ;;
@@
case $baseline in
  *) ;;
%%
expectation: drop --no-config
@@
list_args=(--no-config --list)
@@
list_args=(--list)
%%
expectation: drop --in-diff from the query
@@
[[ -n $diff_file ]] && list_args+=(--in-diff "$diff_file")
@@
: # dropped
%%
expectation: a failed query is not fatal
@@
if ! cargo mutants "${list_args[@]}" >"$expected_file" 2>"$list_err"; then
@@
if false; then
%%
expectation: zero expected skips
@@
if [[ $expected -eq 0 ]]; then
@@
if false; then
%%
run: stop forwarding the caller's argv
@@
  cargo mutants --output . "$@"
@@
  cargo mutants --output .
%%
run: stop clearing stale results
@@
rm -rf "$OUT_DIR"
@@
: # kept
%%
run: drop the nice
@@
nice -n 19 timeout --signal=TERM
@@
timeout --signal=TERM
%%
run: drop the timeout
@@
nice -n 19 timeout --signal=TERM --kill-after=60s "$timeout_secs" \
  cargo mutants --output . "$@"
@@
nice -n 19 cargo mutants --output . "$@"
%%
run: a timed-out run is not a failure
@@
if [[ $cargo_status -eq 124 ]]; then
@@
if false; then
%%
completeness: ignore end_time
@@
if [[ $finished -eq 0 ]]; then
@@
if false; then
%%
completeness: end_time checked in enforce only
@@
if [[ $finished -eq 0 ]]; then
@@
if [[ $finished -eq 0 && $mode == enforce ]]; then
%%
completeness: ignore planned != total
@@
if [[ $planned -ne $total ]]; then
@@
if false; then
%%
completeness: planned -ne -> -gt
@@
if [[ $planned -ne $total ]]; then
@@
if [[ $planned -gt $total ]]; then
%%
sentinel: NO_FILE is a warning, not fatal
@@
  "$NO_FILE") die "cargo-mutants left no
@@
  "$NO_FILE") echo "note: no mutants.json" >&2 ;;
  "__never__") die "cargo-mutants left no
%%
sets: ignore unexpected mutants
@@
if [[ $unexpected_n -gt 0 ]]; then
@@
if false; then
%%
sets: unexpected boundary -gt 0 -> -gt 1
@@
if [[ $unexpected_n -gt 0 ]]; then
@@
if [[ $unexpected_n -gt 1 ]]; then
%%
sets: ignore unscored mutants
@@
if [[ $unscored_n -gt 0 ]]; then
@@
if false; then
%%
sets: unscored boundary -gt 0 -> -gt 1
@@
if [[ $unscored_n -gt 0 ]]; then
@@
if [[ $unscored_n -gt 1 ]]; then
%%
sets: enforce tolerates a subset
@@
  if [[ $mode == enforce ]]; then
@@
  if false; then
%%
sets: advisory reports full coverage
@@
    partial=" — $total of $expected in scope ($unscored_n not in this slice)"
@@
    partial=""
%%
accounting: drop the identity
@@
if [[ $accounted -ne $total ]]; then
@@
if false; then
%%
zero: a zero-mutant run passes
@@
if [[ $total -eq 0 ]]; then
@@
if false; then
%%
zero: an all-unviable run passes
@@
if [[ $viable -le 0 ]]; then
@@
if false; then
%%
zero: viable boundary -le 0 -> -le 1
@@
if [[ $viable -le 0 ]]; then
@@
if [[ $viable -le 1 ]]; then
%%
survivors: timeouts do not count
@@
survivors=$((missed + timeout))
@@
survivors=$((missed))
%%
survivors: enforce warns instead of failing
@@
if [[ $mode == advisory ]]; then
  echo "::warning::
@@
if true; then
  echo "::warning::
%%
report: always claim a full sweep
@@
  if [[ -n $partial ]]; then
@@
  if false; then
%%
report: PARTIAL PASS rendered as PASS
@@
    step_summary "PARTIAL PASS — every mutant in this slice was caught; $summary"
@@
    step_summary "PASS — $summary"
%%
summary: emit no verdict on failure
@@
  step_summary "**FAIL** — ${1%%$'\n'*}"
@@
  : # no summary
%%
summary: skip path emits no verdict
@@
  step_summary "SKIPPED (no mutants in scope)"
@@
  : # no summary
%%
summary: empty-diff path emits no verdict
@@
    step_summary "SKIPPED (empty diff)"
@@
    : # no summary
%%
args: usage check
@@
[[ $# -ge 1 ]] || die "usage
@@
true || die "usage
%%
args: unknown mode accepted
@@
  *) die "unknown mode
@@
  __never__) die "unknown mode
%%
args: accept a listing flag
@@
    --list | --list-files)
@@
    --never-matches-anything)
%%
args: drop the -D (space) spelling
@@
    --in-diff | -D) want_diff_file=1 ;;
@@
    --in-diff) want_diff_file=1 ;;
%%
args: drop the --in-diff=F spelling
@@
    --in-diff=*) diff_file="${arg#*=}" ;;
@@
    --in-diff=*) : ;;
%%
args: drop the -DF spelling
@@
    -D?*) diff_file="${arg#-D}" ;;
@@
    -D?*) : ;;
%%
args: first --in-diff wins instead of last
@@
    diff_file="$arg"
    want_diff_file=0
@@
    [[ -z $diff_file ]] && diff_file="$arg"
    want_diff_file=0
%%
args: dangling --in-diff is tolerated
@@
[[ $want_diff_file -eq 0 ]] || die "--in-diff given with no file argument"
@@
: # tolerated
%%
diff: skip the parses-as-a-diff check
@@
  grep -qE '^(diff --git |--- |\+\+\+ )' "$f" ||
@@
  true ||
%%
diff: skip the quotePath refusal
@@
  if grep -qE '^\+\+\+ ".*\\[0-7]{3}' "$f"; then
@@
  if false; then
%%
diff: quotePath anchored on --- instead of +++
@@
'^\+\+\+ ".*\\[0-7]{3}'
@@
'^--- ".*\\[0-7]{3}'
%%
diff: skip the path-resolution check
@@
        [[ -f $value ]] || die "--in-diff names a path
@@
        true || die "--in-diff names a path
%%
diff: only the first path is checked
@@
for p in paths:
    print("path\t" + p)
@@
for p in paths[:1]:
    print("path\t" + p)
%%
diff: split on whitespace, not tab
@@
line[4:].split("\t")[0]
@@
line[4:].split()[0]
%%
diff: drop the one-letter prefix strip
@@
re.sub(r"^[a-z]/", "", line[4:]
@@
re.sub(r"^$^", "", line[4:]
%%
skips: ignore added skips entirely
@@
  if [[ ${#offenders[@]} -gt 0 ]]; then
@@
  if false; then
%%
skips: check only the diff, not the file
@@
        if not is_skip_attr(l):
            continue
@@
        if True:
            continue
%%
skips: drop the cur guard
@@
    elif cur and line.startswith("+") and is_skip_attr(line[1:]):
@@
    elif line.startswith("+") and is_skip_attr(line[1:]):
%%
skips: drop the attribute requirement
@@
    return n.startswith("#[") and "mutants::skip" in n
@@
    return "mutants::skip" in n
%%
skips: drop the block-comment normalisation
@@
    n = re.sub(r"\s+", "", re.sub(r"/\*.*?\*/", "", line))
@@
    n = re.sub(r"\s+", "", line)
%%
skips: drop the whitespace normalisation
@@
    n = re.sub(r"\s+", "", re.sub(r"/\*.*?\*/", "", line))
@@
    n = re.sub(r"/\*.*?\*/", "", line)
%%
skips: widen the comment window to the file
@@
lines[max(0, i - 3):i]
@@
lines[0:i]
%%
skips: window i-3 -> i-1
@@
lines[max(0, i - 3):i]
@@
lines[max(0, i - 1):i]
%%
skips: window i-3 -> i-4
@@
lines[max(0, i - 3):i]
@@
lines[max(0, i - 4):i]
%%
skips: drop the strip before the comment test
@@
        above = [x.strip() for x in lines[max(0, i - 3):i]]
@@
        above = [x for x in lines[max(0, i - 3):i]]
%%
skips: any line containing a comment marker licenses
@@
        if not any(x.startswith("//") for x in above):
@@
        if not any("//" in x for x in above):
%%
TABLE

# NUL-delimited so a pattern can contain anything at all.
requested=0
while IFS= read -r -d '' label && IFS= read -r -d '' old && IFS= read -r -d '' new; do
  requested=$((requested + 1))
  [[ -z $filter || $label == *"$filter"* ]] || continue
  score_one "$label" "$old" "$new"
done <"$table"

scored=$((killed + survived))
total=$((scored + drifted))

echo
if [[ -n $filter ]]; then
  echo "gate mutation score (FILTERED by '$filter'): ${killed}/${total} — not the full score"
else
  echo "gate mutation score: ${killed}/${total}   (table has $requested mutations)"
fi

if [[ $total -eq 0 ]]; then
  abort "nothing was scored. A score of 0/0 is not a pass."
fi

rc=0
if [[ ${#survivors[@]} -gt 0 ]]; then
  echo "SURVIVORS — each is a decision the gate makes that nothing asserts:"
  printf '  %s\n' "${survivors[@]}"
  rc=1
fi
if [[ ${#drift[@]} -gt 0 ]]; then
  echo "DRIFTED — these no longer match the gate, so they tested nothing:"
  printf '  %s\n' "${drift[@]}"
  rc=1
fi
exit $rc
