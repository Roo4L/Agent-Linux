# Phase 23: codex - Context

**Gathered:** 2026-06-29
**Status:** Ready for planning
**Mode:** Autonomous batch (npm cluster 23-27); discuss auto-resolved from the
ROADMAP phase spec (pin, package, bin, requirements, success criteria are all
locked in ROADMAP.md / REQUIREMENTS.md Appendix A).

<domain>
## Phase Boundary

Make `codex` (OpenAI Codex CLI) installable + removable via the catalog
(`agentlinux install codex` / `agentlinux remove codex`), AND deliver the
self-updater-coexistence enabler (ENABLE-05). Availability only — nothing is
installed by default (CAT-02).
</domain>

<decisions>
## Implementation Decisions

### Packaging (locked by ROADMAP / REQUIREMENTS Appendix A)
- **D-01:** npm package `@openai/codex`, pinned `0.142.3`, binary `codex`
  (verified `npm view @openai/codex@0.142.3 bin` → `{ codex: 'bin/codex.js' }`).
- **D-02:** `source_kind: npm` — reuse the established per-user `npm install -g`
  pattern (NPM_CONFIG_PREFIX=/home/agent/.npm-global from runner.ts); no CLI
  source change (CAT-03). Closest analog: `plugin/catalog/agents/gsd/`.
- **D-03:** post-install version-lock — `codex --version` prints
  `codex-cli <ver>`; recipe greps for the pin (fail-fast on mispin, AGT-02b
  shape).

### ENABLE-05 — self-updater coexistence
- **D-04:** Codex ships `codex update` (self-replace) + a startup
  "newer version available" check. Mitigation: the install recipe sets
  `check_for_update_on_startup = false` in `~/.codex/config.toml`
  (idempotent + non-destructive — prepend the top-level key only when absent;
  the key is a recognized config field in the pinned binary). This disables
  the in-app updater so the catalog pin stays authoritative.
- **D-05:** The npm shim exports `CODEX_MANAGED_PACKAGE_ROOT`, so `codex update`
  already detects an npm-managed install and refuses to clobber a different
  target — upstream belt to our braces. Pin authority is also enforced by the
  binary resolving under `/home/agent/.npm-global/bin` (no `/usr/local` shim).
- **D-06:** Updates flow through `agentlinux upgrade codex` (ADR-011 pin), not
  `codex update`.

### Secrets / state
- **D-07:** No secret baked — codex auth is supplied post-install (login/env).
- **D-08:** `~/.codex/` (config + auth) listed in `preserve_paths.json` —
  survives REMEDIATE-04 uninstall+reinstall (CAT-04).
</decisions>

<canonical_refs>
## Canonical References

- `.planning/REQUIREMENTS.md` — AGT-07, ENABLE-05 + Appendix A pins
- `.planning/ROADMAP.md` §"Phase 23: codex" — goal + 5 success criteria
- `plugin/catalog/agents/gsd/{install,uninstall,preserve_paths.json}` — npm
  recipe analog
- `plugin/cli/src/runner.ts` — recipe env contract (NPM_CONFIG_PREFIX, PATH,
  AGENTLINUX_PINNED_VERSION, AGENTLINUX_PRESERVE_PATHS)
- `.claude/skills/catalog-schema/SKILL.md` — recipe + symmetric-uninstall
  contract
</canonical_refs>

<code_context>
## Existing Code Insights

- Reusable: the `gsd` npm recipe (install→version-lock→symmetric remove) is the
  template; codex drops gsd's bootstrapper step and adds the ENABLE-05 config
  edit.
- Integration: `catalog.json` entry + recipe dir is all that is needed — the
  loader/runner dispatch generically by `source_kind` (CAT-03).
- Test: `tests/bats/53-catalog-npm-cluster.bats` (new) — AGT-07 lifecycle +
  ENABLE-05 dedicated @test.
</code_context>

<specifics>
## Specific Ideas

ENABLE-05 verification is concrete (not hand-waved): the bats test asserts the
`check_for_update_on_startup = false` line is present, the binary is npm-managed
under the agent prefix, the version is the pin, and `~/.codex/config.toml`
survives a remove.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. Other ENABLE-05 consumers
(openclaw, Phase 47) reuse this convention.
</deferred>

---
*Phase: 23-codex*
*Context gathered: 2026-06-29*
