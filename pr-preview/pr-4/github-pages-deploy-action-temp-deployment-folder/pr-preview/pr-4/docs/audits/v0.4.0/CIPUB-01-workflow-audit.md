# CIPUB-01 — Workflow `permissions:` audit

**Date:** 2026-04-26
**Status:** ✅ PASSED — every workflow has an explicit top-level `permissions:` block scoped to least-privilege; `release.yml` publish job has the only elevated grant (`contents: write`) and is gated behind `startsWith(github.ref, 'refs/tags/v')` per the existing pipeline.

## Inventory (post-Phase-10 hardening)

| Workflow | Top-level `permissions:` | Job-level escalations | Verdict |
|----------|--------------------------|------------------------|---------|
| `.github/workflows/test.yml` | `contents: read` (added in this phase) | `gitleaks` job: `contents: read` (explicit, redundant with top-level — kept for self-documentation) | ✓ Least-privilege |
| `.github/workflows/deploy.yml` | `contents: read` + `pages: write` + `id-token: write` | none | ✓ Least-privilege for Pages deploy (exact set required by `actions/configure-pages@v5` + `actions/upload-pages-artifact@v3` + `actions/deploy-pages@v4`) |
| `.github/workflows/nightly-qemu.yml` | `contents: read` | none | ✓ Least-privilege |
| `.github/workflows/nightly-mutation.yml` | `contents: read` | none | ✓ Least-privilege |
| `.github/workflows/release.yml` | `contents: read` | `publish` job only: `contents: write` (required for `softprops/action-gh-release@v2.6.2` to upload assets to the GitHub Release) | ✓ Escalation confined to a single job, gated on `startsWith(github.ref, 'refs/tags/v')` per existing pipeline (Phase 6 Plan 06-04 design lock) |

## Diff applied this phase

```diff
--- a/.github/workflows/test.yml
+++ b/.github/workflows/test.yml
@@ ...
   pull_request:
     branches: [master]
     ...
+
+# v0.4.0 CIPUB-01: explicit least-privilege default.
+permissions:
+  contents: read

 jobs:
```

The four other workflows already had explicit top-level `permissions:` blocks before this phase; only `test.yml` was running on the runner's implicit-default token (which on public repos is `read-all` for `pull_request` and broader on `push`, depending on org / repo settings — never assume).

## What's NOT being granted

Across all five workflows, none grant any of:

- `actions: write` (would let a workflow modify other workflows or cancel runs)
- `checks: write` (would let a workflow create check-run results — only relevant for review-bots)
- `deployments: write` (only `deploy.yml` would need this; it doesn't — Pages deploy uses `pages: write` + `id-token: write` instead)
- `discussions: write`, `issues: write`, `packages: write`, `pull-requests: write` (none of our workflows touch these)
- `repository-projects: write`, `security-events: write`, `statuses: write`

Anything not listed defaults to `none` once a `permissions:` block is set explicitly.

## Conclusion

Every workflow is at least-privilege. `release.yml`'s `contents: write` escalation is in the only place where it is actually required (publishing assets to a Release), confined to a single job, and tag-push-gated.

CIPUB-01 closes GREEN.
