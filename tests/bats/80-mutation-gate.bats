#!/usr/bin/env bats
# tests/bats/80-mutation-gate.bats — the mutation gate's own verdict logic.
#
# The gate exists because the previous inline version could not fail: it ran
# `cargo mutants --in-place --jobs 4`, a flag pair cargo-mutants rejects, and
# `|| echo "::warning::"` plus `continue-on-error: true` reported a mutation
# score for a run that generated zero mutants. Testing the replacement matters
# more than usual — an untested gate is exactly what was wrong before.
#
# `cargo mutants` is stubbed on PATH so each case pins ONE decision: what the
# script concludes from a given results file. The stub writes the
# `mutants.out/outcomes.json` a real run would leave behind, so these assert the
# contract the script actually reads, not a reimplementation of it.

setup() {
  GATE="${BATS_TEST_DIRNAME}/../../scripts/mutation-gate.sh"
  WORK="$(mktemp -d)"
  BIN="$WORK/bin"
  mkdir -p "$BIN"
  cd "$WORK" || return 1
  PATH="$BIN:$PATH"
  export PATH
}

teardown() {
  cd / || true
  rm -rf "$WORK"
}

# Every stub records the argv of every `cargo` invocation to $WORK/argv.log, so
# a case can assert what the gate ASKED FOR and not only what it concluded. The
# absence of that recording is why "MUT-09: a non-empty diff is actually
# forwarded" passed with `"$@"` deleted from the run.
cargo_argv_log() { cat "$WORK/argv.log"; }

# Emit a `cargo` stub. All shape is passed by name so a case says what it means:
#
#   list_n        lines `--list` prints (the gate's EXPECTATION)
#   list_cfg_n    lines `--list` prints when --no-config is ABSENT — i.e. what a
#                 .cargo/mutants.toml would leave. Defaults to list_n.
#   total/missed/caught/timeout/unviable   the outcomes.json counters
#   planned       entries in mutants.json. Defaults to total.
#   end_time      "null" (an interrupted run) or a timestamp. Defaults to a stamp.
#   extra         one mutant NAME to add to mutants.json that `--list` never
#                 offered — the `--error VALUE` shape, which ADDS a mutant per
#                 Result-returning fn
#   baseline      present | missing | failed
#   exit          the stub's exit code
#
# `baseline` is not decoration: a real run records a `"Baseline"` scenario with
# summary `Success`, and `--baseline skip` records none. With a test command that
# fails for its own reasons, EVERY mutant is then marked caught and every other
# check in the gate passes — so a stub that omitted the Baseline entry would have
# modelled the gate's blind spot rather than the tool.
mk_cargo() {
  local list_n=0 list_cfg_n="" total=0 missed=0 caught=0 timeout=0 unviable=0
  local planned="" end_time='"2026-07-31T00:00:00Z"' baseline=present exit_code=0
  local extra=""
  local kv
  for kv in "$@"; do
    case "$kv" in
      list_n=*) list_n="${kv#*=}" ;;
      list_cfg_n=*) list_cfg_n="${kv#*=}" ;;
      total=*) total="${kv#*=}" ;;
      missed=*) missed="${kv#*=}" ;;
      caught=*) caught="${kv#*=}" ;;
      timeout=*) timeout="${kv#*=}" ;;
      unviable=*) unviable="${kv#*=}" ;;
      planned=*) planned="${kv#*=}" ;;
      end_time=*) end_time="${kv#*=}" ;;
      baseline=*) baseline="${kv#*=}" ;;
      extra=*) extra="${kv#*=}" ;;
      exit=*) exit_code="${kv#*=}" ;;
      *)
        echo "mk_cargo: unknown key '$kv'" >&2
        return 1
        ;;
    esac
  done
  [ -n "$list_cfg_n" ] || list_cfg_n="$list_n"
  [ -n "$planned" ] || planned="$total"
  # The stub writes outcomes.json from a Python literal, so JSON's null is None.
  [ "$end_time" = null ] && end_time=None

  cat >"$BIN/cargo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$WORK/argv.log"

# The gate asks the tool what this scope SHOULD contain before running anything.
# --no-config makes that the HONEST expectation: what the scope contains, not
# what a .cargo/mutants.toml left behind. This stub answers differently for the
# two so a gate that dropped --no-config is visible.
listing=0
noconfig=0
for a in "\$@"; do
  [ "\$a" = "--list" ] && listing=1
  [ "\$a" = "--no-config" ] && noconfig=1
done
if [ "\$listing" = 1 ]; then
  n=$list_cfg_n
  [ "\$noconfig" = 1 ] && n=$list_n
  for i in \$(seq 1 "\$n"); do echo "src/x.rs:\$i:1: replace a with b"; done
  exit 0
fi

mkdir -p mutants.out
python3 - <<'PY'
import json
scored = [
    {"name": "src/x.rs:%d:1: replace a with b" % i} for i in range(1, $planned + 1)
]
if "$extra":
    scored.append({"name": "$extra"})
json.dump(scored, open("mutants.out/mutants.json", "w"))
outcomes = [{"scenario": {"Mutant": m}, "summary": "CaughtMutant"} for m in scored]
baseline = "$baseline"
if baseline != "missing":
    summary = "Success" if baseline == "present" else "Failure"
    outcomes.insert(0, {"scenario": "Baseline", "summary": summary})
json.dump(
    {
        "cargo_mutants_version": "27.1.0",
        "total_mutants": $total,
        "missed": $missed,
        "caught": $caught,
        "timeout": $timeout,
        "unviable": $unviable,
        "end_time": $end_time,
        "outcomes": outcomes,
    },
    open("mutants.out/outcomes.json", "w"),
)
PY
printf 'crates/x.rs:1:1: replace a with b\n' >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit $exit_code
EOF
  chmod +x "$BIN/cargo"
}

# Stub `cargo` so `cargo mutants …` leaves the outcomes file a real run leaves.
# $1 total, $2 missed, $3 caught, $4 timeout, $5 exit code, [$6 unviable]
stub_cargo_outcomes() {
  mk_cargo "list_n=$1" "total=$1" "missed=$2" "caught=$3" "timeout=$4" \
    "unviable=${6:-0}" "exit=$5"
}

# A run KILLED partway: cargo-mutants rewrites outcomes.json after every
# scenario, so the file is well-formed and describes only what it reached — but
# end_time is null AND mutants.json still lists the full planned set.
# $1 reached, $2 planned, $3 exit code
#
# Both halves matter and the fixture used to write only the first: it sized
# mutants.json by `reached`, so `planned == total` held and the second of the
# gate's "two independent completeness checks" was exercised by nothing.
stub_cargo_interrupted() {
  mk_cargo "list_n=$2" "total=$1" "caught=$1" "planned=$2" end_time=null "exit=$3"
}

# A run that exits 0 writing NO outcomes.json — the shape cargo-mutants really
# produces when a filter matches nothing (a non-resolving --in-diff, an empty
# --shard, --file matching nothing, --list). MUT-05's stub writes an
# outcomes.json with total_mutants:0, which the real tool never does.
stub_cargo_zero_mutants() {
  cat >"$BIN/cargo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$WORK/argv.log"
# --list prints nothing: the scope genuinely contains no mutants.
for a in "\$@"; do
  if [ "\$a" = "--list" ]; then exit 0; fi
done
echo " INFO No mutants to filter"
exit 0
EOF
  chmod +x "$BIN/cargo"
}

# Stub `cargo` so it fails WITHOUT producing outcomes — the real failure mode:
# a rejected flag combination.
stub_cargo_rejects_flags() {
  cat >"$BIN/cargo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$WORK/argv.log"
for a in "\$@"; do
  if [ "\$a" = "--list" ]; then
    echo "src/x.rs:1:1: replace a with b"
    exit 0
  fi
done
echo "error: the argument '--in-place' cannot be used with '--jobs <JOBS>'" >&2
exit 1
EOF
  chmod +x "$BIN/cargo"
}

# The two cases below invoke the REAL cargo-mutants. That is the point of them —
# every other case stubs `cargo`, so together they pin the gate against a schema
# this repo wrote, and these are what notice when the tool drifts.
#
# It is also what makes running this suite in a loop expensive. The gate's own
# mutation score (ADR-020 section 2) is produced by re-running the whole suite once
# per mutation, ~60 times; at two real tool invocations each that is ~120
# rustc-driving runs of a contract that cannot change between iterations, because
# nothing in the loop touches cargo-mutants. Running them once and skipping them
# for the rest of the loop costs no coverage.
#
# The opt-out is REFUSED under $CI. An env var that silently disables the only
# two cases holding the tool contract would be precisely the bypass this whole
# gate exists to prevent — the same shape as the `|| echo "::warning::"` it
# replaced. Locally it is a speed knob; in CI it is an error.
requires_real_cargo_mutants() {
  if [ -n "${AGENTLINUX_GATE_SUITE_SKIP_TOOL:-}" ]; then
    if [ -n "${CI:-}" ]; then
      echo "AGENTLINUX_GATE_SUITE_SKIP_TOOL is set in CI. It disables the only two" >&2
      echo "cases that pin the cargo-mutants contract; CI is where that must hold." >&2
      return 1
    fi
    skip "AGENTLINUX_GATE_SUITE_SKIP_TOOL set (real-tool cases run once, not per mutation)"
  fi
  if ! command -v cargo >/dev/null || ! cargo mutants --version >/dev/null 2>&1; then
    if [ -n "${CI:-}" ]; then
      echo "cargo-mutants must be installed in CI — the gate's contract is untested without it" >&2
      return 1
    fi
    skip "cargo-mutants not installed (required in CI, optional locally)"
  fi
}

