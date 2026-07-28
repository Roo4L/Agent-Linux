---
phase: 56-registry-cli-verbs-subprocess-dispatcher
verified: 2026-07-28T00:00:00Z
status: gaps_found
score: 7/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
requirements_verified: [VERB-01, VERB-02, VERB-03, GATE-01, GATE-05]
gaps:
  - truth: "The Rust `cargo test` parity harness is reliably green on the default (parallel) test runner"
    status: partial
    reason: >-
      The bin test suite (107 tests) flakes ~15% of default-parallel `cargo test --workspace`
      runs. Root cause is a test-harness defect, NOT a parity/logic bug: 10 test modules each
      declare their OWN module-private `ENV_LOCK` mutex but all mutate the SAME process-global
      env vars (AGENTLINUX_STATE_DIR / AGENTLINUX_CATALOG_DIR / AGENTLINUX_DETECT_CACHE). A
      per-module lock cannot serialize cross-module tests, so under cargo's parallel thread pool
      a test in one module removes an env var another module's test is mid-read of → `None.unwrap()`
      panic → that module's ENV_LOCK is poisoned → cascade of `PoisonError` panics in sibling tests.
      The failures are always env-race panics, never a parity-value assertion mismatch. Single-threaded
      (`--test-threads=1`) and per-module-isolated runs are 228/228 deterministically green, proving the
      shipped verb parity is correct.
    artifacts:
      - path: "rust/crates/agentlinux/src/cmd/pin.rs:173"
        issue: "module-private `static ENV_LOCK` over process-global env; races with sibling modules"
      - path: "rust/crates/agentlinux/src/cmd/upgrade.rs:498"
        issue: "second independent ENV_LOCK; same process-global env; poisons on cross-module race"
      - path: "rust/crates/agentlinux/src/sentinel.rs:203"
        issue: "third independent ENV_LOCK; comment admits AGENTLINUX_STATE_DIR is process-global"
    missing:
      - "One shared process-wide serialization lock (single `static` in a shared test-support module) for ALL tests that mutate AGENTLINUX_* process env — replacing the 10 per-module ENV_LOCKs"
      - "OR: make the env seams non-global (thread-local / passed-in config) so tests need no lock"
      - "OR: force `--test-threads=1` in the bin's test invocation (CI + docs) and document that the default parallel run is expected-flaky, so `228 passed` is not over-claimed"
deferred:
  - truth: "ssh invocation-mode assertions (CLI-01 ssh; AGT-01 ssh x3) green"
    addressed_in: "Phase 59"
    evidence: "Phase 59 success criteria: full bats contract green across Docker + QEMU with a real login. run_ssh (invoke_modes.bash:20,39) requires an agent keypair set up in 20-agent-user.bats, which does not run in per-file isolation — genuinely env-gated, verified independently, not a verb regression (5/6 modes green asserting the identical thing)."
  - truth: "INST-02 installer byte-stable idempotency green under the AGENTLINUX_STAGE_RUST_CLI flag"
    addressed_in: "Phase 57"
    evidence: "Phase 57 provisioner natively symlinks the Rust bin. INST-02 (10-installer.bats:36) snapshots the CLI symlink target pre/post an in-test installer re-run; under the flag the re-run resets the symlink to the TS bundle → drift. GREEN 11/11 on master (TS, no flag) — a harness/staging artifact, not a Rust verb defect."
---

# Phase 56: Registry CLI Verbs + Subprocess Dispatcher Verification Report

**Phase Goal:** Port the user-facing registry CLI — list/install/remove/upgrade/pin/adopt — plus the subprocess dispatcher and the typed env-var recipe contract, so `agentlinux <verb>` produces contract-equivalent stdout + exit codes to the TS CLI and the ~25 unchanged Bash recipes still run correctly against a single generated source of truth.
**Verified:** 2026-07-28
**Status:** gaps_found (1 test-harness flakiness gap; shipped verb parity is correct; 2 legitimately-deferred env-gated bats cases)
**Re-verification:** No — initial verification

