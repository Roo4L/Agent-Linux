---
phase: 54-testing-bedrock
plan: 01
subsystem: testing
tags: [rust, proptest, property-testing, semver, node-semver, golden-test, schemars]

requires:
  - phase: 53-pure-core-spike
    provides: "agentlinux-core pure crate (classify/divergence/reuse/semver_shim/types, 44 unit tests)"
provides:
  - "proptest property machinery over the pure core: P1 (classify totality+determinism), P2 (sticky non-drift invariant), P3 (resolve_latest_for output-satisfies-or-typed-error), P4 (semver_shim parse/normalize/max_satisfying totality+idempotence+soundness), reuse::agent_decision totality"
  - "TEST-04 node-semver parity: audit doc (15 case classes + explicit OR/hyphen scope boundary) + golden test (corpus + catalog-driven + loose-shape), catalog-driven case guards against a future unhandled catalog range"
  - "fully-staged agentlinux-core/Cargo.toml (proptest 1.11 + serde_json dev-deps, schemars 1.2.2 dep) so wave-2 plans 54-02/54-03 touch no shared manifest"
  - "committed proptest-regressions/ replay dir + .gitignore mutants.out scratch entry (staged for Plan 54-03)"
affects: [54-02-schema-gen, 54-03-mutants-ci, 55-pure-core-port]

tech-stack:
  added: ["proptest 1.11.0 (dev)", "serde_json 1.0.151 (dev)", "schemars 1.2.2 (dep, derive lands Plan 54-02)"]
  patterns:
    - "Shared #[cfg(test)] proptest_strategies module (version_str/loose_version_str/range_str) so generators are defined once and reused across classify/divergence/semver_shim proptests"
    - "Invariant-over-generated-input properties (totality, determinism, idempotence, output-satisfies-or-typed-error) — NOT re-listing the 44 concrete example rows"
    - "node-semver oracle = committed TS corpora (node stays uninstalled); golden verdicts lifted verbatim from divergence.test.ts:133"
    - "Catalog-driven golden test reads the real plugin/catalog/catalog.json so a future range the shim mis-handles fails CI at the offending entry"

key-files:
  created:
    - "rust/crates/agentlinux-core/src/proptest_strategies.rs — shared hand-written proptest generators"
    - "rust/crates/agentlinux-core/proptest-regressions/README.md — committed replay dir (T-54-02)"
    - "docs/audits/v0.4.0/TEST-04-node-semver-parity.md — the parity audit doc"
  modified:
    - "rust/crates/agentlinux-core/Cargo.toml — proptest/serde_json dev-deps + schemars dep (semver stays =1.0.28)"
    - "rust/crates/agentlinux-core/src/lib.rs — register #[cfg(test)] proptest_strategies module"
    - "rust/crates/agentlinux-core/src/classify.rs — P1/P2 proptests"
    - "rust/crates/agentlinux-core/src/divergence.rs — P3 proptest"
    - "rust/crates/agentlinux-core/src/semver_shim.rs — P4 proptests + TEST-04 golden test module"
    - "rust/crates/agentlinux-core/src/reuse.rs — agent_decision totality proptest"
    - ".gitignore — rust/**/mutants.out scratch (staged for Plan 54-03); proptest-regressions NOT ignored"

key-decisions:
  - "P2 (sticky invariant) scoped to the non-drift subspace via a shared generated version for sentinel.version and installed, plus a prop_assume guard — sticky is only reached at classify branch 4, after the drift check (Pitfall 5)"
  - "proptest-regressions/ committed with an explanatory README so the failure-persistence dir is git-tracked from day one (proptest only writes the dir lazily on the first counterexample; all properties pass today)"
  - "PROPTEST_CASES left at the default 256; the sub-second suite absorbs ~2560 generated cases across the 10 properties"
  - "TEST-04 golden test names all contain 'parity' so `cargo test -p agentlinux-core parity` selects exactly the parity module"

patterns-established:
  - "Property invariants over generated inputs live in a #[cfg(test)] mod proptests next to the fn they exercise; shared generators live in one crate-root proptest_strategies module"
  - "Every version comparison in tests routes through semver_shim (never semver:: directly) so node-semver parity stays isolated"

requirements-completed: [TEST-01, TEST-04, GATE-01, GATE-05]

