---
phase: 55-pure-logic-core-parity
plan: 01
subsystem: infra
tags: [rust, semver, serde, agentlinux-core, node-semver-parity, port]

# Dependency graph
requires:
  - phase: 53-pure-logic-core
    provides: agentlinux-core crate (classify.rs, divergence.rs, reuse.rs, semver_shim.rs, types.rs) + the pure/I-O seam pattern
  - phase: 54-mutation-property-hardening
    provides: proptest_strategies.rs generators (loose_version_str, range_str, version_str) + cargo-mutants gate scoping
provides:
  - "semver_shim::valid(raw) -> Option<String> — STRICT node semver.valid parity (normalizes v-prefix, rejects partials/ranges)"
  - "semver_shim::satisfies(version, range) -> bool — total node semver.satisfies parity (malformed → false, never panics)"
  - "types.rs: DetectedAgent struct (mirror of DetectCacheAgent)"
  - "types.rs: CatalogEntry.tags: Vec<String> + source_kind: Option<String> (serde-default)"
  - "types.rs: CategoryKey enum (kebab-serialized) + Category struct"
affects: [55-02, 55-03, plan-02-category, plan-02-pin_spec, plan-02-detect_gates, plan-03-decide_version, phase-56-cli-adapter]

# Tech tracking
tech-stack:
  added: []  # no new dependencies — semver/serde/thiserror/proptest already pinned by Phase 53/54
  patterns:
    - "STRICT-vs-lenient semver boundary: valid() calls Version::parse directly (no coerce_partial) so partials are rejected, distinct from parse_lenient's coercion"
    - "total predicate returning bool (never Err/panic) for satisfies() — the T-55-02 no-panic contract"
    - "kebab-serialized enum (CategoryKey) mirroring the Status enum convention for byte-identical TS parity"
    - "Option<String> (not enum) for source_kind so unknown/absent kinds deserialize cleanly"

key-files:
  created: []
  modified:
    - rust/crates/agentlinux-core/src/semver_shim.rs
    - rust/crates/agentlinux-core/src/types.rs
    - rust/crates/agentlinux-core/src/classify.rs
    - rust/crates/agentlinux-core/src/divergence.rs

key-decisions:
  - "valid() uses Version::parse(stripped) directly — NOT parse_lenient — so \"2.1\" → None (the A1 strict subtlety; a lenient valid would wrongly accept the partial pin, threat T-55-01)"
  - "source_kind modelled as Option<String>, not an enum, so an unknown/absent kind deserializes cleanly (detect gates only compare to string literals)"
  - "DetectedAgent status/version kept as plain String (compared to \"healthy\"/\"broken\", version passed to semver_shim::valid) — not modelled as enums"
  - "the single P4d valid-totality proptest uses `if let` not `match` to satisfy clippy::single_match under -D warnings"

patterns-established:
  - "Pattern: strict validity (valid) and lenient comparison (parse_lenient/satisfies) coexist in the shim — the caller picks the semantic; the pin path uses strict, the window/compare path uses lenient"
  - "Pattern: additive serde-default fields on CatalogEntry require updating in-repo struct-literal test constructors (classify/divergence) but leave deserialization backward-compatible"

requirements-completed: [CORE-03, GATE-01, GATE-05]

coverage:
  - id: D1
    description: "semver_shim::valid — STRICT node semver.valid: accepts full/prerelease, normalizes v-prefix, rejects partials/ranges/garbage"
    requirement: "CORE-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#valid_accepts_full_version_returns_normalized"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#valid_rejects_two_component_partial"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#valid_strips_and_normalizes_v_prefix"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#parity_valid_strict_rejects_partials_accepts_prerelease"
        status: pass
    human_judgment: false
  - id: D2
    description: "semver_shim::satisfies — total node semver.satisfies: compound windows, lenient version parse, malformed → false, never panics"
    requirement: "CORE-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#satisfies_compound_range_in_and_out_of_window"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#satisfies_malformed_inputs_return_false_never_panic"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#parity_satisfies_matches_node_semver_over_window"
        status: pass
      - kind: other
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#p4_satisfies_total_on_arbitrary (proptest totality — T-55-02)"
        status: pass
    human_judgment: false
  - id: D3
    description: "valid + satisfies totality proptests — never panic on loose/adversarial inputs (threats T-55-01, T-55-02)"
    requirement: "CORE-03"
    verification:
      - kind: other
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#p4_valid_total_on_arbitrary (proptest)"
        status: pass
      - kind: other
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#p4_valid_total_and_idempotent_on_loose (proptest)"
        status: pass
    human_judgment: false
  - id: D4
    description: "types.rs extended: DetectedAgent, CatalogEntry.tags/source_kind (serde-default), CategoryKey (kebab), Category — wave-2 deciders compile against shared types"
    requirement: "CORE-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/types.rs#category_key_serializes_to_ts_kebab_strings"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/types.rs#detected_agent_deserializes_cache_record"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/types.rs#catalog_entry_defaults_tags_and_source_kind_when_absent"
        status: pass
      - kind: integration
        ref: "cargo build -p agentlinux-core && cargo test -p agentlinux-core --no-run (existing classify/divergence still compile)"
        status: pass
    human_judgment: false
  - id: D5
    description: "semver isolation invariant held (TEST-04): no new semver:: call outside semver_shim.rs; crate stays PURE (no std::process/fs/env in shipped code)"
    requirement: "GATE-05"
    verification:
      - kind: other
        ref: "grep -rn 'semver::' rust/crates/agentlinux-core/src/ | grep -v semver_shim.rs → only the pre-existing test-oracle line in divergence.rs (present at base 29ad322)"
        status: pass
    human_judgment: false