## Verdict

**PARTIAL — GOAL SUBSTANTIVELY ACHIEVED, one non-blocking test-harness defect.**

The verb parity, dispatcher, and env-var contract are all correctly implemented and behaviorally verified. The one gap is a **test-infrastructure flakiness bug** (per-module ENV_LOCKs over process-global env), NOT a masked parity regression: the parity logic is 228/228 deterministically green single-threaded and per-module-isolated; the flake is always an env-race panic, never a wrong-value assertion. The deferred ssh/INST-02 bats cases were independently confirmed genuinely environment-gated. Master is untouched. This is safe to transition to Phase 57 **after** the ENV_LOCK flakiness is fixed (or the default-parallel green claim is qualified) — the flake will otherwise intermittently red the CI Rust job.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The 6 verbs (list/install/remove/upgrade/pin/adopt) parse via clap with the exact Commander surface and produce contract-equivalent stdout + exit codes (VERB-01) | ✓ VERIFIED | All 6 `cmd/*.rs` verb bodies present + substantive + wired via `main.rs` routing (git diff shows real implementations, no stubs/todo!/unimplemented). Parity asserted by the UNCHANGED bats specs run on the staged Rust bin: 40-registry-cli 27/29 (2 red = ssh-only), 23-install-user 9/9, 50-agents non-network 9/12 (3 red = ssh-only). Every non-env-gated verb case green. Rust unit corpus (pin/upgrade/install/remove/adopt/list) 228/228 single-threaded. |
| 2 | The dispatcher runs recipes as target user (`sudo -u`), tees, enforces timeout, escalates SIGTERM→SIGKILL (VERB-02) | ✓ VERIFIED | dispatcher.rs is a real impl: `["sudo","-u",user,"-H","-E","--"]` argv (invoker==target short-circuit, lines 85-104); thread-per-pipe tee (stream_tee); `wait_timeout` + `nix::sys::signal::kill` SIGTERM→`KILL_GRACE=2000ms`→SIGKILL (lines 43-52,183-191); timeout→124 (stream)/1 (buffered) parity map. `cargo test -p agentlinux dispatcher` = **9 passed** (incl. sigterm_ignoring_child_escalates_to_sigkill, timeout_maps_to_124, buffered_timeout_maps_to_1, stream_tees_and_captures, enoent_maps_to_one). 0/10 flake over 10 isolated runs. |
| 3 | The 6 `AGENTLINUX_*` recipe env names come from ONE typed Rust source; a rename is a compile error; ~25 recipes read them unchanged (VERB-03) | ✓ VERIFIED | The 6 recipe-contract pairs (PINNED_VERSION/CATALOG_DIR/AGENT_HOME/SOURCE_KIND/INSTALL_LOG/PRESERVE_PATHS) are produced in exactly one function — `RecipeEnv::into_env_pairs` (recipe_env.rs:67-77) — fed by struct fields, so a field rename is a compile error. No second PRODUCER exists (the other hits of these literals are read-seams: catalog.rs:51 `env::var`, main.rs:136 agent-home heuristic, plus `#[cfg(test)]` fixtures). 58 catalog recipe files read `${AGENTLINUX_*}` unchanged (git diff shows zero plugin/catalog churn). |
| 4 | Full CLI bats surface GREEN on the Rust build, no regression, no newly-skipped test (GATE-01) | ✓ VERIFIED (with enumerated env-gated deferrals) | Bats specs UNCHANGED: `git diff 210db3e..HEAD -- tests/bats/` = **0 lines** (parity comes from Rust matching the spec, not weakening it). Every non-env-gated case green per-file. The 4 red cases are enumerated deferrals (ssh×4 → Phase 59; INST-02-under-flag → Phase 57), each independently confirmed env-gated below — NOT newly-skipped and NOT masked regressions. |
| 5 | `master` stays shippable; verb port reversible per-phase (GATE-05) | ✓ VERIFIED | `git rev-parse master` = f14c092 (untouched; branch is worktree-stack-revisiting). Phase-56 diff (210db3e..HEAD) touches ONLY `rust/**` + `tests/docker/run.sh` (flag-gated staging harness). ZERO churn in plugin/bin, plugin/cli, plugin/provisioner, plugin/catalog, packaging. Rust bin staged only behind `AGENTLINUX_STAGE_RUST_CLI`; provisioner still symlinks the TS bundle. Additive + reversible. |
| 6 | `agentlinux-core` stays pure (no I/O in production code) | ✓ VERIFIED | grep of core `src/` for std::process/std::fs/std::env in non-test, non-doc code → the only hits are inside `#[cfg(test)]` modules: semver_shim.rs:492 (parity_catalog_ranges test, mod tests @185), schema_gen.rs:145/148/153 (schema_is_not_drifted, `#[cfg(test)] mod tests` @121). No production I/O. |
| 7 | Deferred bats cases are genuinely env-gated, not masked verb regressions | ✓ VERIFIED | CLI-01/AGT-01 ssh: run_ssh (invoke_modes.bash:20,39) requires an agent keypair created in 20-agent-user.bats, absent in per-file isolation → "Permission denied (publickey)". CLI-01 asserts the IDENTICAL thing across all 6 modes and passes in 5 (interactive/sudo_u/sudo_u_i/systemd_user/cron) → verb behavior proven; only the ssh transport is gated. INST-02: harness symlink override vs installer re-run drift; 11/11 green on master. Both correctly enumerated as Phase-59/57 deferrals. |
| 8 | The Rust parity harness is reliably green on the default (parallel) test runner | ✗ FAILED (test-harness only) | `cargo test --workspace` flaked ~15% (≈4 failures / 26 runs) with env-race panics (`None.unwrap()`, `PoisonError`) across pin/upgrade modules. Root cause: 10 module-private `ENV_LOCK`s over ONE process-global env (pin.rs:173, upgrade.rs:498, sentinel.rs:203, +7). Cross-module races poison locks. Single-threaded = 228/228 deterministic; per-module isolation = green. NOT a parity/logic bug — the shipped verbs are correct — but the CI Rust job will intermittently red. |

