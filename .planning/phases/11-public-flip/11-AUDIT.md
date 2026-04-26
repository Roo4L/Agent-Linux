---
phase: 11
phase_name: Public Visibility Flip & Smoke Test
milestone: v0.4.0
status: stopped_for_maintainer_signoff
gate: BLOCKED-on-PUB-01-signoff
date: 2026-04-26
---

# Phase 11 Audit — Public Visibility Flip & Smoke Test

## Headline

Phase 11 is the trigger pull. PUB-01 (pre-flight checklist) is fully prepared; every Phase 7-10 deliverable is checked off with concrete artifact links. **Two maintainer-action items from Phase 10 (CIPUB-03 branch protection apply + CIPUB-04 workflow_dispatch smoke) gate PUB-02.** PUB-02 (visibility flip) is itself a maintainer action — autonomous mode does not flip the repository's visibility for the same reason it doesn't apply branch protection: high-blast-radius, one-way collaboration configuration. PUB-03 (post-flip smoke) and PUB-04 (release notes) execute after the flip and close the milestone.

## Coverage table (current state)

| Req | Description | Status |
|-----|-------------|--------|
| PUB-01 | Pre-flight checklist signed off referencing every Phase 7-10 artifact | ⏳ Awaiting maintainer sign-off — checklist body fully prepared at [`docs/audits/v0.4.0/PUB-01-preflight-checklist.md`](../../../docs/audits/v0.4.0/PUB-01-preflight-checklist.md); 13 of 17 items already evidenced; 2 items (CIPUB-03, CIPUB-04) close on staged maintainer commands; 2 decision points documented for maintainer (branch-protection timing + public install URL choice) |
| PUB-02 | Repository visibility flipped to public via `gh repo edit … --visibility public` | ⛔ MAINTAINER TASK — explicit one-way checkpoint per `/gsd-autonomous` invocation note |
| PUB-03 | Post-flip smoke: anonymous clone + `curl \| bash` install path against v0.3.0 release tag | 📅 Post-flip — runs after PUB-02 (also depends on the v0.3.0-rc1 → v0.3.0 final tag-push shipping event for the curl-installer to have a release to fetch) |
| PUB-04 | First public release notes browsable | 📅 Post-flip — natural follow-on to PUB-03 |

## Files added/changed

| Path | Change | Notes |
|------|--------|-------|
| `docs/audits/v0.4.0/PUB-01-preflight-checklist.md` | NEW | Full pre-flight checklist with every Phase 7-10 artifact link, sign-off section, decision points, and post-sign-off command sequence |
| `.planning/phases/11-public-flip/11-AUDIT.md` | NEW | This file — current Phase 11 status and what's blocking |

## What's been deliberately NOT done

- **PUB-02 not executed.** The visibility flip is the milestone's shipping event and is the explicit maintainer-checkpoint per `/gsd-autonomous` invocation. No agent-driven `gh repo edit --visibility public` will ride this branch.
- **No tag pushed.** v0.3.0-rc1 (the v0.3.0 milestone's shipping event) is a separate concern; v0.4.0 (this milestone) ships *as the visibility flip itself* — no new tag required for v0.4.0. The maintainer may choose to cut a v0.3.0 release first, then flip — that ordering decision is recorded in PUB-01 §"Decision points still owed to maintainer".

## Hand-off to maintainer

Three things the maintainer does, in order:

1. **Apply branch protection** per `docs/audits/v0.4.0/CIPUB-03-branch-protection.md` (Option B before this branch merges; or Option A after).
2. **Smoke-run workflows** per `docs/audits/v0.4.0/CIPUB-04-workflow-smoke.md` (`gh workflow run …`); capture URLs in a follow-up `CIPUB-04-runs.md`.
3. **Sign off PUB-01** by editing `docs/audits/v0.4.0/PUB-01-preflight-checklist.md` §"Sign-off" with their name + date + the captured artifacts.

Then the maintainer flips visibility:

```bash
gh repo edit Roo4L/Agent-Linux --visibility public --accept-visibility-change-consequences
```

And runs the post-flip smoke:

```bash
mkdir /tmp/postflip-smoke && cd /tmp/postflip-smoke
git clone https://github.com/Roo4L/Agent-Linux.git
# (After the v0.3.0 release tag publishes:)
curl -fsSL https://agentlinux.org/install.sh | sudo bash
agentlinux list && agentlinux install claude-code && claude --version
# Capture the transcript in docs/audits/v0.4.0/PUB-03-postflip-smoke.md
```

After that, PUB-04 is a one-line release note (or a short README addition) pointing at LICENSE + CONTRIBUTING.md + the curated combos.

## Phase-close gate (current)

GATE: **BLOCKED-on-PUB-01-signoff** (intentional). Once the maintainer signs off PUB-01 and executes PUB-02 + PUB-03 + PUB-04, this AUDIT.md will be amended to GATE: GREEN and the milestone is ready for `/gsd-complete-milestone v0.4.0`.

## Why this is the right place to stop

`/gsd-autonomous` was invoked with the explicit note: `Phase 11 (visibility flip) is a checkpoint:human-verify task — stop before flipping and request maintainer sign-off via comment.` This audit document is that checkpoint, with all the work it can lean on (Phases 7-10) already committed to the branch and ready for review.
