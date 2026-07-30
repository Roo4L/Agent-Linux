#!/usr/bin/env bats
# TST-06: mutation-testing harness scaffolded.
# Post-cutover (v0.4.0): mutation testing is cargo-mutants on the Rust workspace
# (the TS stryker + the bash-mutator.sh advisory scaffold were removed with the
# legacy implementation). Two surfaces: a gating --in-diff run in test.yml's rust
# job, and a full-crate advisory (continue-on-error) score in nightly-mutation.yml.

@test "TST-06: test.yml rust job runs a cargo-mutants gate" {
  grep -q "cargo-mutants" .github/workflows/test.yml
}

@test "TST-06: cargo-mutants is pinned (reproducible gate)" {
  grep -qE "cargo-mutants" .github/workflows/test.yml
  grep -qE "version [0-9]+\.[0-9]+\.[0-9]+ cargo-mutants|--version [0-9]" .github/workflows/test.yml
}

@test "TST-06: nightly-mutation runs the full-crate rust-mutants score" {
  grep -q "rust-mutants" .github/workflows/nightly-mutation.yml
}

@test "TST-06: nightly rust-mutants job is advisory (continue-on-error)" {
  grep -q "continue-on-error: true" .github/workflows/nightly-mutation.yml
}

@test "TST-06: tests/mutation/README.md explains advisory status" {
  [ -f tests/mutation/README.md ]
  grep -qi "advisory" tests/mutation/README.md
}
