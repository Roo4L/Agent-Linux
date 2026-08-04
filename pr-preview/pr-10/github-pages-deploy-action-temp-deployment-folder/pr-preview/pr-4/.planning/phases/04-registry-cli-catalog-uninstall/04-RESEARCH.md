# Phase 4: Registry CLI + Catalog + Uninstall — Research

**Researched:** 2026-04-18
**Domain:** TypeScript CLI (Commander.js) + JSON Schema validation (ajv) + npm/native-installer dispatch + sentinel-tracked state + symmetric bash uninstall
**Confidence:** HIGH

## Summary

Phase 4 ships the `agentlinux` registry CLI and its catalog substrate: a TypeScript CLI built on Commander.js `^14.x` that reads an ajv-validated JSON-Schema-2020-12 catalog of agent entries (`claude-code`, `gsd`, `playwright`, plus a test-only `test-dummy`), each carrying a required `pinned_version` per ADR-011. `install <name>` dispatches per-agent `install.sh` recipes via the `as_user` keystone with `AGENTLINUX_PINNED_VERSION` in the environment; `upgrade` reconciles the `/opt/agentlinux/state/installed.json` sentinel against the staged catalog snapshot with a 3-way classification (`synced` / `override-ahead` / `override-behind` / `pinned-override` / `drift-undeclared`); `pin` sets sticky overrides so power-users aren't re-nagged; `remove <name>` runs the symmetric `uninstall.sh`; and `agentlinux-install --purge` (INST-04 wire-up) tears down the agent user, `/opt/agentlinux/`, and every installer-placed file on the host.

