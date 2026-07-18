#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../../.." && pwd)
skill="$root/.claude/skills/qa-testing/SKILL.md"
codex_link="$root/.codex/skills/qa-testing"

cd "$root"

test -s "$skill"
rg -qF '.claude/skills/qa-testing/' CLAUDE.md
test -L "$codex_link"
test "$(readlink "$codex_link")" = '../../.claude/skills/qa-testing'

for name in $(node - <<'NODE'
const catalog = require('./plugin/catalog/catalog.json');
for (const entry of catalog.agents) console.log(entry.id);
NODE
); do
  rg -qF "\`$name\`" "$skill"
done

node - <<'NODE'
const catalog = require('./plugin/catalog/catalog.json');
const excluded = new Set(['openclaw', 'hermes-agent', 'test-dummy']);
const ids = new Set(catalog.agents.map((entry) => entry.id));
if (ids.size !== catalog.agents.length) throw new Error('duplicate catalog IDs');
for (const id of excluded) if (!ids.has(id)) throw new Error(`missing exclusion: ${id}`);
if (catalog.agents.filter((entry) => excluded.has(entry.id)).length !== 3) {
  throw new Error('catalog exclusion count changed');
}
if (catalog.agents.filter((entry) => !excluded.has(entry.id)).length !== 23) {
  throw new Error('included catalog count changed; reconcile the QA scope');
}
NODE

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

bash -n "$script_dir/verify-skill.sh"
echo 'qa-testing skill self-check: PASS'