@test "MUT-01: a clean run passes in both modes" {
  stub_cargo_outcomes 40 0 40 0 0
  run "$GATE" enforce
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]

  run "$GATE" advisory
  [ "$status" -eq 0 ]
}

@test "MUT-02: a surviving mutant FAILS the enforcing gate" {
  stub_cargo_outcomes 40 3 37 0 2
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"3 of 40 mutant(s) survived"* ]]
}

@test "MUT-03: a surviving mutant only WARNS in advisory mode" {
  stub_cargo_outcomes 40 3 37 0 2
  run "$GATE" advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::"* ]]
  [[ "$output" == *"3 surviving mutant"* ]]
}

@test "MUT-04: a run that never happened FAILS even in advisory mode" {
  # The regression this whole script exists for. cargo-mutants rejected the
  # flags, so there is no outcomes.json. The old gate printed
  # '::warning::surviving mutants' here and went green.
  stub_cargo_rejects_flags
  run "$GATE" advisory
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete a run"* ]]
  [[ "$output" != *"::warning::"* ]]

  run "$GATE" enforce
  [ "$status" -ne 0 ]
}

@test "MUT-05: scoring fewer mutants than the scope contains is never a pass" {
  # The gate asks cargo-mutants what this scope SHOULD contain and compares. A
  # run that scored a SUBSET — because a filter flag, a --shard, or an
  # exclude_globs in .cargo/mutants.toml narrowed it — is not a pass even when
  # every mutant it did score was caught. That shape printed
  # "PASS — every mutant was caught" on a diff with survivors.
  mk_cargo list_n=10 total=5 caught=5
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"never scored"* ]]
  # The message must NAME the unscored mutants, not just count them — a bare
  # count leaves the reader unable to tell which part of the change went
  # unmeasured.
  [[ "$output" == *"unscored: src/x.rs"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-05c: scoring a mutant the scope does not contain fails too" {
  # `--error VALUE` (and error_values in .cargo/mutants.toml) ADDS a mutant per
  # Result-returning fn. Comparing sizes let one knob hide the survivors and a
  # second refill the count — "PASS — every mutant was caught", no argv evidence.
  mk_cargo list_n=3 total=3 caught=3 planned=2 "extra=src/OTHER.rs:9:1: injected"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not contain"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-05b: every mutant must land in a bucket" {
  # `--check` builds each mutant without testing it, leaving all four counters
  # at 0 against a non-zero total — so the gate printed "0 caught" and "every
  # mutant was caught" on consecutive lines.
  mk_cargo list_n=5 total=5 caught=0
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"accounted"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-06: a timed-out mutant counts as surviving, not as caught" {
  stub_cargo_outcomes 40 0 39 1 0
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 of 40 mutant(s) survived"* ]]
  # And it is called out by name: a timeout is a mutant no test killed, but for
  # a different reason from a missed one, and the fix is usually different too.
  [[ "$output" == *"timed out"* ]]
}

@test "MUT-07: an empty --in-diff is an explicit skip, not a silent pass" {
  stub_cargo_outcomes 0 0 0 0 0
  : >empty.diff
  run "$GATE" enforce --in-diff empty.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff is empty"* ]]
}

@test "MUT-08: a missing --in-diff file fails instead of mutating nothing" {
  # `<(git diff ...)` discards git's exit status, so a bad pathspec yields an
  # absent/empty stream. Absent must be loud.
  stub_cargo_outcomes 40 0 40 0 0
  run "$GATE" enforce --in-diff /nonexistent/no-such.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "MUT-09: a non-empty diff is actually forwarded to cargo-mutants" {
  # Guards against the skip-path swallowing a real diff.
  stub_cargo_outcomes 12 0 12 0 0
  printf 'diff --git a/x b/x\n' >real.diff
  run "$GATE" enforce --in-diff real.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"12 tested"* ]]
}

@test "MUT-10: an unknown mode is rejected" {
  stub_cargo_outcomes 40 0 40 0 0
  run "$GATE" definitely-not-a-mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown mode"* ]]
}

@test "MUT-11: a run killed partway is not a clean sweep" {
  # cargo-mutants writes outcomes.json after EVERY scenario, so a SIGKILL after
  # 13 of 78 leaves {"total_mutants":13,"missed":0,"caught":13} — indistinguishable
  # from a clean run by counts alone. Reproduced against the real tool.
  stub_cargo_interrupted 13 78 137
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not finish"* || "$output" == *"interrupted"* ]]
  [[ "$output" != *"PASS"* ]]

  # Advisory is no more tolerant of a run that did not finish.
  run "$GATE" advisory
  [ "$status" -ne 0 ]
  [[ "$output" != *"::warning::"* ]]
}

# The gate calls end_time and planned-vs-total "two INDEPENDENT completeness
# checks". MUT-11's fixture trips both at once, so it holds with either one
# deleted — the claim of independence was asserted by nothing. The two cases
# below isolate them, and each is the shape a plausible cargo-mutants revision
# actually produces.

@test "MUT-11a: end_time alone catches a run that stopped mid-sweep" {
  # Every mutant it planned was reached, but no final summary was written: the
  # process died between the last scenario and the summary flush.
  mk_cargo list_n=13 total=13 caught=13 planned=13 end_time=null exit=137
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-11b: planned-vs-total alone catches a summarised partial run" {
  # end_time IS set — the shape a revision that flushes the summary early, or a
  # --shard run summarised before its last scenario, would leave. Then end_time
  # is single-point-of-failure and this is the only check that sees a 17% run.
  mk_cargo list_n=78 total=13 caught=13 planned=78 exit=137
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not finish"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-11c: a run that tested ZERO mutants is never a pass" {
  # The scope is non-empty and the run completed, but it scored nothing. In
  # ENFORCE the set comparison catches it first; in ADVISORY a subset is legal
  # (that is what makes sharding work), so this is the check standing between an
  # empty shard and `0 tested, 0 caught` reported as a clean slice.
  mk_cargo list_n=5 total=0 caught=0 planned=0
  run "$GATE" advisory --shard 0/4
  [ "$status" -ne 0 ]
  [[ "$output" == *"tested 0 mutants"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-12: a run where every mutant is unviable is not a pass" {
  # Unviable = did not compile = no test ran against it. Same hole as zero
  # mutants, one step in.
  stub_cargo_outcomes 40 0 0 0 0 40
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"unviable"* ]]

  run "$GATE" advisory
  [ "$status" -ne 0 ]
}

@test "MUT-13: some unviable mutants are fine as long as one was viable" {
  # Guards against MUT-12 over-correcting into rejecting normal runs — unviable
  # mutants are routine.
  stub_cargo_outcomes 40 0 39 0 0 1
  run "$GATE" enforce
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "MUT-14: outcomes.json really has the shape the gate reads (contract)" {
  # Every case above stubs `cargo`, so together they pin the gate against a
  # schema THIS REPO wrote. If a cargo-mutants bump nests or renames the summary
  # fields, all thirteen stay green while the real gate hard-fails on every PR.
  # This one runs the pinned tool for real, against a throwaway crate, and
  # asserts the five counters plus the end_time completeness marker exist.
  #
  # Required in CI, where the pin is what it is testing.
  requires_real_cargo_mutants

  # A crate with one mutable function and a test that kills the mutant.
  mkdir -p "$WORK/probe/src"
  cat >"$WORK/probe/Cargo.toml" <<'TOML'
[package]
name = "probe"
version = "0.0.0"
edition = "2021"
[workspace]
TOML
  cat >"$WORK/probe/src/lib.rs" <<'RS'
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}
#[cfg(test)]
mod t {
    #[test]
    fn adds() {
        assert_eq!(super::add(2, 2), 4);
        assert_eq!(super::add(0, 1), 1);
    }
}
RS

  cd "$WORK/probe" || return 1
  # stdout ONLY: bats `run` merges stderr into $output, but the gate captures
  # stdout alone. If cargo-mutants ever adds an INFO line to --list, reading the
  # merged stream would fail this contract test while the gate is healthy — a
  # false red on the check whose job is to report a real contract break.
  cargo mutants --no-config --list >listed.txt
  run cargo mutants --output . --minimum-test-timeout 20
  # Whatever the verdict, the results file must carry the shape the gate reads.
  [ -f mutants.out/outcomes.json ]
  [ -f mutants.out/mutants.json ]
  run python3 -c "
import json
d = json.load(open('mutants.out/outcomes.json'))
for k in ('total_mutants', 'missed', 'caught', 'timeout', 'unviable', 'end_time'):
    assert k in d, 'cargo-mutants no longer emits %r at the top level' % k
assert d['end_time'] is not None, 'a completed run must set end_time'
planned = json.load(open('mutants.out/mutants.json'))
assert len(planned) == d['total_mutants'], \
    'mutants.json length must equal total_mutants for the completeness check'
# The set comparison rests on mutants.json[].name being byte-identical to a
# --list line. If either renderer drifts, both gates go red on every PR with
# the wrong diagnosis ('scored a mutant this scope does not contain').
names = {m['name'] for m in planned}
listed = {l.rstrip('\n') for l in open('listed.txt') if l.strip()}
assert names == listed, (
    'mutants.json[].name no longer matches --list output; '
    'symmetric difference: %r' % sorted(names ^ listed)[:5])
print('contract OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"contract OK"* ]]

  # The BASELINE marker, which is the only thing standing between the gate and a
  # `--baseline skip` run whose every mutant is "caught" by a suite that catches
  # nothing. Pinned here because it is a property of the tool, not of this repo.
  run python3 -c "
import json
d = json.load(open('mutants.out/outcomes.json'))
runs = [o for o in d['outcomes'] if o.get('scenario') == 'Baseline']
assert len(runs) == 1, 'a normal run must record exactly one Baseline scenario'
assert runs[0]['summary'] == 'Success', runs[0]['summary']
print('baseline OK')
"
  [ "$status" -eq 0 ]

  # …and that --baseline skip really omits it, so the gate's discriminator is
  # the tool's behaviour rather than an assumption about it.
  run cargo mutants --output . --baseline skip --minimum-test-timeout 20
  run python3 -c "
import json
d = json.load(open('mutants.out/outcomes.json'))
assert not [o for o in d['outcomes'] if o.get('scenario') == 'Baseline'], \
    '--baseline skip still records a Baseline; the gate would no longer catch it'
assert d['caught'] == d['total_mutants'], 'every mutant is still reported caught'
print('baseline-skip OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"baseline-skip OK"* ]]

  # --no-config is what makes the expectation the HONEST one. A
  # .cargo/mutants.toml narrows the mutant set with no argument-vector evidence
  # at all — the channel the tool-derived expectation exists to close — so the
  # flag's semantics are pinned against the tool, not just the gate's use of it
  # against a stub.
  mkdir -p .cargo
  cat >.cargo/mutants.toml <<'TOML'
exclude_re = ["replace \\+ with"]
TOML
  narrowed=$(cargo mutants --list | grep -c . || true)
  honest=$(cargo mutants --no-config --list | grep -c . || true)
  rm -rf .cargo
  [ "$honest" -gt "$narrowed" ] || {
    echo "a config exclusion no longer narrows --list ($honest vs $narrowed);"
    echo "--no-config may have changed meaning — re-check ADR-020 section 2"
    return 1
  }
}

@test "MUT-15: an empty result is a skip only when the tool says the scope is empty" {
  # The stub answers `--list` honestly — the scope contains 4 mutants — and then
  # produces no results file. That is the shape a narrowing filter or an empty
  # --shard leaves, and it must never read as "nothing was mutable".
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then
    for i in 1 2 3 4; do echo "src/x.rs:$i:1: replace a with b"; done
    exit 0
  fi
done
echo " INFO No mutants to filter"
exit 0
EOF
  chmod +x "$BIN/cargo"

  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS"* ]]

  # Advisory is no more tolerant: a run that scored nothing is not a warning.
  run "$GATE" advisory --shard 99/100
  [ "$status" -ne 0 ]
  [[ "$output" != *"::warning::"* ]]
}

@test "MUT-16: a real test-only diff is still a named skip" {
  # The legitimate case MUT-15 must not break: a non-empty diff whose paths
  # resolve, but whose lines yield no mutants.
  stub_cargo_zero_mutants
  mkdir -p crates/c/src
  printf 'pub fn add() {}\n' >crates/c/src/lib.rs
  printf 'diff --git a/crates/c/src/lib.rs b/crates/c/src/lib.rs\n--- a/crates/c/src/lib.rs\n+++ b/crates/c/src/lib.rs\n@@ -1 +1 @@\n-x\n+y\n' >testonly.diff
  run "$GATE" enforce --in-diff testonly.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing mutable in scope"* ]]
}

@test "MUT-17: an --in-diff whose paths do not resolve is a hard failure" {
  # The missing---relative class: cargo-mutants matches --in-diff against the
  # WORKSPACE root, so repo-root-relative paths match nothing and exit 0.
  stub_cargo_zero_mutants
  printf 'diff --git a/rust/crates/c/src/lib.rs b/rust/crates/c/src/lib.rs\n--- a/rust/crates/c/src/lib.rs\n+++ b/rust/crates/c/src/lib.rs\n@@ -1 +1 @@\n-x\n+y\n' >unresolved.diff
  run "$GATE" enforce --in-diff unresolved.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"path that does not exist relative"* ]]
}

@test "MUT-18: a narrowing filter cannot license a skip, whatever it is called" {
  # Four rounds tried to recognise narrowing by reading argv — a denylist of
  # filter flags, then an allowlist of benign ones. Both were hand-copies of
  # clap's grammar and both leaked; and `.cargo/mutants.toml` narrows with NO
  # argv evidence at all, so no argument rule can see it.
  #
  # The gate now asks the tool (`--list --no-config`) what the scope contains
  # and compares. This asserts THAT property: a run whose scored set is smaller
  # than the tool's own expectation fails, and the sample below deliberately
  # includes spellings no allowlist knew plus a flag that does not exist.
  mkdir -p crates/c/src
  printf 'pub fn f() {}\n' >crates/c/src/lib.rs
  printf 'diff --git a/crates/c/src/lib.rs b/crates/c/src/lib.rs\n--- a/crates/c/src/lib.rs\n+++ b/crates/c/src/lib.rs\n@@ -1 +1 @@\n-x\n+y\n' >d.diff

  # --list (the expectation) always reports 4; the run only ever scores 2.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then
    for i in 1 2 3 4; do echo "src/x.rs:$i:1: replace a with b"; done
    exit 0
  fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 2, "missed": 0, "caught": 2, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
JSON
python3 -c "import json; json.dump([{'name': 'src/x.rs:%d:1: replace a with b' % i} for i in range(1, 3)], open('mutants.out/mutants.json','w'))"
: >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit 0
EOF
  chmod +x "$BIN/cargo"

  for extra in "--file x" "-f x" "-e x" "-E x" "-F x" "-fx" "--shard 9/10" \
    "--iterate" "--package p" "-p p" "--skip-calls f" "--some-flag-from-2027" ""; do
    # shellcheck disable=SC2086
    run "$GATE" enforce --in-diff d.diff $extra
    [ "$status" -ne 0 ] || {
      echo "BYPASS via: '$extra'"
      return 1
    }
  done

  # A listing run can never produce a score, under either spelling.
  for l in --list --list-files; do
    run "$GATE" enforce --in-diff d.diff "$l"
    [ "$status" -ne 0 ]
  done
}

@test "MUT-19: an unparseable or unresolvable diff is never treated as verified" {
  stub_cargo_zero_mutants
  printf 'this is not a diff\n' >garbage.diff
  run "$GATE" enforce --in-diff garbage.diff
  [ "$status" -ne 0 ]

  # Real diff shapes naming a path that does NOT resolve. Each of these once
  # yielded zero regex matches and was waved through as "no .rs paths to check":
  # no prefix, CRLF, a tab+timestamp (GNU diff -u), and core.quotePath quoting.
  printf 'diff --git nope/x.rs nope/x.rs\n--- nope/x.rs\n+++ nope/x.rs\n@@ -1 +1 @@\n-x\n+y\n' >noprefix.diff
  printf 'diff --git a/nope/x.rs b/nope/x.rs\r\n--- a/nope/x.rs\r\n+++ b/nope/x.rs\r\n@@ -1 +1 @@\r\n-x\r\n+y\r\n' >crlf.diff
  printf 'diff --git a/nope/x.rs b/nope/x.rs\n--- a/nope/x.rs\t2026-01-02 10:00:00\n+++ b/nope/x.rs\t2026-01-02 10:00:00\n@@ -1 +1 @@\n-x\n+y\n' >ts.diff
  printf 'diff --git "a/nope/f.rs" "b/nope/f.rs"\n--- "a/nope/f.rs"\n+++ "b/nope/f.rs"\n@@ -1 +1 @@\n-x\n+y\n' >quoted.diff
  for d in noprefix.diff crlf.diff ts.diff quoted.diff; do
    run "$GATE" enforce --in-diff "$d"
    [ "$status" -ne 0 ] || {
      echo "waved through: $d"
      return 1
    }
    [[ "$output" == *"path that does not exist relative"* ]]
  done

  # The converse: a diff.noprefix diff naming a path that DOES resolve must
  # pass. The first extractor mangled `+++ src/lib.rs` into `rc/lib.rs`, so it
  # hard-failed every legitimate PR on such a runner while a comment claimed
  # noprefix was tolerated.
  mkdir -p crates/c/src
  printf 'pub fn f() {}\n' >crates/c/src/lib.rs
  printf 'diff --git crates/c/src/lib.rs crates/c/src/lib.rs\n--- crates/c/src/lib.rs\n+++ crates/c/src/lib.rs\n@@ -1 +1 @@\n-x\n+y\n' >npok.diff
  run "$GATE" enforce --in-diff npok.diff
  [ "$status" -eq 0 ]
}

@test "MUT-20: every shard value the nightly dispatches is one cargo-mutants accepts" {
  # The failure this exists for: the matrix read [1, 2, 3, 4] while cargo-mutants
  # shards are ZERO-indexed, so 4/4 was rejected on every nightly run and shard
  # 0's mutants — 245 of 978, a quarter of the workspace — were never dispatched.
  # Advisory mode tolerates a subset by design, so the gate could not notice.
  #
  # It survived two rounds of "verified" because the verification used --shard 1/4
  # on a scratch crate — a value the workflow never passes. So this test derives
  # the values from the WORKFLOW rather than restating them, and runs them
  # through the real tool. `--list` builds nothing, so it is cheap.
  #
  # The PERMUTATION half below needs no tool, so it is not behind the guard: it
  # is the only structural check that the four shards cover the workspace, and
  # putting it behind cargo-mutants made it skip in every self-test run — where
  # `[0, 1, 2, 2]` and `[1, 2, 3, 4]` then both survived.
  local wf="${BATS_TEST_DIRNAME}/../../.github/workflows/nightly-mutation.yml"
  [ -f "$wf" ]

  # The matrix line, and the /N the step actually divides by.
  local values total
  values=$(sed -n 's/^ *shard: *\[\(.*\)\] *$/\1/p' "$wf" | tr -d ' ' | tr ',' ' ')
  # Every sharded step must divide by the same N — `head -1` would leave a
  # second one silently unchecked.
  local totals
  totals=$(sed -n 's|.*--shard .*/\([0-9][0-9]*\).*|\1|p' "$wf" | sort -u)
  [ "$(printf '%s\n' "$totals" | grep -c .)" -eq 1 ] || {
    echo "workflow shards by more than one divisor: $totals"
    return 1
  }
  total="$totals"
  [ -n "$values" ]
  [ -n "$total" ]

  # The matrix must be a PERMUTATION of 0..N-1, not merely N values the tool
  # accepts. Counting was the same mistake one level up: [0, 1, 2, 2] has four
  # accepted values and leaves shard 3 undispatched — a quarter of the workspace
  # unscored, byte-for-byte the outcome of [1, 2, 3, 4], and this time with no
  # red runner to hint at it.
  local want got
  want=$(seq 0 $((total - 1)) | sort | tr '\n' ' ')
  got=$(printf '%s\n' $values | sort | tr '\n' ' ')
  [ "$got" = "$want" ] || {
    echo "shard matrix is [$got] but must be a permutation of [$want];"
    echo "a missing or duplicated value leaves part of the workspace unscored."
    return 1
  }

  # Only the "does the tool accept these values" half needs the real tool.
  requires_real_cargo_mutants

  cd "${BATS_TEST_DIRNAME}/../../rust" || return 1
  for v in $values; do
    run cargo mutants --no-config --list --shard "$v/$total"
    [ "$status" -eq 0 ] || {
      echo "cargo-mutants rejects --shard $v/$total (the nightly dispatches it): $output"
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# #[mutants::skip] — the one narrowing channel the tool-derived expectation
# cannot see. A skipped fn is absent from BOTH `--list` and `mutants.json`, so
# the sets match and the gate says PASS. In the enforcing per-PR gate that makes
# it the one exemption an author can grant themselves inside the scored diff.

# Write src/x.rs plus a diff adding $1 as the line above `#[mutants::skip]`.
# $1 is the annotation's neighbour: a `//` comment justifies it, anything else
# does not.
seed_skip_diff() {
  mkdir -p src
  cat >src/x.rs <<RS
$1
#[cfg_attr(test, mutants::skip)]
fn adapter() -> bool { true }
RS
  cat >skip.diff <<DIFF
diff --git a/src/x.rs b/src/x.rs
--- /dev/null
+++ b/src/x.rs
@@ -0,0 +1,3 @@
+$1
+#[cfg_attr(test, mutants::skip)]
+fn adapter() -> bool { true }
DIFF
}

@test "MUT-21: a diff adding an UNANNOTATED #[mutants::skip] is refused" {
  stub_cargo_outcomes 40 0 40 0 0
  seed_skip_diff 'use std::fmt;'
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/x.rs:2"* ]]
  [[ "$output" == *"ADR-020"* ]]
}

@test "MUT-21b: the same diff passes once the skip carries a reason" {
  stub_cargo_outcomes 40 0 40 0 0
  seed_skip_diff '/// Not mutation-tested: this adapter only reads the ambient tty.'
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "MUT-21c: a skip the diff did not add is not this PR's to justify" {
  stub_cargo_outcomes 40 0 40 0 0
  seed_skip_diff 'use std::fmt;'
  # Same unannotated file, but the diff touches an unrelated line: the gate must
  # not hold a contributor answerable for an exemption somebody else took.
  cat >skip.diff <<'DIFF'
diff --git a/src/x.rs b/src/x.rs
--- a/src/x.rs
+++ b/src/x.rs
@@ -3 +3 @@
-fn adapter() -> bool { false }
+fn adapter() -> bool { true }
DIFF
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -eq 0 ]
}

@test "MUT-22: an unreadable mutants.json is diagnosed, not a bash error" {
  # `set -u` used to turn this into `verdict[0]: unbound variable` — a bash
  # diagnostic for a cargo-mutants problem, on the line that decides whether the
  # run measured this code at all.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 1, "missed": 0, "caught": 1, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z",
 "outcomes": [{"scenario": "Baseline", "summary": "Success"}]}
JSON
printf '{"name": "src/x.rs:1' >mutants.out/mutants.json
exit 0
EOF
  chmod +x "$BIN/cargo"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" == *"not readable as JSON"* ]]
}

@test "MUT-22b: an ENTRY shape the set comparison cannot read is diagnosed too" {
  # The array-of-strings case: it is a list, and its length matches
  # total_mutants, so it walks past both completeness checks and the baseline
  # check, and only breaks in the SET COMPARISON — the second of the two places
  # this file is read. MUT-22's truncated file dies at the first one, so without
  # this case the second reader's failure handling is asserted by nothing.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 1, "missed": 0, "caught": 1, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z",
 "outcomes": [{"scenario": "Baseline", "summary": "Success"}]}
JSON
echo '["src/x.rs:1:1: replace a with b"]' >mutants.out/mutants.json
exit 0
EOF
  chmod +x "$BIN/cargo"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" == *"could not compare the expected mutant set"* ]]
}

@test "MUT-23: a mutants.json SHAPE change is named as schema drift" {
  # A future `{"mutants": [...]}` wrapper has len 1, which the previous revision
  # compared against total_mutants and reported as "the run did not finish" —
  # the one diagnosis that sends a reader to the runner instead of to the tool.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 1, "missed": 0, "caught": 1, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z",
 "outcomes": [{"scenario": "Baseline", "summary": "Success"}]}
JSON
echo '{"mutants": [{"name": "src/x.rs:1:1: replace a with b"}]}' >mutants.out/mutants.json
exit 0
EOF
  chmod +x "$BIN/cargo"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"changed its results schema"* ]]
  [[ "$output" != *"did not finish"* ]]
}

