---
name: review
description: Runs the AgentLinux review feedback loop on changed files before declaring a task complete. Spawns project-scoped subagents (bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor, ai-deslop) in parallel, aggregates free-form feedback, and re-runs until remaining comments are not actionable. Triggered by CLAUDE.md review-loop instruction (ADR-010) — not a Stop hook. Invoke after any substantive change to plugin/, tests/, or docs/.
---

# /review — AgentLinux Review Feedback Loop

The backpressure mechanism that keeps the bash installer, Node CLI, bats suite, and catalog honest. At the end of every non-trivial task, the main agent spawns the right reviewer subagents in parallel, reads their feedback, triages (fix / skip / stop), and iterates until the remaining comments are not actionable.

Authoritative spec: `docs/HARNESS.md` §4. This skill is the operational runbook.

## When to use this skill

Use it at the end of every task where the agent modified code, tests, or reference documentation. Skip it for:

- Typo fixes and formatting-only changes
- Pure `.planning/` edits (PLAN.md, STATE.md, ROADMAP.md — GSD workflow state does not go through content review)
- `.planning/notes/` scratch files

Use it always for:

- Anything under `plugin/` (installer, CLI, catalog recipes)
- Anything under `tests/` (bats, docker, qemu, harness)
- Anything under `docs/` worth preserving (ADRs, HARNESS, research, proposals)
- Packaging (`packaging/curl-installer/install.sh`, `.deb` builder)
- **End of every phase** — always spawn `behavior-coverage-auditor` regardless of what changed (TST-07 gate).

## The loop

```
Main agent completes task
  │
  ├─ Look at what was produced (bash, TS, bats, docs, catalog recipes, or mix)
  │
  ├─ Spawn appropriate review subagents in parallel (see Dispatch rules below)
  │
  ├─ Collect free-form summaries from each reviewer
  │
  ├─ Triage each comment:
  │     ├── valid + actionable → fix
  │     ├── irrelevant / already addressed / contradictory → skip
  │     └── out of scope for current task → log to deferred-items.md
  │
  ├─ Apply valid fixes
  │
  ├─ Re-spawn reviewers (only those whose domain was touched by the fix)
  │
  └─ Stop when remaining comments are not actionable
```

No artificial iteration cap. Main agent owns the triage decision — reviewers are advisors, not gatekeepers.

## Dispatch rules

Map changed files to subagents. The main agent inspects `git diff --name-only` (or equivalent) and spawns the intersection set.

| Changed file pattern | Subagents to spawn |
|----------------------|--------------------|
| `^plugin/(bin\|lib\|provisioner)/.+\.sh$` | bash-engineer + security-engineer + qa-engineer + ai-deslop |
| `^packaging/curl-installer/.+\.sh$` | bash-engineer + security-engineer + ai-deslop (always — trust-critical surface) |
| `^plugin/cli/(src\|test\|scripts)/.+\.(ts\|mjs\|js)$` | node-engineer + security-engineer + qa-engineer + ai-deslop |
| `^plugin/cli/(package\.json\|tsconfig\.json\|biome\.json\|stryker\.config\.json)$` | node-engineer |
| `^tests/bats/.+\.bats$` | qa-engineer + behavior-coverage-auditor (the spec is the spec — no ai-deslop) |
| `^tests/bats/helpers/.+$` | qa-engineer + bash-engineer + ai-deslop (helpers are bash) |
| `^tests/(docker\|qemu\|harness)/.+$` | qa-engineer + bash-engineer + ai-deslop |
| `^plugin/catalog/(agents/.+/.+\.(sh\|json)\|catalog\.json\|schema\.json)$` | catalog-auditor + security-engineer + ai-deslop (+ bash-engineer if install.sh/remove.sh) |
| `^docs/.+\.md$` (excluding ADRs and research summaries) | global `review-documentation` + `fact-checker` (if available) + ai-deslop |
| `^docs/decisions/.+\.md$` and `^docs/research/.+/SUMMARY\.md$` | global `review-documentation` + `fact-checker` (load-bearing prose — no ai-deslop) |
| `^\.planning/REQUIREMENTS\.md$` | behavior-coverage-auditor (IDs may have drifted from tests) |
| **End-of-phase close** | behavior-coverage-auditor (always, TST-07 gate) |

