# Phase 25: opencode - Context

**Gathered:** 2026-06-29
**Status:** Ready for planning
**Mode:** Autonomous batch (npm cluster 23-27); decisions locked by ROADMAP /
REQUIREMENTS Appendix A.

<domain>
## Phase Boundary
Make `opencode` installable + removable via the catalog. Availability only.
</domain>

<decisions>
## Implementation Decisions
- **D-01:** npm `opencode-ai`, pin `1.17.11`, binary `opencode` (verified
  `npm view` → `{ opencode: 'bin/opencode.exe' }`; the .exe is a cross-platform
  launcher that execs the platform-native optionalDependency — resolves fine on
  linux-x64; `opencode --version` prints `1.17.11`).
- **D-02:** `source_kind: npm`; cluster recipe pattern; no CLI change (CAT-03).
- **D-03:** No secret baked — provider auth via `opencode auth login`.
- **D-04:** `~/.config/opencode/` + `~/.local/share/opencode/` preserved (CAT-04).
</decisions>

<canonical_refs>
## Canonical References
- `.planning/REQUIREMENTS.md` — AGT-05 + Appendix A
- `.planning/ROADMAP.md` §"Phase 25: opencode"
- `plugin/catalog/agents/codex/` — npm recipe analog
- `plugin/cli/src/runner.ts` — recipe env contract
</canonical_refs>

<code_context>
## Existing Code Insights
Clone of the cluster npm pattern. Test: `tests/bats/53-catalog-npm-cluster.bats`
AGT-05 @test.
</code_context>

<specifics>
## Specific Ideas
opencode's npm bin is a launcher (`opencode.exe`) — confirmed it still resolves
as `opencode` and reports the pin on linux-x64 (probed pre-implementation).
</specifics>

<deferred>
## Deferred Ideas
None.
</deferred>

---
*Phase: 25-opencode*
*Context gathered: 2026-06-29*
