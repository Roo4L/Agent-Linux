---
phase: 04-registry-cli-catalog-uninstall
plan: 01
subsystem: cli
tags: [typescript, cli, commander, ajv, jsonschema, catalog, nodenext]

# Dependency graph
requires:
  - phase: 01-harness-setup
    provides: "plugin/cli/ skeleton (package.json with commander pin, tsconfig NodeNext, biome config, stryker skeleton); plugin/catalog/schema.json (Phase 1 stub); pre-commit hooks wired to scripts/validate-catalog.mjs"
  - phase: 02-installer-foundation
    provides: "plugin/lib/as_user.sh (keystone `sudo -u agent -H -E --`); plugin/provisioner/40-path-wiring.sh (the canonical PATH literal the dispatcher caller must match)"
  - phase: 03-nodejs-runtime-per-user-npm-prefix
    provides: "Node.js 22 LTS + npm 10 available on target system; /home/agent/.npm-global/bin as the keystone agent-owned bin path"
provides:
  - "Ajv 2020-12 catalog validator (runtime + pre-commit wrapper) authoritative for CAT-03/CAT-04"
  - "JSON Schema 2020-12 catalog contract extended per ADR-011 (pinned_version required, source_kind enum, allOf/if/then for npm_package_name)"
  - "TypeScript interface surface for all downstream Plans 04-03/04/05 (CatalogEntry, Catalog, Sentinel, VersionDecision, Status)"
  - "Commander.js CLI entrypoint with five subcommand stubs (list/install/remove/upgrade/pin) + CLI-05 EUID preAction guard"
  - "Per-agent sentinel read/write/list/delete (atomic rename) with AGENTLINUX_STATE_DIR test seam"
  - "asUser() TS dispatcher byte-for-byte mirroring plugin/lib/as_user.sh (`sudo -u <u> -H -E --`)"
  - "Pure-function divergence classifier covering all six Status states"
  - "Compile-first test harness (tsc + node:test) — 26 unit tests green"
affects:
  - "04-02 catalog.json recipes (schema contract + pinned_version requirement authoritative here)"
  - "04-03 list/install/remove implementations (consume loader + sentinel + dispatcher + types)"
  - "04-04 upgrade implementation (consumes classifier + dispatcher + semver)"
  - "04-05 pin implementation (consumes sentinel + types)"
  - "04-06 50-registry-cli.sh provisioner (stages dist/ + catalog snapshot)"
  - "04-07 bats CLI-01..07 / CAT-03..04 / INST-04 tests"

# Tech tracking
tech-stack:
  added:
    - "ajv@8.18.0 (JSON Schema 2020-12 validator)"
    - "ajv-formats@3.0.1 (uri/date-time/etc. formats for schema)"
    - "semver@7.7.4 (maxSatisfying/gt/lt/eq for version classifier + upgrade)"
    - "@types/node@22.19.17 + @types/semver@7.7.1 (dev)"
  patterns:
    - "compile-first test harness (tsc tsconfig.test.json → dist-test/ → node --test)"
    - "walk-up schema resolution (env override → search ../.. for plugin/catalog/schema.json)"
    - "CJS interop bridge for ajv under NodeNext ESM (namespace import + `.default ?? namespace` fallback)"
    - "atomic rename(2) write pattern with AGENTLINUX_STATE_DIR env test seam"
    - "Commander.js preAction hook for CLI-05 fail-fast before any action runs"
    - "subcommand stubs throw plan-pointer errors (explicit 'lands in Plan 04-0X')"

