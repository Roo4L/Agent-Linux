---
phase: 54
slug: testing-bedrock
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-28
---

# Phase 54 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust `cargo test` (proptest properties run here) + `cargo-mutants` (mutation) + `schemars` schema-gen drift check + a semver-parity golden test |
| **Config file** | `rust/Cargo.toml` (dev-deps: proptest 1.11; schemars 1.2.2 for the codegen bin/test); `cargo-mutants` 27.1 installed in CI |
| **Quick run command** | `cd rust && . "$HOME/.cargo/env" && cargo test --workspace` |
| **Full suite command** | `cd rust && cargo test --workspace && cargo clippy --workspace --all-targets -- -D warnings && cargo fmt --all --check` + schema drift check (`generated == committed plugin/catalog/schema.json`) + `cargo mutants --package agentlinux-core --in-diff` |
| **Estimated runtime** | ~1–2 min cargo/proptest; mutants bounded by `--in-diff` under the rust job's 15-min cap |

---

## Sampling Rate

- **After every task commit:** `cargo test --workspace` (proptest + unit + golden)
- **After every plan wave:** full Rust suite + schema drift check; run `cargo mutants --in-diff` on the touched core
- **Before verify:** proptest green, schema drift-check green (ajv-strict + real catalog.json + 12 schema.test.ts fixtures still pass), semver golden green, no bats regression
- **Max feedback latency:** ~2 min (cargo); mutants out-of-band

---

## Per-Task Verification Map

> Seeded skeleton — planner refines Task IDs/waves.

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 54-01-01 | 01 | 1 | TEST-01 | classify total/deterministic; sticky⇒{synced,pinned-override}; latest satisfies-or-typed-error | property | `cd rust && cargo test -p agentlinux-core --test proptest_invariants` | ❌ W0 | ⬜ pending |
| 54-01-02 | 01 | 1 | TEST-04 | Rust semver verdicts == node-semver corpus on catalog ranges | golden | `cd rust && cargo test -p agentlinux-core semver_parity` | ❌ W0 | ⬜ pending |
| 54-02-01 | 02 | 2 | TEST-03 | schemars-generated schema == committed schema.json; ajv-strict + catalog.json + 12 fixtures green | integration | schema-gen bin + `diff generated plugin/catalog/schema.json` + `node plugin/cli/scripts/validate-catalog.mjs` | ❌ W0 | ⬜ pending |
| 54-03-01 | 03 | 2 | TEST-02 | cargo-mutants gate on the pure core (advisory→gate) | mutation | `cd rust && cargo mutants --package agentlinux-core --in-diff` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Add dev-deps: `proptest = "1.11"`; `schemars = "1.2"` (codegen path); `cargo-mutants` installed in CI (cache).
- [ ] proptest generators for version-string + range inputs (catalog-realistic).
- [ ] Codegen-only `SchemaCatalogEntry` (full-field) with `#[derive(JsonSchema)]` — do NOT derive on the lean 5-field `CatalogEntry` (would emit a broken schema).

*Existing 44 unit tests + the shipped ajv fixtures are the regression floor.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| cargo-mutants threshold choice | TEST-02 | "agreed threshold" is a policy decision | Orchestrator (autonomous) accepts the research default: advisory→gate at zero un-skipped surviving mutants on `--in-diff` per-PR; full score nightly (reuse existing nightly-mutation workflow) |
| Full-matrix bats on Rust build | GATE-01 (full) | Docker OOM in dev VM; full matrix is Phase 59 | Targeted per-file bats for any touched surface; do not claim full-suite from partial |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 deps
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] schema drift-check is functional-equivalent (ajv-strict + catalog + fixtures), not byte-parity
- [ ] mutants gate can't block a non-Rust hotfix (behind rust-job guard, GATE-05)
- [ ] `nyquist_compliant: true` set

**Approval:** pending
