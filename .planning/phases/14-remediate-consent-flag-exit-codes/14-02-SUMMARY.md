---
phase: 14-remediate-consent-flag-exit-codes
plan: 02
subsystem: infra
tags: [bash, remediate, npm-prefix, chown, rebase, sudoers, path-wiring, provisioner, refactor, t-14-02, t-14-03, t-14-07, t-14-08]

# Dependency graph
requires:
  - phase: 14-remediate-consent-flag-exit-codes
    plan: 01
    provides: DECIDE-THEN-ACT main() flow + RESOLUTIONS map + BAILED_COMPONENTS + remediate::gate_or_bail + per-component handler stubs ([REMEDIATE-NN] markers) + 30-nodejs.sh / 20-sudoers.sh / 40-path-wiring.sh case-dispatch wiring
provides:
  - remediate::nodejs::chown_or_rebase (REMEDIATE-01 — top-level entry)
  - remediate::nodejs::_strategy_for / _is_trivially_salvageable / _enumerate_modules / _apply_chown / _apply_rebase (REMEDIATE-01 helpers)
  - remediate::sudoers::install_or_overwrite (REMEDIATE-03 — single helper for BOTH additive create AND state-overwriting drift overwrite)
  - remediate::user::log_path_wiring_remediated (REMEDIATE-02 — [REMEDIATE-02] transcript marker)
  - 5 new brownfield fixtures in tests/bats/helpers/brownfield.bash for REMEDIATE-01 (chown / rebase / rebase_with_module / rebase_with_catalog_module / chown_blocked) + 3 new for REMEDIATE-02/03 (path_wiring / sudoers_missing / sudoers_drift)
  - teardown_file in 14-remediate.bats restoring canonical post-installer state for downstream bats files
  - REMEDIATE-01 + REMEDIATE-02 + REMEDIATE-03 flipped to Complete in REQUIREMENTS.md
affects: [14-03-remediate-04-cli-reinstall, 15-tty-interactive-prompts, 16-release]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Strategy selector + per-strategy handler stack: a single chown_or_rebase entry point reads detect:: exports, calls a pure-function _strategy_for to pick chown vs rebase, then dispatches to _apply_chown or _apply_rebase. Unit-testable (the predicate functions and selector accept all inputs as args) AND e2e-testable (chown_or_rebase reads globals)."
    - "Allowlist via find -maxdepth-1 -mindepth-1 -not -path / -not -name: the 'trivially salvageable' check uses negative-match flags to enumerate non-allowlist top-level entries; a follow-up scan of lib/node_modules catches the T-14-03 user-installed-module case. -print -quit short-circuits on first hit."
    - "NPM_CONFIG_PREFIX in `as_user env` to target enumeration: `as_user root env NPM_CONFIG_PREFIX=$old_prefix npm ls -g --json --depth=0` enumerates modules under a SPECIFIC prefix (not the caller's npm default). Required for the rebase migration path where the OLD prefix is not on the caller's npm default."
    - "Single factored helper for additive+state-overwriting arms: install_or_overwrite is called by BOTH 20-sudoers.sh's create arm AND its remediate arm (action label distinguishes them in the [REMEDIATE-03] marker). The visudo+install machinery cannot drift between arms because there is only one implementation."
    - "Test-only env-var hatch for hard-to-fixture failure paths: AGENTLINUX_TEST_MODE=1 + AGENTLINUX_TEST_SUDOERS_OVERRIDE=<body> replaces the canonical sudoers content with an arbitrary body so the bats T-14-02 mitigation test can deliberately inject invalid syntax to force the visudo -cf gate to fail. Production builds leave both env vars unset and the branch is dead code."
    - "Fixture-isolation invariant carries from Plan 14-01: each new setup_brownfield_for_remediate_* fixture mutates EXACTLY ONE component on top of _brownfield_baseline (which lays down a REUSE-compatible host). The baseline's npm-prefix seed (~agent/.npm-global + ~agent/.npmrc) was added in Plan 14-02 because the post-purge default npm-prefix is /usr (root-owned) which trips a npm-prefix bail — fixtures targeting REMEDIATE-02/03 would otherwise cascade-fail."
    - "teardown_file restoring canonical post-installer state: 14-remediate.bats now runs `bash $INSTALLER --purge && bash $INSTALLER` in teardown_file so downstream bats files (40-registry-cli.bats etc.) see the same host shape tests/docker/run.sh staged before bats fires. Mirrors the recovery contract that 50-agents.bats's setup_file already encodes."

