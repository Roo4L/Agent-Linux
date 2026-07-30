---
phase: 54-testing-bedrock
plan: 03
subsystem: testing
tags: [ci, cargo-mutants, mutation-testing, github-actions, rust, testing-bedrock]

# Dependency graph
requires:
  - phase: 54-01
    provides: "pure agentlinux-core crate + rust-toolchain + gated rust job in test.yml"
  - phase: 54-02
    provides: "schemars catalog schema codegen (schema_gen.rs drift-check test) + semver parity test that read plugin/catalog/*"
provides:
  - "Per-PR cargo-mutants GATE on agentlinux-core (--in-diff, zero un-skipped survivors) inside the existing gated rust job"
  - "Nightly full-crate cargo-mutants score on agentlinux-core (advisory) in nightly-mutation.yml"
  - "W1: rust-job fetch-depth: 0 + origin/master diff-base assertion so --in-diff cannot silently no-op"
  - "Documented cargo-mutants invocation contract for the pure crate (--in-place + --relative) that later ports (55-57) inherit"
affects: [55-provisioner-port, 56-cli-verbs, 57-canonical-paths, phase-59-release-gate]

# Tech tracking
tech-stack:
  added: ["cargo-mutants 27.1.0 (CI-installed subcommand, pinned + --locked)"]
  patterns:
    - "Mutation gate reuses the existing rust-job guard (steps.guard.outputs.ready) so GATE-05 holds for free"
    - "Per-PR --in-diff gate (bounded, enforcing) + full-crate nightly score (advisory) split"
    - "cargo mutants --in-place for crates whose tests read out-of-workspace sibling files"

key-files:
  created: []
  modified:
    - ".github/workflows/test.yml — rust job: fetch-depth 0 + diff-base assertion + pinned cargo-mutants install + guarded --in-diff gate"
    - ".github/workflows/nightly-mutation.yml — new advisory rust-mutants job (full-crate score)"

key-decisions:
  - "Landed the per-PR mutation gate as an ENFORCING gate this phase (zero un-skipped survivors on --in-diff), not left advisory — per the resolved decision, encoded as normal CI config, no human-decide checkpoint"
  - "cargo mutants runs --in-place in CI: two agentlinux-core tests read ../../../plugin/catalog/* (outside the rust/ workspace), which breaks the default copy-tree isolation baseline"
  - "The --in-diff diff is generated with git diff --relative so paths match the workspace root — without it the gate silently reports 'No mutants to filter' and passes every PR (false-green)"
  - "Full-crate score is nightly + advisory (continue-on-error like stryker/bash-mutator); the merge-blocking gate is the bounded per-PR --in-diff step"

patterns-established:
  - "Pattern: pin CI mutation tooling (cargo install --locked --version 27.1.0) so a silent upstream bump can't change the mutation set mid-milestone (T-54-SC)"
  - "Pattern: floor per-mutant timeout (--minimum-test-timeout 20) so an infinite-loop mutant is killed under the job's 15-min cap (T-54-06), never hangs the runner"

requirements-completed: [TEST-02, GATE-05, GATE-01]

coverage:
  - id: D1
    description: "Per-PR cargo-mutants gate on agentlinux-core (--in-diff, zero un-skipped survivors), pinned + guarded inside the rust job"
    requirement: "TEST-02"
    verification:
      - kind: automated
        ref: "python3 -c yaml assert: rust job has pinned(27.1.0) install + --in-diff mutants step, both behind steps.guard.outputs.ready, no ::warning:: bypass"
        status: pass
      - kind: integration
        ref: "local: cargo mutants --package agentlinux-core --minimum-test-timeout 20 --in-place --in-diff <(git diff --relative origin/master...HEAD -- crates/agentlinux-core/src/reuse.rs) -> 10 tested, 9 caught, 1 unviable, 0 survived, exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Nightly full-crate cargo-mutants score on agentlinux-core (advisory, guarded on rust/ presence)"
    requirement: "TEST-02"
    verification:
      - kind: automated
        ref: "python3 -c yaml assert: nightly-mutation.yml rust-mutants job runs full-crate agentlinux-core score, continue-on-error: true, guarded on rust/Cargo.toml, no --in-diff"
        status: pass
    human_judgment: false
  - id: D3
    description: "GATE-05: mutation steps behind the rust-job guard so a red Rust run never blocks a non-Rust master hotfix"
    requirement: "GATE-05"
    verification:
      - kind: automated
        ref: "python3 -c yaml assert: both mutants steps carry if: steps.guard.outputs.ready == 'true'"
        status: pass
    human_judgment: false
  - id: D4
    description: "W1: --in-diff diff base (origin/master) is guaranteed resolvable (fetch-depth: 0 + explicit fetch + merge-base assertion) so the gate cannot silently no-op on a real PR"
    requirement: "TEST-02"
    verification:
      - kind: automated
        ref: "python3 -c yaml assert: rust checkout fetch-depth: 0 AND a step asserts origin/master resolves + merge-base exists (FAIL on absence)"
        status: pass
    human_judgment: false
  - id: D5
    description: "GATE-01: change is CI-YAML-only; workspace tests stay green, no bats/ajv path touched"
    requirement: "GATE-01"
    verification:
      - kind: unit
        ref: "cargo test --workspace -> 58 passed; 0 failed"
        status: pass
    human_judgment: false

