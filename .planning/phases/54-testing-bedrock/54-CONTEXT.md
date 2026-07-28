# Phase 54: Testing Bedrock - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning
**Mode:** Smart-discuss infrastructure-skip (test/schema machinery on the pure core; no user-facing behavior). Codebase scout populated below.

<domain>
## Phase Boundary

Stand up the property + mutation + schema-generation + semver-parity machinery on
the Phase-53 pure-logic core (`rust/crates/agentlinux-core`) **before** the bulk
port, so the rigor that motivated the whole rewrite is operational — not
aspirational. Deliverables:

1. **TEST-01** — `proptest` property tests asserting the core's invariants:
   `classify` is total & deterministic; `sticky ⇒ status ∈ {synced, pinned-override}`;
   latest-resolution output always satisfies the constraint or returns a typed error.
2. **TEST-02** — `cargo-mutants` runs on the pure crate in CI, reporting a mutation
   score gated at an agreed threshold (advisory→gate).
3. **TEST-03** — the catalog JSON Schema is generated from Rust catalog types via
   `schemars` (single source of truth); CI fails if committed `schema.json` drifts
   from generated output.
4. **TEST-04** — a `node-semver` → Rust `semver` behavior-parity audit doc + a
   golden test asserting identical `satisfies`/`maxSatisfying`/`valid` verdicts on
   the current catalog ranges.
5. **GATE-01 / GATE-05** — full bats green for the ported surface (no regression /
   no newly-skipped); master stays shippable; parallel track; per-phase rollback.

OUT of scope: porting more logic (Phase 55), CLI verbs (56), provisioner (57).
This phase only adds TEST machinery around the EXISTING Phase-53 core.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (infrastructure phase)
All implementation choices at Claude's discretion — testing/schema machinery, no
user-observable behavior change. Recommended shape below for the planner; not binding.

### Recommended
- **proptest** targets the pure core's total functions (classify, semver_shim
  parse/normalize, reuse::agent_decision, resolve_latest_for). Invariants over
  generated inputs; shrinking on failure. Keep generators catalog-realistic.
- **cargo-mutants** scoped with `--package agentlinux-core` (the crate is pure by
  design precisely so mutants can target it). Start advisory (report score), then
  set a `--minimum-test-timeout` and an agreed threshold gate in CI; a red mutants
  run must be gated so it can't block a master hotfix (GATE-05), same guard shape
  as the Phase-53 `rust` job.
- **schemars**: add `#[derive(JsonSchema)]` to the Rust catalog types
  (`agentlinux-core::types` — CatalogEntry etc.), generate `schema.json`, and add a
  CI drift-check (`generated == committed`, else fail). The generated schema MUST
  still validate the real `plugin/catalog/catalog.json` and keep the existing
  TS-side ajv validator (`plugin/cli/scripts/validate-catalog.mjs`) + pre-commit
  `catalog-schema-validate` hook GREEN — do not break the shipped validation path;
  reconcile Rust-generated schema with the 2020-12 hand-written one (schema.json,
  109 LOC). If exact byte-parity with the hand-written schema is impractical,
  document the reconciliation and make the DRIFT-CHECK authoritative (generated is
  the SoT), updating the ajv consumer to read the generated file.
- **semver parity (TEST-04)**: the live catalog uses only caret (`^2.1`) +
  compound comparators — the Phase-53 `semver_shim` already handles these. This
  phase writes the audit DOC (every range/prerelease case) + a golden test locking
  `satisfies`/`maxSatisfying`/`valid` verdicts against the current catalog. Full
  prerelease edge-case audit beyond the catalog's current ranges stays here (it's
  TEST-04's home); do not expand catalog ranges.

</decisions>

<code_context>
## Existing Code Insights (from scout)

### proptest / cargo-mutants target — the pure core (Phase 53)
- `rust/crates/agentlinux-core/src/` — 1027 LOC: classify.rs (143), divergence.rs
  (269), reuse.rs (255), semver_shim.rs (274), types.rs (73), lib.rs (13).
- The crate is intentionally pure (no std::process/fs/env) so `cargo-mutants
  --package agentlinux-core` scopes cleanly. Existing 44 unit tests are the
  regression floor the mutation score builds on.

### schemars target — TEST-03
- `plugin/catalog/schema.json` (109 LOC, hand-written 2020-12) + `plugin/cli/src/types.ts`
  (CatalogEntry) are the two hand-maintained artifacts that drift today.
- Consumers to keep green: `plugin/cli/scripts/validate-catalog.mjs` (ajv) + the
  `catalog-schema-validate` pre-commit hook + `plugin/catalog/catalog.json` (the
  real data the schema validates).
- Rust `agentlinux-core::types` already has a CatalogEntry with (speculative,
  Phase-53-flagged) serde derives — add `schemars::JsonSchema` here.

### semver parity target — TEST-04
- Catalog ranges in use: caret `^2.1` (the only `version_constraint`); all other
  entries pin exact `pinned_version`. `semver_shim` (normalize_range + parse_lenient)
  already handles compound + `v`-prefix + partial. The audit formalizes this.

### CI integration
- `.github/workflows/test.yml` `rust` job (Phase 53) — extend it (or add a sibling
  gated job) for proptest (runs under `cargo test`), the mutants gate, and the
  schema-drift check. Mirror the existing gated guard shape (GATE-05).

</code_context>

<specifics>
## Specific Ideas

- This phase makes the "testing rigor" that justified the rewrite REAL on the pure
  core before the bulk port — every later port (55-57) then lands behind a live gate.
- Keep master shippable; all on branch `worktree-stack-revisiting`.
- cargo-mutants can be slow — bound its runtime in CI and gate it so it never
  blocks a non-Rust hotfix (GATE-05); acceptable to start advisory and ratchet.

</specifics>

<deferred>
## Deferred Ideas

- Full pure-core port (category derivation, detect gates, pin-spec) → Phase 55.
- CLI verbs + generated env-var contract → Phase 56.
- Provisioner port + CANONICAL_PATHS consolidation → Phase 57.

</deferred>
