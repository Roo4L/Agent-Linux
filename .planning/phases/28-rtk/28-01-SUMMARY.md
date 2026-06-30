---
phase: 28-rtk
plan: 01
subsystem: catalog
tags: [catalog-schema, ajv, json-schema, typescript, source_kind, prebuilt-binary, enable-01]

# Dependency graph
requires:
  - phase: 04-registry-cli-catalog
    provides: ajv catalog validator (getValidator), CatalogEntry type, loader.ts pipeline
provides:
  - "source_kind enum extended with \"binary\" in schema.json (ajv source of truth)"
  - "CatalogEntry.source_kind union extended with \"binary\" in types.ts"
  - "unit coverage proving a binary entry validates + the enum advertises \"binary\""
  - "hermetic schema-test seam (AGENTLINUX_CATALOG_DIR pinned to the repo schema)"
affects: [28-02 prebuilt-binary helper, 28-03 rtk recipe + catalog entry, 28-04 bats lifecycle, 29-33 binary-kind tools]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Closed-set source_kind enum mirrored in JSON schema + TS union (single source of truth, two files kept in sync)"
    - "Binary fetch logic lives in the recipe + shared bash helper, NOT declarative schema fields (RESEARCH §Alternatives Considered)"

key-files:
  created:
    - plugin/cli/test/fixtures/catalog-binary.json
  modified:
    - plugin/catalog/schema.json
    - plugin/cli/src/types.ts
    - plugin/cli/test/schema.test.ts

key-decisions:
  - "Add \"binary\" as a third source_kind value ONLY (one-line enum edit per file); no new allOf/required clause for binary — the recipe owns all fetch/verify logic (ENABLE-01)."
  - "Schema unit test pinned to the repo's plugin/catalog/schema.json via AGENTLINUX_CATALOG_DIR so it is hermetic vs. any staged /opt/agentlinux schema on the build host."

patterns-established:
  - "Pattern: new source_kind values are a closed-set enum extension mirrored in schema.json + types.ts + a fixture-backed validator round-trip test — phases 29-33 reuse the kind with zero further CLI source edits."

requirements-completed: [ENABLE-01]

# Metrics
duration: ~20min
completed: 2026-06-30
---

# Phase 28 Plan 01: source_kind "binary" enum + unit coverage Summary

**Catalog `source_kind` enum extended to `["npm","script","binary"]` in both the ajv schema and the TypeScript `CatalogEntry` union, with a fixture-backed unit test proving a binary entry validates and that the enum negative test advertises `binary`.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-06-30T18:24Z (approx)
- **Completed:** 2026-06-30T18:40:04Z
- **Tasks:** 2
- **Files modified:** 4 (3 modified, 1 created)

## Accomplishments
- `plugin/catalog/schema.json` — `source_kind` enum is now `["npm", "script", "binary"]` (one changed line; no other schema edits, no catalog version bump).
- `plugin/cli/src/types.ts` — `CatalogEntry.source_kind` union is now `"npm" | "script" | "binary"` (project still type-checks under `tsc`).
- `plugin/cli/test/fixtures/catalog-binary.json` — well-formed `source_kind: "binary"` fixture (no `npm_package_name` — binary entries carry none).
- `plugin/cli/test/schema.test.ts` — the enum negative test now asserts `allowedValues.includes("binary")`, plus a new `accepts well-formed catalog with a binary entry` round-trip test. Schema suite green 8/8.

## Task Commits

Each task was committed atomically (hooks on — pre-commit green):

1. **Task 1: Add "binary" to the source_kind enum (schema + TS union)** - `141673b` (feat)
2. **Task 2: Unit coverage — binary entry validates + enum lists binary** - `800851f` (test)

**Plan metadata:** (docs commit — this SUMMARY + STATE + ROADMAP)