key-files:
  created:
    - .planning/phases/14-remediate-consent-flag-exit-codes/14-02-SUMMARY.md
  modified:
    - plugin/lib/remediate/nodejs.sh (Task 1: chown_or_rebase + 5 helpers replacing the stub)
    - plugin/lib/remediate/sudoers.sh (Task 2: install_or_overwrite + legacy *_stub shims)
    - plugin/lib/remediate/user.sh (Task 2: log_path_wiring_remediated + legacy stub shim)
    - plugin/provisioner/30-nodejs.sh (Task 1: remediate arm calls chown_or_rebase)
    - plugin/provisioner/20-sudoers.sh (Task 2: refactored — both create+remediate arms call install_or_overwrite; inline visudo+install machinery removed)
    - plugin/provisioner/40-path-wiring.sh (Task 2: emits [REMEDIATE-02] marker when REUSED_USER=true)
    - tests/bats/14-remediate.bats (Task 1+2: +23 @tests total, teardown_file added, Plan 14-01 Test 7 updated per plan-mandated follow-through)
    - tests/bats/helpers/brownfield.bash (Task 1+2: +8 new fixtures + _brownfield_baseline helper)
    - .planning/REQUIREMENTS.md (REMEDIATE-01/02/03 flipped to [x] + Complete in traceability table)

key-decisions:
  - "REMEDIATE-01 strategy selector: chown only when prefix is UNDER install user's home AND trivially salvageable (per CONTEXT.md Area 2 Q1+Q2). The allowlist is airtight via find-maxdepth-1 negative matching plus a follow-up scan of lib/node_modules — Test 26 + Test 29 + Test 37 prove a single user-installed module flips the strategy to rebase (T-14-03 mitigation)."
  - "REMEDIATE-01 module migration enumerates the OLD prefix via NPM_CONFIG_PREFIX, not the caller's npm default (Rule 1 — bug found during initial Docker run when Test 33 failed because as_user root npm ls -g listed root's default prefix instead of the targeted /usr/local/agentlinux-old)."
  - "REMEDIATE-01 filtering set per Area 2 Q3: npm, @anthropic-ai/claude-code, get-shit-done-cc, @playwright/cli. claude-code uses the native installer (not npm) but @anthropic-ai/claude-code is included defensively in case a brownfield host installed claude via npm. Verified by Test 30 + Test 34."
  - "REMEDIATE-03 install_or_overwrite factoring: BOTH 20-sudoers.sh's create AND remediate arms call the SAME helper (Test 46 grep asserts ≥2 references in the provisioner + zero inline visudo -cf). This eliminates the divergence-between-arms class of bug (T-14-02 mitigation — the drift overwrite uses the SAME visudo gate as the additive create)."
  - "REMEDIATE-03 visudo-fail test (T-14-02) uses a test-only env-var hatch (AGENTLINUX_TEST_MODE + AGENTLINUX_TEST_SUDOERS_OVERRIDE) to deliberately inject invalid sudoers syntax. The hatch is gated by a clearly-named env var that production builds never set; the branch is dead code outside the test (verified by name — the env vars do not appear anywhere else in the codebase)."
  - "REMEDIATE-02 is deliberately mostly-no-op in code: the actual additive wiring happens in 40-path-wiring.sh's ensure_marker_block + write_file_atomic calls. log_path_wiring_remediated is just a [REMEDIATE-02] transcript marker that fires when REUSED_USER=true so the operator can distinguish 're-attaching to a pre-existing user' from 'creating from scratch'. The contract is intentionally thin — Plan 14-01 already established that 40-path-wiring.sh runs unconditionally."
  - "Plan 14-01 Test 7 (per-component stubs source + emit markers) updated per Rule 3 plan-mandated follow-through: the spot-check moved from remediate::sudoers::overwrite_stub (now a thin shim that mutates state — wrong for a unit test) to remediate::user::log_path_wiring_remediated (still additive — just emits a log line). The 4-token enumeration of *_stub symbols + new Plan 14-02 handler symbols (chown_or_rebase, install_or_overwrite, log_path_wiring_remediated) are all asserted defined."
  - "teardown_file in 14-remediate.bats restores canonical post-installer state via --purge + bash $INSTALLER (no --yes). This is necessary because the brownfield @tests leave fixture residue (e.g. /usr/local/agentlinux-old/ from the rebase tests). Without the teardown the downstream 40-registry-cli.bats setup_file — which has NO recovery — finds /opt/agentlinux missing and cascade-fails (caught in initial Docker run, Rule 3 deviation)."
  - "_brownfield_baseline seeds ~agent/.npm-global + ~agent/.npmrc so the npm-prefix component is REUSE-compatible. Without this seed the post-purge default npm-prefix is /usr (root-owned) → reuse::npm_prefix_decision returns remediate → fixtures targeting REMEDIATE-02/03 cascade-bail. Caught in initial Docker run; the seed makes the fixture-isolation invariant hold (each fixture mutates EXACTLY ONE component)."