@test "MUT-24: every terminating path renders a VERDICT in the job summary" {
  # The summary is the only output most readers see. An earlier revision
  # appended the `mutants: N tested…` count BEFORE the remaining die-checks, so a
  # failed job rendered a count with no verdict beside it.
  export GITHUB_STEP_SUMMARY="$WORK/summary.md"

  : >"$GITHUB_STEP_SUMMARY"
  stub_cargo_outcomes 40 0 40 0 0
  run "$GATE" enforce
  [ "$status" -eq 0 ]

  stub_cargo_outcomes 40 3 37 0 2
  run "$GATE" enforce
  [ "$status" -ne 0 ]

  stub_cargo_outcomes 40 3 37 0 2
  run "$GATE" advisory
  [ "$status" -eq 0 ]

  # total==0 with a non-empty expectation: fails AFTER the count is computed,
  # which is exactly where the verdict-less line used to be written.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 0, "missed": 0, "caught": 0, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z",
 "outcomes": [{"scenario": "Baseline", "summary": "Success"}]}
JSON
echo '[]' >mutants.out/mutants.json
exit 0
EOF
  chmod +x "$BIN/cargo"
  run "$GATE" enforce
  [ "$status" -ne 0 ]

  stub_cargo_outcomes 0 0 0 0 0
  : >empty.diff
  run "$GATE" enforce --in-diff empty.diff
  [ "$status" -eq 0 ]

  # A non-empty diff the tool says contains nothing mutable — a test-only PR.
  # The other exit-0 path, and the one a reader is most likely to misread.
  stub_cargo_zero_mutants
  printf 'diff --git a/src/x.rs b/src/x.rs\n--- a/src/x.rs\n+++ b/src/x.rs\n@@ -1 +1 @@\n-a\n+b\n' >solid.diff
  mkdir -p src && : >src/x.rs
  run "$GATE" enforce --in-diff solid.diff
  [ "$status" -eq 0 ]

  [ -s "$GITHUB_STEP_SUMMARY" ]
  while IFS= read -r line; do
    [[ "$line" == *PASS* || "$line" == *FAIL* || "$line" == *WARN* || "$line" == *SKIPPED* ]] ||
      { echo "job-summary line has no verdict: $line"; return 1; }
  done <"$GITHUB_STEP_SUMMARY"
  # …and one line per invocation, so none of them silently wrote nothing.
  [ "$(grep -c . "$GITHUB_STEP_SUMMARY")" -eq 6 ]
}

