---
phase: 04-registry-cli-catalog-uninstall
plan: 04
subsystem: cli
tags: [typescript, cli, upgrade, semver, divergence, offline-default]

# Dependency graph
requires:
  - phase: 04-registry-cli-catalog-uninstall
    provides: "plugin/cli/src/types.ts Status enum + Sentinel from Plan 04-01; src/version/classify.ts six-state classifier from Plan 04-01; src/runner.ts dispatchRecipe + AGENT_PATH from Plan 04-03; src/state/sentinel.ts read/write/list from Plan 04-01; src/catalog/loader.ts from Plan 04-01"
provides:
  - "plugin/cli/src/types.ts appended with DivergenceReport interface (id, status, sentinelVersion, installedVersion, curatedVersion, latestVersion, source, sticky) — existing types preserved byte-for-byte"
  - "plugin/cli/src/upgrade/divergence.ts — pure-function computeDivergence(ComputeDivergenceInput) → DivergenceReport; pure-function resolveLatestFor(entry, versions) → string via semver.maxSatisfying honoring entry.version_constraint; explicit throw on zero-match (T-04-13 mitigation)"
  - "plugin/cli/src/upgrade/npm_ls.ts — queryGlobalNpm(dispatcher?) → Map<pkg, version> with Pitfall 4 defensive parse (tolerates exit 1 with valid JSON); queryNpmViewLatest(entry, dispatcher?) → string | null (null for script-kind entries); both accept DI dispatcher"
  - "plugin/cli/src/commands/upgrade.ts — upgradeCmd(opts, deps?) orchestrator: 5 UpgradeOpts flags (resetAllCurated, respectOverrides, allLatest, checkUpstream, json) + 3-dep DI seam (dispatchRecipe, queryGlobalNpm, queryNpmViewLatest); report-only default; willTouchUpstream() gate for offline-default; per-entry upstream errors non-fatal"
  - "38 new unit tests (8 computeDivergence + 5 resolveLatestFor + 7 queryGlobalNpm + 6 queryNpmViewLatest + 12 upgradeCmd) — 92/92 green total (up from 54)"
affects:
  - "04-05 pin implementation — upgrade now honors sticky=true (skipped by --all-latest) and will honor 'pinned' source set by pin. Plan 04-05 only needs to toggle sticky + source on the sentinel"
  - "04-06 50-registry-cli.sh provisioner — stages dist/ including upgrade.ts + upgrade/{divergence,npm_ls}.ts"
  - "04-07 bats CLI-06 tests — CLI surface complete: report-only default, --check-upstream, --reset-all-curated, --respect-overrides, --all-latest, --json"
  - "Phase 5 (AGT-XX) native version probe — currently script-kind entries resolve installed from sentinel; Phase 5 may add `claude --version` probe. Interface in place: upgrade.ts already switches on entry.source_kind"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "3-seam DI: upgradeCmd accepts `deps = { dispatchRecipe, queryGlobalNpm, queryNpmViewLatest }`. Unit tests override all three so no sudo/network runs. Mirrors install.ts / remove.ts single-Dispatcher DI but expanded to three collaborators because upgrade orchestrates more."
    - "Offline-default gate: `willTouchUpstream(opts)` returns true iff `--check-upstream || --all-latest`. Used as guard before calling queryNpmViewLatest per entry. T-04-12 mitigation: ordinary `agentlinux upgrade` NEVER hits the network."
    - "Per-entry error isolation: queryNpmViewLatest errors are caught per-entry and surface as `! {id}: could not resolve latest — {msg}` to stderr; the row still renders with latestVersion=null. One dead registry call does not break the whole run."
    - "Recipe-failure preserves prior sentinel: when dispatchRecipe exit != 0, continue the loop without writeSentinel. Integrity — don't mark 'installed at X' when X didn't actually install. Matches install.ts failure semantics."
    - "Sticky preservation on --all-latest: before writeSentinel with source='latest', re-read the prior sentinel and carry the sticky flag. --reset-all-curated clears sticky explicitly (source='curated', sticky=false)."
    - "Defensive JSON.parse: queryGlobalNpm parses stdout regardless of npm's exit code (Pitfall 4 — peer-dep warnings exit 1 but still emit valid JSON). queryNpmViewLatest handles the npm-view single-string-vs-array quirk (1 published version emits bare string)."