patterns-established:
  - "Strategy selector + per-strategy handler stack for REMEDIATE-class actions: chown_or_rebase ⇒ _strategy_for ⇒ _apply_chown | _apply_rebase. Future REMEDIATE plans (REMEDIATE-04 in 14-03; potential v0.4+ classes) can follow the same shape."
  - "Single factored helper for additive+state-overwriting arms: install_or_overwrite serves BOTH arms. The action_label distinguishes them in the transcript marker; the underlying machinery is identical so the additive vs state-overwriting taxonomy lives at the dispatch layer (collect_all_decisions / gate_or_bail) not the helper layer."
  - "Test-only env-var hatch for hard-to-fixture failure paths: AGENTLINUX_TEST_MODE=1 + AGENTLINUX_TEST_*_OVERRIDE replaces the canonical content with arbitrary text. Production builds never set the gate var so the branch is dead code. Used for the T-14-02 visudo-fail test where a natural fixture would have to corrupt /etc/sudoers.d/ semi-permanently."
  - "_brownfield_baseline helper that lays a REUSE-compatible host EVERY component: --purge + agent user + canonical sudoers + Node 22 + ~agent/.npm-global + ~agent/.npmrc. Each fixture mutates EXACTLY ONE component on top of it — the fixture-isolation invariant from Plan 14-01 carries forward unchanged."
  - "teardown_file restoring canonical state for downstream bats files: when a bats file does destructive --purge fixtures, its teardown_file runs --purge + clean re-install so the next bats file sees the same shape tests/docker/run.sh staged."

requirements-completed: [REMEDIATE-01, REMEDIATE-02, REMEDIATE-03]

# Metrics
duration: ~1h 30m
completed: 2026-05-10
---

# Phase 14 Plan 14-02: REMEDIATE-01 + REMEDIATE-02 + REMEDIATE-03 Summary

**REMEDIATE handler bodies — npm-prefix chown/rebase + module migration (REMEDIATE-01), [REMEDIATE-02] PATH-wiring transcript marker, sudoers install_or_overwrite helper that BOTH arms of 20-sudoers.sh call (REMEDIATE-03 + refactor). 177/177 bats green on Ubuntu 22.04 + 24.04 Docker.**

## Performance

- **Duration:** ~1h 30m (Task 1 ~50 min, Task 2 ~40 min)
- **Started:** 2026-05-10
- **Completed:** 2026-05-10
- **Tasks:** 2 (both atomic commits, both tdd="true")
- **Files modified:** 9 (8 modified + 1 SUMMARY created)
- **Test growth:** 154 → 177 bats @tests (+23 net; 14 Task 1 + 9 Task 2; both Ubuntu 22.04 + 24.04)

## Accomplishments

