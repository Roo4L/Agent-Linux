# AgentLinux — Claude Code Guidance

@AGENTS.md

---

The shared, agent-neutral project context lives in `@AGENTS.md` above. This file
adds only the **Claude-Code-specific** mechanics. Codex CLI is supported
alongside Claude Code — see `docs/codex.md`.

## Review Loop — Claude Code host adapter

Run the shared review loop (per `AGENTS.md` > "Review Loop" and
`@docs/HARNESS.md` §4) through `.claude/skills/review/`. The skill is
agent-neutral; Claude Code supplies the native project-subagent dispatch while
Codex supplies its own. The skill contains the authoritative file-type → role
mapping, reviewer contract, and triage rules.

This instruction is the primary trigger, with a one-shot reminder at
`.claude/hooks/review-reminder.sh` as a backstop. ADR-010 (refined 2026-05-02)
still rejects reviewer-invoking hooks; reminder hooks with a
`stop_hook_active` guard remain allowed.

Main agent owns triage: fix what's valid, skip what's noise, and iterate until
the remaining comments are not actionable.

A Claude-only `pre-delivery-cleanup` pass may be used as an additive self-review
before an MR, but it does not replace the shared `$review` loop.

## Session Tracking — Claude Code

Track deliverables in Jira project **AL** per `@.claude/skills/session-tracker/SKILL.md`
(details in `AGENTS.md` > "Session Tracking"). A one-shot Stop-hook reminder at
`.claude/hooks/session-tracker-reminder.sh` (backstop, same ADR-010 refinement
that allows the review-reminder hook) nudges Claude to invoke the skill before
stopping. Skip for research-only / Q&A / `.planning/`-only sessions — request
stop again to pass through.

## Project skills

- `.claude/skills/qa-testing/` — reusable scoped integration-QA workflow with a
  productive-time/latest-10 regression-to-zero stop rule and representative
  PTY/TUI session.

---
*Last updated: 2026-07-18 — split shared context into `AGENTS.md`; this file now
carries Claude-Code-specific mechanics only.*
