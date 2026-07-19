#!/usr/bin/env bash
# Codex Stop hook: reminds Codex to run AGENTS.md's Review Loop before stopping.
# Codex sibling of .claude/hooks/review-reminder.sh (kept separate — see docs/codex.md).
#
# Behavior (Codex Stop-hook contract):
#   - Reads the Stop-hook JSON envelope from stdin.
#   - If "stop_hook_active": true is present, exits 0 (one-shot guard so the
#     reminder fires at most once per turn — mirrors ADR-010 Refinement).
#   - Otherwise emits {"decision":"block","reason":"..."} on stdout. Codex reads
#     the reason, decides whether to run the shared project review skill with its
#     native subagents, then re-requests stop,
#     at which point stop_hook_active=true and we pass through.
#
# Smoke tests:
#   echo '{"stop_hook_active":false}' | bash .codex/hooks/review-reminder.sh
#     -> stdout contains '"decision":"block"', exit 0
#   echo '{"stop_hook_active":true}'  | bash .codex/hooks/review-reminder.sh
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
{"decision":"block","reason":"Before stopping: did you run the shared project $review skill on changed files? See AGENTS.md > 'Review Loop' and .codex/skills/review. Dispatch the file-type -> reviewer-role mapping via your native multi_agent spawn_agent tool (agent_type = role name, resolved from .codex/agents/*.toml); do not invoke the Claude CLI, and do not substitute the built-in `codex review` command. If you've already reviewed this session, or this turn changed only .planning/ (or made no code/doc changes worth reviewing), request stop again to pass through."}
JSON
