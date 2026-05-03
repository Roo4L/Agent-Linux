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
{"decision":"block","reason":"Before stopping: keep the linked Jira ticket in sync via the session-tracker skill (default project for this repo: AL on copiedwonder.atlassian.net, board 2). State-change triggers to apply this turn: PR/MR opened -> Sub-task to In Review (and link the PR URL); reviewer pushed back -> back to In Progress via Review unsuccessful; blocked on dep/decision -> On hold + comment; new deliverable scoped -> file a Sub-task under the anchor; PR merged or work accepted -> Sub-task to Done; all sub-tasks Done -> ask user before closing anchor Task. If no Jira ticket is linked to this session yet, the skill's session-start ritual decides whether to propose one. Skip and re-request stop if: research-only / Q&A session, no state change happened this turn, you already updated the ticket, or this turn changed only .planning/."}
JSON
