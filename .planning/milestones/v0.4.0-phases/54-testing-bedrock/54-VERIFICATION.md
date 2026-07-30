---
phase: 54-testing-bedrock
verified: 2026-07-28T00:00:00Z
status: passed
score: 6/6 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
notes:
  - "REQUIREMENTS.md traceability table still lists TEST-02 and TEST-03 as 'Pending' (lines 21-22, 89-90) while the phase delivers them. This is a bookkeeping lag in the ledger, NOT a codebase gap — both requirements are verified implemented below. Recommend flipping both to 'Complete' when the phase is marked done."
---

# Phase 54: Testing Bedrock Verification Report

**Phase Goal:** Stand up proptest (property) + cargo-mutants (mutation) + schemars (schema-gen, kills catalog schema drift) + node-semver parity machinery on the Phase-53 pure core, BEFORE the bulk port, so every later port lands behind a live testing gate.
**Verified:** 2026-07-28
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | classify total & deterministic; sticky⇒{Synced,PinnedOverride}; resolve_latest satisfies-or-typed-error (TEST-01, P1-P3) | ✓ VERIFIED | `classify::proptests::{p1_classify_is_total, p1_classify_is_deterministic, p2_sticky_implies_synced_or_pinned_override}` + `divergence::proptests::p3_resolve_latest_satisfies_or_typed_error` present and green. P1 asserts no-panic + determinism over loose inputs; P2 uses `prop_assume(eq)` non-drift precondition then asserts `matches!(Synced\|PinnedOverride)`; P3 asserts member-of-published + satisfies-recheck OR one of 3 typed DivergenceError variants. Real invariants, not tautologies. |
| 2 | semver_shim parse/normalize/max_satisfying total + idempotent + sound (TEST-01, P4) | ✓ VERIFIED | `semver_shim::proptests::{p4_normalize_range_idempotent, p4_normalize_range_idempotent_arbitrary, p4_parse_lenient_total_on_loose, p4_parse_lenient_total_on_arbitrary, p4_max_satisfying_total_and_sound}` green. Idempotence proven on catalog-realistic AND `.*` arbitrary strings; max_satisfying asserts membership + soundness recheck. |
| 3 | reuse::agent_decision is branch-total (TEST-01) | ✓ VERIFIED | `reuse::proptests::agent_decision_is_total` green. |
| 4 | Rust semver_shim == node-semver satisfies/maxSatisfying/valid on every catalog range (TEST-04 golden) | ✓ VERIFIED | 3 parity fns green. `parity_corpus_max_satisfying_matches_node_semver` asserts `^1.0`→1.2.0, `~1.1`→1.1.0, `*`→2.1.0, `^9.0`→None — byte-identical to the recorded oracle in `plugin/cli/test/divergence.test.ts:133-151` (verified against source). `parity_catalog_ranges_all_round_trip_the_shim` reads the real `plugin/catalog/catalog.json` as a regression guard. Audit doc `docs/audits/v0.4.0/TEST-04-node-semver-parity.md` (131 lines) enumerates cases + a genuine "Known scope boundary" section (hyphen/OR-ranges documented untested). |
| 5 | proptest counterexamples replayed forever (proptest-regressions committed) | ✓ VERIFIED | `rust/crates/agentlinux-core/proptest-regressions/README.md` is git-tracked (dir kept under version control); `.gitignore` ignores `rust/**/mutants.out*` and deliberately does NOT ignore proptest-regressions (`.gitignore:94-99`). |
| 6 | schema.json generated from Rust types (SoT); CI fails on drift; generated schema validates real catalog + all 12 fixtures incl. negatives; 3 ajv consumers unchanged (TEST-03) | ✓ VERIFIED | See dedicated scrutiny below — types.rs has NO JsonSchema derive; drift-check is real (regen produces byte-identical committed file); 26 catalog entries validate; 12 fixtures green with 6 negatives still REJECTING; plugin/cli byte-unchanged from master. |
| 7 | cargo-mutants runs on agentlinux-core as a per-PR --in-diff GATE (not false-green), guarded, pinned; full-crate nightly advisory (TEST-02) | ✓ VERIFIED | See dedicated false-green scrutiny below — empirically proven the `--relative` diff yields 45 real mutants while the un-relative diff yields 0 ("No mutants to filter"); a real run on reuse.rs = 9 caught / 1 unviable / 0 survived. |
| 8 | Full bats suite unchanged; master shippable; all CI behind rust guard (GATE-01, GATE-05) | ✓ VERIFIED | `git diff master...HEAD -- tests/bats/` empty; 58 core + 245 CLI tests green; master untouched at f14c092; every mutants/schema step behind `steps.guard.outputs.ready == 'true'`. |