@test "MUT-25: a run with no BASELINE is never a pass, in either mode" {
  # The demonstrated false green, and the last way "nothing ran" could render as
  # "nothing survived": with `--baseline skip` and a test command that fails for
  # its own reasons, cargo-mutants marks EVERY mutant caught. end_time is set,
  # planned == total, the sets match, accounting balances, unviable is 0 — every
  # other check in the gate passes on a tree where no test passes.
  mk_cargo list_n=5 total=5 caught=5 baseline=missing
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"no baseline"* || "$output" == *"established no baseline"* ]]
  [[ "$output" != *"PASS"* ]]

  # Advisory is not exempt: a warning mode still must not report a score for a
  # run that measured nothing.
  run "$GATE" advisory
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-25b: a FAILING baseline is a different diagnosis from a missing one" {
  # A red suite before any mutation is applied. The counters look identical to
  # MUT-25's, so the two must be told apart by the reader, not just both refused.
  mk_cargo list_n=5 total=5 caught=5 baseline=failed
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"baseline did not pass"* ]]
  [[ "$output" != *"--baseline skip"* ]]
}

@test "MUT-26: --no-config is what makes the expectation honest" {
  # `.cargo/mutants.toml` narrows the mutant set with NO argument-vector evidence
  # at all — the channel the tool-derived expectation exists to close. Drop
  # --no-config from the query and the expectation shrinks in lockstep with the
  # run, the sets match, and the gate passes a scope a config file carved up.
  # This stub answers --list with 8 mutants only when asked --no-config.
  mk_cargo list_n=8 list_cfg_n=3 total=3 caught=3
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"never scored"* ]]
  [[ "$output" != *"PASS"* ]]

  # And the query really did carry both flags.
  [[ "$(cargo_argv_log)" == *"--no-config --list"* ]]
}

