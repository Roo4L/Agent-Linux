---
phase: 56-registry-cli-verbs-subprocess-dispatcher
plan: 01
subsystem: infra
tags: [rust, clap, nix, dispatcher, sudo, cli, tsrewrite, musl, bats]

# Dependency graph
requires:
  - phase: 53-rust-spike
    provides: "the agentlinux bin crate (argv-match reuse-decision path) + agentlinux-core pure crate + the run.sh RUST-03 host-build/stage scaffold"
provides:
  - "clap CLI skeleton (cli.rs) — 6 verbs / 23 flags / 4 positionals mirroring the Commander surface, incl. the install --version shadow (CLI-03)"
  - "RecipeEnv (recipe_env.rs) — the single typed source of the 6 AGENTLINUX_* names + resolve_install_user + full_child_env canonical PATH assembly (VERB-03)"
  - "the subprocess dispatcher (dispatcher.rs) — as_user buffered+streaming, invoker==target short-circuit, thread-per-pipe tee, SIGTERM→2000ms→SIGKILL, exit-map 124/1/0/code (VERB-02)"
  - "tests/docker/run.sh — optional per-file bats arg + flag-gated Rust-CLI symlink override, fail-loud (GATE-01/GATE-05)"
affects: [56-02-list-adopt-pin, 56-03-install-remove-upgrade, 57-provisioner-port, 58-cutover]

# Tech tracking
tech-stack:
  added: [clap 4.6.4 (derive), nix 0.31.3 (signal/process/user), wait-timeout 0.2.1]
  patterns:
    - "One-typed-source env contract: the 6 AGENTLINUX_* keys live in exactly one function; a rename is a compile error"
    - "Thread-per-pipe streaming tee to avoid the two-pipe deadlock; buffered path also drains via reader threads"
    - "nix::sys::signal::kill for SIGTERM-then-SIGKILL escalation (std Child::kill is SIGKILL-only)"
    - "Pre-clap short-circuit preserves a legacy provisioner subcommand (reuse-decision) outside the clap verb surface"
    - "Test-harness-only symlink override (run.sh) re-points the CLI command at the Rust bin without touching the provisioner"

key-files:
  created:
    - rust/crates/agentlinux/src/cli.rs
    - rust/crates/agentlinux/src/recipe_env.rs
    - rust/crates/agentlinux/src/dispatcher.rs
  modified:
    - rust/crates/agentlinux/src/main.rs
    - rust/crates/agentlinux/Cargo.toml
    - tests/docker/run.sh

key-decisions:
  - "Bin crate version pinned to 0.3.6 (matches plugin/cli/package.json → CLI-01), NOT the v0.4.0 milestone label — like-for-like, nothing user-observable changes."
  - "reuse-decision kept OUT of the clap Command enum and dispatched via a pre-clap short-circuit, so the six-verb surface stays byte-stable and the Phase-53 reuse path (13-reuse.bats) is untouched."
  - "Buffered path honors a timeout too (not just streaming) — npm ls/view run buffered with timeout 30_000 (Open Q2); used wait-timeout for the buffered wait, a try_wait poll for the streaming watchdog."
  - "Verb bodies are loud EX_SOFTWARE (70) not-implemented stubs, not todo!()-panics — a premature invocation is a clean line, not a SIGABRT."
  - "recipe_env/dispatcher carry a module-scoped #![allow(dead_code)] for the Wave-0 scaffold; the verb-layer consumers (Plans 02/03) remove it when they import."

patterns-established:
  - "Pure/adapter split held: ALL new I/O (clap parse, env-file read, subprocess spawn, signals) lives in the agentlinux bin; agentlinux-core has zero non-doc std::process/std::fs/std::env at runtime."
  - "Parity-test-as-oracle: each Rust test module mirrors the exact TS test corpus (cli_parse ← index.ts rows, recipe_env ← runner.test.ts, dispatcher ← dispatcher-stream.test.ts)."

requirements-completed: [VERB-01, VERB-02, VERB-03, GATE-01, GATE-05]