key-files:
  created:
    - "plugin/cli/src/types.ts (shared interface contracts — single source of truth)"
    - "plugin/cli/src/catalog/schema.ts (Ajv 2020 singleton + compiled validator)"
    - "plugin/cli/src/catalog/loader.ts (loadCatalog with validate opt-in)"
    - "plugin/cli/src/guard/user.ts (CLI-05 EUID guard via os.userInfo)"
    - "plugin/cli/src/state/sentinel.ts (per-agent atomic write/read/list/delete)"
    - "plugin/cli/src/state/dispatcher.ts (asUser mirrors plugin/lib/as_user.sh)"
    - "plugin/cli/src/version/classify.ts (pure-function six-state classifier)"
    - "plugin/cli/src/index.ts (Commander bootstrap + preAction + parseAsync)"
    - "plugin/cli/src/commands/{list,install,remove,upgrade,pin}.ts (five STUBS)"
    - "plugin/cli/test/schema.test.ts (6 CAT-03/CAT-04 ajv tests)"
    - "plugin/cli/test/classify.test.ts (12 six-state + decideVersion tests)"
    - "plugin/cli/test/sentinel.test.ts (8 atomic roundtrip tests)"
    - "plugin/cli/test/fixtures/catalog-{valid,missing-pin,bad-source-kind}.json"
    - "plugin/cli/tsconfig.test.json (compile-first test target)"
    - "plugin/cli/pnpm-lock.yaml (first lockfile in the repo)"
  modified:
    - "plugin/cli/package.json (added ajv/ajv-formats/semver/@types/*; bin.agentlinux; test+check scripts)"
    - "plugin/cli/tsconfig.json (types:[node], allowImportingTsExtensions:false, explicit include)"
    - "plugin/catalog/schema.json (replaced Phase 1 stub with 2020-12 schema per ADR-011)"
    - "plugin/cli/scripts/validate-catalog.mjs (Phase 1 zero-dep → Phase 4 ajv-driven)"
    - ".gitignore (added plugin/cli/dist/ and plugin/cli/dist-test/)"

key-decisions:
  - "Compile-first test strategy (tsc → dist-test/ → node --test) instead of --experimental-strip-types, because executor host Node is 20.20.1 (the v0.3.0 provisioner installs Node 22 LTS; this only affects local dev ergonomics, not CI or release)."
  - "strictRequired:false on Ajv 2020 to permit allOf/then's required clause to reference parent-scope properties (npm_package_name declared once on $defs/agent, not duplicated into the then clause). Other strict checks (unknown keywords, strict types, additionalProperties:false on ALL levels) stay on."
  - "Namespace-import CJS interop bridge for ajv/ajv-formats: `(mod as any).default ?? (mod as any).Ajv2020 ?? mod`. Portable across TS 5.x minor versions that differ on how they surface `export default` from a CJS package under NodeNext."
  - "Walk-up schema path resolution (plus AGENTLINUX_CATALOG_DIR env override) covers three layouts: repo dev build (dist/ sibling of plugin/catalog), repo test build (dist-test/src/ walking further up), and production (/opt/agentlinux/ where env var is set)."
  - "No flock for sentinel writes — atomic rename(2) on same FS is sufficient for interactive-user concurrency model per 04-RESEARCH §Pattern 5. Revisit only if Phase 5+ introduces automated loop callers."
  - "AGENTLINUX_STATE_DIR env seam for sentinel.ts — resolves installedDir() lazily per-call so unit tests can mutate after module load. Production sets it via /etc/agentlinux.env-shaped config in Plan 06 provisioner."
  - "Five subcommand handlers as STUBS in Wave 1 — each throws `Error` with plan-pointer ('lands in Plan 04-03/04/05'). Keeps the Commander.js program structure + option flags locked here so downstream plans only replace function bodies."
  - "loader.ts named `loader.ts` (not `load.ts` as 04-RESEARCH §Component Responsibilities line 316 suggests) — plan frontmatter files list has `loader.ts` on line 71-72; export name `loadCatalog`. Locked."
  - "src/version/classify.ts imports `Sentinel` from `../types.js`, NOT from `../state/sentinel.js` where RESEARCH §Pattern 6 line 779 shows it. Rationale: types.ts is the single source of truth (Task 2); circular-import-safer."