**Score:** 6/6 must-have truth groups verified (8 rows; TEST-01 spans rows 1-3, one per plan-declared truth cluster). 0 present-behavior-unverified.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `rust/crates/agentlinux-core/Cargo.toml` | proptest 1.11 + serde_json dev/dep + schemars 1.2.2 + semver pinned =1.0.28 | ✓ VERIFIED | All present; `semver = "=1.0.28"` pinned exactly (not bumped). |
| `.../src/proptest_strategies.rs` | version/loose/range generators | ✓ VERIFIED | 3 pub Strategy fns (version_str, loose_version_str, range_str), 46 LOC — substantive. |
| P1-P4 + reuse proptest modules | invariant properties | ✓ VERIFIED | 10 proptest fns across classify.rs/divergence.rs/semver_shim.rs/reuse.rs, all green. |
| `.../src/semver_shim.rs` parity module | corpus + catalog-driven + loose golden | ✓ VERIFIED | 3 parity fns; corpus matches TS oracle; catalog case reads real catalog.json. |
| `docs/audits/v0.4.0/TEST-04-node-semver-parity.md` | parity audit + scope boundary | ✓ VERIFIED | 131 lines; scope-boundary section present (hyphen/OR-ranges documented untested). |
| `proptest-regressions/` | committed replay dir | ✓ VERIFIED | README.md tracked; not gitignored. |
| `.../src/schema_gen.rs` | codegen-only 20-field SchemaCatalogEntry + schema_json() + drift-check | ✓ VERIFIED | 20 fields, `deny_unknown_fields`, `extend` for allOf/$id; drift-check reads committed file and assert_eq's generated. |
| `plugin/catalog/schema.json` | regenerated from Rust, marked generated | ✓ VERIFIED | 136 insertions from master's hand-written; `$comment` GENERATED marker; regen is byte-idempotent. |
| `CONTRIBUTING.md` | UPDATE_SCHEMA regeneration note | ✓ VERIFIED | Line 73+ documents "generated — never hand-edit" + UPDATE_SCHEMA command. |
| `.github/workflows/test.yml` rust job | pinned + guarded --in-diff --relative gate | ✓ VERIFIED | cargo-mutants 27.1.0 pinned; `--in-diff <(git diff --relative ...)`; guarded; fetch-depth 0 + merge-base assertion (W1); no advisory bypass. |
| `.github/workflows/nightly-mutation.yml` | full-crate advisory rust-mutants job | ✓ VERIFIED | `rust-mutants` job, full-crate `cargo mutants --package agentlinux-core`, continue-on-error: true, guarded on rust/ presence. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| property/golden tests | semver_shim | all comparisons route through shim, never `semver::` directly | ✓ WIRED | parity + P3/P4 call `semver_shim::{eq, max_satisfying, parse_lenient, normalize_range}`. |
| catalog-driven golden case | plugin/catalog/catalog.json | CARGO_MANIFEST_DIR-relative read | ✓ WIRED | `parity_catalog_ranges_all_round_trip_the_shim` reads real catalog; a future unhandled range fails HERE. |
| schema_gen SchemaCatalogEntry | plugin/catalog/schema.json | schema_json() emitter + drift-check | ✓ WIRED | Regeneration produces byte-identical committed file (verified live). |
| generated schema.json | 3 ajv consumers | identical repo path, no consumer change | ✓ WIRED | validate-catalog.mjs / schema.ts / schema.test.ts byte-unchanged from master; 26 entries + 12 fixtures green. |
| mutants gate | agentlinux-core diff | `git diff --relative` path rewrite | ✓ WIRED | Empirically: --relative → 45 mutants; without → 0 (false-green avoided). |

## TEST-03 Scrutiny (schema not silently loosened)

- `types.rs` grep for `JsonSchema`/`schemars` → **0 matches** (Pitfall 3 avoided — the lean 5-field CatalogEntry carries no derive; the schema comes from a codegen-only 20-field SchemaCatalogEntry).
- Drift-check `schema_gen::tests::schema_is_not_drifted` is a REAL comparison: reads committed `plugin/catalog/schema.json` and `assert_eq!(committed, generated)`. Ran `UPDATE_SCHEMA=1 cargo test schema` → `git status` clean afterward ⇒ committed file IS the generated output (no drift, not a no-op).
- `node plugin/cli/scripts/validate-catalog.mjs` → **"26 entries OK"** — the real catalog validates under ajv strict against the generated schema.
- All **12** schema.test.ts fixtures pass. The **6 negatives still REJECT**: (1) missing pinned_version, (2) unknown source_kind enum, (5) lowercase secret_env, (8) http endpoint_url, (10) npm missing npm_package_name, (11) non-semver "1.2". No negative flipped to passing → the schema was not loosened.
- `git diff master...HEAD -- plugin/cli` is **empty** — the 3 ajv consumers are byte-unchanged; only `plugin/catalog/schema.json` (136 insertions) changed.

