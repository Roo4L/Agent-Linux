#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../../.." && pwd)
skill="$root/.claude/skills/qa-testing/SKILL.md"
codex_link="$root/.codex/skills/qa-testing"
ledger="$root/.planning/phases/50-integration-qa/50-SCENARIO-LEDGER.md"

cd "$root"

test -s "$skill"
test -s "$ledger"
rg -qF '.claude/skills/qa-testing/' CLAUDE.md
test -L "$codex_link"
test "$(readlink "$codex_link")" = '../../.claude/skills/qa-testing'

catalog_ids=$(
  node <<'NODE'
const catalog = require('./plugin/catalog/catalog.json');
for (const entry of catalog.agents) console.log(entry.id);
NODE
)
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  rg -qF "\`$name\`" "$skill"
done <<<"$catalog_ids"

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

node - "$ledger" <<'NODE'
const fs = require('fs');
const catalog = require('./plugin/catalog/catalog.json');
const ledger = fs.readFileSync(process.argv[2], 'utf8');
const excluded = new Set(['openclaw', 'hermes-agent', 'test-dummy']);
const expected = catalog.agents.map((entry) => entry.id).filter((id) => !excluded.has(id));
const actual = [...ledger.matchAll(/^\| PKG-\d+ \| `([^`]+)`/gm)].map((match) => match[1]);
if (actual.length !== expected.length) {
  throw new Error(`ledger package row count mismatch: expected ${expected.length}, got ${actual.length}`);
}
if (new Set(actual).size !== actual.length) throw new Error('duplicate ledger package row');
const missing = expected.filter((id) => !actual.includes(id));
const extra = actual.filter((id) => !expected.includes(id));
if (missing.length || extra.length) {
  throw new Error(`ledger/catalog mismatch; missing=${missing.join(',')} extra=${extra.join(',')}`);
}
const rows = new Map([...ledger.matchAll(/^\| PKG-\d+ \| `([^`]+)` \| ([^|]+) \|/gm)]
  .map((match) => [match[1], match[2].trim().toLowerCase()]));
for (const entry of catalog.agents.filter((candidate) => !excluded.has(candidate.id))) {
  const expectedVersion = `${entry.pinned_version} / ${entry.source_kind}`.toLowerCase();
  if (rows.get(entry.id) !== expectedVersion) {
    throw new Error(`ledger catalog-field mismatch for ${entry.id}: expected ${expectedVersion}, got ${rows.get(entry.id) || '<missing>'}`);
  }
}
const actualExclusions = [...ledger.matchAll(/^\| `([^`]+)` \| [^|]+ \| excluded; not pass\/fail \|$/gm)]
  .map((match) => match[1]);
const actualExclusionSet = new Set(actualExclusions);
if (actualExclusions.length !== excluded.size || actualExclusionSet.size !== excluded.size ||
    [...excluded].some((id) => !actualExclusionSet.has(id))) {
  throw new Error(`ledger exclusion mismatch: expected exactly ${[...excluded].join(',')}, got ${actualExclusions.join(',')}`);
}
NODE

rg -qF '30 minutes' "$skill"
rg -qF 'latest 10' "$skill"
rg -qF 'clean for new-issue discovery' "$skill"
rg -qF 'productive' "$skill"
rg -qF 'known' "$skill"
rg -qF 'new' "$skill"
rg -qF 'observation' "$skill"
rg -qF 'blocked' "$skill"
rg -qF 'observation-only' "$skill"
rg -qF 'Coverage limits' "$skill"
rg -qF 'TERM=xterm-256color' "$skill"
rg -qF '80-column' "$skill"
rg -qF 'QEMU' "$skill"
rg -qF 'runtime' "$skill"
rg -qF 'redact' "$skill"
rg -qF 'does not count as a clean idea' "$skill"
if rg -n 'counts clean for discovery|counts as clean for novelty' "$skill"; then
  echo 'known-issue replay is incorrectly treated as clean' >&2
  exit 1
fi

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
