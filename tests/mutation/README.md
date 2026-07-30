# Mutation Testing — AgentLinux

Mutation testing introduces small intentional faults into the source (mutants) and
verifies the test suite catches each one. Mutation score (mutants killed / mutants
generated) is the **truth-meter** for test quality — it distinguishes tests that
assert real behavior from tests that merely execute lines.

## Scope

Post-cutover (v0.4.0), the registry CLI + provisioner are the Rust workspace under
`rust/`, so mutation testing is [`cargo-mutants`](https://mutants.rs/) on the Rust
crates. The legacy TypeScript `stryker` job and the in-house `bash-mutator.sh`
scaffold were removed with `plugin/cli/` + the Bash provisioner. The `~25` per-agent
recipes under `plugin/catalog/agents/` stay Bash (irreducible npm/apt/curl glue) and
are covered by the bats behavior suite, not mutation-tested.

| Target | Tool | Where |
|--------|------|-------|
| `rust/crates/agentlinux-core` (pure logic) + `rust/crates/agentlinux` | [`cargo-mutants`](https://mutants.rs/) (pinned) | gating `--in-diff` step in `test.yml`'s `rust` job; full-crate advisory score in `nightly-mutation.yml` |

## Two surfaces

- **Gating (per-PR):** `test.yml`'s `rust` job runs `cargo-mutants --in-diff` over the
  changed Rust lines — a zero-survivor gate scoped to the diff, so a PR that adds
  untested logic fails. See `.github/workflows/test.yml`.
- **Advisory (nightly):** `.github/workflows/nightly-mutation.yml`'s `rust-mutants`
  job runs the full-crate score `continue-on-error: true` — a regression opens a
  follow-up, not a release blocker.

## Run locally

```bash
cd rust
cargo install --locked --version 27.1.0 cargo-mutants   # pinned, matches CI
# full-crate score:
cargo mutants
# diff-scoped (what the PR gate runs), from the repo root:
cargo mutants --in-diff <(git diff origin/master...HEAD -- rust/) --relative
```

`cargo-mutants` restores the tree after each run. A clean diff yields "no mutants
to test" and exits 0.