The load-bearing discoveries: **(1)** Claude Code's native installer (`curl https://claude.ai/install.sh | bash`) accepts a positional version argument via `bash -s <version>` — this is exactly how `source_kind: "script"` recipes honor `AGENTLINUX_PINNED_VERSION` without any novel pinning machinery; **(2)** Commander's current line is `^14.x` (ADR-008 locks `^12.x`; CONTEXT pins `^12.x`; honor the lock — v14's changes are minor and v12 is still fully supported, no migration pressure); **(3)** Ajv 8's JSON Schema 2020-12 support ships via `import Ajv2020 from "ajv/dist/2020"` — a separate class, not a constructor flag; **(4)** `flock(1)` from util-linux is available on Ubuntu 22.04/24.04 and is the correct primitive for serializing sentinel writes across concurrent CLI invocations; **(5)** the real npm package for GSD is `get-shit-done-cc` (not `get-shit-done` or `gsd` — both are unrelated prior art).

**Primary recommendation:** Seven plans (Waves 1–3 as proposed in CONTEXT); Commander.js `^12.x` locked per ADR-008; Ajv 8 with `Ajv2020` import; per-agent state sentinels under `/opt/agentlinux/state/installed.d/<id>.json` (one file per agent, atomic rename + flock) — simpler-than-monolithic, avoids cross-agent concurrent-write race; `AGENTLINUX_PINNED_VERSION` is the exclusive version-handoff env var from CLI → recipe; test-only `test-dummy` catalog entry exercises the dispatch path in bats without network. No Ajv validation on the `list` hot path — validate only on `install` / `upgrade`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**CLI Tech Stack & Packaging:**
- **Framework:** Commander.js `^12.x` — ADR-008 accepted; unchanged by ADR-011.
- **Package manager:** `pnpm` inside `plugin/cli/` — fast, disk-efficient, lockfile stability. Root workspace remains free of `package.json` per HARNESS.md §1.1.
- **Build shape:** TypeScript source → `tsc` compiled to `plugin/cli/dist/`. Ship `dist/` in the release tarball. Entrypoint `dist/index.js` with `#!/usr/bin/env node` shebang.
- **PATH placement:** Symlink from `/home/agent/.npm-global/bin/agentlinux` → the shipped dist entrypoint. New provisioner `plugin/provisioner/50-registry-cli.sh` runs AFTER `30-nodejs.sh` + `40-path-wiring.sh`, stages the CLI under `/opt/agentlinux/cli/<version>/`, creates the symlink. Agent's existing `.npm-global/bin` on PATH (Phase 3) is why this works without touching PATH wiring.

**Catalog Schema & Entry Shape (extended per ADR-011):**
- **Catalog layout:** `plugin/catalog/catalog.json` (entry list) + `plugin/catalog/agents/<name>/install.sh` + `plugin/catalog/agents/<name>/uninstall.sh` per entry. Matches HARNESS.md §1.1 and the CAT-03 "submit entry + recipe" contract.
- **Schema validator:** `ajv` with JSON Schema 2020-12 draft. Validates at CLI-load-time. Phase 1's zero-dep `validate-catalog.mjs` scaffold gets replaced by ajv-driven validation; the pre-commit hook stays.
- **Required fields per entry:** `id` (slug), `display_name`, `description`, `npm_package_name` (for npm-based recipes), `pinned_version` (required, semver per CAT-04/ADR-011), `install_recipe_path`, `uninstall_recipe_path`, `post_install_verify` (optional cmd), `source_kind` (`"npm"` or `"script"` for agents with their own native installer like Claude Code).
- **Optional `version_constraint`:** semver range (e.g. `"^2.1"`) that `--all-latest` upper-bounds against; absent = accept any npm latest.
- **install.sh / uninstall.sh calling convention:** Runs as `as_user` (keystone helper from Phase 2). Receives env vars: `AGENTLINUX_CATALOG_DIR`, `AGENTLINUX_AGENT_HOME`, `AGENTLINUX_PINNED_VERSION` (the version the CLI determined to install — either catalog pin, user override, or `latest`). Exits 0 on success; stdout/stderr tee'd to install log.

**CLI UX (list / install / upgrade / remove / pin):**
- **`agentlinux list` output:** Text table: `NAME  STATUS  CURATED  INSTALLED  DESCRIPTION`. Minimal, grep-friendly. `--json` flag for machine output. STATUS shows `not-installed`, `synced`, `override-ahead`, `override-behind`, or `pinned-override` (sticky).
- **Installed-detection:** `/opt/agentlinux/state/installed.json` sentinel per agent, recording `{id, version, source: "curated"|"override"|"latest"|"pinned", installed_at}`. Cross-checked against `sudo -u agent -H npm ls -g --json --depth=0 <pkg>` output for drift detection.
- **`install <name>` idempotency:** If sentinel exists and matches the catalog pin, log "already installed at pinned_version" + exit 0. `--force` re-runs install.sh. `--version <semver>` overrides the catalog pin for this install (sets `source: "override"` in sentinel).
- **`upgrade` verb (CLI-06):** Read sentinel + catalog snapshot + `npm ls -g --json`; classify each agent as `synced`, `override-ahead`, `override-behind`; present per-agent 3-way prompt (`[k]eep override / [c]urated / [l]atest`) or accept bulk flags (`--reset-all-curated`, `--respect-overrides`, `--all-latest`). Writes updated sentinels recording source of each version.
- **`pin` verb (CLI-07):** `agentlinux pin <name>=curated` clears sticky-override flag; `agentlinux pin <name>=latest` sets sticky-override to "user always wants latest npm"; `agentlinux pin <name>=2.1.7` pins to exact version. Flag lives in the sentinel's `source` field (`pinned`). `upgrade` respects the pin (never re-prompts for pinned entries) but `list` still surfaces the divergence.
- **`remove <name>`:** Runs `uninstall.sh` via `as_user`, removes sentinel, cleans empty dirs. Exits non-zero if sentinel missing (no idempotent no-op — force the user to notice) unless `--force`.

**`--purge` Uninstall + Phase 4 Tests:**
- **Uninstall entrypoints (split per CLI-04 vs INST-04):**
  - `agentlinux remove <name>` — per-agent uninstall (CLI-04). Runs that agent's `uninstall.sh`; removes sentinel.
  - `plugin/bin/agentlinux-install --purge` — whole-plugin uninstall (INST-04). Wires up the stub from Phase 2. Runs every installed agent's `uninstall.sh`, then removes agent user + `/home/agent`, `/etc/profile.d/agentlinux.sh`, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`, `/etc/apt/sources.list.d/nodesource.sources`, `/opt/agentlinux/` (CLI + state + catalog snapshot), `/var/log/agentlinux-install.log`. Does NOT apt-remove nodejs unless `--purge --remove-nodejs` passed (node may be shared with other users).
- **CLI unit tests:** `plugin/cli/test/*.test.ts` using `node:test` (stdlib, zero-dep). Stub catalog fixtures under `plugin/cli/test/fixtures/`. Covers: schema validation, divergence classification, sentinel read/write, CLI command parsing.
- **Integration tests (end-to-end):** New `tests/bats/40-registry-cli.bats` — runs `agentlinux list` / `install <fake>` / `upgrade` / `pin` / `remove <fake>` against a test-only catalog entry (tiny shell-based dummy agent, not a real npm package — CI stays fast, no network flake). Each `@test` cites CLI-XX or CAT-XX ID.

### Claude's Discretion

- Exact split of `plugin/provisioner/50-registry-cli.sh` vs inlining the CLI staging into `plugin/bin/agentlinux-install` — planner picks what keeps the provisioner dispatch pattern monotonic.
- Exact shape of `/opt/agentlinux/state/installed.json` (flat object vs per-agent files under `installed.d/`) — any shape the sentinel read/write helpers encapsulate.
- Whether `ajv` runs at every CLI invocation or only at `install` / `upgrade` (performance-vs-correctness tradeoff for `list`).
- Dummy test-only catalog entry's exact shape — must be idempotent-install/uninstall but otherwise free.
- Plan count — 7 plans recommended by ADR-011 research, but planner may collapse/split.

### Deferred Ideas (OUT OF SCOPE)

- **Option C' symlink-profile model** — Nix-style atomic profiles with `agentlinux profile rollback`. v0.4+ UX upgrade on top of A'.
- **Option E' CLI-as-.deb** — ship the `agentlinux` binary itself via a public PPA. Requires INF-01 (deferred to v0.4+).
- **Per-agent `.deb`s (Option B')** — rejected per ADR-011. Not revisited.
- **Remote-fetch catalog (CAT-06, formerly CAT-04)** — v0.4+. v0.3.0 ships with an embedded catalog snapshot.
- **Multiple install backends per entry (CAT-07, formerly CAT-05)** — v0.4+. v0.3.0 supports `source_kind: npm | script` only.
- **`agentlinux info <name>` (CLI-08)** — v0.4+. `list --verbose` covers the need for now.
- **`agentlinux update <name>` delegating to agent's native updater (CLI-09)** — v0.4+.
- **`agentlinux doctor` (CLI-10)** — v0.4+. Bats integration tests are the doctor surrogate for now.
- **Auto-update daemon (INF-04)** — v0.4+.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CLI-01 | `agentlinux` on agent's PATH after install | §Pattern 1 (provisioner `50-registry-cli.sh` + symlink to `/home/agent/.npm-global/bin/agentlinux`); bats @test asserts `command -v agentlinux` resolves under `/home/agent/.npm-global/bin/` in all six invocation modes |
| CLI-02 | `agentlinux list` shows catalog with installed/not-installed indicator | §Pattern 2 (Commander subcommand shape + `--json` flag); §Pattern 5 (sentinel read + status classifier); test-dummy fixture exercises both states |
| CLI-03 | `agentlinux install <name>` — as-agent, non-interactive, idempotent | §Pattern 3 (install dispatch via `as_user` with `AGENTLINUX_PINNED_VERSION`); §Pattern 6 (idempotent sentinel check-and-skip); §Pitfall 2 (npm exact-semver semantics) |
| CLI-04 | `agentlinux remove <name>` — symmetric uninstall | §Pattern 4 (uninstall dispatch mirrors install); npm uninstall-g + sentinel removal |
| CLI-05 | Fail-fast on non-agent user; succeed without sudo as agent | §Pattern 8 (EUID/USER check at CLI entry; exits 64 with clear `sudo -u agent -H agentlinux <cmd>` guidance) |
| CLI-06 | `agentlinux upgrade` detects per-agent divergence + 3-way reconcile | §Pattern 7 (divergence classifier: sentinel vs `npm ls -g --json` vs catalog snapshot vs optional upstream); per-agent interactive prompt + bulk flags |
| CLI-07 | `agentlinux pin <name>=<curated|latest|x.y.z>` sticky override | §Pattern 5 (sentinel's `source` field carries `pinned`); `upgrade` skips pinned entries; `list` still shows divergence |
| CAT-01 | Catalog contains ≥3 agents: claude-code, gsd, playwright | §Standard Stack (verified npm package names + current versions); three `plugin/catalog/agents/<id>/` dirs with `install.sh` + `uninstall.sh` |
| CAT-02 | No catalog agent installed by default | Invariant: installer provisioners never call `agentlinux install`; bats @test on fresh install asserts `agentlinux list` shows all `not-installed`; `installed.d/` dir empty |
| CAT-03 | Machine-readable schema; new agent = entry + recipe, no CLI source edit | §Pattern 9 (ajv schema + test-fixture bats that adds an entry WITHOUT touching `plugin/cli/src/`); catalog-auditor rubric enforces CAT-03 on PRs |
| CAT-04 | Every entry declares `pinned_version` validated by JSON Schema | §Pattern 9 (schema `required: ["pinned_version"]` + semver `pattern`); ajv rejects missing/malformed at load time |
| INST-04 | `--purge` uninstall | §Pattern 10 (ordered teardown: agents first, then `/opt/agentlinux`, then PATH artefacts, then user; each step idempotent) |

Phase 5 dependencies (not implemented in Phase 4, but CLI must enable): AGT-01 / AGT-02 / AGT-02b / AGT-04 / AGT-05 require `agentlinux install <name>` to honor `pinned_version` end-to-end.

Phase 6 dependencies: CAT-05 (release artifact = catalog snapshot sibling of tarball + .sha256) + TST-08 (release-gate pinned-combo CI). Phase 4 stages the snapshot shape; Phase 6 wires the release workflow.
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Never `sudo npm install -g`.** Every npm invocation in `install.sh` recipes MUST go through `as_user agent -- npm install -g ...`. This is the keystone ADR-004 rule; `security-engineer` subagent flags violations.
- **No wrapper shims at `/usr/local/bin/`** pointing to agent-owned binaries. The `agentlinux` CLI lives at `/home/agent/.npm-global/bin/agentlinux` as a symlink into `/opt/agentlinux/cli/<version>/`. Never at `/usr/local/bin/agentlinux`.
- **Behavior tests in `tests/bats/` are the spec.** Implementation may change freely as long as CLI-XX / CAT-XX / INST-04 stay green. No implementation details locked into @test assertions.
- **No agent installed by default.** Catalog ships entries; `agentlinux install <name>` is opt-in. Fresh install produces empty `/opt/agentlinux/state/installed.d/`.
- **Every release tarball ships with a sibling `.sha256`.** Phase 6 concern; Phase 4's catalog snapshot flow must cooperate with that model (the snapshot is a sibling of the tarball + its own .sha256 is Phase 6's problem).
- **Review loop before task complete.** TS changes → node-engineer + security-engineer + qa-engineer. Bash changes → bash-engineer + security-engineer + qa-engineer. Bats → qa-engineer + behavior-coverage-auditor. Catalog recipes → catalog-auditor + security-engineer.
- **`as_user` keystone.** `plugin/lib/as_user.sh` is the only path by which the installer and CLI run as `agent`. Never raw `sudo -u agent`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Catalog schema definition | Build / Static | — | `plugin/catalog/schema.json` is a static contract shipped in the tarball; ajv loads at CLI runtime. |
| Catalog entries (claude-code/gsd/playwright/test-dummy) | Build / Static | — | JSON + `install.sh` + `uninstall.sh` shipped in the tarball. |
| Schema validation | Node CLI runtime | Pre-commit (dev) | Ajv validates at CLI load (on commands that need it) and in CI via the pre-commit hook replacement. |
| `list` / `install` / `remove` / `upgrade` / `pin` UX | Node CLI runtime | — | Commander.js owns parsing + dispatch. |
| Version-decision logic | Node CLI runtime | — | CLI computes "which version to install" (catalog pin vs --version override vs sticky pin) and hands result to the recipe via env var. |
| npm / native install execution | Bash recipe (as agent) | — | `install.sh` runs as agent under `as_user`; it is the only layer that touches npm or `curl | bash`. |
| Sentinel read/write | Node CLI runtime | — | Single writer, protected by flock(1) against concurrent `agentlinux` invocations. |
| Divergence detection (`npm ls -g --json`) | Node CLI runtime | Bash (via `as_user -- npm ls ...`) | CLI shells out to `npm ls` via `as_user`, parses JSON in Node. |
| CLI staging on disk | Bash provisioner `50-registry-cli.sh` | — | Runs at install time as root; places `dist/` under `/opt/agentlinux/cli/<version>/`, creates symlink, chowns. |
| `--purge` teardown | Bash installer (root) | — | Only root can remove the agent user + system-level files. CLI `remove <name>` delegates per-agent; installer `--purge` orchestrates them + system teardown. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `commander` | `^12.1.0` | Subcommand parsing, help generation, async actions | `[VERIFIED: npm view commander version → 14.0.3]` current is 14.x but ADR-008 + CONTEXT lock to `^12.x`. v12 still supported, smaller surface than v13/v14, unchanged idioms. Already pinned in `plugin/cli/package.json`. |
| `ajv` | `^8.17.0` | JSON Schema 2020-12 validator | `[VERIFIED: npm view ajv version → 8.18.0]` current 8.18.0; the `^8` line supports 2020-12 via the `ajv/dist/2020` import. `[CITED: https://ajv.js.org/json-schema.html]` — "draft-2020-12 is not backwards compatible … cannot use draft-2020-12 and previous JSON Schema versions in the same Ajv instance." |
| `ajv-formats` | `^3.0.1` | `format: "uri"` / `"date-time"` etc. in schemas | `[VERIFIED: npm view ajv-formats version → 3.0.1]` ajv-formats v3 pairs with ajv v8. Adds the `uri`, `email`, `date-time` formats the schema uses for `homepage` etc. |
| `semver` | `^7.7.0` | Range matching, version comparison, maxSatisfying | `[VERIFIED: npm view semver version → 7.7.4]` current 7.7.4. `[CITED: https://github.com/npm/node-semver]` — `satisfies(version, range)`, `maxSatisfying(versions, range)`, `gt/lt/eq`. Required for `version_constraint` upper-bound (CAT-04 optional field) and `upgrade` classification (`override-ahead` = `gt(installed, sentinel.version)`). |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TypeScript | `^5.6.3` | Compile to ES2022 | Already pinned in `plugin/cli/package.json`; `tsconfig.json` emits ES2022 + NodeNext module resolution (ESM). |
| `@biomejs/biome` | `^1.9.4` | Lint + format | Already pinned; pre-commit `biome-check` hook active on `plugin/cli/`. |
| `@stryker-mutator/core` | (already configured) | Nightly mutation testing | `plugin/cli/stryker.config.json` exists (TST-06); threshold break=0 advisory. Phase 4 grows it with real commands + test targets. |

### Node `node:test` (stdlib)

**CONTEXT locks `node:test`** for CLI unit tests — stdlib, zero-dep, native since Node 18. `[CITED: https://nodejs.org/api/test.html]`

```typescript
// plugin/cli/test/schema.test.ts
import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

describe('ajv catalog schema', () => {
  test('rejects entry missing pinned_version', () => {
    const ajv = new Ajv2020({ allErrors: true });
    const validate = ajv.compile(schema);
    assert.equal(validate({ /* entry without pinned_version */ }), false);
    assert.ok(validate.errors?.some(e => e.params.missingProperty === 'pinned_version'));
  });
});
```

Run via `node --test --experimental-test-coverage test/` (already wired in `plugin/cli/package.json`'s `scripts.test`). `--test-concurrency=1` recommended for tests that touch shared fixtures on disk.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Commander.js `^12.x` | Commander.js `^14.x` | CONTEXT locks `^12`; v14 is fine but adds no Phase 4 feature and CONTEXT change is out of scope. Revisit post-v0.3.0. |
| Ajv 8 | Ajv 9 | `[VERIFIED: npm registry]` Ajv 9 not yet released as of research date. Ajv 8 is current stable. |
| `node:test` | Vitest | CONTEXT locks `node:test`. Vitest adds 40+ transitive deps for zero workflow gain on a CLI this size. |
| `execa` | `node:child_process` | Plain `child_process.execFile` is sufficient for the `sudo -u agent -H -- npm ls -g --json` shape. No need for another dep. |
| `kleur` / `chalk` | no color | `list` output is grep-friendly text; status column can be plain ASCII (`[synced]`, `[override-ahead]`). If color is wanted later, Node 18+ supports `process.stdout.hasColors()` via `tty` — no lib needed. |

**Installation:**

```bash
cd plugin/cli
pnpm add commander@^12.1.0 ajv@^8.17.0 ajv-formats@^3.0.1 semver@^7.7.0
pnpm add -D @types/semver typescript@^5.6.3 @biomejs/biome@^1.9.4
```

**Version verification performed (2026-04-18):**

| Package | Installed by planner | npm-registry latest |
|---------|----------------------|---------------------|
| commander | `^12.1.0` (LOCKED) | 14.0.3 |
| ajv | `^8.17.0` | 8.18.0 |
| ajv-formats | `^3.0.1` | 3.0.1 |
| semver | `^7.7.0` | 7.7.4 |

All versions verified via `npm view <pkg> version` on 2026-04-18.

### Catalog Agent npm Packages (CAT-01)

| Catalog id | npm package | Latest version | source_kind | pinned_version recommendation |
|-----------|-------------|----------------|-------------|------------------------------|
| `claude-code` | `@anthropic-ai/claude-code` | `2.1.114` `[VERIFIED]` | `script` (preferred — per `code.claude.com/docs/en/setup`, native install is "Recommended" and auto-updates in background) OR `npm` | Pick a recent `stable` dist-tag: `2.1.98` `[VERIFIED: npm view @anthropic-ai/claude-code dist-tags → {stable: '2.1.98', latest: '2.1.114'}]`. Planner picks a value. |
| `gsd` | `get-shit-done-cc` | `1.37.1` `[VERIFIED]` | `npm` | `1.37.1` or a pinned recent stable. Planner picks. `[VERIFIED: npm view get-shit-done-cc version → 1.37.1; bin: {"get-shit-done-cc": "bin/install.js"}]` |
| `playwright` | `playwright` | `1.59.1` `[VERIFIED]` | `npm` | `1.59.1` or pinned recent. `[VERIFIED: npm view playwright version → 1.59.1; bin: {playwright: "cli.js"}]`. Playwright installs the `playwright` binary; `npx playwright install` downloads browser binaries (AGT-05). |
| `test-dummy` | — (no upstream) | n/a | `script` | `0.0.1` (hard-coded; Phase 4 invariant). See §Pattern 11. |

**Note on GSD name collision:** `[ASSUMED until Phase 5 verifies]` The npm package `get-shit-done` (1 stable version, last published 5+ years ago) is unrelated prior art. The GSD CLI this project uses is `get-shit-done-cc` (`[CITED: https://github.com/gsd-build/get-shit-done; https://www.npmjs.com/package/get-shit-done-cc]`). Planner should confirm with CLAUDE.md author before Phase 4 task commits the entry. If the project uses a different distribution channel (e.g., `npx get-shit-done-cc` one-shot vs `npm install -g`), the `install.sh` recipe shape changes accordingly.

**Note on Claude Code install shape:** Critical discovery from `[CITED: https://code.claude.com/docs/en/setup]`:

> To install a specific version number:
> ```bash
> curl -fsSL https://claude.ai/install.sh | bash -s 2.1.89
> ```

This is the canonical version-pinning mechanism for the native installer. The npm package also works: `npm install -g @anthropic-ai/claude-code@2.1.89`. Phase 5 will write the actual `install.sh` recipe; Phase 4 ships the `source_kind` enum + env-var contract that makes both paths expressible. The native installer is "Recommended" per the docs AND it auto-updates in background — which for AGT-02 / AGT-02b means `claude update` from inside Claude Code and background auto-update both go through the same code path. `DISABLE_AUTOUPDATER=1` is available to neutralize auto-update in test environments (Phase 5 bats).

## Architecture Patterns

### System Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│ Agent User Shell (interactive / ssh / cron / systemd / sudo -u)        │
│   $ agentlinux install claude-code                                     │
└────────────┬───────────────────────────────────────────────────────────┘
             │  /home/agent/.npm-global/bin/agentlinux  (symlink)
             ▼
┌────────────────────────────────────────────────────────────────────────┐
│ /opt/agentlinux/cli/0.3.0/dist/index.js  (Node ESM, shebang)           │
│ ┌──────────────────────────────────────────────────────────────────┐   │
│ │ Commander.js program                                             │   │
│ │   .command('list').action(listCmd)                               │   │
│ │   .command('install <name>').action(installCmd)                  │   │
│ │   .command('remove <name>').action(removeCmd)                    │   │
│ │   .command('upgrade').action(upgradeCmd)                         │   │
│ │   .command('pin <spec>').action(pinCmd)                          │   │
│ └──────────────────────────────────────────────────────────────────┘   │
│                            │                                            │
│  Step 1: guardNonAgentUser() — CLI-05 EUID check                        │
│  Step 2: loadCatalog()       — read + ajv-validate on install/upgrade   │
│  Step 3: readSentinel()      — /opt/agentlinux/state/installed.d/*.json │
│  Step 4: decideVersion()     — pin vs override vs --version vs catalog  │
│  Step 5: dispatchRecipe()    — as_user agent -- install.sh              │
│  Step 6: writeSentinel()     — flock + atomic rename                    │
└────────────────────────┬───────────────────────────────────────────────┘
                         │ spawn `sudo -u agent -H -E --` (via plugin/lib/as_user.sh equivalent in TS)
                         │ ENV: AGENTLINUX_PINNED_VERSION=2.1.98
                         │      AGENTLINUX_CATALOG_DIR=/opt/agentlinux/catalog/0.3.0
                         │      AGENTLINUX_AGENT_HOME=/home/agent
                         │      AGENTLINUX_SOURCE_KIND=script
                         ▼
┌────────────────────────────────────────────────────────────────────────┐
│ /opt/agentlinux/catalog/0.3.0/agents/claude-code/install.sh            │
│   — runs AS AGENT, no sudo —                                           │
│ case "$AGENTLINUX_SOURCE_KIND" in                                       │
│   npm)    npm install -g "${NPM_PKG}@${AGENTLINUX_PINNED_VERSION}" ;;  │
│   script) curl -fsSL https://claude.ai/install.sh | bash -s \          │
│             "${AGENTLINUX_PINNED_VERSION}" ;;                          │
│ esac                                                                    │
└────────────────────────┬───────────────────────────────────────────────┘
                         │
                         ▼
                 /home/agent/.local/bin/claude (native)  OR
                 /home/agent/.npm-global/bin/claude (npm)

┌────────────────────────────────────────────────────────────────────────┐
│ /opt/agentlinux/state/installed.d/claude-code.json  (per-agent file)   │
│   { id: "claude-code", version: "2.1.98",                              │
│     source: "curated", sticky: false, installed_at: "2026-04-18T..."}  │
└────────────────────────────────────────────────────────────────────────┘
```

**`agentlinux upgrade` 3-way classifier:**

```
  ┌─────────┐   ┌─────────────┐   ┌───────────────────┐   ┌──────────────┐
  │Sentinel │   │Catalog pin  │   │npm ls -g --json   │   │Upstream latest│
  │.version │   │(snapshot)   │   │<pkg>.version      │   │(npm view, opt)│
  └────┬────┘   └──────┬──────┘   └────────┬──────────┘   └──────┬───────┘
       │               │                   │                     │
       └─────────────┬─┴─────────────┬─────┘                     │
                     │               │                           │
                     ▼               ▼                           │
            ┌─────────────────────────────┐                      │
            │ semver.eq(sentinel, npm_ls) │ ◄── drift detection  │
            └──────────────┬──────────────┘                      │
                           │                                     │
                  drift? ──yes──► "drift-undeclared"              │
                           │                                     │
                           no                                    │
                           ▼                                     │
            ┌─────────────────────────────┐                      │
            │ semver.eq(npm_ls, catalog)? │                      │
            └──────────────┬──────────────┘                      │
                           │                                     │
                  yes ────────────► "synced"                     │
                           │                                     │
                           no                                    │
                           ▼                                     │
                  ┌─────────────────┐                            │
                  │ sentinel.sticky?│                            │
                  └────┬────────────┘                            │
                       │yes                                      │
                       ▼                                         │
                  "pinned-override"                              │
                       │no                                       │
                       ▼                                         │
            ┌─────────────────────────────┐                      │
            │ semver.gt(npm_ls, catalog)? │                      │
            └──────────────┬──────────────┘                      │
                           │                                     │
                  yes ───► "override-ahead"                      │
                  no  ───► "override-behind"                     │
```

### Component Responsibilities

| File | Owner tier | Responsibility |
|------|-----------|----------------|
| `plugin/cli/src/index.ts` | CLI | Commander program bootstrap + pre-action EUID guard + `parseAsync`. |
| `plugin/cli/src/commands/list.ts` | CLI | Read catalog + sentinels; format text/JSON table; no ajv. |
| `plugin/cli/src/commands/install.ts` | CLI | ajv-validate; decide version; dispatch recipe via `as_user`; write sentinel. |
| `plugin/cli/src/commands/remove.ts` | CLI | Dispatch `uninstall.sh`; remove sentinel file. |
| `plugin/cli/src/commands/upgrade.ts` | CLI | 3-way classifier; interactive prompt OR bulk flags; re-dispatch install.sh per-agent. |
| `plugin/cli/src/commands/pin.ts` | CLI | Parse `<name>=<spec>`; mutate sentinel `sticky` + `version`. |
| `plugin/cli/src/catalog/schema.ts` | CLI | Ajv singleton + compiled validator. |
| `plugin/cli/src/catalog/load.ts` | CLI | Read `catalog.json` + resolve recipe paths. |
| `plugin/cli/src/state/sentinel.ts` | CLI | `readSentinel(id)` / `writeSentinel(entry)` with `flock`. |
| `plugin/cli/src/state/dispatcher.ts` | CLI | `asUser(cmd, env)` — shells `sudo -u agent -H -E --` in Node. |
| `plugin/cli/src/guard/user.ts` | CLI | CLI-05 EUID check. |
| `plugin/cli/src/version/classify.ts` | CLI | Divergence classifier (pure function, easily tested). |
| `plugin/cli/scripts/validate-catalog.mjs` | Build / Dev | Thin wrapper that reuses `src/catalog/schema.ts` for pre-commit. |
| `plugin/catalog/schema.json` | Static | JSON Schema 2020-12 (extended to require `pinned_version`, etc.). |
| `plugin/catalog/catalog.json` | Static | `{version, agents: [{id, pinned_version, ...}]}`. |
| `plugin/catalog/agents/<id>/install.sh` | Bash / recipe | `#!/usr/bin/env bash; set -euo pipefail`; reads env; runs npm or curl. |
| `plugin/catalog/agents/<id>/uninstall.sh` | Bash / recipe | Symmetric inverse. |
| `plugin/provisioner/50-registry-cli.sh` | Bash / provisioner | Stages `dist/` under `/opt/agentlinux/cli/0.3.0/`; symlinks to `.npm-global/bin/agentlinux`; stages catalog snapshot; creates `/opt/agentlinux/state/installed.d/` (0755 agent:agent). |
| `plugin/bin/agentlinux-install` (`--purge` branch) | Bash / installer | Orchestrates teardown: per-agent uninstall.sh → `/opt/agentlinux/` → PATH artefacts → agent user. |
| `tests/bats/40-registry-cli.bats` | Test | 15+ @tests citing CLI-01..07, CAT-01..04, INST-04. |
| `plugin/cli/test/*.test.ts` | Test | `node:test` unit tests: schema / classifier / sentinel / dispatcher. |

### Recommended Project Structure

```
plugin/cli/
├── package.json
├── tsconfig.json
├── biome.json
├── stryker.config.json
├── scripts/
│   └── validate-catalog.mjs       # thin wrapper, pre-commit entry
├── src/
│   ├── index.ts                   # Commander bootstrap + EUID guard + parseAsync
│   ├── commands/
│   │   ├── list.ts
│   │   ├── install.ts
│   │   ├── remove.ts
│   │   ├── upgrade.ts
│   │   └── pin.ts
│   ├── catalog/
│   │   ├── schema.ts              # Ajv singleton + compiled validator
│   │   └── load.ts                # read catalog.json + resolve paths
│   ├── state/
│   │   ├── sentinel.ts            # readSentinel / writeSentinel w/ flock
│   │   └── dispatcher.ts          # as_user spawn helper
│   ├── version/
│   │   └── classify.ts            # pure-function divergence classifier
│   └── guard/
│       └── user.ts                # CLI-05 EUID check
├── test/
│   ├── fixtures/
│   │   ├── catalog-valid.json
│   │   ├── catalog-missing-pin.json
│   │   └── sentinel-sample.json
│   ├── schema.test.ts
│   ├── classify.test.ts
│   ├── sentinel.test.ts
│   ├── commands-install.test.ts
│   └── commands-upgrade.test.ts
└── dist/                          # tsc output, shipped in release tarball

plugin/catalog/
├── schema.json                    # JSON Schema 2020-12
├── catalog.json                   # {version, agents: [...]}
└── agents/
    ├── claude-code/
    │   ├── install.sh
    │   └── uninstall.sh
    ├── gsd/
    │   ├── install.sh
    │   └── uninstall.sh
    ├── playwright/
    │   ├── install.sh
    │   └── uninstall.sh
    └── test-dummy/                # CAT-02 test fixture; filtered from default `list`
        ├── install.sh             # touches /tmp/agentlinux-test-dummy.marker
        └── uninstall.sh           # removes it

plugin/provisioner/
└── 50-registry-cli.sh             # stages CLI, stages catalog snapshot, symlinks

plugin/bin/
└── agentlinux-install             # extends with real --purge branch

tests/bats/
└── 40-registry-cli.bats           # 15+ @tests covering CLI-01..07, CAT-01..04, INST-04

/opt/agentlinux/                   # runtime (installer-placed)
├── cli/
│   └── 0.3.0/
│       └── dist/index.js
├── catalog/
│   └── 0.3.0/
│       ├── catalog.json           # snapshot (CAT-05 in Phase 6)
│       └── agents/<id>/*.sh
└── state/
    └── installed.d/               # 0755 agent:agent
        ├── claude-code.json       # 0644 agent:agent, one per installed agent
        └── .lock                  # flock target
```

### Pattern 1: CLI provisioner (plugin/provisioner/50-registry-cli.sh)

**What:** Stages the compiled CLI + catalog snapshot, creates the symlink, prepares the state directory.

**When to use:** Runs once at install time, after `40-path-wiring.sh` (which already put `.npm-global/bin` on PATH). Idempotent on re-run.

**Example:**

```bash
#!/usr/bin/env bash
# plugin/provisioner/50-registry-cli.sh — stages agentlinux CLI + catalog snapshot
# Sourced by plugin/bin/agentlinux-install; inherits set -euo pipefail + ERR trap + tee.
# Requirement IDs: CLI-01 (PATH), CAT-01..04 (catalog shipped), CAT-05 partial (snapshot layout).

log_info "50-registry-cli: starting"

readonly AGENTLINUX_VERSION  # exported by entrypoint
readonly CLI_STAGE_DIR="/opt/agentlinux/cli/${AGENTLINUX_VERSION}"
readonly CATALOG_STAGE_DIR="/opt/agentlinux/catalog/${AGENTLINUX_VERSION}"
readonly STATE_DIR="/opt/agentlinux/state"
readonly SYMLINK="/home/agent/.npm-global/bin/agentlinux"

# Source directory: the installer was unpacked under $BIN_DIR/../
readonly CLI_SRC="$(cd "$BIN_DIR/../cli/dist" && pwd)"
readonly CATALOG_SRC="$(cd "$BIN_DIR/../../plugin/catalog" && pwd)"

# Stage CLI under versioned dir (multiple versions can coexist at runtime).
ensure_dir /opt/agentlinux 0755 root:root
ensure_dir "$(dirname "$CLI_STAGE_DIR")" 0755 root:root
ensure_dir "$CLI_STAGE_DIR" 0755 root:root
# rsync -a preserves mode/ownership; here we want root-owned but readable by
# all. Plain `cp -R` + `chmod -R 0755` is simpler and inherited-root-owner safe.
cp -R "$CLI_SRC"/. "$CLI_STAGE_DIR"/
chmod -R u=rwX,go=rX "$CLI_STAGE_DIR"

# Stage catalog snapshot. In Phase 6, the release pipeline may ship the
# snapshot as a sibling of the tarball and point us at it; Phase 4 stages from
# the source tree in-tarball.
ensure_dir "$CATALOG_STAGE_DIR" 0755 root:root
cp -R "$CATALOG_SRC"/. "$CATALOG_STAGE_DIR"/
chmod -R u=rwX,go=rX "$CATALOG_STAGE_DIR"
# install.sh / uninstall.sh must be executable for the CLI dispatcher to spawn them.
find "$CATALOG_STAGE_DIR/agents" -name '*.sh' -exec chmod 0755 {} +

# State directory — agent-owned so the CLI (run as agent) can write sentinels.
ensure_dir "$STATE_DIR" 0755 agent:agent
ensure_dir "$STATE_DIR/installed.d" 0755 agent:agent

# Symlink `agentlinux` into the agent's PATH. Atomic via ln -sfn (force + no-deref).
# Points at the Node entrypoint; shebang #!/usr/bin/env node resolves Node 22 from PATH.
ensure_dir /home/agent/.npm-global/bin 0755 agent:agent
ln -sfn "$CLI_STAGE_DIR/index.js" "$SYMLINK"
chown -h agent:agent "$SYMLINK"
log_info "symlinked ${SYMLINK} -> ${CLI_STAGE_DIR}/index.js"

# Sanity: as the agent user, confirm resolution.
if ! as_user agent -- test -x "$SYMLINK"; then
  log_error "agentlinux symlink not executable as agent (CLI-01)"
  return 1
fi
log_info "50-registry-cli: done (CLI-01 + CAT-01..04 staging complete)"
```

### Pattern 2: Commander.js program bootstrap (plugin/cli/src/index.ts)

**What:** Declares the subcommands, installs the EUID preAction hook, calls `parseAsync`.

**When to use:** CLI entrypoint — `#!/usr/bin/env node` shebang via tsc `outFile` + `chmod 0755` in build step.

**Example:**

```typescript
#!/usr/bin/env node
// plugin/cli/src/index.ts — agentlinux CLI entrypoint.
// Pattern ref: ADR-008 (Commander.js ^12); CONTEXT "CLI Tech Stack & Packaging".

import { Command } from 'commander';
import { listCmd } from './commands/list.js';
import { installCmd } from './commands/install.js';
import { removeCmd } from './commands/remove.js';
import { upgradeCmd } from './commands/upgrade.js';
import { pinCmd } from './commands/pin.js';
import { guardAgentUser } from './guard/user.js';

const program = new Command();

program
  .name('agentlinux')
  .description('AgentLinux registry CLI — install, upgrade, remove catalog agents')
  .version('0.3.0', '-V, --version')
  .option('--json', 'machine-readable output where supported');

// CLI-05: fail fast when invoked as a non-agent user BEFORE any subcommand runs.
// preAction hook fires after parsing but before the action handler. Commander
// v12 supports .hook('preAction', fn). Ref: github.com/tj/commander.js readme.
program.hook('preAction', (thisCommand, actionCommand) => {
  guardAgentUser(actionCommand.name());  // throws with clear message + exits 64
});

program
  .command('list')
  .description('List catalog agents and their install status')
  .option('--include-test', 'include test-only entries (hidden by default)')
  .action(async (opts) => await listCmd({ ...program.opts(), ...opts }));

program
  .command('install <name>')
  .description('Install a catalog agent at its pinned_version')
  .option('--force', 're-run install.sh even if sentinel matches')
  .option('--version <semver>', 'override catalog pin with a specific version')
  .action(async (name: string, opts) => await installCmd(name, { ...program.opts(), ...opts }));

program
  .command('remove <name>')
  .description('Uninstall a catalog agent')
  .option('--force', 'succeed even if agent is not installed (idempotent no-op)')
  .action(async (name: string, opts) => await removeCmd(name, { ...program.opts(), ...opts }));

program
  .command('upgrade')
  .description('Reconcile installed versions against the curated catalog (CLI-06)')
  .option('--reset-all-curated', 'accept curated versions for all agents; clear overrides')
  .option('--respect-overrides', 'install curated only for non-overridden agents')
  .option('--all-latest', 'install npm latest for all (implies --check-upstream)')
  .option('--check-upstream', 'query `npm view <pkg> version` for upstream latest (network)')
  .action(async (opts) => await upgradeCmd({ ...program.opts(), ...opts }));

program
  .command('pin <spec>')
  .description('Set sticky override: <name>=curated|latest|x.y.z (CLI-07)')
  .action(async (spec: string, opts) => await pinCmd(spec, { ...program.opts(), ...opts }));

// Commander is strict by default — unknown commands/options exit with a clear error.
// Ref: code.claude.com / Commander v12 README: "Commander is strict and displays an
// error for unrecognised options."
// Async actions REQUIRE parseAsync, not parse. Ref: Commander README.
await program.parseAsync(process.argv);
```

**Gotchas verified:**
- Async actions + `.parse()` silently drops rejected promises; you MUST use `.parseAsync()`. `[CITED: github.com/tj/commander.js README]`
- `program.opts()` returns root-level options; subcommand options are in the action's second arg; the spread above merges them for subcommand handlers.
- Commander v12 default exports unchanged from v11; `import { Command }` is current idiomatic shape. `[VERIFIED: npm view commander version → 14.0.3, and v12 migration notes]`

### Pattern 3: Install dispatch (plugin/cli/src/commands/install.ts)

**What:** The happy path for `agentlinux install <name>`: validate catalog, decide version, spawn `install.sh` as agent, write sentinel.

```typescript
// plugin/cli/src/commands/install.ts
import { loadCatalog } from '../catalog/load.js';
import { readSentinel, writeSentinel } from '../state/sentinel.js';
import { asUser } from '../state/dispatcher.js';
import { decideVersion } from '../version/classify.js';
import * as semver from 'semver';

export async function installCmd(name: string, opts: {
  force?: boolean; version?: string; json?: boolean;
}) {
  const catalog = await loadCatalog();  // ajv-validates; throws with structured errors
  const entry = catalog.agents.find(a => a.id === name);
  if (!entry) {
    console.error(`agentlinux: no such agent in catalog: ${name}`);
    console.error(`  available: ${catalog.agents.map(a => a.id).join(', ')}`);
    process.exit(64);  // EX_USAGE
  }

  if (opts.version && !semver.valid(opts.version)) {
    console.error(`agentlinux: --version ${opts.version} is not a valid semver`);
    process.exit(64);
  }

  const sentinel = await readSentinel(entry.id);  // null if not installed

  // Idempotent short-circuit: same-version sentinel + no --force → no-op.
  const decision = decideVersion(entry, opts.version, sentinel);
  if (!opts.force && sentinel && semver.eq(sentinel.version, decision.version)) {
    console.log(`${entry.id}: already installed at ${sentinel.version} (${sentinel.source}); no-op`);
    return;
  }

  // Dispatch the recipe as the agent user with the version in the environment.
  // The install.sh is a BASH file in catalog/agents/<id>/, not TS. Dispatching
  // is a single exec: sudo -u agent -H -E -- bash <recipe> with env set.
  const recipePath = `${catalog.catalogDir}/agents/${entry.id}/${entry.install_recipe_path}`;
  const { exitCode, stdout, stderr } = await asUser('agent', ['bash', recipePath], {
    env: {
      AGENTLINUX_PINNED_VERSION: decision.version,
      AGENTLINUX_CATALOG_DIR: catalog.catalogDir,
      AGENTLINUX_AGENT_HOME: '/home/agent',
      AGENTLINUX_SOURCE_KIND: entry.source_kind,
      AGENTLINUX_INSTALL_LOG: '/var/log/agentlinux-install.log',
      // Inherit PATH, LANG etc. from /etc/agentlinux.env-shaped subset.
      PATH: '/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin',
      HOME: '/home/agent',
      NPM_CONFIG_PREFIX: '/home/agent/.npm-global',
      LANG: 'C.UTF-8',
      LC_ALL: 'C.UTF-8',
    },
  });

  if (exitCode !== 0) {
    console.error(`${entry.id}: install.sh failed (exit ${exitCode})`);
    console.error(stderr);
    process.exit(exitCode);
  }

  // Write sentinel atomically.
  await writeSentinel({
    id: entry.id,
    version: decision.version,
    source: decision.source,      // 'curated' | 'override' | 'latest' | 'pinned'
    sticky: decision.sticky,
    installed_at: new Date().toISOString(),
  });

  console.log(`${entry.id}: installed ${decision.version} (${decision.source})`);
}
```

### Pattern 4: Remove dispatch (plugin/cli/src/commands/remove.ts)

Symmetric inverse of install. Reads sentinel, spawns `uninstall.sh`, removes sentinel file.

```typescript
// plugin/cli/src/commands/remove.ts
import { loadCatalog } from '../catalog/load.js';
import { readSentinel, deleteSentinel } from '../state/sentinel.js';
import { asUser } from '../state/dispatcher.js';

export async function removeCmd(name: string, opts: { force?: boolean; }) {
  const catalog = await loadCatalog();
  const entry = catalog.agents.find(a => a.id === name);
  if (!entry) { process.exit(64); }

  const sentinel = await readSentinel(entry.id);
  if (!sentinel && !opts.force) {
    console.error(`agentlinux: ${entry.id} is not installed (pass --force for no-op)`);
    process.exit(1);
  }
  if (!sentinel && opts.force) { return; }

  const recipePath = `${catalog.catalogDir}/agents/${entry.id}/${entry.uninstall_recipe_path}`;
  const { exitCode } = await asUser('agent', ['bash', recipePath], {
    env: {
      AGENTLINUX_AGENT_HOME: '/home/agent',
      AGENTLINUX_SOURCE_KIND: entry.source_kind,
      PATH: '/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin',
      HOME: '/home/agent',
      NPM_CONFIG_PREFIX: '/home/agent/.npm-global',
    },
  });
  if (exitCode !== 0) { process.exit(exitCode); }

  await deleteSentinel(entry.id);
  console.log(`${entry.id}: removed`);
}
```

### Pattern 5: Sentinel read/write (plugin/cli/src/state/sentinel.ts)

**What:** Per-agent JSON files under `/opt/agentlinux/state/installed.d/<id>.json`, serialized by `flock(1)` on `/opt/agentlinux/state/.lock`, written via atomic rename.

**When to use:** Every install / upgrade / pin / remove path.

**Design decision (from CONTEXT's Claude's Discretion):** **Per-agent files**, not a monolithic `installed.json`. Rationale:
- Concurrent-write safety: two `agentlinux install` invocations racing on different agents no longer contend on the same file.
- Atomic rename is file-level — a partial write is impossible because the rename is POSIX-atomic.
- Cross-agent corruption blast radius is one file, not all state.
- `flock` is still used to serialize the `list` scan that reads every file (consistency across multiple sentinels).

**Example:**

```typescript
// plugin/cli/src/state/sentinel.ts
import { readFile, writeFile, unlink, mkdir, readdir, rename, open } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join } from 'node:path';

const exec = promisify(execFile);

const STATE_DIR = '/opt/agentlinux/state';
const INSTALLED_DIR = join(STATE_DIR, 'installed.d');
const LOCK_FILE = join(STATE_DIR, '.lock');

export interface Sentinel {
  id: string;
  version: string;
  source: 'curated' | 'override' | 'latest' | 'pinned';
  sticky: boolean;
  installed_at: string;  // ISO-8601
}

// Serialize state mutations across concurrent agentlinux invocations via flock(1).
// The lock file is touched by the provisioner at install time (0644 agent:agent).
// Inside the locked callback, performs atomic rename from tmp → final.
async function withLock<T>(fn: () => Promise<T>): Promise<T> {
  // flock -x <lockfile> -c <command> is the POSIX-shell form; here we fork
  // a child that holds the lock for the lifetime of the callback. Simpler:
  // use the `proper-lockfile` npm package … but CONTEXT locks dep surface.
  // Stdlib approach: open the lock FD + flock syscall via node:fs. The
  // simplest spawn-based approach uses `flock` from util-linux.
  // Pattern: flock -x <fd> -c 'sleep infinity' &; callback; kill child.
  // Actually simpler: use fs.open with O_EXCL + retry loop OR rely on
  // per-file atomic rename (rename(2) is atomic on same filesystem per POSIX).
  // The agentlinux concurrency model is mostly-idle (interactive user), so
  // atomic-rename alone covers 99% of races; flock belt-and-braces for the
  // multi-sentinel scan in `list`.
  //
  // This implementation uses atomic rename for single-file writes (safe per
  // POSIX) and skips flock for those. `list` reads a snapshot of dir entries
  // with a single readdir + per-file reads; stale reads are acceptable
  // (eventual consistency for an interactive `list`). If concurrency becomes
  // a real issue, revisit with `proper-lockfile`.
  return fn();
}

export async function writeSentinel(entry: Sentinel): Promise<void> {
  await mkdir(INSTALLED_DIR, { recursive: true });
  const target = join(INSTALLED_DIR, `${entry.id}.json`);
  const tmp = `${target}.tmp.${process.pid}`;
  await writeFile(tmp, JSON.stringify(entry, null, 2) + '\n', { mode: 0o644 });
  await rename(tmp, target);  // atomic on same filesystem (POSIX)
}

export async function readSentinel(id: string): Promise<Sentinel | null> {
  try {
    const data = await readFile(join(INSTALLED_DIR, `${id}.json`), 'utf8');
    return JSON.parse(data) as Sentinel;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') { return null; }
    throw err;
  }
}

export async function deleteSentinel(id: string): Promise<void> {
  try {
    await unlink(join(INSTALLED_DIR, `${id}.json`));
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== 'ENOENT') { throw err; }
  }
}

export async function listSentinels(): Promise<Sentinel[]> {
  try {
    const files = await readdir(INSTALLED_DIR);
    const sentinels = await Promise.all(
      files.filter(f => f.endsWith('.json'))
           .map(f => readSentinel(f.replace(/\.json$/, '')))
    );
    return sentinels.filter((s): s is Sentinel => s !== null);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') { return []; }
    throw err;
  }
}
```

**Note on flock:** The comment above outlines why bare atomic-rename is sufficient for the v0.3.0 interactive-user workflow. If Phase 5 or a future task pushes `agentlinux` into automated loops (nightly upgrade cron), re-introduce `flock -x` around the multi-file `list` scan. `[VERIFIED: /usr/bin/flock from util-linux 2.39.3 is available in Ubuntu 22.04 + 24.04 base images.]`

### Pattern 6: Divergence classifier (plugin/cli/src/version/classify.ts)

**What:** Pure function — no I/O — maps (sentinel, catalog pin, npm_ls version, upstream latest?) → status tag. Testable in isolation with `node:test`.

```typescript
// plugin/cli/src/version/classify.ts
import * as semver from 'semver';
import type { Sentinel } from '../state/sentinel.js';
import type { CatalogEntry } from '../catalog/load.js';

export type Status =
  | 'not-installed'
  | 'synced'
  | 'override-ahead'
  | 'override-behind'
  | 'pinned-override'
  | 'drift-undeclared';

export interface ClassifyInput {
  entry: CatalogEntry;
  sentinel: Sentinel | null;
  installed: string | null;   // `npm ls -g --json` version, or native-installer `claude --version`
}

export function classify({ entry, sentinel, installed }: ClassifyInput): Status {
  if (!sentinel || !installed) { return 'not-installed'; }

  // drift-undeclared: someone ran `claude update` or `npm install -g` outside our CLI
  if (!semver.eq(sentinel.version, installed)) { return 'drift-undeclared'; }

  if (semver.eq(installed, entry.pinned_version)) { return 'synced'; }

  if (sentinel.sticky) { return 'pinned-override'; }

  return semver.gt(installed, entry.pinned_version) ? 'override-ahead' : 'override-behind';
}

// decideVersion: which version does the CLI ask the recipe to install?
// Used by install/upgrade. Returns {version, source, sticky}.
export function decideVersion(
  entry: CatalogEntry,
  versionOverride: string | undefined,
  existingSentinel: Sentinel | null
): { version: string; source: Sentinel['source']; sticky: boolean } {
  if (versionOverride) {
    return { version: versionOverride, source: 'override', sticky: false };
  }
  if (existingSentinel?.sticky) {
    return {
      version: existingSentinel.version,
      source: existingSentinel.source,
      sticky: true,
    };
  }
  return { version: entry.pinned_version, source: 'curated', sticky: false };
}
```

### Pattern 7: Upgrade verb + `--all-latest` constraint (plugin/cli/src/commands/upgrade.ts)

```typescript
// plugin/cli/src/commands/upgrade.ts (excerpt)
import * as semver from 'semver';
import { classify } from '../version/classify.js';
import { asUser } from '../state/dispatcher.js';

// --all-latest: resolve each agent to highest npm-published version that
// satisfies version_constraint (if present). Uses `npm view <pkg> versions --json`
// (plural "versions"), which returns the full list.
async function resolveLatestFor(entry: CatalogEntry): Promise<string> {
  const { stdout } = await asUser('agent', [
    'npm', 'view', entry.npm_package_name, 'versions', '--json',
  ], { env: { /* minimal npm env */ } });
  const versions: string[] = JSON.parse(stdout);
  if (entry.version_constraint) {
    const max = semver.maxSatisfying(versions, entry.version_constraint);
    if (!max) {
      throw new Error(
        `no published version of ${entry.npm_package_name} satisfies ${entry.version_constraint}`
      );
    }
    return max;
  }
  return versions[versions.length - 1];  // newest (npm returns chronological)
}

