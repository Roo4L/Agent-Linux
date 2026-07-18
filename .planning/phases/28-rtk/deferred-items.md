# Phase 28 — Deferred / Out-of-Scope Items

## Pre-existing CLI unit-test failure (NOT caused by Plan 28-01)

- **File:** `plugin/cli/test/install.test.js`
- **Symptom:** `pnpm test` reports the `install.test.js` file as `fail 1` even
  though all 14 of its individual subtests pass (`pass 13` at the subtest level
  + the file node counts itself). The failure surfaces at the file/process
  level with `'test failed'` and no individual assertion error — consistent with
  a real `process.exit(64)` reaching the harness from one of the
  `process.exit(...)`-stubbing subtests.
- **Status at baseline:** Present on the committed tree BEFORE any Plan 28-01
  edit (the file is not in this plan's scope and was not modified). Reproduced
  by running `node --test dist-test/test/install.test.js` on a clean build.
- **Scope decision:** Out of scope for Plan 28-01 (source_kind enum + schema
  unit coverage). Not fixed here per the executor scope-boundary rule. The
  schema test file (`schema.test.ts`) — the surface this plan touches — passes
  6/6 in isolation and continues to pass after the enum change.
- **Suggested follow-up:** Triage the `install.test.js` process-level exit
  separately (likely a `mock`/`process.exit` stub leak); candidate Jira sub-task.
- **Re-confirmed in Plan 28-03 (Task 3):** Still 157 pass / 1 fail with the rtk
  `catalog.json` entry present; stashing the rtk entry yields the identical
  157 / 1, and `rtk` is absent from the committed `HEAD` catalog — so the failure
  is independent of the new binary entry. The rtk entry validates against the
  schema (ajv) and round-trips through `loadCatalog`. Left untouched.