coverage:
  - id: D1
    description: "TEST-01 proptest invariants P1-P4 + reuse totality — classify total & deterministic, sticky⇒{synced,pinned-override}, resolve_latest_for output satisfies constraint or typed error, semver_shim parse/normalize/max_satisfying total+idempotent+sound"
    requirement: "TEST-01"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/{classify,divergence,semver_shim,reuse}.rs#mod proptests (cargo test -p agentlinux-core)"
        status: pass
    human_judgment: false
  - id: D2
    description: "TEST-04 node-semver parity golden test — corpus verdicts (verbatim from divergence.test.ts:133), catalog-driven case (reads real catalog.json), loose-shape case (v-prefix, 2-part partial, GA-date pins)"
    requirement: "TEST-04"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#mod parity (cargo test -p agentlinux-core parity)"
        status: pass
    human_judgment: false
  - id: D3
    description: "TEST-04 parity audit doc — 15 case classes with node-semver oracle verdict + raw dtolnay 1.0.28 behavior + shim reconciliation, and explicit OR/hyphen-range scope boundary"
    requirement: "TEST-04"
    verification:
      - kind: manual_procedural
        ref: "docs/audits/v0.4.0/TEST-04-node-semver-parity.md — fact-checker verified ^2.1 sole constraint, no OR/hyphen ranges, line refs accurate"
        status: pass
    human_judgment: false
  - id: D4
    description: "GATE-01 no-regression — the 44 pre-existing agentlinux-core unit tests stay green; GATE-05 — all work additive under rust/ on worktree-stack-revisiting, nothing can block a master hotfix"
    requirement: "GATE-01"
    verification:
      - kind: unit
        ref: "cargo test --workspace (57 passed: 44 existing + 13 new) + cargo clippy --workspace --all-targets -- -D warnings + cargo fmt --all --check"
        status: pass
    human_judgment: false

duration: 34 min
completed: 2026-07-28
status: complete
---

# Phase 54 Plan 01: Testing Bedrock (property tests + node-semver parity) Summary

**proptest invariants P1-P4 (+ reuse totality) over the pure agentlinux-core crate, a node-semver→dtolnay-semver parity audit doc + catalog-driven golden test, and the fully-staged Cargo.toml (proptest/serde_json/schemars) so wave-2 touches no shared manifest.**

## Performance

- **Duration:** 34 min
- **Started:** 2026-07-28T07:17:xxZ
- **Completed:** 2026-07-28T07:51:51Z
- **Tasks:** 2 (both TDD)
- **Files modified:** 11 (3 created, 8 modified)

## Accomplishments

- **TEST-01 property machinery:** 10 proptest properties over the pure core, each asserting an invariant the 44 example unit tests cannot express:
  - **P1** — `classify` is total (never panics for any generated entry/sentinel/installed, incl. loose/malformed version strings) and deterministic.
  - **P2** — sticky ⇒ status ∈ {Synced, PinnedOverride}, scoped to the non-drift subspace with a `prop_assume!` precondition (sticky is only reached at classify branch 4 — Pitfall 5).
  - **P3** — `resolve_latest_for` returns either an `Ok(v)` that is a published version AND re-verified to satisfy the constraint, or one of the three typed `DivergenceError` variants — never a panic, never a constraint-violating `Ok`.
  - **P4** — `normalize_range` is idempotent (catalog-realistic + arbitrary strings), `parse_lenient` never panics (loose + arbitrary), `max_satisfying` never panics and its winner is a member of the input list that satisfies the range.
  - **reuse totality** — `agent_decision` returns a `Decision` for any id/status/path strings without panicking.
- **TEST-04 node-semver parity:** an audit doc enumerating 15 case classes (caret/tilde/star, closed + open-ended space-compound, exact pin, GA-date pin, v-prefix, partial, prerelease, zero-match, empty list, valid, malformed range/version) each with the node-semver oracle verdict, raw dtolnay `1.0.28` behavior, and shim reconciliation — plus an explicit scope boundary declaring OR-ranges and hyphen-ranges untested/unsupported. Paired with a golden test (corpus verdicts verbatim from `divergence.test.ts:133`; catalog-driven case reading the real `plugin/catalog/catalog.json`; loose-shape case).
- **Dependency staging:** `agentlinux-core/Cargo.toml` now carries `proptest 1.11` + `serde_json 1` dev-deps and the `schemars 1.2.2` dep (the `JsonSchema` derive lands in Plan 54-02; an unused dep does not fail the build). `semver` stays pinned at `=1.0.28`. `.gitignore` gained a `rust/**/mutants.out` scratch entry (for Plan 54-03) without ignoring `proptest-regressions/`.

