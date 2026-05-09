---
quick_id: 260509-kn2
description: Add ai-deslop review agent and remove existing AI slop (AL-35)
status: complete
date: 2026-05-09
jira: AL-35
---

# Quick Task 260509-kn2 — SUMMARY

Implements [AL-35](https://copiedwonder.atlassian.net/browse/AL-35) on
branch `worktree-ai-deslop`.

## Outcome

- New project-scoped `ai-deslop` review subagent at
  `.claude/agents/ai-deslop.md` — flags tour-guide comments, defensive
  try/catch around trusted internal calls, `any`-cast workarounds,
  speculative validation past typed boundaries, backwards-compat shims,
  stylistic inconsistency, filler doc prose, and dead test scaffolding.
- Wired into `.claude/skills/review/SKILL.md` Dispatch table for every
  source file under `plugin/`, `tests/` (excluding bats specs),
  `packaging/`, and `docs/` (excluding ADRs and research summaries).
- `CLAUDE.md` §Review Loop reviewer-by-file-type table updated to match.
- Conservative one-time deslop pass on recently-merged code:
  - `tests/docker/dogfood.sh` — removed two tour-guide comments.
  - `plugin/cli/src/catalog/schema.ts` — collapsed `} catch { /* next */ }`
    to `} catch {}` in the schema-path search loop.

## Commits

- `9a831db` — feat(review): add ai-deslop reviewer + wire into review loop (AL-35)
- `8be9180` — chore(deslop): trim three tour-guide comments per ai-deslop rubric (AL-35)

## Verification

- `pre-commit run --files tests/docker/dogfood.sh plugin/cli/src/catalog/schema.ts` → all green (shellcheck, shfmt, biome, secret-scan).
- `pnpm --dir plugin/cli test` → 112/112 PASS, 0 fail.
- Behaviour-preserving: only comment removals + an empty-catch-block
  cosmetic collapse — no functional code change.

## Notes for the next contributor

The deslop pass on this branch was deliberately small. The recent
v0.3.0 work (AL-25 / AL-29 / AL-30 / AL-31 / AL-36 / AL-37) was already
mostly clean — most heavy comment blocks earn their place by explaining
non-obvious why-context (CJS/ESM Ajv interop, sed-not-jq rationale,
T-05.1-XX threat-model citations on `20-sudoers.sh`, AL-31 redirect
workaround on `dogfood.sh`). The new `ai-deslop` agent will keep that
discipline going forward without imposing it retroactively on prose
that's load-bearing.

The Jira ticket AL-35 was groomed before implementation: scope, explicit
out-of-scope list, deliverables, acceptance criteria, and Definition of
Done are now documented on the ticket. Status: In Progress.

The pre-existing `_pending_` row for `260503-8z4` in STATE.md is
unrelated to this task — leaving as-is.