**Score:** 7/8 truths verified (0 present, behavior-unverified). Truth 8 is a test-infrastructure defect, not a shipped-code parity failure.

### Deferred Items

Items not green in per-file Docker but explicitly and correctly deferred to a later phase (independently confirmed env-gated, not verb regressions).

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | CLI-01 ssh + AGT-01 ssh ×3 (invocation-mode assertions) | Phase 59 | No agent ssh keypair in per-file Docker isolation (20-agent-user.bats keypair setup doesn't run); run_ssh requires it. 5/6 modes green asserting the same thing. QEMU provides a real login. |
| 2 | INST-02 idempotency under `AGENTLINUX_STAGE_RUST_CLI` | Phase 57 | Pure-installer test; harness symlink override vs in-test installer re-run drifts the symlink target. 11/11 GREEN on master (TS, no flag). Phase 57 provisioner natively symlinks the Rust bin. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `rust/crates/agentlinux/src/cli.rs` | clap surface: 6 verbs, 23 flags, install --version shadow | ✓ VERIFIED | Present, substantive, wired via main.rs; CLI-01/CLI-03 bats green in 5 modes. |
| `rust/crates/agentlinux/src/dispatcher.rs` | sudo-u/tee/timeout/SIGTERM→SIGKILL | ✓ VERIFIED | Real nix::signal impl; 9 dispatcher tests pass; 0/10 flake. |
| `rust/crates/agentlinux/src/recipe_env.rs` | single typed source of 6 env pairs | ✓ VERIFIED | `into_env_pairs` sole producer (lines 67-77); field-rename = compile error. |
| `rust/crates/agentlinux/src/cmd/list.rs` | padded table + suffixes + --by-category/--json | ✓ VERIFIED | list green on 40-registry-cli. |
| `rust/crates/agentlinux/src/cmd/pin.rs` | state-only sentinel mutation, exact literals | ✓ VERIFIED (parity) / ⚠️ flaky harness | pin logic correct; test module races cross-module (Truth 8). |
| `rust/crates/agentlinux/src/cmd/adopt.rs` | reuse-record only, [ADOPT]/[MIGRATE] literals | ✓ VERIFIED | adopt green on 40-registry-cli. |
| `rust/crates/agentlinux/src/cmd/install.rs` | reuse\|remediate\|create → dispatch install.sh | ✓ VERIFIED | Real dispatch; 23-install-user 9/9; 50-agents real installs succeeded through the dispatcher. |
| `rust/crates/agentlinux/src/cmd/remove.rs` | dispatch uninstall.sh streaming | ✓ VERIFIED | Present + wired. |
| `rust/crates/agentlinux/src/cmd/upgrade.rs` | DivergenceReport table + reconcile + continue-on-failure | ✓ VERIFIED (parity) / ⚠️ flaky harness | upgrade logic correct; test module races cross-module (Truth 8). |
| `rust/crates/agentlinux/src/{probe,npm,rewire,catalog,sentinel,cache,guard}.rs` | adapters | ✓ VERIFIED | All present + wired; feed the pure gates. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| dispatcher.rs | recipe_env::into_env_pairs | child env build | ✓ WIRED | VERB-02 dispatch + VERB-03 typed source meet; 9 dispatcher tests + env-pair test pass. |
| install/remove/upgrade | dispatcher::dispatch_recipe | real recipe dispatch | ✓ WIRED | 23-install-user 9/9 + 50-agents real installs green — end-to-end on real recipes. |
| npm.rs | buffered dispatcher (30s timeout) | npm ls/view | ✓ WIRED | buffered_timeout_maps_to_1 test green; feeds resolve_latest_for. |
| cmd/*.rs verbs | agentlinux-core pure gates | classify/presence/reuse/remediate/derive_category/parse_pin_spec | ✓ WIRED | adapters read files, gates stay pure (core purity Truth 6). |
| main.rs | clap subcommands → verb adapters | routing | ✓ WIRED | reuse-decision subcommand preserved; all 6 verbs reachable. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| VERB-02 dispatcher floor | `cargo test -p agentlinux dispatcher` | 9 passed (0/10 flake) | ✓ PASS |
| Workspace parity corpus (deterministic) | `cargo test --workspace -- --test-threads=1` | 228 passed | ✓ PASS |
| Workspace parity corpus (default parallel) | `cargo test --workspace` | ~15% flake (env-race panics) | ✗ FLAKY |
| Per-module isolation (pin/upgrade/install/remove/adopt/sentinel) | `cargo test -p agentlinux <mod>` ×3 each | all green | ✓ PASS |
| Clippy | `cargo clippy -p agentlinux --all-targets -- -D warnings` | exit 0, no warnings | ✓ PASS |
| Fmt | `cargo fmt --all --check` | exit 0, clean | ✓ PASS |
| Bats specs unchanged | `git diff 210db3e..HEAD -- tests/bats/` | 0 lines | ✓ PASS |
| Master untouched / parallel-track | `git rev-parse master` + phase diff name-only | f14c092; only rust/** + run.sh | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| VERB-01 | 56-01/02/03 | 6 verbs contract-equivalent stdout + exit codes | ✓ SATISFIED | Verbs implemented + wired; unchanged bats green on non-env-gated cases; 228 unit corpus green single-threaded. |
| VERB-02 | 56-01/03 | dispatcher sudo-u/tee/timeout/SIGTERM→SIGKILL | ✓ SATISFIED | Real impl + 9 passing dispatcher tests (incl. escalation + timeout mapping). |
| VERB-03 | 56-01 | 6 env vars from one typed source | ✓ SATISFIED | into_env_pairs sole producer; recipes read unchanged. |
| GATE-01 | 56-04 | full CLI bats green, no regression/newly-skipped | ⚠️ SATISFIED-WITH-CAVEAT | Bats unchanged; non-env-gated green; env-gated cases enumerated + deferred. NOTE: the Rust `cargo test` parity harness is flaky under default parallelism (Truth 8) — the bats surface itself is green, but the Rust-side regression oracle is not reliably green in parallel. |
| GATE-05 | 56-04 | master shippable, reversible per-phase | ✓ SATISFIED | Master untouched; additive rust-only + flag-gated harness. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| cmd/pin.rs, cmd/upgrade.rs, sentinel.rs, +7 | 173/498/203/… | 10 per-module `static ENV_LOCK` over ONE process-global env | ⚠️ Warning | Cross-module parallel races → intermittent `None.unwrap()` + `PoisonError` panics (~15% of default-parallel workspace runs). Not a parity bug; a test-harness serialization defect. |
| (phase-56 rust files) | — | TBD/FIXME/XXX/todo!()/unimplemented!()/PLACEHOLDER | ℹ️ None found | Clean. |

### Gaps Summary

One actionable gap: the Rust bin test suite is **not reliably green under cargo's default parallel runner**. Ten test modules each hold a module-private `ENV_LOCK` mutex, but they all mutate the same process-global `AGENTLINUX_*` env vars. A per-module lock serializes only within its module, so cross-module tests race: one removes an env var another is reading → `Option::unwrap()` on `None` panic → the panicking module's `ENV_LOCK` is poisoned → sibling tests cascade into `PoisonError` panics. Reproduced ~4 times in ~26 default runs (≈15%); the failing sets are always in pin/upgrade/install and always env-race panics — never a wrong-value parity assertion.

This is a **test-infrastructure defect, not a shipped-code parity regression**: the verb logic is correct (228/228 deterministic single-threaded; green per-module-isolated; clippy + fmt clean; bats unchanged and green on all non-env-gated cases). But the SUMMARY's flat "`cargo test --workspace` → 228 passed" claim over-states reliability — the default invocation the CI Rust job uses is expected-flaky. Fix before transition (single shared process-wide test lock, OR non-global env seams, OR force `--test-threads=1` and document it) so Phase 57 doesn't inherit a red-intermittent gate.

The two deferred bats cases (ssh ×4 → Phase 59; INST-02-under-flag → Phase 57) were independently scrutinized and are genuinely environment-gated — no parity bug is hiding behind the "deferred" label.

---

*Verified: 2026-07-28*
*Verifier: Claude (gsd-verifier)*

---

## Resolution (post-verification)

The one actionable gap — the parallel-runner test flake — was **fixed and proven
resolved** before transition:

- **Fix** (`f4b87b6`): replaced the 10 module-private `ENV_LOCK` mutexes with a
  single process-wide, **poison-tolerant** `crate::test_support::ENV_LOCK` +
  `env_guard()` (acquired at all 44 sites). One shared lock serializes every
  env-mutating test across modules; poison-tolerance stops any single panic from
  cascading.
- **Proof:** the default parallel invocation `cargo test --workspace` was run
  **25× in a loop — 25/25 all-passed** (228/228 each run, zero panics). clippy
  `-D warnings` clean; `cargo fmt --all --check` clean; `tests/bats/` and
  `agentlinux-core` untouched.
- Two accepted review MEDIUMs documented (`d63cb62`): the `recipe_path` catalog
  trust boundary + the un-timed `upgrade`-sweep parity note.

**Verdict upgraded: GOAL ACHIEVED.** 8/8 must-haves — the CLI surface is
byte-compatible on the Rust build (bats unchanged + green on all non-env-gated
cases), the dispatcher floor holds, VERB-03 single-source enforced, core pure,
master untouched, and `cargo test --workspace` now reliably green. The ssh-mode
(×4 → Phase 59) and INST-02-under-flag (→ Phase 57) remainders are genuinely
environment-gated, not parity bugs.

*Resolution recorded: 2026-07-28*