- **REMEDIATE-01 npm-prefix chown/rebase landed** — the strategy selector picks `chown` when prefix is UNDER install user's home AND trivially salvageable (per CONTEXT.md Area 2 Q1 + Q2 allowlist: lib/, bin/, share/, etc/, package.json, package-lock.json), else `rebase` to ~user/.npm-global with best-effort module migration via `npm ls -g --json --depth=0`. Old prefix is NEVER deleted (CONTEXT Q4 — user cleanup). T-14-03 / T-14-07 / T-14-08 mitigations verified via 14 @tests.
- **REMEDIATE-02 PATH wiring [REMEDIATE-02] marker** — the additive wiring already happens unconditionally via 40-path-wiring.sh's ensure_marker_block + write_file_atomic primitives; Plan 14-02 adds the `[REMEDIATE-02] component=user action=path-wiring-additive` transcript marker that fires when the user was REUSED so the operator can distinguish re-attaching from creating. Test 44 + Test 45 verify the wiring re-attaches AND preserves pre-existing user content outside the marker block AND is byte-stable across re-runs.
- **REMEDIATE-03 install_or_overwrite helper + 20-sudoers.sh refactor** — the single helper that BOTH 20-sudoers.sh's create arm AND remediate arm call. The visudo+install machinery (tmpfile → visudo -cf pre-install gate → install -m 0440 root:root atomic rename → visudo -cf post-install verify) is now in plugin/lib/remediate/sudoers.sh. T-14-02 mitigation: drift overwrite uses the SAME visudo gate as additive create (Test 41 + Test 46 verify).
- **Brownfield fixture matrix expanded** — 8 new fixtures total: 5 REMEDIATE-01 (chown / rebase / rebase_with_module / rebase_with_catalog_module / chown_blocked) + 3 REMEDIATE-02/03 (path_wiring / sudoers_missing / sudoers_drift). The new `_brownfield_baseline` helper lays a REUSE-compatible host across EVERY component; each fixture mutates EXACTLY ONE component (fixture-isolation invariant from Plan 14-01).
- **teardown_file invariant** — 14-remediate.bats restores canonical post-installer state (--purge + clean re-install) so downstream 40-registry-cli.bats / 50-agents.bats / 51-*.bats files see the same shape tests/docker/run.sh staged. Required by the Docker fast-path harness which has no per-bats-file recovery for /opt/agentlinux.

## Task Commits

Each task was committed atomically:

1. **Task 1: REMEDIATE-01 npm prefix chown/rebase + module migration** — `e283924` (feat, 14 new @tests, ~50 min)
2. **Task 2: REMEDIATE-02 + REMEDIATE-03 helpers + sudoers refactor** — `75eb997` (feat, 9 new @tests, REQUIREMENTS.md flips, ~40 min)

**Plan metadata commit:** [pending — landed after this SUMMARY.md] (docs: complete plan)

## Files Created/Modified

### Created

- `.planning/phases/14-remediate-consent-flag-exit-codes/14-02-SUMMARY.md`

### Modified

- `plugin/lib/remediate/nodejs.sh` — chown_or_rebase + 5 helpers (_is_trivially_salvageable, _strategy_for, _enumerate_modules, _apply_chown, _apply_rebase). Legacy npm_prefix_stub kept as a thin shim. (Task 1)
- `plugin/lib/remediate/sudoers.sh` — install_or_overwrite helper. Legacy install_stub + overwrite_stub kept as thin shims. Test-only AGENTLINUX_TEST_MODE + AGENTLINUX_TEST_SUDOERS_OVERRIDE hatch supports Test 41. (Task 2)
- `plugin/lib/remediate/user.sh` — log_path_wiring_remediated [REMEDIATE-02] marker emitter. Legacy path_wiring_stub kept as a thin shim. (Task 2)
- `plugin/provisioner/30-nodejs.sh` — RESOLUTIONS[npm-prefix]=remediate arm calls chown_or_rebase || return 1 (replacing the Plan 14-01 stub call). (Task 1)
- `plugin/provisioner/20-sudoers.sh` — refactored: both create + remediate arms call install_or_overwrite with action labels; inline visudo + install machinery REMOVED (now in the helper). (Task 2)
- `plugin/provisioner/40-path-wiring.sh` — emits [REMEDIATE-02] marker when REUSED_USER=true (one-line addition after the startup log_info). (Task 2)
- `tests/bats/14-remediate.bats` — +23 @tests (Tests 25-47); teardown_file added; Plan 14-01 Test 7 updated per Rule 3 plan-mandated follow-through. (Task 1+2)
- `tests/bats/helpers/brownfield.bash` — 8 new brownfield fixtures + `_brownfield_baseline` helper that lays a REUSE-compatible host across every component (the npm-prefix seed was added during Task 2 to prevent cascade bails in REMEDIATE-02/03 fixtures). (Task 1+2)
- `.planning/REQUIREMENTS.md` — REMEDIATE-01 + REMEDIATE-02 + REMEDIATE-03 flipped from `[ ]` to `[x]`; traceability table rows flipped from Pending to Complete. (Task 2)

## Decisions Made

1. **REMEDIATE-01 strategy selector airtight allowlist (T-14-03)** — `_is_trivially_salvageable` uses `find -maxdepth 1 -mindepth 1 -not -path ... -not -name ... -print -quit` followed by a `find $prefix/lib/node_modules -maxdepth 1 -mindepth 1 -print -quit` scan. The two-step check catches BOTH stray top-level entries (e.g. `agent.json`) AND the canonical T-14-03 case (a `lib/node_modules/<user-pkg>/` from a prior `sudo npm install -g`). Test 26 + Test 29 + Test 37 prove the predicate flips to `rebase` in every non-allowlist case.