## Task Commits

1. **Task 1: test deps + P1-P4 invariant properties (TEST-01)** — `a986e11` (test)
2. **Task 2: node-semver parity audit doc + golden test (TEST-04)** — `1f73c4e` (test)
3. **Review fix: tighten TEST-04 compatibility_window precision** — `a7c1d77` (docs)

_Both tasks are `tdd="true"`; because they add test/audit machinery over already-correct Phase-53 production code, the properties pass on first green run rather than RED→GREEN over new production logic (expected for a testing-infra plan)._

## Files Created/Modified

- `rust/crates/agentlinux-core/Cargo.toml` — proptest/serde_json dev-deps + schemars dep; semver pinned `=1.0.28`
- `rust/crates/agentlinux-core/src/proptest_strategies.rs` — hand-written version/loose-version/range generators (dtolnay semver ships no Arbitrary support)
- `rust/crates/agentlinux-core/src/lib.rs` — register the `#[cfg(test)]` strategies module
- `rust/crates/agentlinux-core/src/classify.rs` — P1/P2 proptests
- `rust/crates/agentlinux-core/src/divergence.rs` — P3 proptest
- `rust/crates/agentlinux-core/src/semver_shim.rs` — P4 proptests + `mod parity` golden test
- `rust/crates/agentlinux-core/src/reuse.rs` — agent_decision totality proptest
- `rust/crates/agentlinux-core/proptest-regressions/README.md` — committed replay dir (T-54-02)
- `docs/audits/v0.4.0/TEST-04-node-semver-parity.md` — parity audit doc
- `.gitignore` — mutants.out scratch (staged for Plan 54-03)
- `rust/Cargo.lock` — resolved proptest 1.11.0, schemars 1.2.2, serde_json 1.0.151, semver 1.0.28

## Verification Evidence

- `cargo test --workspace` → **57 passed; 0 failed** (44 pre-existing unit tests + 13 new: 10 proptest properties @ 256 cases each ≈ 2560 generated inputs, + 3 parity golden fns). GATE-01 no-regression holds.
- `cargo test -p agentlinux-core parity` → **4 passed** (3 new parity golden fns + the pre-existing `eq_handles_v_prefix_parity` unit test the filter also selects).
- `cargo clippy --workspace --all-targets -- -D warnings` → **clean**.
- `cargo fmt --all --check` → **clean**.
- `git check-ignore` confirms `proptest-regressions/` is TRACKED and `mutants.out` is IGNORED.
- Fact-check of the audit doc: `^2.1` (claude-code) is the sole live `version_constraint`; the catalog has **zero** OR-ranges and **zero** hyphen-ranges (scope-boundary claim accurate); all cited `semver_shim.rs`/`divergence.rs` line refs match. Scope-boundary guard proven to have teeth — `normalize_range("^1.0 || ^2.0")` → `"^1.0, ||, ^2.0"` which `VersionReq::parse` rejects, so the catalog-driven golden test would fail if such a range entered the catalog.

## Decisions Made

- **P2 non-drift scoping** — generated a single `shared_version` used for both `sentinel.version` and `installed`, plus a `prop_assume!(eq(...))` guard, so the property lands where sticky is actually consulted (classify branch 4, after the drift check). Without this the generator would produce legitimate `DriftUndeclared` inputs outside the invariant's scope (Pitfall 5).
- **Committed proptest-regressions/ with a README** — proptest only creates the dir lazily on the first discovered counterexample; committing a tracked placeholder ensures the first counterexample lands in a git-tracked location and replays forever (threat T-54-02).
- **Shared strategies module** — generators live once in `proptest_strategies.rs` rather than duplicated across the four proptest modules.
- **schemars staged as a non-dev dep now** — per the plan, so Plan 54-02's schema-gen touches no shared manifest; the `JsonSchema` derive itself lands in Plan 54-02.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] proptest macro format-string incompatibility**
- **Found during:** Task 1 (first `cargo test` run)
- **Issue:** `prop_assert!`/`prop_assert_eq!` route their message through `concat!`, which does not support Rust 2021 inline named-capture (`{range:?}`), and a bare `matches!(...)` arg with struct-pattern `{ .. }` braces tripped the format parser.
- **Fix:** Converted all inline-capture messages to positional `{:?}` args, and bound the `matches!` result to a `let is_typed = …` before `prop_assert!(is_typed, …)`.
- **Files modified:** classify.rs, divergence.rs, semver_shim.rs (Task 1 commit)
- **Verification:** `cargo test -p agentlinux-core` compiles and passes 54 tests.
- **Committed in:** `a986e11`

