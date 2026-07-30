---
phase: 56-registry-cli-verbs-subprocess-dispatcher
plan: 04
subsystem: registry-cli (Rust rewrite — phase closeout / parity)
tags: [rust, cli, bats, dispatcher, parity, gate-01, staging, phase-closeout]
status: complete
requires:
  - "56-01 (dispatcher.rs / recipe_env.rs / cli.rs + run.sh staging override — VERB-02/03 + GATE-05 harness)"
  - "56-02 (catalog/sentinel/cache/guard adapters + list/pin/adopt — VERB-01 read verbs)"
  - "56-03 (install/remove/upgrade + probe/npm/rewire — VERB-01 mutating verbs; VERB-02/03 on real recipes)"
provides: "GATE-01 phase gate — full CLI bats surface green on the Rust build (per-file); CLI-01 interactive-mode staging reconciled; the VERB-01/02/03 + GATE-01/05 sign-off; the consolidated Phase-59-deferred (env-gated) remainder"
affects:
  - tests/docker/run.sh
  - .planning/phases/56-registry-cli-verbs-subprocess-dispatcher/56-VALIDATION.md
tech-stack:
  added: []
  patterns:
    - "flag-gated CLI staging relocates the Rust bin OFF the agent PATH (/opt/agentlinux/rust/agentlinux) so it cannot shadow the canonical ~agent/.npm-global/bin/agentlinux symlink by name — the reuse shim's AGENTLINUX_RUST_BIN accepts any absolute path, so the off-PATH move is transparent to 13-reuse.bats"
    - "staging-mechanic reconciliation, not a source change: the CLI-01 fix lives entirely in the test harness (run.sh); zero rust/ or plugin/cli/ churn — the version string was already pinned to package.json 0.3.6 in Wave 0"
key-files:
  created:
    - .planning/phases/56-registry-cli-verbs-subprocess-dispatcher/56-04-SUMMARY.md
  modified:
    - tests/docker/run.sh
    - .planning/phases/56-registry-cli-verbs-subprocess-dispatcher/56-VALIDATION.md
decisions:
  - "CLI-01 interactive failure was a HARNESS-staging artifact (a Rust bin named `agentlinux` at ~agent/.local/bin — first on the interactive login PATH — shadowed the canonical .npm-global/bin symlink), NOT a CLI behavior gap; fixed by relocating the staged bin off-PATH (Rule 3 blocking-issue auto-fix, harness-side)"
  - "ssh invocation mode (CLI-01 ssh, AGT-01 x3) is genuinely env-gated — the Docker container has no agent ssh keypair; deferred to Phase 59 QEMU, not claimed green"
  - "INST-02 (installer byte-stable idempotency) is a PURE-installer test that is out-of-scope for the CLI surface and incompatible with the post-install CLI-symlink override under the flag; it is GREEN on the shipped TS path (master unaffected), only perturbed by the parallel-track staging — resolved in Phase 57 when the provisioner natively symlinks the Rust bin"
  - "No residual cross-verb parity fix was needed: Waves 1-2 already greened every non-env-gated verb case when the whole 40-registry-cli file runs end-to-end"
metrics:
  duration: "~45m"
  completed: 2026-07-28
  tasks: 2
  commits: 1
  files_created: 1
  files_modified: 2
  unit_tests_added: 0
---

# Phase 56 Plan 04: CLI Parity Closeout + GATE-01 Phase Gate Summary

Wave 3 — the phase closeout. It proves the FULL CLI bats surface green on the
Rust build (per-file, Docker-OOM-safe), reconciles the last staging artifact
(CLI-01 interactive-mode resolution), re-asserts the VERB-02 dispatcher floor
after all six verbs are wired, and consolidates the environment-gated remainder
into an unambiguous Phase-59 QEMU deferral. VERB-01/02/03 + GATE-01/GATE-05 are
signed off. Zero `rust/` or `plugin/cli/` churn — the only source change is a
test-harness staging fix in `tests/docker/run.sh`.

## What shipped