2. **REMEDIATE-01 module migration NPM_CONFIG_PREFIX targeting (Rule 1 — bug-of-naive-implementation)** — the initial Docker run revealed that `as_user root npm ls -g --json --depth=0` lists modules from root's DEFAULT npm prefix (typically `/usr/lib/node_modules`), NOT the OLD prefix at `/usr/local/agentlinux-old`. Test 33 caught this immediately. Fix: `as_user "$owner" env "NPM_CONFIG_PREFIX=$old_prefix" npm ls -g --json --depth=0` carries the OLD prefix into the npm invocation via env-var precedence (Pitfall 7 from CONTEXT). The optional `[old_prefix]` second arg is documented as the right way to call _enumerate_modules.

3. **REMEDIATE-01 filtering set hardcoded** — the EXCLUDED list (`npm`, `@anthropic-ai/claude-code`, `get-shit-done-cc`, `@playwright/cli`) is built inline in `_enumerate_modules` and converted to a jq-data argument via `printf | jq -R . | jq -s .` (no string interpolation, no injection surface — T-14-07 mitigation). claude-code uses the native installer (not npm), but `@anthropic-ai/claude-code` is included defensively for brownfield hosts that installed claude via npm before discovering the native installer.

4. **REMEDIATE-03 install_or_overwrite factoring (T-14-02 mitigation)** — BOTH 20-sudoers.sh's create AND remediate arms call the SAME helper (Test 46 grep asserts ≥2 references in the provisioner + zero inline `visudo -cf`). The helper carries exactly 2 `visudo -cf` calls (pre-install + post-install). This eliminates the entire "drift overwrite uses a different validation than create" bug class; the additive vs state-overwriting taxonomy lives at the dispatch layer (collect_all_decisions / gate_or_bail) not the helper layer.

5. **REMEDIATE-03 visudo-fail test uses a clearly-named env-var hatch** — AGENTLINUX_TEST_MODE=1 + AGENTLINUX_TEST_SUDOERS_OVERRIDE=<body> replaces the canonical sudoers content with the override. Both env vars must be set; production builds never set either, the branch is dead code. The alternative was a fixture-level corruption of /etc/sudoers.d/ which would risk semi-permanently breaking the test container's sudo configuration.

6. **REMEDIATE-02 deliberately mostly-no-op** — the actual additive wiring happens in 40-path-wiring.sh's `ensure_marker_block` + `write_file_atomic` primitives that already run unconditionally (Plan 14-01 documented this as DELIBERATE). Plan 14-02's contribution is ONLY the `[REMEDIATE-02] component=user action=path-wiring-additive` transcript marker that fires when REUSED_USER=true — gives the operator a clear "re-attaching wiring to a pre-existing user" signal in the install log. Test 44 + Test 45 verify the wiring + idempotency contracts.

7. **Plan 14-01 Test 7 marker spot-check moved (Rule 3 — plan-mandated follow-through)** — the original spot-check called `remediate::sudoers::overwrite_stub` and grep'd for "action=stub" in the output. Plan 14-02 replaces the stub body with a thin shim delegating to install_or_overwrite which IS mutating (writes /etc/sudoers.d/agentlinux). Calling it from a unit test would (a) try to mutate state in a bats sandbox that may not have visudo, (b) emit "action=overwrite" not "action=stub". Fix: spot-check moved to `remediate::user::log_path_wiring_remediated` (still additive — just a log line) and the symbol-presence assertions extended to cover both legacy `*_stub` symbols AND new Plan 14-02 handler symbols.

8. **teardown_file invariant (Rule 3 — Docker harness recovery contract)** — initial Docker run revealed cascade failures in 40-registry-cli.bats and 50-agents.bats because my brownfield @tests left the host in a remediated-but-quirky state (e.g. /usr/local/agentlinux-old/ residue). Fix: 14-remediate.bats `teardown_file` runs `bash $INSTALLER --purge && rm -rf /usr/local/agentlinux-old && bash $INSTALLER` so downstream files see the canonical post-installer shape. This matches the recovery contract that 50-agents.bats's setup_file already encodes (re-runs `bash $INSTALLER` when /home/agent/.npm-global/bin/agentlinux symlink is absent).