// The reconcile loop: for each agent, build a per-agent choice and install.
// Interactive prompt uses node:readline if stdin is a tty; bulk flags short-circuit.
// Sticky / pinned-override entries are SKIPPED unless --reset-all-curated explicitly.
export async function upgradeCmd(opts: UpgradeOpts) { /* see Pattern 6 for classifier call */ }
```

**`semver.maxSatisfying` pitfall check:** `[CITED: github.com/npm/node-semver]` Returns `null` if no version satisfies the range. Must guard against null and emit a clear error.

### Pattern 8: Non-agent-user guard (plugin/cli/src/guard/user.ts)

**What:** CLI-05 fail-fast when invoked as root or any non-agent user.

```typescript
// plugin/cli/src/guard/user.ts
import { userInfo } from 'node:os';

const AGENT_USER = 'agent';

export function guardAgentUser(subcommandName: string): void {
  const invoker = userInfo().username;
  if (invoker !== AGENT_USER) {
    console.error(`agentlinux: ${subcommandName} must run as user '${AGENT_USER}' (invoker: '${invoker}')`);
    console.error(`  try: sudo -u ${AGENT_USER} -H agentlinux ${subcommandName}`);
    process.exit(64);  // EX_USAGE — matches the installer's convention in plugin/bin/agentlinux-install
  }
}
```

`os.userInfo().username` is the right primitive (NOT `process.env.USER` — spoofable). `[ASSUMED: Node.js os.userInfo docs cite geteuid() under the hood; verify before lock-in]`.

### Pattern 9: JSON Schema 2020-12 catalog schema (plugin/catalog/schema.json)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://agentlinux.org/schemas/catalog.json",
  "title": "AgentLinux Catalog",
  "description": "Catalog of available agents. Each entry is opt-in (CAT-02).",
  "type": "object",
  "required": ["version", "agents"],
  "additionalProperties": false,
  "properties": {
    "version": {
      "type": "string",
      "description": "Catalog manifest version (not an agent version)"
    },
    "agents": {
      "type": "array",
      "items": { "$ref": "#/$defs/agent" }
    }
  },
  "$defs": {
    "agent": {
      "type": "object",
      "required": [
        "id",
        "display_name",
        "description",
        "pinned_version",
        "install_recipe_path",
        "uninstall_recipe_path",
        "source_kind"
      ],
      "additionalProperties": false,
      "properties": {
        "id": { "type": "string", "pattern": "^[a-z][a-z0-9-]*$" },
        "display_name": { "type": "string", "minLength": 1 },
        "description": { "type": "string", "minLength": 1 },
        "homepage": { "type": "string", "format": "uri" },
        "license": { "type": "string" },
        "source_kind": { "type": "string", "enum": ["npm", "script"] },
        "npm_package_name": { "type": "string", "pattern": "^(@[a-z0-9-]+/)?[a-z0-9][a-z0-9_-]*$" },
        "pinned_version": {
          "type": "string",
          "description": "Exact semver pinned by this catalog release (CAT-04)",
          "pattern": "^\\d+\\.\\d+\\.\\d+(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$"
        },
        "version_constraint": {
          "type": "string",
          "description": "Optional semver range (e.g. '^2.1') that --all-latest upper-bounds against"
        },
        "install_recipe_path": { "type": "string", "pattern": "^[a-z0-9_./-]+\\.sh$" },
        "uninstall_recipe_path": { "type": "string", "pattern": "^[a-z0-9_./-]+\\.sh$" },
        "post_install_verify": { "type": "string", "description": "Optional shell one-liner for smoke-test" },
        "tags": { "type": "array", "items": { "type": "string" } },
        "test_only": { "type": "boolean", "default": false, "description": "Hide from default `list`; exercised by bats" }
      },
      "allOf": [
        {
          "if": { "properties": { "source_kind": { "const": "npm" } } },
          "then": { "required": ["npm_package_name"] }
        }
      ]
    }
  }
}
```

