# Roadmap: AgentLinux v0.4.0 — Open-Source Release

**Milestone:** v0.4.0 Open-Source Release
**Started:** 2026-04-26
**Triggered by:** Issue AGE-6 "Make repository public"
**Phase numbering:** Continues from v0.3.0 (last phase 6 → next phase 7). v0.3.0 phase directories under `.planning/phases/01-*..06-*` are preserved until the v0.3.0-rc1 tag push completes the v0.3.0 shipping event; v0.4.0 phases land in `.planning/phases/07-*..11-*` alongside them. Conflict-free.

## Overview

v0.4.0 takes AgentLinux from a private repository to a public one. The product does not change in this milestone — no new agents, no new distros, no new installer features. What changes is the repository's distribution model: licensing, secret-scanning hygiene, repo cleanup, public-CI/CD readiness, and the visibility flip itself.

The critical path is **license + audit-and-clean before the flip, never after**. Once the repository is public, third parties can clone or fork at any moment — re-private is not a real undo. Phases 7-10 produce the artifacts that justify Phase 11; Phase 11 is the trigger pull plus a post-flip smoke test.

Key locked decisions honored by this roadmap:
- The visibility flip (PUB-02) is treated as one-way; every preceding phase must close cleanly first.
- "Done" for secret scanning is **zero verifiable findings or every finding triaged with a documented decision**, not "we ran the scanner."
- "Done" for CI/CD readiness includes a concrete adversary check (fork-PR exfiltration audit), not a vibes-based assumption.
- Documentation evidence (`docs/audits/v0.4.0/<REQ-ID>-*.md` + ADRs) is the primary verification artifact for this milestone — most v0.4.0 work is repo-level / process-level, not behavior-level, so bats @tests are rare here. The TST-07 phase-close discipline carries over via per-phase `<phase-NN>-AUDIT.md` files that cite the evidence per requirement.
- The v0.3.0-rc1 tag push (the v0.3.0 shipping event) does **not** block v0.4.0. Phases 7-9 can run in parallel with that tag push; Phase 10 specifically depends on a green CI run that may include the rc1 push or a workflow_dispatch dry-run.

## Phases

**Phase Numbering:**
- Integer phases (7, 8, 9, 10, 11): Planned milestone work, executed in numeric order
- Decimal phases (e.g., 8.1) reserved for urgent insertions discovered during the milestone (precedent: v0.3.0 Phase 5.1)

- [x] **Phase 7: License & Public-Ready Documentation** — MIT license (ADR-013), LICENSE file, README license badge + section, SPDX headers on 16 first-party source files, CONTRIBUTING.md with DCO-equivalent affirmation. ✓ 2026-04-26 (commit `c52b3c1`; 4/4 LIC-XX evidenced; phase-close gate: GREEN; `.planning/phases/07-license-and-public-docs/07-AUDIT.md`).
- [x] **Phase 8: Secret Scanning & History Audit** — gitleaks (1 finding, triaged false positive — OpenNebula API hostname matched `generic-api-key` regex) + trufflehog (0 verified, 0 unverified) + targeted manual audit (8 patterns × 255 commits = 0 matches). SEC-04 closes as no-op (ADR-014). gitleaks gate wired in pre-commit + CI; smoke-test confirms gate fires on contrived secrets. ✓ 2026-04-26 (commit `c94920a`; 5/5 SEC-XX evidenced; phase-close gate: GREEN; `.planning/phases/08-secret-scanning/08-AUDIT.md`).
- [x] **Phase 9: Repository Hygiene & Artifact Cleanup** — 2 branches (no stale, no merged-but-unpurged); zero blobs >500 KB anywhere in history; .gitignore hardened (env/npmrc/credentials/SSH keys/editor cruft/coverage/caches with deliberate allow-lists); `.planning/` retention is deliberate per CLAUDE.md convention. ✓ 2026-04-26 (commit `158e465`; 4/4 CLEAN-XX evidenced; phase-close gate: GREEN; `.planning/phases/09-repo-hygiene/09-AUDIT.md`).
- [x] **Phase 10: Public CI/CD Verification & Branch Protection** — workflow `permissions:` blocks at least-privilege (test.yml gained explicit top-level); `pull_request_target` = 0; fork-PR exfiltration surface = empty. Branch protection on `master` designed and **staged for maintainer apply** via single `gh api -X PUT` command (CIPUB-03; Option A/B documented). CIPUB-04 de facto GREEN from PR #2 + recent nightly runs (<24h). ✓ 2026-04-26 (commit `446c89b`; 4/4 CIPUB-XX evidenced or staged; phase-close gate: GREEN-pending-2-maintainer-tasks; `.planning/phases/10-public-cicd/10-AUDIT.md`).
- [x] **Phase 11: Public Visibility Flip & Smoke Test** — Repository visibility flipped to PUBLIC at 2026-04-26T15:30Z; squash-merged as `c8a2787` on master; branch protection re-applied as Option A (enforce_admins, linear, no force-push, gitleaks status check). Public release published as **`v0.3.1 — Open-Source Flip`** (2026-05-02; the originally-tagged `v0.4.0` was renamed to `v0.3.1` for version-constant lockstep — see release notes). Post-flip smoke (anonymous clone + raw curl-installer fetch + SHA + syntax) green. End-to-end `curl … | sudo bash` install deferred to v0.3.x final-release event. ✓ shipped 2026-05-02 (commit `c8a2787`, tag `v0.3.1`; 4/4 PUB-XX evidenced; phase-close gate: GREEN; `.planning/phases/11-public-flip/11-AUDIT.md`).

