# Phase 26: qwen-code - Context

**Gathered:** 2026-06-29
**Status:** Ready for planning
**Mode:** Autonomous batch (npm cluster 23-27); decisions locked by ROADMAP /
REQUIREMENTS Appendix A.

<domain>
## Phase Boundary
Make `qwen-code` (Qwen Code CLI) installable + removable via the catalog.
Availability only.
</domain>

<decisions>
## Implementation Decisions
- **D-01:** npm `@qwen-code/qwen-code`, pin `0.19.2`, binary `qwen` (verified
  `npm view` → `{ qwen: 'cli-entry.js' }`).
- **D-02:** `source_kind: npm`; cluster recipe pattern; no CLI change (CAT-03).
- **D-03:** No secret baked — provider auth (DASHSCOPE_API_KEY / OpenAI-compat)
  post-install.
- **D-04:** `~/.qwen/` preserved across uninstall (CAT-04).
</decisions>

<canonical_refs>
## Canonical References
- `.planning/REQUIREMENTS.md` — AGT-08 + Appendix A
- `.planning/ROADMAP.md` §"Phase 26: qwen-code"
- `plugin/catalog/agents/codex/` — npm recipe analog
- `plugin/cli/src/runner.ts` — recipe env contract
</canonical_refs>

<code_context>
## Existing Code Insights
Clone of the cluster npm pattern. Test: `tests/bats/53-catalog-npm-cluster.bats`
AGT-08 @test.
</code_context>

<specifics>
## Specific Ideas
None.
</specifics>

<deferred>
## Deferred Ideas
None.
</deferred>

---
*Phase: 26-qwen-code*
*Context gathered: 2026-06-29*
