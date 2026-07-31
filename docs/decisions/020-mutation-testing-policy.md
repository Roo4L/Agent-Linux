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
| nightly | whole workspace, `--shard i/4` for i in 0..3 | warns | `nightly-mutation.yml` |

The per-PR gate is bounded by the diff so its cost is proportional to the
change. The nightly exists because `--in-diff` only ever scores lines someone
edited: a module nobody touches is never re-scored, and its tests can rot
undetected.

### 2. The verdict comes from the results file, never from the exit code

Both call `scripts/mutation-gate.sh`, which reads `mutants.out/outcomes.json`.
A missing outcomes file, or a run that tested **zero** mutants, is a hard
failure **in both modes** — with one narrowly-conditioned exception for a diff
that genuinely had nothing mutable in it, spelled out below. "Nothing survived" and "nothing ran" must not be
representable as the same outcome — that equivalence is the entire bug above.

Corollaries, each of which was a real false-green:

- advisory means *a surviving mutant warns*. It does not mean a broken gate is
  tolerated, so there is no `continue-on-error`.
- an empty `--in-diff` is a legitimate skip (a PR touching no Rust) but is
  named out loud rather than passing silently. So is a non-empty `--in-diff`
  whose lines yield no mutants — a test-only PR, or a manifest edit — because a
  gate that hard-fails on something the contributor cannot fix is how the
  previous one earned its bypass.
- the skip's condition is derived from the TOOL, not from reading the argument
  vector. cargo-mutants exits 0 writing no results file for several reasons — a
  diff with nothing mutable, a `--file` matching nothing, an empty `--shard`, a
  non-resolving `--in-diff` — and, worse, `.cargo/mutants.toml` can narrow the
  set with no argv evidence at all. So the gate asks
  `cargo mutants --no-config --list --in-diff <diff>` what the scope SHOULD
  contain, BEFORE the run, and licenses the skip only when the answer is zero.
  A failed query is fatal, not an empty scope — swallowing it produced
  `expected=0` and skipped past every other check.

  It then compares the two SETS, not their sizes: `mutants.json`'s `name` field
  is byte-identical to a `--list` line. Sizes were not enough — `--error VALUE`
  (and `error_values` in the config) ADDS a mutant per Result-returning fn, so
  one knob could hide the survivors and a second refill the count. Anything
  scored that is not in the expectation fails in both modes. Anything expected
  but unscored fails in ENFORCE mode, and is reported as partial coverage in
  ADVISORY mode — which is what makes the nightly's `--shard` legal (§1, §3):
  each runner scores a slice and the four together cover the workspace. That
  asymmetry is the only place narrowing is tolerated, and only because advisory
  is a warning.

  Finally `caught + missed + timeout + unviable == total`, so a `--check` run —
  which builds mutants without testing any — cannot report a score.

- the run must have established a **baseline**. This closed the last
  demonstrated way to render "nothing ran" as "nothing survived":

  ```
  $ mutation-gate.sh enforce --baseline skip     # with a failing test suite
  mutation gate (enforce): PASS — every mutant was caught.
  ```

  A test command that always fails marks every mutant killed. `end_time` is set,
  `planned == total`, the sets match exactly, accounting balances, `unviable` is
  zero — every other check above passes on a tree where NO test passes. And
  `--baseline skip` is a plausible edit, not a contrived one: `--in-place` makes
  the per-PR run serial and re-runs the baseline every time, so skipping it is
  the obvious way to speed up a gate §5 already admits is close to its cap.

  The discriminator was already in the file being parsed. A normal run records a
  `"Baseline"` scenario with summary `Success`; `--baseline skip` records no
  Baseline entry at all. Both are pinned against the tool by MUT-14, not
  assumed.

  Three earlier revisions tried to decide this by inspecting arguments: a
  denylist of filter flags, then an allowlist of benign ones. Both are
  hand-copies of clap's grammar; the denylist leaked eleven spellings, the
  allowlist blessed flags that do not exist while rejecting real ones, and
  neither could ever see the config file. Delegating to the tool needs no model
  of its grammar and survives flags it has not shipped yet.

The gate script has its own bats suite (`tests/bats/80-mutation-gate.bats`).
Testing the thing that judges the tests is not ceremony here: an untested gate
is precisely what failed.

**And the suite is measured the same way it measures everything else.** A case
count says nothing — an early revision had 29 cases and, when 21 single-token
mutations were applied to the gate, killed 6. The whole advisory reporting path,
one of the two "independent completeness checks", and `--no-config` (the flag the
entire redesign rests on) were asserted by nothing. The number to report when
changing this gate is **its own mutation score**, produced by mutating
`scripts/mutation-gate.sh` and running its suite. It currently stands at 32/32.

Two patterns caused most of those survivors, and both are worth naming because
they recur:

- **stubs co-blind with the code.** Every stub answered `--list` by matching the
  flag alone and recorded nothing about the rest of argv, so no case could see
  `--no-config` disappear — a fixture modelling the gate's assumption instead of
  the tool's behaviour. Stubs now log every invocation's argv and answer `--list`
  differently with and without `--no-config`.
