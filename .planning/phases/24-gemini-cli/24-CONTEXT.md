# Phase 24: gemini-cli - Context

**Gathered:** 2026-06-29
**Status:** Ready for planning
**Mode:** Autonomous batch (npm cluster 23-27); decisions locked by ROADMAP /
REQUIREMENTS Appendix A.

<domain>
## Phase Boundary
Make `gemini-cli` (Google Gemini CLI) installable + removable via the catalog.
Availability only (CAT-02).
</domain>

<decisions>
## Implementation Decisions
- **D-01:** npm `@google/gemini-cli`, pin `0.49.0`, binary `gemini` (verified
  `npm view` → `{ gemini: 'bundle/gemini.js' }`).
- **D-02:** `source_kind: npm`; reuse the cluster recipe pattern (install →
  `gemini --version` pin-lock → symmetric remove). No CLI change (CAT-03).
- **D-03:** No secret baked — Google auth (OAuth / GEMINI_API_KEY) post-install.
- **D-04:** `~/.gemini/` preserved across uninstall (CAT-04).
</decisions>

<canonical_refs>
## Canonical References
- `.planning/REQUIREMENTS.md` — AGT-06 + Appendix A
- `.planning/ROADMAP.md` §"Phase 24: gemini-cli"
- `plugin/catalog/agents/codex/` and `.../gsd/` — npm recipe analog
- `plugin/cli/src/runner.ts` — recipe env contract
</canonical_refs>

<code_context>
## Existing Code Insights
Pure clone of the cluster npm pattern (codex minus ENABLE-05). Test:
`tests/bats/53-catalog-npm-cluster.bats` AGT-06 @test.
</code_context>

<specifics>
## Specific Ideas
None — standard npm recipe.
</specifics>

<deferred>
## Deferred Ideas
None.
</deferred>

---
*Phase: 24-gemini-cli*
*Context gathered: 2026-06-29*