# Metrics
duration: 44min
completed: 2026-07-28
status: complete
---

# Phase 54 Plan 03: cargo-mutants Mutation Gate Summary

**An enforcing per-PR `cargo-mutants --in-diff` gate on the pure agentlinux-core crate (zero un-skipped survivors, pinned 27.1.0, behind the rust-job guard) plus an advisory full-crate nightly score — with the diff base made resolvable (W1) and two silent-failure bugs in the invocation fixed and proven locally.**

## Performance

- **Duration:** ~44 min
- **Started:** 2026-07-28T07:30:00Z (approx)
- **Completed:** 2026-07-28T08:14:00Z
- **Tasks:** 2 (+ 1 deviation-fix commit)
- **Files modified:** 2

## Accomplishments
- **TEST-02 per-PR gate (enforcing):** the existing `rust` job in `test.yml` now installs pinned `cargo-mutants 27.1.0 --locked` and runs `cargo mutants --package agentlinux-core --minimum-test-timeout 20 --in-place --in-diff <diff>` as a merge-blocking gate — a surviving un-skipped mutant fails the step (no `|| echo ::warning::` bypass).
- **TEST-02 nightly full-crate score:** a new advisory `rust-mutants` job in `nightly-mutation.yml` runs the full-crate `cargo mutants --package agentlinux-core --minimum-test-timeout 20 --in-place` (continue-on-error, guarded on `rust/` presence) — reports out-of-band without blocking.
- **GATE-05:** both mutation steps sit behind `if: steps.guard.outputs.ready == 'true'` (the existing rust-job guard, `ready=false` when no code changed or `rust/Cargo.toml` absent) — a red Rust run can never block a non-Rust master hotfix.
- **W1 (plan-checker flagged, REQUIRED):** the rust-job checkout is now `fetch-depth: 0` with an explicit `git fetch origin master` + a `merge-base` assertion step that FAILS loudly if the diff base is missing — the `--in-diff` gate can no longer silently no-op on a real PR.
- **Local demo (bounded):** proved the gate mechanics end-to-end on a single well-tested file — `reuse.rs` diff → **10 mutants tested, 9 caught, 1 unviable, 0 survived, exit 0** (existing wave-1/2a tests kill every viable mutant).

## Task Commits

1. **Task 1: guarded pinned --in-diff mutants gate (+ W1 fix)** — `4121740` (ci)
2. **Task 2: nightly full-crate rust-mutants job** — `d5545ad` (ci)
3. **Deviation fix: --in-place + --relative (Rule 3 blocking)** — `d6f09c8` (fix)

**Plan metadata:** committed with this SUMMARY (docs).

## Files Created/Modified
- `.github/workflows/test.yml` — rust job: `fetch-depth: 0`; a diff-base assertion step; a pinned `cargo install --locked --version 27.1.0 cargo-mutants` step; and the guarded `--in-place --in-diff` mutation gate — all behind `steps.guard.outputs.ready`.
- `.github/workflows/nightly-mutation.yml` — new `rust-mutants` job: advisory (continue-on-error), guarded on `rust/Cargo.toml`, installs the pinned toolchain + cargo-mutants, runs the full-crate `--in-place` score.

## Decisions Made
- **Gate now, not later.** Per the resolved decision the per-PR mutation step lands as an enforcing gate this phase (zero un-skipped survivors on `--in-diff`), encoded as normal CI YAML — not a `checkpoint:human-decide`. A justified survivor is excluded with `#[mutants::skip]` + a comment in Rust, not by loosening the gate.
- **`--in-place` in CI.** The default cargo-mutants copy-tree isolation copies only the `rust/` workspace, but two agentlinux-core tests (`schema_gen::schema_is_not_drifted`, `semver_shim::parity::…round_trip`) read sibling files at `../../../plugin/catalog/*`. `--in-place` mutates the disposable CI checkout directly so those reads resolve; cargo-mutants restores each mutation.
- **`git diff --relative`.** The step runs from `working-directory: rust` but `git diff` emits repo-root paths (`rust/crates/…`), while cargo-mutants matches `--in-diff` against the workspace root — the mismatch made the gate a false-green. `--relative` rewrites the diff paths so the filter matches.
- **Nightly is advisory.** The full-crate score matches the sibling stryker/bash-mutator advisory pattern; the enforcing gate is the bounded per-PR `--in-diff` step (keeps the merge gate honest under the 15-min cap).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] cargo-mutants copy-tree isolation aborts the baseline → added `--in-place`**
- **Found during:** Local demo (before finalizing Task 1)
- **Issue:** Running `cargo mutants --package agentlinux-core` failed with `ERROR cargo test failed in an unmutated tree, so no mutants were tested`. Two wave-1/wave-2a tests read `env!("CARGO_MANIFEST_DIR")/../../../plugin/catalog/{schema.json,catalog.json}` — files OUTSIDE the `rust/` workspace that cargo-mutants copies. The baseline run in the temp copy fails, aborting the whole gate.
- **Fix:** Added `--in-place` to both the per-PR and nightly invocations (mutates the checked-out tree directly; disposable on a CI runner; cargo-mutants restores each mutation). Documented the rationale inline in both workflows.
- **Files modified:** `.github/workflows/test.yml`, `.github/workflows/nightly-mutation.yml`
- **Verification:** `cargo mutants … --in-place --file reuse.rs` → baseline OK, 10 mutants, 9 caught, 1 unviable, 0 survived.
- **Committed in:** `d6f09c8`

