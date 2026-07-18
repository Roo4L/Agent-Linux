#!/usr/bin/env bash
# Codex Stop hook: reminds Codex to run AGENTS.md's Review Loop before stopping.
# Codex sibling of .claude/hooks/review-reminder.sh (kept separate — see docs/codex.md).
#
# Behavior (Codex Stop-hook contract):
#   - Reads the Stop-hook JSON envelope from stdin.
#   - If "stop_hook_active": true is present, exits 0 (one-shot guard so the
#     reminder fires at most once per turn — mirrors ADR-010 Refinement).
#   - Otherwise emits {"decision":"block","reason":"..."} on stdout. Codex reads
#     the reason, decides whether to run its review pass, then re-requests stop,
#     at which point stop_hook_active=true and we pass through.
#
# Smoke tests:
#   echo '{"stop_hook_active":false}' | bash .codex/hooks/review-reminder.sh
#     -> stdout contains '"decision":"block"', exit 0
#   echo '{"stop_hook_active":true}'  | bash .codex/hooks/review-reminder.sh
#     -> no stdout, exit 0
set -euo pipefail

input=$(cat)

if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

cat <<'JSON'
{"decision":"block","reason":"Before stopping: did you run the review loop on changed files? See AGENTS.md > 'Review Loop'. In Codex, run `codex review` for a review pass, using the file-type -> concern mapping as a checklist (bash -> shellcheck/idempotency/quoting/set -euo pipefail/no sudo npm install -g; TS/JS -> type safety + error handling; bats -> behavior coverage; catalog recipes -> schema + symmetric uninstall + no /usr/local shims; docs -> accuracy + no internal-vocab leakage). Codex has no equivalent to the project reviewer subagents — that deep multi-agent loop is Claude Code's. If you've already reviewed this session, or this turn changed only .planning/ (or made no code/doc changes worth reviewing), request stop again to pass through."}
JSON
