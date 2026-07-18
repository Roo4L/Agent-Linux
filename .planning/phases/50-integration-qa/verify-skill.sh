#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SKILL="$ROOT/.claude/skills/qa-testing/SKILL.md"
LINK="$ROOT/.codex/skills/qa-testing"

test -s "$SKILL"
grep -q 'qa-testing' "$ROOT/CLAUDE.md"
grep -q 'qa-testing' "$ROOT/AGENTS.md"
test -L "$LINK"
test "$(readlink "$LINK")" = "../../.claude/skills/qa-testing"

for needle in \
  'Scoped' \
  'Regression-to-zero' \
  'real interactive PTY' \
  'TERM=xterm-256color' \
  '80-column' \
  'QA_ROUND_MINUTES' \
  'QA_QUIET_ROUNDS' \
  'Coverage limits' \
  'direct' \
  'adjacent' \
  'QEMU' \
  'TST-08'; do
  grep -qF "$needle" "$SKILL"
done

if grep -Eq '(OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY)=' "$SKILL"; then
  printf 'qa-testing skill contains a credential-looking assignment\n' >&2
  exit 1
fi

bash -n "${BASH_SOURCE[0]}"
printf 'qa-testing skill self-check: PASS\n'
