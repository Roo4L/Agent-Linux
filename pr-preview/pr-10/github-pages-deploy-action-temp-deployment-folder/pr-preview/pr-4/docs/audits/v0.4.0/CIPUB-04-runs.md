# CIPUB-04 — Workflow smoke run URLs

**Date:** 2026-04-26
**Triggered by:** agent (Claude Code) per maintainer authorization

## Pre-flip smoke runs (`agent/claude-code/5b93ad3c`)

| Workflow | Trigger | Run ID | URL | Status |
|----------|---------|--------|-----|--------|
| test | push (Phase 11 commit) | 24959328215 | https://github.com/Roo4L/Agent-Linux/actions/runs/24959328215 | in_progress (will be updated when complete) |
| nightly-mutation | workflow_dispatch | 24959374094 | https://github.com/Roo4L/Agent-Linux/actions/runs/24959374094 | ✅ success (26s) |
| nightly-qemu | workflow_dispatch | 24959373543 | https://github.com/Roo4L/Agent-Linux/actions/runs/24959373543 | in_progress (QEMU boot is slow) |
| test | pull_request (PR #3) | 24959386533 | https://github.com/Roo4L/Agent-Linux/actions/runs/24959386533 | in_progress |

`test.yml` does not declare `workflow_dispatch` (its triggers are `push` to non-master branches and `pull_request` to master). Both auto-fire from this branch's push and PR — the explicit-dispatch step in CIPUB-04 is satisfied by those organic triggers.

`release.yml` is not exercised here — it requires a tag push (the v0.3.0-rc1 → v0.3.0 shipping event, separate concern).

## Update protocol

Once each in-progress run completes, the conclusion is appended below. If any run fails red, the visibility flip is aborted until the workflow is fixed.

## Status

- [x] Workflows triggered
- [x] Run URLs captured (above)
- [ ] All runs completed green (in progress at audit time)
