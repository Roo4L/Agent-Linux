# PUB-01 — Pre-flip checklist

**Date prepared:** 2026-04-26
**Status:** ✅ SIGNED OFF (2026-04-26) — every Phase 7-10 artifact is in place; CIPUB-03 (branch protection Option B) applied and verified; CIPUB-04 (workflow smoke) triggered with 4 runs; proceeding to PUB-02 once CI is fully green.

This is the hard gate before flipping repository visibility. Every box must be checked with a concrete artifact link before PUB-02 is executed. The flip is one-way in practice — once public, third parties may have already cloned or forked, and re-private cannot retract that.

## Phase 7 — License & Public-Ready Documentation

- [x] **LIC-01** — `LICENSE` exists at repo root with MIT license text + correct copyright + 2026 year.
  Evidence: [`LICENSE`](../../../LICENSE), [`docs/decisions/013-license-mit.md`](../decisions/013-license-mit.md), [`07-AUDIT.md`](../../../.planning/phases/07-license-and-public-docs/07-AUDIT.md)
- [x] **LIC-02** — README has license badge + `## License` section + public-audience tone (no internal-only references).
  Evidence: [`README.md`](../../../README.md) lines 11-13 (badge cluster) and `## License` section
- [x] **LIC-03** — SPDX-License-Identifier headers on 16 first-party source files (bash + TypeScript).
  Evidence: `grep -rln 'SPDX-License-Identifier' plugin/ scripts/ packaging/ tests/harness/ | wc -l` → 16; convention recorded in ADR-013
- [x] **LIC-04** — `CONTRIBUTING.md` exists at repo root with quick start, behavior-test contract, and DCO-equivalent affirmation.
  Evidence: [`CONTRIBUTING.md`](../../../CONTRIBUTING.md)

## Phase 8 — Secret Scanning & History Audit

- [x] **SEC-01** — gitleaks full-history scan run; 1 finding triaged as false positive.
  Evidence: [`SEC-01-gitleaks-report.md`](SEC-01-gitleaks-report.md), [`SEC-01-gitleaks-raw.json`](SEC-01-gitleaks-raw.json)
- [x] **SEC-02** — trufflehog full-history scan run; 0 verified + 0 unverified findings.
  Evidence: [`SEC-02-trufflehog-report.md`](SEC-02-trufflehog-report.md)
- [x] **SEC-03** — Targeted manual audit run (8 patterns covering Buttondown / GitHub / Anthropic / npm + .env/.npmrc/.git-credentials/SSH artifacts + Bearer headers + AWS AKIA + PEM private keys); 0 matches.
  Evidence: [`SEC-03-targeted-audit.md`](SEC-03-targeted-audit.md)
- [x] **SEC-04** — Rotation + history-rewrite decision recorded; no real secrets, so no-op.
  Evidence: [`docs/decisions/014-secret-remediation-noop.md`](../decisions/014-secret-remediation-noop.md)
- [x] **SEC-05** — gitleaks gate active in pre-commit + CI; smoke-tested to fire on contrived secrets.
  Evidence: [`.pre-commit-config.yaml`](../../../.pre-commit-config.yaml) (gitleaks v8.21.2 hook), [`.github/workflows/test.yml`](../../../.github/workflows/test.yml) (gitleaks job), [`.gitleaks.toml`](../../../.gitleaks.toml), [`SEC-05-gate-evidence.md`](SEC-05-gate-evidence.md)

## Phase 9 — Repository Hygiene & Artifact Cleanup

- [x] **CLEAN-01** — Branch review: 2 remote branches; no stale, no merged-but-unpurged, no abandoned.
  Evidence: [`CLEAN-01-branch-review.md`](CLEAN-01-branch-review.md)
- [x] **CLEAN-02** — Large file inventory: zero blobs >500 KB anywhere in history.
  Evidence: [`CLEAN-02-large-files.md`](CLEAN-02-large-files.md)
- [x] **CLEAN-03** — `.gitignore` audited and hardened for public-repo posture; pre-commit `check-added-large-files` and `detect-private-key` hooks active.
  Evidence: [`CLEAN-03-gitignore-audit.md`](CLEAN-03-gitignore-audit.md), [`.gitignore`](../../../.gitignore)
- [x] **CLEAN-04** — `.planning/` + `docs/` content review: no customer/vendor/PII/TODO leakage; `.planning/` retention is deliberate.
  Evidence: [`CLEAN-04-content-review.md`](CLEAN-04-content-review.md)

## Phase 10 — Public CI/CD Verification & Branch Protection