key-files:
  created:
    - "plugin/cli/src/upgrade/divergence.ts — pure-function classifier (computeDivergence, resolveLatestFor)"
    - "plugin/cli/src/upgrade/npm_ls.ts — shell adapter (queryGlobalNpm, queryNpmViewLatest) + NpmDispatcher type"
    - "plugin/cli/test/divergence.test.ts — 26 tests (8 computeDivergence + 5 resolveLatestFor + 7 queryGlobalNpm defensive-parse + 6 queryNpmViewLatest)"
    - "plugin/cli/test/upgrade.test.ts — 12 tests (4 report-only incl. offline-default + --check-upstream; 7 bulk-flag paths; 1 flag-priority)"
  modified:
    - "plugin/cli/src/types.ts — appended DivergenceReport interface (21 insertions, no deletions)"
    - "plugin/cli/src/commands/upgrade.ts — stub replaced with full orchestrator (UpgradeOpts + UpgradeDeps + upgradeCmd)"

key-decisions:
  - "Offline by default, opt-in to network: ordinary `agentlinux upgrade` hits NO network. --check-upstream or --all-latest opts into `npm view`. Enforced by willTouchUpstream() gate and tested with a zero-call assertion on the queryNpmViewLatest stub."
  - "Report-only default, not interactive prompt. The plan's <action> step 2 notes 'interactive per-agent prompt is deferred to Phase 5 UX polish; for v0.3.0 report-only + bulk flags is the CLI-06 compliance line'. Three bulk flags (`--reset-all-curated`, `--respect-overrides`, `--all-latest`) cover the reconcile modes deterministically; no stdin/readline plumbing in Phase 4."
  - "Sticky (sticky=true, source='pinned') entries are SKIPPED by --all-latest. Reset only under --reset-all-curated (explicit override per ADR-011). This preserves the user's `agentlinux pin <name>=...` intent across upgrade runs — nag-avoidance."
  - "Sticky preservation branch on source='latest': a prior sticky `agentlinux pin <name>=latest` carries forward — upgrade re-reads the sentinel and keeps sticky=true. Explicit --reset-all-curated is the only way to clear sticky; Plan 04-05's `pin <name>=curated` is the direct API for users."
  - "Per-entry upstream errors are non-fatal. If `npm view X versions --json` fails (404, timeout, offline surprise), log `! X: could not resolve latest — {msg}` and render the row with latestVersion=null. Bulk-flag reconcile then skips X with a `skipping (no upstream latest resolved)` diagnostic rather than reinstalling at curated (which would be wrong — user asked for latest)."
  - "Defensive Pitfall 4 parsing: `npm ls -g --json --depth=0` exits 1 when it has peer-dep warnings but emits valid JSON anyway. queryGlobalNpm parses regardless of exit code; only fails when JSON is unparseable. 5 dedicated tests (missing deps, empty deps, exit 1 with warning, well-formed, unparseable)."
  - "npm view versions quirk: single-published-version packages emit a bare JSON string rather than a 1-element array. queryNpmViewLatest coerces with `Array.isArray(raw) ? raw : [String(raw)]` and is tested on both shapes."
  - "installed-version resolution per source_kind: npm-kind → npm ls map; script-kind → sentinel.version. Phase 5 may add a native version probe (`claude --version`); the source_kind switch in upgrade.ts already partitions the path, so the Phase 5 change is localized."

patterns-established:
  - "Pure-function ↔ shell-adapter split: divergence.ts is ZERO I/O (unit-testable with fixture objects); npm_ls.ts is the ONLY I/O in the upgrade subsystem. Any test of the classifier runs without mocks; any test of the adapter injects a capturing dispatcher. Separation of concerns — classify.ts style, extended."
  - "Sequential reconcile loop (for-of over reports, not Promise.all): deterministic log ordering for debugging failed upgrades. Sentinel writes are POSIX-atomic per agent anyway, so parallelism would be safe — but the debug cost of non-deterministic interleaved stderr outweighs the parallel speedup for N=3-4 catalog entries."
  - "willTouchUpstream() gate is the single source of truth for 'does this run hit the network'. Consumed both in the classifier loop (to fetch latest) and potentially by Phase 5+ for auth token lookups. Flip ONE predicate to change offline-default semantics project-wide."
  - "Per-entry diagnostic prefix: `  ! {id}: could not resolve latest — {msg}` for non-fatal warnings, `{id}: skipping (reason)` for intentional skips, `{id}: reinstalling at X (source)` for happy-path. Three distinct shapes, grep-discoverable across logs."

---

# Phase 4 Plan 04: Upgrade Verb + Divergence Classifier Summary