coverage:
  - id: D1
    description: "clap CLI shell parses the exact Commander surface (6 verbs, 23 flags, 4 positionals) incl. the install --version 9.9.9 shadow (both flag orders) + unknown-verb Err; --version prints 0.3.6"
    requirement: "VERB-01"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/cli.rs#mod cli_parse (9 tests)"
        status: pass
      - kind: unit
        ref: "cd rust && cargo test -p agentlinux cli_parse → 9 passed"
        status: pass
    human_judgment: false
  - id: D2
    description: "RecipeEnv centralizes the 6 AGENTLINUX_* names in one function (rename = compile error); resolve_install_user precedence + POSIX-charset fallback; full_child_env byte-identical canonical PATH + extraEnv override"
    requirement: "VERB-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/recipe_env.rs#mod recipe_env_tests (8 tests)"
        status: pass
      - kind: unit
        ref: "cd rust && cargo test -p agentlinux recipe_env → 8 passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dispatcher reproduces asUser on all 6 dispatcher-stream.test.ts parity cases (tee+capture, non-zero-no-throw exit 7, buffered captures, sudo-branch unknown user, ENOENT→1, timeout→124) + SIGKILL escalation against a trap '' TERM child + buffered timeout"
    requirement: "VERB-02"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/dispatcher.rs#mod dispatcher_tests (9 tests)"
        status: pass
      - kind: unit
        ref: "cd rust && cargo test -p agentlinux dispatcher → 9 passed"
        status: pass
    human_judgment: false
  - id: D4
    description: "tests/docker/run.sh accepts an optional per-file bats arg AND (flag-gated AGENTLINUX_STAGE_RUST_CLI=1) re-points ~agent/.npm-global/bin/agentlinux at the staged Rust musl bin, failing loudly on a missing bin; provisioner untouched; master default TS path unchanged"
    requirement: "GATE-01"
    verification:
      - kind: other
        ref: "bash -n tests/docker/run.sh (syntax) + grep ln -sfn + grep refusing/false-green + git diff --name-only shows only tests/docker/run.sh"
        status: pass
      - kind: other
        ref: "shellcheck --severity=warning + shfmt -i 2 -ci -bn (pre-commit hooks) → passed"
        status: pass
    human_judgment: true
    rationale: "The end-to-end effect (CLI bats actually run against the Rust bin inside a booted systemd container) is only observable in a Docker/QEMU run, which this VM cannot run at plan-execution time (Docker OOMs the full suite; QEMU is the release gate). Static checks pass; a human/CI must confirm the in-container CLI bats go green under the Rust bin in a later run."

# Metrics
duration: 12min
completed: 2026-07-28
status: complete
---

# Phase 56 Plan 01: CLI Skeleton, Typed Recipe Env, and the Subprocess Dispatcher Summary

**A clap-parsed `agentlinux` CLI shell (6 verbs + `install --version` shadow), the single-typed-source `RecipeEnv`, and a byte-for-byte Rust port of the `asUser` subprocess dispatcher (invoker==target short-circuit, thread-per-pipe tee, SIGTERM→SIGKILL escalation, 124/1/0/code exit map) — all six `dispatcher-stream.test.ts` parity cases green — plus a flag-gated bats staging override in `run.sh`.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-28T17:14:22Z
- **Completed:** 2026-07-28T17:26:47Z
- **Tasks:** 4
- **Files modified:** 6 (3 created, 3 modified)

