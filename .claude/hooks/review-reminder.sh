#!/usr/bin/env bash
# Stop hook: reminds the host agent to run the shared review skill before stopping.
#
# Behavior:
#   - Reads the Stop-hook JSON envelope from stdin.
#   - If "stop_hook_active": true is present, exits 0 (one-shot guard so the
#     reminder fires at most once per turn — see ADR-010 Refinement 2026-05-02).
#   - Otherwise emits {"decision":"block","reason":"..."} on stdout. The host
#     reads the reason, decides whether to dispatch the project's reviewer roles
#     with its native subagents (the hook does NOT spawn them — see ADR-010), then re-requests
#     stop, at which point stop_hook_active=true and we pass through.
#
# Smoke tests:
#   echo '{"stop_hook_active":false}' | bash .claude/hooks/review-reminder.sh
#     -> stdout contains '"decision":"block"', exit 0
#   echo '{"stop_hook_active":true}'  | bash .claude/hooks/review-reminder.sh
#     -> no stdout, exit 0
set -euo pipefail

input=$(cat)

stop_hook_active=false
if command -v node >/dev/null 2>&1; then
  stop_hook_active=$(printf '%s' "$input" | node -e 'let input=""; process.stdin.on("data", chunk => { input += chunk; }); process.stdin.on("end", () => { try { process.stdout.write(JSON.parse(input).stop_hook_active === true ? "true" : "false"); } catch { process.stdout.write("false"); } });')
fi

if [[ "$stop_hook_active" == true ]]; then
  exit 0
fi

cat <<'JSON'
{"decision":"block","reason":"Before stopping: did you run the shared project $review skill on changed files? See AGENTS.md > 'Review Loop' and .claude/skills/review/SKILL.md. Use the host's native subagents and the skill's file-type -> reviewer-role mapping; do not invoke the built-in codex review command or another agent's CLI. If you've already run it this session, or this turn changed only .planning/ (or made no code/doc changes worth reviewing), request stop again to pass through."}
JSON