# Metrics
duration: 6min
completed: 2026-07-28
status: complete
---

# Phase 55 Plan 01: Pure-Logic Core Parity (Wave-1 Unblocker) Summary

**Added the two missing semver_shim entry points (`valid` STRICT-normalized, `satisfies` total) with A1 golden cross-check rows, and grew `types.rs` with `DetectedAgent` + `CatalogEntry.tags`/`source_kind` + `CategoryKey`/`Category` — unblocking the wave-2 category/pin-spec/detect-gate ports without breaking the node-semver isolation invariant.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-07-28T08:50:53Z
- **Completed:** 2026-07-28T08:57:01Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- `semver_shim::valid(raw) -> Option<String>` — STRICT node `semver.valid`: accepts full versions + prereleases, normalizes a leading `v` (`"v1.2.3"` → `"1.2.3"`), and REJECTS partials (`"2.1"` → `None`) and ranges (`"^2.1"` → `None`). Uses `Version::parse` directly (NOT `parse_lenient`), so the A1 pin-safety subtlety holds — a malformed/partial pin never reaches the sentinel as "valid" (threat T-55-01).
- `semver_shim::satisfies(version, range) -> bool` — total node `semver.satisfies`: compound windows via `normalize_range`, lenient version parse (so `"v1.37.1"` satisfies), malformed range/version → `false`, never panics (threat T-55-02).
- Golden `#[test]` rows for every `<behavior>` row PLUS the two explicit A1 cross-check rows the TS corpus does not exercise (`"2.1"` → None, `"v1.2.3"` → Some("1.2.3")), in both the `tests` and `parity` modules.
- Totality proptests for `valid` and `satisfies` (loose + arbitrary/adversarial inputs), plus a `valid` idempotence property (its normalized output is a stable fixpoint).
- `types.rs`: `DetectedAgent` (4-field mirror of `DetectCacheAgent`), `CatalogEntry.tags: Vec<String>` + `source_kind: Option<String>` (both `#[serde(default)]`), and `CategoryKey` (kebab-serialized) + `Category { key, label, order }`.

## Task Commits

Each task was committed atomically:

1. **Task 1 (TDD): semver_shim::valid + satisfies + goldens** — RED `91446bd` (test), GREEN `7397846` (feat, clippy-fix amended in)
2. **Task 2: types.rs DetectedAgent / tags-source_kind / CategoryKey-Category** — `1c8c17d` (feat)

**Plan metadata:** (docs commit — this SUMMARY)

_Note: Task 1 followed RED→GREEN; the REFACTOR-equivalent clippy `single_match`→`if let` fix was amended into the GREEN commit to keep the shim in one coherent state._

## Files Created/Modified
- `rust/crates/agentlinux-core/src/semver_shim.rs` — added `valid` + `satisfies` fns; golden rows in `tests` + `parity`; totality/idempotence proptests in `proptests`.
- `rust/crates/agentlinux-core/src/types.rs` — extended `CatalogEntry` (tags/source_kind); added `DetectedAgent`, `CategoryKey`, `Category`; added a `tests` module (kebab serialization, cache-record deserialization, serde-default).
- `rust/crates/agentlinux-core/src/classify.rs` — updated 2 `CatalogEntry` struct-literal test constructors for the additive fields.
- `rust/crates/agentlinux-core/src/divergence.rs` — updated 2 `CatalogEntry` struct-literal test constructors for the additive fields.

## Decisions Made
- **`valid` is STRICT, not lenient** — `Version::parse(stripped)` directly, so `"2.1"` → None. Reusing `parse_lenient`/`coerce_partial` would coerce `"2.1"` → `"2.1.0"` and wrongly accept a partial the TS `parsePinSpec` rejects (Assumption A1 / Pitfall 6; threat T-55-01).
- **`source_kind: Option<String>`, not an enum** — an unknown/absent kind deserializes cleanly; the detect gates only compare it to the string literals `"npm"`/`"script"`/`"binary"`/`"mcp"`.
- **`DetectedAgent.status`/`version` are plain `String`** — deciders compare `status` to `"healthy"`/`"broken"` and pass `version` to `semver_shim::valid`; not modelled as enums.
- **`valid` returns the NORMALIZED string** (not the raw input) — the sentinel + downstream consume the clean value (Pitfall 6).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Update existing CatalogEntry test constructors for the two additive fields**
- **Found during:** Task 2 (types.rs extension)
- **Issue:** Adding `tags` + `source_kind` (non-`Default`-derived) to `CatalogEntry` broke compilation of the existing `classify.rs` and `divergence.rs` test struct-literal constructors ("missing `source_kind` and `tags`").
- **Fix:** Added `tags: Vec::new()` + `source_kind: None` to all four in-repo `CatalogEntry { .. }` construction sites (classify base_entry + entry_strategy; divergence `e()` + entry_with_range). These match the serde defaults, so classify/divergence semantics are unchanged (they never read the new fields).
- **Files modified:** rust/crates/agentlinux-core/src/classify.rs, rust/crates/agentlinux-core/src/divergence.rs
- **Verification:** `cargo test -p agentlinux-core --no-run` compiles; full workspace test 77 passed / 0 failed.
- **Committed in:** `1c8c17d` (Task 2 commit)