- **one fixture tripping two checks.** `stub_cargo_interrupted` set `end_time` to
  null AND sized `mutants.json` by the reached count, so the one case covering
  "the run did not finish" held with either check deleted — the independence the
  script claims was asserted by nothing. Each now has a case that isolates it.

### 3. `--in-place` is required, and therefore `--shard`, not `--jobs`

Two `agentlinux-core` tests read fixtures under `plugin/catalog/`, outside the
`rust/` workspace, so `cargo-mutants`' default copy-tree isolation fails the
baseline. `--in-place` fixes that and is safe on a disposable runner, but it
forbids `--jobs`. `--shard i/N` is compatible, so the nightly parallelises across
runners instead of threads. Shards are ZERO-indexed — cargo-mutants rejects
`k/n` unless `k < n`, and a matrix of `[1,2,3,4]` both red-lined one runner
nightly and left shard 0's quarter of the workspace unscored. MUT-20 loops the
workflow's own matrix values through the tool so that cannot recur.

Vendoring those two fixtures inside the workspace would remove the constraint.
Not done: the fixtures are the live catalog, and a copy would need its own
drift check — trading a CI flag constraint for a new invariant to maintain.

### 4. When a mutant may survive

Two escape hatches, both requiring a written reason at the site:

- **`#[mutants::skip]`** on a function whose mutants are unobservable — e.g.
  `TmpGuard::disarm`, where skipping the disarm makes `Drop` unlink a path the
  rename already consumed, a no-op no test can distinguish. Four of these exist,
  all in `sysio.rs`, each with a comment. (The other three skips in the tree —
  `detect.rs`, `cmd/install.rs`, `cmd/provision.rs` — belong to the third case
  below, not this one.)
- **A documented equivalent mutant**, where the mutated code has the same
  observable behavior. `detect_gates::reuse_gate`'s gate 1 (reject an empty
  compatibility window) is the example: `satisfies(v, "")` is already false for
  every `v`, so deleting the gate changes no verdict. The gate stays because it
  states the rule where a reader looks for it; the comment records why it cannot
  be killed.

Neither hatch may be used to silence a mutant that survives because the test is
weak. That is the finding, not the noise.

**Why the written reason is enforced mechanically.** `#[mutants::skip]` is the
only narrowing channel §2's tool-derived expectation is blind to. A skipped
function is absent from `--list` AND from `mutants.json`, so both sets shrink
together, they still match, and the gate reports PASS. In the enforcing per-PR
gate that makes it self-licensing: an author facing a red mutant can grant the
exemption inside the very diff being scored. So when a `--in-diff` is given, the
gate refuses any file whose diff ADDS a skip line if any skip in that file has no
comment on the three lines above it (`scripts/mutation-gate.sh`'s `check_diff`, MUT-21).

Deliberately a shape check, not a judgement. It makes an *unannotated* skip
unmergeable; whether the stated reason is any good — and whether it carries the
ADR-019 §5 back-reference the third case below requires — stays with the
reviewer. It is scoped to files the diff adds a skip to, so a PR is never
answerable for an exemption somebody else took.

Recognising the attribute is the one place this gate models Rust, and a plain
`"mutants::skip" in line` was not enough. Rust tolerates whitespace and comments
around `::`, cargo-mutants resolves the attribute through `syn` rather than
textually, and `#[cfg_attr(test, mutants :: skip)]` suppresses every mutant of
the function — so one extra space bought the whole exemption back, in a spelling
that looks *more* idiomatic to a reviewer skimming the diff. The line is now
normalised (block comments dropped, whitespace removed) and must be an
attribute. §2 rules out hand-copied grammars after the argv denylist leaked
eleven flag spellings; this one is knowingly small, and the difference is that
clap's flag grammar is large and grows every release, while "optional whitespace
or a block comment around `::`" is closed and has not changed since Rust 1.0.
Requiring `#[` is also what keeps a `//` comment that merely *mentions* the
attribute — every justification comment does — from being read as a skip.

**Third case, added after the gate went enforcing.** ADR-019 §5 records modules
that are deliberately unseamed. The enforcing per-PR gate covers the whole
workspace, so a PR touching a line in one of them meets a red gate on a mutant
no writable test could kill — and the contributor's only exits are "build the
seam" (correct, but unscoped in their PR) or "reach for `#[mutants::skip]`",
which the paragraph above forbids. The collision is real: `cargo mutants --list`
puts tens of mutants in `nodejs`, `agent_user` and the purge/report paths.

So a mutant may also be skipped when it is **structurally unreachable pending a
recorded seam gap**, on one condition: the `#[mutants::skip]` carries a
back-reference to the ADR-019 §5 entry explaining why. That keeps the hatch
auditable — `grep -c 'ADR-019 §5'` is the size of the debt — and makes closing
the gap delete the skips rather than leave them behind. A skip with no
back-reference is still a finding.

The interaction is smaller than that count suggests: `provision_with`
(ADR-019 §3b) made the orchestrator's phases injectable, so most of
`cmd/provision`'s share became killable.

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
