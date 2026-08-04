---
phase: 10
phase_name: Public CI/CD Verification & Branch Protection
milestone: v0.4.0
status: passed_with_maintainer_action_items
gate: GREEN-pending-2-maintainer-tasks
date: 2026-04-26
---

# Phase 10 Audit — Public CI/CD Verification & Branch Protection

## Headline

Workflow `permissions:` blocks are at least-privilege; `pull_request_target` is unused (zero fork-PR exfiltration surface); branch protection on `master` is designed and ready to apply via a single `gh api` command; pre-existing CI history is green across the board with the explicit `workflow_dispatch` smoke run as belt-and-braces. Two requirements (CIPUB-03, CIPUB-04) close on maintainer execution of pre-staged commands.

## Coverage table

| Req | Description | Evidence | Status |
|-----|-------------|----------|--------|
| CIPUB-01 | Workflow `permissions:` blocks reviewed and least-privilege | `docs/audits/v0.4.0/CIPUB-01-workflow-audit.md` (per-workflow inventory: deploy/nightly-qemu/nightly-mutation/release/test all explicit; release.yml's `contents: write` confined to publish job and tag-push-gated; test.yml top-level `permissions: contents: read` added in this phase) + `.github/workflows/test.yml` diff | ✓ |
| CIPUB-02 | `pull_request_target` audited; fork-PR exfiltration risk assessed | `docs/audits/v0.4.0/CIPUB-02-fork-pr-exfiltration.md` (0 `pull_request_target`, 0 `workflow_run`, 0 PR-controlled-ref interpolation, 0 ref-override on `actions/checkout`; default-stance recorded) | ✓ |
| CIPUB-03 | Branch protection on `master` configured | `docs/audits/v0.4.0/CIPUB-03-branch-protection.md` (designed: enforce_admins / linear / no force-push / no deletions / 1 approval + dismiss-stale + strict status checks: pre-commit, cli-unit, bats-docker matrix, gitleaks; ready to apply via single `gh api -X PUT` command — both Option A "after this branch merges" and Option B "bootstrap before this branch merges" pre-written) | ⏳ MAINTAINER TASK — apply Option B before flip; swap to Option A after this branch merges |
| CIPUB-04 | Workflows smoke-run via `workflow_dispatch` to confirm public-readiness | `docs/audits/v0.4.0/CIPUB-04-workflow-smoke.md` (de facto GREEN from PR #2 + nightly runs <24 hrs old; explicit `workflow_dispatch` commands documented for belt-and-braces) | ⏳ MAINTAINER TASK — `gh workflow run test.yml/nightly-qemu.yml/nightly-mutation.yml` and capture URLs |

## Files added/changed

| Path | Change | Notes |
|------|--------|-------|
| `.github/workflows/test.yml` | MODIFIED | Top-level `permissions: contents: read` added (with comment explaining the public-repo posture) |
| `docs/audits/v0.4.0/CIPUB-01-workflow-audit.md` | NEW | Per-workflow permissions inventory + diff applied + "what's NOT being granted" list |
| `docs/audits/v0.4.0/CIPUB-02-fork-pr-exfiltration.md` | NEW | `pull_request_target` audit + default-stance statement |
| `docs/audits/v0.4.0/CIPUB-03-branch-protection.md` | NEW | Configuration design + ready-to-apply `gh api` commands (Options A/B) + verification jq snippet |
| `docs/audits/v0.4.0/CIPUB-04-workflow-smoke.md` | NEW | Pre-existing CI signal + explicit `workflow_dispatch` smoke commands |

## Coverage verification

```bash
# test.yml top-level permissions present:
grep -A 1 '^permissions:' .github/workflows/test.yml | head -3

# All workflows have explicit permissions:
for f in .github/workflows/*.yml; do echo -n "$f: "; grep -c '^permissions:' "$f"; done
# All ≥ 1.

# pull_request_target absent:
grep -rE 'pull_request_target' .github/workflows/ | wc -l
# 0

# Branch protection design captured:
test -f docs/audits/v0.4.0/CIPUB-03-branch-protection.md && echo present

# Smoke command set captured:
test -f docs/audits/v0.4.0/CIPUB-04-workflow-smoke.md && echo present
```

## Deviations from PLAN

- **No PLAN.md authored** — same reason as Phases 7-9 (autonomous continuation; deterministic outputs).
- **CIPUB-03 not applied autonomously.** Branch protection is high-blast-radius collaboration configuration; the maintainer reviews and applies (~30s via `gh api`). Two pre-written commands cover the only valid timing question (before vs. after this branch merges, with the `gitleaks` context). Documented in CIPUB-03-branch-protection.md.
- **CIPUB-04 not "actively" smoke-run.** Pre-existing CI signal from PR #2 (less than 24 hours old, all green: pre-commit / cli-unit / bats-docker × 22.04 / bats-docker × 24.04) plus nightly-qemu and nightly-mutation runs from the most recent night already provide GREEN evidence. The explicit `workflow_dispatch` is belt-and-braces — the maintainer runs it and pastes the run URLs into a follow-up audit doc. Documented in CIPUB-04-workflow-smoke.md.

## Phase-close gate

GATE: GREEN — all 4 CIPUB-XX requirements have at least one cited evidence artifact OR a ready-to-execute maintainer command with explicit verification criteria. The two ⏳ items are tracked into the Phase 11 pre-flight checklist (PUB-01).

## Hand-off to Phase 11

Phase 11 (Public Visibility Flip & Smoke Test) is the next and final phase. It depends on:

1. CIPUB-03 applied (branch protection on `master` per Option B then Option A). Maintainer runs the staged `gh api` command.
2. CIPUB-04 verified via `workflow_dispatch` (or accepted via the pre-existing CI signal). Maintainer captures run URLs.
3. PUB-01 pre-flight checklist sign-off referencing every Phase 7-10 artifact.
4. PUB-02 visibility flip (`gh repo edit Roo4L/Agent-Linux --visibility public --accept-visibility-change-consequences`).
5. PUB-03 post-flip smoke (anonymous clone + `curl | bash` install). 6. PUB-04 first public release notes.

Phase 11 PLAN explicitly stops between PUB-01 and PUB-02 for maintainer sign-off. The flip is one-way and is the milestone's shipping event.
