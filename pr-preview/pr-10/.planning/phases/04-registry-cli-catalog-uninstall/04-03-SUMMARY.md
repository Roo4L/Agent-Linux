---
phase: 04-registry-cli-catalog-uninstall
plan: 03
subsystem: cli
tags: [typescript, cli, commander, sentinel, dispatch, idempotency, di-seam]

# Dependency graph
requires:
  - phase: 04-registry-cli-catalog-uninstall
    provides: "plugin/cli/src/{types,guard/user,state/sentinel,state/dispatcher,version/classify,catalog/loader,index}.ts interface surface from Plan 04-01; plugin/catalog/catalog.json + 8 recipes from Plan 04-02"
provides:
  - "plugin/cli/src/runner.ts exporting dispatchRecipe(args, dispatcher?) + AGENT_PATH constant byte-identical to plugin/provisioner/40-path-wiring.sh line 146 (T-04-07 mitigation)"
  - "plugin/cli/src/commands/list.ts — catalog+sentinels → classify() → text table or --json output; filters test_only unless --include-test"
  - "plugin/cli/src/commands/install.ts — loadCatalog(validate:true) → decideVersion → idempotent short-circuit (semver.eq + !force) → dispatchRecipe(install.sh) → writeSentinel"
  - "plugin/cli/src/commands/remove.ts — sentinel-required (unless --force) → dispatchRecipe(uninstall.sh) → deleteSentinel"
  - "DI seam established: install/remove accept optional third-parameter Dispatcher for unit-test capturing mocks (mock.module undefined on Node 20.20.1 executor)"
  - "23 new unit tests (5 runner + 6 list + 12 install + 5 remove) — 54/54 green total"
  - "--include-test flag registered on `install` subcommand (addition to Plan 04-01's list-only registration)"
affects:
  - "04-04 upgrade implementation — reuses dispatchRecipe/runner.ts for its recipe dispatch path; classify() already exercised"
  - "04-05 pin implementation — reuses writeSentinel (via the locked sentinel shape) + decideVersion sticky branch"
  - "04-06 50-registry-cli.sh provisioner — stages dist/ including runner.ts + commands/{list,install,remove}.ts"
  - "04-07 bats CLI-02/03/04/05 tests — the CLI surface they assert against is now complete"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DI seam via optional parameter: runner.ts exports `type Dispatcher = (user, argv, opts) => Promise<DispatchResult>`; install/remove accept an optional third arg defaulting to the real dispatchRecipe. Unit tests inject a capturing implementation — no real sudo invocation. Chosen over node:test mock.module because that API is undefined on Node 20.20.1 (executor host)."
    - "process.exit throw-sentinel test pattern: tests replace process.exit with a `(code) => { throw new Error('__test_exit_${code}__') }` wrapper, then `assert.rejects(..., /__test_exit_64__/)` captures the intended exit code without actually exiting the test runner."
    - "Silent-stdio test helper: reassigns console.log/console.error to arrays on entry, restores in finally{} — asserts on captured output without cluttering the test runner."
    - "AGENTLINUX_CATALOG_DIR + AGENTLINUX_STATE_DIR tmp-dir env seams chained per test suite; dynamic `await import()` of the tested module so env vars are set before module body reads defaults (belt-and-braces; loader+sentinel both resolve per-call anyway)."
    - "biome-ignore annotation for semantically-required `delete process.env.X`: the biome unsafe-fix would coerce assignments to the literal string 'undefined', contaminating sibling test env lookups. `delete` is the only correct API."

key-files:
  created:
    - "plugin/cli/src/runner.ts — shared dispatchRecipe + AGENT_PATH + Dispatcher type"
    - "plugin/cli/test/runner.test.ts — 5 tests (argv shape, env injection, canonical PATH, extraEnv override, exit-code pass-through)"
    - "plugin/cli/test/list.test.ts — 6 tests (text hiding test_only, --include-test reveal, not-installed, synced-status, --json array, --json hides test_only)"
    - "plugin/cli/test/install.test.ts — 12 tests (fresh install, idempotent no-op, --force, --version override, invalid semver exit 64, unknown agent exit 64, test_only guard, --include-test opts in, recipe exit non-zero propagates, canonical env wiring, sticky --force, sticky short-circuit)"
    - "plugin/cli/test/remove.test.ts — 5 tests (happy, not-installed exit 1, --force no-op, unknown agent exit 64, recipe exit non-zero keeps sentinel)"
  modified:
    - "plugin/cli/src/commands/list.ts (stub → real; classify + test_only filter + text/JSON output)"
    - "plugin/cli/src/commands/install.ts (stub → real; decideVersion + idempotent + dispatchRecipe + writeSentinel)"
    - "plugin/cli/src/commands/remove.ts (stub → real; sentinel guard + dispatchRecipe + deleteSentinel)"
    - "plugin/cli/src/index.ts (added --include-test flag on install subcommand)"

