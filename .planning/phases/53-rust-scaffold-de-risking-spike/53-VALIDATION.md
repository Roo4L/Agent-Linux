---
phase: 53
slug: rust-scaffold-de-risking-spike
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-28
---

# Phase 53 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust `cargo test` (unit + parity golden corpus) + existing bats-core (behavior oracle) |
| **Config file** | `rust/Cargo.toml` (workspace) — installed in Wave 0 |
| **Quick run command** | `cd rust && cargo test --workspace` |
| **Full suite command** | `cd rust && cargo test --workspace && cargo clippy --workspace -- -D warnings && cargo fmt --check` then targeted bats: `./tests/docker/run.sh ubuntu-24.04 tests/bats/13-reuse.bats` |
| **Estimated runtime** | ~30–90 s Rust (cold build longer); ~2–4 min per targeted bats container |

---

## Sampling Rate

- **After every task commit:** Run `cargo test --workspace` (+ `cargo clippy`/`fmt` on the touched crate)
- **After every plan wave:** Run the full Rust suite + the targeted bats file(s) covering the ported surface
- **Before `/gsd-verify-work`:** Rust suite green AND the ported-surface bats file(s) green (no newly-skipped tests — GATE-01)
- **Max feedback latency:** ~90 s for Rust; bats is out-of-band (per-file container)

---

## Per-Task Verification Map

> Seeded skeleton — the planner refines Task IDs/waves to match PLAN.md. The load-bearing rows are the semver parity corpus and the reuse-seam bats.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 53-01-01 | 01 | 0 | RUST-01 | — | static musl binary builds; `ldd` → not dynamic | integration | `cd rust && cargo build --release --target x86_64-unknown-linux-musl && ldd target/x86_64-unknown-linux-musl/release/agentlinux` | ❌ W0 | ⬜ pending |
| 53-01-02 | 01 | 1 | RUST-03/CORE | — | classify verdicts identical to TS corpus | unit | `cd rust && cargo test -p agentlinux-core classify` | ❌ W0 | ⬜ pending |
| 53-01-03 | 01 | 1 | RUST-03/CORE | — | divergence + maxSatisfying match TS corpus incl. zero-match error + `normalize_range`/lenient-parse shims | unit | `cd rust && cargo test -p agentlinux-core divergence` | ❌ W0 | ⬜ pending |
| 53-02-01 | 02 | 2 | RUST-03/GATE-01 | — | reuse decision token identical; 13-reuse.bats green via Rust behind shim | bats | `./tests/docker/run.sh ubuntu-24.04 tests/bats/13-reuse.bats` | ✅ | ⬜ pending |
| 53-03-01 | 03 | 2 | RUST-02 | — | CI: build+clippy+fmt+test rust job on PR | ci | `.github/workflows/test.yml` rust job (act/dry-verify) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `rust/Cargo.toml` + `rust/crates/agentlinux-core/` + `rust/crates/agentlinux/` — cargo workspace scaffold
- [ ] Port the `divergence.test.ts` + `classify.test.ts` tables into Rust `#[test]` golden-corpus modules (parity oracle)
- [ ] Toolchain already installed this session (rustc/cargo 1.97.1, musl target, musl-gcc, clippy, rustfmt) — no framework install needed

*Existing bats infrastructure covers the provisioner-seam behavior (13-reuse.bats); no new bats file required for the spike.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full-matrix bats green on Rust build | GATE-01 (full) | Full Docker suite OOMs in dev VM (documented); full matrix + QEMU is Phase 59's gate | Spike validates only the ported-surface file(s); record which bats files were exercised, do not claim full-suite green from a partial run |
| Agent-loop cost metrics | RUST-03 | Observation of the porting process itself, not a code assertion | Record iterations-to-green, cargo-timeout + crate-hallucination incidents to `53-METRICS.md` as the port proceeds |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (cargo workspace + parity corpora)
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s (Rust)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