patterns-established:
  - "Compile-first TS test harness: tsconfig.test.json extends tsconfig.json with rootDir:. + outDir:dist-test; test script is `tsc -p tsconfig.test.json && node --test dist-test/test/`. Node 20 LTS compatible (no --experimental-strip-types dependency)."
  - "Walk-up resource resolution: env override → walk up N levels from import.meta.url looking for sibling paths. Covers repo dev, repo test, production layouts uniformly. Applied in schema.ts and the fixture resolver in test/schema.test.ts."
  - "asUser() dispatcher = execFile array form: prevents shell injection via catalog-entry id; mirrors plugin/lib/as_user.sh byte-for-byte for the three load-bearing flags -H -E --; returns {exitCode, stdout, stderr} rather than throwing so callers decide."
  - "STUB pattern for interface-surface plans: each subcommand file throws an Error with explicit plan-pointer ('lands in Plan 04-0X'). Downstream plans only replace function bodies; Opts shape + Commander options remain locked."
  - "Biome check auto-write normalization: when pre-commit biome normalizes single→double quotes + import ordering, adjust downstream verification greps to match the normalized form. Future phases' plans that grep for single-quoted flag strings must accept biome-normalized double-quoted variants."
  - "Comments must avoid forbidden grep substrings (Plan 02-04 precedent extended): guard/user.ts rephrased 'process.env.USER' to 'environment-variable lookup of the invoking account' to stay clear of the plan's `! grep -q 'process.env.USER'` verify chain."

requirements-completed: [CLI-01, CAT-03, CAT-04]

# Metrics
duration: 11 min
completed: 2026-04-19
---

# Phase 4 Plan 01: CLI Scaffold + Ajv Catalog Validator + Interface Surface Summary

**TypeScript CLI foundation with Ajv 2020-12 catalog validator, Commander.js bootstrap, and the full interface surface (types/guard/sentinel/dispatcher/classifier/loader) that Plans 04-03/04/05 will implement against — 26 unit tests green on a compile-first test harness.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-04-19T10:28:49Z
- **Completed:** 2026-04-19T10:39:53Z
- **Tasks:** 3 (all `type="auto" tdd="true"`)
- **Commits:** 3 atomic task commits
- **Files created:** 15 (13 source/test/config + 1 pnpm-lock.yaml + 1 tsconfig.test.json)
- **Files modified:** 5 (package.json, tsconfig.json, schema.json, validate-catalog.mjs, .gitignore)

## Accomplishments

- **CAT-03 schema contract locked:** plugin/catalog/schema.json is now JSON Schema 2020-12 with `pinned_version` + `install_recipe_path` + `uninstall_recipe_path` + `source_kind` all required, `additionalProperties:false` at both levels (schema injection defense), `allOf/if/then` conditional for `npm_package_name` when `source_kind=npm`. Recipe paths carry `^[a-z0-9_./-]+\.sh$` pattern blocking `..` traversal.
- **CAT-04 pinned_version enforced:** schema pattern `^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$` accepts full semver incl. pre-release + build metadata; rejected by ajv at both runtime (loader) and pre-commit-time (scripts/validate-catalog.mjs).
- **CLI-01 scaffolding complete:** `dist/index.js` builds with `#!/usr/bin/env node` shebang + 0755 mode; `node dist/index.js --version` prints `0.3.0`; `--help` lists all five subcommands (list/install/remove/upgrade/pin); `preAction` hook registered calling `guardAgentUser()` (CLI-05 fail-fast at exit 64 for non-agent invoker).
- **Interface surface for Plans 04-03/04/05:** types.ts exports CatalogEntry/Catalog/Sentinel/VersionDecision/Status; sentinel.ts + dispatcher.ts + classify.ts + loader.ts + guard/user.ts are all wired with documented invariants. Downstream plans need not re-discover anything.
- **Test coverage:** 26/26 green (6 schema ajv + 12 classify + 8 sentinel). Compile-first harness (tsc → dist-test → node --test) compatible with both Node 20 LTS (executor) and Node 22 LTS (target).

## Task Commits

1. **Task 1: Package deps + tsconfig + schema extension + ajv validator** — `de86015` (feat)
2. **Task 2: Interface surface — types/guard/sentinel/dispatcher/classifier/loader** — `fa522a6` (feat)
3. **Task 3: Commander entrypoint + five subcommand STUBS + classify/sentinel unit tests** — `e0469e8` (feat)

## Files Created/Modified

### Created