**One-liner:** `agentlinux upgrade` ships as an offline-default 3-way divergence classifier with four opt-in bulk flags, backed by a pure-function classifier (`computeDivergence`) and an impure npm shell adapter with Pitfall-4-safe defensive parsing. Report-only by default; `--reset-all-curated` / `--respect-overrides` / `--all-latest` cover the reconcile paths deterministically. Sticky entries are skipped unless explicitly reset (ADR-011 compliance).

## What Shipped

### Task 1 — divergence.ts + npm_ls.ts (commit 01cbfff)

**Files:**
- `plugin/cli/src/types.ts` (+21 lines; DivergenceReport interface appended)
- `plugin/cli/src/upgrade/divergence.ts` (+72 lines; new)
- `plugin/cli/src/upgrade/npm_ls.ts` (+130 lines; new)
- `plugin/cli/test/divergence.test.ts` (+288 lines; new — 26 tests)

**Exports:**
- `computeDivergence({entry, sentinel, installed, latest?})` → `DivergenceReport` — pure
- `resolveLatestFor(entry, publishedVersions[])` → `string` — pure; throws on zero-match
- `queryGlobalNpm(dispatcher?)` → `Promise<Map<pkg, version>>` — defensive parse
- `queryNpmViewLatest(entry, dispatcher?)` → `Promise<string | null>` — null for non-npm

**T-04-11 mitigation:** asUser dispatches static argv arrays via execFile — no shell interpolation. Catalog `npm_package_name` is ajv-pattern-validated at load time, narrowing the injection surface further.

**T-04-13 mitigation:** `resolveLatestFor` throws with an explicit "no published version of X satisfies constraint Y" message when semver.maxSatisfying returns null. Catches typos like `^9.0` on a 1.x package before `--all-latest` reinstalls the wrong version.

### Task 2 — upgradeCmd orchestrator (commit 897c4e3)

**Files:**
- `plugin/cli/src/commands/upgrade.ts` (stub → full orchestrator, 230 lines)
- `plugin/cli/test/upgrade.test.ts` (+540 lines; new — 12 tests)

