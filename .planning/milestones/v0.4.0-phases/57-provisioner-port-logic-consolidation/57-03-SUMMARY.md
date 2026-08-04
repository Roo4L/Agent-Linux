---
phase: 57-provisioner-port-logic-consolidation
plan: 03
subsystem: rust-provisioner
tags: [rust, provisioner, sudoers, security, adr-012, byte-fidelity]
requires:
  - "sysio::{write_file_atomic,visudo_validate,ensure_dir} (57-01)"
  - "pkg::pkg_install + distro::Family (57-01)"
  - "ProvisionCtx / Resolutions + orchestrator step vec (57-02)"
provides:
  - "provision::sudoers::run — the visudo-gated 0440 root:root NOPASSWD drop-in step"
  - "orchestrator step 20 wired (sudoers) after agent_user"
affects:
  - "rust/crates/agentlinux/src/cmd/provision.rs (step vec: sudoers now live)"
tech-stack:
  added: []
  patterns:
    - "DECIDE-THEN-ACT dispatch on RESOLUTIONS[sudoers] token"
    - "visudo TOCTOU belt (validate-before + re-verify-after) around an atomic install"
    - "single install_or_overwrite helper shared by create + remediate arms"
    - "RAII TmpCleanup guard mirroring Bash trap RETURN tmpfile cleanup"
key-files:
  created:
    - rust/crates/agentlinux/src/provision/sudoers.rs
  modified:
    - rust/crates/agentlinux/src/provision/mod.rs
    - rust/crates/agentlinux/src/cmd/provision.rs
decisions:
  - "chown root:root explicitly after write_file_atomic (belt over the euid-inherited owner) to guarantee install(1) -o root -g root parity even for a CAP_CHOWN non-root caller"
  - "pre-install visudo candidate written via a dedicated same-dir tmpfile (write_tmp) so the real install still routes through the audited write_file_atomic primitive"
metrics:
  duration_min: 6.1
  completed: 2026-07-28
  tests_added: 4
  workspace_tests: 291
status: complete
---

# Phase 57 Plan 03: provision/sudoers.rs (20-sudoers.sh port) Summary

Ported `plugin/provisioner/20-sudoers.sh` + `plugin/lib/remediate/sudoers.sh` into
`provision/sudoers.rs`: the visudo-gated `/etc/sudoers.d/agentlinux` 0440 root:root
NOPASSWD drop-in (ADR-012), with the security-critical TOCTOU belt (visudo -cf
validate-before + re-verify-after) and one `install_or_overwrite` source of truth
for both the create and remediate arms — byte-identical to the Bash path, GREEN on
the apt/dnf pair.

## What was built

- **`provision/sudoers.rs`** (`pub fn run(ctx: &ProvisionCtx)`): ensures `visudo`
  exists first (`pkg::pkg_install(family, ["sudo"])` if absent — apt on debian,
  dnf on rhel), re-asserts `/etc/sudoers.d` at `0755 root:root`, then dispatches on
  `ctx.resolutions.sudoers`:
  - `Reuse` → no-op (`[REUSE]` marker)
  - `Create` → `install_or_overwrite("install")`
  - `Remediate` → `install_or_overwrite("overwrite")` (`--yes` gate passed upstream)
  - `ReuseWithWarning` → `[REUSE-WARN] component=sudoers`, leave file as-is
  - `Bail` → defensive `Err` (unreachable — a bail exits 65 before the step loop)
- **`install_or_overwrite`** — the ONE helper both arms route through: builds the
  byte-exact content (static ADR-012 header + `<user> ALL=(ALL) NOPASSWD: ALL`),
  writes a tmpfile, `visudo_validate` BEFORE the atomic `write_file_atomic(0o440)`
  install, `chown root:root`, then `visudo_validate` AFTER (the TOCTOU belt). Either
  visudo failure is a hard error — a malformed sudoers can never land.