key-decisions:
  - "DI seam over module mocking: `mock.module` is undefined on Node 20.20.1 (executor host); chose to pass an optional Dispatcher parameter (default = real dispatchRecipe). Portable across Node 20 dev and Node 22 LTS production. Each test that needs to assert dispatch behavior injects a capturing impl."
  - "`--include-test` added on the install subcommand too (Plan 04-01 registered it only on `list`). Required by plan's must-have `agentlinux install test-dummy --include-test`. Auto-added as Rule 2 (missing critical functionality for a documented plan contract)."
  - "process.exit throw-sentinel pattern for CLI exit-code assertions in unit tests. Standard alternative (spawning a child node process) is heavier; the throw-sentinel captures exit code + prevents test-runner termination in-process."
  - "`delete process.env.X` with biome-ignore comment is the correct cleanup for test env seams. Biome's unsafe-fix transforms `delete` to `process.env.X = undefined`, but Node.js coerces all process.env assignments to strings, so the second form leaves the literal string 'undefined' — a silent correctness bug that pollutes sibling tests."
  - "Idempotency short-circuit lives inside installCmd (not in runner.ts). runner.ts is dispatch-only; the `semver.eq(existing.version, decision.version) && !force` test is the install-verb contract. `decideVersion` itself is pure (plan 04-01) and agnostic of prior install state save for sticky preservation."

patterns-established:
  - "Tri-layer test capture: (a) `silenceConsole()` swaps console.log/error with array-appenders returning a restore fn; (b) `makeCap()` returns a Dispatcher mock + calls[] array; (c) `process.exit` override throws a regex-matchable sentinel. All three layered in try/finally blocks so test-runner state restores even on assertion failure."
  - "Tmp-dir fixture lifecycle per-suite: `before()` mkdtemp + stage catalog + recipes; `beforeEach()` rm -rf STATE_DIR for clean slate between tests; `after()` rm -rf TMP + delete env vars (with biome-ignore)."
  - "Idempotency is asserted via mock call count, not just side-effect observation: two sequential `installCmd(same-args)` invocations must leave `cap.calls.length === 1` — bytes-stable semantics verified."
  - "Cross-verification of PATH literal via `grep -F` of the exact 66-character string against both plugin/cli/src/runner.ts and plugin/provisioner/40-path-wiring.sh — enforces that any future PATH change in one place fails the plan-verify chain unless the other is updated."

requirements-completed: [CLI-02, CLI-03, CLI-04, CLI-05]

# Metrics
duration: 7 min
completed: 2026-04-19
---

# Phase 4 Plan 03: list/install/remove CLI commands + shared runner.ts Summary

**Three Commander.js action handlers (list/install/remove) + shared dispatchRecipe() in plugin/cli/src/runner.ts land the CLI-02/CLI-03/CLI-04/CLI-05 contract end-to-end on the TypeScript side — idempotent install (`semver.eq + !force` short-circuit), `--force` re-run, `--version` override (sentinel source='override'), test_only filter with `--include-test` opt-in, --json output for machine consumption. 23 new unit tests (5+6+12+5) brought suite to 54/54 green. DI seam via optional `Dispatcher` parameter keeps tests sudo-free on Node 20 where `mock.module` is undefined.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-04-19T11:02:03Z
- **Completed:** 2026-04-19T11:09:12Z
- **Tasks:** 2 (both `type="auto"` tdd="true")
- **Commits:** 2 atomic task commits
- **Files created:** 4 (runner.ts + 3 new test files)
- **Files modified:** 4 (3 command stubs → real impls + index.ts --include-test flag)