| Path | Purpose |
|------|---------|
| `plugin/cli/src/types.ts` | Shared interface contracts — CatalogEntry, Catalog, Sentinel, VersionDecision, Status |
| `plugin/cli/src/catalog/schema.ts` | Ajv 2020-12 singleton + compiled validator with walk-up schema resolution |
| `plugin/cli/src/catalog/loader.ts` | loadCatalog(validate?) — reads catalog.json, ajv-validates on demand |
| `plugin/cli/src/guard/user.ts` | CLI-05 EUID guard via os.userInfo().username |
| `plugin/cli/src/state/sentinel.ts` | Per-agent sentinel read/write/list/delete with atomic rename + env test seam |
| `plugin/cli/src/state/dispatcher.ts` | asUser() mirrors plugin/lib/as_user.sh `sudo -u <u> -H -E --` via execFile |
| `plugin/cli/src/version/classify.ts` | Pure-function classifier (6 Status states) + decideVersion (3 branches) |
| `plugin/cli/src/index.ts` | Commander bootstrap + preAction hook + parseAsync + five subcommand registrations |
| `plugin/cli/src/commands/list.ts` | STUB → throws NotImplemented, points at Plan 04-03 |
| `plugin/cli/src/commands/install.ts` | STUB → throws NotImplemented, points at Plan 04-03 |
| `plugin/cli/src/commands/remove.ts` | STUB → throws NotImplemented, points at Plan 04-03 |
| `plugin/cli/src/commands/upgrade.ts` | STUB → throws NotImplemented, points at Plan 04-04 |
| `plugin/cli/src/commands/pin.ts` | STUB → throws NotImplemented, points at Plan 04-05 |
| `plugin/cli/test/schema.test.ts` | 6 ajv tests (missing pin, bad enum, valid mixed, allOf, pattern negative, pattern positive) |
| `plugin/cli/test/classify.test.ts` | 12 tests (6 Status states ×2 + 5 decideVersion branches + variants) |
| `plugin/cli/test/sentinel.test.ts` | 8 tests (read missing, roundtrip, atomic, delete idempotent, listSentinels) |
| `plugin/cli/test/fixtures/catalog-valid.json` | CAT-03 positive — mixed npm + script entries |
| `plugin/cli/test/fixtures/catalog-missing-pin.json` | CAT-04 negative — missing pinned_version |
| `plugin/cli/test/fixtures/catalog-bad-source-kind.json` | CAT-03 negative — source_kind='apt' |
| `plugin/cli/tsconfig.test.json` | Compile-first test target (rootDir:., outDir:dist-test) |
| `plugin/cli/pnpm-lock.yaml` | First lockfile — pins commander@12.1.0, ajv@8.18.0, ajv-formats@3.0.1, semver@7.7.4 |

### Modified

| Path | Change |
|------|--------|
| `plugin/cli/package.json` | Added deps (ajv^8.17.0, ajv-formats^3.0.1, semver^7.7.0); devDeps (@types/node^22, @types/semver^7.5); bin.agentlinux; test+check scripts |
| `plugin/cli/tsconfig.json` | Added types:[node]; allowImportingTsExtensions:false; declaration:false; sourceMap:false; explicit include:src/**/*.ts |
| `plugin/catalog/schema.json` | Replaced Phase 1 stub with 2020-12 schema per ADR-011 — required pinned_version + install/uninstall_recipe_path + source_kind; allOf/if/then for npm_package_name; pattern for recipe_path blocks traversal |
| `plugin/cli/scripts/validate-catalog.mjs` | Replaced zero-dep Phase 1 scaffold with ajv-driven; dynamic import keeps graceful-fail if node_modules absent |
| `.gitignore` | Added plugin/cli/dist/ + plugin/cli/dist-test/ (tsc build artefacts) |

## Decisions Made

Key decisions (all captured in frontmatter `key-decisions`):

- **Compile-first test strategy** — Node 20.20.1 on executor host lacks `--experimental-strip-types`; chose `tsc -p tsconfig.test.json && node --test dist-test/test/` over adding `tsx` or `ts-node` dev-dep (CONTEXT locks minimum deps). Future executor hosts running Node 22+ can opt-in to `--experimental-strip-types` without changing the source tree.

- **strictRequired:false Ajv option** — 2020-12 schema's `allOf/then/required: [npm_package_name]` would trigger `strictRequired` error because `npm_package_name` is declared on the parent `$defs/agent` properties, not inside the `then` clause. Duplicating the property definition into the `then` clause would violate DRY for no semantic gain. Turned off ONLY strictRequired; other strict checks (unknown keywords, strict types, additionalProperties:false, strict mode defaults) stay on.

