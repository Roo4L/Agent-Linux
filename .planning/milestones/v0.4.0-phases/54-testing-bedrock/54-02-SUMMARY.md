---
phase: 54-testing-bedrock
plan: 02
subsystem: testing
tags: [rust, schemars, json-schema, catalog, drift-check, ajv, testing-bedrock]

# Dependency graph
requires:
  - phase: 54-01
    provides: schemars 1.2.2 + serde_json staged in agentlinux-core/Cargo.toml; proptest + parity landed
provides:
  - "plugin/catalog/schema.json is now a GENERATED artifact of the Rust catalog types (single source of truth)"
  - "schema_gen.rs: codegen-only SchemaCatalogEntry (full ~15-field schema) + pure schema_json() emitter + drift-check #[test]"
  - "CI-enforceable generated-vs-committed drift-check (UPDATE_SCHEMA=1 emits, else asserts)"
  - "CONTRIBUTING.md regeneration note"
affects: [55-core-port, catalog, schema, phase-55-catalog-entry-expansion]

# Tech tracking
tech-stack:
  added: []  # schemars/serde_json were staged in 54-01; serde_json promoted to a non-dev dep (see deviations)
  patterns:
    - "schemars-in-CI drift-check idiom: pure schema_json() + a #[cfg(test)] emit/assert gate"
    - "codegen-only mirror struct (SchemaCatalogEntry) to source a full schema without expanding the lean core type"
    - "reproduce non-derivable JSON-Schema constructs (if/then, $id, $comment) via #[schemars(extend(...))]"

key-files:
  created:
    - rust/crates/agentlinux-core/src/schema_gen.rs
  modified:
    - rust/crates/agentlinux-core/src/lib.rs
    - rust/crates/agentlinux-core/src/types.rs
    - rust/crates/agentlinux-core/Cargo.toml
    - plugin/catalog/schema.json
    - CONTRIBUTING.md

key-decisions:
  - "Option (a): the generated schema is the SoT; the 3 ajv consumers read the same path unchanged (zero consumer edits)."
  - "Codegen-only SchemaCatalogEntry (not deriving JsonSchema on the lean types::CatalogEntry) — contains blast radius; full-field core type stays Phase-55 scope."
  - "Acceptance is FUNCTIONAL equivalence (ajv-strict + real-catalog + 12 fixtures incl. negatives), NOT byte-parity — the ['string','null'] optional union and dropped per-field descriptions are intentional, ajv-harmless divergences."
  - "Promoted serde_json to [dependencies] (schema_json() pretty-prints in non-test code); it was already a transitive schemars dep so the build graph is unchanged."

patterns-established:
  - "Drift-check: UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema writes; a plain run asserts committed == generated."
  - "extend() re-injects the npm-requires allOf if/then conditional in a form ajv strict accepts."

requirements-completed: [TEST-03, GATE-01, GATE-05]

coverage:
  - id: D1
    description: "plugin/catalog/schema.json generated from Rust catalog types (single SoT) with a generated-vs-committed drift-check"
    requirement: "TEST-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/schema_gen.rs#schema_is_not_drifted"
        status: pass
    human_judgment: false
  - id: D2
    description: "Generated schema keeps the shipped ajv catalog-validation path green (real 26-entry catalog validates under ajv strict; pre-commit catalog-schema-validate green)"
    requirement: "GATE-01"
    verification:
      - kind: integration
        ref: "node plugin/cli/scripts/validate-catalog.mjs -> '26 entries OK'"
        status: pass
      - kind: integration
        ref: "pre-commit run catalog-schema-validate --all-files -> Passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "All 12 schema.test.ts fixtures green — negatives still REJECT malformed entries (no dropped constraint / if-then)"
    requirement: "TEST-03"
    verification:
      - kind: unit
        ref: "plugin/cli/test/schema.test.ts (node --test dist-test/test/schema.test.js) -> 12 pass / 0 fail"
        status: pass
    human_judgment: false
  - id: D4
    description: "GATE-05: schema drift-check is all-Rust + a generated JSON artifact; no consumer source changed, master stays shippable behind the rust-job guard"
    requirement: "GATE-05"
    verification:
      - kind: other
        ref: "git diff b28d018..HEAD -- plugin/cli/scripts/validate-catalog.mjs plugin/cli/src/catalog/schema.ts plugin/cli/src/types.ts (empty = unchanged)"
        status: pass
    human_judgment: false

