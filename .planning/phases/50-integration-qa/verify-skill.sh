#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/qa-testing/SKILL.md
codex_link=.codex/skills/qa-testing

test -s "$skill"
rg -qF '.claude/skills/qa-testing/' CLAUDE.md
test -L "$codex_link"
test "$(readlink "$codex_link")" = '../../.claude/skills/qa-testing'

for name in claude-code gsd playwright-cli codex gemini-cli opencode qwen-code \
  ccusage rtk gh glab trivy gitleaks sentry-cli chrome-devtools-mcp context7 \
  github-mcp sentry-mcp firecrawl-mcp slack-mcp linear-mcp jira-atlassian-mcp \
  spec-kit openclaw hermes-agent test-dummy; do
  rg -qF "\`$name\`" "$skill"
done

rg -qF '30 minutes' "$skill"
rg -qF 'latest 10' "$skill"
rg -qF 'productive' "$skill"
rg -qF 'known' "$skill"
rg -qF 'new' "$skill"
rg -qF 'blocked' "$skill"
rg -qF 'observation-only' "$skill"
rg -qF 'Coverage limits' "$skill"
rg -qF 'TERM=xterm-256color' "$skill"
rg -qF '80-column' "$skill"
rg -qF 'QEMU' "$skill"
rg -qF 'runtime' "$skill"
rg -qF 'redact' "$skill"

if rg -n 'QA_ROUND_MINUTES|QA_QUIET_ROUNDS|fixed round|fix.*during.*sweep' "$skill"; then
  echo 'obsolete round or inline-fix language found' >&2
  exit 1
fi
if rg -n '(OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY|GH_TOKEN|SENTRY_AUTH_TOKEN)=' "$skill"; then
  echo 'credential-looking assignment found' >&2
  exit 1
fi

bash -n "$0"
echo 'qa-testing skill self-check: PASS'