- **CJS-interop namespace import bridge** — under TypeScript 5.x with `moduleResolution: NodeNext`, `import Ajv2020 from 'ajv/dist/2020.js'` fails at compile time with "This expression is not constructable" despite ajv's `export default`. The fix is `import * as mod from 'ajv/dist/2020.js'` then `const Ajv2020 = (mod as any).default ?? (mod as any).Ajv2020 ?? mod`. Portable across TS minors.

- **Walk-up schema path resolution** — instead of hardcoding `join(HERE, '..', '..', '..', 'catalog')` which breaks across three build layouts (dev dist/, test dist-test/src/, production /opt/agentlinux/), the schema loader walks depths 2-6 looking for `catalog/schema.json` or `plugin/catalog/schema.json`. Env override `AGENTLINUX_CATALOG_DIR` takes precedence. Same pattern mirrored in `test/schema.test.ts` for fixture resolution.

- **No flock, atomic rename only** — per 04-RESEARCH §Pattern 5 the interactive-user workflow races are cross-agent (different files), not same-agent. rename(2) is POSIX-atomic on same FS. Deferred flock to if/when Phase 5+ introduces automated-loop callers.

- **Five subcommand STUBs** — preserves the Commander.js option-flag surface (`--force`, `--version <semver>`, `--include-test`, `--reset-all-curated`, etc.) so downstream plans only replace function bodies. Each stub throws an Error with explicit plan-pointer ("lands in Plan 04-03"), so invocation shows exactly which plan is missing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Ajv strict mode rejects parent-scope required property reference**
- **Found during:** Task 1 (ajv validator unit tests)
- **Issue:** Ajv 2020's `strict: true` flags `allOf/then: {required: [npm_package_name]}` because `npm_package_name` is declared on `$defs/agent/properties`, not inside the `then` clause. All six schema tests failed with `strict mode: required property "npm_package_name" is not defined at "$defs/agent/allOf/0/then"`.
- **Fix:** Added `strictRequired: false` to the Ajv2020 constructor in BOTH `src/catalog/schema.ts` and `scripts/validate-catalog.mjs`. Other strict checks (unknown keywords, strict types) stay on. Schema remains correct; this is a pure strict-mode false-positive.
- **Files modified:** plugin/cli/src/catalog/schema.ts, plugin/cli/scripts/validate-catalog.mjs
- **Verification:** 6/6 schema tests pass after the change.
- **Committed in:** de86015 (Task 1)

**2. [Rule 1 - Bug] TypeScript import of ajv/dist/2020.js rejected under NodeNext + esModuleInterop**
- **Found during:** Task 1 (first `pnpm run build` after creating schema.ts)
- **Issue:** `import Ajv2020 from 'ajv/dist/2020.js'` failed tsc with "This expression is not constructable — Type '...' has no construct signatures." Same issue with `import addFormats from 'ajv-formats'`. The cause is a TS 5.x interaction with CJS `export default` resolved under NodeNext.
- **Fix:** Used namespace import + runtime interop bridge: `import * as AjvModule from 'ajv/dist/2020.js'; const Ajv2020: any = (AjvModule as any).default ?? (AjvModule as any).Ajv2020 ?? AjvModule;`. Similar for ajv-formats. Two `biome-ignore lint/suspicious/noExplicitAny` comments document the CJS-interop bridge.
- **Files modified:** plugin/cli/src/catalog/schema.ts
- **Verification:** tsc --noEmit clean; runtime tests green.
- **Committed in:** de86015 (Task 1)

**3. [Rule 3 - Blocking] Build script tried to chmod dist/index.js before Task 3 shipped it**
- **Found during:** Task 1 (first `pnpm run build` after creating package.json)
- **Issue:** Plan 04-01's `build: "tsc && chmod 0755 dist/index.js"` fails because Task 1 only creates src/catalog/schema.ts; dist/index.js doesn't exist until Task 3. Plan body itself acknowledges this in Step 2 but didn't adjust the script.
- **Fix:** Build script changed to `"tsc && ([ -f dist/index.js ] && chmod 0755 dist/index.js || true)"` — guards the chmod with existence check. Once Task 3 ships src/index.ts the chmod fires. Still idempotent on re-build.
- **Files modified:** plugin/cli/package.json
- **Verification:** pnpm run build passes all three tasks (Task 1 skips chmod; Tasks 2-3 apply it).
- **Committed in:** de86015 (Task 1)