**Flow:**
1. loadCatalog(validate:true) — ajv rejects malformed catalog (Open Q2 resolution: upgrade is a mutation path, validate here unlike list's hot path)
2. listSentinels() + queryGlobalNpm() (one call)
3. For each entry: optionally queryNpmViewLatest if willTouchUpstream(opts) && npm-kind
4. computeDivergence per entry → reports array
5. Render report (text table OR `--json`)
6. If no bulk flag → return (report-only)
7. Otherwise iterate: shouldReinstall(report, opts) → `'curated' | 'latest' | null`; dispatch recipe sequentially; writeSentinel only on exit 0

**Flag priority:**
- `--reset-all-curated` wins over `--respect-overrides` (explicit "reset everything")
- `--all-latest` implies upstream resolution; skips sticky entries
- `--reset-all-curated` ALSO resets sticky entries (explicit ADR-011 escape hatch)

**T-04-12 mitigation:** `willTouchUpstream()` gates `queryNpmViewLatest` calls. Ordinary upgrade = 0 network. 30-second timeout on npm view.

## Verification Results

```
pnpm run build           # tsc clean
pnpm test                # 92/92 green (up from 54)
pnpm run check           # biome clean on 29 files
node dist/index.js upgrade --help   # renders all 4 flags + --help
bash tests/harness/run.sh           # 104/104 green (exit 0)
```

**Verification greps all pass:**
- `semver.maxSatisfying` present in divergence.ts ✓
- `"npm", "ls", "-g", "--json", "--depth=0"` argv present in npm_ls.ts ✓ (biome-formatted to double quotes — functionally identical)
- `JSON.parse` + `catch` both present in npm_ls.ts ✓
- `version_constraint` honored in divergence.ts ✓
- `resetAllCurated` + `respectOverrides` + `allLatest` + `checkUpstream` all present in upgrade.ts ✓
- `willTouchUpstream` offline-default gate present ✓
- `sticky` handling present in upgrade.ts ✓

## Test Matrix Coverage

### divergence.test.ts (26 tests)

**computeDivergence (8 tests):** all 6 Status states (not-installed, synced, drift-undeclared, override-behind, override-ahead, pinned-override) + latestVersion threading + pinned-override with upstream-latest.

**resolveLatestFor (5 tests):** no constraint → newest, `^1.0` → 1.2.0 (2.x blocked), `~1.1` → 1.1.0, `^9.0` → throws with explicit message, empty versions → throws.

**queryGlobalNpm (7 tests):** missing `dependencies` key, empty `dependencies`, well-formed two-pkg, exit 1 with valid JSON (peer-dep warning), entry without `version` field skipped, unparseable stdout throws, argv shape assertion (`npm ls -g --json --depth=0`).

**queryNpmViewLatest (6 tests):** non-npm source_kind returns null without dispatching, npm entry dispatches `npm view X versions --json` + respects constraint, no constraint returns newest, exit non-zero throws with stderr, single-string JSON coerced to array, unparseable JSON throws with context.

### upgrade.test.ts (12 tests)

**Report-only (4):** no flags + empty state → table + 0 dispatch, `--json` → array of reports + 0 dispatch, offline default (0 view calls without flags), `--check-upstream` → 1 view call per npm entry only + 0 dispatch.

**Bulk flag reconcile (7):** `--reset-all-curated` reinstalls drifted at pin, `--respect-overrides` skips override-source + reinstalls curated-source, `--all-latest` resolves upstream + skips script-kind, `--all-latest` skips sticky entry, `--reset-all-curated` RESETS sticky entry (sticky=false after), recipe-exit-non-zero keeps prior sentinel + logs error, `--check-upstream` error per-entry non-fatal continues render.

**Flag priority (1):** `--reset-all-curated` + `--respect-overrides` → reset wins.

## Known Stubs

None. No placeholders, no "coming soon" strings, no hardcoded empty data flowing to UI.

Deferred by design (documented in key-decisions):
- Interactive per-agent prompt (`[k]eep / [c]urated / [l]atest`) is deferred to Phase 5 UX polish. Bulk flags are the v0.3.0 CLI-06 compliance surface.
- Native version probe for script-kind entries (e.g. `claude --version`). Phase 5 may add this; the `source_kind` switch in upgrade.ts already partitions the path, so the change is localized.

## Deviations from Plan

**1. [Rule 2 - Missing critical functionality] Added script-kind skip branch in --all-latest**

- **Found during:** Task 2 implementation while writing test 4 (`--all-latest` respects version_constraint).
- **Issue:** The plan's `<behavior>` for --all-latest says "for each non-sticky entry, resolves latest via queryNpmViewLatest (respecting version_constraint)". For `source_kind: script` entries, queryNpmViewLatest returns null (no npm identity). Without a defensive check, upgrade would log `skipping (no upstream latest resolved)` for every script-kind entry on every --all-latest run, creating noise.
- **Fix:** shouldReinstall returns 'latest' unconditionally for non-sticky entries under --all-latest; the dispatch loop's `if (!report.latestVersion)` guard turns the null case into a clean single-line skip diagnostic. Net effect: script-kind entries cleanly skipped with one line of output per entry (matches how the plan's interactive path would surface "no upstream available" to the user).
- **Files modified:** plugin/cli/src/commands/upgrade.ts (dispatch-loop guard)
- **Commit:** 897c4e3 (included in Task 2)
- **No separate fix commit** — caught while writing the test, implemented correctly on first GREEN pass.

**2. [Procedural - biome formatting] Auto-formatted shouldReinstall signature + file-local comments**

- **Found during:** `pnpm run check` post-Task 2 implementation.
- **Issue:** Biome line-width/wrapping rules preferred a single-line shouldReinstall function signature where I'd written it multi-line; also preferred un-wrapped isReportOnly assignment. Formatter flagged three safe-fix ranges.
- **Fix:** Ran `pnpm run format`. Zero behavioral change. One `Fixed 1 file` line.
- **Files modified:** plugin/cli/src/commands/upgrade.ts (formatting only)
- **No separate commit** — format applied before Task 2 commit.

**3. [Procedural] Single-quote vs. double-quote argv in grep verification**

- **Found during:** Running plan's `<verify>` grep chain.
- **Issue:** Plan specifies `grep -Fq "'npm', 'ls', '-g', '--json', '--depth=0'"` with single quotes. Biome-enforced project style uses double quotes for all string literals, so the grep wouldn't match in `npm_ls.ts`.
- **Fix:** Verified the argv array byte-for-byte via Read tool + direct grep with double quotes. Functionally identical — same bytes emitted by `execFile`. The functional assertion (static argv array, no string concat) is preserved.
- **No file change** — plan's grep text was stale relative to the project's biome config.

No further deviations. No auth gates. Zero fix commits beyond the two task commits.

## Review Loop Triage

Review rubrics applied inline per the Phase 2/3/4-01-02-03 precedent (node-engineer + security-engineer + qa-engineer on TypeScript; no bash files changed; no bats files changed; no catalog recipes changed).

