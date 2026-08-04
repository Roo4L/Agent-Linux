# Phase 4: Registry CLI + Catalog + Uninstall - Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

The `agentlinux` CLI is on the agent's PATH and can list / install / upgrade / remove entries from a JSON-Schema-validated catalog that contains claude-code, gsd, and playwright as *available* (none installed by default). Entries carry a `pinned_version` field (ADR-011): `agentlinux install <name>` installs exactly that version. `agentlinux upgrade` reconciles installed versions against the release's curated pin with explicit 3-way divergence UX. `agentlinux pin` sets sticky overrides so power-users who jump ahead aren't re-nagged. A symmetric `--purge` uninstall path removes what the installer placed.

Requirements in scope: CLI-01..CLI-07, CAT-01..CAT-04, INST-04. (Phase 6 adds CAT-05 catalog-snapshot release artifact; Phase 5 adds AGT-01..AGT-05 + AGT-02b using this CLI to install real agents.)

Out of scope for Phase 4: Actual agents running end-to-end (Phase 5), release pipeline + catalog snapshot sibling (Phase 6), QEMU validation (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### CLI Tech Stack & Packaging
- **Framework:** Commander.js `^12.x` — ADR-008 accepted; unchanged by ADR-011.
- **Package manager:** `pnpm` inside `plugin/cli/` — fast, disk-efficient, lockfile stability. Root workspace remains free of `package.json` per HARNESS.md §1.1.
- **Build shape:** TypeScript source → `tsc` compiled to `plugin/cli/dist/`. Ship `dist/` in the release tarball. Entrypoint `dist/index.js` with `#!/usr/bin/env node` shebang.
- **PATH placement:** Symlink from `/home/agent/.npm-global/bin/agentlinux` → the shipped dist entrypoint. New provisioner `plugin/provisioner/50-registry-cli.sh` runs AFTER `30-nodejs.sh` + `40-path-wiring.sh`, stages the CLI under `/opt/agentlinux/cli/<version>/`, creates the symlink. Agent's existing `.npm-global/bin` on PATH (Phase 3) is why this works without touching PATH wiring.

### Catalog Schema & Entry Shape (extended per ADR-011)
- **Catalog layout:** `plugin/catalog/catalog.json` (entry list) + `plugin/catalog/agents/<name>/install.sh` + `plugin/catalog/agents/<name>/uninstall.sh` per entry. Matches HARNESS.md §1.1 and the CAT-03 "submit entry + recipe" contract.
- **Schema validator:** `ajv` with JSON Schema 2020-12 draft. Validates at CLI-load-time. Phase 1's zero-dep `validate-catalog.mjs` scaffold gets replaced by ajv-driven validation; the pre-commit hook stays.
- **Required fields per entry:** `id` (slug), `display_name`, `description`, `npm_package_name` (for npm-based recipes), `pinned_version` (required, semver per CAT-04/ADR-011), `install_recipe_path`, `uninstall_recipe_path`, `post_install_verify` (optional cmd), `source_kind` (`"npm"` or `"script"` for agents with their own native installer like Claude Code).
- **Optional `version_constraint`:** semver range (e.g. `"^2.1"`) that `--all-latest` upper-bounds against; absent = accept any npm latest.
- **install.sh / uninstall.sh calling convention:** Runs as `as_user` (keystone helper from Phase 2). Receives env vars: `AGENTLINUX_CATALOG_DIR`, `AGENTLINUX_AGENT_HOME`, `AGENTLINUX_PINNED_VERSION` (the version the CLI determined to install — either catalog pin, user override, or `latest`). Exits 0 on success; stdout/stderr tee'd to install log.

### CLI UX (list / install / upgrade / remove / pin)
- **`agentlinux list` output:** Text table: `NAME  STATUS  CURATED  INSTALLED  DESCRIPTION`. Minimal, grep-friendly. `--json` flag for machine output. STATUS shows `not-installed`, `synced`, `override-ahead`, `override-behind`, or `pinned-override` (sticky).
- **Installed-detection:** `/opt/agentlinux/state/installed.json` sentinel per agent, recording `{id, version, source: "curated"|"override"|"latest"|"pinned", installed_at}`. Cross-checked against `sudo -u agent -H npm ls -g --json --depth=0 <pkg>` output for drift detection.
- **`install <name>` idempotency:** If sentinel exists and matches the catalog pin, log "already installed at pinned_version" + exit 0. `--force` re-runs install.sh. `--version <semver>` overrides the catalog pin for this install (sets `source: "override"` in sentinel).
- **`upgrade` verb (CLI-06):** Read sentinel + catalog snapshot + `npm ls -g --json`; classify each agent as `synced`, `override-ahead`, `override-behind`; present per-agent 3-way prompt (`[k]eep override / [c]urated / [l]atest`) or accept bulk flags (`--reset-all-curated`, `--respect-overrides`, `--all-latest`). Writes updated sentinels recording source of each version.
- **`pin` verb (CLI-07):** `agentlinux pin <name>=curated` clears sticky-override flag; `agentlinux pin <name>=latest` sets sticky-override to "user always wants latest npm"; `agentlinux pin <name>=2.1.7` pins to exact version. Flag lives in the sentinel's `source` field (`pinned`). `upgrade` respects the pin (never re-prompts for pinned entries) but `list` still surfaces the divergence.
- **`remove <name>`:** Runs `uninstall.sh` via `as_user`, removes sentinel, cleans empty dirs. Exits non-zero if sentinel missing (no idempotent no-op — force the user to notice) unless `--force`.

### `--purge` Uninstall + Phase 4 Tests
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

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (shipped Phases 1-3)
- `plugin/lib/{log,idempotency,as_user,distro_detect}.sh` — lib primitives, 12 functions.
- `plugin/lib/as_user.sh` — **THE keystone.** Every install.sh invocation goes through `as_user -- npm install -g ...` — never raw `sudo -u`.
- `plugin/bin/agentlinux-install` — dispatches `plugin/provisioner/[0-9][0-9]-*.sh` in sorted numeric order; `--purge` is a stub flag we wire up.
- `plugin/provisioner/{10-agent-user,30-nodejs,40-path-wiring}.sh` — agent user + Node 22 + PATH + npm prefix all done.
- `plugin/catalog/schema.json` + `plugin/catalog/agents/` — scaffolding from Phase 1, now filled in.
- `plugin/cli/` — skeleton from Phase 1 (empty); Phase 4 populates src/.
- `plugin/cli/scripts/validate-catalog.mjs` — zero-dep Phase 1 scaffold; replaced by ajv-driven validator in Phase 4.
- `tests/bats/helpers/{invoke_modes.bash,assertions.bash}` — six-mode helpers and diagnostic assertions (including `assert_user_prefix_in_home` from Phase 3).
- `tests/docker/run.sh` + Dockerfiles — Phase 4 new bats files auto-picked up by the harness.
- `.claude/skills/catalog-schema/SKILL.md` — codifies JSON Schema, install/uninstall contract, CAT-02 no-default invariant. Phase 4 is its first concrete absorption.
- `.github/workflows/test.yml` — `bats-docker` matrix job runs on every PR.

### Established Patterns
- Per-task atomic commits via `git add <files> && git commit --no-gpg-sign -m "..."` — continuing Phase 1/2/3 precedent.
- Every bats `@test` references its requirement ID.
- Review loop before task complete: `node-engineer` + `security-engineer` + `qa-engineer` on new TypeScript; `bash-engineer` + `security-engineer` + `qa-engineer` on new bash; `catalog-auditor` + `security-engineer` on catalog recipes; `qa-engineer` + `behavior-coverage-auditor` on new bats. `behavior-coverage-auditor` at phase close per TST-07.
- Threat model block on every plan (T-04-NN).
- Idempotent primitives for every state mutation.
- `as_user -- cmd args` signature — never `sudo -u agent cmd`.
- Plans consume CONTEXT + RESEARCH + VALIDATION; spawn researcher + planner + plan-checker before executing.

### Integration Points
- `50-registry-cli.sh` provisioner stages CLI under `/opt/agentlinux/cli/<version>/` + symlinks to `/home/agent/.npm-global/bin/agentlinux` (agent-owned PATH already).
- `ajv` validator runs at CLI load and in pre-commit (replacing `validate-catalog.mjs`).
- `install.sh` / `uninstall.sh` receive `AGENTLINUX_PINNED_VERSION` env var from the CLI — this is the ADR-011 mechanism that decouples the CLI (which decides the version) from the recipe (which installs it).
- `agentlinux upgrade` reads catalog snapshot from `/opt/agentlinux/catalog/<version>/catalog.json` (staged by the installer; CAT-05 makes this a Phase 6 release artifact).
- `.github/workflows/test.yml` runs `pnpm --filter plugin/cli test` + the bats matrix; both must be green.

</code_context>

<specifics>
## Specific Ideas

- The `test-only dummy catalog entry` for bats integration tests is crucial for CI speed + determinism. Design: a shell script that `touch`es a sentinel in `/tmp/agentlinux-test-<id>` on install, removes it on uninstall. Validates the CLI's dispatch + sentinel logic without a real npm install. Keep this as a real catalog entry (id `test-dummy`) with `source_kind: "script"` so the CLI code path exercised is identical to real agents; just filter it from `agentlinux list` by default (`--include-test` flag to show it).
- `/opt/agentlinux/state/installed.json` lives in a root-owned directory because the CLI is agent-user-invoked but writes to shared state. Use 0644 file + 0755 dir with `agent:agent` ownership on the file so agent can write it. (Or `/opt/agentlinux/state/` owned `agent:agent` wholesale — simpler.)
- CAT-03 guardrail: extending the CLI source for a new agent must NOT be required. Test this in bats: add a throwaway catalog entry via a test fixture and assert `agentlinux list` shows it without any CLI code change.
- `ajv`-driven schema: schema lives at `plugin/catalog/schema.json` (already scaffolded in Phase 1). Add `pinned_version` (pattern: `^\\d+\\.\\d+\\.\\d+(-[\\w\\.]+)?(\\+[\\w\\.]+)?$` semver), `npm_package_name` (string, required when `source_kind === "npm"`), `source_kind` enum.
- `agentlinux upgrade` MUST NOT reach the network unless user explicitly passes `--check-upstream` — by default, it reconciles against the locally-staged catalog snapshot only (offline-safe; faster). `--all-latest` implies `--check-upstream` (queries `npm view <pkg> version`).
- The `install.sh` for Claude Code (Phase 5 will write it) uses `sudo -u agent -H curl https://claude.ai/install.sh | bash` (native installer) OR `sudo -u agent -H npm install -g @anthropic-ai/claude-code@<pinned>` — decision deferred to Phase 5 but the CLI's recipe-dispatch contract supports either via `source_kind`.

</specifics>

<deferred>
## Deferred Ideas

- **Option C' symlink-profile model** — Nix-style atomic profiles with `agentlinux profile rollback`. Research flagged this as more elegant but adds novel abstractions. v0.4+ UX upgrade on top of A'.
- **Option E' CLI-as-.deb** — ship the `agentlinux` binary itself via a public PPA. Requires INF-01 (deferred to v0.4+). Not needed for v0.3.0 since `.npm-global/bin` already handles PATH.
- **Per-agent `.deb`s (Option B')** — rejected per ADR-011 split-brain + cadence + portability + submitter-friction. Not revisited.
- **Remote-fetch catalog (CAT-06, formerly CAT-04)** — v0.4+. v0.3.0 ships with an embedded catalog snapshot.
- **Multiple install backends per entry (CAT-07, formerly CAT-05)** — v0.4+. v0.3.0 supports `source_kind: npm | script` only.
- **`agentlinux info <name>` (CLI-08)** — v0.4+. `list --verbose` covers the need for now.
- **`agentlinux update <name>` delegating to agent's native updater (CLI-09)** — v0.4+. User runs `claude update` directly for now.
- **`agentlinux doctor` (CLI-10)** — v0.4+. Bats integration tests are the doctor surrogate for now.
- **Auto-update daemon (INF-04)** — v0.4+. User invokes `agentlinux upgrade` explicitly.

</deferred>