**4. [Rule 3 - Blocking] Plan's `node --test "glob"` pattern does not expand on Node 20**
- **Found during:** Task 1 (first `pnpm test` after creating schema.test.ts)
- **Issue:** Plan's `node --test --experimental-test-coverage "dist-test/test/**/*.test.js"` passed the literal glob string as a filename, yielding "Could not find '.../dist-test/test/**/*.test.js'". Node 20's `--test` expects individual file paths or directory arguments; it does not glob-expand.
- **Fix:** Changed test script to `node --test dist-test/test/` — directory form which Node 20+ recursively loads. Also dropped `--experimental-test-coverage` to keep the script stable across Node 20/22; coverage reports are a future Phase 6 concern.
- **Files modified:** plugin/cli/package.json
- **Verification:** All 26 tests discovered and green.
- **Committed in:** de86015 (Task 1)

**5. [Rule 3 - Blocking] tsc does not copy .json fixtures to dist-test/**
- **Found during:** Task 1 (schema tests ran but couldn't find fixtures)
- **Issue:** Test built to `dist-test/test/schema.test.js` tried `readFile(join(HERE, 'fixtures', 'catalog-valid.json'))` → ENOENT because tsc only emits .js for .ts sources; .json fixtures stay in source tree.
- **Fix:** Added `resolveFixturesDir()` in test/schema.test.ts that walks up from the compiled file's dir looking for `test/fixtures/` (or `plugin/cli/test/fixtures/`). Works from both source-tree and compiled-tree cwds.
- **Files modified:** plugin/cli/test/schema.test.ts
- **Verification:** All 6 fixture-loading tests green.
- **Committed in:** de86015 (Task 1)

**6. [Rule 2 - Missing Critical] .gitignore missing plugin/cli/dist* entries**
- **Found during:** Task 1 (pre-commit-time git status review)
- **Issue:** Project's .gitignore covered `node_modules/` but not the newly-introduced `plugin/cli/dist/` and `plugin/cli/dist-test/` build artefacts. Shipping compiled .js into git would violate the v0.3.0 convention (HARNESS.md doesn't declare any vendored binaries for plugin/cli/).
- **Fix:** Added `plugin/cli/dist/` + `plugin/cli/dist-test/` to .gitignore with a comment naming them as "TypeScript build output + test-build tree (tsc emits, not checked in)".
- **Files modified:** .gitignore
- **Verification:** `git status --short` shows neither dist/ nor dist-test/ as tracked; pnpm-lock.yaml IS tracked (reproducible-install convention).
- **Committed in:** de86015 (Task 1)

**7. [Rule 1 - Bug] Biome lint forbids non-null `!` assertion in sentinel.test.ts**
- **Found during:** Task 3 (biome check after writing tests)
- **Issue:** Two `process.env.AGENTLINUX_STATE_DIR!` non-null assertions in sentinel.test.ts triggered `lint/style/noNonNullAssertion` (biome recommended default).
- **Fix:** Replaced `!` assertion with `?? ""` fallback. Semantically equivalent because the `before()` hook unconditionally sets the env var; no runtime difference.
- **Files modified:** plugin/cli/test/sentinel.test.ts
- **Verification:** biome check clean; 8/8 sentinel tests still pass.
- **Committed in:** e0469e8 (Task 3)

**8. [Plan 02-04 precedent] Rephrased comment to avoid plan's forbidden grep substring**
- **Found during:** Task 2 (keystone invariant verification)
- **Issue:** Plan's verify chain `! grep -Fq 'process.env.USER' plugin/cli/src/guard/user.ts` matched a comment that read "— NOT process.env.USER (spoofable per ...)". Positive-verify chain treats forbidden substrings as forbidden anywhere in source, including documentation comments (established precedent: Plan 02-04 `sudoers.d` / `/usr/local/bin/`, Plan 03-01 `set -euo pipefail` / `echo >>`).
- **Fix:** Rephrased the comment to "intentionally avoids the environment-variable lookup of the invoking account because that value is caller-controlled and spoofable". Semantic invariant identical; just doesn't contain the literal grep substring.
- **Files modified:** plugin/cli/src/guard/user.ts
- **Verification:** Grep returns no match; the guard's runtime behavior is unchanged.
- **Committed in:** fa522a6 (Task 2)

### Plan-body deviations (documented, not bugs)

- **Test count 26 > plan's 20.** Plan expected 6+9+5=20; delivered 6+12+8=26. Extra tests cheap to write and add useful coverage (not-installed ×2 variants, override-override edge case, dir-missing-vs-file-missing for sentinel, list-empty-vs-list-populated). No cost in runtime (~450ms total).
- **Build script guards chmod on dist/index.js.** Per deviation #3 above — plan's literal script fails Task 1 in isolation.
- **Test script uses directory form `node --test dist-test/test/` instead of glob pattern.** Per deviation #4 above — plan's literal pattern doesn't work on Node 20.
- **loader.ts filename.** Plan's frontmatter `files_modified` (line 71-72) says `plugin/cli/src/catalog/loader.ts` but 04-RESEARCH §Component Responsibilities line 316 says `load.ts`. Honored the frontmatter + `export loadCatalog`.
- **Biome auto-formatting applied during Task 1.** Biome's `--write` normalized single-quotes → double-quotes and sorted imports alphabetically in schema.ts, validate-catalog.mjs, and schema.test.ts. Verification greps in later tasks adjusted to match (e.g., keystone-flags check uses `"-H", "-E", "--"` double-quoted form, not plan's `'-H', '-E', '--'` single-quoted).

**Total deviations:** 8 auto-fixed (2 bugs, 2 missing-critical/rephrase, 4 blocking) + 5 plan-body deviations (cosmetic/defensive).
**Impact on plan:** All auto-fixes necessary for correctness (ajv strict-mode false-positive, TS 5.x CJS interop, Node 20 test runner) or hygiene (gitignore, biome-clean). No scope creep. Plan-body deviations are either stricter coverage (more tests) or necessary adjustments for the executor environment (Node 20 vs Node 22 target).

## Issues Encountered

- **Executor host Node is 20.20.1, not 22.** Target runtime is Node 22 LTS (installed by Phase 3 provisioner). Chose compile-first test harness to stay compatible with both. Future Phase 4 executor work can opt into `--experimental-strip-types` when the executor image gets Node 22.

- **First build failed on TypeScript + ajv CJS interop.** Resolved via namespace-import bridge (decision #3). Documented with two `biome-ignore lint/suspicious/noExplicitAny` comments so future readers know why.

- **Ajv strict mode false-positive on schema.** Resolved via `strictRequired: false` (decision #2). Schema itself is correct JSON Schema 2020-12; the relax is in the validator configuration, not in the schema contract.

## Review Loop

Applied inline per Phase 2/3 precedent (project's subagent-spawn mechanism is not available in the sequential-executor context; rubrics applied directly against each file):

### Task 1 — Package/tsconfig/schema/validator

- **node-engineer rubric:** ajv/dist/2020.js explicit extension ✓ (Pitfall 1 mitigation); allErrors:true for UX; async discipline in getValidator(); @types/node pinned; `types: ["node"]` in tsconfig for clean type resolution. NB: CJS-interop bridge added as fix.
- **security-engineer rubric:** additionalProperties:false at both root + agent levels blocks schema injection; pinned_version regex bounded (no ReDoS); install_recipe_path pattern blocks `..` traversal; no eval; no dynamic require; ajv `strict:true` (minus strictRequired) maintained.
- **qa-engineer rubric:** 6 schema tests cover positive + negative + boundary (pre-release + build metadata); fixtures minimal and focused; schema tests explicitly both accept AND reject.
- **catalog-auditor rubric:** CAT-02 test_only boolean present with default false; CAT-03 schema authoritative (ajv is the only validator); CAT-04 pinned_version required for every entry.

### Task 2 — Interface surface

- **node-engineer rubric:** .js extensions on relative imports under NodeNext ✓; execFile array form in dispatcher (not exec shell-string); async/await discipline; error handling on execFile rejection preserves {exitCode, stdout, stderr} rather than throwing; semver default-import under esModuleInterop works.
- **security-engineer rubric:** execFile prevents shell injection via catalog-entry id; no eval; no dynamic require; AGENTLINUX_STATE_DIR env trust boundary safe (only writable by agent user); userInfo() backed by geteuid() is not caller-controlled; forbidden-substring rephrase applied to guard/user.ts comment.
- **qa-engineer rubric:** pure classifier easily unit-testable (I/O-free); sentinel atomic-rename visible (tmp + rename); guard exits 64; dispatcher returns structured result not throws.

### Task 3 — Commander + stubs + unit tests

- **node-engineer rubric:** parseAsync awaited at top level (Pitfall 3); preAction hook signature matches Commander v12; subcommand stubs throw clearly; .js extensions correct.
- **security-engineer rubric:** preAction is blocking (guardAgentUser exit 64 → action never fires); stubs emit plan-pointer errors (no silent no-ops that mask missing functionality); no privilege-escalation paths introduced.
- **qa-engineer rubric:** every Status has ≥1 classify @test; decideVersion covers all 3 branches + 2 edge cases; sentinel atomic assertion robust via `.tmp.<pid>` glob scan on post-write directory read.

**Iterations:** 1 pass per task (plus the Rule 1/3 auto-fixes documented in Deviations above). No outstanding actionable findings.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Plan 04-02 (catalog entries + recipes) unblocked with:
- Authoritative JSON Schema contract in `plugin/catalog/schema.json` (catalog.json author can run `pnpm exec node plugin/cli/scripts/validate-catalog.mjs` to validate before commit).
- Ajv pre-commit wrapper at `plugin/cli/scripts/validate-catalog.mjs` ready to gate catalog.json changes.
- `source_kind: npm | script` + `npm_package_name` required-when-npm + `pinned_version` semver contract all enforced by schema.

Plan 04-03 (list/install/remove) unblocked with:
- `plugin/cli/src/types.ts` exporting CatalogEntry, Catalog, Sentinel, VersionDecision, Status.
- `loadCatalog()` ready to import + consume; default validate:true with opt-out.
- `readSentinel/writeSentinel/deleteSentinel/listSentinels` ready; atomic; AGENTLINUX_STATE_DIR env seam for unit tests.
- `asUser()` ready; byte-for-byte mirrors plugin/lib/as_user.sh; execFile array form.
- `guardAgentUser()` registered via preAction hook — subcommand bodies run only as agent user.
- Subcommand stubs document expected option-flag shape (`--force`, `--version`, `--include-test`).

Plan 04-04 (upgrade) unblocked with:
- `classify()` + `decideVersion()` pure-function contracts — 12 unit tests prove correctness.
- Commander.js upgrade subcommand registered with all flags (`--reset-all-curated`, `--respect-overrides`, `--all-latest`, `--check-upstream`).

Plan 04-05 (pin) unblocked with:
- Sentinel `sticky` + `source` fields defined in types.ts.
- pin subcommand registered; pinCmd stub points at Plan 04-05.

Plan 04-06 (50-registry-cli.sh provisioner) unblocked with:
- `dist/index.js` shipped with `#!/usr/bin/env node` shebang + 0755 mode — symlink target from /home/agent/.npm-global/bin/agentlinux.
- pnpm-lock.yaml in place — Phase 6 CI will install `--frozen-lockfile`.

Plan 04-07 (bats tests) unblocked with:
- CLI-01 sanity test path: `agentlinux --version` prints 0.3.0.
- CLI-05 guard test path: non-agent invocation exits 64 with clear message.

**No blockers or concerns.**

## Self-Check: PASSED

- Commits verified: de86015, fa522a6, e0469e8 all in `git log --oneline`.
- Files created verified (15 new): all present on disk.
- Files modified verified (5): all show `M` in pre-commit git status.
- Tests verified: 26/26 green on final run.
- Build verified: dist/index.js present, 0755, shebang intact, --version prints 0.3.0, --help lists 5 subcommands.
- Harness verified: `bash tests/harness/run.sh` still 104/104 green.

---
*Phase: 04-registry-cli-catalog-uninstall*
*Completed: 2026-04-19*
