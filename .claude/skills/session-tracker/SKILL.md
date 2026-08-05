---
name: session-tracker
description: Track agent work sessions (Claude Code, Codex) in AL Jira (copiedwonder.atlassian.net) — propose tracking structure at session start, create Tasks/Subtasks for deliverables, and keep status in sync as work moves through In Progress / In Review / Done. Trigger at the start of a session that will produce a concrete deliverable (PR/MR, doc, decision artifact, ticket in another project), or mid-session when an already-tracked AL issue needs a status transition (PR opened, review bounced, blocked, merged). Do not trigger for research-only or Q&A sessions.
---

# Session Tracker

## When to track

Propose tracking when the session will produce concrete deliverables: a PR/MR, a doc, a decision artifact, an issue in another project. Skip for pure research, exploratory questions, or quick fixes that don't change anything reviewable. If the deliverable boundary is genuinely unclear, ask once before proceeding.

## Three granularity shapes

Pick one at session start. If scope grows mid-session, convert: single-issue → multi-deliverable means converting the existing Task into the anchor and filing new Subtasks under it; do not retro-rename the original Task.

1. **Single-issue session** — one AL Task. Use when the session produces one deliverable.
2. **Multi-deliverable session** — one Task as anchor + Subtasks per deliverable. Use when multiple things go through their own review cycles in parallel (e.g. multiple PRs land separately). Existing pattern: AL-18 (`Ship v0.3.0-rc12 — Phase 6 release pipeline complete`) + Subtasks AL-29/AL-30/AL-31 (one per upstream MR).
3. **Milestone session** — an existing Epic + new Task under it + Subtasks per phase/task. Use when working on a multi-phase milestone of this project.

## Issue description (required, never empty)

Every AL issue created by this skill — Task or Subtask — must have a description with at least these two sections, in this order:

- **Motivation** — why we are doing this. The problem it solves, the value it delivers, or what it unblocks. Understandable without implementation context.
- **Expected results** (a.k.a. acceptance criteria) — how we know it's done. Concrete deliverables, not activities. This is the acceptance check the user uses to close the issue.

Optionally add a **Solution Proposal** between the two when the approach matters. Use Jira wiki markup (`h2.` headers, `*` bullets). Never create an issue with an empty description, with only the summary repeated, or with placeholder text. The companion `jira-issues` skill has the full format and a worked example — reuse it.

## Session-start ritual

Run once before meaningful work begins:

1. **Decide.** Research-only? Skip and continue. Otherwise carry on.
2. **Find context.** Before creating anything, search AL:
   - Related work: `project = AL AND text ~ "<keyword>" ORDER BY updated DESC`
   - Active milestone epics: `project = AL AND issuetype = Epic AND statusCategory != Done`
   Look for an Epic the session naturally belongs under and Tasks that overlap.
3. **Propose a structure** to the user, e.g.:
   - "Single-issue: I'll create AL-NN — `<summary>`."
   - "Fits under epic AL-XX (`<title>`). I'll create a Task under it; we add Subtasks per PR as they appear."
   - "Continues AL-XX. I'll add a Subtask AL-NN — `<deliverable>`."
4. **Confirm**, then create. Write the description per the **Issue description** section above (Motivation + Expected results required). Assign to the user. Transition to `In Progress` immediately after creation — see **Board visibility**.

## Status mapping (AL workflow)

| Conceptual state | AL status | Transition to enter |
|---|---|---|
| Working on it | `In Progress` | id 21 — `In Progress` (global) |
| Awaiting review (user-side OR external team PR) | `In Review` | id 31 — `In Review` (global) |
| Bounced back from review | `In Progress` | id 21 — `In Progress` (global) |
| Finished/merged | `Done` | id 41 — `Done` (global) |
| Parked / not now | `Backlog` | id 2 — `Backlog` (global) |

AL has no dedicated `On hold` status. For short-lived blockers (waiting on a dependency, decision, or external team), leave the issue in its current status and add a comment with what's blocking and how it gets unblocked. For long-lived parking, move to `Backlog` (id 2).

The five transitions above are global on the AL workflow — they're available from any source status. Re-query transitions with `getTransitionsForJiraIssue` if uncertain — it also returns status-scoped ones this skill does not use (`Groomed` from `Backlog`, `Work started` from `To Do`, `Development complete` from `In Progress`, `Review successful` / `Review unsuccessful` from `In Review`). They are scoped by source status, not by issue type. Pick from the table above; ignore the rest.