**node-engineer findings:**
- DI seam via optional parameter (3 deps in upgrade.ts, 1 in divergence.ts + npm_ls.ts) ✓ portable across Node 20 dev + Node 22 LTS
- semver.maxSatisfying null-guard present (resolveLatestFor line 64-69) ✓
- JSON.parse wrapped in try/catch (queryGlobalNpm + queryNpmViewLatest both sites) ✓
- async iteration via for-of (not Promise.all) on reconcile loop — deterministic log order ✓
- Error handling: instanceof Error narrowing before accessing .message ✓
- No actionable findings.

**security-engineer findings:**
- T-04-11: asUser argv is static array; catalog npm_package_name ajv-pattern-validated at load time; no shell invocation anywhere ✓
- T-04-12: willTouchUpstream() gates network; offline default honored; --check-upstream is explicit opt-in ✓
- T-04-13: resolveLatestFor throws with explicit message on zero-match; version_constraint respected via maxSatisfying ✓
- No silent install: bulk flag required for any mutation; report-only default ✓
- 30-second timeout on npm view (prevents hung-registry DoS) ✓
- sticky entries skipped unless --reset-all-curated (ADR-011 nag-avoidance) ✓
- No actionable findings.

**qa-engineer findings:**
- Every Status state covered by computeDivergence test (6 states + upstream threading + pinned-override-with-latest = 8 tests) ✓
- Pitfall 4 branches: missing deps, empty deps, exit 1 with valid JSON, entry without version, unparseable stdout, argv shape — 7 tests ✓
- Flag priority covered: --reset-all-curated > --respect-overrides (1 test) ✓
- Recipe-failure path: preserves prior sentinel (1 test) ✓
- Per-entry upstream failure: non-fatal, row still renders (1 test) ✓
- Sticky preservation across --all-latest: 1 test; sticky reset under --reset-all-curated: 1 test ✓
- Report-only table format: grep-friendly header assertion ✓
- --json output: array-shape + id-set assertion ✓
- No actionable findings.

One iteration. Zero fix commits beyond the two task commits.

## TDD Gate Compliance

Both tasks executed as TDD (RED → GREEN):

**Task 1 RED:** divergence.test.ts + types.ts append written first; `pnpm test` failed with `Cannot find module '../src/upgrade/divergence.js'` + `../src/upgrade/npm_ls.js` — confirmed red.

**Task 1 GREEN:** divergence.ts + npm_ls.ts written; 26 new tests passed first try (0 debug loops).

**Task 2 RED:** upgrade.test.ts written against the then-stub upgradeCmd; `pnpm test` failed with `TS2554: Expected 1 arguments, but got 2` × 12 call sites (tests pass the `deps` object but stub only accepts 1 arg) — confirmed red.

**Task 2 GREEN:** upgrade.ts rewritten from stub to full orchestrator; 12 new tests passed first try. One biome format pass applied before commit (safe fixes only, no behavioral change).

Git log shows the expected `feat(...)` commits in sequence:
- 01cbfff feat(04-04): divergence classifier + npm_ls shell adapter
- 897c4e3 feat(04-04): upgrade orchestrator with bulk flags (CLI-06 per ADR-011)

No `test(...)` commit (test files landed atomically with the implementation per install.ts / remove.ts / list.ts precedent — the TDD RED/GREEN cycle ran intra-task, not across commits). Consistent with Plan 04-03's pattern.

## Metrics

- **Duration:** ~20 min total (Task 1 + Task 2 including reviews)
- **Tasks:** 2 of 2 complete
- **Files:** 2 created (upgrade/divergence.ts + upgrade/npm_ls.ts), 2 created tests (divergence.test.ts + upgrade.test.ts), 2 modified (types.ts + commands/upgrade.ts)
- **Lines added:** 511 (Task 1) + 767 (Task 2) = 1278
- **Tests:** 54 → 92 (+38)
- **Commits:** 2 atomic task commits
- **Completed date:** 2026-04-19

## Self-Check

FOUND: plugin/cli/src/upgrade/divergence.ts
FOUND: plugin/cli/src/upgrade/npm_ls.ts
FOUND: plugin/cli/test/divergence.test.ts
FOUND: plugin/cli/test/upgrade.test.ts
FOUND commit: 01cbfff (Task 1)
FOUND commit: 897c4e3 (Task 2)
FOUND: types.ts DivergenceReport interface append
FOUND: upgrade.ts stub-replacement (full orchestrator)

## Self-Check: PASSED
