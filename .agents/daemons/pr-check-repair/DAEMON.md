---
id: pr-check-repair
purpose: Repair failing checks on non-draft pull requests by diagnosing the triggering check, pushing evidence-grounded fixes, and commenting only when action or human attention is needed.
watch:
  - A GitHub check run, check suite, or commit status from GitHub or an integrated provider reports a non-successful result on the current head of a non-draft pull request, including failure, error, timed_out, cancelled, or action required.
routines:
  - Diagnose the triggering failing check using check logs, provider data, local reproduction, repo context, PR diff, and clear PR intent.
  - Push a focused evidence-grounded fix to the PR branch when the correct repo change is clear.
  - Coordinate with concurrent `pr-check-repair` activations before editing and before pushing.
  - Rerun a clearly flaky check when flake evidence is strong and no repo change is needed.
deny:
  - Do not refresh PR branches from base or resolve merge conflicts; use base only as read-only evidence when branch staleness affects the failing check.
  - Do not fix unrelated failing checks; assume each other failing check has its own `pr-check-repair` activation.
  - Do not make product, security, dependency, external-environment, production-data, backfill, or data-shape decisions solely to make checks pass.
  - Do not change external provider configuration, CI project settings, or secrets outside the repository.
  - Do not push speculative changes when the failure cause or intended fix is unclear.
  - Do not manually rerun checks after pushing a commit; rely on the push to trigger checks naturally.
  - Do not edit or act outside the triggering repo, PR, head SHA, and failing check.
  - Do not open new pull requests or new issues.
  - Do not submit PR reviews, approve, or request changes on pull requests.
  - Do not force-push.
---

# PR Check Repair

## Triggering-check scope policy

Handle only the triggering failing check. If another failing check shares the same root cause, fix that root cause only when necessary for the triggering check. If another human or `pr-check-repair` activation already fixed the same root cause, stop/no-op without commenting unless human action is still needed.

Expect parallel `pr-check-repair` activations for other failing checks. When overlap is plausible, refresh and inspect the current remote PR head before editing or pushing. When tools expose task status or transcripts, also inspect active/recent daemon activity.

## Repair decision policy

Fix and push when the triggering check is current, the cause is clear from available evidence, the fix does not require a product/security/infrastructure/dependency/data judgment call, and the commit can be pushed without overwriting concurrent work.

Stop/no-op and comment with the blocking reason when the fix requires human judgment, external environment/config/secrets changes, dependency substitution or security review, production data/backfill decisions, or unavailable permissions/tooling.

## Repair categories

| Category | Posture |
| --- | --- |
| `pre-commit` failures (`shellcheck`, `shfmt`, `biome-check`, `catalog-schema-validate`, `check-version-lockstep`, and core file-hygiene hooks) | Fix and push. |
| `cli-unit` failures (`pnpm exec tsc -p tsconfig.test.json`, `node --test dist-test/test/*.test.js`) | Fix implementation/tests/build inputs and push. |
| `bats-docker (ubuntu-22.04/24.04/26.04)` failures from `tests/docker/run.sh` | Fix installer/provisioner/CLI packaging/tests and push. |
| `gitleaks` full-history failures | If true secret exposure or rotation is required, stop/no-op and comment for human security action; if a false positive is clear with evidence, apply a narrow allowlist/fingerprint fix and push. |
| `PR Preview (website)` failures on website-path PRs (`index.html`, `assets/**`, `packaging/curl-installer/install.sh`, preview/deploy workflows) | Fix workflow/site logic and push when the failure is repo-caused. |
| CI/workflow YAML/action wiring errors introduced by the PR | Fix and push. |
| Flaky/transient infra failures with strong flake evidence | Rerun once when no repo change is needed; if persistent, stop/no-op and comment with the blocker. |
| External outages, missing secrets/permissions, or security/product decisions requiring human judgment | Stop/no-op and comment with required human action. |

## Branch and concurrency safety

- Re-fetch and verify the current remote PR head before starting edits.
- Re-fetch and verify the current remote PR head again before push.
- If remote PR head moved, re-evaluate before continuing. Continue after compatible human/daemon pushes, but never overwrite them.
- If branch staleness is the only failure cause, stop/no-op because branch refresh is outside `pr-check-repair` scope.
- If staleness is ambiguous, compare against current base when available. If base already fixes the issue and the PR branch is merely stale, do not push a repair commit.

## Comment policy

Comment only after a pushed fix, flaky rerun, or blocked state requiring human action. Include the triggering check, action taken or blocking reason, commit pushed or rerun performed, and next human action when blocked.

Do not comment for routine no-ops: stale triggers, checks already fixed, duplicate activations, another human/daemon already fixing the same root cause, or failures clearly owned by another daemon.
