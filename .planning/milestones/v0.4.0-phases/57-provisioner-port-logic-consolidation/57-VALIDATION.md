---
phase: 57
slug: provisioner-port-logic-consolidation
status: signed-off
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-28
signed_off: 2026-07-29
sign_off_note: >-
  Wave-5 closeout (57-06) completed the full-surface bats verification on the Rust
  provisioner across the 4-distro matrix. The Docker-runnable provisioner surface
  (10/13/14/15/18-*/20/22/23/30-six-mode/50) is GREEN on ubuntu-24.04 +
  almalinux-9 (apt/dnf floor) with ubuntu-22.04/26.04 18-pkg-dispatch spot-checks
  green; NO regression / NO newly-skipped vs the Bash provisioner (GATE-01). The
  six-mode iteration (incl. sudo_u/sudo_u_i, masked in Wave 4) is confirmed via
  the run.sh ssh-keypair seed. Remaining: the pre-existing 13-reuse #29 schema
  failure (red on BOTH builds; Phase-54-02 origin, out of scope) and the
  systemd/cron/ssh QEMU gate -> Phase 59. Sampling continuity held: every per-step
  wave's bats greened end-to-end here.
---

# Phase 57 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 57 is a **pre-Node systems-I/O** port (agent-user/sudoers/Node/PATH/
> staging) + wiring the already-ported pure core. Primary oracle: the shipped
> **bats behavior suite on the Rust provisioner**, asserting identical observable
> system state (file content + mode + owner) across the **six invocation modes**
> on **Ubuntu 22/24/26 + AlmaLinux 9**. New pure helpers (idempotency primitives,
> distro/pkg branch logic) also get Rust unit + proptest coverage.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Frameworks** | (1) the shipped **bats provisioner suite on the Rust build** (byte-fidelity oracle, ADR-002); (2) Rust `cargo test` for the ported idempotency primitives + distro/pkg branch logic; (3) Phase-54 `cargo-mutants --in-diff` for new pure helpers |
| **Config file** | `rust/Cargo.toml` (NO new crates — clap/nix/wait-timeout already present + re-verified OK) |
| **Quick run command** | `cd rust && . "$HOME/.cargo/env" && cargo test --workspace` |
| **Provisioner bats on Rust build** | `AGENTLINUX_PROVISION_RUST=1 ./tests/docker/run.sh <distro> <bats-file>` (extends the Phase-56 staging seam; Bash entrypoint stays authoritative on master → GATE-05). Docker OOM → NEVER full-suite; per-file. |
| **Distro matrix** | ubuntu-22.04, ubuntu-24.04, ubuntu-26.04 (apt), almalinux-9 (dnf) — PROV-03 parity |
| **Full suite command** | `cargo test --workspace && cargo clippy --workspace --all-targets -- -D warnings && cargo fmt --all --check` + `cargo mutants --package agentlinux-core --in-diff --relative --in-place` |
| **Estimated runtime** | ~1–2 min cargo; per-file bats ~30–120 s each × 4 distros |

---

## Sampling Rate

- **After every task commit:** `cargo test --workspace` (primitives + branch logic)
- **After every provisioner step lands:** its owning bats file green on the Rust build, per-file, on at least ubuntu-24.04 AND almalinux-9 (the apt/dnf parity pair)
- **After every plan wave:** full Rust suite + `cargo mutants --in-diff` on any new pure module + the wave's bats across the 4-distro matrix (per-file)
- **Before verify:** `RT-*` (30-runtime, six-mode), `AGT-*` (50-agents), `DET-*`/`REUSE-*`/`REMEDIATE-*`, `INST-*` (10-installer, 23-install-user) green on the Rust provisioner across Ubuntu 22/24/26 + AlmaLinux 9 (non-QEMU-gated cases); no regression on the Bash provisioner (master)
- **Max feedback latency:** ~2 min cargo / ~2 min per bats file per distro

---

## Per-Task Verification Map

> Seeded skeleton from the researcher's 6-wave recommendation — planner refines Task IDs/waves.