## Accomplishments
- **Dispatcher (the #1 risk, gated first):** `as_user` reproduces `asUser` exactly — invoker==target runs argv directly, else `sudo -u <user> -H -E -- argv` (array argv, load-bearing `--`); buffered path never throws on a non-zero child exit (Pitfall 5); streaming path tees live via one reader thread per pipe (Pitfall 2); timeouts escalate SIGTERM→2000ms→SIGKILL via `nix::sys::signal::kill` (not std `Child::kill`, SIGKILL-only, Pitfall 1); exit map `timeout=124 / signal=1 / ENOENT=1 / clean=code`. All 6 `dispatcher-stream.test.ts` parity cases + the SIGKILL-escalation case + a buffered-timeout case are green.
- **clap CLI skeleton:** the `Cli`/`Command` derive tree mirrors `index.ts:20-108` byte-for-byte on flag names + positionals; `install --version <semver>` shadows the program `-V` via `disable_version_flag`; bin version synced to `0.3.6` (package.json → CLI-01); `reuse-decision` preserved as a pre-clap short-circuit (13-reuse.bats untouched).
- **RecipeEnv:** the 6 `AGENTLINUX_*` names live in one function (rename = compile error, VERB-03); `resolve_install_user` ports the precedence + POSIX-charset re-validation; `full_child_env` assembles the byte-identical canonical PATH + locale + extraEnv override.
- **run.sh staging override:** optional per-file bats arg (Docker OOM dodge) + flag-gated Rust-bin-as-`agentlinux` symlink override with a fail-loud exit-127 guard; provisioner untouched; master's default TS path unchanged.

## Task Commits

Each task was committed atomically:

1. **Task 1: clap CLI skeleton** — `a73795e` (feat)
2. **Task 2: RecipeEnv typed source** — `a3e467f` (feat)
3. **Task 3: subprocess dispatcher** — `2d86c42` (feat)
4. **Task 4: run.sh staging override** — `1ead909` (test)

_Tasks 1 & 2 were authored TDD-style (test corpus + implementation together); each shipped as one atomic feat commit rather than a split RED/GREEN pair._

## Files Created/Modified
- `rust/crates/agentlinux/src/cli.rs` (created) — clap `Cli` root + `Command` enum (6 verbs) + per-verb arg structs + the `install --version` shadow + `cli_parse` corpus.
- `rust/crates/agentlinux/src/recipe_env.rs` (created) — `RecipeEnv` + `into_env_pairs` (the 6 keys) + `resolve_install_user` + `full_child_env` + `recipe_env_tests`.
- `rust/crates/agentlinux/src/dispatcher.rs` (created) — `DispatchResult` + `as_user` (buffered+streaming) + `dispatch_recipe`/`dispatch_recipe_with_env` + `dispatcher_tests` (9 parity/escalation cases).
- `rust/crates/agentlinux/src/main.rs` (modified) — `mod` registration; pre-clap `reuse-decision` short-circuit; `Cli::try_parse` → EX_USAGE(64)/version-help exit 0; verb dispatch stubs.
- `rust/crates/agentlinux/Cargo.toml` (modified) — version 0.3.6; clap/nix/wait-timeout deps.
- `tests/docker/run.sh` (modified) — optional `[bats-file]` arg; `AGENTLINUX_STAGE_RUST_CLI` symlink override; fail-loud guard.

## Decisions Made
- **Bin version = 0.3.6, not 0.4.0.** The `--version` string is user-observable (CLI-01 derives it from package.json); the v0.4.0 milestone label is internal. Plan-check B1 pre-applied; confirmed with the version-sync grep.
- **`reuse-decision` outside clap.** Kept as a pre-`Cli::parse()` short-circuit so the six-verb surface stays byte-stable and the Phase-53 provisioner path is immune to any clap help/version interception.
- **Buffered timeout honored (Open Q2).** npm probes run buffered with `timeout 30_000`; the Rust buffered path uses `wait-timeout` and escalates to 124 identically to streaming.
- **`nix` features `signal + process + user`.** `signal` for `kill`, `user` for `User::from_uid` (invoker resolution), `process` for `Pid`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] shfmt-normalized one pre-existing alignment block in run.sh**
- **Found during:** Task 4 (run.sh staging override)
- **Issue:** The repo's pre-commit shfmt hook (`-i 2 -ci -bn`) would reformat a pre-existing `SECRET_ALLOWLIST` comment-alignment block (unrelated to my edit) and FAIL the commit on `tests/docker/run.sh`.
- **Fix:** Ran `shfmt -i 2 -ci -bn -w tests/docker/run.sh` so the whole file (my additions + the one pre-existing block) is hook-clean. My added lines already used the 2-space house style; only the pre-existing comment-alignment whitespace changed.
- **Files modified:** tests/docker/run.sh
- **Verification:** `shfmt -i 2 -ci -bn -d` clean; the pre-commit shfmt + shellcheck hooks passed on the Task 4 commit.
- **Committed in:** `1ead909` (Task 4 commit)

**2. [Rule 3 - Blocking] Renamed test modules to dodge clippy::module_inception**
- **Found during:** Tasks 2 & 3
- **Issue:** A `#[cfg(test)] mod recipe_env` inside `recipe_env.rs` (and `mod dispatcher` inside `dispatcher.rs`) trips `clippy::module_inception`, which `-D warnings` turns into a build error.
- **Fix:** Renamed the test modules to `recipe_env_tests` / `dispatcher_tests`. The plan's verify filters (`cargo test ... recipe_env` / `... dispatcher`) still match the test paths.
- **Files modified:** rust/crates/agentlinux/src/recipe_env.rs, dispatcher.rs
- **Verification:** `cargo clippy -p agentlinux --all-targets -- -D warnings` → No issues found.
- **Committed in:** `a3e467f`, `2d86c42`

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking tooling issues)
**Impact on plan:** Both are lint/format hygiene required to keep the tree committable + clippy-clean; no scope creep, no behavior change. The pre-existing shfmt block change is whitespace-only and out of my functional scope but was unavoidable to pass the hook.