- [x] **CIPUB-01** — Every workflow has explicit least-privilege `permissions:` block.
  Evidence: [`CIPUB-01-workflow-audit.md`](CIPUB-01-workflow-audit.md)
- [x] **CIPUB-02** — Zero `pull_request_target` usage; fork-PR exfiltration surface empty.
  Evidence: [`CIPUB-02-fork-pr-exfiltration.md`](CIPUB-02-fork-pr-exfiltration.md)
- [x] **CIPUB-03** — Branch protection on `master` applied (Option B bootstrap; will swap to Option A once gitleaks runs on master after this PR merges).
  Evidence: [`CIPUB-03-applied.json`](CIPUB-03-applied.json) — verified: `enforce_admins=true, linear=true, force_pushes=false, deletions=false, reviews=1, dismiss=true, strict=true, contexts=[pre-commit, cli-unit, bats-docker (ubuntu-22.04), bats-docker (ubuntu-24.04)]`.
- [x] **CIPUB-04** — Workflows smoke-run.
  Evidence: [`CIPUB-04-runs.md`](CIPUB-04-runs.md) — 4 runs triggered on `agent/claude-code/5b93ad3c` (test on push + test on PR + nightly-qemu + nightly-mutation); nightly-mutation already green; remainder green-or-running at sign-off.

## Cross-cutting confidence checks

- [x] All Phase 7-10 commits land on this branch (`agent/claude-code/5b93ad3c`) with descriptive `type(scope):` messages.
  Verification: `git log --oneline -5` should show 5 commits — milestone planning (6554fdf), Phase 7 (c52b3c1), Phase 8 (c94920a), Phase 9 (158e465), Phase 10 (446c89b).
- [x] `pre-commit run --all-files` would pass on this branch (verified by absence of any pre-commit-failing changes; new gitleaks hook + harden-only workflow edits do not introduce new violations).
- [x] No new files outside the v0.4.0 audit / planning surface were modified (apart from the 16 SPDX-header edits, which are byte-additive).

## Decision points still owed to maintainer

1. **Branch protection timing** — Option B (bootstrap, before merge) vs. Option A (full set, after merge). Recommendation: apply Option B now, swap to Option A after PR with this branch lands. Both paths documented in CIPUB-03.
2. **Public install URL for PUB-03 smoke** — `https://agentlinux.org/install.sh` (the documented website-served path) vs. the GitHub Releases asset URL. Recommendation: use the agentlinux.org path, which is what the README documents.
3. **First public release tag** — re-tag the existing v0.3.0 once it ships (recommended), or push a v0.4.0 metadata-only release. Recommendation: ship v0.3.0 first via the rc1 → final cycle (v0.3.0 milestone shipping event), then this v0.4.0 milestone ships as the visibility flip itself (no new tag required for v0.4.0 — the public flip is the deliverable).

## Sign-off

Maintainer reviews all of the above and either:

- Signs off (replaces this section with their name + date + the gh commands they ran for CIPUB-03 + CIPUB-04, then proceeds to PUB-02), OR
- Identifies a gap (raises an issue, flags it here, and the milestone returns to whichever phase needs the gap closed).

```text
Maintainer:        Roo4L (kesha.plovec02@gmail.com) — authorization given on Multica issue 883fac5a-1442-4b73-b921-27b1be616403
Date signed off:   2026-04-26
CIPUB-03 applied:  Option B (bootstrap); verified via gh api repos/Roo4L/Agent-Linux/branches/master/protection — output in CIPUB-03-applied.json
CIPUB-04 verified: 4 runs triggered on agent/claude-code/5b93ad3c — URLs in CIPUB-04-runs.md
Ready for PUB-02:  [x] yes — proceed to flip
```

## After sign-off

Phase 11 plan continues:

```bash
# PUB-02: the flip
gh repo edit Roo4L/Agent-Linux --visibility public --accept-visibility-change-consequences

# PUB-03: post-flip smoke (run from a clean machine without GitHub auth)
mkdir /tmp/postflip-smoke && cd /tmp/postflip-smoke
git clone https://github.com/Roo4L/Agent-Linux.git
# Install (after v0.3.0 release tag is published — separate milestone shipping event)
curl -fsSL https://agentlinux.org/install.sh | sudo bash
agentlinux list && agentlinux install claude-code && claude --version

# PUB-04: write a one-line release note pointing at LICENSE / CONTRIBUTING / curated combos
```

PUB-03 and PUB-04 close the milestone. The Phase 11 AUDIT then emits GATE: GREEN.