| Task ID | Plan | Wave | Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|----------|-----------|-------------------|-------------|--------|
| 57-00-01 | 00 | 0 | PROV-01 | `sysio.rs` — the 6 idempotency primitives (ensure_marker_block/ensure_line/atomic install mode+owner) byte-faithful to idempotency.sh | unit | `cd rust && cargo test -p agentlinux sysio` | ❌ W0 | ⬜ pending |
| 57-00-02 | 00 | 0 | PROV-03 | `distro.rs`+`pkg.rs` — apt↔dnf verb set + distro detect (Ubuntu 22/24/26 + AlmaLinux 9) | unit | `cd rust && cargo test -p agentlinux 'distro::' 'pkg::'` | ❌ W0 | ⬜ pending |
| 57-00-03 | 00 | 0 | GATE-05 | `run.sh` `AGENTLINUX_PROVISION_RUST=1` staging seam (Bash authoritative default); PROV-02 grep gate | manual | `AGENTLINUX_PROVISION_RUST=1 ./tests/docker/run.sh ubuntu-24.04 10-installer` | ❌ W0 | ⬜ pending |
| 57-01-01 | 01 | 1 | PROV-01 | `provision/agent_user.rs` — useradd + locale + CLAUDE.md marker block; idempotent | bats | `... run.sh {ubuntu-24.04,almalinux-9} 23-install-user` | ❌ W0 | ⬜ pending |
| 57-02-01 | 02 | 2 | PROV-01 | `provision/sudoers.rs` — /etc/sudoers.d/agentlinux 0440 root:root + visudo gate (BHV-07/INST-06) | bats | `... run.sh {ubuntu-24.04,almalinux-9} 22-agent-sudo` | ❌ W0 | ⬜ pending |
| 57-03-01 | 03 | 3 | PROV-01/03 | `provision/nodejs.rs` — NodeSource setup (apt/dnf) pre-Node bootstrap + version pin; idempotent | bats | `... run.sh {ubuntu-24.04,almalinux-9} 30-runtime` | ❌ W0 | ⬜ pending |
| 57-04-01 | 04 | 4 | PROV-01 | `provision/path_wiring.rs` — the four artefacts (profile.d/.bashrc-top/agentlinux.env/cron.d), six-mode PATH parity | bats | `... run.sh {ubuntu-24.04,almalinux-9} 30-runtime` (RT-* six modes) | ❌ W0 | ⬜ pending |
| 57-05-01 | 05 | 5 | PROV-01/02 | `provision/registry_cli.rs` staging + detect/remediate/reuse wiring + delete Bash CANONICAL_PATHS/GSD_SYSTEM_PATH + --purge/--dry-run parity | bats | `... run.sh {ubuntu-24.04,almalinux-9} 10-installer 50-agents` | ❌ W0 | ⬜ pending |
| 57-05-02 | 05 | 5 | GATE-01 | full provisioner bats green on Rust build across the 4-distro matrix; parity closeout | bats | per-file across 10/23/22/30/50 × 4 distros | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `sysio.rs` — port the 6 `idempotency.sh` primitives (ensure_marker_block, ensure_line, atomic file install with mode+owner at rename via `nix`), each with a Rust unit test asserting byte-identical output + mode + owner. These are the load-bearing "same observable state" primitives; byte-fidelity (trailing newline, marker delimiters, ordering) is asserted by the bats.
- [ ] `distro.rs` + `pkg.rs` — the distro-detect (Ubuntu 22/24/26 + AlmaLinux 9) + apt↔dnf verb abstraction (`pkg.sh` 226 LOC). The PROV-03 parity surface; unit-test each branch.
- [ ] `run.sh` `AGENTLINUX_PROVISION_RUST=1` staging seam — the Bash entrypoint stays authoritative by default (GATE-05 rollback); the flag routes provisioning through the Rust bin, fail-loud (missing bin → hard error, never silent Bash fallback that false-greens).
- [ ] PROV-02 grep gate: a check that fails if `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` still has a live Bash definition after Wave 5 deletes it (single-source enforcement).

*No new crates; the pure gates + Phase-56 adapters are the reuse floor.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| systemd `User=agent` + cron invocation modes | PROV-01 (2 of 6 modes) | Docker can't reproduce systemd/cron reliably | Prove interactive/ssh/sudo_u/sudo_u_i in Docker now; systemd_user + cron defer to Phase 59 QEMU — do not claim green from Docker |
| Full 4-distro matrix + QEMU release gate | GATE-01 (full) | Docker OOM in dev VM; full matrix + QEMU is Phase 59 | Per-file bats on ubuntu-24.04 + almalinux-9 (the apt/dnf pair) as the in-phase floor; full 22/24/26 + EL9 QEMU → Phase 59 |
| NodeSource live fetch | PROV-01 | Depends on the live NodeSource endpoint | Run the real install in Docker where available; note network dependency |

---

## Validation Sign-Off

- [ ] All tasks have automated verify (cargo/bats) or Wave 0 deps
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Every provisioner step has a bats file green on the Rust build on BOTH ubuntu-24.04 AND almalinux-9 (apt/dnf parity)
- [ ] The six-mode PATH matrix (RT-*) green for the 4 Docker-runnable modes; systemd/cron recorded as Phase-59 QEMU
- [ ] `agentlinux-core` stays pure; all new I/O in the `agentlinux` bin
- [ ] mutants gate covers any new pure helper (distro/pkg branch logic, primitives' pure parts)
- [ ] PROV-02: no live Bash `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` remains (grep gate green)
- [ ] Staging seam fail-loud; no bats false-greens on the Bash provisioner while claiming Rust
- [ ] `nyquist_compliant: true` set

**Approval:** pending