**2. [Rule 3 - Blocking] `--in-diff` path mismatch silently passed the gate → added `git diff --relative`**
- **Found during:** Local demo of the exact CI `--in-diff` invocation
- **Issue:** `cargo mutants … --in-diff <(git diff origin/master...HEAD -- 'crates/agentlinux-core/**')` reported `INFO No mutants to filter`, exit 0 — a FALSE-GREEN. `git diff` emits repo-root-relative paths (`rust/crates/…`) but the step runs from `working-directory: rust` and cargo-mutants matches `--in-diff` paths against the workspace root, so nothing matched and the gate tested nothing.
- **Fix:** Generate the diff with `git diff --relative …` so paths become `crates/agentlinux-core/…` and match the workspace. (Nightly runs the full crate, no `--in-diff`, so no `--relative` needed there.)
- **Files modified:** `.github/workflows/test.yml`
- **Verification:** With `--relative` the reuse.rs diff yields 10 mutants (tested: 9 caught, 1 unviable, 0 survived); without it the identical invocation reports 0 mutants.
- **Committed in:** `d6f09c8`

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking). Both were latent silent-failure bugs in the plan's specified invocation — the gate would have installed cleanly and gone green on every PR while testing nothing. Fixing them is what makes TEST-02 an actual gate rather than an inert step.
**Impact on plan:** No scope creep — the fixes are confined to the two workflow YAML files the plan already targets. They convert a nominally-present-but-inert gate into a working one.

## Issues Encountered
- **cargo-mutants install runtime (RUST-03-style datapoint):** `cargo install cargo-mutants --version 27.1.0 --locked` compiled from source and took several minutes in this VM (expected, not a hang). In CI this is a cache-hit no-op on warm runs via the existing `Swatinem/rust-cache` (per-PR job) and unavoidable but bounded on the nightly job. No per-mutant timeout friction observed: the crate suite runs in ~0.1s, and the auto-set 20s per-mutant timeout gave 10 mutants tested in ~10s wall-clock.
- **Agent-loop metrics (honest):** 0 timeouts on the mutation runs; 0 hallucinated APIs. 2 self-corrections during the local demo, each caught by actually running the tool rather than trusting the plan text: (1) the copy-tree baseline abort → `--in-place`; (2) the `--in-diff` path-prefix false-green → `--relative`. Both are the reason the plan mandated a real local demo. The full-crate `--in-diff` on this branch would mutate the entire (new-vs-master) crate; I deliberately scoped the demo to one file per the plan's "bounded local demo" instruction rather than burning time on an exhaustive run (that is the nightly job's job).

## User Setup Required
None - no external service configuration required. cargo-mutants is CI-installed; nothing ships in the product.

## Next Phase Readiness
- The mutation gate is live and enforcing for every later port. Phases 55-57 (provisioner/CLI/canonical-paths port) will land behind this gate: any new agentlinux-core logic whose mutants survive on the PR diff fails CI.
- **Inherited invariant for later phases:** any agentlinux-core test that reads out-of-workspace files keeps `--in-place` correct; any new per-PR `--in-diff` usage must keep `git diff --relative` (documented inline in `test.yml`). If a future crate's tests become fully workspace-local, `--in-place` could be dropped, but there is no need to.
- No blockers.

## Self-Check: PASSED
- `.github/workflows/test.yml` — FOUND (modified; valid YAML; guarded pinned `--in-diff` gate present, no bypass; W1 fetch-depth 0 + diff-base assertion present)
- `.github/workflows/nightly-mutation.yml` — FOUND (modified; valid YAML; advisory guarded full-crate `rust-mutants` job present)
- Commits `4121740`, `d5545ad`, `d6f09c8` — all FOUND in `git log`
- `cargo test --workspace` — 58 passed, 0 failed (GATE-01 green)
- Local mutants demo — ran and recorded (reuse.rs: 10 tested, 9 caught, 1 unviable, 0 survived)

---
*Phase: 54-testing-bedrock*
*Completed: 2026-07-28*