- **Wiring**: `pub mod sudoers;` in `provision/mod.rs`; `provision::sudoers::run(&ctx)`
  slotted into the orchestrator step vec after `agent_user`, replacing the Wave-2
  not-yet-wired marker in `cmd/provision.rs`.

## Byte-fidelity

The drop-in content is byte-exact vs the Bash heredoc: the two static header lines
(UTF-8 em-dash preserved), the NOPASSWD grant line for the resolved install user,
one trailing newline. Proven end-to-end: bats test 7 (sha256 byte-stable across a
**Bash** `agentlinux-install` re-run) passed on BOTH distros — i.e. the Rust-produced
file is byte-identical to what the Bash provisioner would write.

## Verification

- `cargo fmt --all --check` — clean.
- `cargo clippy -p agentlinux --all-targets -- -D warnings` — clean.
- `cargo test --workspace` — 291 passed / 0 failed (baseline 287 + 4 new sudoers tests).
- Acceptance greps: `visudo_validate` non-comment call count = 2 (before + after);
  `fn install_or_overwrite` count = 1; only `rust/` changed (GATE-05 — Bash provisioner
  untouched).
- **`22-agent-sudo.bats` on the Rust provisioner (`AGENTLINUX_PROVISION_RUST=1`):**
  - ubuntu-24.04 — 7/7 GREEN (`== PASS ==`)
  - almalinux-9 — 7/7 GREEN (`== PASS ==`)
  - Both distros run the fresh musl bin's `20-sudoers: [REMEDIATE-03] … mode 0440
    root:root — ADR-012` and pass BHV-07 (0440 root:root, visudo-clean, NOPASSWD line,
    byte-stable) + INST-06 (`sudo -n true` / `sudo -n -l` for the agent user).

## Deviations from Plan

**1. [Rule 3 - Blocking] Stale prebuilt musl binary caused a false-red first bats run.**
- **Found during:** Task 1 verify.
- **Issue:** The docker runner's `host_build_musl` (`tests/docker/run.sh:257`)
  early-returns if `$HOST_MUSL_BIN` already exists — it never rebuilds a stale bin.
  The cached `rust/target/x86_64-unknown-linux-musl/release/agentlinux` predated my
  edit, so the first bats run staged a binary still printing "20-sudoers step
  not-yet-wired (Wave 2)" and all 7 tests failed.
- **Fix:** Rebuilt the musl bin explicitly
  (`cargo build --release --target x86_64-unknown-linux-musl -p agentlinux`) before
  re-running; confirmed the `20-sudoers: starting` string is present in the bin.
  This is a harness caching artifact, not a source defect — no code change needed,
  and out of scope to change the runner's rebuild logic (Wave-scope: rust/ only).
- **Files modified:** none (build artifact only).

Otherwise the plan executed as written.

## Threat mitigations applied (from `<threat_model>`)

- **T-57-07 (DoS — malformed sudoers locks out host):** mitigated — the visudo -cf
  TOCTOU belt (pre-install validate + post-install re-verify) is present; the two
  calls are asserted by the acceptance grep. A failed check aborts non-zero and never
  installs.
- **T-57-08 (Elevation via the NOPASSWD line):** mitigated — the install-user name is
  charset-validated (`^[a-z][a-z0-9_-]*$` + reserved denylist) upstream in
  `cmd/provision.rs` before it reaches the sudoers line; that upstream guard is now
  load-bearing (a future change removing it could allow sudoers injection). Documented
  in the module doc.

## Known Stubs

None. The step is fully wired and functional. (`RESOLUTIONS[sudoers]` is seeded
`create` until Wave 5 lands the real detect→decide — the consumed-token seam is
intentional and carried from 57-02, not a stub in this step.)

## Self-Check: PASSED

- `rust/crates/agentlinux/src/provision/sudoers.rs` — FOUND
- commit `56850c9` — FOUND
- `22-agent-sudo.bats` GREEN on ubuntu-24.04 + almalinux-9 on the Rust provisioner — VERIFIED
