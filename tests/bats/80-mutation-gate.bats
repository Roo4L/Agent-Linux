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
# The gate first asks the tool what this scope SHOULD contain, via
# \`--list\`. Answer with total_mutants lines so the expectation matches.
for a in "\$@"; do
  if [ "\$a" = "--list" ]; then
    for i in \$(seq 1 $1); do echo "src/x.rs:\$i:1: replace a with b"; done
    exit 0
  fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<JSON
{"total_mutants": $1, "missed": $2, "caught": $3, "timeout": $4,
 "unviable": $unviable, "end_time": "2026-07-31T00:00:00Z"}
JSON
python3 -c "import json; json.dump([{'name': 'src/x.rs:%d:1: replace a with b' % i} for i in range(1, $1 + 1)], open('mutants.out/mutants.json','w'))"
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
for a in "\$@"; do
  if [ "\$a" = "--list" ]; then
    for i in \$(seq 1 $2); do echo "src/x.rs:\$i:1: replace a with b"; done
    exit 0
  fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<JSON
{"total_mutants": $1, "missed": 0, "caught": $1, "timeout": 0,
 "unviable": 0, "end_time": null}
JSON
python3 -c "import json; json.dump([{'name': 'src/x.rs:%d:1: replace a with b' % i} for i in range(1, $1 + 1)], open('mutants.out/mutants.json','w'))"
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
# --list prints nothing: the scope genuinely contains no mutants.
for a in "$@"; do
  if [ "$a" = "--list" ]; then exit 0; fi
done
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
for a in "$@"; do
  if [ "$a" = "--list" ]; then
    echo "src/x.rs:1:1: replace a with b"
    exit 0
  fi
done
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
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then
    for i in 1 2 3 4 5 6 7 8 9 10; do echo "src/x.rs:$i:1: replace a with b"; done
    exit 0
  fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 5, "missed": 0, "caught": 5, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
JSON
python3 -c "import json; json.dump([{'name': 'src/x.rs:%d:1: replace a with b' % i} for i in range(1, 6)], open('mutants.out/mutants.json','w'))"
: >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit 0
EOF
  chmod +x "$BIN/cargo"
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
{"total_mutants": 3, "missed": 0, "caught": 3, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
JSON
python3 -c "import json; json.dump([{'name': 'src/x.rs:1:1: replace a with b'}, {'name': 'src/x.rs:2:1: replace a with b'}, {'name': 'src/OTHER.rs:9:1: injected'}], open('mutants.out/mutants.json','w'))"
: >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit 0
EOF
  chmod +x "$BIN/cargo"
  run "$GATE" enforce
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not contain"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MUT-05b: every mutant must land in a bucket" {
  # `--check` builds each mutant without testing it, leaving all four counters
  # at 0 against a non-zero total — so the gate printed "0 caught" and "every
  # mutant was caught" on consecutive lines.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then
    for i in 1 2 3 4 5; do echo "src/x.rs:$i:1: replace a with b"; done
    exit 0
  fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 5, "missed": 0, "caught": 0, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
JSON
python3 -c "import json; json.dump([{'name': 'src/x.rs:%d:1: replace a with b' % i} for i in range(1, 6)], open('mutants.out/mutants.json','w'))"
: >mutants.out/missed.txt
: >mutants.out/timeout.txt
exit 0
EOF
  chmod +x "$BIN/cargo"
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
  [[ "$output" == *"does not exist relative to"* ]]
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
    [[ "$output" == *"does not exist relative to"* ]]
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
  command -v cargo >/dev/null && cargo mutants --version >/dev/null 2>&1 || {
    if [ -n "${CI:-}" ]; then
      echo "cargo-mutants must be installed in CI to check the shard matrix" >&2
      return 1
    fi
    skip "cargo-mutants not installed (required in CI)"
  }

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
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
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
  # total_mutants, so it walks past both completeness checks and only breaks in
  # the set comparison. That is the one shape that reaches the second reader's
  # guard — MUT-22's truncated file dies at the first one, so without this case
  # the guard is asserted by nothing.
  cat >"$BIN/cargo" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "--list" ]; then echo "src/x.rs:1:1: replace a with b"; exit 0; fi
done
mkdir -p mutants.out
cat >mutants.out/outcomes.json <<'JSON'
{"total_mutants": 1, "missed": 0, "caught": 1, "timeout": 0,
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
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
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
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
 "unviable": 0, "end_time": "2026-07-31T00:00:00Z"}
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

  [ -s "$GITHUB_STEP_SUMMARY" ]
  while IFS= read -r line; do
    [[ "$line" == *PASS* || "$line" == *FAIL* || "$line" == *WARN* || "$line" == *SKIPPED* ]] ||
      { echo "job-summary line has no verdict: $line"; return 1; }
  done <"$GITHUB_STEP_SUMMARY"
  # …and one line per invocation, so none of them silently wrote nothing.
  [ "$(grep -c . "$GITHUB_STEP_SUMMARY")" -eq 5 ]
}