@test "MUT-27: an advisory shard reports PARTIAL, never an unqualified PASS" {
  # The nightly's everyday success path: each of four runners scores a slice and
  # every mutant in that slice is caught. Rendering that as `PASS — every mutant
  # was caught` is the original nothing-survived-vs-nothing-ran confusion one
  # level up, in the reporting.
  export GITHUB_STEP_SUMMARY="$WORK/summary.md"
  : >"$GITHUB_STEP_SUMMARY"
  mk_cargo list_n=8 total=2 caught=2 planned=2

  run "$GATE" advisory --shard 0/4
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 of 8 in scope"* ]]
  [[ "$output" == *"IN THIS SLICE"* ]]
  [[ "$output" != *"PASS — every mutant was caught"* ]]
  [[ "$(cat "$GITHUB_STEP_SUMMARY")" == *"PARTIAL PASS"* ]]

  # The same subset is NOT tolerable in the merge gate: a shard of the mutant set
  # is not a scoring of the change.
  run "$GATE" enforce --shard 0/4
  [ "$status" -ne 0 ]
  [[ "$output" == *"never scored"* ]]
}

@test "MUT-28: the run receives the caller's flags, and the query its own" {
  # The gate makes two `cargo` calls with different argv and both matter: the
  # query must be `--no-config --list [--in-diff F]`, and the RUN must carry
  # everything the caller passed. Asserted from the recorded argv rather than
  # from the verdict — with `"$@"` deleted from the run, every earlier version of
  # this case still passed.
  mk_cargo list_n=12 total=12 caught=12
  printf 'diff --git a/src/x.rs b/src/x.rs\n--- a/src/x.rs\n+++ b/src/x.rs\n@@ -1 +1 @@\n-a\n+b\n' >real.diff
  mkdir -p src && : >src/x.rs

  run "$GATE" enforce --in-place --minimum-test-timeout 20 --in-diff real.diff
  [ "$status" -eq 0 ]

  local log
  log="$(cargo_argv_log)"
  [[ "$log" == *"mutants --no-config --list --in-diff real.diff"* ]]
  [[ "$log" == *"--in-place --minimum-test-timeout 20 --in-diff real.diff"* ]]
  # …and the run writes where the gate reads.
  [[ "$log" == *"--output ."* ]]
}

@test "MUT-29: every --in-diff spelling clap accepts is checked, not just one" {
  # `--in-diff F`, `--in-diff=F` and `-DF` are one option to clap. A spelling the
  # gate does not recognise silently skips BOTH the path-resolution check and the
  # skip policy — fail-open on the two checks that read the diff.
  mk_cargo list_n=4 total=4 caught=4
  printf 'diff --git a/rust/nope.rs b/rust/nope.rs\n--- a/rust/nope.rs\n+++ b/rust/nope.rs\n@@ -1 +1 @@\n-a\n+b\n' >bad.diff

  local spelling
  for spelling in "--in-diff bad.diff" "--in-diff=bad.diff" "-Dbad.diff"; do
    # shellcheck disable=SC2086
    run "$GATE" enforce $spelling
    [ "$status" -ne 0 ] || {
      echo "spelling '$spelling' bypassed the diff checks"
      return 1
    }
    [[ "$output" == *"path that does not exist relative"* ]] || {
      echo "spelling '$spelling' gave: $output"
      return 1
    }
  done
}

@test "MUT-30: a whitespace-spelled mutants::skip is still an added skip" {
  # Rust tolerates whitespace and comments around `::`, and cargo-mutants
  # resolves the attribute through syn, so `mutants :: skip` really does suppress
  # every mutant of the function. A substring match on "mutants::skip" bought the
  # whole exemption back for one extra space — in a spelling that looks MORE
  # idiomatic to a reviewer skimming the diff.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  local spelling
  for spelling in '#[cfg_attr(test, mutants :: skip)]' '#[mutants::  skip]'; do
    printf 'use std::fmt;\n%s\nfn adapter() {}\n' "$spelling" >src/x.rs
    printf 'diff --git a/src/x.rs b/src/x.rs\n--- /dev/null\n+++ b/src/x.rs\n@@ -0,0 +1,3 @@\n+use std::fmt;\n+%s\n+fn adapter() {}\n' "$spelling" >skip.diff
    run "$GATE" enforce --in-diff skip.diff
    [ "$status" -ne 0 ] || {
      echo "spelling '$spelling' evaded the skip policy"
      return 1
    }
    [[ "$output" == *"ADR-020"* ]]
  done
}

@test "MUT-30b: the comment must be NEAR the skip, not anywhere above it" {
  # The whole content of the rule is the window. Widen it to the top of the file
  # and the check is unconditionally vacuous on real source: all seven skips in
  # this tree sit hundreds of lines below some `//`.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  cat >src/x.rs <<'RS'
// A comment, but about something else entirely, far above.
use std::fmt;
use std::io;
use std::path::Path;
use std::process;
#[cfg_attr(test, mutants::skip)]
fn adapter() {}
RS
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,7 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/x.rs:6"* ]]
}

@test "MUT-30c: a comment that MENTIONS the attribute is not itself a skip" {
  # Every justification comment in the tree names the attribute it justifies. If
  # the recogniser matched those, the file would be pulled into scope by its own
  # documentation — and each comment line judged as an unannotated skip.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  cat >src/x.rs <<'RS'
/// This function is not annotated with #[mutants::skip] and does not need to be.
fn ordinary() {}
RS
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,2 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "MUT-31: a stale mutants.out from a previous run is never read as this one" {
  # The gate reads a fixed directory. Left in place, a prior invocation's results
  # — a clean sweep, say — are what a failed run would be judged by.
  mkdir -p mutants.out
  python3 -c "
import json
json.dump({'total_mutants': 99, 'missed': 0, 'caught': 99, 'timeout': 0,
           'unviable': 0, 'end_time': 'stale',
           'outcomes': [{'scenario': 'Baseline', 'summary': 'Success'}]},
          open('mutants.out/outcomes.json','w'))
json.dump([{'name': 'stale'}], open('mutants.out/mutants.json','w'))
"
  stub_cargo_rejects_flags
  run "$GATE" enforce --in-place --jobs 4
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete a run"* ]]
  [[ "$output" != *"99"* ]]
}

@test "MUT-32: invoked with no arguments it says so, rather than crashing" {
  run "$GATE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "MUT-32b: a listing flag is refused — it produces no score to judge" {
  # `--list` and `--list-files` write no mutants.out at all, so every check here
  # would read a missing file and report "cargo-mutants did not complete a run".
  # True, but it names the wrong problem: the caller asked for a listing, not a
  # run. Refuse it where the argument is read.
  mk_cargo list_n=4 total=4 caught=4
  local flag
  for flag in --list --list-files; do
    run "$GATE" enforce "$flag"
    [ "$status" -ne 0 ]
    [[ "$output" == *"produces no mutation score"* ]] || {
      echo "'$flag' gave: $output"
      return 1
    }
  done
}

@test "MUT-33: a core.quotePath-escaped diff is refused with the fix, not a guess" {
  # git's DEFAULT quoting for non-ASCII paths. Decoding it wrong means
  # hard-failing an honest PR, so the gate refuses and names the flag that fixes
  # it. Without this the path check reports "does not exist relative to", sending
  # the reader to look for a file that is really just mis-encoded.
  mk_cargo list_n=4 total=4 caught=4
  printf 'diff --git "a/src/caf\\303\\251.rs" "b/src/caf\\303\\251.rs"\n--- "a/src/caf\\303\\251.rs"\n+++ "b/src/caf\\303\\251.rs"\n@@ -1 +1 @@\n-a\n+b\n' >quoted.diff
  run "$GATE" enforce --in-diff quoted.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"core.quotePath"* ]]
}

