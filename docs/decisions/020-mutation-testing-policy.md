# 020: Mutation-testing policy — an enforcing per-PR gate, an advisory nightly, and what may be skipped

**Status:** Accepted
**Date:** 2026-07-31

## Context

The bats suite is the behavior spec (ADR-002), and it is good at proving a
behavior exists. It is poor at proving a *test* would notice if the behavior
stopped. The Rust cutover made that gap visible: tests were added alongside the
port that asserted a literal against itself, or re-derived the value under test
inside the test body, and every one of them passed.

Mutation testing is the check that catches that class directly — it changes the
production code and asks whether anything fails. The project already ran
`cargo-mutants`, but the gate had a defect worse than not having one:

```
cargo mutants --minimum-test-timeout 20 --in-place --jobs 4 \
  || echo "::warning::surviving mutants (nightly full-workspace advisory)"
```

`cargo-mutants` rejects that flag pair outright (`--in-place` cannot be used
with `--jobs`). The `||` converted the usage error to success, `continue-on-error:
true` kept the job green, and the warning text read like a real finding. Every
night reported a mutation score for a run that generated zero mutants.

## Decision

### 1. Two gates, different jobs

| | scope | verdict on a survivor | where |
|---|---|---|---|
| per-PR | lines the diff touches (`--in-diff`) | **fails the merge** | `test.yml` |
| nightly | whole workspace, `--shard i/4` | warns | `nightly-mutation.yml` |

The per-PR gate is bounded by the diff so its cost is proportional to the
change. The nightly exists because `--in-diff` only ever scores lines someone
edited: a module nobody touches is never re-scored, and its tests can rot
undetected.

### 2. The verdict comes from the results file, never from the exit code

Both call `scripts/mutation-gate.sh`, which reads `mutants.out/outcomes.json`.
A missing outcomes file, or a run that tested **zero** mutants, is a hard
failure **in both modes**. "Nothing survived" and "nothing ran" must not be
representable as the same outcome — that equivalence is the entire bug above.

Corollaries, each of which was a real false-green:

- advisory means *a surviving mutant warns*. It does not mean a broken gate is
  tolerated, so there is no `continue-on-error`.
- an empty `--in-diff` is a legitimate skip (a PR touching no Rust) but is
  named out loud rather than passing silently.
- the diff is written to a file under `set -euo pipefail`, not passed via
  `<(git diff …)`, because process substitution discards git's exit status and a
  bad pathspec then yields an empty diff and a green gate.

The gate script has its own bats suite (`tests/bats/80-mutation-gate.bats`).
Testing the thing that judges the tests is not ceremony here: an untested gate
is precisely what failed.

### 3. `--in-place` is required, and therefore `--shard`, not `--jobs`

Two `agentlinux-core` tests read fixtures under `plugin/catalog/`, outside the
`rust/` workspace, so `cargo-mutants`' default copy-tree isolation fails the
baseline. `--in-place` fixes that and is safe on a disposable runner, but it
forbids `--jobs`. `--shard i/N` is compatible, so the nightly parallelises across
runners instead of threads.

Vendoring those two fixtures inside the workspace would remove the constraint.
Not done: the fixtures are the live catalog, and a copy would need its own
drift check — trading a CI flag constraint for a new invariant to maintain.

### 4. When a mutant may survive

Two escape hatches, both requiring a written reason at the site:

- **`#[mutants::skip]`** on a function whose mutants are unobservable — e.g.
  `TmpGuard::disarm`, where skipping the disarm makes `Drop` unlink a path the
  rename already consumed, a no-op no test can distinguish. Four exist, each
  with a comment.
- **A documented equivalent mutant**, where the mutated code has the same
  observable behavior. `detect_gates::reuse_gate`'s gate 1 (reject an empty
  compatibility window) is the example: `satisfies(v, "")` is already false for
  every `v`, so deleting the gate changes no verdict. The gate stays because it
  states the rule where a reader looks for it; the comment records why it cannot
  be killed.

Neither hatch may be used to silence a mutant that survives because the test is
weak. That is the finding, not the noise.

### 5. The cost, stated honestly

`--in-place` means the per-PR run is serial. At roughly 6 seconds per mutant a
normal PR (one bin file, 10–35 mutants) costs 1–3 minutes. A PR whose diff is
the whole workspace — the Rust cutover itself — produces ~1000 mutants and will
exceed the job's cap. The answer for that merge is to shard it like the nightly,
**not** to narrow the gate's scope back to the pure crate. The bin crate is where
every `sudo`, `chown`, `useradd` and file-mode decision lives, and while the gate
skipped it, delete-the-function mutants survived on `install_or_overwrite`,
`resolve_argv` and `visudo_validate`.

## Consequences

- A PR that adds a test which cannot fail is caught mechanically rather than by
  a reviewer noticing.
- Repairing the gate immediately paid: the first real run found two surviving
  mutants in `time.rs`, on an arm of Hinnant's civil-from-days that is
  unreachable for `u64` input. Dead code, removed.
- CI spends minutes it did not before. Accepted; the alternative is a green
  check that means nothing.
- Reviewers can rely on `#[mutants::skip]` and documented-equivalent comments as
  deliberate, and should treat an undocumented survivor as a finding.

## References

- ADR-002 — behavior contract framing; bats remains the spec, this is the check on the checkers
- ADR-019 — the provisioner seams that make the bin crate mutable-and-testable at all
- `scripts/mutation-gate.sh`, `tests/bats/80-mutation-gate.bats`