# Metrics
duration: 8min
completed: 2026-07-28
status: complete
---

# Phase 54 Plan 02: Schemars Catalog Schema Generation Summary

**plugin/catalog/schema.json is now generated from a codegen-only Rust `SchemaCatalogEntry` (full ~15-field mirror + npm if/then via `#[schemars(extend)]`), with a CI drift-check, keeping ajv-strict + all 12 schema.test.ts fixtures green and zero consumer changes.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-28T07:57:00Z
- **Completed:** 2026-07-28T08:05:07Z
- **Tasks:** 2
- **Files modified:** 6 (1 created, 5 modified)

## Accomplishments
- Made `plugin/catalog/schema.json` a generated artifact of the Rust catalog types (TEST-03) — a single Rust source of truth, marked generated via `$comment`.
- Added a codegen-only `SchemaCatalogEntry` that mirrors the FULL catalog schema (all ~15 fields, every `pattern`/`minLength`/`format` constraint, the `source_kind` enum inlined, `additionalProperties:false`, and the npm-requires `allOf if/then` re-injected via `extend`) — deliberately NOT deriving `JsonSchema` on the lean `types::CatalogEntry` (avoids the broken 5-field schema, Pitfall 3).
- Proved FUNCTIONAL equivalence (the acceptance oracle, not byte-parity): ajv strict validates the real 26-entry catalog; all 12 `schema.test.ts` fixtures pass with the 6 negative fixtures still REJECTING; the `catalog-schema-validate` pre-commit hook is green.
- Added a `#[cfg(test)]` drift-check that emits on `UPDATE_SCHEMA=1` and otherwise asserts committed == generated, so CI fails on drift. `schema_json()` itself stays pure (no I/O).
- Zero ajv-consumer edits — `validate-catalog.mjs`, `catalog/schema.ts`, `schema.test.ts`, and `types.ts` are byte-for-byte unchanged; `/opt` staging path is transparent.

## Functional-Equivalence Evidence (the acceptance oracle)

| Gate | Command | Result |
|------|---------|--------|
| Drift-check (committed == generated) | `cargo test -p agentlinux-core schema` | `test result: ok. 1 passed` |
| ajv strict — real catalog (GATE-01) | `node plugin/cli/scripts/validate-catalog.mjs` | `26 entries OK (10 preserve_paths.json validated)` |
| 12 schema fixtures (positives + negatives) | `node --test dist-test/test/schema.test.js` | `# tests 12 / # pass 12 / # fail 0` |
| Full CLI suite (no regression) | `cd plugin/cli && pnpm test` | `# tests 245 / # pass 245 / # fail 0` |
| Pre-commit shipped path | `pre-commit run catalog-schema-validate --all-files` | `Passed` |
| Negative rejection spot-check | ajv on npm-missing-pkg + `pinned_version:"1.2"` | both `REJECTED: true` |
| Rust workspace | `cargo test --workspace` | `58 passed; 0 failed` |
| Lint | `cargo clippy --workspace --all-targets -- -D warnings` | clean |
| Format | `cargo fmt --all --check` | clean |

**Structural parity vs the hand-written schema (constraint-preservation proof, T-54-03):** identical `required` sets (root + agent), identical `additionalProperties:false` at both levels, identical `allOf if/then`, identical property-name set (all ~15 fields), identical `$id`/`title`, all 7 `pattern`s + both `format:"uri"`s + all `minLength`s + the `enum` preserved. The only divergences are the `["string","null"]` optional union (ajv-harmless) and dropped per-field `description` annotations (non-constraining) — intentional, per the RESEARCH Option (a) reconciliation.

