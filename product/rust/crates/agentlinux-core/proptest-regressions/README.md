# proptest regression seeds (TEST-01)

This directory is **committed on purpose**. When a `proptest!` property in
`agentlinux-core` (P1–P4 + the `reuse` totality property) discovers a failing
input, proptest writes the failing seed to a `*.txt` file here. Committing those
seeds makes the counterexample **replay on every future `cargo test` run**, so a
regression can never silently re-open (threat T-54-02).

- **Do NOT gitignore this directory.** `.gitignore` ignores only the
  `cargo-mutants` scratch (`rust/**/mutants.out`), never `proptest-regressions/`.
- It is currently empty of seeds because every property passes today. The
  directory itself is tracked (via this file) so the first discovered
  counterexample lands in a git-tracked location rather than an untracked one a
  contributor might overlook.
- Seed files are named `<module>.txt` (e.g. `classify.txt`) and are managed by
  proptest — do not hand-edit them; add new failing seeds by letting a failing
  test run persist them, then commit.

See `.planning/phases/54-testing-bedrock/54-RESEARCH.md` §"proptest hygiene".
