---
name: catalog-schema
description: Use when adding, modifying, or validating a catalog entry under plugin/catalog/. Documents the JSON Schema layout, required fields, install.sh/uninstall.sh contract, symmetric uninstall (CLI-04), the "no agents installed by default" invariant (CAT-02), and the convention for adding a new agent without touching CLI source (CAT-03). Every install recipe runs via as_user — never sudo npm install -g. Grows once the schema is finalized in Phase 4.
---

# catalog-schema — Catalog entry format

**Status:** Skeleton. The stub schema at `plugin/catalog/schema.json` was seeded in Phase 1 (Plan 01-01). Phase 4 finalizes it and adds the first three catalog entries (`claude-code`, `gsd`, `playwright`). This skill grows with Phase 4 to absorb the final field list.

Authoritative spec: `docs/HARNESS.md` §5.2 (skill table). Decisions: ADR-003 (no default agents installed), ADR-004 (per-user npm prefix — every install recipe enforces it). Requirements this skill helps enforce: CAT-01, CAT-02, CAT-03, CLI-03, CLI-04, INST-04.

## When to use this skill

Use when the task touches any file under:

- `plugin/catalog/schema.json` — the JSON Schema.
- `plugin/catalog/catalog.json` — the catalog manifest (arrives Phase 4).
- `plugin/catalog/agents/<name>/install.sh` — per-agent install recipe.
- `plugin/catalog/agents/<name>/remove.sh` — per-agent symmetric uninstall.
- `plugin/catalog/agents/<name>/recipe.json` — per-agent metadata (arrives Phase 4).
- `plugin/cli/scripts/validate-catalog.mjs` — the validator.

## Why this exists (CAT-03)

New agents must be addable by submitting **only** a JSON catalog entry plus an install recipe — no CLI source changes, no TypeScript edits. The schema is the contract that enforces that. A PR that adds a new agent should not touch `plugin/cli/src/*.ts`. If it does, either the schema is missing a field or the CLI has a generic feature it should have grown.

## Current (Phase 1) schema shape

Mirrored from `plugin/catalog/schema.json`:

```json
{
  "version": "string",
  "agents": [
    {
      "name": "^[a-z][a-z0-9-]*$",
      "description": "string",
      "install": "string"
    }
  ]
}
```

- `additionalProperties: false` at both levels — strict by default.
- `name` is lowercase-kebab; used as the subdirectory under `plugin/catalog/agents/<name>/`.
- `version` is the catalog manifest version, not the agent version (agent versions are resolved at install time via npm / upstream).

## Planned Phase 4 extensions

Not binding; documented so Phase 4 has a starting point:

- `homepage` — optional canonical URL.
- `license` — SPDX identifier.
- `tags: string[]` — for grouping / filtering (`agentlinux list --tag browser`).
- `min_node_version` — refuse install if the agent user's Node is older.
- `env: { KEY: value }` — optional per-agent environment injection at install time.
- `install` becomes a path reference to `plugin/catalog/agents/<name>/install.sh` rather than a shell string.
- `remove` — optional path reference to `plugin/catalog/agents/<name>/remove.sh` (symmetric uninstall per CLI-04).
- `invocation_test` — a bats-friendly one-liner the post-install smoke test runs (seeds the AGT-XX tests).
- Top-level invariant check: catalog MUST NOT carry a field that says "installed by default." CAT-02 is enforced by schema absence; the installer simply never reads such a field.

## Install recipe contract

Every `plugin/catalog/agents/<name>/install.sh` MUST:

1. Start with `#!/usr/bin/env bash` and `set -euo pipefail` (same discipline as the installer — see `agentlinux-installer` skill).
2. Source `plugin/lib/as_user.sh` (or equivalent) and run every state-changing command via `as_user agent <cmd>`.
3. **Never** `sudo npm install -g`. The keystone ownership rule (ADR-004) is enforced at the install-recipe layer too.
4. Be idempotent — re-running `agentlinux install <name>` must converge (CLI-03).
5. Emit `log_info`, `log_error` (from `plugin/lib/log.sh`) for user-facing messages; no bare `echo`.
6. Return non-zero on any sub-step failure; do not swallow errors.
7. Write only under `$HOME/.npm-global/` or `$HOME/.local/` for the agent user. Never into `/usr/local/` (that path is the wrapper-shim trap the `security-engineer` and `catalog-auditor` rubrics flag).

Every `remove.sh` MUST be the symmetric inverse:

- Uninstalls the npm global package as the agent user.
- Removes any config files the install wrote.
- Is idempotent (running it twice is not an error).
- Leaves no files the install placed.

## Validation

Phase 1 ships `plugin/cli/scripts/validate-catalog.mjs` — a zero-dep structural validator (built-in `node:fs` + `JSON.parse`; see Plan 01-02 notes). It runs in pre-commit and blocks malformed entries.

Phase 4 upgrades it to ajv-based JSON Schema 2020-12 validation, with a separate check that every catalog entry has a matching `plugin/catalog/agents/<name>/install.sh` on disk and that the `install.sh` grep-passes the "no `sudo npm install -g`" rule. The `catalog-auditor` subagent runs those greps at review time.

## The CAT-02 invariant (no default agents)

**A fresh install of AgentLinux installs zero agents.** Every entry in the catalog is opt-in via `agentlinux install <name>`. This is non-negotiable — it's the point of the pivot from v0.2.0 (where Claude Code was baked into the image) to v0.3.0 (where the user chooses). Tests that assert "Claude Code is already installed after `agentlinux-install`" are bugs — the `behavior-coverage-auditor` flags them on every phase close.

## Growth plan

- **Phase 4:** Finalizes the schema, adds the three real entries (claude-code, gsd, playwright), upgrades `validate-catalog.mjs` to ajv, and ships the first install+remove recipes. This skill absorbs the final field list and concrete `install.sh` / `remove.sh` templates.
- **Phase 5:** First AGT-XX tests exercise every recipe. This skill adds the "what a working install.sh looks like" example section.
- **v0.4+:** Multiple install backends per entry (npm / apt / binary download / pipx — CAT-05 deferred). Remote-fetch catalog with embedded fallback (CAT-04 deferred). This skill grows backend-abstraction guidance at that point.

## Related

- `docs/HARNESS.md` §1.1 (plugin/catalog/ layout), §5.2 (skill table), §4.2 (catalog-auditor + security-engineer rubrics).
- ADRs: 003 (no default agents), 004 (per-user npm prefix), 008 (Commander.js CLI that consumes this catalog).
- Subagents: `catalog-auditor` (every catalog PR), `security-engineer` (install-recipe injection review).
- Sibling skills: `agentlinux-installer` (shares the `as_user` / idempotency discipline), `behavior-test-contract` (CAT-XX tests under `tests/bats/50-registry-cli.bats`).
- Validator: `plugin/cli/scripts/validate-catalog.mjs`.