## TEST-02 Scrutiny (gate is not a false-green)

The single hardest scrutiny point — verified empirically with cargo-mutants 27.1.0 locally:

- **WITHOUT `--relative`** (the false-green): `cargo mutants --list --in-diff <(git diff master...HEAD -- 'crates/agentlinux-core/**')` → **0 mutants, "INFO No mutants to filter"** → exit 0. This is the false-green a naive gate would ship.
- **WITH `--relative`** (the shipped fix at test.yml:237): same command with `git diff --relative` → **45 real mutants enumerated** (e.g. `replace max_satisfying ... with Ok(Some(""))`, `replace >= with <`).
- Root cause confirmed: the whole `rust/` tree is NEW on this branch (absent on master); `--relative` rewrites diff headers to `+++ b/crates/agentlinux-core/...` (workspace-root-relative) so cargo-mutants' `--in-diff` filter matches.
- **Real mutation run** on reuse.rs: `10 mutants tested: 9 caught, 1 unviable` → **0 survived** — the proptest+unit suite genuinely kills mutants (matches the plan's recorded local result exactly).
- Gate hygiene: pinned `27.1.0 --locked`; `--minimum-test-timeout 20` (no hang under 15-min cap); `--in-place` (required for the out-of-workspace catalog reads); **no `|| echo ::warning::` advisory bypass** on the per-PR gate; `fetch-depth: 0` + explicit origin/master fetch + merge-base assertion (W1) so `--in-diff` cannot silently no-op on a shallow clone.
- Nightly full-crate `rust-mutants` job present in nightly-mutation.yml, advisory (continue-on-error), guarded.

## GATE-01 / GATE-05

- `cargo test --workspace` → **58 passed** (agentlinux-core); `pnpm test` → **245 pass, 0 fail** (CLI, incl. the 12 schema fixtures). clippy `-D warnings` clean; `cargo fmt --check` clean.
- `git diff master...HEAD -- tests/bats/` → **empty** (no behavior test changed or skipped).
- master untouched at **f14c092** (matches expected). Phase-54 footprint: rust/crates/agentlinux-core, plugin/catalog/schema.json, docs/audits, CONTRIBUTING.md, .gitignore, 2 CI workflows. `plugin/lib/reuse/agents.sh` + `tests/docker/run.sh` on the branch are **Phase 53** commits (1b5cd86, d292407), not Phase 54.
- Every mutants + schema step gated behind `steps.guard.outputs.ready == 'true'`; nothing touches shipped Bash/CLI behavior → a red Rust run can never block a non-Rust master hotfix.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TEST-01 | 54-01 | proptest property tests on the pure core | ✓ SATISFIED | 10 proptest fns green (P1-P4 + reuse totality). |
| TEST-04 | 54-01 | node-semver parity audit + golden test | ✓ SATISFIED | 3 parity fns green + audit doc with scope boundary. |
| TEST-03 | 54-02 | schemars-generated schema + drift-check | ✓ SATISFIED | codegen SoT + real drift-check + 26 entries + 12 fixtures (6 negatives reject). |
| TEST-02 | 54-03 | cargo-mutants CI gate (advisory→gate) | ✓ SATISFIED | --relative --in-diff gate proven non-false-green; nightly advisory. |
| GATE-01 | 54-01/02/03 | full bats green, no regression/skip | ✓ SATISFIED | 58 core + 245 CLI green; no bats file changed. |
| GATE-05 | 54-01/02/03 | master shippable, CI behind rust guard | ✓ SATISFIED | master at f14c092; all new CI guarded. |

No orphaned requirements — all 6 phase requirement IDs are claimed by plans and satisfied.

### Anti-Patterns Found

None. No TBD/FIXME/XXX debt markers and no TODO/HACK/PLACEHOLDER in Phase-54-authored files. No stub implementations (all modules substantive: strategies 3 fns, schema_gen 20-field struct, 13 proptest/parity/drift test fns).

### Human Verification Required

None. Every truth was confirmed with executable evidence (cargo test, pnpm test, live cargo-mutants runs, git diff). No behavior-dependent truth was left present-but-unexercised — the mutation gate's non-false-green property and the mutant-killing capability were both run, not merely grep-confirmed.

### Gaps Summary

No gaps. All 6 phase requirement IDs (TEST-01/02/03/04, GATE-01/05) are implemented and verified against the actual codebase. The two hardest scrutiny points requested — TEST-02's gate being a genuine (not false-green) mutation gate, and TEST-03's negative fixtures still rejecting a non-loosened schema — both hold under direct empirical test. The only follow-up is a documentation-bookkeeping nit: REQUIREMENTS.md still marks TEST-02/TEST-03 "Pending" in the traceability table; flip them to "Complete" when the phase is closed (not a codebase gap).

---

_Verified: 2026-07-28_
_Verifier: Claude (gsd-verifier)_
