# Requirements: AgentLinux v0.4.0 — Open-Source Release

**Defined:** 2026-04-26
**Milestone:** v0.4.0 Open-Source Release
**Triggered by:** Issue AGE-6 "Make repository public"
**Core Value (carried from PROJECT.md):** An agent can be dropped into any supported Linux system and just work — provisioned correctly the first time. v0.4.0 does not change the product; it changes the repository's distribution model from private to public so the project can ride free GitHub Actions minutes and accept community contributions.

## Design Philosophy (read first)

**Treat the visibility flip as one-way.** Re-private is technically possible but third parties can clone or fork the moment the repo is public; once material is out, it is out. Therefore:

- Every Phase 7-10 outcome must be in place *before* Phase 11 flips visibility. Phase 11 is purely the trigger pull and the post-flip smoke test.
- "Done" for the secret-scanning phase is **zero verifiable findings or every finding triaged with a documented decision** (rotate, accept, or rewrite history). It is not "we ran the scanner and looked at the report."
- "Done" for CI/CD readiness includes a *concrete adversary check*: a hostile fork PR cannot exfiltrate secrets via the workflow. We do not assume — we audit.
- The behavior-test-as-spec discipline from v0.3.0 carries over. Every requirement here gets at least one verifiable check before its phase closes (bats @test, CI workflow run citation, tooling output committed to `docs/audits/v0.4.0/`, or a documented manual verification with evidence).

## v0.4.0 Requirements

Grouped by area. Each `XXX-NN` is a testable, verifiable outcome — auditable before the phase closes.

### License & Documentation (LIC) — Phase 7

- [ ] **LIC-01**: A `LICENSE` file exists at the repository root containing an OSI-approved OSS license. MIT is the recommended pick (permissive, dependency-friendly, low community-adoption friction); Apache-2.0 is acceptable if a patent-grant rationale is recorded in `docs/decisions/`. The chosen license is logged as an ADR (`docs/decisions/ADR-013-license-choice.md`).
- [ ] **LIC-02**: README references the license — at minimum a `License` section linking to `LICENSE`, ideally a license badge near the top. The README is reviewed for public-audience tone (no internal-only references, no "TODO" placeholders blocking comprehension).
- [ ] **LIC-03**: Source files include SPDX license identifier headers where appropriate — bash entrypoints (`plugin/bin/*`), TypeScript sources under `plugin/cli/src/`, and any new contribution-template files. A repo-wide grep proves the convention is applied consistently to *new* files going forward (existing files may be batch-updated or left to organic touch — decision recorded in the ADR).
- [ ] **LIC-04**: A `CONTRIBUTING.md` file exists at the repository root (or under `.github/`) documenting how to file issues, open PRs, run the test harness locally, and the expected review-loop conventions from `docs/HARNESS.md`. README links to it.

### Secret Scanning & History Audit (SEC) — Phase 8

- [ ] **SEC-01**: `gitleaks detect --redact --no-banner --source . --log-opts="--all"` runs against full git history (every branch, every commit) with zero High/Critical findings, OR every finding is triaged in `docs/audits/v0.4.0/SEC-01-gitleaks-report.md` with a documented decision (rotate, accept-with-rotation, or remove-from-history).
- [ ] **SEC-02**: `trufflehog git file://. --since-commit=$(git rev-list --max-parents=0 HEAD) --only-verified` runs against full history with zero **verified** findings, OR every verified finding is rotated and a remediation note exists in `docs/audits/v0.4.0/SEC-02-trufflehog-report.md`. (Unverified findings are listed for completeness but do not block — they are most often false positives or test fixtures.)
- [ ] **SEC-03**: A targeted manual audit covers the four high-risk classes called out in issue AGE-6: (a) Buttondown API tokens used by the website signup flow; (b) GitHub / Anthropic / npm / package-registry credentials; (c) `.env` / `.npmrc` / `.git-credentials` / SSH key artifacts; (d) any `Authorization: Bearer ...` strings in committed logs, fixtures, or test recordings. Result: either "none found" with grep evidence, or each instance is itemized in `docs/audits/v0.4.0/SEC-03-targeted-audit.md` with a remediation entry.
- [ ] **SEC-04**: For every secret found by SEC-01..03 that was real (not a false positive), the secret is rotated upstream (new token issued, old token revoked) AND the decision between "accept rotation as the remediation" vs. "rewrite history with `git filter-repo`" is recorded in the ADR `docs/decisions/ADR-014-secret-remediation.md`. Default decision: rotate without rewriting unless the secret grants ongoing access that cannot be revoked from upstream.
- [ ] **SEC-05**: A `gitleaks` (or equivalent) gate runs on every PR going forward — either as a pre-commit hook in `.pre-commit-config.yaml` or as a GitHub Actions step in `.github/workflows/test.yml`. The gate catches any *new* secret-shaped string from being committed and is verified to fire on a contrived test commit (evidence: a test PR or local pre-commit run).