9. **_brownfield_baseline npm-prefix seed (Rule 3 — fixture-isolation invariant)** — initial Task 2 Docker run revealed that REMEDIATE-02/03 fixtures cascade-bailed on npm-prefix because the post-purge default npm-prefix is `/usr` (root-owned). Fix: `_brownfield_baseline` now seeds `/home/agent/.npm-global` + `~agent/.npmrc` pointing at it, so reuse::npm_prefix_decision returns `reuse` (no remediate). Each fixture still mutates EXACTLY ONE component on top of the baseline.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] _enumerate_modules used caller's npm default prefix instead of targeting OLD prefix**
- **Found during:** Task 1 first Docker run — Test 33 (rebase migrates pre-existing modules)
- **Issue:** `as_user "$owner" npm ls -g --json --depth=0` against root listed root's DEFAULT npm prefix (typically /usr/lib/node_modules), NOT the OLD prefix at /usr/local/agentlinux-old. lodash was never enumerated.
- **Fix:** Added optional `[old_prefix]` second arg + `env NPM_CONFIG_PREFIX=$old_prefix` wrapping in the `as_user` call.
- **Files modified:** plugin/lib/remediate/nodejs.sh (_enumerate_modules + _apply_rebase call site).
- **Verification:** Test 33 PASS post-fix on both Ubuntu 22.04 + 24.04.
- **Committed in:** e283924 (Task 1 commit)

**2. [Rule 3 - Blocking] teardown_file required for downstream bats files**
- **Found during:** Task 1 first Docker run — 50-agents.bats AGT-01/02/03/04/05 failures (8 failures)
- **Issue:** REMEDIATE-01 brownfield @tests left the host in a remediated-but-quirky state. 40-registry-cli.bats had no setup_file recovery → cascade failures.
- **Fix:** Added `teardown_file()` in 14-remediate.bats running `bash $INSTALLER --purge && rm -rf /usr/local/agentlinux-old && bash $INSTALLER`. Mirrors the recovery contract 50-agents.bats's setup_file already encodes.
- **Files modified:** tests/bats/14-remediate.bats
- **Verification:** 50-agents.bats + 51-*.bats PASS post-fix.
- **Committed in:** e283924 (Task 1 commit)

**3. [Rule 1 - Bug] _brownfield_baseline missing npm-prefix REUSE prep**
- **Found during:** Task 2 first Docker run — Tests 39, 42, 44, 45 (REMEDIATE-02/03 fixtures bailed on npm-prefix)
- **Issue:** Post-purge default npm-prefix is /usr (root-owned). reuse::npm_prefix_decision returned `remediate` → cascade bail in fixtures targeting REMEDIATE-02/03.
- **Fix:** `_brownfield_baseline` now seeds /home/agent/.npm-global + ~agent/.npmrc pointing at it, so reuse::npm_prefix_decision returns `reuse` and only the target component triggers remediation.
- **Files modified:** tests/bats/helpers/brownfield.bash
- **Verification:** Tests 39, 42, 44, 45 PASS post-fix.
- **Committed in:** 75eb997 (Task 2 commit)

**4. [Rule 3 - Blocking] Plan 14-01 Test 7 marker spot-check rewritten per plan-mandated follow-through**
- **Found during:** Task 2 first Docker run — Test 48 (per-component stubs source + emit markers)
- **Issue:** Plan 14-02's overwrite_stub now delegates to install_or_overwrite which writes to /etc/sudoers.d/agentlinux. Test 7's `run remediate::sudoers::overwrite_stub` actually called install_or_overwrite which (a) emitted "action=overwrite" not "action=stub", (b) is mutating from a unit-test context.
- **Fix:** Spot-check moved from `remediate::sudoers::overwrite_stub` (now mutating) to `remediate::user::log_path_wiring_remediated` (still additive — just a log_info call). Symbol-presence assertions extended to cover both legacy `*_stub` symbols AND new Plan 14-02 handler symbols.
- **Files modified:** tests/bats/14-remediate.bats (Plan 14-01 Test 7 — preserved test name + req-id, updated assertions).
- **Verification:** Test 48 (renumbered Test 7 in post-Task-2 indexing) PASS.
- **Committed in:** 75eb997 (Task 2 commit)
- **Note:** This is plan-mandated follow-through; the Plan 14-02 plan explicitly stated "Plan 14-02 lands the real handler bodies" + Plan 14-01 noted "Plan 14-02 replaces with real body".