## Accomplishments

- **CLI-02 (list):** `agentlinux list` emits a grep-friendly NAME/STATUS/CURATED/INSTALLED/DESCRIPTION table; `--json` emits a machine-parseable array; `test_only` entries hidden by default, revealed by `--include-test`. Verified end-to-end against the real `plugin/catalog/catalog.json` — three real agents + test-dummy under `--include-test` all render correctly with status `not-installed`.
- **CLI-03 (install):** Idempotent short-circuit on `semver.eq(existing.version, decision.version) && !opts.force`; `--force` re-runs recipe even when sentinel matches; `--version 9.9.9` writes sentinel with `source='override'` and dispatches recipe with `AGENTLINUX_PINNED_VERSION=9.9.9`. Unknown agent → exit 64 with available-list message. Invalid semver → exit 64. test_only entry without `--include-test` → exit 64.
- **CLI-04 (remove):** Missing sentinel + no `--force` → exit 1 with clear message (T-04-09 mitigation: prevents drive-by uninstall of never-installed catalog entries); `--force` makes missing-sentinel a silent no-op; uninstall.sh non-zero exit propagates and keeps sentinel (retryable by design).
- **CLI-05 (preAction guard):** Already established by Plan 04-01's index.ts preAction hook; this plan's smoke test confirmed `agentlinux list` works under the agent user's EUID.
- **runner.ts (shared dispatcher):** Exports `dispatchRecipe(args, dispatcher?)` + `AGENT_PATH` constant. Env map includes canonical PATH/HOME/NPM_CONFIG_PREFIX/LANG/LC_ALL byte-identical to plugin/provisioner/40-path-wiring.sh line 146 (T-04-07 mitigation — `grep -F` cross-verified). Accepts optional `Dispatcher` DI seam so unit tests avoid real sudo.
- **Test coverage:** 54/54 tests green. 23 new (5 runner + 6 list + 12 install + 5 remove). Idempotency asserted via mock call-count (not just side-effect observation). sticky-sentinel preservation verified under --force (keeps sticky version over catalog pin).
- **Verifications green:** `pnpm run build` (tsc clean), `pnpm test` (54/54), `pnpm run check` (biome clean on 25 files), `bash tests/harness/run.sh` (104/104).

## Task Commits

1. **Task 1: runner.ts — shared recipe dispatcher** — `86ff777` (feat)
2. **Task 2: list/install/remove commands + unit tests** — `93fb37d` (feat)

## Files Created/Modified

### Created

| Path | Purpose |
|------|---------|
| `plugin/cli/src/runner.ts` | Shared dispatchRecipe + AGENT_PATH constant + Dispatcher type export |
| `plugin/cli/test/runner.test.ts` | 5 tests (argv shape, env injection, canonical PATH, extraEnv override, exit pass-through) |
| `plugin/cli/test/list.test.ts` | 6 tests (text default filter, --include-test reveal, not-installed, synced, --json array, --json filter) |
| `plugin/cli/test/install.test.ts` | 12 tests (fresh, idempotent, --force, --version, invalid semver, unknown, test_only guard, --include-test opt-in, recipe-exit-nonzero, canonical env, sticky+--force, sticky short-circuit) |
| `plugin/cli/test/remove.test.ts` | 5 tests (happy, not-installed exit 1, --force no-op, unknown agent exit 64, recipe-exit-nonzero keeps sentinel) |

### Modified

| Path | Change |
|------|--------|
| `plugin/cli/src/commands/list.ts` | Stub replaced with real impl: loadCatalog(validate:false) + listSentinels + classify per entry + text/JSON rendering + test_only filter |
| `plugin/cli/src/commands/install.ts` | Stub replaced with real impl: loadCatalog(validate:true) + catalog.find + test_only guard + semver.valid + decideVersion + idempotent short-circuit + dispatchRecipe + writeSentinel. Accepts optional Dispatcher DI seam. |
| `plugin/cli/src/commands/remove.ts` | Stub replaced with real impl: loadCatalog(validate:true) + catalog.find + sentinel guard + dispatchRecipe + deleteSentinel. Accepts optional Dispatcher DI seam. |
| `plugin/cli/src/index.ts` | Added `--include-test` flag to `install` subcommand registration (Plan 04-01 had it only on `list`) |