## Issues Encountered
- **rtk hook mangled a `grep` regex** during an acceptance-check (the `^\s*//` pattern was rewritten). Worked around by running greps via `rtk proxy bash -c '...'`. No impact on deliverables.
- **A pre-existing `git stash` entry** was observed on a sibling branch — left strictly untouched (worktree stash-list is shared across worktrees; touching it is prohibited).

## Known Stubs
The six verb bodies in `main.rs` (`dispatch()`) are intentional Wave-0 stubs — they print an `EX_SOFTWARE (70)` "not implemented yet (Wave 1/2)" line to stderr and exit non-zero. This is by plan design: Wave 0 is scaffold + dispatcher only; the verb adapters land in Plans 56-02 (`list`/`adopt`/`pin`) and 56-03 (`install`/`remove`/`upgrade`). The stubs are loud (non-zero, no silent success), so a premature invocation cannot false-green. `dispatch_recipe`/`dispatch_recipe_with_env` and the `RecipeEnv` API are complete but not yet wired to a non-test caller (the `#![allow(dead_code)]` is removed when Plans 02/03 import them).

## Threat Flags
None. No new network endpoint, auth path, file-access pattern, or schema change beyond the plan's `<threat_model>` register (T-56-01..05, T-56-SC). The dispatcher's `sudo -u` elevation, the env-file read, and the recipe child env are all covered dispositions and were implemented as specified (array argv + `--` terminator; POSIX-charset user re-validation; explicit canonical PATH; run.sh fail-loud guard).

## Verification (phase-close gates for this plan)
- `cargo test -p agentlinux cli_parse` → **9 passed** (VERB-01).
- `cargo test -p agentlinux recipe_env` → **8 passed** (VERB-03).
- `cargo test -p agentlinux dispatcher` → **9 passed** (VERB-02, the 6 parity cases + escalation + buffered timeout + recipe run).
- `cargo test --workspace` → **147 passed**.
- `cargo clippy -p agentlinux --all-targets -- -D warnings` → **No issues found**.
- `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux` → **static-PIE bin built**; `--version` → `agentlinux 0.3.6`; `reuse-decision gsd` → `create` (exit 0).
- `grep -rn 'std::process' rust/crates/agentlinux-core/src/` → only doc-comment mentions; zero non-doc process I/O in the pure core.
- `bash -n tests/docker/run.sh` valid; symlink-override + per-file + fail-loud present; provisioner untouched (GATE-01/GATE-05).

## Review
Ran the project `$review` loop rubrics. The dispatch table has no Rust `.rs` pattern (the TS→Rust rewrite postdates it), so no Rust-surface subagent role exists; the host also exposes no subagent facility to this executor, so — per the skill's fallback clause — the main agent ran the applicable role rubrics itself (**limited pass**): security-engineer + reliability-reviewer + simplicity-reviewer against the dispatcher/recipe_env, and bash-engineer + qa-engineer against run.sh. Findings: none actionable. Security: sudo argv is an array with the `--` terminator, user re-validated upstream, `env_clear` + explicit PATH — faithful to T-56-01/02/04. Reliability: both paths timeout-bounded, reader threads joined, ENOENT classified distinctly, no hang path. run.sh: `set -euo pipefail`, targeted symlink ops, fail-loud guard, no `sudo npm install -g`, no `/usr/local` shim; shellcheck + shfmt clean.

## Next Phase Readiness
- **Plan 56-02 (list/adopt/pin) & 56-03 (install/remove/upgrade)** are unblocked: they read the `cli.rs` `Command` structs, call `dispatcher::dispatch_recipe` (building env via `recipe_env::full_child_env`), and remove the `#![allow(dead_code)]` as they import.
- Every later plan's bats verification uses the `run.sh` `AGENTLINUX_STAGE_RUST_CLI` override to exercise the Rust bin as the `agentlinux` command.
- **Deferred to phase close / CI:** the in-container CLI bats (`40-registry-cli` etc.) running green against the Rust bin under a booted systemd container — not runnable in this VM (Docker OOM / QEMU release gate). Static-musl link is proven; the end-to-end bats-on-Rust run is the phase-close/CI gate (D4, human_judgment).

## Self-Check: PASSED

- Created files present: `cli.rs`, `recipe_env.rs`, `dispatcher.rs` — all FOUND.
- Commits present: `a73795e`, `a3e467f`, `2d86c42`, `1ead909` — all FOUND.

---
*Phase: 56-registry-cli-verbs-subprocess-dispatcher*
*Completed: 2026-07-28*
