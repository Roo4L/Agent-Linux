---
phase: 56-registry-cli-verbs-subprocess-dispatcher
plan: 03
subsystem: registry-cli (Rust rewrite — mutating verbs)
tags: [rust, verbs, install, remove, upgrade, dispatcher, npm, rewire, probe]
status: complete
requires:
  - "56-01 (dispatcher.rs / recipe_env.rs / cli.rs — VERB-02/03 primitives + clap surface)"
  - "56-02 (catalog.rs / sentinel.rs / cache.rs / guard.rs + list/pin/adopt verbs)"
  - "agentlinux-core (decide_version, compute_divergence, resolve_latest_for, detect_gates, semver_shim)"
provides: "the three mutating verbs (install/remove/upgrade) + probe/npm/rewire adapters — VERB-01 complete for all six verbs; VERB-02/VERB-03 proven on REAL recipe dispatch"
affects:
  - rust/crates/agentlinux/src/probe.rs
  - rust/crates/agentlinux/src/npm.rs
  - rust/crates/agentlinux/src/rewire.rs
  - rust/crates/agentlinux/src/cmd/install.rs
  - rust/crates/agentlinux/src/cmd/remove.rs
  - rust/crates/agentlinux/src/cmd/upgrade.rs
  - rust/crates/agentlinux/src/main.rs
  - rust/crates/agentlinux/src/cmd/mod.rs
tech-stack:
  added: []
  patterns:
    - "DI dispatcher seam (fn-pointer) on every verb so unit tests exercise the exit map + literals + branch selection with NO sudo/network"
    - "pure gate + adapter statSync/existsSync split — the DECISION lives in agentlinux-core; the host I/O lives in the verb"
    - "buffered npm dispatch honors the 30_000ms timeout (Open Q2); parses npm ls JSON even on non-zero exit (Pitfall 5)"
key-files:
  created:
    - rust/crates/agentlinux/src/probe.rs
    - rust/crates/agentlinux/src/npm.rs
    - rust/crates/agentlinux/src/rewire.rs
    - rust/crates/agentlinux/src/cmd/install.rs
    - rust/crates/agentlinux/src/cmd/remove.rs
    - rust/crates/agentlinux/src/cmd/upgrade.rs
  modified:
    - rust/crates/agentlinux/src/main.rs
    - rust/crates/agentlinux/src/cmd/mod.rs
decisions:
  - "install command exposes no --json flag in index.ts, so install.ts's opts.json dry-run branch is unreachable — the Rust port always prints the [DRY-RUN] text line (matches real TS behavior)"
  - "shouldReinstall ported as a bin-side pure helper (it reads only report+opts, has no agentlinux-core home yet) — Open Q3 disposition"
  - "validateReusedBinary's statSync lives in the upgrade adapter (bin I/O); the flag-priority logic is the pure shouldReinstall helper"
metrics:
  duration: "~1h"
  completed: 2026-07-28
  tasks: 4
  commits: 3
  files_created: 6
  files_modified: 2
  unit_tests_added: 34
---

# Phase 56 Plan 03: Registry CLI Mutating Verbs (install/remove/upgrade) Summary

Wave 2 of the like-for-like TS→Rust registry-CLI port: the three mutating verbs
(`install`/`remove`/`upgrade`) plus the `probe`/`npm`/`rewire` adapters, driving
the Wave-0 subprocess dispatcher (VERB-02) with the `RecipeEnv` 6-var contract
(VERB-03) end-to-end on REAL Bash recipes for the first time. VERB-01 is now
complete across all six verbs; the pure `agentlinux-core` was untouched.

## What shipped

- **`probe.rs`** — `probe_installed_version`: reads `<npm-prefix>/lib/node_modules/<pkg>/package.json`,
  normalizes via `semver_shim::valid`; `None` for non-npm / absent / non-semver.
- **`npm.rs`** — `query_global_npm` (`npm ls -g --json`, parses the JSON EVEN on a
  non-zero exit — Pitfall 5) and `query_npm_view_latest` (`npm view … versions
  --json` → `resolve_latest_for`), both via the BUFFERED dispatcher with a
  `30_000`ms timeout (Open Q2). DI seam so unit tests inject a canned dispatch.
- **`rewire.rs`** — `reconcile_cross_wiring`: after a wireable coding agent is
  installed, re-runs each installed provider's rewire recipe; best-effort (never
  fails the install).
- **`cmd/install.rs`** — full `install.ts` port: usage exits (64) for
  `--dry-run`+`--yes` / unknown / test-only-without-`--include-test` / bad
  `--version` semver; `--dry-run` `[DRY-RUN]` preview (no dispatch); REUSE-03
  (pure `reuse_gate` + adapter `statSync` → reused sentinel + `[REUSE-03]`);
  REMEDIATE-04 (pure `remediate_gate`; non-TTY `--yes` bail=65; uninstall dispatch
  → post-uninstall `existsSync`=1 if present → install dispatch; broken-after-
  remediate trail; `[REMEDIATE-04]`); `decide_version` idempotent no-op; create
  path streams `install.sh`, propagates the recipe exit, writes the sentinel, then
  `reconcile_cross_wiring`. Byte-exact literals (`▸ installing`/`installed`/`no-op`).
- **`cmd/remove.rs`** — `remove.ts` port: 64 unknown / 1 not-installed-without-
  `--force` / 0 force-no-op / reused-binary-vanished sentinel delete; streaming
  `uninstall.sh` dispatch; `▸ removing`/`removed`; recipe exit propagated +
  sentinel preserved on failure.
