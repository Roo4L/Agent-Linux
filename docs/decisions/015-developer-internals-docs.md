# 015: Developer internals docs — embed in review loop, no new hook

**Status:** Accepted
**Date:** 2026-05-09
**Drives:** DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07
**Companion to:** ADR-010 (review loop via CLAUDE.md, refined 2026-05-02)

## Context

AL-22 ("Create documentation on what AgentLinux does") asks for developer-facing internal documentation explaining what each AgentLinux component does and why — with a product-perspective lens. The litmus question is *"What value does AgentLinux provide in installing GSD instead of using the GSD installation from npm directly?"* The docs must give the project owner a 60-second answer per surface and double as raw material for blog posts, marketing emails, and the agentlinux.org landing page.

Two adjacent decisions had to land alongside the docs themselves:

1. **How to keep the docs in sync with the source.** Documentation that drifts is worse than no documentation — it actively misleads. The codebase already has a review loop (CLAUDE.md "Review Loop" instruction + `.claude/agents/<reviewer>.md` subagents + ADR-010's reminder-hook refinement) that catches plugin/ source changes; it needs to learn about docs/internals/ too.
2. **Whether to add a third stop-hook.** The codebase has two reminder hooks today — `.claude/hooks/review-reminder.sh` (review-loop nudge) and `.claude/hooks/session-tracker-reminder.sh` (Jira nudge), both wired per the ADR-010 2026-05-02 refinement. A naive solution to docs sync would be a third hook. The maintainer pushed back: a third hook multiplies reminder noise without adding value, because the existing review-reminder already triggers the review loop and the review loop already routes plugin/ changes to reviewers.

## Decision

**Embed `dev-docs-auditor` (a new project-scoped reviewer subagent) in the existing review loop. Do NOT add a third stop-hook.**

Specifically:

1. Ship `docs/internals/` — one index doc + nine per-component docs (installer, agent-user, sudo-drop-in, nodejs-runtime, claude-code, gsd, playwright, registry-cli, catalog). Each follows a four-section contract: problem → AgentLinux's answer → value vs the naive approach → related cross-links. No source-line deep links; ADR mentions in prose are optional.
2. Ship `.claude/agents/dev-docs-auditor.md` — a read-only reviewer (`tools: Read, Grep, Glob, Bash`) that consumes a new `.claude/skills/dev-docs/SKILL.md` skill (the source-path → doc-path dispatch table + the four-section contract).
3. Wire the reviewer into the existing CLAUDE.md "Review Loop" reviewer-by-file-type table by extending three existing rows (Bash, TS/JS, Catalog recipes) — NOT by adding a new "Internal docs" row. Keeping the wiring inside the existing routing keeps the surface flat.
4. Make `docs/internals/` discoverable from the top-level `README.md` (a "Why AgentLinux — concepts" section + a "## Links" row).
5. NO new file under `.claude/hooks/`. NO edit to `.claude/settings.json`.

## Consequences

### What changes

- The review loop now flags missing or stale `docs/internals/<component>.md` updates whenever `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, or `packaging/curl-installer/` changes — without any new orchestration plumbing.
- The internals docs are explicitly *reference material*, not a release gate. The `dev-docs-auditor` does not gate phase close (no `## Exit behavior` section in its body); it documents drift for the main agent to triage.
- Skip conditions are explicit: pure refactors, comment-only changes, typo fixes, formatting-only diffs, `.planning/`-only changes, and tests-only changes do not require docs updates.

### Why no third hook

ADR-010's original 2026-04-18 critique — "subjective LLM review in a Stop hook wastes tokens" — applied to hooks that *spawn* reviewers. The 2026-05-02 refinement permits *reminder* hooks (one-shot via `stop_hook_active`, no reviewer spawn). A third reminder hook for docs sync was considered and rejected because:

- The existing `review-reminder.sh` already nudges Claude to run the review loop. Once the review loop runs, the reviewer-by-file-type routing table already routes plugin/ changes through `dev-docs-auditor`. A second nudge for the same loop is redundant.
- Each reminder hook costs at most one extra "block + re-stop" round-trip per turn (per ADR-010 §"Refinement"). Two reminders cost two round-trips; three cost three. The cost is real even though small.
- Reminder noise has a usability cost too — Claude reads each reminder reason and decides whether to act. More reasons mean longer reminder text means more turns where the reminder is mostly skipped, which trains the loop to ignore reminders generally.
- The maintainer drew the line at "no third hook" explicitly. Two hooks is a deliberate stopping point, not an accident.

### Why a flat extend, not a new CLAUDE.md section

Adding a top-level CLAUDE.md H2 like `## Internal docs review` would split the review-routing surface into two places (the existing "Review Loop" table + the new section). Future contributors would have to read both to know which reviewers fire on which file types. Extending three existing rows keeps the routing in one place.

### Reversibility

If `docs/internals/` proves not worth the maintenance overhead, the unwind is small:

- Delete `docs/internals/`.
- Remove `dev-docs-auditor` from the three CLAUDE.md "Review Loop" rows.
- Delete `.claude/agents/dev-docs-auditor.md` and `.claude/skills/dev-docs/`.
- Drop the README.md "Why AgentLinux — concepts" section + Links row.

No hook to retract, no settings.json edit to revert. The reversibility cost is bounded by design.

## References

- ADR-010 — Review loop via CLAUDE.md (the precedent this ADR builds on; refined 2026-05-02 to permit reminder hooks with `stop_hook_active` guard).
- `.planning/phases/12-developer-documentation-for-installer-runtime-and-cli-al-22/12-CONTEXT.md` — the user-decisions context that drove this design.
- `docs/internals/README.md` — the index doc this ADR drives.
- `.claude/agents/dev-docs-auditor.md` — the reviewer this ADR drives.
- `.claude/skills/dev-docs/SKILL.md` — the skill this ADR drives.
