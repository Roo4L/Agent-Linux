# CIPUB-02 — `pull_request_target` / fork-PR exfiltration audit

**Date:** 2026-04-26
**Status:** ✅ PASSED — zero `pull_request_target` usage; zero PR-controlled-ref interpolation in any privileged step; the standard `pull_request` event runs untrusted PR code without elevated permissions, which is the safe posture.

## Method

```bash
# Search every workflow YAML for the high-risk events:
grep -nE 'pull_request_target|workflow_run' .github/workflows/*.yml

# Search for PR-controlled refs flowing into shell or actions/checkout:
grep -nE '\$\{\{[[:space:]]*github\.event\.pull_request\.head' .github/workflows/*.yml

# Verify checkout actions ride the default $GITHUB_REF (safe) not a PR-controlled override:
grep -nB 1 -A 4 'actions/checkout' .github/workflows/*.yml | grep -E '(ref:|head|pr)'
```

## Findings

### `pull_request_target` usage

**0 matches.** No workflow uses `pull_request_target` — the high-risk event that runs in the context of the *base* repo (with secrets) but checks out the *PR's* code (untrusted). Every PR-triggered workflow uses `pull_request`, which runs without secret access by default for fork PRs — the safe posture.

### `workflow_run` chained workflows

**0 matches.** No workflow chains off another via `workflow_run` (a privilege-elevation vector if combined with PR-fetched artifacts).

### PR-controlled-ref interpolation

**0 matches** for `${{ github.event.pull_request.head.* }}` shell interpolation. No workflow injects a PR-controlled ref into a shell command, which would be a command-injection vector.

### `actions/checkout@*` ref overrides

Every `actions/checkout@v4` invocation in the five workflows uses either:
- The default `$GITHUB_REF` (safe — for `pull_request` events on public repos this is `refs/pull/<n>/merge`, the result of merging the PR into `master` at the time the workflow ran, not an attacker-controlled ref), OR
- An explicit `with: { fetch-depth: 0 }` (this phase's gitleaks job) — fetches full history but still on the default ref, not a PR-controlled override.

No `with: { ref: ${{ github.event.pull_request.head.<X> }} }` patterns. No `with: { ref: ${{ github.head_ref }} }` patterns either (which is a softer variant of the same anti-pattern).

## Default posture statement

We prefer `pull_request` over `pull_request_target` everywhere. If any future workflow requires `pull_request_target` (e.g., a label-based deploy preview), the contributor must:

1. Document the rationale in the workflow header comment,
2. Pin `actions/checkout@v4` to a hardcoded ref (`with: { ref: ${{ github.base_ref }} }` if checking out the base, or no `with: ref:` at all),
3. Treat any PR-derived input (titles, descriptions, file contents) as untrusted — never feed it into shell, never set it as an env var that's later expanded into shell, never use it as part of a path,
4. Get a review with `security-engineer` / human security review before merging.

This stance is recorded in `CONTRIBUTING.md` review-loop expectations and is not currently invoked by any workflow.

## Conclusion

The fork-PR exfiltration threat surface is empty. CIPUB-02 closes GREEN.