**2. [Rule 3 - Blocking] rustfmt reflow of a golden-test assertion**
- **Found during:** Task 2 (`cargo fmt --all --check`)
- **Issue:** One `assert_eq!` line in the new parity module exceeded the width rustfmt enforces.
- **Fix:** Ran `cargo fmt --all` to reflow; re-ran the suite (57 passed) to confirm no behavior change.
- **Files modified:** semver_shim.rs (Task 2 commit)
- **Committed in:** `1f73c4e`

**3. [Rule 1 - Imprecise claim] audit-doc "every compatibility_window" overstatement (review triage)**
- **Found during:** post-task review loop (fact-checker lens)
- **Issue:** Row 4 said `>=2.0.0 <3.0.0` is "every compatibility_window"; strictly `test-dummy` has none and 5 MCP/agent entries use the open-ended single-comparator form (row 5's class).
- **Fix:** Reworded row 4 to "every *closed* compatibility_window (20 of 26)" and enumerated the 5 open-ended windows in row 5.
- **Files modified:** docs/audits/v0.4.0/TEST-04-node-semver-parity.md
- **Committed in:** `a7c1d77`

---

**Total deviations:** 3 auto-fixed (2 blocking/tooling, 1 doc-precision from review). **Impact:** No scope creep, no production-code change — all three were test-infra/doc corrections necessary for the suite to compile/format and for the audit doc to be factually precise.

## Agent-Loop Metrics (milestone tracks these)

- **Iterations to green:** 2 `cargo test` compile-fix cycles on Task 1 (both the same proptest-macro format-string class), 1 `cargo fmt` reflow cycle on Task 2. Task 2 golden tests compiled and passed first try.
- **cargo timeouts:** 0. Cold `cargo fetch` + first build ~9s; test suite runs in ~0.12s; no command approached its timeout.
- **Crate hallucinations:** 0. All three added crates (proptest, schemars, serde_json) resolved to the exact versions RESEARCH's package-legitimacy audit named (proptest 1.11.0, schemars 1.2.2, serde_json 1.0.151); no similarly-named substitution or invented crate.
- **Trap avoided:** RESEARCH's "Pattern 1" schema-codegen snippet (flagged in the executor prompt as belonging to the LATER Plan 54-02) was NOT implemented here — this plan stayed on P1-P4 + TEST-04 and only *staged* the schemars dep.

## Issues Encountered

None beyond the auto-fixed deviations above. The pure-core branch order in `classify.rs`/`divergence.rs` matched RESEARCH exactly, so the property preconditions (esp. P2's non-drift subspace) were derivable from the cited line numbers without surprises.

## User Setup Required

None - no external service configuration required. All machinery is test-only and behind the rust-job guard (GATE-05).

## Next Phase Readiness

- **Plan 54-02 (schema-gen, TEST-03):** the `schemars 1.2.2` dep + `serde_json` dev-dep are already in `Cargo.toml`; Plan 02 only adds the `#[derive(JsonSchema)]` + `schema_gen.rs` codegen without editing the shared manifest.
- **Plan 54-03 (cargo-mutants CI, TEST-02):** `.gitignore` already ignores `rust/**/mutants.out` scratch; the committed `proptest-regressions/` + the proptest suite give the mutation gate its killing tests.
- **No blockers.** All work is additive under `rust/` + `docs/audits/` on `worktree-stack-revisiting`; master is untouched (GATE-05).

## Self-Check: PASSED

- Created files exist: `proptest_strategies.rs`, `proptest-regressions/README.md`, `docs/audits/v0.4.0/TEST-04-node-semver-parity.md` — all present on disk.
- Commits exist: `a986e11`, `1f73c4e`, `a7c1d77` — all in `git log`.
- `cargo test --workspace` green (57), clippy clean, fmt clean.

---
*Phase: 54-testing-bedrock*
*Completed: 2026-07-28*
