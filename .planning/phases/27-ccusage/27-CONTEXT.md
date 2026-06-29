# Phase 27: ccusage - Context

**Gathered:** 2026-06-29
**Status:** Ready for planning
**Mode:** Autonomous batch (npm cluster 23-27); decisions locked by ROADMAP /
REQUIREMENTS Appendix A.

<domain>
## Phase Boundary
Make `ccusage` (read-only Claude Code cost/usage reporter) installable +
removable via the catalog. Availability only.
</domain>

<decisions>
## Implementation Decisions
- **D-01:** npm `ccusage`, pin `20.0.14`, binary `ccusage` (verified `npm view`
  → `{ ccusage: './src/cli.js' }`). License MIT (GitHub shows NOASSERTION but is
  MIT per REQUIREMENTS Appendix B).
- **D-02:** `source_kind: npm`; cluster recipe pattern; no CLI change (CAT-03).
- **D-03:** Read-only — no token/secret required or accepted; ccusage parses the
  local ~/.claude usage logs. Nothing baked.
- **D-04:** No `preserve_paths.json` — ccusage owns no per-user state of its own
  (the ~/.claude logs belong to Claude Code, not ccusage).
</decisions>

<canonical_refs>
## Canonical References
- `.planning/REQUIREMENTS.md` — WORK-01 + Appendix A/B
- `.planning/ROADMAP.md` §"Phase 27: ccusage"
- `plugin/catalog/agents/codex/` — npm recipe analog (minus preserve_paths)
- `plugin/cli/src/runner.ts` — recipe env contract
</canonical_refs>

<code_context>
## Existing Code Insights
Clone of the cluster npm pattern with no preserve_paths. Test:
`tests/bats/53-catalog-npm-cluster.bats` WORK-01 @test.
</code_context>

<specifics>
## Specific Ideas
First catalog entry with no preserve_paths_file (read-only tool) — exercises the
runner's empty-AGENTLINUX_PRESERVE_PATHS path.
</specifics>

<deferred>
## Deferred Ideas
None.
</deferred>

---
*Phase: 27-ccusage*
*Context gathered: 2026-06-29*
