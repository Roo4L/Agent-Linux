---
phase: 59
slug: full-validation-gate
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-29
---

# Phase 59 — Validation Strategy

> Per-phase validation contract. Phase 59 is the FINAL, milestone-closing VALIDATION
> GATE — it proves the Rust rewrite is behavior-preserving at full matrix scale, wires
> CI/QEMU to gate on the Rust build, audits coverage, and validates the canonical AGT-02
> acceptance test. It is validation + CI-wiring + red-resolution, not new feature code.

---

## ⚠️ Dev-runnable vs. CI/QEMU-gated (the structural split)

This dev VM OOMs on the full Docker suite and has no KVM/live-release env. So the gate
SPLITS — and the phase must NEVER fake a local full-matrix pass:
- **Dev-runnable (the in-phase floor):** per-file bats on the Rust build across the 4
  distros (`run.sh <t> <file>`), the `behavior-coverage-auditor` (GATE-03), a targeted
  `claude update` on the Rust chain where the CDN is reachable (GATE-04 smoke).
- **CI/QEMU-gated (WIRED + documented, proven by the pipeline — NOT faked locally):**
  the full Docker matrix (`test.yml`), the full QEMU matrix (`nightly-qemu.yml` +
  `tests/qemu/boot.sh`), and the live-CDN AGT-02 gate (`release.yml` gate-3/4). The
  deliverable for these is green-in-CI + the correct wiring, evidenced by the phase's PR
  CI run + the nightly/release pipeline.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Frameworks** | the full bats behavior contract (42 files) on the Rust build; `behavior-coverage-auditor` (GATE-03); `51-agt02-release-gate.bats` (GATE-04); the CI/QEMU pipelines (GATE-02) |
| **Config file** | `.github/workflows/{test,nightly-qemu,release}.yml`, `tests/qemu/boot.sh`, `tests/docker/run.sh` |
| **Dev per-file bats** | `./tests/docker/run.sh <distro> <bats-file>` — the musl provisioner is the DEFAULT (no flag, Phase 58); OOM-safe per-file |
| **Coverage audit** | the `behavior-coverage-auditor` agent over REQUIREMENTS.md → bats/harness evidence on the Rust build |
| **AGT-02 (GATE-04)** | `51-agt02-release-gate.bats` on the Rust chain + a real `claude update` (zero EACCES) where the CDN is reachable |
| **cargo floor** | `cargo test --workspace` (~338) + clippy + fmt stay green |
| **Estimated runtime** | per-file bats ~1–2 min each; coverage audit ~fast; full matrix + QEMU = CI |

---

## Sampling Rate