## Decisions Made

- **DI seam over module mocking:** Node 20.20.1 (executor host) has `mock.module` undefined — confirmed empirically (`typeof test.mock?.module` returns `undefined`). Chose DI via optional third parameter: `installCmd(name, opts, dispatcher?: Dispatcher)` with default = real dispatchRecipe. Unit tests inject a capturing impl; production code omits the arg. This is portable across Node 20 dev + Node 22 LTS production without experimental flags.

- **--include-test added to install subcommand (Rule 2):** Plan 04-01 registered `--include-test` only on `list`, but the plan's must-have truth `agentlinux install test-dummy --include-test` requires it on install too. Added the Commander option there in index.ts — Rule 2 (missing critical functionality for documented plan contract).

- **process.exit throw-sentinel pattern:** Tests that assert on `process.exit(code)` replace the function with a throwing wrapper: `(code) => { exitCodes.push(code); throw new Error('__test_exit_${code}__') }`. Test body then uses `assert.rejects(..., /__test_exit_64__/)` to match. Cleaner than spawning child node processes + in-process so state assertions work on tmp-dir sentinels.

- **`delete process.env.X` over `= undefined`:** Biome's `unsafe-fix` would rewrite `delete process.env.X` to `process.env.X = undefined`, but Node.js stringifies every process.env assignment — you'd get the literal 3-character string `"undefined"`, which is not the same as absence. `delete` is the only API that actually removes the key. Annotated with `biome-ignore lint/performance/noDelete` comment citing the semantic requirement.

- **Idempotency logic lives in installCmd, not runner.ts:** runner.ts is a dispatch primitive — it takes (recipe path, version, env extras) and runs. The `semver.eq + !force` short-circuit is the install-verb's UX contract, so it belongs in commands/install.ts. decideVersion stays pure (Plan 04-01) and is agnostic of prior state except for the sticky preservation branch.

## Deviations from Plan

