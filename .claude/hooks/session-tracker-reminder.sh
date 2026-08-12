#!/usr/bin/env bash
# Stop hook: reminds Claude to run the session-tracker skill before stopping.
#
# Behavior:
#   - Reads the Stop-hook JSON envelope from stdin.
#   - If "stop_hook_active": true is present, exits 0 (one-shot guard so the
#     reminder fires at most once per turn — see ADR-010 Refinement 2026-05-02).
#   - Otherwise emits {"decision":"block","reason":"..."} on stdout. Claude
#     reads the reason, decides whether to invoke the session-tracker skill
#     (the hook does NOT invoke it — see ADR-010), then re-requests stop, at
#     which point stop_hook_active=true and we pass through.
#
# The reason string below condenses .claude/skills/session-tracker/SKILL.md >
# "Board visibility" + "State-change triggers". The skill is the source of truth;
# update both together or this drifts (it already did once).
#
# Smoke tests:
#   echo '{"stop_hook_active":false}' | bash .claude/hooks/session-tracker-reminder.sh
#     -> stdout contains '"decision":"block"', exit 0
#   echo '{"stop_hook_active":true}'  | bash .claude/hooks/session-tracker-reminder.sh
#     -> no stdout, exit 0
set -euo pipefail

input=$(cat)

if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

cat <<'JSON'
{"decision":"block","reason":"Before stopping: keep the linked Jira ticket in sync via the session-tracker skill. See CLAUDE.md > 'Session Tracking' for the project routing. Board visibility: the watched issue (the lone Task, the anchor Task, or the Task under the Epic) must pass through In Progress before any later state — a Jira automation rule promotes its card onto the board on that transition, and Backlog -> In Review or Backlog -> Done are legal hops that skip it, leaving finished work with no card. That rule lives in Jira, not this repo — if the card does not appear, report it rather than re-transitioning. State-change triggers to apply this turn (in a single-issue session apply the Subtask rows to the lone Task): work started on a Subtask -> that Subtask and the watched issue to In Progress; PR/MR opened -> Subtask to In Review (and link the PR URL); reviewer pushed back -> Subtask to In Progress, and the watched issue too if it had reached In Review; blocked on dep/decision -> comment with what is blocking and leave the status alone (Backlog only for a long-lived block); new deliverable scoped -> file a Subtask under the watched issue; PR merged or work accepted -> Subtask to Done; every Subtask In Review or Done with at least one not Done -> watched issue to In Review; all Subtasks Done -> ask the user before closing the watched issue. If no Jira ticket is linked to this session yet, the skill's session-start ritual decides whether to propose one. Skip and re-request stop if: research-only / Q&A session, no state change happened this turn, you already updated the ticket, or this turn changed only .planning/."}
JSON