### Repository Hygiene & Artifact Cleanup (CLEAN) — Phase 9

- [ ] **CLEAN-01**: All remote branches are reviewed. Branches that are merged to `master` are deleted on the remote; branches that are stale (>90 days, no merges, no recent commits) are either documented in `docs/audits/v0.4.0/CLEAN-01-branch-review.md` with a keep-or-delete decision or deleted. Live work-in-progress branches are listed with their owner and ETA.
- [ ] **CLEAN-02**: Files larger than 1 MB tracked anywhere in git history are inventoried (`git rev-list --all --objects | git cat-file --batch-check --batch-all-objects ...` or equivalent). Any large file that is not a legitimate release artifact is either removed (and history rewritten if necessary, decision recorded in the ADR) or moved to GitHub Releases / Git LFS. Result documented in `docs/audits/v0.4.0/CLEAN-02-large-files.md`.
- [ ] **CLEAN-03**: `.gitignore` is audited for completeness. Build outputs, editor files, OS files (`.DS_Store`, `Thumbs.db`), virtualenvs, `node_modules/`, `dist/`, coverage reports, and any local test caches are covered. A pre-commit hook (`check-added-large-files`, already present per `.pre-commit-config.yaml`) is verified to be active. Result: `.gitignore` diff committed; hook smoke-test evidence in `docs/audits/v0.4.0/CLEAN-03-gitignore-audit.md`.
- [ ] **CLEAN-04**: `.planning/` and `docs/` are reviewed for content that should not be public-facing — internal vendor names, customer references, unredacted incident notes, or experiment artifacts. Anything sensitive is redacted, moved to a private location, or kept after explicit decision recorded in the audit. `.planning/` is intentionally retained per project convention (it's the GSD workflow trail and provides context for new contributors).

### Public CI/CD Readiness (CIPUB) — Phase 10

- [ ] **CIPUB-01**: Every GitHub Actions workflow (`test.yml`, `nightly-qemu.yml`, `nightly-mutation.yml`, `release.yml`, `deploy.yml`) is reviewed under public-repo permissions semantics. Each workflow's `permissions:` block is set to least-privilege (default `contents: read`; `contents: write` only on the publish job in `release.yml`). Result documented in `docs/audits/v0.4.0/CIPUB-01-workflow-audit.md`.
- [ ] **CIPUB-02**: `pull_request_target` usage is audited for fork-PR exfiltration risk. If any workflow uses it, untrusted-input handling is verified (no `${{ github.event.pull_request.head.ref }}` injected into shell, no `actions/checkout@v* ref: <PR ref>` followed by privileged steps). Default posture: prefer `pull_request` over `pull_request_target`; if `pull_request_target` is required, the workflow runs on a curated, hardcoded ref. Evidence: workflow YAML diffs, audit notes.
- [ ] **CIPUB-03**: Branch protection on `master` is configured: require at least 1 review approval; require all required status checks (CI green); require linear history (no force-push); restrict who can push directly to maintainers. The protection rule is captured in `docs/audits/v0.4.0/CIPUB-03-branch-protection.md` (a screenshot of the GitHub settings page or `gh api repos/:owner/:repo/branches/master/protection` JSON output).
- [ ] **CIPUB-04**: `nightly-qemu.yml`, `nightly-mutation.yml`, and `release.yml` are smoke-run (`workflow_dispatch`) against the public-repo configuration before the visibility flip and exit zero. This catches any repo-name / token-name / runner-permission drift before it becomes a public-repo embarrassment. Evidence: GitHub Actions run URLs.

### Public Visibility Flip & Smoke Test (PUB) — Phase 11

- [ ] **PUB-01**: A pre-flip checklist is signed off in `docs/audits/v0.4.0/PUB-01-preflight-checklist.md`. Every Phase 7-10 requirement is checked off with a concrete artifact link. The checklist explicitly includes: license present, no verified secrets in history, scanner gate active, branch protection on, CI smoke-run green under public-repo simulation. Pre-flight is a hard blocker for PUB-02.
- [ ] **PUB-02**: Repository visibility is flipped to public via `gh repo edit Roo4L/Agent-Linux --visibility public --accept-visibility-change-consequences` (or the equivalent GitHub UI action). The flip is performed by the maintainer; this requirement is "complete" when the GitHub repo settings page shows visibility = Public.
- [ ] **PUB-03**: Post-flip smoke test: from a clean machine without a GitHub auth token, `git clone https://github.com/Roo4L/Agent-Linux.git` succeeds; `curl -fsSL https://agentlinux.org/install.sh | bash` (or the documented public install URL) succeeds against the v0.3.0 release tag; `agent` user is provisioned; `agentlinux list` works. Evidence: terminal session log committed to `docs/audits/v0.4.0/PUB-03-postflip-smoke.md`.
- [ ] **PUB-04**: The first public release (`v0.3.0` GA, or a follow-on `v0.3.1`/`v0.4.0` documentation-only release) is tagged with a public-friendly release notes blurb (link to LICENSE, contributing guide, and a "what's in the box" summary). The release page is browsable anonymously.

## Post-v0.4.0 Addendum Requirements

The v0.4.0 milestone closed at commit `c8a2787` on 2026-05-02 with 21 requirements (LIC/SEC/CLEAN/CIPUB/PUB). The following requirement set is a *post-v0.4.0 addendum* added under issue AL-22 ("Create documentation on what AgentLinux does") — captured in this file because REQUIREMENTS.md is still the active per-project requirements doc, but tracked separately so the v0.4.0 milestone gate count stays honest.

### Developer Documentation (DOC) — Phase 12

- [x] **DOC-01**: A `docs/internals/README.md` exists at the documented location, opens with a one-paragraph "What AgentLinux is" lede in product voice, and contains a `## Components` H2 with a TOC linking to all nine component docs (installer, agent-user, sudo-drop-in, nodejs-runtime, claude-code, gsd, playwright, registry-cli, catalog). Verified by file-existence check + grep for the nine `(*.md)` link targets.
- [x] **DOC-02**: Nine component docs exist under `docs/internals/` — one per surface listed in the index. Each follows the four-section structural contract: `## The problem` → `## What AgentLinux does` → `## Value vs the naive approach` → `## Related`. Each `## Value vs the naive approach` is a numbered list with **bold lead clause** items (excerpt-friendly per the AL-22 reuse-as-blog-source signal). No source-line deep links anywhere in `docs/internals/` (per the dev-docs depth contract). Verified by grep across the nine files.
- [x] **DOC-03**: A new project-scoped reviewer agent `.claude/agents/dev-docs-auditor.md` exists with read-only tools (`tools: Read, Grep, Glob, Bash`) and a frontmatter description triggering it on changes under `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, and `packaging/curl-installer/`. The reviewer is registered in CLAUDE.md "Review Loop" by extending the Bash, TS/JS, and Catalog recipes rows of the reviewer-by-file-type table. Verified by file existence + `grep -E '^- Bash → .*dev-docs-auditor' CLAUDE.md` and equivalents for the other two extended rows.
- [x] **DOC-04**: A new project-scoped skill `.claude/skills/dev-docs/SKILL.md` exists, documenting the docs/internals/ contract (per-component four-section structure, source-path → doc-path dispatch table, when to update, product-perspective lens, and the explicit decision to not add a stop-hook). The skill is enumerated in CLAUDE.md "Pointers" alongside the other project-scoped skills. Verified by file existence + grep for the dispatch-table entries covering all 9 component docs.
- [x] **DOC-05**: Top-level discoverability — top-level `README.md` gains a "Why AgentLinux — concepts" H2 section linking `docs/internals/README.md`, AND a `## Links` row labelled `**Internals (developer docs):**` linking `docs/internals/`. Verified by grep across `README.md`.
- [x] **DOC-06**: No new stop-hook was added — `.claude/hooks/dev-docs-reminder.sh` does not exist; `.claude/settings.json` is unchanged across the Phase 12 commit range. The dev-docs sync check rides inside the existing `review-reminder.sh`-triggered review loop per the ADR-010 2026-05-02 refinement and per ADR-015 (DOC-07). Verified by `! test -f .claude/hooks/dev-docs-reminder.sh` and `git diff <phase-12-base>..HEAD -- .claude/settings.json | wc -l` returning 0.
- [x] **DOC-07**: A new ADR `docs/decisions/015-developer-internals-docs.md` records the design decision behind Phase 12 — what `docs/internals/` is for, why a reviewer + skill instead of a hook, why a flat embed inside the existing Review Loop instead of a new top-level CLAUDE.md section. Status `Accepted`. Verified by file existence + `grep -q '^## Decision' docs/decisions/015-developer-internals-docs.md`.

## Future Requirements (not in this milestone)

- Public package distribution beyond GitHub Releases (PPA, Homebrew tap, AUR) — deferred until adoption signals justify the maintenance cost.
- Code of Conduct, security policy (`SECURITY.md`), issue templates, PR template — track separately as a documentation milestone if the contribution surface grows.
- Additional distro targets (Fedora / CentOS / Alma / Arch) — feature milestone, separate from open-sourcing.
- Mutation testing promoted to release gate — still planned for v0.5+ per ADR-010.

## Out of Scope (explicit exclusions)

**v0.4.0 out of scope:**
- New product features. v0.4.0 is a repository / process / governance milestone.
- Migration to a different GitHub organization. The repo stays at `Roo4L/Agent-Linux` and only flips visibility.
- Renaming the default branch from `master` to `main`. Cosmetic; not blocking the public flip and would invalidate downstream URL references for no functional gain. Track separately if desired.
- Setting up GitHub Discussions, Sponsors, Pages-hosted documentation, or other community-platform features. Deferred to a community-launch milestone after the flip lands.
- Re-licensing existing third-party content vendored under `vendor/` or similar. Out-of-scope here; flagged for review only if SEC/CLEAN audits surface a conflict.

**Permanently out of scope (carried from prior milestones):**
- User accounts or login functionality on website
- Blog or content management system
- Mobile app
- E-commerce / payments
- Multi-arch (ARM) — x86_64 only for now
- Docker-in-Docker inside the agent environment

## REQ-ID Traceability

| Phase | Requirements | Count |
|-------|--------------|-------|
| 7 License & Public-Ready Documentation | LIC-01, LIC-02, LIC-03, LIC-04 | 4 |
| 8 Secret Scanning & History Audit | SEC-01, SEC-02, SEC-03, SEC-04, SEC-05 | 5 |
| 9 Repository Hygiene & Artifact Cleanup | CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04 | 4 |
| 10 Public CI/CD Verification & Branch Protection | CIPUB-01, CIPUB-02, CIPUB-03, CIPUB-04 | 4 |
| 11 Public Visibility Flip & Smoke Test | PUB-01, PUB-02, PUB-03, PUB-04 | 4 |
| **Total v0.4.0** | | **21** |

**Coverage check:** 21 requirements mapped to 5 phases. Zero orphans.

### Post-v0.4.0 Addendum Traceability

| Phase | Requirements | Count |
|-------|--------------|-------|
| 12 Developer Documentation (AL-22) | DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07 | 7 |
| **Total addendum** | | **7** |

**Coverage check:** 7 addendum requirements mapped to 1 phase. Zero orphans. (v0.4.0 milestone total remains 21 requirements across 5 phases — see the table above.)

## Verification Convention

Each requirement must close with at least one verifiable artifact before its phase closes (TST-07 phase-close pattern from v0.3.0):

| Verification kind | Where it lives |
|-------------------|----------------|
| Tool output (gitleaks, trufflehog, large-file inventory) | `docs/audits/v0.4.0/<REQ-ID>-*.md` with the relevant command, output, and triage notes |
| ADR | `docs/decisions/ADR-013-license-choice.md`, `docs/decisions/ADR-014-secret-remediation.md` |
| Workflow run citation | GitHub Actions run URL captured in the audit doc |
| Manual smoke transcript | Terminal-session paste committed to the audit doc with date and host |
| Bats @test (rare in this milestone — most v0.4.0 work is repo-level, not behavior-level) | `tests/bats/*.bats` if a behavior contract is added (e.g., a license-header smoke test) |

Phase-close gate (analogous to v0.3.0's TST-07): every requirement has at least one of the above evidence forms cited in its phase's AUDIT.md, and the phase's behavior-coverage-auditor (or a `gsd-eval-auditor` retrofit for this milestone) emits `GATE: GREEN`.
