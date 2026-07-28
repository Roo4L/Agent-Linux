---
phase: 56
slug: registry-cli-verbs-subprocess-dispatcher
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-28
---

# Phase 56 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 56 is an **I/O + CLI-arg + subprocess** port — unlike Phases 53–55
> (pure logic, golden-corpus oracle), the primary oracle here is the **shipped
> bats behavior suite on the Rust build** (ADR-002) plus the dispatcher's
> 6-case parity unit spec. Pure helpers still get golden/proptest coverage.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Frameworks** | (1) Rust `cargo test` for the dispatcher parity spec + any new pure helpers; (2) the shipped **bats CLI suite on the Rust build** as the byte-compatible stdout/exit-code oracle; (3) Phase-54 `cargo-mutants --in-diff` for new pure logic |
| **Config file** | `rust/Cargo.toml` (adds `clap` derive + `nix` for SIGTERM/SIGKILL escalation — dispatcher only) |
| **Quick run command** | `cd rust && . "$HOME/.cargo/env" && cargo test --workspace` |
| **Dispatcher parity** | `cd rust && cargo test -p agentlinux dispatcher` (the 6 cases from `dispatcher-stream.test.ts`: tee+capture, non-zero-no-throw, ENOENT→1, sudo-branch, timeout→SIGTERM→124, SIGKILL escalation) |
| **CLI bats on Rust build** | Stage the Rust bin + override the provisioner symlink (`agentlinux` → Rust bin, not `dist/index.js`); targeted per-file: `AGENTLINUX_RUST_BIN=... ./tests/docker/run.sh ubuntu-24.04 40-registry-cli` (Docker OOM → NEVER full-suite in dev VM) |
| **Full suite command** | `cargo test --workspace && cargo clippy --workspace --all-targets -- -D warnings && cargo fmt --all --check` + `cargo mutants --package agentlinux-core --in-diff --relative --in-place` |
| **Estimated runtime** | ~1–2 min cargo; per-file bats ~30–90 s each |

---

## Sampling Rate

- **After every task commit:** `cargo test --workspace` (dispatcher parity + helpers)
- **After every verb lands:** its owning bats file green on the Rust build (per-file)
- **After every plan wave:** full Rust suite + `cargo mutants --in-diff` on any new pure module + the wave's bats files
- **Before verify:** all CLI bats (40-registry-cli, 23-install-user, 10-installer; 50-agents where not network/systemd-gated) green on the Rust build; dispatcher 6-case parity green; no regression on the TS build
- **Max feedback latency:** ~2 min cargo / ~90 s per bats file

---

## Per-Task Verification Map

> Seeded skeleton from the researcher's 4-wave recommendation — planner refines Task IDs/waves.

| Task ID | Plan | Wave | Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|----------|-----------|-------------------|-------------|--------|
| 56-00-01 | 00 | 0 | VERB-01 | clap CLI skeleton: 6 subcommands + flags parse == Commander surface | unit | `cd rust && cargo test -p agentlinux cli_parse` | ❌ W0 | ⬜ pending |
| 56-00-02 | 00 | 0 | VERB-03 | `RecipeEnv` single typed source sets the 6 `AGENTLINUX_*` vars | unit | `cd rust && cargo test -p agentlinux recipe_env` | ❌ W0 | ⬜ pending |
| 56-00-03 | 00 | 0 | VERB-02 | dispatcher: tee+capture, non-zero-no-throw, ENOENT→1, sudo-branch, timeout→SIGTERM→124, SIGKILL escalation | unit | `cd rust && cargo test -p agentlinux dispatcher` | ❌ W0 | ⬜ pending |
| 56-00-04 | 00 | 0 | GATE-05 | docker harness overrides `agentlinux` symlink → Rust bin (flag-gated) | manual | `AGENTLINUX_RUST_BIN=... ./tests/docker/run.sh ubuntu-24.04 40-registry-cli` | ❌ W0 | ⬜ pending |
| 56-01-01 | 01 | 1 | VERB-01 | `list` byte-compatible stdout + exit codes | bats | `... run.sh ubuntu-24.04 40-registry-cli` | ❌ W0 | ⬜ pending |
| 56-01-02 | 01 | 1 | VERB-01 | `adopt` + `pin` contract-equivalent; cache/sentinel/catalog adapters | bats | `... run.sh ubuntu-24.04 40-registry-cli` | ❌ W0 | ⬜ pending |
| 56-02-01 | 02 | 2 | VERB-01/02 | `install` (incl. `--version` positional shadow) drives dispatcher | bats | `... run.sh ubuntu-24.04 23-install-user` | ❌ W0 | ⬜ pending |
| 56-02-02 | 02 | 2 | VERB-01/02 | `remove` + `upgrade` contract-equivalent; probe/npm/rewire adapters | bats | `... run.sh ubuntu-24.04 50-agents` | ❌ W0 | ⬜ pending |
| 56-03-01 | 03 | 3 | GATE-01 | full CLI-bats green on Rust build; parity closeout | bats | per-file across 40/23/10/50 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `clap` derive CLI skeleton: 6 subcommands (`list`/`install`/`remove`/`upgrade`/`pin`/`adopt`) + all 23 flags / 4 positionals matching the Commander surface (`plugin/cli/src/index.ts`); plan-time check the bats `--help`/usage-text asserts since clap's default help text differs.
- [ ] `RecipeEnv` struct — the single typed source for the 6 `AGENTLINUX_*` names (`PINNED_VERSION`, `CATALOG_DIR`, `AGENT_HOME`, `SOURCE_KIND`, `INSTALL_LOG`, `PRESERVE_PATHS`); a rename is a compile error. Recipes read plain `${AGENTLINUX_*}` from inherited env → `Command::envs` satisfies all ~25 unchanged.
- [ ] Dispatcher module (`std::process::Command` + `nix` for SIGTERM-then-2000ms-SIGKILL; thread-per-pipe to avoid two-pipe deadlock) with all 6 parity unit tests from `dispatcher-stream.test.ts` GREEN. This is the #1 risk — gate it first.
- [ ] Docker harness: override provisioner symlink (`agentlinux` → Rust bin, not `dist/index.js`; `50-registry-cli.sh:124`) post-install, flag-gated for GATE-05; per-file to dodge Docker OOM.

*The dispatcher parity spec is the regression floor for VERB-02; the bats suite is the floor for VERB-01.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full-matrix bats on Rust build | GATE-01 (full) | Docker OOM in dev VM; full 22/24/26 matrix + QEMU is Phase 59 | Targeted per-file bats for the CLI surface; do not claim full-suite from partial |
| `50-agents` network/systemd-gated cases | VERB-01/02 | Real npm/apt/systemd side effects not reproducible in dev Docker reliably | Run the non-gated subset per-file; note gated cases deferred to Phase 59 QEMU |
| SIGKILL escalation after SIGTERM timeout | VERB-02 | Requires a recipe that ignores SIGTERM | Dispatcher unit test with a `trap '' TERM` sleep child asserts escalation to SIGKILL within the 2000ms window |

---

## Validation Sign-Off

- [ ] All tasks have automated verify (cargo/bats) or Wave 0 deps
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Every verb has a bats file green on the Rust build (byte-compatible stdout/exit)
- [ ] Dispatcher 6-case parity spec green (the VERB-02 floor)
- [ ] `agentlinux-core` stays pure; all new I/O lives in the `agentlinux` bin
- [ ] mutants gate covers any new pure helper
- [ ] Docker symlink-override staging works; no bats exits 127 for missing Rust bin
- [ ] `nyquist_compliant: true` set

**Approval:** pending