- **CLI-01 interactive-mode reconciliation** (`tests/docker/run.sh`): the RUST-03
  reuse-path staging drops the Rust bin at `~agent/.local/bin/agentlinux`, which
  sits FIRST on the agent's interactive login PATH (Ubuntu's skel `~/.profile`
  prepends `~/.local/bin` ahead of `/etc/profile.d/agentlinux.sh`'s
  `.npm-global/bin`). A bin literally named `agentlinux` there SHADOWED the
  canonical `~agent/.npm-global/bin/agentlinux` symlink, so under
  `AGENTLINUX_STAGE_RUST_CLI=1` CLI-01's `command -v agentlinux` resolved
  `.local/bin` instead of the contract-required `.npm-global/bin`. Fix: when the
  CLI override is active, RELOCATE the staged bin off the agent PATH (to
  `/opt/agentlinux/rust/agentlinux` — an absolute path the reuse shim's
  `AGENTLINUX_RUST_BIN` accepts verbatim), drop the front-of-PATH
  `.local/bin/agentlinux` copy, and point the `.npm-global/bin` symlink at the
  relocated bin. `command -v agentlinux` then resolves the canonical symlink
  (byte-identical to master's TS resolution) across interactive / sudo_u /
  sudo_u_i / systemd_user / cron. The default flag-unset `.local/bin` staging
  for `13-reuse.bats` is UNTOUCHED; the fail-loud missing-bin guard is preserved.

- **VERB-02 dispatcher-floor re-assert**: `cargo test -p agentlinux dispatcher`
  = 9 passed, re-run AFTER all six verbs wired `dispatch_recipe` — no regression
  from the verb integration.

- **VALIDATION.md flipped**: `nyquist_compliant: true` + `wave_0_complete: true`;
  the full sign-off checklist is checked with evidence.

## Per-verb → bats-file green matrix (VERB-01)

| Verb    | bats file(s)              | Green cases |
|---------|---------------------------|-------------|
| list    | 40-registry-cli           | CLI-02 (3), AL-61 list/present (8,11), AL-62 (11), CAT-01/04 (24,26) |
| install | 40-registry-cli, 23-install-user | CLI-03 (13-16); INST-07 AC1-AC5 all 9 (real recipe dispatch as non-agent user `claude`) |
| remove  | 40-registry-cli           | CLI-04 (17,18) |
| upgrade | 40-registry-cli, 50-agents | CLI-06 report-only no-mutation (21); AGT report path renders real agents |
| pin     | 40-registry-cli           | CLI-07 (22,23) |
| adopt   | 40-registry-cli           | AL-61 adopt (6,7,9), AL-62 adopt migrate (12) |

## Full per-file bats breakdown (staged Rust bin, ubuntu-24.04, per-file)

| File | Result | Detail |
|------|--------|--------|
| **40-registry-cli** | 27/29 green; 2 red = ssh-mode only | Tests 3-29 GREEN. Tests 1-2 (CLI-01 "every invocation mode") pass interactive/sudo_u/sudo_u_i/systemd_user/cron; abort ONLY at the `ssh` mode (`Permission denied (publickey)` — no agent ssh key in Docker). Interactive mode was RECONCILED this wave (was the sole reconcilable red in Wave 2). |
| **23-install-user** | 9/9 GREEN | All INST-07 AC1-AC5 pass, incl. AC4 (catalog op dispatches recipes as the configured user `claude`) — VERB-02/03 on a real non-agent user. |
| **10-installer** | 10/11 green; 1 red = INST-02 under flag | INST-01, INST-05, DOC-02, CAT-05 all green. INST-02 (installer byte-stable idempotency) is a PURE-installer test; it re-runs `agentlinux-install`, which resets the CLI symlink to the TS bundle after the harness override, so its pre/post symlink-target check drifts. On master (TS, no flag) 10-installer is **11/11 GREEN** — INST-02 is only perturbed by the parallel-track staging, not by any Rust verb. Out-of-scope for the CLI surface; resolved in Phase 57. |
| **50-agents** | 9/12 green; 3 red = ssh-mode only | AGT-02b/02c/03/04/05/06 all green (12 assertions on the REAL installed claude/gsd/playwright binaries — installs succeeded through the Rust dispatcher). AGT-01 x3 ("every invocation mode") abort ONLY at the `ssh` mode — same missing-ssh-key limitation. Note: AGT-01 exercises the `claude`/`gsd`/`playwright` binaries, not `agentlinux`, so its ssh failure is orthogonal to the Rust port entirely. |

Per-file runs only (Docker OOM avoided — never the full `tests/bats/` dir).

## Per-mode CLI-01 proof (the reconciliation, verified in-container)

| Invocation mode | `command -v agentlinux` | `agentlinux --version` | Status |
|-----------------|-------------------------|------------------------|--------|
| interactive     | `/home/agent/.npm-global/bin/agentlinux` | `agentlinux 0.3.6` | ✅ green (reconciled this wave) |
| sudo_u          | `/home/agent/.npm-global/bin/agentlinux` | `agentlinux 0.3.6` | ✅ green |
| sudo_u_i        | `/home/agent/.npm-global/bin/agentlinux` | `agentlinux 0.3.6` | ✅ green |
| systemd_user    | `/home/agent/.npm-global/bin/agentlinux` | `agentlinux 0.3.6` | ✅ green |
| cron            | `/home/agent/.npm-global/bin/agentlinux` | (resolves) | ✅ green |
| ssh             | `Permission denied (publickey)` | — | ⏸ Phase-59 QEMU (no agent ssh key in Docker) |

5 of 6 invocation modes green; ssh is the sole env-gated mode.

## Phase-59-deferred (environment-gated — enumerated, NOT claimed green)

| Case | File | @test | Gate reason |
|------|------|-------|-------------|
| CLI-01 (ssh) | 40-registry-cli | "agentlinux binary resolves under .npm-global/bin in every invocation mode" | `ssh agent@localhost` fails `Permission denied (publickey,password)` — the Docker container has no agent ssh keypair (the `20-agent-user.bats` keypair setup does not run when a single CLI file is invoked in isolation). QEMU harness provides a real login. |
| CLI-01 (ssh) | 40-registry-cli | "agentlinux --version prints package.json version from every invocation mode" | Same ssh-key limitation. |
| AGT-01 (ssh) x3 | 50-agents | claude/gsd/playwright "--version/--help exits 0 in every invocation mode" | Same ssh-key limitation. There is no `SKIP_SYSTEMD_UNAVAILABLE`-style sentinel for ssh, so the mode hard-fails rather than skipping in Docker. The SAME binaries pass their plain-invocation assertions (AGT-02b/03/05), so the installs are green — only the ssh mode is gated. |
| INST-02 (under `AGENTLINUX_STAGE_RUST_CLI`) | 10-installer | "re-running the installer is byte-stable (idempotency)" | Pure-installer test; incompatible with the post-install CLI-symlink override under the flag (the in-test installer re-run resets the symlink to the TS bundle). GREEN on the shipped TS path (master unaffected). Resolves in Phase 57 when the provisioner natively symlinks the Rust bin, making a re-run byte-stable again. |

The systemd invocation mode is NOT deferred — systemd runs as PID 1 in the
`--privileged --cgroupns=host` Docker container, and CLI-01/AGT-01 pass under it.

## VERB-01/02/03 + GATE-01/GATE-05 sign-off

- **VERB-01 (six verbs byte-compatible)** ✅ — list/install/remove/upgrade/pin/adopt
  all pass their owning bats cases on the Rust build with byte-compatible stdout +
  identical exit codes; the bats specs are unchanged (the fixed contract).
- **VERB-02 (dispatcher floor + real-recipe dispatch)** ✅ — `cargo test -p
  agentlinux dispatcher` = 9 green (tee+capture, non-zero-no-throw, buffered,
  sudo-branch, ENOENT→1, timeout→124, SIGKILL escalation, buffered-timeout, real
  `dispatch_recipe`), re-asserted after all six verbs wired the shared dispatch
  path. Real-recipe dispatch is proven end-to-end by 23-install-user AC4 (recipe
  dispatched as user `claude`) and 50-agents (real claude/gsd/playwright installs).
- **VERB-03 (one typed `RecipeEnv` source; ~25 recipes unchanged)** ✅ — the 6
  `AGENTLINUX_*` vars flow from a single typed struct; CLI-03/CAT-04 prove
  `AGENTLINUX_PINNED_VERSION` reaches the recipe (`version=0.0.1` in the marker),
  and the real-agent installs prove the ~25 unchanged Bash recipes read the
  inherited env correctly.
- **GATE-01 (full CLI bats green on the Rust build, no regression / no
  newly-skipped)** ✅ — the full CLI surface is green per-file; every red is an
  enumerated environment-gated case (ssh mode) or an out-of-scope pure-installer
  test perturbed only by the parallel-track staging. No bats gate was weakened;
  no test was newly skipped vs. the TS build.
- **GATE-05 (TS build not regressed; master shippable)** ✅ — the only change is
  `tests/docker/run.sh` (a flag-gated test harness); `git diff --name-only` shows
  no `plugin/cli/` and no `rust/` churn. The provisioner still symlinks the TS
  bundle; the Rust bin runs ONLY under `AGENTLINUX_STAGE_RUST_CLI=1`.

## Verification (per task)

| Task | Verify | Result |
|------|--------|--------|
| 1 (full CLI bats + staging reconcile) | per-file 40/23/10/50 on the staged Rust bin | 40: 27/29 (2 ssh); 23: 9/9; 10: 10/11 (1 INST-02-under-flag); 50: 9/12 (3 ssh) — all non-env-gated cases GREEN, CLI-01 interactive reconciled |
| 2 (dispatcher floor + workspace gate + sign-off) | `cargo test -p agentlinux dispatcher` + `cargo test --workspace` + clippy + fmt + core-purity | dispatcher 9 passed; workspace **228 passed**; clippy clean; fmt clean; core production code pure |

Workspace-wide: `cargo test --workspace` → **228 passed**;
`cargo clippy --workspace --all-targets -- -D warnings` → **clean**;
`cargo fmt --all --check` → **clean**.

Core purity: the naive plan grep flags 4 `std::fs`/`std::env` lines in
`agentlinux-core`, but ALL are inside `#[test]` functions
(`parity_catalog_ranges_all_round_trip_the_shim` in `semver_shim.rs`,
`schema_is_not_drifted` in `schema_gen.rs` — test-only catalog/schema oracles);
the remaining matches are `//!` doc comments. Production runtime code has zero
`std::process`/`std::fs`/`std::env` — `agentlinux-core` stayed pure.

## Deviations from Plan

### Rule-driven (no user permission needed)

**1. [Rule 3 — blocking issue] CLI-01 interactive staging reconciled off-PATH**
- **Found during:** Task 1, first full 40-registry-cli run against the staged bin.
- **Issue:** `command -v agentlinux` (interactive login) resolved
  `/home/agent/.local/bin/agentlinux` instead of the contract-required
  `.npm-global/bin` — because the RUST-03 reuse-path staging dropped a bin named
  `agentlinux` at `.local/bin`, which is first on the interactive login PATH (via
  Ubuntu's skel `~/.profile`), shadowing the canonical symlink. This was the
  reconcilable staging artifact the Wave-2 note flagged (a `.local/bin` vs
  `.npm-global/bin` target detail).
- **Fix:** Relocate the flag-gated staged bin off the agent PATH
  (`/opt/agentlinux/rust/agentlinux`) and drop the `.local/bin/agentlinux` copy,
  so `command -v` resolves the canonical `.npm-global/bin` symlink. Harness-side
  only (`tests/docker/run.sh`); the reuse shim's `AGENTLINUX_RUST_BIN` (absolute
  path, any name) follows the relocated bin; fail-loud guard preserved; the
  default flag-unset `.local/bin` staging for `13-reuse.bats` is untouched.
- **File:** `tests/docker/run.sh`. Commit `1ffbe2c`.

### Deferrals (env-gated — see the Phase-59-deferred table above)

- ssh invocation mode (CLI-01 ssh on 40; AGT-01 ssh x3 on 50) → Phase-59 QEMU
  (no agent ssh keypair in Docker).
- INST-02 under `AGENTLINUX_STAGE_RUST_CLI` → Phase-57 (pure-installer test,
  incompatible with the post-install CLI-symlink override; green on the TS path).

**No residual cross-verb parity fix was needed** — Waves 1-2 already greened
every non-env-gated verb case when the whole 40-registry-cli file runs
end-to-end. No `rust/` source changed this wave.

## Self-Check: PASSED

- `tests/docker/run.sh` change committed (`1ffbe2c`), verified in `git log`.
- `56-VALIDATION.md` flipped to `nyquist_compliant: true` + `wave_0_complete: true`
  with an evidenced sign-off.
- `git diff --name-only tests/bats/` is EMPTY (bats specs unchanged).
- `git diff --name-only` shows only `tests/docker/run.sh` (+ `.planning/` docs) —
  no `plugin/cli/` and no `rust/` churn (GATE-05 held).
- Dispatcher floor (9), workspace (228), clippy, fmt all re-verified green.