## Phase Details

### Phase 7: License & Public-Ready Documentation
**Goal**: A future visitor landing on the public repo can identify the license, understand what the project is, and find a clear path to contribute — without internal-only references, TODOs blocking comprehension, or missing license metadata. The license is a deliberate decision, recorded as an ADR.
**Depends on**: Nothing (first v0.4.0 phase; can start in parallel with v0.3.0-rc1 tag push)
**Requirements**: LIC-01, LIC-02, LIC-03, LIC-04
**Success Criteria** (what must be TRUE):
  1. `LICENSE` file exists at repo root, contains the full MIT (or chosen) license text, with the correct copyright holder line and current year — LIC-01.
  2. ADR `docs/decisions/ADR-013-license-choice.md` documents WHY MIT (or alternative) was chosen — LIC-01.
  3. README has a `## License` section linking `LICENSE`; ideally a license badge near the top (`shields.io/github/license/Roo4L/Agent-Linux`) — LIC-02.
  4. README is reviewed for public-audience tone: no internal-only product names, no unredacted vendor / customer references, no `TODO` placeholders that block comprehension — LIC-02.
  5. SPDX license identifier headers (`# SPDX-License-Identifier: MIT`) added to bash entrypoints under `plugin/bin/` and TypeScript sources under `plugin/cli/src/`. A repo-wide grep verifies coverage on *new* files; existing-file backfill policy is documented in ADR-013 — LIC-03.
  6. `CONTRIBUTING.md` exists at repo root (or `.github/`), links to `docs/HARNESS.md` for the review-loop conventions, and explains how to file issues, run the test harness locally, and what reviewers check — LIC-04.
  7. Phase-close audit `docs/audits/v0.4.0/PHASE-07-AUDIT.md` (or `.planning/phases/07-license-and-docs/07-AUDIT.md`) cites the file path / line range for every LIC-XX requirement; gate emits GREEN.
**Plans**: estimated 2 plans
- [ ] 07-01-PLAN.md — License pick (ADR-013) + LICENSE file + README license section/badge + SPDX header convention applied to new files (LIC-01, LIC-02, LIC-03)
- [ ] 07-02-PLAN.md — CONTRIBUTING.md + README public-audience tone pass + Phase 7 AUDIT (LIC-02 close, LIC-04, phase-close gate)