- **`cmd/upgrade.rs`** — `upgrade.ts` port: pure `compute_divergence` +
  `presence_gate` overlay + npm INSTALLED column + opt-in `resolve_latest_for`;
  `shouldReinstall` pure flag-priority helper; `validateReusedBinary` `statSync`
  in the adapter; padded 7-column table
  `[ID,STATUS,SENTINEL,INSTALLED,CURATED,LATEST,SRC]` or `--json` (present
  overlay); reconcile loop `continue`s per-entry on failure (never aborts, exit 0),
  preserving the sentinel.
- **`main.rs`** — routes `Command::Install/Remove/Upgrade` to the new verbs
  (the Wave-1 not-implemented stubs removed).

## Verification (per task)

| Task | Verify | Result |
|------|--------|--------|
| 1 (probe/npm/rewire) | `cargo test -p agentlinux -- probe::/npm::/rewire::` | PASS — probe 5, npm 9, rewire 4 |
| 2 (install) | `cargo test -p agentlinux -- cmd::install` | PASS — 10 |
| 3 (remove/upgrade) | `cargo test -p agentlinux -- cmd::remove cmd::upgrade` | PASS — remove 6, upgrade 9 |
| 4 (bats gate) | `AGENTLINUX_STAGE_RUST_CLI=1 ./tests/docker/run.sh ubuntu-24.04 {40-registry-cli,23-install-user,50-agents}` | install/remove/upgrade cases GREEN (see below) |

Workspace-wide: `cargo test --workspace` → **228 passed**; `cargo clippy -p
agentlinux --all-targets -- -D warnings` → **clean**; `cargo fmt --all --check`
→ **clean**.

### bats on the staged Rust musl bin (Task 4)

- **40-registry-cli** (ubuntu-24.04): the install/remove/upgrade cases are all
  GREEN — CLI-03 install (13), idempotent no-op (14), `--force` (15), `--version
  9.9.9`→source=override (16); CLI-04 remove (17), remove not-installed 1/force-0
  (18); CLI-06 upgrade report-only no-mutation (21). CLI-05 guard 19/20 green,
  CLI-07 pin 22/23, CAT/INST 24-29 green.
- **23-install-user** (ubuntu-24.04): **all 9 INST-07 cases GREEN**, including AC4
  ("catalog op dispatches recipes as the configured user (claude)") — the
  dispatcher `sudo -u` path + `resolve_install_user` + guard exercised end-to-end
  on a real recipe as a non-agent user. VERB-02/VERB-03 proven on a real user.
- **50-agents** (ubuntu-24.04): the REAL `agentlinux install
  claude-code/gsd/playwright-cli` (`setup_file`) all SUCCEEDED through the Rust
  dispatcher — proven by AGT-02b/02c/03/04/05/06 (12 cases; the artifact/version
  assertions on the real installed binaries) all GREEN.

## Deviations from Plan

### Rule-driven / design deviations (no user permission needed)

**1. [Rule 3 — API differs] install `--json` dry-run branch is unreachable**
- **Found during:** Task 2. `install.ts` references `opts.json` in the `--dry-run`
  branch, but `index.ts`'s install command declares NO `--json` option (and the
  Wave-0 `InstallArgs` clap struct correctly omits it).
- **Fix:** The Rust port drops the dead JSON branch and always prints the
  `[DRY-RUN]` text line — byte-identical to the only reachable TS path.
- **File:** `rust/crates/agentlinux/src/cmd/install.rs` (documented inline). Commit `d75341d`.

**2. [Open Q3] `shouldReinstall` ported to the bin, not `agentlinux-core`**
- The flag-priority helper reads only `report + opts` and has no core home yet;
  ported as a bin-side pure fn (matching the plan's "or note it could go to core"
  latitude). `validateReusedBinary`'s `statSync` stays in the adapter.

### Non-Rust-verb failures (staging / infra — NOT verb regressions, deferred to Phase 59)

These bats cases fail under the plain-Docker + `AGENTLINUX_STAGE_RUST_CLI`
staging harness for reasons orthogonal to the install/remove/upgrade verbs. They
are the network/systemd/ssh-gated dimension the plan (and 56-VALIDATION
§Manual-Only) defers to the Phase-59 QEMU/full-matrix gate. NOT counted as a Rust
pass and NOT a red introduced by these verbs.

| Case | File | Why (staging/infra, not a verb) |
|------|------|--------------------------------|
| CLI-01 (interactive) `binary resolves under .npm-global/bin` | 40-registry-cli | The `AGENTLINUX_STAGE_RUST_CLI` override re-points the CLI symlink at `.local/bin/agentlinux`, so `command -v` resolves the staged target — a harness artifact. The run.sh staging reconciliation is explicit Wave-3 closeout scope (Plan 04). |
| CLI-01 (ssh) `--version from every invocation mode` | 40-registry-cli | The `ssh` invocation mode fails with `Permission denied (publickey,password)` — the Docker container has no agent ssh key; systemd/ssh invocation modes need the QEMU harness. |
| AGT-01 ×3 (claude/gsd/playwright — "every invocation mode") | 50-agents | Same ssh/systemd invocation-mode limitation. The SAME binaries pass the plain-invocation assertions (AGT-02b/03/05), so the installs themselves are green; only the ssh/cron/systemd modes fail (no `SKIP_SYSTEMD_UNAVAILABLE` sentinel in Docker → they fail rather than skip). Deferred to Phase-59 QEMU. |

Per-file runs only (Docker OOM avoided); the bats specs were UNCHANGED; the
Plan-01 fail-loud staging guard prevented any false-green.

## Self-Check: PASSED

- All six created files exist on disk.
- All three task commits are in `git log`: `8cd40d0` (probe/npm/rewire),
  `d75341d` (install), `26efc7e` (remove/upgrade).
- Task 4 required no code changes (all verb cases passed on the first staged run),
  so it carries no separate commit — its acceptance was met by Tasks 1-3.
