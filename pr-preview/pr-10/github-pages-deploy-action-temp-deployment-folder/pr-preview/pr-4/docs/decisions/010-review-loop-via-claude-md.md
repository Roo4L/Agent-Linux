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