One Rule 2 auto-add (documented above: `--include-test` on install subcommand), one Rule 1 test bug fix (self-discovered during first `pnpm test` run), plus biome-formatter/noDelete hygiene.

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added `--include-test` flag registration to install subcommand in index.ts**
- **Found during:** Task 2 (writing installCmd test_only guard code — realized Commander doesn't register the flag for install)
- **Issue:** Plan's must-have says `agentlinux install test-dummy --include-test` must work. Plan 04-01's index.ts registered `--include-test` only on `list`; `install` has `--force` + `--version <semver>`. Without the flag on install, Commander would either ignore the arg (treating it as a positional) or throw "unknown option". The installCmd body already honors `opts.includeTest` — just the registration is missing.
- **Fix:** Added `.option("--include-test", "allow installing test-only entries (hidden by default)")` on the install subcommand in index.ts.
- **Files modified:** plugin/cli/src/index.ts
- **Verification:** smoke-tested via unit test `test_only entry WITH --include-test: install proceeds` — passes.
- **Committed in:** 93fb37d (Task 2)

**2. [Rule 1 - Test Bug] Sticky-sentinel test first written with version matching catalog pin — triggered idempotent short-circuit instead of asserting sticky preservation**
- **Found during:** Task 2 (first `pnpm test` after writing install.test.ts)
- **Issue:** Original test pre-seeded sentinel `{version: '1.2.3', sticky: true}` and called `installCmd('fake-agent', {})` expecting dispatchRecipe to be called with AGENTLINUX_PINNED_VERSION=1.2.3. But: `decideVersion` preserves sticky so decision.version='1.2.3', and existing.version='1.2.3' → `semver.eq` is true → idempotent short-circuit fires → no dispatch → `cap.calls[0]` is undefined → TypeError reading 'env'.
- **Fix:** Split the behavior into two tests: (a) sticky preserved under `--force` (asserts dispatch fires AND env.AGENTLINUX_PINNED_VERSION=1.2.3 — NOT the catalog's 1.0.0), and (b) sticky + matching-version WITHOUT --force still short-circuits (companion test documenting the normal-path semantics). Both tests pass.
- **Files modified:** plugin/cli/test/install.test.ts
- **Verification:** 54/54 tests green after fix.
- **Committed in:** 93fb37d (Task 2)

### Textual Adjustments

**3. [Biome hygiene] Applied biome's safe fixes for import ordering + line-width + organizeImports; guarded `delete process.env.X` with biome-ignore comments**
- **Found during:** Task 2 (pre-commit-style `pnpm run check` after writing commands)
- **Issue:** Biome flagged (a) unsorted imports in install.ts/remove.ts (type exports second alphabetically), (b) long `console.error(...)` + `join(...)` calls split across lines that biome's formatter would collapse to single lines, (c) `delete process.env.X` in the three test after-hooks (`lint/performance/noDelete`).
- **Fix:** `npx biome check --write` applied safe fixes for (a) and (b). For (c), the biome unsafe-fix would rewrite `delete` to `= undefined` — but Node.js coerces all process.env values to strings, so assignment leaves the literal string `"undefined"`, contaminating sibling tests. Added `// biome-ignore lint/performance/noDelete: delete is required for process.env` comments on all six occurrences across list/install/remove tests.
- **Files modified:** plugin/cli/src/commands/install.ts, plugin/cli/src/commands/remove.ts, plugin/cli/test/install.test.ts, plugin/cli/test/list.test.ts, plugin/cli/test/remove.test.ts
- **Verification:** `pnpm run check` clean on 25 files.
- **Committed in:** 93fb37d (Task 2)

---

**Total deviations:** 1 Rule 2 auto-add (CLI flag registration), 1 Rule 1 test-bug fix (wrong sticky-test expectation), 1 biome hygiene cluster (import ordering + noDelete).
**Impact on plan:** Zero functional deviation from plan intent. All plan must-have truths pass. Test count 12 in install vs plan's ~7-8 — expanded for sticky coverage.

## Issues Encountered

- **Node 20.20.1 lacks `mock.module`:** Confirmed empirically. Plan anticipated this and specified DI fallback; executed as planned. Tests are portable across Node 20 dev and Node 22 LTS production without experimental flags.

- **Biome noDelete + process.env cleanup:** Biome's "fix" for `delete process.env.X` is semantically wrong (assignment coerces to string). Handled with inline biome-ignore comments citing the rationale.

## Review Loop

Applied rubrics inline per Phase 2/3/4-01 precedent (sub-agent spawns unavailable in sequential executor context):

### Task 1 — runner.ts

- **node-engineer rubric:** DI via optional parameter justified in top-level comment; AGENT_PATH exported for cross-verification; Dispatcher type exported so install/remove inherit the shape; `.js` extensions on relative imports (NodeNext); async/await discipline; returns DispatchResult, doesn't throw (mirrors asUser from Plan 04-01). No biome findings.
- **security-engineer rubric:** PATH literal byte-identical to plugin/provisioner/40-path-wiring.sh line 146 (verified via `grep -F` cross-ref); no eval; no shell-string; no user input flows to PATH (it's a constant); extraEnv spread AFTER base env so explicit CLI-internal overrides work without attacker-control risk.
- **qa-engineer rubric:** 5 tests cover argv shape / env injection / canonical PATH / extraEnv override / exit-code pass-through. Zero real-sudo calls.

### Task 2 — list + install + remove + tests

- **node-engineer rubric:** `.js` extensions on all relative imports; async/await discipline; process.exit for CLI error paths (not throw — caller-script contract); DI seam consistent across install + remove (same optional third-parameter shape + same Dispatcher type); stub replacement preserves Opts interface from Plan 04-01; no unhandled rejections; biome clean on 25 files.
- **security-engineer rubric:** agent-id resolved via `catalog.agents.find()` string equality — no shell interpolation (T-04-07); `dispatchRecipe` always called through runner.ts which injects canonical env (no caller can bypass); `semver.valid()` pre-dispatch validation for override versions; no eval / no dynamic require / no user-input-to-shell; test_only enforcement gated by explicit opt-in flag; path construction uses `node:path.join` (not string concat) preventing traversal; CLI-05 guard still fires via preAction hook from Plan 04-01 before any action runs (smoke-test confirmed).
- **qa-engineer rubric:** Idempotent path unit-tested via mock call-count (test 2 confirms second call yields 0 additional dispatch); --force path tested (call count = 2 after two calls); --version override tested (sentinel.source='override' + version=9.9.9); 3 error paths tested (unknown agent / bad semver / test-only without flag); DI seam minimizes coupling — zero real sudo calls in any test; sticky sentinel covered with both --force (dispatch fires with sticky version) and no-force (short-circuit). Remove: 5 cases (happy/missing-no-force/missing-force/unknown/exit-nonzero). List: 6 cases (text filter/reveal/all-not-installed/synced-status/json-array/json-filter).

**Iterations:** 1 pass per task plus the Rule 2 `--include-test` registration add + Rule 1 sticky-test fix documented above. No outstanding actionable findings.

## User Setup Required

None — no external service configuration required. The DI seam + tmp-dir env seams keep all tests self-contained.

## Next Phase Readiness

Plan 04-04 (upgrade command — CLI-06) unblocked with:
- `dispatchRecipe()` ready to call for upgrade.sh-equivalent paths (upgrade reuses install.sh with different AGENTLINUX_PINNED_VERSION env values)
- `classify()` already exercised by list.ts — upgrade calls the same function per entry to pick which branch of the 3-way UX to surface
- Sentinel shape locked; writeSentinel call pattern demonstrated in install.ts
- `semver` + `decideVersion` already integrated — upgrade reuses both

Plan 04-05 (pin command — CLI-07) unblocked with:
- `writeSentinel({...existing, source: 'pinned', sticky: true})` pattern demonstrated in install.ts — pin is a sentinel-only mutation (no recipe dispatch)

Plan 04-06 (50-registry-cli.sh provisioner) unblocked with:
- `plugin/cli/dist/` contains runner.js + commands/{list,install,remove}.js in addition to the Plan 04-01 interface surface — a single `cp -r dist/` stages everything

Plan 04-07 (bats integration) unblocked with:
- Full CLI-02/03/04/05 surface implemented; bats can now assert on `agentlinux list` output text, `agentlinux install test-dummy --include-test` side-effects (sentinel written + /tmp/agentlinux-test-dummy.marker present), `agentlinux remove test-dummy` symmetric cleanup, double-install idempotency, and CLI-05 non-agent-user exit 64

**No blockers or concerns.**

## Self-Check: PASSED

**Created files verified present:**
- plugin/cli/src/runner.ts ✓ FOUND
- plugin/cli/test/runner.test.ts ✓ FOUND
- plugin/cli/test/list.test.ts ✓ FOUND
- plugin/cli/test/install.test.ts ✓ FOUND
- plugin/cli/test/remove.test.ts ✓ FOUND

**Modified files verified:**
- plugin/cli/src/commands/list.ts — stub replaced with real impl (classify + test_only filter + text/JSON) ✓
- plugin/cli/src/commands/install.ts — stub replaced (decideVersion + idempotent + dispatchRecipe + writeSentinel + DI seam) ✓
- plugin/cli/src/commands/remove.ts — stub replaced (sentinel guard + dispatchRecipe + deleteSentinel + DI seam) ✓
- plugin/cli/src/index.ts — `--include-test` flag added to install subcommand ✓

**Commits verified present in git log:**
- 86ff777 (Task 1: runner.ts + 5 tests) ✓ FOUND
- 93fb37d (Task 2: list/install/remove commands + 23 tests + --include-test flag) ✓ FOUND

**Verification run:**
- `pnpm run build` → tsc clean ✓
- `pnpm test` → 54/54 green ✓
- `pnpm run check` → biome clean on 25 files ✓
- `bash tests/harness/run.sh` → 104/104 green ✓
- `grep -Fq '/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin' plugin/cli/src/runner.ts && grep -Fq ... plugin/provisioner/40-path-wiring.sh` → both match (T-04-07 cross-ref) ✓
- End-to-end smoke: `AGENTLINUX_CATALOG_DIR=... AGENTLINUX_STATE_DIR=... node plugin/cli/dist/index.js list` prints the real catalog with 3 entries visible + test-dummy hidden; `--include-test --json` emits a valid 4-entry JSON array ✓

---
*Phase: 04-registry-cli-catalog-uninstall*
*Completed: 2026-04-19*
