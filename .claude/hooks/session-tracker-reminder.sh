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
{"decision":"block","reason":"Before stopping: did this session produce a concrete deliverable (MR, doc, decision artifact, ticket) that should be tracked in Jira? See .claude/skills/session-tracker/SKILL.md. The default project for this repo is AL (copiedwonder.atlassian.net, board 2). If yes, propose a tracking structure (single-issue / multi-deliverable / milestone) and create the Task / Sub-task with Motivation + Expected results, then transition to In Progress (or In Review if an MR is already open). If this was research-only / Q&A / .planning-only / no reviewable change, or you've already tracked this session, request stop again to pass through."}
JSON