Pass `transition.id` (not the status name) to `transitionJiraIssue`.

## Board visibility

AL is team-managed and board 2 keeps its backlog, so board membership is a list separate from status — creating an issue and transitioning it does not by itself put a card on the board. A Jira automation rule closes that gap: it fires on the transition to `In Progress` and moves the issue onto the board. So that transition is what makes a session visible, and a tracked issue left in `Backlog` misreports it as not started. **The watched issue must pass through `In Progress` before any later state.** Every transition in the table above is global, so `Backlog → In Review` and `Backlog → Done` are legal single hops — either one skips the promotion edge, and the issue then has no card even once the work is finished. Deliberate parking is the one exception to leaving `Backlog` — that is what the long-lived-block row below is for.

The board renders parent-level work items only, so Subtasks are not cards and the rule skips them. Exactly one issue per session is **the watched issue**: the lone Task in a single-issue session, the anchor Task in a multi-deliverable one, the Task under the Epic in a milestone session. Drive its status too, not just its Subtasks'; **State-change triggers** says when.

If the watched issue is `In Progress` but has no card, the promotion rule failed — say so and stop. Re-transitioning will not fix it, and no MCP tool can put a card on a board.

## State-change triggers

Update right after each trigger — don't batch. After every transition, log it in chat: `[jira] AL-NN → In Review (PR #NN)` so the user has a trail.

In a single-issue session, apply the Subtask rows to the lone Task — but close it with the confirmation gate from the last row, not the bare `Done` of the merge row.

| Trigger | Action |
|---|---|
| Work starts on a Subtask | Subtask → `In Progress` (21). Watched issue → `In Progress` (21), including back from `In Review`. |
| PR opened | Subtask → `In Review` (31). Add PR URL in the description or as a comment. |
| External reviewer pushed back ("needs changes") | Subtask → `In Progress` (21). Watched issue back to `In Progress` (21) if it had reached `In Review`. |
| Blocked on dep / decision / external team | Comment with what's blocking and how it gets unblocked; leave status as-is. If the block is long-lived, move to `Backlog` (2). |
| New deliverable scoped mid-session | Add a Subtask under the watched issue. It starts in `Backlog`; leave the watched issue where it is. |
| PR merged or work accepted | Subtask → `Done` (41). |
| Every Subtask is `In Review` or `Done`, and at least one is not `Done` | Watched issue → `In Review` (31). |
| All Subtasks Done | Watched issue → `Done` (41) after the user confirms. If it never reached `In Progress`, take it there first — closing straight from `Backlog` leaves finished work with no card. |

## Naming

- Anchor Task summary: deliverable-oriented. Examples from AL: `Ship v0.3.0-rc12 — Phase 6 release pipeline complete` (AL-18); `Bake a "ready-to-curl-install" Docker image to make dogfood retests one command` (AL-36).
- Subtask summary: mirror the parent Task's existing convention by inspecting its current children. Do not invent a prefix. AL-18's children use no prefix and embed the deliverable + cross-link directly (`Consolidate version-string SoT (plugin source + bats)`, `Fix four installer bugs blocking curl-pipe-bash on bare Ubuntu`). Embed cross-links (PR number, sibling project ticket) in the summary — the board reads by summary.

## Reference

- cloudId: `a06d8d18-fdca-4a38-beda-409bd9933626` (or pass `copiedwonder.atlassian.net`).
- Project: `AL` (team-managed Jira project, board 2). Board 2 keeps its backlog; a Jira automation rule promotes the issue to the board on the `In Progress` transition — see **Board visibility**. The rule is owned in Jira, not in this repo; nothing here can substitute for it.
- User accountId: `70121:6a2319ff-c197-4d3c-a414-a380c6cf95dc`.
- Epic linking: team-managed projects use the standard `parent` field — set `parent.key="AL-XX"` on a Task to link it under an Epic. There is no `Epic Link` customfield.
- Subtask creation: `createJiraIssue` with `issuetype.name="Subtask"` and `parent.key="AL-XX"`. Parent must be Task / Story / Bug — Subtasks cannot live directly under an Epic.
- Companion skill: `jira-issues` (description format, search-before-create rules). Don't duplicate that format here — reuse it.