@test "MUT-34: both workflows still invoke the mode and the flags they need" {
  # MUT-20 derives the shard matrix from the workflow and runs it through the
  # real tool. The same reasoning applies to the two things that decide what the
  # gate MEANS: one word at test.yml — enforce -> advisory — turns the merge gate
  # into a warning, with the whole suite still green and the change reading in
  # review as a plausible "reduce PR friction" edit.
  local root="${BATS_TEST_DIRNAME}/../.."
  local pr="$root/.github/workflows/test.yml"
  local nightly="$root/.github/workflows/nightly-mutation.yml"
  [ -f "$pr" ] && [ -f "$nightly" ]

  # Both invocations wrap over a backslash continuation, so join those first —
  # grepping the raw line sees the mode and none of the flags.
  #
  # And anchor on the INVOCATION, not on any line mentioning the script: both
  # workflows also discuss it in prose (test.yml's step comment,
  # nightly-mutation.yml's job header). Matching those too meant the assertions
  # ran over a concatenation that happened to contain the right words — so a
  # future comment reading "run `mutation-gate.sh enforce` locally" would keep
  # this case green through the exact one-word change it exists to catch.
  gate_call() {
    sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$1" |
      grep -hE '^[[:space:]]*(run:[[:space:]]*)?([A-Z_]+=[^[:space:]]*[[:space:]]+)*[./A-Za-z_-]*scripts/mutation-gate\.sh[[:space:]]'
  }
  local pr_call nightly_call
  pr_call="$(gate_call "$pr")"
  nightly_call="$(gate_call "$nightly")"

  # The per-PR gate FAILS a merge, and is bounded by the diff so its cost is
  # proportional to the change (ADR-020 §1).
  [[ "$pr_call" == *"mutation-gate.sh enforce"* ]] || {
    echo "test.yml no longer calls the gate in enforce mode: $pr_call"
    return 1
  }
  [[ "$pr_call" == *"--in-diff"* ]] || {
    echo "test.yml no longer bounds the gate by the diff: $pr_call"
    return 1
  }
  # The nightly WARNS, and covers the whole workspace by sharding.
  [[ "$nightly_call" == *"mutation-gate.sh advisory"* ]] || {
    echo "nightly no longer calls the gate in advisory mode: $nightly_call"
    return 1
  }
  [[ "$nightly_call" == *"--shard"* ]]
  # --in-place is required by both (two agentlinux-core tests read fixtures
  # outside the workspace, so the default copy-tree baseline fails) and it is
  # what forbids --jobs.
  [[ "$pr_call" == *"--in-place"* ]]
  [[ "$nightly_call" == *"--in-place"* ]]
  [[ "$pr_call" != *"--jobs"* ]]
  [[ "$nightly_call" != *"--jobs"* ]]
  # The flag that made the false green reproducible.
  [[ "$pr_call" != *"--baseline"* ]]
  [[ "$nightly_call" != *"--baseline"* ]]

  # Exactly one invocation each — a second, unasserted call would be scored by
  # none of the above.
  [ "$(printf '%s\n' "$pr_call" | grep -c .)" -eq 1 ]
  [ "$(printf '%s\n' "$nightly_call" | grep -c .)" -eq 1 ]
}

@test "MUT-34d: neither gate step is allowed to not-fail" {
  # The original bug was `|| echo "::warning::"` plus `continue-on-error: true`
  # plus a flag pair the tool rejects. Two of those three live in YAML, and
  # MUT-34 reads only the joined `run:` line — so adding `continue-on-error: true`
  # to the enforcing step, or replacing its `if:` with `false`, leaves the merge
  # gate switched off with all 67 cases green. ADR-020 §2 names
  # `continue-on-error` explicitly as something advisory mode does NOT license.
  local root="${BATS_TEST_DIRNAME}/../.."
  local wf step
  for wf in "$root/.github/workflows/test.yml" "$root/.github/workflows/nightly-mutation.yml"; do
    # The step block: from the `- name:` line that mentions the gate, up to the
    # next `- name:` at the same indentation.
    step="$(awk '
      /^      - name:/ { inblock = /mutants|mutation/ ? 1 : 0 }
      inblock { print }
    ' "$wf")"
    [ -n "$step" ] || {
      echo "no mutation-gate step found in $wf"
      return 1
    }
    [[ "$step" != *"continue-on-error"* ]] || {
      echo "$wf lets the mutation gate step not fail:"
      echo "$step"
      return 1
    }
    # The `if:` must be the readiness guard, not a constant that switches the
    # step off entirely.
    [[ "$step" != *"if: false"* && "$step" != *"if: \${{ false }}"* ]] || {
      echo "$wf disables the mutation gate step with a constant if:"
      return 1
    }
  done
}

@test "MUT-34e: the enforcing gate's own timeout fits inside the job cap" {
  # `--in-place` mutates the working tree and cargo-mutants restores on SIGTERM
  # but not SIGKILL, so the gate's timeout must fire BEFORE the job cap does.
  # With the gate defaulting to 3600s inside a 15-minute job, the inner bound was
  # unreachable in the only path where the argument matters.
  local root="${BATS_TEST_DIRNAME}/../.."
  local pr="$root/.github/workflows/test.yml"
  local job_min gate_secs
  job_min="$(awk '/^  rust:/{f=1} f && /timeout-minutes:/{print $2; exit}' "$pr")"
  gate_secs="$(grep -oE 'MUTATION_GATE_TIMEOUT=[0-9]+' "$pr" | head -1 | cut -d= -f2)"
  [ -n "$job_min" ] || { echo "no timeout-minutes on the rust job"; return 1; }
  [ -n "$gate_secs" ] || {
    echo "the enforcing step does not set MUTATION_GATE_TIMEOUT; it would default"
    echo "to a value nothing ties to the job cap"
    return 1
  }
  [ "$gate_secs" -lt "$((job_min * 60))" ] || {
    echo "gate timeout ${gate_secs}s is not inside the ${job_min}m job cap"
    return 1
  }
}

@test "MUT-34b: both jobs pin the SAME cargo-mutants version" {
  # ADR-020 §1 has the two gates sharing one mutant set: the nightly re-scores
  # what the per-PR gate never revisits. That only holds if both run the same
  # tool. Nothing compared the two pins, and MUT-14 validates the schema against
  # whatever is on PATH — which in the nightly job no test ever exercises.
  local root="${BATS_TEST_DIRNAME}/../.."
  local pr nightly
  pr="$(grep -hoE 'cargo-mutants@[0-9.]+|cargo-mutants --version [0-9.]+|--version [0-9.]+' \
    "$root/.github/workflows/test.yml" | head -1)"
  nightly="$(grep -hoE 'cargo-mutants@[0-9.]+|cargo-mutants --version [0-9.]+|--version [0-9.]+' \
    "$root/.github/workflows/nightly-mutation.yml" | head -1)"
  [ -n "$pr" ] || { echo "no cargo-mutants pin found in test.yml"; return 1; }
  [ -n "$nightly" ] || { echo "no cargo-mutants pin found in nightly-mutation.yml"; return 1; }
  [ "$pr" = "$nightly" ] || {
    echo "the two jobs pin different cargo-mutants versions: '$pr' vs '$nightly';"
    echo "ADR-020 section 1 has them sharing one mutant set"
    return 1
  }
}

@test "MUT-34c: CI runs this whole suite, not a filtered slice of it" {
  # This file is the only thing asserting the gate works. A `--filter` on the CI
  # invocation would leave most of it unrun with the job still green.
  local root="${BATS_TEST_DIRNAME}/../.."
  local call
  call="$(grep -h '80-mutation-gate.bats' "$root/.github/workflows/test.yml")"
  [ -n "$call" ] || { echo "test.yml no longer runs the gate's own suite"; return 1; }
  [[ "$call" != *"--filter"* && "$call" != *" -f "* ]] || {
    echo "the gate suite is run filtered in CI: $call"
    return 1
  }
}

# ---------------------------------------------------------------------------
# Boundary cases. Round 11 mutated every threshold in the script by one and the
# suite killed none of them: MUT-05 uses 5 unscored, MUT-26 uses 5, MUT-27 uses
# 6, MUT-13 uses 39 viable. `-gt 0 -> -gt 1` on the merge gate's central
# comparison passed 46 cases while letting a one-mutant narrowing through — and
# one `exclude_re` line in .cargo/mutants.toml matching one function produces
# exactly that.

@test "MUT-35: ONE unscored mutant already fails the merge gate" {
  mk_cargo list_n=4 total=3 caught=3 planned=3
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 mutant(s) in scope were never scored"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-35b: ONE unexpected mutant already fails, in both modes" {
  mk_cargo list_n=3 total=4 caught=4 planned=3 "extra=src/OTHER.rs:9:1: injected"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"scored 1 mutant(s) this scope does not contain"* ]]
  run "$GATE" advisory
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-35c: exactly ONE viable mutant is a legitimate run, not a failure" {
  # The other side of the boundary: `-le 0 -> -le 1` hard-fails a diff whose one
  # mutable line happens to sit among unviable ones — a false RED the
  # contributor cannot act on.
  mk_cargo list_n=4 total=4 caught=1 unviable=3
  run "$GATE" enforce
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "MUT-35d: FEWER planned than scored is a partial run too" {
  # `-ne -> -gt` survived because every fixture had planned > total. A truncated
  # mutants.json, or an outcomes file padded past it, walks through `-gt`.
  mk_cargo list_n=5 total=5 caught=5 planned=4
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not finish"* ]]
}

@test "MUT-36: -D FILE, the fourth spelling, is checked like the other three" {
  # `--in-diff F`, `--in-diff=F`, `-DF` and `-D F` are one option to clap.
  # MUT-29 covered three; deleting `-D` from the case arm left `-D bad.diff`
  # skipping BOTH the path check and the skip policy, and the gate printed PASS.
  mk_cargo list_n=4 total=4 caught=4
  printf 'diff --git a/rust/nope.rs b/rust/nope.rs\n--- a/rust/nope.rs\n+++ b/rust/nope.rs\n@@ -1 +1 @@\n-a\n+b\n' >bad.diff
  run "$GATE" enforce -D bad.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"path that does not exist relative"* ]]
}