**5. [Rule 1 - Lint] SC2034 on unused pre_alias variable in Test 44**
- **Found during:** Task 2 pre-commit hook
- **Issue:** `local pre_alias=$(grep ...)` was unused in the test body (the assertion was a fresh grep, not a comparison with pre_alias).
- **Fix:** Removed pre_alias declaration; the comment block now explains the design (assertions grep the post-run .bashrc directly).
- **Files modified:** tests/bats/14-remediate.bats
- **Verification:** pre-commit ShellCheck PASS.
- **Committed in:** 75eb997 (Task 2 commit)

---

**Total deviations:** 5 auto-fixed (3 Rule 1 bugs, 2 Rule 3 blocking — both plan-mandated follow-throughs).
**Impact on plan:** All 5 fixes were necessary for correctness or compliance with the plan's stated update contract. No scope creep — fixes 1+3 were implementation bugs caught by the bats suite, fix 2 was a Docker harness recovery contract, fix 4 was the plan-mandated stub→handler migration, fix 5 was a lint cleanup.

## Issues Encountered

- **Initial _enumerate_modules naivety** (Deviation 1) — Treating `as_user root npm ls -g` as enumerating "modules at the OLD prefix" was wrong; it enumerates modules at root's npm-default prefix. The OLD prefix needs to be carried in explicitly via NPM_CONFIG_PREFIX. Found at the first Test 33 run — the bats fixture exposed the bug immediately.
- **Initial _brownfield_baseline missing npm-prefix REUSE prep** (Deviation 3) — Subtle interaction between --purge (which kills /home/agent → no .npmrc) and Phase 14's npm-prefix layer (which now bails on a wrong-owner prefix). The fix is one-time fixture surgery; no protocol change.
- **Docker harness assumption violated** (Deviation 2) — 40-registry-cli.bats has no setup_file recovery, only the docker harness's pre-bats install run. Brownfield-running tests in 14-remediate.bats violated that assumption. The teardown_file fix restores the contract.

## Authentication Gates

None encountered. The installer runs as root; bats fixtures execute inside the Docker container as root. No external service credentials required.

## User Setup Required

None — no external service configuration required.

## TDD Gate Compliance

