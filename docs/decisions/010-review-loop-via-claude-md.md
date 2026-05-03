# 010: Review loop triggered by CLAUDE.md instruction, not a Stop hook

**Status:** Accepted
**Date:** 2026-04-18

## Context

The review feedback loop (main agent spawns reviewer subagents on task
completion, reads feedback, fixes what it agrees with, iterates) needs a reliable
trigger. Two options: (a) a CLAUDE.md instruction ("before reporting task
complete, run the review loop"), or (b) a Claude Code Stop hook that
programmatically invokes reviewers on every stop event.

## Decision

Trigger the review loop via a CLAUDE.md instruction. Do not use a Stop hook for
subjective LLM review. A lightweight Stop hook may still run *deterministic*
checks (pre-commit lint, unit tests for changed CLI files) in the future.

## Consequences

- Stop hooks fire on every stop (user interrupts, context limits, errors) — not
  just task completion. Subjective LLM review in a Stop hook wastes tokens. Deterministic
  checks (pre-commit) may still live in a future Stop hook.
- CLAUDE.md instruction is the Anthropic-recommended pattern and matches the
  ELS-OS reference and Spotify's Honk architecture.
- The review convention lives in `.claude/skills/review/SKILL.md` (arrives in
  Plan 01-03); CLAUDE.md points at it.
- A reminder Stop hook with `stop_hook_active` one-shot guard is allowed
  (see Refinement below); see `.claude/hooks/review-reminder.sh` and
  `.claude/hooks/session-tracker-reminder.sh`.

## Refinement — 2026-05-02 — Reminder hooks allowed

The original decision (2026-04-18) rejected Stop hooks on the grounds that
they "fire on every stop … wasting tokens." That concern targeted
**reviewer-invoking hooks** — hooks that programmatically spawn LLM
reviewers on every Stop event. That rejection stands.

This refinement permits a narrower variant: a **reminder hook** that
(a) reads the Stop-hook JSON envelope, (b) short-circuits via the
`stop_hook_active` one-shot guard, and (c) emits
`{"decision":"block","reason":"..."}` to nudge Claude to run the review
loop. The hook does *not* spawn reviewers; Claude does, after reading the
reason. Net cost: at most one extra "block + re-stop" round-trip per turn,
and zero cost on turns that need no review (Claude reads the reason and
immediately re-requests stop).

Why this is consistent with the original decision:

- **Reviewers still live in subagents owned by Claude.** The hook is text,
  not orchestration. ADR-010's "subjective LLM review in a Stop hook
  wastes tokens" critique applies to hooks that *run* the reviewers —
  this hook does not.
- **One-shot guard caps the cost.** `stop_hook_active: true` means the
  hook has already fired this turn; the script exits 0 immediately.
  Worst case is one extra reminder per turn, not one per stop event.
- **Claude decides whether the reminder applies.** The reason text lists
  the skip cases (already ran this session; .planning-only changes); the
  hook itself has no project knowledge.
- **CLAUDE.md instruction remains the primary trigger.** The hook is a
  backstop for the case where Claude forgets to consult CLAUDE.md before
  reporting complete.

Implementation: `.claude/hooks/review-reminder.sh` and
`.claude/hooks/session-tracker-reminder.sh`, both wired via
`.claude/settings.json` (project-shared) under the same Stop matcher block.
Each hook owns one reminder concern and short-circuits independently via
`stop_hook_active`; worst case is one extra "block + re-stop" round-trip per
hook per turn.