**2. [Rule 1 - Bug] clippy::single_match on the new valid-totality proptest**
- **Found during:** Task 1 (GREEN, running `cargo clippy --all-targets -- -D warnings`)
- **Issue:** The `match valid(&v) { Some(..) => .., None => {} }` proptest arm tripped `clippy::single_match` under `-D warnings`, which would fail the GATE-05 clean-clippy bar.
- **Fix:** Rewrote as `if let Some(normalized) = valid(&v) { .. }`.
- **Files modified:** rust/crates/agentlinux-core/src/semver_shim.rs
- **Verification:** `cargo clippy --workspace --all-targets -- -D warnings` → No issues found.
- **Committed in:** `7397846` (amended into the Task 1 GREEN commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug/lint)
**Impact on plan:** Both auto-fixes were necessary for compilation and the GATE-05 clean-clippy bar. No scope creep — the crate's shipped surface matches the plan exactly (two shim fns + the specified type additions).

## Issues Encountered
- **Review loop had no Rust reviewer role.** The project `$review` dispatch table (`.claude/skills/review/`) maps file patterns to bash/TS/bats/catalog/docs roles only — there is no `rust-engineer` and no pattern matching `rust/**/*.rs`, so the changed-file ∩ dispatch-table intersection is empty. Per the skill's contract this is a limited pass: I applied the relevant trait lenses (correctness/parity, purity, isolation, serde-default) manually, backed by the authoritative deterministic gates (`cargo clippy --workspace --all-targets -- -D warnings` clean, `cargo fmt --all --check` clean, golden + proptest suite green). No actionable findings. (Follow-up: a `rust-engineer` role + a `rust/**/*.rs` dispatch row would close this gap for the rewrite milestone — recorded for a future harness phase.)

## Verification Evidence
- `cargo test -p agentlinux-core semver_shim` → **37 passed, 0 failed** (valid/satisfies goldens + A1 cross-check rows + totality/idempotence proptests).
- `cargo build -p agentlinux-core` → clean; `cargo test -p agentlinux-core --no-run` → compiles (existing classify/divergence unchanged).
- `cargo test --workspace` → **77 passed, 0 failed** in agentlinux-core (58 baseline + 19 new), bin suite 0/0.
- `cargo clippy --workspace --all-targets -- -D warnings` → **No issues found**.
- `cargo fmt --all --check` → **clean**.
- `grep -rn 'semver::' crates/agentlinux-core/src/ | grep -v semver_shim.rs` → only the pre-existing test-oracle line at `divergence.rs:320` (present at base `29ad322`, inside a `#[cfg(test)] proptests` module — the independent-oracle convention, NOT a production leak; this plan added zero `semver::` calls outside the shim).
- Crate purity: no `std::process`/`std::fs`/`std::env` in shipped code (the one `std::fs` is a pre-existing `#[cfg(test)]` catalog-parity test).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Wave-2 (Plan 02) unblocked:** `category.rs`/`pin_spec.rs`/`detect_gates.rs` can now compile against `semver_shim::valid`, `semver_shim::satisfies`, `DetectedAgent`, `CatalogEntry.tags`/`source_kind`, and `CategoryKey`/`Category`.
- **Plan 03 (`decide_version`)** likewise has its `valid`/`satisfies` foundations in place.
- Semver isolation invariant (TEST-04) intact — every version op still routes through the shim.
- No blockers. `master` unaffected (additive-only under `rust/`, on `worktree-stack-revisiting` per GATE-05).

## Self-Check: PASSED

- Modified files exist on disk: `semver_shim.rs`, `types.rs`, `classify.rs`, `divergence.rs`, and `55-01-SUMMARY.md` — all FOUND.
- Task commits present in git history: `91446bd` (RED test), `7397846` (GREEN feat), `1c8c17d` (types feat) — all FOUND.
- Plan-level `<verification>` re-run: `cargo test -p agentlinux-core semver_shim` green; `cargo build -p agentlinux-core` green; `cargo test --workspace` 77/0; no `semver::` call added outside the shim.

---
*Phase: 55-pure-logic-core-parity*
*Completed: 2026-07-28*
