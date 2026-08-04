---
phase: 55
slug: pure-logic-core-parity
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-28
---

# Phase 55 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust `cargo test` (golden corpora ported verbatim from the TS `.test.ts` tables + proptest invariants) + the Phase-54 `cargo-mutants` gate + the shipped bats/CLI suites for no-regression |
| **Config file** | `rust/Cargo.toml` (no new deps — proptest/semver already staged) |
| **Quick run command** | `cd rust && . "$HOME/.cargo/env" && cargo test --workspace` |
| **Full suite command** | `cd rust && cargo test --workspace && cargo clippy --workspace --all-targets -- -D warnings && cargo fmt --all --check` + `cargo mutants --package agentlinux-core --in-diff --relative --in-place` on the new modules |
| **Estimated runtime** | ~1–2 min cargo; mutants bounded by `--in-diff` |

---

## Sampling Rate

- **After every task commit:** `cargo test --workspace` (golden parity + proptest)
- **After every plan wave:** full Rust suite + `cargo mutants --in-diff` on the new pure modules
- **Before verify:** every ported function's golden corpus green (byte-for-byte TS parity), proptest green, mutants gate green, no bats/CLI regression
- **Max feedback latency:** ~2 min

---

## Per-Task Verification Map

> Seeded skeleton — planner refines Task IDs/waves.

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 55-01-01 | 01 | 1 | CORE-03 | `semver_shim::valid` (STRICT) + `satisfies` match node-semver | unit | `cd rust && cargo test -p agentlinux-core semver_shim` | ❌ W0 | ⬜ pending |
| 55-02-01 | 02 | 2 | CORE-03 | `category` derivation == TS across category.test.ts corpus | golden | `cd rust && cargo test -p agentlinux-core category` | ❌ W0 | ⬜ pending |
| 55-02-02 | 02 | 2 | CORE-03 | `parse_pin_spec` == TS across pin.test.ts parse cases (+ 2 distinct error messages) | golden | `cd rust && cargo test -p agentlinux-core pin_spec` | ❌ W0 | ⬜ pending |
| 55-02-03 | 02 | 2 | CORE-03 | detect-gate pure deciders (reuse/remediate/presence + isCanonicalAgentPath) == TS | golden | `cd rust && cargo test -p agentlinux-core detect_gates` | ❌ W0 | ⬜ pending |
| 55-03-01 | 03 | 3 | CORE-01/02 | classify + divergence corpus re-assert; decideVersion folded in (5-row golden) | golden | `cd rust && cargo test -p agentlinux-core classify decide divergence` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Extend `semver_shim` with `valid` (STRICT parse — the A1 node-parity subtlety, NOT `parse_lenient` coercion) + `satisfies`, each with a golden cross-check row. This UNBLOCKS parsePinSpec + detect gates.
- [ ] `types.rs` additions: `DetectedAgent` struct (mirrors `DetectCacheAgent`), `Category`, tags/source_kind as needed by the ported deciders.
- [ ] Port the TS golden tables (category.test.ts, pin.test.ts parse cases, detect-gate cases, decideVersion 5-row) as Rust `#[test]` modules — the parity oracle.

*Existing classify/divergence tests are the regression floor; no new framework.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full-matrix bats on Rust build | GATE-01 (full) | Docker OOM in dev VM; full matrix is Phase 59 | Targeted per-file bats for any touched surface (the CLI detect/pin/list tests); do not claim full-suite from partial |
| semver valid/satisfies node-parity edge cases | CORE-03 (A1) | node-semver deps uninstalled | The golden cross-check rows encode the expected node verdicts from the TS corpora; document the boundary |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 deps
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Every ported function has a byte-for-byte TS golden corpus
- [ ] `agentlinux-core` stays pure (no std::process/fs/env — the cache I/O is Phase 56)
- [ ] mutants gate covers the new modules
- [ ] `nyquist_compliant: true` set

**Approval:** pending
