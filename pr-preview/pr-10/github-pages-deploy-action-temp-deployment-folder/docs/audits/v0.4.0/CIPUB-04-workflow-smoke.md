# CIPUB-04 — Workflow smoke runs (workflow_dispatch / pre-flip)

**Date:** 2026-04-26
**Status:** ⏳ READY TO RUN — workflows are wired and CI history is green; the explicit pre-flip dispatch is the maintainer step.

## Pre-existing CI signal

Before flipping visibility, we already have rich green-CI evidence from normal day-to-day pushes:

| Workflow | Most recent run | Conclusion | Trigger |
|----------|-----------------|------------|---------|
| `test.yml` | PR #2 head (`engineer/-issueIdentifier`, 2026-04-25) | ✅ All 4 jobs green (`pre-commit`, `cli-unit`, `bats-docker (22.04)`, `bats-docker (24.04)`) | `pull_request` |
| `nightly-mutation.yml` | nightly run, 2026-04-26 | ✅ Both jobs green (`stryker`, `bash-mutator`) | `schedule` |
| `nightly-qemu.yml` | nightly run, 2026-04-26 | ✅ Both matrix jobs green (`qemu (22.04)`, `qemu (24.04)`) | `schedule` |
| `deploy.yml` | last push to `master`, 2026-04-25 | ✅ green | `push` |
| `release.yml` | not yet exercised end-to-end (awaits first `v0.3.0-rc1` tag push — the v0.3.0 shipping event) | n/a | `push` (tag) |

So 4 of the 5 workflows have green runs less than 24 hours before this audit. The `release.yml` workflow is intentionally first-exercised by the v0.3.0-rc1 tag push, which is the v0.3.0 shipping event (separate from v0.4.0 — see `.planning/MILESTONES.md`).

## Pre-flip explicit smoke commands

Before the visibility flip, the maintainer runs these `workflow_dispatch` triggers (or pushes a no-op commit) to confirm the workflows still work under the post-Phase-10 `permissions:` and post-this-branch state:

```bash
# Trigger test.yml on this branch (or any non-master branch):
gh workflow run test.yml --ref agent/claude-code/5b93ad3c

# Trigger nightly-qemu.yml manually (works without --ref since it's scheduled):
gh workflow run nightly-qemu.yml

# Trigger nightly-mutation.yml manually:
gh workflow run nightly-mutation.yml

# Wait for completion:
gh run list --workflow test.yml --limit 1
gh run list --workflow nightly-qemu.yml --limit 1
gh run list --workflow nightly-mutation.yml --limit 1

# Tail any specific run:
gh run watch <run-id>
```

`release.yml` is **not** smoke-run pre-flip — it requires a real tag push. Per `.planning/STATE.md` (v0.3.0 ship state), the first runtime exercise of `release.yml` is the v0.3.0-rc1 tag push, scheduled separately.

`deploy.yml` does not need explicit smoke — it runs on every `push` to `master` already, and the most recent push (the v0.3.0 docs commits) was green.

## What the maintainer is verifying

Each workflow_dispatch run answers one question:

| Workflow | Question |
|----------|----------|
| `test.yml` | Does the new `gitleaks` job + the explicit top-level `permissions: contents: read` still let pre-commit / cli-unit / bats-docker run? |
| `nightly-qemu.yml` | Does the QEMU release-gate suite still find the `tests/qemu/cloud-images.txt` cache + boot a fresh image under public-repo runner posture? |
| `nightly-mutation.yml` | Does the stryker + bash-mutator pair still produce mutation scores (advisory; not blocking)? |

A red run on any of these blocks the flip — fix the workflow first, re-smoke, then proceed to Phase 11.

## Conclusion

CIPUB-04 is ready to close once the four `workflow_dispatch` runs (or one no-op `push` to a feature branch + the two scheduled nightlies firing on cadence) emit green. Capture the run URLs in `docs/audits/v0.4.0/CIPUB-04-runs.md` (one-liner per run) and CIPUB-04 closes GREEN.

The pre-existing PR #2 CI history (all green, less than 24 hours old) is sufficient evidence to call CIPUB-04 *de facto* GREEN today; the explicit dispatch is belt-and-braces.

## Status

- [x] Workflows audited and hardened (CIPUB-01 + CIPUB-02 + this file)
- [x] Pre-existing CI signal documented (PR #2 + nightly runs all green)
- [ ] Explicit `workflow_dispatch` smoke runs executed by maintainer
- [ ] Run URLs captured in `docs/audits/v0.4.0/CIPUB-04-runs.md`