### Phase 8: Secret Scanning & History Audit
**Goal**: After this phase, no verified secret remains in git history; any secret that did leak is rotated upstream and a remediation decision is on record; and a scanner gate is active to prevent re-introduction.
**Depends on**: Phase 7 (avoids racing license content into history while we're rewriting it)
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, SEC-05
**Success Criteria** (what must be TRUE):
  1. `gitleaks detect --no-banner --redact --source . --log-opts="--all"` exit 0 OR every finding triaged in `docs/audits/v0.4.0/SEC-01-gitleaks-report.md` — SEC-01.
  2. `trufflehog git file://. --since-commit=$(git rev-list --max-parents=0 HEAD) --only-verified` reports zero verified findings OR every verified finding triaged in `docs/audits/v0.4.0/SEC-02-trufflehog-report.md` — SEC-02.
  3. Targeted manual audit (Buttondown tokens, GitHub / Anthropic / npm credentials, `.env`/`.npmrc`/`.git-credentials`/SSH artifacts, `Authorization: Bearer ...` strings) is run and documented in `docs/audits/v0.4.0/SEC-03-targeted-audit.md` — SEC-03.
  4. For every real secret found: rotated upstream + remediation decision (rotate vs. history rewrite) recorded in ADR-014. Default: rotate-only unless the secret grants ongoing access that cannot be revoked — SEC-04.
  5. Pre-commit hook OR a `.github/workflows/test.yml` step runs gitleaks on every PR; verified to fire on a contrived test commit (evidence committed to audit) — SEC-05.
  6. Phase-close audit `docs/audits/v0.4.0/PHASE-08-AUDIT.md` cites every SEC-XX evidence; gate emits GREEN.
**Plans**: estimated 3 plans
- [ ] 08-01-PLAN.md — Run gitleaks + trufflehog + targeted manual audit; produce SEC-01/02/03 report files (SEC-01, SEC-02, SEC-03)
- [ ] 08-02-PLAN.md — Triage findings; rotate any real secrets upstream; ADR-014 remediation decision; (optional) `git filter-repo` rewrite if severity demands (SEC-04)
- [ ] 08-03-PLAN.md — Wire gitleaks gate into pre-commit + CI; smoke-test the gate fires on a contrived secret-shaped commit; Phase 8 AUDIT (SEC-05, phase-close gate)

### Phase 9: Repository Hygiene & Artifact Cleanup
**Goal**: A future contributor cloning the repo gets only what they need — no stale branches confusing the dev surface, no >1MB files bloating history that aren't legitimate release artifacts, no editor / OS / build-output cruft, no internal-only content in `.planning/` or `docs/` that shouldn't go public.
**Depends on**: Phase 8 (history rewrites land before hygiene cleanup so we don't redo work)
**Requirements**: CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04
**Success Criteria** (what must be TRUE):
  1. Branch review complete: merged branches deleted on remote; stale branches (>90 days) decided keep-or-delete; live work-in-progress branches listed with owner + ETA. Result in `docs/audits/v0.4.0/CLEAN-01-branch-review.md` — CLEAN-01.
  2. >1MB files inventoried via `git rev-list --all --objects | git cat-file --batch-check`; non-release-artifact large files removed (or moved to Releases / LFS); decision documented in `docs/audits/v0.4.0/CLEAN-02-large-files.md` — CLEAN-02.
  3. `.gitignore` audited and updated; build outputs / editor files / OS files / virtualenvs / `node_modules/` / `dist/` / coverage / local caches all covered; `check-added-large-files` pre-commit hook active and verified — CLEAN-03.
  4. `.planning/` + `docs/` reviewed for content that should not be public-facing; sensitive content redacted, moved, or kept-after-explicit-decision in `docs/audits/v0.4.0/CLEAN-04-content-review.md` — CLEAN-04.
  5. Phase-close audit `docs/audits/v0.4.0/PHASE-09-AUDIT.md` cites every CLEAN-XX evidence; gate emits GREEN.
**Plans**: estimated 2 plans
- [ ] 09-01-PLAN.md — Branch review + large-file inventory + remediation; produce CLEAN-01/CLEAN-02 audit files (CLEAN-01, CLEAN-02)
- [ ] 09-02-PLAN.md — `.gitignore` audit + `.planning/` and `docs/` content review; Phase 9 AUDIT (CLEAN-03, CLEAN-04, phase-close gate)

### Phase 10: Public CI/CD Verification & Branch Protection
**Goal**: Every GitHub Actions workflow runs cleanly under public-repo permissions and survives the fork-PR threat model; branch protection on `master` is in force; the maintainer has confidence that flipping visibility will not produce a same-day exfiltration incident or a CI breakage cascade.
**Depends on**: Phase 9 (works against the cleaned-up workflow surface, not the pre-cleanup one)
**Requirements**: CIPUB-01, CIPUB-02, CIPUB-03, CIPUB-04
**Success Criteria** (what must be TRUE):
  1. Every workflow's `permissions:` block reviewed and set to least-privilege; default `contents: read`; elevated permissions confined to specific jobs (e.g., publish job in `release.yml`). Result documented in `docs/audits/v0.4.0/CIPUB-01-workflow-audit.md` — CIPUB-01.
  2. `pull_request_target` usage audited; if used, untrusted-input handling verified (no PR-controlled refs flowing into shell or `actions/checkout`); preference for `pull_request` over `pull_request_target` enforced. Evidence: workflow YAML diffs + audit notes — CIPUB-02.
  3. Branch protection on `master`: require ≥1 review, require CI status checks, no force-push, no direct pushes from non-maintainers, linear history. Captured in `docs/audits/v0.4.0/CIPUB-03-branch-protection.md` (screenshot or `gh api` JSON) — CIPUB-03.
  4. `nightly-qemu.yml`, `nightly-mutation.yml`, `release.yml`, `test.yml`, `deploy.yml` smoke-run via `workflow_dispatch` (or by triggering on a no-op PR) in the current private-repo state to catch any drift before the flip; runs exit 0. GitHub Actions run URLs captured — CIPUB-04.
  5. Phase-close audit `docs/audits/v0.4.0/PHASE-10-AUDIT.md` cites every CIPUB-XX evidence; gate emits GREEN.
**Plans**: estimated 2 plans
- [ ] 10-01-PLAN.md — Workflow `permissions:` + `pull_request_target` audit + diffs; CIPUB-01/CIPUB-02 audit files (CIPUB-01, CIPUB-02)
- [ ] 10-02-PLAN.md — Branch protection configuration + workflow smoke-runs; Phase 10 AUDIT (CIPUB-03, CIPUB-04, phase-close gate)

### Phase 11: Public Visibility Flip & Smoke Test
**Goal**: The repository is public; an anonymous user on a fresh machine can clone and install AgentLinux; the maintainer has a documented post-flip smoke transcript proving the public install path works.
**Depends on**: Phase 10 (every preceding phase has a green AUDIT)
**Requirements**: PUB-01, PUB-02, PUB-03, PUB-04
**Success Criteria** (what must be TRUE):
  1. Pre-flip checklist `docs/audits/v0.4.0/PUB-01-preflight-checklist.md` references every Phase 7-10 artifact and is signed off — PUB-01.
  2. `gh repo edit Roo4L/Agent-Linux --visibility public --accept-visibility-change-consequences` (or GitHub UI) executed; GitHub repo settings shows visibility = Public — PUB-02.
  3. Post-flip smoke: `git clone https://github.com/Roo4L/Agent-Linux.git` from a clean machine without auth succeeds; `curl -fsSL <documented public install URL> | bash` against the v0.3.0 release tag provisions an `agent` user; `agentlinux list` works. Transcript in `docs/audits/v0.4.0/PUB-03-postflip-smoke.md` — PUB-03.
  4. The first public release is browsable anonymously; release notes link to LICENSE, CONTRIBUTING.md, and a "what's in the box" summary — PUB-04.
  5. Phase-close audit `docs/audits/v0.4.0/PHASE-11-AUDIT.md` cites every PUB-XX evidence; gate emits GREEN.
**Plans**: estimated 2 plans
- [ ] 11-01-PLAN.md — Pre-flight checklist sign-off + visibility flip (PUB-01, PUB-02) — checkpoint:human-verify task type; the flip is the maintainer's hand on the trigger
- [ ] 11-02-PLAN.md — Post-flip anonymous-clone + curl-pipe-bash smoke test + release notes pass; Phase 11 AUDIT (PUB-03, PUB-04, phase-close gate, milestone-close gate)

## Progress

**Execution Order:**
Phases execute in numeric order: 7 → 8 → 9 → 10 → 11

| Phase | Plans Estimated | Status | Notes |
|-------|-----------------|--------|-------|
| 7. License & Public-Ready Documentation | 2 | ✓ Complete (commit `c52b3c1`) | LIC-01..04 evidenced |
| 8. Secret Scanning & History Audit | 3 | ✓ Complete (commit `c94920a`) | SEC-01..05 evidenced; gitleaks gate live |
| 9. Repository Hygiene & Artifact Cleanup | 2 | ✓ Complete (commit `158e465`) | CLEAN-01..04 evidenced |
| 10. Public CI/CD Verification & Branch Protection | 2 | ✓ Complete-pending-maintainer (commit `446c89b`) | CIPUB-01..02 evidenced; CIPUB-03..04 staged for maintainer apply |
| 11. Public Visibility Flip & Smoke Test | 2 | ✓ Shipped 2026-05-02 (commit `c8a2787`, tag `v0.3.1`) | PUB-01..04 evidenced; v0.4.0 originally tagged then renamed to `v0.3.1` for version-constant lockstep |
| **Total** | **~11 plans** | 5/5 phases shipped — milestone complete | Per-phase work landed via direct commits + `*-AUDIT.md`; no per-plan PLAN/SUMMARY files (autonomous-deterministic path; documented in each AUDIT §"Deviations from PLAN") |

## Coverage Summary

**Total v0.4.0 requirements:** 21 (4 LIC + 5 SEC + 4 CLEAN + 4 CIPUB + 4 PUB)
**Mapped:** 21 / 21
**Orphaned:** 0

Requirement allocation per phase:

| Phase | Requirements | Count |
|-------|--------------|-------|
| 7 License & Public-Ready Documentation | LIC-01..LIC-04 | 4 |
| 8 Secret Scanning & History Audit | SEC-01..SEC-05 | 5 |
| 9 Repository Hygiene & Artifact Cleanup | CLEAN-01..CLEAN-04 | 4 |
| 10 Public CI/CD Verification & Branch Protection | CIPUB-01..CIPUB-04 | 4 |
| 11 Public Visibility Flip & Smoke Test | PUB-01..PUB-04 | 4 |
| **Total** | | **21** |

**Notes on verification:**
- Most v0.4.0 work is repo-level / process-level. Evidence is documentation artifacts under `docs/audits/v0.4.0/<REQ-ID>-*.md`, ADRs under `docs/decisions/`, GitHub Actions run URLs, and (where applicable) screenshots / `gh api` JSON outputs.
- The bats / Docker / QEMU harness from v0.3.0 is **not** the primary verification surface for v0.4.0. It's still green and still required to stay green (CIPUB-04 smoke runs cover it), but new bats tests are not the deliverable here.
- The phase-close gate convention (TST-07-style) carries over: every requirement must close with a cited evidence artifact in its phase's AUDIT doc before the gate emits GREEN.

## Open Questions for Discuss-Phase

These are open questions to resolve in `/gsd-discuss-phase 7` (and subsequent phases):

- **License pick**: MIT (recommended) vs. Apache-2.0 (patent grant) vs. another OSI license? — resolved in Phase 7 ADR-013.
- **Existing-file SPDX backfill**: apply headers retroactively to all source files in one big commit, or only to new files going forward? — resolved in Phase 7 ADR-013.
- **History rewrite vs. accept-and-rotate** for any leaked secrets: depends on what is found. Default-stance: rotate without rewrite unless the secret grants ongoing access — resolved in Phase 8 ADR-014.
- **Default branch rename** (`master` → `main`): explicitly out of scope for v0.4.0; raise as a separate milestone if desired. (Cosmetic; would invalidate existing URL references.)
- **Public install URL** for PUB-03 smoke: is it `agentlinux.org/install.sh` or `https://github.com/Roo4L/Agent-Linux/releases/download/v0.3.0/install.sh`? Resolve before Phase 11.

### Phase 12: Developer documentation for installer, runtime, and CLI (AL-22)

**Goal:** A reader landing on the AgentLinux repo can find a 60-second answer to "what value does AgentLinux provide for surface X" for every component (installer, agent user, sudo drop-in, Node.js runtime, the agent catalog, the registry CLI, and the curated agent set: Claude Code, GSD, Playwright). The docs stay in sync with the source via a project-scoped reviewer (`dev-docs-auditor`) embedded in the existing review loop — no new stop-hook is added (ADR-015 lands in Plan 12-05).
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07
**Depends on:** Phase 11
**Plans:** 5/5 plans complete

Plans:
- [x] 12-01-PLAN.md — docs/internals/ index + 4 install/runtime layer component docs (DOC-01, DOC-02)
- [x] 12-02-PLAN.md — 5 agent + CLI/catalog component docs (DOC-02)
- [x] 12-03-PLAN.md — dev-docs-auditor reviewer agent + dev-docs skill (DOC-03, DOC-04, DOC-06)
- [x] 12-04-PLAN.md — CLAUDE.md Review Loop + Pointers wiring + top-level README.md discoverability (DOC-03, DOC-05)
- [x] 12-05-PLAN.md — REQUIREMENTS.md DOC-XX entries + ADR-015 + Phase 12 AUDIT (DOC-01..DOC-07, phase-close) (completed 2026-05-10)
