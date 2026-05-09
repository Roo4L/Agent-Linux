# CIPUB-03 — Branch protection on `master`

**Date:** 2026-04-26
**Status:** ⏳ READY TO APPLY — configuration documented; maintainer to execute one of the two `gh` commands below before the visibility flip.

## Current state (pre-flip)

```bash
gh api repos/Roo4L/Agent-Linux/branches/master/protection
# → {"message":"Branch not protected","status":"404"}
```

Master is currently unprotected. This is fine while the repo is private and the maintainer is the sole pusher; it is **not** fine for a public repo where any non-default state could matter to a forking observer.

## Required configuration

| Rule | Setting | Reason |
|------|---------|--------|
| Require pull request before merging | `required_pull_request_reviews.required_approving_review_count = 1` | Forces review for every change; the bare minimum for OSS hygiene. Maintainer can self-approve their own PR (allowed by GitHub default for non-org admins) but must still go through the PR flow. |
| Dismiss stale reviews | `dismiss_stale_reviews = true` | If a PR is force-pushed after approval, the approval is invalidated. Prevents a "stamp-then-tamper" attack. |
| Require status checks before merging | `required_status_checks.strict = true` (up-to-date with base) + contexts: `pre-commit`, `cli-unit`, `bats-docker (ubuntu-22.04)`, `bats-docker (ubuntu-24.04)`, `gitleaks` (after this branch merges) | The CI matrix is the spec; PRs must be green and up-to-date with base before merging. |
| Require linear history | `required_linear_history = true` | No merge commits; rebase/squash only. Cleaner history; also defeats one class of "merge commit pulls in stale code" bugs. |
| No force-push | `allow_force_pushes = false` | Force-push to master would orphan tags / Releases / contributor clones. Catastrophic on a public repo. |
| No deletion | `allow_deletions = false` | Belt-and-braces against an accidental `git push origin :master`. |
| Enforce on admins | `enforce_admins = true` | The maintainer is bound by the same rules as everyone else — no "I'll just push directly" escape hatch. Closes the typical hole in branch protection. |

## Apply with one command

### Option A: full protection (recommended once this branch is merged)

```bash
gh api -X PUT repos/Roo4L/Agent-Linux/branches/master/protection \
  -F enforce_admins=true \
  -F required_linear_history=true \
  -F allow_force_pushes=false \
  -F allow_deletions=false \
  -F required_pull_request_reviews.required_approving_review_count=1 \
  -F required_pull_request_reviews.dismiss_stale_reviews=true \
  -F required_pull_request_reviews.require_code_owner_reviews=false \
  -F required_status_checks.strict=true \
  -F required_status_checks.contexts[]=pre-commit \
  -F required_status_checks.contexts[]=cli-unit \
  -F required_status_checks.contexts[]='bats-docker (ubuntu-22.04)' \
  -F required_status_checks.contexts[]='bats-docker (ubuntu-24.04)' \
  -F required_status_checks.contexts[]=gitleaks \
  -F restrictions= 2>&1 | tee docs/audits/v0.4.0/CIPUB-03-applied.json
```

### Option B: bootstrap protection without `gitleaks` context (use BEFORE this branch merges)

Required because GitHub rejects `required_status_checks.contexts` containing names that have not yet appeared on `master`'s commit-status surface. After this branch merges and a single PR runs the new `gitleaks` job to completion, swap to Option A.

```bash
gh api -X PUT repos/Roo4L/Agent-Linux/branches/master/protection \
  -F enforce_admins=true \
  -F required_linear_history=true \
  -F allow_force_pushes=false \
  -F allow_deletions=false \
  -F required_pull_request_reviews.required_approving_review_count=1 \
  -F required_pull_request_reviews.dismiss_stale_reviews=true \
  -F required_pull_request_reviews.require_code_owner_reviews=false \
  -F required_status_checks.strict=true \
  -F required_status_checks.contexts[]=pre-commit \
  -F required_status_checks.contexts[]=cli-unit \
  -F required_status_checks.contexts[]='bats-docker (ubuntu-22.04)' \
  -F required_status_checks.contexts[]='bats-docker (ubuntu-24.04)' \
  -F restrictions= 2>&1 | tee docs/audits/v0.4.0/CIPUB-03-applied.json
```

## Verification

After applying, verify with:

```bash
gh api repos/Roo4L/Agent-Linux/branches/master/protection \
  --jq '{enforce_admins: .enforce_admins.enabled,
         linear: .required_linear_history.enabled,
         force_pushes: .allow_force_pushes.enabled,
         deletions: .allow_deletions.enabled,
         reviews: .required_pull_request_reviews.required_approving_review_count,
         dismiss: .required_pull_request_reviews.dismiss_stale_reviews,
         strict: .required_status_checks.strict,
         contexts: .required_status_checks.contexts}'
```

Expected output:

```json
{
  "enforce_admins": true,
  "linear": true,
  "force_pushes": false,
  "deletions": false,
  "reviews": 1,
  "dismiss": true,
  "strict": true,
  "contexts": ["pre-commit", "cli-unit", "bats-docker (ubuntu-22.04)", "bats-docker (ubuntu-24.04)" /* + "gitleaks" once Option A is applied */]
}
```

Save this output to `docs/audits/v0.4.0/CIPUB-03-applied.json` for the audit trail (the apply commands above already pipe to that location).

## Why this isn't applied autonomously

Branch protection affects every collaborator's push semantics — it is a high-blast-radius configuration change. The autonomous mode running this milestone explicitly stops at maintainer-action checkpoints (per the `/gsd-autonomous` invocation note that Phase 11 is checkpoint:human-verify). CIPUB-03 is the analogous checkpoint *within* Phase 10: the maintainer reviews this configuration and applies one of the two commands above.

After application, append the verification JSON output to this audit document; CIPUB-03 then closes GREEN.

## Status

- [x] Configuration designed and documented (this file)
- [ ] Applied by maintainer (Option B before this branch merges; swap to Option A after it merges and the gitleaks check runs once)
- [ ] Verification output appended to this file
