#!/usr/bin/env bash
# Codex Stop hook: reminds Codex to run the session-tracker skill before stopping.
#
# Codex-specific sibling of .claude/hooks/session-tracker-reminder.sh (kept
# separate — see .codex/hooks/review-reminder.sh header and docs/codex.md).
#
# Behavior (Codex Stop-hook contract):
#   - Reads the Stop-hook JSON envelope from stdin.
#   - If "stop_hook_active": true is present, exits 0 (one-shot guard).
#   - Otherwise emits {"decision":"block","reason":"..."} on stdout. Codex reads
#     the reason, decides whether to invoke the session-tracker skill (the hook
#     does NOT invoke it), then re-requests stop, at which point
#     stop_hook_active=true and we pass through.
#
# Note: session tracking writes to Jira via the Atlassian MCP server, which must
# be registered in ~/.codex/config.toml for Codex (see docs/codex.md). Without it
# the skill degrades gracefully — Codex simply cannot reach Jira.
#
# Smoke tests:
#   echo '{"stop_hook_active":false}' | bash .codex/hooks/session-tracker-reminder.sh
#     -> stdout contains '"decision":"block"', exit 0
#   echo '{"stop_hook_active":true}'  | bash .codex/hooks/session-tracker-reminder.sh
#     -> no stdout, exit 0
set -euo pipefail

input=$(cat)

if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

cat <<'JSON'
{"decision":"block","reason":"Before stopping: keep the linked Jira ticket in sync via the session-tracker skill (.codex/skills/session-tracker). See AGENTS.md > 'Session Tracking' for the project routing (Jira project AL). State-change triggers to apply this turn: PR/MR opened -> Sub-task to In Review (and link the PR URL); reviewer pushed back -> back to In Progress (Review unsuccessful); blocked on dep/decision -> On hold + comment; new deliverable scoped -> file a Sub-task under the anchor; PR merged or work accepted -> Sub-task to Done; all sub-tasks Done -> ask user before closing anchor Task. If no Jira ticket is linked to this session yet, the skill's session-start ritual decides whether to propose one. Skip and re-request stop if: research-only / Q&A session, no state change happened this turn, you already updated the ticket, this turn changed only .planning/, or the Atlassian MCP server is not configured for Codex."}
JSON