@test "MUT-36b: when the option repeats, the file the RUN uses is the one checked" {
  # clap takes the last occurrence. A gate that inspected the first would verify
  # `good.diff` while cargo-mutants scored `bad.diff` — the check and the run
  # looking at different files, which is a green gate over an unverified diff.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src && : >src/good.rs
  printf 'diff --git a/src/good.rs b/src/good.rs\n--- a/src/good.rs\n+++ b/src/good.rs\n@@ -1 +1 @@\n-a\n+b\n' >good.diff
  printf 'diff --git a/rust/nope.rs b/rust/nope.rs\n--- a/rust/nope.rs\n+++ b/rust/nope.rs\n@@ -1 +1 @@\n-a\n+b\n' >bad.diff
  run "$GATE" enforce --in-diff good.diff --in-diff bad.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"nope.rs"* ]]
}

@test "MUT-37: EVERY path in a multi-file diff must resolve, not just the first" {
  # Every diff fixture named exactly one .rs path, so the loop was
  # indistinguishable from a first-element check and `paths[:1]` survived.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src && : >src/first.rs
  {
    printf 'diff --git a/src/first.rs b/src/first.rs\n--- a/src/first.rs\n+++ b/src/first.rs\n@@ -1 +1 @@\n-a\n+b\n'
    printf 'diff --git a/src/second.rs b/src/second.rs\n--- a/src/second.rs\n+++ b/src/second.rs\n@@ -1 +1 @@\n-a\n+b\n'
  } >two.diff
  run "$GATE" enforce --in-diff two.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"second.rs"* ]]
}

@test "MUT-37b: a path containing spaces is read whole" {
  # `+++ b/src/my file.rs` — the tab-terminated field, not the first
  # whitespace-delimited word. `.split("\t")` -> `.split()` truncates it to
  # `b/src/my`, which then does not end in .rs and is silently skipped: an
  # unverified path waved through as "nothing to check".
  mk_cargo list_n=4 total=4 caught=4
  printf 'diff --git a/src/my file.rs b/src/my file.rs\n--- a/src/my file.rs\n+++ b/src/my file.rs\n@@ -1 +1 @@\n-a\n+b\n' >spaced.diff
  run "$GATE" enforce --in-diff spaced.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"my file.rs"* ]]
}

@test "MUT-38: an INDENTED skip with an indented comment is accepted" {
  # The shape of this repo's own source: sysio.rs's skips sit inside an `impl`,
  # indented, under an indented `///`. Dropping `.strip()` from the window
  # refuses every one of them — a false RED on the only real example there is,
  # and every skip fixture in this file writes at column 0.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  cat >src/x.rs <<'RS'
struct TmpGuard;
impl TmpGuard {
    /// Not mutation-tested: skipping the disarm makes Drop unlink a path the
    /// rename already consumed — a no-op no test can distinguish.
    #[cfg_attr(test, mutants::skip)]
    fn disarm(&self) {}
}
RS
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,7 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "MUT-38b: the window is exactly three lines, pinned from both sides" {
  # `i - 3 -> i - 1` and `i - 3 -> i - 4` both survived: every fixture put the
  # comment either immediately above or five lines up, so the rule ADR-020 states
  # was only constrained to 1..4. Under `i - 1` an ordinary
  # `// reason` / `#[cfg(unix)]` / `#[mutants::skip]` becomes unmergeable.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src

  # Comment exactly 3 above: ACCEPTED.
  cat >src/x.rs <<'RS'
// Not mutation-tested: unobservable through the seam.
#[cfg(unix)]
#[allow(dead_code)]
#[mutants::skip]
fn adapter() {}
RS
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,5 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -eq 0 ]

  # Comment 4 above: REFUSED. The reason is too far to be read as one.
  cat >src/x.rs <<'RS'
// Not mutation-tested: unobservable through the seam.
#[cfg(unix)]
#[allow(dead_code)]
#[allow(unused)]
#[mutants::skip]
fn adapter() {}
RS
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,6 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/x.rs:5"* ]]
}

@test "MUT-38c: a URL in the line above does not count as a comment" {
  # `x.startswith("//")` -> `"//" in x` survived. Any preceding line containing
  # `http://` — a doc link, a URL in a string literal — then licenses an
  # unannotated skip.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  cat >src/x.rs <<'RS'
const DOCS: &str = "https://example.invalid/mutants";
#[mutants::skip]
fn adapter() {}
RS
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,3 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/x.rs:2"* ]]
}

@test "MUT-38d: a block comment inside the attribute does not evade the policy" {
  # The normalisation drops /* … */ before matching, and MUT-30 only exercised
  # whitespace spellings, so removing that survived.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  printf 'use std::fmt;\n#[cfg_attr(test, mutants /*why*/ :: skip)]\nfn adapter() {}\n' >src/x.rs
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,3 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"ADR-020"* ]]
}

@test "MUT-38e: a NON-Rust file that quotes the attribute is not a skip site" {
  # ADR-020 itself quotes `#[mutants::skip]` a dozen times. Dropping the
  # `cur and` guard makes a docs-only PR crash the gate with a Python TypeError
  # reported as "could not read the --in-diff file".
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p docs/decisions src && : >src/x.rs
  # The added line must BE the attribute, not merely mention it — a fenced code
  # block in the ADR, which is how that document actually shows one. Prose with
  # the attribute quoted mid-sentence does not start with `#[`, so the recogniser
  # skips it and the fixture never reaches the guard it is named for.
  {
    echo 'diff --git a/docs/decisions/020-mutation-testing-policy.md b/docs/decisions/020-mutation-testing-policy.md'
    echo '--- a/docs/decisions/020-mutation-testing-policy.md'
    echo '+++ b/docs/decisions/020-mutation-testing-policy.md'
    echo '@@ -1 +1,4 @@'
    echo '+A skip is written:'
    echo '+```rust'
    echo '+#[cfg_attr(test, mutants::skip)]'
    echo '+```'
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- a/src/x.rs'
    echo '+++ b/src/x.rs'
    echo '@@ -1 +1 @@'
    echo '-a'
    echo '+b'
  } >docs.diff
  run "$GATE" enforce --in-diff docs.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  [[ "$output" != *"could not read"* ]]
}

@test "MUT-36c: --in-diff with no file argument is refused" {
  # The dangling-option case. Left unguarded, `diff_file` stays empty, so the
  # whole diff half of the gate — path resolution AND the skip policy — is
  # skipped, and the expectation query silently widens to the entire workspace.
  mk_cargo list_n=4 total=4 caught=4
  run "$GATE" enforce --in-place --in-diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"--in-diff given with no file argument"* ]]
}

@test "MUT-39: ADVISORY is no more tolerant of a missing end_time" {
  # MUT-11a isolates end_time in ENFORCE only, and MUT-11's advisory half is
  # caught by the planned-vs-total check instead — so `finished` could be made
  # enforce-only and the suite stayed green. The nightly is the mode that
  # actually runs long enough to be OOM-killed between the last scenario and the
  # summary flush.
  mk_cargo list_n=13 total=13 caught=13 planned=13 end_time=null exit=137
  run "$GATE" advisory
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-40: a MISSING mutants.json names the missing file, not a partial run" {
  # The third sentinel arm. MUT-22 covers unparseable and MUT-23 covers the
  # wrong shape; with NO_FILE untested, replacing its die with a warning left the
  # gate reporting "planned -1 mutant(s) but outcomes.json records only 1 — the
  # run did not finish", which is the misdiagnosis MUT-23 exists to prevent.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 1, "missed": 0, "caught": 1, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z",
 "outcomes": [{"scenario": "Baseline", "summary": "Success"}]}
JSON
exit 0
EOF
  chmod +x "$BIN/cargo"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"left no"* && "$output" == *"mutants.json"* ]]
  [[ "$output" != *"did not finish"* ]]
  [[ "$output" != *"-1"* ]]
}