Plan 14-02 was declared `type: execute` at the plan level, but BOTH tasks carried `tdd="true"`. RED/GREEN gates were enforced per-task as a single commit each (the plan's `<verify>` block requires tests to pass, not strict RED-then-GREEN commit separation per the same precedent as Plan 14-01 — see 14-01-SUMMARY.md "TDD Gate Compliance"):

- Task 1 (commit e283924): 14 @tests for REMEDIATE-01 + chown_or_rebase implementation + 30-nodejs.sh call-site update + 5 fixtures + teardown_file. RED+GREEN bundled per the plan's per-task tdd="true" semantics. Tests asserted both unit-level (predicates) and end-to-end (full installer brownfield runs).
- Task 2 (commit 75eb997): 9 @tests for REMEDIATE-02/03 + install_or_overwrite helper + 20-sudoers.sh refactor + 40-path-wiring.sh marker + 3 fixtures + Plan 14-01 Test 7 update + REQUIREMENTS.md flips. RED+GREEN bundled. Tests cover unit-level (helper definitions + visudo-fail injection) + integration (full installer paths) + grep-shape (refactor invariant + helper-call-count assertions).

## Plan 14-02 → Plan 14-03 Handoff

Plan 14-03 must:
- Replace `remediate::agents::reinstall_stub` (Plan 14-01 stub) with the broken-agent reinstall body (REMEDIATE-04).
- Wire the TypeScript CLI (plugin/cli/src/commands/install.ts) to the per-agent reinstall flow. The per-agent `agents.<id>` keys in the RESOLUTIONS map are populated by `remediate::collect_all_decisions` (one entry per REUSE_AGENT_CANONICAL_PATHS key); Plan 14-03 wires the consumer side.
- Add the `broken-after-remediate` sentinel status to plugin/cli/src/state/sentinel.ts + the list renderer.
- Add per-agent `preserve_paths.json` files for CAT-04 user-data preservation.

The bash-side handler stubs Plan 14-02 just replaced (sudoers.sh + user.sh + nodejs.sh real bodies) are STABLE — Plan 14-03 only touches plugin/lib/remediate/agents.sh + the TS CLI.

## Threat Mitigation Evidence

| Threat ID | Disposition | Evidence |
|-----------|-------------|----------|
| T-14-02 (sudoers drift overwrite without consent) | mitigate | Plan 14-01's bail gate gates drift overwrite via collect_all_decisions; Plan 14-02's install_or_overwrite uses the SAME visudo gate as the additive create path (Test 46 asserts: ≥2 calls to install_or_overwrite in 20-sudoers.sh, zero inline visudo -cf, exactly 2 visudo -cf in the helper). Test 41 forces visudo -cf failure via the test-only hatch and asserts the file is left UNCHANGED. Test 43 asserts drift bails 65 without --yes AND the file is byte-identical (no mutation). |
| T-14-03 (chown on non-empty prefix) | mitigate | _is_trivially_salvageable returns false on any non-allowlist entry. Test 26 (unit-level: pre-populated lib/node_modules/some-user-pkg/ flips predicate to false). Test 29 (unit-level: strategy_for returns "rebase" for under-home + non-salvageable). Test 37 (E2E: brownfield with pre-existing user-installed module → strategy=rebase fires; pre-existing module preserved). |
| T-14-07 (npm-ls output injection) | mitigate | jq parses safely (`-r --argjson` with no string interpolation). `--` terminates sudo AND npm option parsing in the per-module install loop. 2 occurrences of `npm install -g --` in plugin/lib/remediate/nodejs.sh. Adversarial version strings flow to npm which rejects invalid semver (logged as [REMEDIATE-01:partial], no shell evaluation). |
| T-14-08 (chown -R on system path) | mitigate | _strategy_for checks `[[ "$prefix" != "$user_home"/* ]]` and forces rebase for system paths. Test 28 (unit-level: /usr → "rebase"). Test 36 (unit-level: /usr → "rebase" even when empty). |

## Greenfield + Brownfield Bats Counts

- **Ubuntu 22.04:** 177/177 PASS (154 Plan 14-01 baseline + 14 Plan 14-02 Task 1 + 9 Plan 14-02 Task 2)
- **Ubuntu 24.04:** 177/177 PASS
- **Test growth:** +23 net (177 - 154)

The plan's `<verification>` block predicted 174 — actual is 177 because Test 39 implicitly grew into Tests 39 + 47 (BHV-07 regression coverage added to verify the refactor preserves byte-stability), Test 45 was added as a re-run idempotency check on the path-wiring fixture (beyond Test 44's E2E check), and Test 47 is the post-refactor BHV-07 regression check called for in the plan's `<verify>` block. The plan's "174" baseline did not account for these natural extensions.

## Self-Check: PASSED

- plugin/lib/remediate/nodejs.sh: FOUND (Task 1, commit e283924)
- plugin/lib/remediate/sudoers.sh: FOUND (Task 2, commit 75eb997)
- plugin/lib/remediate/user.sh: FOUND (Task 2, commit 75eb997)
- plugin/provisioner/{30-nodejs,20-sudoers,40-path-wiring}.sh modifications: FOUND (Task 1 + Task 2)
- tests/bats/14-remediate.bats (+23 @tests): FOUND (Task 1 + Task 2)
- tests/bats/helpers/brownfield.bash (+8 fixtures + _brownfield_baseline): FOUND (Task 1 + Task 2)
- .planning/REQUIREMENTS.md (REMEDIATE-01/02/03 → Complete): FOUND (Task 2)
- Commits e283924 + 75eb997: FOUND in `git log --oneline -3`
- 177/177 bats GREEN on Ubuntu 22.04 + 24.04 Docker: VERIFIED via /tmp/test-24d.log + /tmp/test-22b.log

## Next Phase Readiness

- Plan 14-03 ready to start (the per-agent stub `remediate::agents::reinstall_stub` + the TS CLI `install.ts` wiring; bash-side handlers from Plan 14-02 are STABLE).
- REMEDIATE-01 + REMEDIATE-02 + REMEDIATE-03 complete; only REMEDIATE-04 remains for v0.3.4 Phase 14.
- T-14-02 + T-14-03 + T-14-07 + T-14-08 mitigations all verified by @tests + greps.
- Greenfield invariant: 177/177 GREEN on full Docker matrix; brownfield REMEDIATE-01/02/03 paths all green end-to-end.
- No blockers; no open questions; no out-of-scope deferrals.

---
*Phase: 14-remediate-consent-flag-exit-codes*
*Completed: 2026-05-10*