**Fixture negative-rejection map (guards against a silently-dropped constraint):** missing `pinned_version` → required error; unknown `source_kind` → enum error; npm missing `npm_package_name` → the `allOf if/then` required error; lowercase `secret_env` → pattern error; http `endpoint_url` → pattern error; non-semver `pinned_version "1.2"` → pattern error. All still reject.

## Task Commits

Each task was committed atomically:

1. **Task 1: schemars codegen struct + emitter + drift-check test (TEST-03)** - `91b72e0` (feat)
2. **Task 2: Regenerate schema.json + prove functional equivalence (TEST-03/GATE-01)** - `d3acbba` (feat)

_Note: Task 1 is a `tdd="true"` task whose "test" is the drift-check itself; the RED (drift when committed != generated) is resolved by Task 2 regenerating and committing the file, at which point the drift-check asserts green._

## Files Created/Modified
- `rust/crates/agentlinux-core/src/schema_gen.rs` (created) - Codegen-only `SchemaCatalogEntry` + `Catalog` wrapper + `SourceKind` enum + pure `schema_json()` emitter + `#[cfg(test)]` drift-check.
- `rust/crates/agentlinux-core/src/lib.rs` - Registered `pub mod schema_gen;`.
- `rust/crates/agentlinux-core/src/types.rs` - Corrected a now-stale module doc-comment that claimed `#[derive(JsonSchema)]` bolts onto the lean types (reversed decision; also satisfies the "no JsonSchema in types.rs" acceptance grep).
- `rust/crates/agentlinux-core/Cargo.toml` - Promoted `serde_json` from `[dev-dependencies]` to `[dependencies]` (see deviation).
- `plugin/catalog/schema.json` - Regenerated from the Rust types (generated is the SoT), marked generated via `$comment`.
- `CONTRIBUTING.md` - Note: schema.json is generated; regenerate with `UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema`; CI drift-check enforces freshness.

## Decisions Made
- **Generated schema is the SoT (Option a):** the three ajv consumers read the identical repo path, so no consumer/`/opt`-staging change was needed.
- **Codegen-only `SchemaCatalogEntry`:** kept the lean `types::CatalogEntry` untouched (full-field core type is Phase-55 scope), containing the blast radius on the shipped catalog validation.
- **`source_kind` inlined** via a container-level `#[schemars(inline)]` on the `SourceKind` enum to match the hand-written inline enum (rather than a `$ref` to `$defs/SourceKind`).
- **`$comment` marks the file generated** so a contributor regenerates rather than hand-edits; ajv strict accepts `$comment` (a standard annotation keyword).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Promoted `serde_json` from `[dev-dependencies]` to `[dependencies]`**
- **Found during:** Task 1 (implementing `schema_json()`)
- **Issue:** The plan specified `pub fn schema_json()` in non-test `src/` code, but `serde_json` was staged in 54-01 as a `[dev-dependency]`, so `serde_json::to_string_pretty` failed to resolve outside `#[cfg(test)]` (`E0433: cannot find module or crate serde_json`). The plan said "does NOT touch Cargo.toml," but the required pure `schema_json()` API cannot compile without serde_json in scope.
- **Fix:** Moved the `serde_json = "1"` line to `[dependencies]`. It is already a transitive dependency of `schemars`, so the build graph and binary size are unchanged; this is a compile-blocker fix, not a new dependency.
- **Files modified:** `rust/crates/agentlinux-core/Cargo.toml`
- **Verification:** `cargo build -p agentlinux-core` succeeds; `cargo test --workspace` green; `cargo clippy -- -D warnings` clean.
- **Committed in:** `91b72e0` (Task 1 commit)