@test "MUT-42: a run that outlives its timeout is a failure, not a pass" {
  # `--in-place` mutates the working tree, so an abrupt kill leaves
  # `~ changed by cargo-mutants ~` in the source. cargo-mutants restores on
  # SIGTERM but not on SIGKILL, and an agent harness or CI step timeout sends
  # SIGKILL — so the gate's own timeout must fire FIRST. Without it the outer
  # kill also takes the gate with it, leaving no verdict at all.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
sleep 30
EOF
  chmod +x "$BIN/cargo"
  MUTATION_GATE_TIMEOUT=1 run "$GATE" enforce --in-place
  [ "$status" -ne 0 ]
  [[ "$output" == *"gate timeout"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-43: the run is niced, so it yields to anything interactive" {
  # Every mutant is a full rustc build plus the entire test suite. Run at normal
  # priority in a loop this starves the machine it is running on — which is how
  # a mutation experiment took a host down hard enough to lock out SSH.
  cat >"$BIN/cargo" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
ps -o nice= -p \$\$ | tr -d ' ' >"$WORK/niceness"
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 1, "missed": 0, "caught": 1, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z",
 "outcomes": [{"scenario": "Baseline", "summary": "Success"}]}
JSON
echo '[{"name": "src/x.rs:1:1: replace a with b"}]' >mutants.out/mutants.json
: >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit 0
EOF
  chmod +x "$BIN/cargo"
  # Assert the child is niced strictly BELOW its parent, not merely `> 0`.
  # `> 0` was satisfied by INHERITED niceness: the self-test driver runs each
  # iteration under `nice`, so the stub reported 19 whether or not the gate niced
  # anything, and `run: drop the nice` survived its own test. The test was
  # co-blind with the harness written to run it.
  local parent
  parent="$(ps -o nice= -p $$ | tr -d ' ')"
  if [ "$parent" -ge 19 ]; then
    # `nice` caps at 19, so from a parent already there it provably cannot
    # raise the child and this has nothing to measure. Stated, not silently
    # passed. The self-test driver deliberately stays below 19 for this reason.
    skip "already at niceness $parent; nice(1) cannot raise the child further"
  fi

  run "$GATE" enforce --in-place
  [ "$status" -eq 0 ]
  local child
  child="$(cat "$WORK/niceness")"
  [ "$child" -gt "$parent" ] || {
    echo "the mutation run is not niced: child=$child parent=$parent"
    return 1
  }
}

@test "MUT-47: a cargo-mutants that ignores SIGTERM is still killed" {
  # `--kill-after` is the grace period after the TERM. Without it a tool that
  # traps or ignores SIGTERM is never killed at all, so the bound that stops an
  # interrupted `--in-place` run wedging the job does nothing.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
trap '' TERM
sleep 30
EOF
  chmod +x "$BIN/cargo"
  local start end
  start=$(date +%s)
  MUTATION_GATE_TIMEOUT=1 MUTATION_GATE_KILL_GRACE=1 run "$GATE" enforce --in-place
  end=$(date +%s)
  [ "$status" -ne 0 ]
  # Without --kill-after the sleep runs its full 30s; with it, TERM is ignored,
  # then KILL lands one grace period later and the gate returns promptly. The
  # grace is an env knob so this can assert it in seconds rather than the
  # production minute.
  [ "$((end - start))" -lt 15 ] || {
    echo "the run was not killed after the timeout ($((end - start))s elapsed)"
    return 1
  }
}

@test "MUT-47b: a path with surrounding whitespace is still checked" {
  # `.strip()` before the quote-strip. Without it a `+++` header carrying a
  # trailing space yields a path that does not end in `.rs`, so it silently
  # leaves the checked set — fail-OPEN on the check that catches a diff whose
  # paths do not resolve.
  mk_cargo list_n=4 total=4 caught=4
  printf 'diff --git a/rust/nope.rs b/rust/nope.rs\n--- a/rust/nope.rs\n+++ b/rust/nope.rs \n@@ -1 +1 @@\n-a\n+b\n' >spacey.diff
  run "$GATE" enforce --in-diff spacey.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"path that does not exist relative"* ]]
}

@test "MUT-48: a path merely CONTAINING .rs is not a Rust file" {
  # `endswith(".rs")` -> `".rs" in p`. Under the mutant `docs/x.rs.md` and
  # `src/a.rst` enter the checked set, so an unresolvable path in a docs-only PR
  # hard-fails the gate — a false RED nobody can act on.
  mk_cargo list_n=4 total=4 caught=4
  printf 'diff --git a/docs/x.rs.md b/docs/x.rs.md\n--- a/docs/x.rs.md\n+++ b/docs/x.rs.md\n@@ -1 +1 @@\n-a\n+b\n' >notrust.diff
  run "$GATE" enforce --in-diff notrust.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "MUT-49: only an ATTRIBUTE is a skip, not any line starting with #" {
  # `startswith("#[")` -> `startswith("#")`. rustdoc hides lines in a doc example
  # with a leading `#`, so `/// # use x::mutants::skip;` normalises to a line
  # starting with `#` and containing the path — under the mutant a documented
  # EXAMPLE is judged an unannotated skip.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  cat >src/x.rs <<'RS'
fn documented() {}
# use crate::mutants::skip;
RS
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,2 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "MUT-50: two block comments in one attribute do not evade the policy" {
  # The strip must be NON-greedy. Greedy `/\*.*\*/` spans from the first `/*` to
  # the LAST `*/`, deleting `test, mutants ` along with the comments and leaving
  # `#[cfg_attr(::skip)]` — which no longer contains `mutants::skip`, so the skip
  # walks through unannotated.
  mk_cargo list_n=4 total=4 caught=4
  mkdir -p src
  printf 'use std::fmt;\n#[cfg_attr(/*a*/test, mutants /*b*/:: skip)]\nfn adapter() {}\n' >src/x.rs
  {
    echo 'diff --git a/src/x.rs b/src/x.rs'
    echo '--- /dev/null'
    echo '+++ b/src/x.rs'
    echo '@@ -0,0 +1,3 @@'
    sed 's/^/+/' src/x.rs
  } >skip.diff
  run "$GATE" enforce --in-diff skip.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"ADR-020"* ]]
}

@test "MUT-44: a zero or malformed gate timeout is refused, not silently unbounded" {
  # GNU `timeout 0` means NO timeout. `:-3600 -> :-0` therefore removed the
  # containment while every other check still passed — and the containment is the
  # whole reason an interrupted `--in-place` run does not leave mutated source
  # behind.
  mk_cargo list_n=4 total=4 caught=4
  local bad
  for bad in 0 abc -5 3.5; do
    MUTATION_GATE_TIMEOUT="$bad" run "$GATE" enforce --in-place
    [ "$status" -ne 0 ] || {
      echo "MUTATION_GATE_TIMEOUT='$bad' was accepted"
      return 1
    }
    [[ "$output" == *"positive"* ]] || {
      echo "MUTATION_GATE_TIMEOUT='$bad' gave: $output"
      return 1
    }
    # The KILL grace is the second bound and needs the same guard: `0` there
    # means the SIGKILL never lands, so a tool ignoring SIGTERM runs forever.
    MUTATION_GATE_KILL_GRACE="$bad" run "$GATE" enforce --in-place
    [ "$status" -ne 0 ] || {
      echo "MUTATION_GATE_TIMEOUT='$bad' was accepted"
      return 1
    }
    [[ "$output" == *"positive"* ]] || {
      echo "MUTATION_GATE_TIMEOUT='$bad' gave: $output"
      return 1
    }
  done
}

@test "MUT-45: the rendered counts are the run's own, and survivors are named" {
  # The summary line and the survivor list are the half a human reads. Three
  # mutations of them survived: `${total} tested` -> `${caught} tested`, deleting
  # the `cat missed.txt timeout.txt`, and `extra[:10]` -> `extra[:0]` (unexpected
  # mutants counted but never named, while `unscored:` names were pinned — an
  # asymmetry nothing justified).
  export GITHUB_STEP_SUMMARY="$WORK/summary.md"
  : >"$GITHUB_STEP_SUMMARY"
  mk_cargo list_n=40 total=40 caught=36 missed=3 timeout=1 exit=3
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  # 40 tested, not 36: the count must describe the run, not one of its buckets.
  [[ "$output" == *"mutants: 40 tested, 36 caught, 3 missed, 1 timeout"* ]] || {
    echo "summary line misreports: $output"
    return 1
  }
  # The failure says "see the list above", so there must be a list above.
  [[ "$output" == *"--- surviving mutants ---"* ]]
  [[ "$output" == *"crates/x.rs:1:1: replace a with b"* ]] || {
    echo "the surviving mutants were not listed: $output"
    return 1
  }
  # On the FAIL path the job summary carries die's verdict line, which must
  # itself state the proportion — a reader of the summary alone should not have
  # to open the log to learn how bad it was.
  [[ "$(cat "$GITHUB_STEP_SUMMARY")" == *"**FAIL**"* ]]
  [[ "$(cat "$GITHUB_STEP_SUMMARY")" == *"4 of 40"* ]]
}

@test "MUT-45b: an unexpected mutant is NAMED, not just counted" {
  mk_cargo list_n=3 total=3 caught=3 planned=2 "extra=src/OTHER.rs:9:1: injected"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected: src/OTHER.rs:9:1: injected"* ]] || {
    echo "the unexpected mutant was counted but not named: $output"
    return 1
  }
}

@test "MUT-46: an ABSENT end_time is a partial run, not a completed one" {
  # The completeness argument rests on end_time, and every stub emits the key —
  # so `d.get("end_time")` -> `d.get("end_time", "x")` survived. A cargo-mutants
  # revision that OMITS the key on an interrupted run rather than nulling it
  # would defeat the first of the two independent completeness checks, and the
  # fixture shape made that untestable.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then
    for i in 1 2 3; do echo "src/x.rs:$i:1: replace a with b"; done
    exit 0
  fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 3, "missed": 0, "caught": 3, "timeout": 0, "unviable": 0,
 "outcomes": [{"scenario": "Baseline", "summary": "Success"}]}
JSON
python3 -c "import json; json.dump([{'name': 'src/x.rs:%d:1: replace a with b' % i} for i in range(1,4)], open('mutants.out/mutants.json','w'))"
: >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit 0
EOF
  chmod +x "$BIN/cargo"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-41: an ADDED file with a quoted path is refused, not reported missing" {
  # MUT-33's fixture is a MODIFIED file, so both headers are quoted and the
  # detector's `+++` anchor is unpinned — anchored on `---` instead, the case
  # still passes. For an ADDED file the `---` header is /dev/null, so only the
  # `+++` anchor sees the escape, and without it the gate says "path does not
  # exist" about a path that is really just mis-encoded.
  mk_cargo list_n=4 total=4 caught=4
  printf 'diff --git a/dev/null "b/src/caf\\303\\251.rs"\n--- /dev/null\n+++ "b/src/caf\\303\\251.rs"\n@@ -0,0 +1 @@\n+a\n' >added.diff
  run "$GATE" enforce --in-diff added.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"core.quotePath"* ]]
  [[ "$output" != *"does not exist"* ]]
}