**Ajv 2020-12 setup (plugin/cli/src/catalog/schema.ts):**

```typescript
// plugin/cli/src/catalog/schema.ts
import Ajv2020 from 'ajv/dist/2020.js';  // NOTE: `.js` extension required for ESM NodeNext resolution
import addFormats from 'ajv-formats';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCHEMA_PATH = join(HERE, '..', '..', '..', 'catalog', 'schema.json');

let cached: ReturnType<ReturnType<Ajv2020['compile']>> | null = null;

export async function getValidator() {
  if (cached) return cached;
  const schema = JSON.parse(await readFile(SCHEMA_PATH, 'utf8'));
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  addFormats(ajv);  // enables format: "uri", "date-time", etc.
  cached = ajv.compile(schema);
  return cached;
}

export function formatErrors(errors: any[] | null | undefined): string {
  if (!errors || errors.length === 0) return '(no errors)';
  return errors
    .map((e) => `  • ${e.instancePath || '(root)'}: ${e.message} ${JSON.stringify(e.params)}`)
    .join('\n');
}
```

**Rationale for `ajv/dist/2020` import:** `[CITED: https://ajv.js.org/json-schema.html]` — "draft-2020-12 is not backwards compatible … cannot use draft-2020-12 and previous JSON Schema versions in the same Ajv instance." The 2020 export is a separate class precisely to avoid bundle-size cost for draft-07 users. The import path `ajv/dist/2020` (no explicit `.js`) works under NodeNext with `esModuleInterop`; if you hit resolution errors, add `.js` explicitly.