**2. [Rule 1 - Bug] Corrected a stale doc-comment in types.rs**
- **Found during:** Task 1 (acceptance-criteria verification: "grep types.rs for JsonSchema returns nothing")
- **Issue:** `types.rs` line 4 carried a pre-existing module doc-comment stating Phase 54's `#[derive(JsonSchema)]` "bolts on" to the lean types. Plan 54-02 explicitly reversed that (codegen-only struct; lean types untouched), so the comment was factually wrong and also tripped the acceptance grep.
- **Fix:** Rewrote the doc-comment to state that the schema is generated from a dedicated codegen-only struct in `schema_gen.rs` and these core types stay minimal. No code/behavior change.
- **Files modified:** `rust/crates/agentlinux-core/src/types.rs`
- **Verification:** `grep JsonSchema types.rs` now returns nothing; `cargo test --workspace` green; `cargo fmt --check` clean.
- **Committed in:** `91b72e0` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug).
**Impact on plan:** Deviation 1 was the minimal Cargo.toml change required to satisfy the plan's own `pub fn schema_json()` API contract (zero build-graph impact). Deviation 2 corrected stale documentation and satisfied a literal acceptance grep. No scope creep; the lean core type and all ajv consumers remain untouched.

## Known Stubs
None — every schema field is wired to a real constrained property; no placeholder/TODO values.

## Threat Flags
None — the change introduces no new network endpoint, auth path, or file-access surface. The one boundary this phase touches (Rust codegen → schema.json → ajv consumers) is guarded exactly as the threat model prescribes: the negative fixtures + ajv-strict gate prove no constraint was dropped (T-54-03), the drift-check guards against hand-edits (T-54-04), and `validate-catalog.mjs` ran before commit without loosening any strict flag (T-54-05).

## Agent-Loop Metrics (honest)
- **Iterations to green:** ~3 build/probe cycles. (1) empirical schemars-1.2.2 probe to confirm `regex`/`length`/`url`/`extend` output before writing the real module; (2) `#[schemars(inline)]` was rejected at field level — moved it to the `SourceKind` enum container; (3) `serde_json` resolution failure in non-test code → the dependency-move deviation.
- **Timeouts:** 0.
- **Hallucinations / dead-ends:** 1 minor — initially placed `#[schemars(inline)]` on the field (per an intuitive reading) rather than the enum; the compiler's "unknown schemars attribute `inline`" caught it immediately, corrected by inspecting the schemars_derive source. No fabricated APIs shipped; every attribute was probe-confirmed before landing.
- **Review pass:** limited (no Rust-engineer role in the repo's reviewer roster and no subagent facility available; ran catalog-auditor / security-engineer / reliability-reviewer / ai-deslop / technical-writer+fact-checker rubrics directly). No actionable findings.

## Issues Encountered
None beyond the two deviations above — both resolved within the task.

## Next Phase Readiness
- TEST-03 complete: schema is generated + drift-checked; ready for Plan 54-03 (which extends the CI `rust`-job guard so the drift-check + mutants run behind it — GATE-05).
- Phase 55 (full core-type port) can now expand `types::CatalogEntry` to the full field set and, if desired, retire the codegen-only `SchemaCatalogEntry` in favor of deriving on the expanded core type — the drift-check will keep that migration honest.

## Self-Check: PASSED
- Created files verified on disk: `schema_gen.rs`, `plugin/catalog/schema.json`, `54-02-SUMMARY.md`.
- Task commits verified in git history: `91b72e0`, `d3acbba`.
- All plan `<verification>` gates re-run green (drift-check, ajv-strict real catalog, 12 fixtures incl. negatives, pre-commit `catalog-schema-validate`, `cargo test --workspace`, `clippy -D warnings`, `fmt --check`, consumers unchanged via git diff).

---
*Phase: 54-testing-bedrock*
*Completed: 2026-07-28*
