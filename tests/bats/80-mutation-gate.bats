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

# Stub `cargo` so `cargo mutants …` leaves the outcomes file a real run leaves.
# $1 total, $2 missed, $3 caught, $4 timeout, $5 exit code, [$6 unviable]
# Writes the shape a COMPLETED run leaves: end_time set, and mutants.json
# listing exactly total_mutants entries.
stub_cargo_outcomes() {
  local unviable="${6:-0}"
  cat >"$BIN/cargo" <<EOF
#!/usr/bin/env bash
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<JSON
{"total_mutants": $1, "missed": $2, "caught": $3, "timeout": $4,
 "unviable": $unviable, "end_time": "2026-07-31T00:00:00Z"}
JSON
python3 -c "import json,sys; json.dump([{}]*$1, open('mutants.out/mutants.json','w'))"
printf 'crates/x.rs:1:1: replace a with b\n' >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit $5
EOF
  chmod +x "$BIN/cargo"
}

# A run KILLED partway: cargo-mutants rewrites outcomes.json after every
# scenario, so the file is well-formed and describes only what it reached —
# but end_time is null and mutants.json still lists the full planned set.
# $1 reached, $2 planned, $3 exit code
stub_cargo_interrupted() {
  cat >"$BIN/cargo" <<EOF
#!/usr/bin/env bash
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<JSON
{"total_mutants": $1, "missed": 0, "caught": $1, "timeout": 0,
 "unviable": 0, "end_time": null}
JSON
python3 -c "import json,sys; json.dump([{}]*$2, open('mutants.out/mutants.json','w'))"
: >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit $3
EOF
  chmod +x "$BIN/cargo"
}

# A run that exits 0 writing NO outcomes.json — the shape cargo-mutants really
# produces when a filter matches nothing (a non-resolving --in-diff, an empty
# --shard, --file matching nothing, --list). MUT-05's stub writes an
# outcomes.json with total_mutants:0, which the real tool never does.
stub_cargo_zero_mutants() {
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
echo " INFO No mutants to filter"
exit 0
EOF
  chmod +x "$BIN/cargo"
}

# Stub `cargo` so it fails WITHOUT producing outcomes — the real failure mode:
# a rejected flag combination.
stub_cargo_rejects_flags() {
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
echo "error: the argument '--in-place' cannot be used with '--jobs <JOBS>'" >&2
exit 1
EOF
  chmod +x "$BIN/cargo"
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
  [[ "$output" == *"3 mutant(s) survived"* ]]
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

@test "MUT-05: testing zero mutants is never a pass" {
  # The --in-diff --relative path-rewriting bug: the filter matches nothing,
  # cargo-mutants exits 0, and every PR sails through.
  stub_cargo_outcomes 0 0 0 0 0
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"0 mutants"* ]]

  run "$GATE" advisory
  [ "$status" -ne 0 ]
}

@test "MUT-06: a timed-out mutant counts as surviving, not as caught" {
  stub_cargo_outcomes 40 0 39 1 0
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 mutant(s) survived"* ]]
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
  # Required in CI, where the pin is what it is testing. Skipped locally when
  # cargo-mutants is not installed — stated rather than silent.
  if ! command -v cargo >/dev/null || ! cargo mutants --version >/dev/null 2>&1; then
    if [ -n "${CI:-}" ]; then
      echo "cargo-mutants must be installed in CI — the gate's contract is untested without it" >&2
      return 1
    fi
    skip "cargo-mutants not installed (required in CI, optional locally)"
  fi

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
assert len(json.load(open('mutants.out/mutants.json'))) == d['total_mutants'], \
    'mutants.json length must equal total_mutants for the completeness check'
print('contract OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"contract OK"* ]]
}

@test "MUT-15: a zero-mutant run only skips when an --in-diff explains it" {
  # The real tool exits 0 writing nothing whenever a filter matches nothing.
  # Treating that status alone as "the diff had no mutable lines" turned the
  # canonical missing---relative bug into a permanent green on the ENFORCING
  # gate. Without an --in-diff there is no diff to blame, so it must fail.
  stub_cargo_zero_mutants
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete a run"* ]]

  # The nightly shape: --shard, no --in-diff. An empty shard must not read as
  # "nothing in the diff" — there is no diff.
  run "$GATE" advisory --shard 99/100
  [ "$status" -ne 0 ]
  [[ "$output" != *"no mutants in diff"* ]]
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
  [[ "$output" == *"no mutants"* ]]
}

@test "MUT-17: an --in-diff whose paths do not resolve is a hard failure" {
  # The missing---relative class: cargo-mutants matches --in-diff against the
  # WORKSPACE root, so repo-root-relative paths match nothing and exit 0.
  stub_cargo_zero_mutants
  printf 'diff --git a/rust/crates/c/src/lib.rs b/rust/crates/c/src/lib.rs\n--- a/rust/crates/c/src/lib.rs\n+++ b/rust/crates/c/src/lib.rs\n@@ -1 +1 @@\n-x\n+y\n' >unresolved.diff
  run "$GATE" enforce --in-diff unresolved.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist relative to"* ]]
}

@test "MUT-18: --in-diff paired with any other filter cannot license the skip" {
  # A second filter can empty the mutant set for a diff that is full of uncaught
  # mutants, producing the same "exit 0, no results file" as an honest
  # nothing-to-mutate run. Enumerating the flagless shapes closed instances;
  # this closes the class. test.yml's own comment advises sharding this gate for
  # a large diff, which would otherwise walk straight into it.
  stub_cargo_zero_mutants
  mkdir -p crates/c/src
  printf 'pub fn f() {}\n' >crates/c/src/lib.rs
  printf 'diff --git a/crates/c/src/lib.rs b/crates/c/src/lib.rs\n--- a/crates/c/src/lib.rs\n+++ b/crates/c/src/lib.rs\n@@ -1 +1 @@\n-x\n+y\n' >d.diff

  for extra in "--file crates/zzz/**" "--exclude crates/c/**" "--shard 99/100"; do
    # shellcheck disable=SC2086
    run "$GATE" enforce --in-diff d.diff $extra
    [ "$status" -ne 0 ] || {
      echo "BYPASS via $extra"
      return 1
    }
  done

  # --list can never produce a score, so it is refused outright.
  run "$GATE" enforce --in-diff d.diff --list
  [ "$status" -ne 0 ]

  # …and --in-diff alone still skips.
  run "$GATE" enforce --in-diff d.diff
  [ "$status" -eq 0 ]
}

@test "MUT-19: a file that is not a diff is never treated as verified" {
  # The path check only fires on lines it recognises, so anything it cannot
  # parse — diff.noprefix, custom srcPrefix, CRLF, a space in a path, --stat
  # output, plain garbage — used to be waved through as "no .rs paths to check".
  stub_cargo_zero_mutants
  printf 'this is not a diff\n' >garbage.diff
  run "$GATE" enforce --in-diff garbage.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"not"*"diff"* ]]

  # A real diff shape the old regex could not parse, naming a path that does
  # not resolve, must still be caught.
  printf 'diff --git nope/x.rs nope/x.rs\n--- nope/x.rs\n+++ nope/x.rs\n@@ -1 +1 @@\n-x\n+y\n' >noprefix.diff
  run "$GATE" enforce --in-diff noprefix.diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist relative to"* ]]
}