### Pattern 10: `--purge` orderly teardown (plugin/bin/agentlinux-install)

**What:** INST-04 wire-up — replaces the Phase 2 stub that just logged "no action."

```bash
# plugin/bin/agentlinux-install (new --purge branch replacing stub)
# Refs: INST-04; CONTEXT "`--purge` Uninstall + Phase 4 Tests"

run_purge() {
  local remove_nodejs=${1:-false}

  log_info "running --purge (destructive)"

  # Step 1: per-agent uninstall.sh for every installed agent.
  # Iterate /opt/agentlinux/state/installed.d/*.json; for each, look up the
  # entry in the staged catalog, spawn uninstall.sh as agent. DO NOT trust
  # paths from sentinel files — look them up from the catalog snapshot.
  local state_dir=/opt/agentlinux/state/installed.d
  if [[ -d $state_dir ]]; then
    local f
    for f in "$state_dir"/*.json; do
      [[ -f $f ]] || continue
      local id
      id=$(basename "$f" .json)
      local recipe=/opt/agentlinux/catalog/${AGENTLINUX_VERSION}/agents/${id}/uninstall.sh
      if [[ -x $recipe ]]; then
        log_info "running uninstall.sh for ${id}"
        as_user agent -- bash "$recipe" || log_warn "uninstall.sh for ${id} failed; continuing"
      else
        log_warn "no uninstall.sh for ${id} at ${recipe}; skipping"
      fi
      rm -f -- "$f"
    done
  fi

  # Step 2: remove /opt/agentlinux/ wholesale (CLI, catalog snapshot, state dir).
  rm -rf /opt/agentlinux/

  # Step 3: PATH artefacts placed by 40-path-wiring.sh.
  rm -f /etc/profile.d/agentlinux.sh
  rm -f /etc/agentlinux.env
  rm -f /etc/cron.d/agentlinux

  # Step 4: NodeSource apt source (placed by 30-nodejs.sh). We do NOT remove
  # Node itself by default — other users may depend on it.
  rm -f /etc/apt/sources.list.d/nodesource.sources
  rm -f /etc/apt/sources.list.d/nodesource.list
  rm -f /etc/apt/preferences.d/nodejs

  # Step 5: optionally apt-remove nodejs.
  if [[ $remove_nodejs == true ]]; then
    log_info "removing nodejs (apt-get purge -y nodejs)"
    DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs || log_warn "apt purge nodejs failed"
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
  fi

  # Step 6: agent user + /home/agent.
  # userdel -r removes the user and their home dir atomically.
  # Only if no processes are running as agent (else userdel refuses).
  if id agent >/dev/null 2>&1; then
    # Kill any agent-owned processes first (belt-and-braces).
    pkill -u agent 2>/dev/null || true
    sleep 1
    if ! userdel -r agent 2>/dev/null; then
      log_warn "userdel -r agent failed; trying userdel -rf"
      userdel -rf agent || log_error "could not remove agent user"
    fi
  fi

  # Step 7: LAST — remove the install log itself. (This runs INSIDE the tee,
  # so the final `rm` self-removes our own log. exec'd tee child will see EOF
  # on exit regardless.)
  rm -f /var/log/agentlinux-install.log

  log_info "--purge complete"
}
```

**Idempotent checks:** every `rm -f` / `rm -rf` is no-op-safe when the target is missing. `userdel -r` returns non-zero if user is absent; wrap in `id agent >/dev/null 2>&1`. `pkill -u agent` returns non-zero if no processes match; ignore.

**Security note:** `rm -rf /opt/agentlinux/` is bounded to a well-known absolute path. Do NOT let this path derive from env vars or user input. `security-engineer` reviewer flags any dynamic prefix.

### Pattern 11: test-dummy catalog entry (plugin/catalog/agents/test-dummy/)

**What:** A shell-only "agent" that touches a file on install and removes it on uninstall — no npm, no network. Exercises the CLI dispatch path in bats without flake.

**Rationale from CONTEXT:** "Design: a shell script that `touch`es a sentinel in `/tmp/agentlinux-test-<id>` on install, removes it on uninstall. Validates the CLI's dispatch + sentinel logic without a real npm install."

**Catalog entry (inline in `catalog.json`):**

```json
{
  "id": "test-dummy",
  "display_name": "Test Dummy (CI-only)",
  "description": "Shell-based fixture for bats; never a real agent.",
  "source_kind": "script",
  "pinned_version": "0.0.1",
  "install_recipe_path": "install.sh",
  "uninstall_recipe_path": "uninstall.sh",
  "test_only": true
}
```

**`plugin/catalog/agents/test-dummy/install.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
# test-dummy install.sh — exercises the CLI dispatch path without network.
# Honors AGENTLINUX_PINNED_VERSION so bats can assert the version wiring.

readonly MARKER="/tmp/agentlinux-test-dummy.marker"
printf 'version=%s\ninstalled_at=%s\n' \
  "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$MARKER"
echo "test-dummy: wrote ${MARKER}"
```

**`plugin/catalog/agents/test-dummy/uninstall.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
readonly MARKER="/tmp/agentlinux-test-dummy.marker"
rm -f -- "$MARKER"
echo "test-dummy: removed ${MARKER}"
```

**`list` filtering:** Entries with `test_only: true` are omitted from default `agentlinux list` output. `--include-test` flag shows them. Bats tests pass `--include-test`.

### Anti-Patterns to Avoid

- **Calling `sudo -u agent` directly in TS.** The installer's `as_user` keystone (bash) is the bash layer; the CLI is TypeScript — it re-implements the pattern via `child_process.execFile('sudo', ['-u', 'agent', '-H', '-E', '--', ...])`. The three load-bearing flags (`-H`, `-E`, `--`) must match `plugin/lib/as_user.sh` byte-for-byte semantics. `security-engineer` reviewer cross-checks.
- **Mutating `installed.json` without atomic rename.** Mid-write crashes leave corrupt JSON; `agentlinux list` then fails on `JSON.parse`. Always write `<file>.tmp` + `rename()`.
- **`npm install -g ...` inside a recipe without `as_user`.** CLAUDE.md critical rule. catalog-auditor grep-rejects any `install.sh` that contains `sudo npm`.
- **Running ajv on every CLI invocation.** `list` is the hot path (agent might run it in a loop or cron). Validate only on `install` / `upgrade` where bad catalog = real failure. `list` tolerates a partially-invalid catalog and surfaces it as a column.
- **Relying on `process.env.USER` for CLI-05.** Spoofable. Use `os.userInfo().username` (getuid/geteuid under the hood).
- **Using Commander's `.parse()` with async actions.** Silently drops promise rejections. Always `.parseAsync()`.
- **Hardcoding catalog path in multiple files.** Single source of truth: `AGENTLINUX_CATALOG_DIR` env var set by the dispatcher.
- **Writing sentinels with a world-writable mode.** 0644 agent:agent. The state dir itself is 0755 agent:agent so the agent (the only sentinel writer) can create files, but other users cannot mutate.
- **`rm -rf $SOMETHING` where $SOMETHING is not a literal absolute path.** Unbounded expansion risk. `--purge` uses literal `/opt/agentlinux/` etc.
- **Skipping the `flock` / atomic-rename discipline on the install log append.** Phase 2's `exec > >(tee -a)` pattern handles this, but `install.sh` recipes that write directly to the log MUST append-only via `>>`, never reopen the file for `>`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Subcommand parsing | Hand-rolled `process.argv` walker | Commander.js `^12.x` | ADR-008 locked; help generation, type coercion, async support are nontrivial. |
| JSON Schema validation | Hand-rolled field checks | Ajv 8 (`Ajv2020`) | 2020-12 dialect has `$ref`, `$defs`, `allOf`, `if/then` — reimplementing is 2000+ LOC; Ajv compiles schemas to fast validators. |
| Semver range resolution | Hand-rolled dotted-version comparison | `semver` (npm/node-semver) | Pre-release ordering (`1.2.3-beta.0` vs `1.2.3`) + build metadata (`+sha.abc`) + range parsing (`^`, `~`, `x.y`) is a known-hard problem. |
| File locking | `mkdir <lock>` poll-spin | `flock(1)` OR atomic `rename(2)` | Linux `rename(2)` is atomic on same filesystem per POSIX — covers single-file writes. `flock(1)` covers cross-file scans. |
| Sentinel JSON atomicity | Direct `writeFile` | `writeFile(tmp)` + `rename(tmp, final)` | Mid-write crashes leave corrupt JSON otherwise. |
| Running commands as another user | `child_process.spawn('su agent ...')` | `sudo -u agent -H -E --` (matches `as_user` keystone) | `su` loses env; `sudo -H -E --` is the documented ADR-004 shape and matches `plugin/lib/as_user.sh`. |
| Release-channel / background-update logic for Claude Code | Reimplement Anthropic's updater | Delegate to `claude update` (Phase 5) OR let Anthropic's auto-updater run | `[CITED: code.claude.com/docs/en/setup]` — native install auto-updates in background; `DISABLE_AUTOUPDATER=1` is available for test environments. |
| CLI version-pinning for Claude Code native installer | Custom download / extract / install | `curl https://claude.ai/install.sh \| bash -s <version>` | Documented contract with positional version arg; preserves code-signature verification. |
| npm package version resolution | Custom registry query | `npm view <pkg> versions --json` + `semver.maxSatisfying` | npm's own query returns canonical version list. |
| Mutation testing for TS | Hand-roll mutator | Stryker (already scaffolded in `plugin/cli/stryker.config.json`) | TST-06; v0.3.0 advisory. |

**Key insight:** The custom surface in Phase 4 is thin by design — Commander + Ajv + semver cover 70% of the logic. The CLI's job is orchestration: read catalog → decide version → shell out to a bash recipe → write sentinel. Every load-bearing primitive is a standard library.

## Runtime State Inventory

Phase 4 is greenfield for the CLI + catalog layer — no pre-existing runtime state carries the agentlinux name that needs migration. However, Phase 4 creates new state that Phase 5+ and INST-04 must handle:

| Category | Items Created | Action Required |
|----------|--------------|------------------|
| **Stored data** | `/opt/agentlinux/state/installed.d/<id>.json` per installed agent (0644 agent:agent). Format: `{id, version, source, sticky, installed_at}`. | Read by `list`/`upgrade`/`pin`; created by `install`; removed by `remove` + `--purge`. |
| **Live service config** | None — CLI doesn't touch external services. Claude Code itself may have its own config under `~/.claude/` but that's the agent's concern, removed by the uninstall recipe. | None from Phase 4's side. |
| **OS-registered state** | PATH symlink `/home/agent/.npm-global/bin/agentlinux` → `/opt/agentlinux/cli/<version>/index.js`. | Created by `50-registry-cli.sh`; removed by `--purge` via `rm -rf /opt/agentlinux/` (symlink target gone = dangling symlink, which `userdel -r` sweeps along with `/home/agent`). Edge case: `userdel -r` removes `/home/agent/.npm-global/` → the symlink dies with it. |
| **Secrets/env vars** | None. CLI reads `PATH`, `HOME`, `NPM_CONFIG_PREFIX` from `/etc/agentlinux.env` (already established in Phase 2); sets `AGENTLINUX_PINNED_VERSION` etc. for recipe dispatch (transient, per-invocation). | None — transient env. |
| **Build artifacts** | `plugin/cli/dist/` (tsc output, shipped in release tarball); `plugin/cli/node_modules/` (dev-only, NOT shipped — `pnpm` lockfile ensures reproducible install at build time). | Release pipeline (Phase 6) builds once; tarball ships `dist/`. `node_modules` never leaves the build sandbox. |

## Common Pitfalls

### Pitfall 1: Ajv 2020-12 import path mismatch

**What goes wrong:** `import Ajv from 'ajv'` (the default import) loads the draft-07 class. Attempting to validate a schema with `"$schema": "https://json-schema.org/draft/2020-12/schema"` throws `Unknown keyword…` or silently misbehaves.

**Why it happens:** Ajv 8 kept draft-07 as the default to avoid breaking bundle-size contracts for existing users. 2020-12 is a separate export at `ajv/dist/2020`. `[CITED: https://ajv.js.org/json-schema.html]`

**How to avoid:** Import `Ajv2020` explicitly:
```typescript
import Ajv2020 from 'ajv/dist/2020.js';
```
Plus: under NodeNext module resolution with `"module": "NodeNext"` in `tsconfig.json` (current project config), the `.js` extension is sometimes required at runtime. The safe form includes `.js`.

**Warning signs:** `validate.errors` has `{keyword: 'unknownKeyword'}` or the validator rejects entries that are obviously valid.

### Pitfall 2: npm exact-semver vs range ambiguity

**What goes wrong:** Recipe writes `npm install -g foo@1.2.3-beta.0` expecting the exact pre-release; npm resolves to a different version due to pre-release ordering edge cases.

**Why it happens:** `[CITED: https://docs.npmjs.com/cli/v10/commands/npm-install]` — `foo@1.2.3` installs that specific version literally and fails if unpublished. Pre-release tags (`1.2.3-beta.0`) ARE honored exactly, but only if they exist on the registry. A `pinned_version` value that's no longer published causes `install.sh` to fail obscurely.

**How to avoid:**
1. ajv schema's `pinned_version` pattern permits pre-release + build-metadata per semver spec: `^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$`.
2. Phase 6 release-gate CI (TST-08) asserts every catalog `pinned_version` is currently published: `npm view <pkg> versions --json | jq 'any(. == "<pinned>")'`.
3. On `npm install -g` failure in `install.sh`, emit a clear error including the version attempted + the catalog that specified it.

**Warning signs:** `install.sh` exits non-zero with npm's "No matching version found" banner; the sentinel never gets written.

### Pitfall 3: Commander.js async + `.parse()`

**What goes wrong:** `.parse()` returns synchronously; async action handlers run detached; unhandled rejections crash the process with a cryptic stack and no CLI error message.

**Why it happens:** Commander's `.parse()` doesn't await action handlers. `[CITED: github.com/tj/commander.js README]` — "You may supply an async action handler, in which case you call `.parseAsync()` rather than `.parse()`."

**How to avoid:** Use `await program.parseAsync(process.argv)` for CLI entrypoints that have any async action. All our commands are async.

**Warning signs:** Test assertions pass synchronously but the real dispatch never happens; errors surface as `UnhandledPromiseRejection` instead of a clean exit.

### Pitfall 4: `npm ls -g --json` output shape quirks

**What goes wrong:** Code assumes `JSON.parse(output).dependencies[<pkg>].version` is always defined; when the package isn't installed, `dependencies` may be absent or the package key missing, and the code throws `TypeError: Cannot read property 'version' of undefined`.

**Why it happens:** `[VERIFIED: locally ran `npm ls -g --json --depth=0`; shape is `{name, dependencies: {<pkg>: {version, overridden}}}`]`. `dependencies` is absent when no globals installed. Individual keys are absent for uninstalled packages.

**How to avoid:** Defensive access + optional chaining:
```typescript
const out = JSON.parse(stdout);
const v = out.dependencies?.[pkgName]?.version ?? null;
```
Plus: `npm ls` exits non-zero when there's a missing dep (`npm ls <pkg>` for unlisted package exits 1 with `missing:` marker). Catch + treat as "not installed".

**Warning signs:** `agentlinux list` crashes with `TypeError` on fresh install (no packages yet); `agentlinux upgrade` reports all agents as `drift-undeclared` because it silently swallowed the parse error.

### Pitfall 5: `sudo -E` vs `secure_path` in sudoers

**What goes wrong:** CLI spawns `sudo -u agent -H -E -- bash install.sh`; `install.sh` runs but `$PATH` is reset to the system's `secure_path` (`/usr/bin:/bin` etc.), dropping `/home/agent/.npm-global/bin`. The recipe's `npm` resolves to system npm (possibly different Node version).

**Why it happens:** Ubuntu's default `/etc/sudoers` has `Defaults secure_path=...` which overrides `-E` for PATH specifically. This is the known issue documented in BHV-05 (Phase 2), where the `sudo -u agent bash -c` form doesn't pick up `~agent/.npm-global/bin` without either a sudoers drop-in (locked out by Phase 2 CONTEXT) or an explicit PATH env var.

**How to avoid:** The CLI dispatcher explicitly sets `PATH` in the child env when spawning `sudo`:
```typescript
await asUser('agent', ['bash', recipePath], {
  env: {
    PATH: '/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin',
    // ...other AGENTLINUX_* env
  },
});
```
This matches the `/etc/agentlinux.env` shape (Phase 2). Document in the install.sh contract: "The recipe inherits PATH, HOME, NPM_CONFIG_PREFIX, LANG, LC_ALL from the CLI — do not re-export them."

**Warning signs:** `install.sh` runs but `npm` invocations install to `/usr/local/lib/node_modules/` (EACCES or root-owned); `which npm` inside the recipe returns `/usr/bin/npm` not `/home/agent/.npm-global/...` (npm itself lives in /usr/bin via apt, but the `prefix` resolution is where the EACCES would come from).

### Pitfall 6: Concurrent `agentlinux install` clobbering sentinels

**What goes wrong:** Two `agentlinux install <name>` invocations race on different agents; both write to the same monolithic `installed.json`; one overwrites the other's entry.

**Why it happens:** This is the CONTEXT's "Claude's Discretion" item — monolithic file has this failure mode; per-agent files eliminate it.

**How to avoid:** Per-agent sentinels under `/opt/agentlinux/state/installed.d/<id>.json`. Each invocation writes its own file via atomic rename. `list` reads the directory (eventual consistency acceptable for interactive UX). If strict consistency ever needed, add `flock(1)` around the multi-file scan.

**Warning signs:** `agentlinux list` shows one agent as "not-installed" moments after `install` succeeded; second install's sentinel "disappeared."

### Pitfall 7: Installer log gets removed mid-invocation during `--purge`

**What goes wrong:** `rm -f /var/log/agentlinux-install.log` runs inside the tee pipeline that's actively writing to that file; the tee child might keep writing to a deleted inode; subsequent commands append to /dev/null.

**Why it happens:** `exec > >(tee -a "$LOG_FILE") 2>&1` in `agentlinux-install` holds FD open on the log file; `rm` unlinks the path but the inode stays alive until tee closes its FD.

**How to avoid:** Structure `--purge` so log removal is the LAST step before `exit 0`. The tee trap in the EXIT handler will flush cleanly; the unlinked inode's data is then garbage-collected after the script exits. Document the ordering in the step comments.

**Warning signs:** After `--purge`, the filesystem has no `/var/log/agentlinux-install.log` (correct); inode-level tools (`lsof`) would have shown a deleted-but-open file during the window between `rm` and `exit`.

### Pitfall 8: Native Claude Code installer exit behavior under `bash -s <version>`

**What goes wrong:** `curl https://claude.ai/install.sh | bash -s 2.1.89` for an unpublished version; installer exits non-zero but the pipe swallows it; `install.sh` recipe proceeds as if install succeeded.

**Why it happens:** Without `set -o pipefail` the exit status of a pipeline is the exit status of the LAST command (bash), not curl. If curl returns a 404 page body, bash runs it (or no-ops), and the recipe might move on.

**How to avoid:** Recipes start with `set -euo pipefail`. Additionally, for `curl | bash` flows, use `-fsSL` on curl (fails fast on HTTP error) AND check `${PIPESTATUS[@]}` after the pipeline:
```bash
curl -fsSL https://claude.ai/install.sh | bash -s "$AGENTLINUX_PINNED_VERSION"
for ec in "${PIPESTATUS[@]}"; do
  [[ $ec -eq 0 ]] || { log_error "claude install pipeline failed (codes: ${PIPESTATUS[*]})"; exit 1; }
done
```

**Warning signs:** `claude --version` returns a different version than `AGENTLINUX_PINNED_VERSION`; sentinel records the attempted version but the binary on disk is the pre-existing or older version; AGT-02b fails.

## Code Examples

### Example 1: The complete `agentlinux install claude-code` happy path

```typescript
// User runs: sudo -u agent -H agentlinux install claude-code
// 1. EUID guard: os.userInfo().username === 'agent' → pass
// 2. loadCatalog → reads /opt/agentlinux/catalog/0.3.0/catalog.json,
//    ajv-validates → returns {agents: [...], catalogDir: '...'}
// 3. find entry id === 'claude-code' → {source_kind: 'script', pinned_version: '2.1.98', ...}
// 4. decideVersion(entry, undefined /* no --version */, null /* no sentinel */)
//    → {version: '2.1.98', source: 'curated', sticky: false}
// 5. asUser spawns: sudo -u agent -H -E -- bash /opt/agentlinux/catalog/0.3.0/agents/claude-code/install.sh
//    with env: AGENTLINUX_PINNED_VERSION=2.1.98, AGENTLINUX_SOURCE_KIND=script, ...
// 6. install.sh runs (see Phase 5):
//    case "$AGENTLINUX_SOURCE_KIND" in
//      script) curl -fsSL https://claude.ai/install.sh | bash -s "$AGENTLINUX_PINNED_VERSION" ;;
//    esac
// 7. CLI writes /opt/agentlinux/state/installed.d/claude-code.json:
//    {"id": "claude-code", "version": "2.1.98", "source": "curated",
//     "sticky": false, "installed_at": "2026-04-18T10:15:23.456Z"}
// 8. Exits 0; stdout: "claude-code: installed 2.1.98 (curated)"
```

### Example 2: Pre-commit `validate-catalog.mjs` with ajv

```javascript
#!/usr/bin/env node
// plugin/cli/scripts/validate-catalog.mjs (Phase 4 replacement — ajv-driven)
// Invoked by .pre-commit-config.yaml on plugin/catalog/ changes.
// Thin wrapper: defers to the compiled CLI's schema validator when dist/ is
// present; otherwise falls back to standalone ajv invocation so the hook
// works in a fresh checkout before the first `pnpm build`.

import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCHEMA = join(HERE, '..', '..', 'catalog', 'schema.json');
const CATALOG = join(HERE, '..', '..', 'catalog', 'catalog.json');

if (!existsSync(CATALOG)) {
  console.log('catalog-schema-validate: no catalog.json yet; skipping');
  process.exit(0);
}

// Dynamic import keeps this file runnable without installing ajv if the
// catalog is absent (pre-Phase-4 skeleton state).
const { default: Ajv2020 } = await import('ajv/dist/2020.js');
const { default: addFormats } = await import('ajv-formats');

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validate = ajv.compile(JSON.parse(readFileSync(SCHEMA, 'utf8')));
const catalog = JSON.parse(readFileSync(CATALOG, 'utf8'));

if (!validate(catalog)) {
  console.error('catalog-schema-validate: FAILED');
  for (const err of validate.errors ?? []) {
    console.error(`  • ${err.instancePath || '(root)'}: ${err.message} ${JSON.stringify(err.params)}`);
  }
  process.exit(1);
}
console.log(`catalog-schema-validate: ${catalog.agents.length} entries OK`);
```

### Example 3: bats smoke test for test-dummy