- **After the red fixes:** the three carried reds go green (13-reuse #29 on the Rust build; HRN-05; HRN-06) — re-run each per-file
- **After the QEMU re-wire:** `tests/qemu/boot.sh` runs the Rust `provision` (not the Bash entrypoint) + asserts the running provisioner IS the musl bin — the key GATE-02 fix (a boot.sh unit/smoke check; full QEMU is CI)
- **Before verify:** the dev-runnable per-file bats green across the 4 distros on the Rust build; the coverage auditor reports zero uncovered (GATE-03); the AGT-02 smoke green (GATE-04 dev floor); CI wired for the full matrix + QEMU + live-CDN
- **Max feedback latency:** ~2 min per bats file / coverage audit fast

---

## Per-Task Verification Map

> Seeded skeleton from the researcher's 3-wave recommendation — planner refines.

| Task ID | Plan | Wave | Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|----------|-----------|-------------------|-------------|--------|
| 59-00-01 | 00 | 0 | GATE-01 | fix stale 13-reuse #29 (schema emits `["string","null"]` from `Option<String>`; schema is TEST-03 SoT → fix the TEST assertion) | bats | `... run.sh ubuntu-24.04 13-reuse` (32/32) | ❌ W0 | ⬜ pending |
| 59-00-02 | 00 | 0 | GATE-01 | HRN-05 (`.planning/research/SUMMARY.md` restored) + HRN-06 (`0440\|sudoers` in security-engineer.md) | harness | `bash tests/harness/run.sh` | ❌ W0 | ⬜ pending |
| 59-01-01 | 01 | 1 | GATE-02 | `tests/qemu/boot.sh` re-pointed at the Rust `provision` (NOT the Bash entrypoint) + asserts the running provisioner is the musl bin | smoke | `bash -n tests/qemu/boot.sh` + the provisioner-identity assertion | ❌ W0 | ⬜ pending |
| 59-01-02 | 01 | 1 | GATE-02 | confirm `test.yml` Docker matrix + `release.yml` gates build/run the Rust build (Phase 58 default); wire any gap | CI-config | grep/read the workflows | ❌ W0 | ⬜ pending |
| 59-02-01 | 02 | 2 | GATE-03 | `behavior-coverage-auditor` reports zero uncovered on the Rust build (every family BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC + RUST/TEST/CORE/VERB/PROV/DIST/GATE) | audit | run the auditor → coverage report | ❌ W0 | ⬜ pending |
| 59-02-02 | 02 | 2 | GATE-04 | AGT-02 `claude update` zero-EACCES on the Rust chain (dev smoke where CDN reachable; the isolated-invocation false-green trap avoided); live-CDN = release.yml CI gate | bats | `... run.sh ubuntu-24.04 51-agt02-release-gate` | ❌ W0 | ⬜ pending |
| 59-02-03 | 02 | 2 | GATE-05 | declare the Rust track master-ready; TS/Bash retained as rollback (NO cutover deletion); master shippable | manual | verify plugin/cli + Bash entrypoint retained; final green summary | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Resolve the 3 carried pre-existing reds so the gate is genuinely green:
  - **13-reuse #29:** the schema (TEST-03 source-of-truth) correctly emits `["string","null"]` from `Option<String>` (schemars) — fix the STALE TEST assertion at `13-reuse.bats:552` (`type=="string"` → accept the nullable union), NOT the schema. Re-run → 32/32.
  - **HRN-05:** restore the `.planning/research/SUMMARY.md` the harness meta-test expects (stripped by planning-hygiene).
  - **HRN-06:** add the `0440|sudoers` evidence line to `.claude/agents/security-engineer.md`.
- [ ] `bash tests/harness/run.sh` fully green after the HRN fixes.

*These are the ONLY known non-environment reds; the gate cannot be declared green until they pass.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full Docker matrix (22/24/26 + EL9) | GATE-02 | OOMs in dev VM | Green-in-CI via `test.yml` on the phase PR; per-file locally as the floor |
| Full QEMU matrix + live-CDN AGT-02 | GATE-02/04 | No KVM / live-release env in dev | Wired in `nightly-qemu.yml`/`release.yml` (re-pointed at Rust); proven by the nightly/release pipeline, documented not faked |
| Live-CDN `claude update` at scale | GATE-04 | Depends on the live Anthropic CDN | Dev smoke where reachable; the authoritative gate is release.yml against the live CDN |

---

## Validation Sign-Off

- [ ] The 3 carried reds are GREEN (13-reuse 32/32 on the Rust build; HRN-05; HRN-06); `tests/harness/run.sh` green
- [ ] `tests/qemu/boot.sh` runs the Rust `provision` + asserts the musl-bin provisioner (the #1-risk GATE-02 fix) — no false green on the Bash path
- [ ] `test.yml` + `release.yml` confirmed to build/run the Rust build; any gap wired
- [ ] `behavior-coverage-auditor` reports ZERO uncovered on the Rust build (GATE-03)
- [ ] AGT-02 zero-EACCES on the Rust chain (dev smoke); the isolated-invocation false-green trap avoided; live-CDN gate wired in CI (GATE-04)
- [ ] Dev-runnable per-file bats green across the 4 distros on the Rust build; CI wired for the full matrix + QEMU (documented, not faked)
- [ ] TS/Bash rollback substrate RETAINED (no cutover deletion); master shippable; the Rust track DECLARED ready to become master (GATE-05)
- [ ] `nyquist_compliant: true` set

**Approval:** pending
