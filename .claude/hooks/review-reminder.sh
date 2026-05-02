#!/usr/bin/env bash
# Stop hook: reminds Claude to run CLAUDE.md's Review Loop before stopping.
#
# Behavior:
#   - Reads the Stop-hook JSON envelope from stdin.
#   - If "stop_hook_active": true is present, exits 0 (one-shot guard so the
#     reminder fires at most once per turn — see ADR-010 Refinement 2026-05-02).
#   - Otherwise emits {"decision":"block","reason":"..."} on stdout. Claude
#     reads the reason, decides whether to spawn the project's reviewer
#     subagents (the hook does NOT spawn them — see ADR-010), then re-requests
#     stop, at which point stop_hook_active=true and we pass through.
#
# Smoke tests:
#   echo '{"stop_hook_active":false}' | bash .claude/hooks/review-reminder.sh
#     -> stdout contains '"decision":"block"', exit 0
#   echo '{"stop_hook_active":true}'  | bash .claude/hooks/review-reminder.sh
#     -> no stdout, exit 0
set -euo pipefail

input=$(cat)

if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

cat <<'JSON'
{"decision":"block","reason":"Before stopping: did you run the review feedback loop on changed files? See CLAUDE.md > 'Review Loop' and .claude/skills/review/SKILL.md. Spawn the AgentLinux reviewers that match the changed file types: bash-engineer + security-engineer + qa-engineer for Bash; node-engineer + security-engineer + qa-engineer for TS/JS; qa-engineer + behavior-coverage-auditor for Bats; catalog-auditor + security-engineer for catalog recipes. If you've already run them this session, or this turn changed only .planning/ (or made no code/doc changes worth reviewing), request stop again to pass through."}
JSON