## Files Created/Modified
- `plugin/catalog/schema.json` - `source_kind` enum gains `"binary"` (ajv source of truth)
- `plugin/cli/src/types.ts` - `CatalogEntry.source_kind` union gains `"binary"`
- `plugin/cli/test/fixtures/catalog-binary.json` - new well-formed binary-kind fixture
- `plugin/cli/test/schema.test.ts` - extended enum negative test + new binary acceptance test + hermetic `AGENTLINUX_CATALOG_DIR` pin

## Decisions Made
- Kept the change minimal and declarative-free: no binary-specific `required`/`allOf` clause, no `release_repo`/`asset`/`checksum` schema fields. Per RESEARCH §Alternatives Considered, that per-tool variety lives in the recipe + shared bash helper (plan 28-02), where the bats harness exercises it — keeping CLI/TypeScript surface generic (CAT-03 spirit).
- Did NOT bump `catalog.json`/`package.json` version (version-lockstep pre-commit hook stays satisfied; this is a schema capability addition, not a catalog release).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Pinned the schema test to the repo schema (non-hermetic test environment)**
- **Found during:** Task 2 (unit coverage)
- **Issue:** `getValidator()` resolves the schema via `AGENTLINUX_CATALOG_DIR` → `/opt/agentlinux/catalog/<VERSION>/schema.json` → repo walk-up, in that order. This executor host has a leftover real AgentLinux install at `/opt/agentlinux/catalog/0.3.4/schema.json` (the old `["npm","script"]` enum), and `package.json` version is also `0.3.4`, so the schema test was silently validating the **stale staged schema** instead of the repo source of truth. The baseline suite "passed" only because it was testing the old enum; my new `binary` assertions correctly failed against it.
- **Fix:** Added a `resolveRepoCatalogDir()` walk-up in `schema.test.ts` that locates the repo's `plugin/catalog/schema.json` and sets `process.env.AGENTLINUX_CATALOG_DIR` to its dir at module load (before any `getValidator()` call). The schema suite is now hermetic regardless of any ambient `/opt/agentlinux` install — it always validates the repo schema. In Docker/CI the staged schema matches the source, so behavior is unchanged there; this only corrects a false-pass on hosts with a divergent staged copy.
- **Files modified:** plugin/cli/test/schema.test.ts
- **Verification:** `node --test dist-test/test/schema.test.js` → 8/8 green (including the new `binary` tests); `pnpm test` returns to the pre-existing baseline failure count.
- **Committed in:** `800851f` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking).
**Impact on plan:** The fix makes the schema unit test correctly test the repo schema — essential for the plan's coverage to mean anything. No scope creep (change confined to the schema test file the plan already edits).

## Deferred Issues
- **`plugin/cli/test/install.test.js` (pre-existing, out of scope):** `pnpm test` reports this file as `fail 1` even though all 14 of its individual subtests pass — a process-level `'test failed'` consistent with a real `process.exit(64)` reaching the harness from a `process.exit`-stubbing subtest. Present on the committed tree BEFORE any Plan 28-01 edit (the file is not in this plan's scope and was not modified), and runs in its own child process unaffected by my hermetic env change. Logged in `.planning/phases/28-rtk/deferred-items.md`; candidate Jira sub-task.

## Issues Encountered
- See Deviation 1 (stale staged schema shadowing the repo copy). Resolved by the hermetic `AGENTLINUX_CATALOG_DIR` pin.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ENABLE-01's schema gate is open: ajv now accepts `source_kind: "binary"` and `CatalogEntry` types it. Plan 28-02 (shared `prebuilt-binary.sh` helper) and 28-03 (rtk recipe pair + `catalog.json` entry with `source_kind: "binary"`, pin `0.42.4`) can land with no further enum/type edits.
- The rtk `catalog.json` entry added in 28-03 will be the first real catalog row exercising this enum value; the version-lockstep + ajv pre-commit hooks already validate it.

## Self-Check: PASSED

- All 4 plan files present (schema.json, types.ts, catalog-binary.json, schema.test.ts) + SUMMARY.md
- Both task commits present in git history (141673b, 800851f)

---
*Phase: 28-rtk*
*Completed: 2026-06-30*