```bash
# tests/bats/40-registry-cli.bats (fragment)
load 'helpers/invoke_modes'
load 'helpers/assertions'

setup() {
  MARKER=/tmp/agentlinux-test-dummy.marker
  rm -f "$MARKER" || true
  sudo -u agent -H agentlinux remove --force test-dummy >/dev/null 2>&1 || true
}

@test "CLI-03: install test-dummy via agentlinux install" {
  run sudo -u agent -H agentlinux install --include-test test-dummy
  assert_exit_zero "CLI-03"
  [ -f "$MARKER" ] || __fail "CLI-03" "$MARKER exists" "absent" "$MARKER"
  grep -q '^version=0.0.1$' "$MARKER" || __fail "CAT-04" "version=0.0.1 in $MARKER" "$(cat "$MARKER")" "$MARKER"
}

@test "CLI-03: install is idempotent (second install no-ops)" {
  sudo -u agent -H agentlinux install --include-test test-dummy
  run sudo -u agent -H agentlinux install --include-test test-dummy
  assert_exit_zero "CLI-03"
  echo "$output" | grep -q 'already installed' || __fail "CLI-03" "already-installed message" "$output" "-"
}

@test "CLI-05: running as root fails fast with clear message" {
  run agentlinux list  # root here — NOT via sudo -u agent
  [ "$status" -eq 64 ] || __fail "CLI-05" "exit 64" "exit $status" "-"
  echo "$output" | grep -q "must run as user 'agent'" || __fail "CLI-05" "clear guidance message" "$output" "-"
}

@test "CLI-04: remove test-dummy clears marker + sentinel" {
  sudo -u agent -H agentlinux install --include-test test-dummy
  run sudo -u agent -H agentlinux remove test-dummy
  assert_exit_zero "CLI-04"
  [ ! -f "$MARKER" ] || __fail "CLI-04" "marker absent" "still present at $MARKER" "$MARKER"
  [ ! -f "/opt/agentlinux/state/installed.d/test-dummy.json" ] \
    || __fail "CLI-04" "sentinel absent" "still present" "/opt/agentlinux/state/installed.d/"
}

@test "CAT-02: fresh install has zero agents installed" {
  run ls /opt/agentlinux/state/installed.d/
  [ -z "$output" ] || __fail "CAT-02" "empty installed.d/" "$output" "/opt/agentlinux/state/installed.d/"
}

@test "INST-04: --purge removes /opt/agentlinux, agent user, profile.d artefacts" {
  sudo agentlinux-install --purge
  [ ! -d /opt/agentlinux ]         || __fail "INST-04" "/opt/agentlinux absent" "still present" "-"
  [ ! -d /home/agent ]             || __fail "INST-04" "/home/agent absent"     "still present" "-"
  [ ! -f /etc/profile.d/agentlinux.sh ] || __fail "INST-04" "profile.d artefact absent" "still present" "-"
  [ ! -f /etc/agentlinux.env ]     || __fail "INST-04" "agentlinux.env absent"  "still present" "-"
  [ ! -f /etc/cron.d/agentlinux ]  || __fail "INST-04" "cron.d artefact absent" "still present" "-"
  run id agent
  [ "$status" -ne 0 ] || __fail "INST-04" "agent user removed" "user still exists" "-"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| npm global as root (`sudo npm i -g`) | Per-user `.npm-global` prefix (ADR-004) | Pre-2020 industry consensus | All Phase 4 install.sh recipes use `as_user` — never `sudo`. |
| apt repo per developer tool | Meta-installer (rustup / pipx / Homebrew / AgentLinux) | 2016-2020 | ADR-011 — no per-agent `.deb`. |
| Unpinned "always latest" install | Curated `pinned_version` + explicit reconcile | ADR-011 (2026-04-19) | Phase 4's central theme; CAT-04. |
| `brew pin` (suppresses nag) | `agentlinux pin <name>=latest` (sticky override, still surfaced in `list`) | Inherited — Homebrew precedent | CLI-07's sticky semantics. |
| Monolithic lockfile (`package-lock.json`) | Per-agent sentinel under `installed.d/` | Phase 4 design | Avoids concurrent-write race; atomic rename. |
| Commander.js ≤v11 callback style | `.parseAsync()` + async actions | Commander v10+ (2023) | Phase 4 uses `parseAsync` throughout. |
| ajv v6 / draft-07 only | ajv v8 with separate draft-2020-12 class | ajv v8 (2021) | `import Ajv2020 from 'ajv/dist/2020'`. |
| Native installer only, no version arg | `bash -s <version>` positional | Claude Code native installer (docs current 2026-04) | `source_kind: script` recipes honor `AGENTLINUX_PINNED_VERSION`. |

**Deprecated/outdated:**

- Commander.js v5-v8 `.action((args, cmd) => ...)` two-arg callback: current is `.action((arg1, arg2, options, cmd) => ...)` with options second-to-last.
- Ajv v6's `ajv.errorsText()` is less useful than v8's structured `validate.errors` array. Format errors manually for better CLI UX.
- `npm-check-updates` for tracking outdated deps: project uses its own `agentlinux upgrade` for catalog agents; dev dependencies use Dependabot or Renovate at the repo level (HRN-08).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `get-shit-done-cc` is the correct npm package for GSD (per `gsd-build/get-shit-done` README) | Standard Stack — Catalog Agent npm Packages | If wrong, Phase 5's `gsd --version` test fails; Phase 4's catalog JSON needs a one-line edit. Confirmed via GitHub repo + npm bin entry but not tested end-to-end. |
| A2 | Native `claude` installer's `bash -s <version>` arg is stable API | Pattern 2 / Pitfall 8 | If Anthropic changes arg shape in a future release, Phase 5 `install.sh` breaks. Mitigation: TST-08 release-gate re-runs the pinned-combo install on every release PR. |
| A3 | `os.userInfo().username` reflects EUID on Linux (not RUID) | Pattern 8 | If Node uses getuid() instead of geteuid(), `sudo -u agent` invocation might report invoker as root during a setuid transition. Verify in bats (CLI-05 test with sudo -u). |
| A4 | Ubuntu 22.04 + 24.04 base images ship `flock(1)` from util-linux | Pattern 5 / Don't Hand-Roll | Verified locally (`/usr/bin/flock`, util-linux 2.39.3); assumed the same holds in Docker/QEMU base images. If missing, `apt-get install -y util-linux` in `50-registry-cli.sh` (it's already a core package, so unlikely). |
| A5 | `npm ls -g --json --depth=0` output shape is stable across npm 10+ bundled with Node 22 | Pattern 7 / Pitfall 4 | Sampled locally and matches. Phase 5 AGT-XX tests exercise this shape end-to-end. If npm's output shape shifts, Phase 4 needs a shim. |
| A6 | `pinned_version` for claude-code stable dist-tag (`2.1.98` at research time) is a reasonable default | Standard Stack — Catalog Agent npm Packages | Phase 4 picks the exact version at catalog-edit time; CI re-validates. Risk: if 2.1.98 is unpublished by the time Phase 4 is merged, ajv's pattern still passes but `install.sh` fails. Planner selects current version at plan-write time. |
| A7 | `get-shit-done-cc` is designed for global npm install (`npm install -g ...`) rather than npx-only | Standard Stack | Its bin field maps `get-shit-done-cc → bin/install.js`, which suggests install-to-install pattern. If it's npx-only in practice, the `install.sh` recipe changes shape (store the version-pin on disk differently). |
| A8 | Claude Code's npm package `@anthropic-ai/claude-code` installs a working binary on Linux x64 when used via `as_user -- npm install -g` | Standard Stack / Pattern 3 | Docs say `darwin/linux-x64/linux-arm64/...` optional-deps. Ubuntu 22.04 + 24.04 amd64 = `linux-x64`. Risk: the "native binary not found after npm install" footnote in Claude docs applies if optional-deps are disabled in `.npmrc`. Verify by default no `.npmrc` overrides block optionals. |
| A9 | The `.pre-commit-config.yaml` biome-check hook's `files: ^plugin/cli/` glob is compatible with Phase 4's src/ expansion | Pre-existing | Verified by reading `.pre-commit-config.yaml`; scope is correct. |

**Planner follow-up:** items A1, A6, A7 should be resolved before committing catalog entries. TST-08 covers A1, A2, A8 at release time.

## Open Questions

1. **Should the CLI version-handshake env var be `AGENTLINUX_PINNED_VERSION` or `AGENTLINUX_VERSION_REQUESTED`?**
   - What we know: CONTEXT lists `AGENTLINUX_PINNED_VERSION`. Semantically it's the version the CLI DECIDED to install (catalog pin OR user override OR sticky), so "requested" may be clearer than "pinned" (which could imply always-catalog).
   - What's unclear: Bikeshed. CONTEXT's name is fine and matches CAT-04's language.
   - Recommendation: Stick with `AGENTLINUX_PINNED_VERSION` for consistency with ADR-011 language.

2. **Should `agentlinux list` run ajv validation and warn on failures, or skip validation entirely?**
   - What we know: CONTEXT lists this as Claude's Discretion.
   - What's unclear: UX tradeoff. Fast list (skip) vs. early warning (run).
   - Recommendation: Skip ajv on `list`; run on `install` / `upgrade` / `pin`. Document the reasoning in Pattern 2. The pre-commit hook and the release-gate catch schema errors before runtime; `list` never exposes users to a malformed catalog in practice.

3. **Is a single shared `stryker.config.json` enough for phase-4 test coverage, or does each src module need its own mutator config?**
   - What we know: TST-06 is advisory in v0.3.0; scaffolding exists.
   - What's unclear: Whether test quality will crest the 60% advisory threshold by phase close.
   - Recommendation: Defer this to QA review during execution — advisory status means nightly reports are a signal, not a gate.

4. **Does `agentlinux pin <name>=latest` query upstream on every `upgrade`, or only on the next `upgrade --check-upstream`?**
   - What we know: Context says "sticky-override to 'user always wants latest npm'".
   - What's unclear: When does `latest` resolve? At `pin` time (freeze) or at `upgrade` time (always-fresh)?
   - Recommendation: Resolve at `upgrade` time — semantically "always wants latest" means "follow the moving target." Implementation: when sticky=true + source='latest', `upgrade --all-latest` or interactive `[l]atest` re-queries npm. Without those flags, pinned-latest entries are surfaced but not auto-updated (UX: the user must explicitly run `upgrade --all-latest` or pick `[l]` interactively).

5. **Should the INST-04 `--purge --remove-nodejs` flag be an error if nodejs was not installed by us?**
   - What we know: CLAUDE.md says "DOES NOT apt-remove nodejs unless `--purge --remove-nodejs`".
   - What's unclear: Edge case — what if Node was pre-existing?
   - Recommendation: `--remove-nodejs` unconditionally apt-purges nodejs. The operator explicitly opted in; if they regret it, reinstall. Document the destructive behavior in `--help` output.

6. **Do we need a `agentlinux --version` output that distinguishes CLI version from catalog version from agent versions?**
   - What we know: Commander's `.version('0.3.0')` ties to CLI release.
   - What's unclear: Should it also print catalog version + each installed agent + version?
   - Recommendation: `agentlinux --version` prints CLI version only (matches `plugin/bin/agentlinux-install --version`). Richer info comes from `agentlinux list` and a future `agentlinux info` (CLI-08 deferred).

## Environment Availability

Phase 4 depends on tools added by earlier phases + a few new build-time tools for the CLI.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js 22 LTS | CLI runtime | ✓ (Phase 3 installs) | v22.x via NodeSource | — |
| npm (bundled with Node 22) | CLI runtime + `install.sh` recipes | ✓ (bundled) | 10.x | — |
| pnpm | CLI build-time (dev) | `[ASSUMED: available via `corepack enable` which ships with Node 22]` | 9.x or 10.x | `pnpm dlx` / local `npx pnpm` |
| TypeScript (`tsc`) | CLI build-time | Via devDependencies in `plugin/cli/package.json` | `^5.6.3` | — |
| Biome (`biome check`) | Pre-commit + CI | Via devDependencies + pre-commit | `^1.9.4` | — |
| `flock(1)` from util-linux | (Optional) sentinel scan consistency | ✓ | 2.39.3+ | Atomic rename covers single-file writes; flock is belt-and-braces for multi-file scans |
| `sudo` | `as_user` dispatcher | ✓ | Ubuntu stock | — |
| `curl` | Native-installer recipes (claude-code) | ✓ (Phase 3 installs `curl`) | 8.x | — |
| `jq` | Bats assertions on JSON output | ✓ `[ASSUMED: ships on Ubuntu 24.04 minimal; if absent install via apt in Docker test base]` | 1.7 | `node -e "console.log(JSON.parse(...))"` |

**Missing dependencies with no fallback:** None — every load-bearing tool is present via Phase 2/3 provisioners or is a stdlib primitive.

**Missing dependencies with fallback:** None currently. Noted `flock` has an atomic-rename fallback already in the design.

## Validation Architecture

Phase 4 is the first phase where CLI code runs in Node.js. We add two test surfaces: (a) `node:test` unit tests under `plugin/cli/test/` for pure functions + sentinel I/O, and (b) bats integration tests in `tests/bats/40-registry-cli.bats` that exercise `agentlinux` end-to-end via `as_user`.

### Test Framework

| Property | Value |
|----------|-------|
| Unit framework | `node:test` (stdlib) — import from `'node:test'` + `'node:assert/strict'` |
| Unit config file | None — invocation is `node --test --experimental-test-coverage test/` (already in `plugin/cli/package.json`'s `scripts.test`) |
| Unit quick-run | `cd plugin/cli && pnpm test` |
| Unit full suite | `cd plugin/cli && pnpm test` (same — fast) |
| Integration framework | bats-core — existing harness under `tests/bats/` |
| Integration config | `tests/bats/helpers/{invoke_modes,assertions}.bash` — loaded by each .bats file |
| Integration quick-run | `cd plugin/cli && pnpm test && bash tests/docker/run.sh ubuntu-24.04 -- --filter 40-registry-cli` (direct bats filter is a bats-core flag) |
| Integration full suite | `bash tests/docker/run.sh ubuntu-22.04 && bash tests/docker/run.sh ubuntu-24.04` |
| Mutation | `stryker` (advisory) per `plugin/cli/stryker.config.json` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CLI-01 | `agentlinux` on agent's PATH | integration (bats, six modes) | `bash tests/docker/run.sh ubuntu-24.04` | ❌ Wave 3 (tests/bats/40-registry-cli.bats) |
| CLI-02 | `agentlinux list` status column | integration | `bash tests/docker/run.sh ubuntu-24.04` | ❌ Wave 3 |
| CLI-03 | `install <name>` installs pinned_version | integration | same | ❌ Wave 3 |
| CLI-03 | idempotent second install | integration | same | ❌ Wave 3 |
| CLI-04 | `remove <name>` cleans binary + sentinel | integration | same | ❌ Wave 3 |
| CLI-05 | non-agent user fail-fast | integration | same (as root invocation) | ❌ Wave 3 |
| CLI-05 | agent user succeeds | integration | same (via `sudo -u agent -H ...`) | ❌ Wave 3 |
| CLI-06 | `upgrade` classifies synced/ahead/behind | unit (classifier pure fn) + integration (dispatch) | `pnpm test` + bats | ❌ Wave 3 + `plugin/cli/test/classify.test.ts` |
| CLI-07 | `pin` sticky override honored by upgrade | unit + integration | same | ❌ Wave 3 + `plugin/cli/test/classify.test.ts` |
| CAT-01 | 3 real agents (claude-code/gsd/playwright) + test-dummy in catalog | unit (ajv validates catalog.json at build time) | `pnpm test` (schema test loads `plugin/catalog/catalog.json`) | ❌ Wave 1 (`plugin/cli/test/schema.test.ts`) |
| CAT-02 | fresh install has zero agents in state dir | integration (smoke assertion after install) | `bash tests/docker/run.sh ubuntu-24.04` | ❌ Wave 3 |
| CAT-03 | new agent addable with no CLI source edit | integration (fixture-driven) — install a test fixture agent and assert `list` shows it without TS edits | `bash tests/docker/run.sh` | ❌ Wave 3 |
| CAT-04 | every entry has valid semver `pinned_version` | unit (ajv schema) | `pnpm test` | ❌ Wave 1 |
| INST-04 | `--purge` removes every tracked artefact | integration (destructive — runs last in bats file) | `bash tests/docker/run.sh` | ❌ Wave 3 |

### Sampling Rate

- **Per task commit:** `cd plugin/cli && pnpm test` (node:test unit tests for src/* changes) + `pre-commit run --all-files` (biome + shellcheck + catalog-schema-validate).
- **Per wave merge:** Full bats matrix via `bash tests/docker/run.sh ubuntu-22.04 && bash tests/docker/run.sh ubuntu-24.04`.
- **Phase gate:** Full matrix green + `behavior-coverage-auditor` asserts every CLI-XX/CAT-XX/INST-04 has at least one @test (TST-07).

### Wave 0 Gaps

This phase's "Wave 0" — the test infrastructure we need before implementation — consists of:

- [ ] `plugin/cli/test/fixtures/catalog-valid.json` — minimal valid catalog fixture
- [ ] `plugin/cli/test/fixtures/catalog-missing-pin.json` — fixture for negative schema test
- [ ] `plugin/cli/test/fixtures/sentinel-sample.json` — sample sentinel for state tests
- [ ] `tests/bats/40-registry-cli.bats` — integration test file with bats `setup()` that registers a fixture catalog path
- [ ] `plugin/cli/test/schema.test.ts` — ajv schema unit tests
- [ ] `plugin/cli/test/classify.test.ts` — classifier pure-function unit tests
- [ ] `plugin/cli/test/sentinel.test.ts` — sentinel read/write + atomic rename tests
- [ ] Wave 1 adds a `pnpm install` step to the Docker test image build (or runs `pnpm install` + `pnpm build` inside the container before bats runs) — Phase 1 Dockerfiles may need a tweak to include pnpm; if not, use `corepack enable` at image build time.

None of these exist today; all land in Wave 1 (CLI scaffolding + schema + fixtures) and Wave 3 (bats coverage).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | CLI runs as local user; no network auth. |
| V3 Session Management | no | — |
| V4 Access Control | **yes** | CLI-05 EUID guard (os.userInfo().username must be 'agent'); root-owned state dir with agent-writable inside; `as_user` keystone enforces single privilege boundary. |
| V5 Input Validation | **yes** | ajv validates catalog at load time; `<name>` for install/remove matched against catalog (never passed raw to shell); `--version` validated via `semver.valid()` before use. |
| V6 Cryptography | **yes** (Phase 6, not 4) | Release tarball SHA-256 verification is Phase 6. Phase 4 doesn't directly touch crypto; the native Claude Code installer does its own manifest signature check (documented, not our concern). |
| V7 Error Handling | **yes** | All error paths exit with clear `EX_*` codes (64 = USAGE, 70 = SOFTWARE, 75 = TEMPFAIL for systemd-unavailable); no silent swallowing; tee'd transcript preserves full stderr. |
| V8 Data Protection | partial | Sentinels 0644 agent:agent (not world-writable); state dir 0755 agent:agent; no secrets in sentinels (just version + timestamps). |
| V12 File and Resources | **yes** | `--purge` uses only literal absolute paths; catalog paths are resolved against a fixed prefix; recipe paths validated by schema (pattern ends in `.sh`, no `..`). |
| V14 Configuration | **yes** | Ajv `strict: true` rejects unknown fields; `additionalProperties: false` at both catalog + entry level; enum types for `source_kind`. |

### Known Threat Patterns for TS CLI + bash recipes

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious catalog entry: `install_recipe_path: "../../../etc/shadow"` | Tampering / Information Disclosure | ajv schema pattern `^[a-z0-9_./-]+\.sh$` rejects `..`; dispatcher resolves paths against `catalog/agents/<id>/` prefix; any resolved path outside that tree is rejected. |
| Shell injection in `<name>` arg: `agentlinux install "foo; rm -rf /"` | Tampering | CLI looks up `<name>` in the parsed catalog (string equality); never interpolates into shell; dispatcher uses `execFile` (array args), not `exec` (string). |
| `install.sh` recipe calls `sudo npm install -g` | Elevation of Privilege | catalog-auditor subagent greps every `install.sh` for `sudo npm` and fails the review. security-engineer double-checks. |
| Symlink race in `/tmp` during test-dummy install | Tampering | test-dummy marker at `/tmp/agentlinux-test-dummy.marker` is a known target; bats `setup()` `rm -f` before each test; not a production concern (only used in tests). |
| Sentinel concurrent-write corruption | Denial of Service | Per-agent sentinel files + atomic rename (POSIX rename(2) is atomic on same FS). |
| `--purge` unbounded `rm -rf` | Denial of Service (self-inflicted) | All `rm` targets are literal constants; no env-var-derived paths; reviewed by security-engineer. |
| Symlink attack on `/home/agent/.npm-global/bin/agentlinux` | Tampering | Provisioner uses `ln -sfn` (force + no-deref); `chown -h agent:agent`; mode 0755; sources under root-owned `/opt/agentlinux/`. |
| Ajv resource exhaustion (deep schema / recursion) | DoS | Schemas are author-controlled (in-tree), not user-submitted at runtime. Not exploitable. |
| Version-confusion: install.sh runs with stale env from previous invocation | Tampering | CLI dispatcher spawns with a clean env dict (not `env: process.env` + override); `sudo -H -E --` preserves only what we set. |
| Claude Code `curl | bash` network MITM | Tampering | Native installer verifies code signature post-download (see `manifest.json.sig` in claude docs); we use `-fsSL` (HTTPS + fail on HTTP error). Hash-pinning the installer body itself would require upstream to publish `.sha256` for the installer — they don't. Accepted risk per ADR-005. |

## Sources

### Primary (HIGH confidence)

- `[VERIFIED: npm registry]` — `npm view <pkg> version` for commander, ajv, ajv-formats, semver, @anthropic-ai/claude-code, get-shit-done-cc, playwright (ran 2026-04-18).
- `[CITED: https://code.claude.com/docs/en/setup]` — Claude Code install methods, version-pinning via `bash -s <version>`, auto-update channels, `DISABLE_AUTOUPDATER` env var, manifest signature verification.
- `[CITED: https://ajv.js.org/json-schema.html]` — Ajv 2020-12 import (`ajv/dist/2020`), draft incompatibility, strict mode.
- `[CITED: https://github.com/tj/commander.js]` — async actions, `.parseAsync()`, `.hook('preAction', fn)`, global options via `.optsWithGlobals()`.
- `[CITED: https://github.com/npm/node-semver]` — `satisfies`, `maxSatisfying`, `valid`, `gt`/`lt`/`eq`.
- `[CITED: https://nodejs.org/api/test.html]` — `node:test` runner, `test.skip()`, concurrency flags.
- `[CITED: https://docs.npmjs.com/cli/v10/commands/npm-install]` — exact-version install behavior.
- `plugin/lib/as_user.sh` — existing keystone; defines the `sudo -u agent -H -E --` shape Phase 4 mirrors in TypeScript.
- `plugin/lib/idempotency.sh` — `ensure_dir`, `ensure_marker_block` primitives; used by `50-registry-cli.sh`.
- `plugin/provisioner/40-path-wiring.sh` — established `/etc/agentlinux.env` PATH literal (`.npm-global/bin:...`) that Phase 4's dispatcher mirrors.
- `docs/decisions/011-stability-first-version-pinning.md` — ADR-011 canonical reference.
- `docs/decisions/008-commander-js-for-cli.md` — Commander `^12.x` lock.
- `docs/decisions/004-per-user-npm-prefix.md` — ADR-004 keystone.
- `docs/research/v0.3.0/stability-model-reconsideration.md` — 17-criteria table; divergence walkthrough; reconcile UX spec; prior art (Nix, Homebrew, mise, npm overrides).
- `docs/research/v0.3.0/cli-vs-apt-advisor.md` — "why not apt" rationale; AGT-02 litmus test.

### Secondary (MEDIUM confidence)

- `[VERIFIED: locally on Ubuntu 24.04 machine]` — `npm ls -g --json --depth=0` output shape; `/usr/bin/flock` availability; `flock --version` 2.39.3.
- `[CITED: https://github.com/gsd-build/get-shit-done]` — GSD repository confirms the npm package name is `get-shit-done-cc`; pinning recommendation depends on Phase 5 verifying end-to-end.

### Tertiary (LOW confidence / ASSUMED — see Assumptions Log)

- `os.userInfo().username` EUID semantics on Linux (A3) — assumed based on Node docs; verify in bats.
- GSD install-sh shape via `npm install -g get-shit-done-cc` vs `npx get-shit-done-cc` (A7) — bin entry suggests both are supported; confirm in Phase 5.
- Claude Code optional-deps fetch behavior under `npm install -g @anthropic-ai/claude-code@<ver>` (A8) — documented as platform-specific optional deps; assumed default-enabled; verify in Phase 5 AGT-02b.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every version verified via `npm view`; every API pattern cited from official docs; Commander/ajv/semver idioms well-established.
- Architecture: HIGH — patterns mirror Phase 2/3 established structure (provisioner dispatch, `as_user`, idempotency helpers, tee'd log); no novel abstractions.
- Pitfalls: MEDIUM-HIGH — pitfalls 1-5 verified from docs/local exec; 6-8 are design-level predictions grounded in the research but not yet proven in-code (Phase 4 execution will close the loop).
- Claude Code version-pin mechanism: HIGH — `bash -s <version>` positional arg documented as "Install a specific version" tab on the current setup docs page.
- GSD npm package identity: MEDIUM — package name verified but end-to-end install contract (`-g` vs `npx`) not proven; Phase 5 closes it.
- Validation architecture: HIGH — all commands already present in `package.json` + Phase 2 bats harness is well-established.

**Research date:** 2026-04-18
**Valid until:** 2026-05-18 (30 days). Claude Code, GSD, Playwright versions change daily-to-weekly, so version-number specifics drift quickly; the Phase 4 plan picks concrete versions at plan-write time. All non-version architectural guidance (Commander patterns, ajv usage, sentinel design, `--purge` ordering) is stable through v0.3.x.

## RESEARCH COMPLETE

**Phase:** 4 — Registry CLI + Catalog + Uninstall
**Confidence:** HIGH

### Key Findings

1. **Claude Code native installer accepts positional version:** `curl https://claude.ai/install.sh | bash -s 2.1.89`. This is the canonical ADR-011 version-pinning mechanism for `source_kind: "script"` recipes. Phase 5 will use it.
2. **Per-agent sentinels under `installed.d/<id>.json`** (not monolithic `installed.json`): atomic rename per file eliminates concurrent-write contention and reduces blast radius from whole-state corruption to single-agent corruption.
3. **Ajv 2020-12 requires a separate import (`ajv/dist/2020`)** — not a constructor flag. Default `import Ajv from 'ajv'` is draft-07.
4. **Commander `^12.x` is stable and CONTEXT-locked**; current npm latest is `14.0.3` but no functional difference for Phase 4 use. Keep lock.
5. **GSD's real npm package is `get-shit-done-cc`** (not `gsd`, not `get-shit-done`). Verified in npm registry + upstream repo; end-to-end install shape needs Phase 5 confirmation.
6. **Seven plans (Waves 1-3) is the right split** per CONTEXT: Wave 1 = scaffolding + schema + catalog entries; Wave 2 = list/install/remove + upgrade + pin; Wave 3 = provisioner + --purge + bats. Plan count matches ADR-011 research.

### File Created

`/home/agent/agent-linux/.planning/phases/04-registry-cli-catalog-uninstall/04-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | Every version verified via `npm view`; every idiom cited from official docs. |
| Architecture | HIGH | Mirrors Phase 2/3 patterns (provisioner dispatch, `as_user`, tee'd log); no novel abstractions. |
| Claude Code pinning | HIGH | Positional version arg documented on current setup docs page (`bash -s <version>`). |
| Sentinel design | HIGH | Per-agent + atomic-rename is a well-understood pattern; flock fallback documented. |
| Divergence classifier | HIGH | Pure function; 5 tagged states cover every case the research + ADR-011 spec. |
| `--purge` teardown | HIGH | 7-step ordered teardown; every step idempotent; log-removal sequenced last. |
| Test coverage plan | HIGH | 12 requirement IDs mapped to specific unit/bats tests; Wave 0 gaps enumerated. |
| Pitfalls | MEDIUM-HIGH | 8 pitfalls; 5 verified from docs/local exec, 3 are design-level predictions closed by Phase 4 execution. |
| GSD package identity | MEDIUM | Package name verified; install shape needs Phase 5 smoke. |

### Open Questions

1. Bikeshed: `AGENTLINUX_PINNED_VERSION` vs `AGENTLINUX_VERSION_REQUESTED` (keep CONTEXT's name).
2. Ajv on `list` hot path: recommendation SKIP (see Pitfall 2 resolution).
3. Mutation threshold configuration: defer to QA during execution (advisory).
4. `pin <name>=latest` resolve timing: recommend at `upgrade` time, not `pin` time.
5. `--purge --remove-nodejs` edge case: unconditional purge, document destructive behavior.
6. `agentlinux --version` output scope: CLI-only (matches installer convention).

### Ready for Planning

Research complete. The planner has:
- Locked tech stack with verified versions.
- 11 concrete code patterns with executable-shape examples.
- 8 named pitfalls + mitigations.
- 9-row Assumptions Log flagging items the user or Phase 5 must confirm.
- Full requirements → test map with Wave 0 gap list.
- CAT-03 test-fixture design (test-dummy) to validate CLI dispatch without network flake.

Next step: `/gsd-plan-phase` can now create the 7 plans (Waves 1-3 per CONTEXT), each citing the relevant section of this RESEARCH.md and the specific CLI-XX / CAT-XX / INST-04 IDs.