Parallelism note: when multiple subagents are dispatched, spawn them as independent Task-tool invocations in a single tool block so they run in parallel. Aggregate after all return.

## Triage rules (main agent keeps authority)

- **Fix** — the reviewer flags a concrete, verifiable issue:
  - shellcheck warning
  - missing idempotency primitive (`echo >> file` instead of `ensure_line_in_file`)
  - uncovered requirement ID (BHV/RT/AGT/CLI/CAT/INST)
  - sudoers drop-in with mode ≠ 0440
  - `sudo npm install -g` anywhere (instant fix, no debate)
  - `/usr/local/bin/<tool>` shim pointing at agent-owned binary
  - test with only exit-code assertion
- **Skip** — the reviewer asks for a stylistic change that:
  - contradicts another reviewer's suggestion
  - is already addressed elsewhere in the change
  - is a preference without a concrete failure mode
- **Stop** — remaining comments are:
  - stylistic preference
  - out of the current task's scope (log to `deferred-items.md` in the phase dir)
  - would require more work than the current plan allocates

The main agent is the decider. Reviewers produce input; the main agent ships.

## Trigger mechanism

**This loop is triggered by the CLAUDE.md review-loop instruction** (see CLAUDE.md §Review Loop). Not a Stop hook. Per **ADR-010** (`docs/decisions/010-review-loop-via-claude-md.md`):

- Stop hooks fire on every stop — user interrupts, context limits, errors — not just task completion. Subjective LLM review in a Stop hook wastes tokens and confuses the user when they hit Ctrl+C.
- CLAUDE.md instruction is the Anthropic-recommended pattern and matches the ELS-OS reference and Spotify's Honk architecture.
- A future lightweight Stop hook may still run **deterministic** checks (pre-commit, CLI unit tests on changed `plugin/cli/` files) per `docs/HARNESS.md` §4.4 — not subjective LLM review.

## Relation to TST-07

`behavior-coverage-auditor` is the acceptance gate for every phase from Phase 2 onward. **TST-07 requires it to run at the end of every phase.** This skill explicitly lists that requirement so the main agent does not forget to spawn it at phase-close.

At phase close:

1. Spawn `behavior-coverage-auditor` unconditionally.
2. Read the report. Look for the `TST-07 gate: RED|GREEN` line at the bottom.
3. If RED — uncovered BHV/RT/AGT/CLI/CAT/INST requirements exist — add tests or document the deferral with an ADR before closing the phase.
4. If GREEN — phase can close; auditor output goes in `docs/reviews/phase-NN-coverage.md` if worth preserving.

## Reviewer principles (reminder)

Copy-of-truth from `docs/HARNESS.md` §4.3:

1. **Free-form output.** Reviewers produce a summary with comments, action points, and observations. No rigid BLOCK/FLAG/PASS structure — the main agent interprets relevance and severity.
2. **Scoped context.** Each reviewer loads only the files relevant to its review, not the full conversation history.
3. **Main agent owns triage.** Decides what to fix, what to skip, when the output is good enough.

## Related

- `docs/HARNESS.md` §4 — authoritative spec
- `docs/decisions/010-review-loop-via-claude-md.md` — trigger mechanism rationale (ADR-010)
- `.claude/agents/{bash-engineer,node-engineer,security-engineer,qa-engineer,behavior-coverage-auditor,catalog-auditor,ai-deslop}.md` — the seven subagents this skill dispatches
- Global `pre-delivery-cleanup` skill — pre-MR self-deslop pass that pairs with `ai-deslop`
- `CLAUDE.md` §Review Loop — the instruction that triggers this skill
