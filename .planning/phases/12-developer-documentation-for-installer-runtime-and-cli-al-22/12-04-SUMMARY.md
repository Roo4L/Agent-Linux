---
phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
plan: 04
subsystem: docs
tags: [claude-md, readme, review-loop, dev-docs, discoverability]

# Dependency graph
requires:
  - phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
    provides: docs/internals/ tree (Plan 12-01), 9 component docs (Plan 12-02), dev-docs-auditor reviewer + dev-docs skill (Plan 12-03)
provides:
  - "CLAUDE.md Review Loop reviewer-by-file-type table extended with dev-docs-auditor on Bash, TS/JS, and Catalog recipes rows"
  - "CLAUDE.md Pointers skills enumeration includes dev-docs/ and workspace-cleanup/; stale '(arrive Plan 01-04)' parenthetical removed"
  - "Top-level README.md gains a 'Why AgentLinux — concepts' H2 section linking docs/internals/README.md"
  - "Top-level README.md ## Links section gains an 'Internals (developer docs)' row pointing at docs/internals/"
affects: [phase-12-plan-05-audit, future-plugin-edits-routed-to-dev-docs-auditor, blog-marketing-content-discovery]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CLAUDE.md Review Loop wiring: extend existing reviewer-by-file-type rows (NOT add a new row) when a reviewer's trigger globs overlap an established file-type bucket"
    - "Top-level README.md conceptual entry point: short H2 lede + See line linking the deep-dive index, placed in the install -> verify -> uninstall -> why -> stability flow"

key-files:
  created: []
  modified:
    - "CLAUDE.md"
    - "README.md"

key-decisions:
  - "Wired dev-docs-auditor by extending Bash, TS/JS, and Catalog recipes rows rather than adding a new 'Internal docs' row, per CONTEXT.md §'CLAUDE.md wiring' — keeps the surface flat."
  - "Bats and Docs rows left unchanged: bats has no internals doc; the Docs row already routes to technical-writer + fact-checker."
  - "Skills enumeration aligned with on-disk reality: dropped the stale '(arrive Plan 01-04)' parenthetical and added both dev-docs/ and the previously-omitted workspace-cleanup/ in alphabetical order."
  - "Placed the new 'Why AgentLinux — concepts' README section ABOVE Stability model so the conceptual story flows install -> verify -> uninstall -> why (internals) -> stability model -> escape hatches."
  - "Placed the new Internals Links row between 'Architecture decisions' and 'Test harness spec' so repo-internal reference rows stay grouped."

patterns-established:
  - "Pattern: CLAUDE.md reviewer wiring is multi-row extension when a reviewer's triggers span existing file-type buckets, not single-row addition"
  - "Pattern: README.md gains a short conceptual-entry-point section adjacent to the existing concept doc (Stability model) rather than burying internals links in a single Links row"

requirements-completed: [DOC-03, DOC-05]

# Metrics
duration: 2min
completed: 2026-05-10
---

# Phase 12 Plan 04: CLAUDE.md + README.md wiring of dev-docs surfaces

**Phase 12 outputs (dev-docs-auditor reviewer + dev-docs skill + docs/internals/ tree) wired into the two top-level discovery surfaces — the Review Loop routing table in CLAUDE.md and the conceptual-entry-point + Links section in README.md — so contributors and visitors land on the right surface from a flat read of the repo root.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-05-10T08:51:31Z
- **Completed:** 2026-05-10T08:53:10Z
- **Tasks:** 2
- **Files modified:** 2 (CLAUDE.md, README.md)

## Accomplishments

- CLAUDE.md "Review Loop" reviewer-by-file-type table now routes Bash, TS/JS, and Catalog recipes changes through `dev-docs-auditor` alongside the existing reviewers. Bats and Docs rows correctly left unchanged (bats has no internals doc; docs reviewers already cover the docs surface).
- CLAUDE.md "Pointers" skills enumeration aligned with on-disk reality: includes `.claude/skills/dev-docs/` and the previously-omitted `.claude/skills/workspace-cleanup/`; the stale "(arrive Plan 01-04)" parenthetical is gone.
- README.md gains a "Why AgentLinux — concepts" H2 section above the existing "## Stability model" — 2-3 line lede framing the per-component story plus a See line into `docs/internals/README.md`. This is the conceptual entry point a first-time visitor lands on from the README's natural top-to-bottom read.
- README.md "## Links" section gains an "Internals (developer docs)" row, placed adjacent to "Architecture decisions" so repo-internal reference rows remain grouped.

## Task Commits

Each task was committed atomically:

1. **Task 1: Update CLAUDE.md — extend Review Loop table + Pointers skills enumeration** — `1efb2a9` (docs)
2. **Task 2: Update top-level README.md — add Why AgentLinux concepts section + Links row** — `b148ef3` (docs)

**Plan metadata commit:** to be created after this SUMMARY lands.

## Files Created/Modified

- `CLAUDE.md` — extended Review Loop reviewer-by-file-type bullet list (Bash + TS/JS + Catalog recipes rows append `dev-docs-auditor`); refreshed Pointers skills bullet (dropped `(arrive Plan 01-04)`, added `dev-docs/` and `workspace-cleanup/`).
- `README.md` — inserted new H2 section "Why AgentLinux — concepts" above "## Stability model" with a 2-3 line lede + See line linking `docs/internals/README.md`; inserted "Internals (developer docs)" row in `## Links` between "Architecture decisions" and "Test harness spec".

## Decisions Made

- **Multi-row reviewer wiring (not new row).** Per CONTEXT.md §"CLAUDE.md wiring," extended Bash + TS/JS + Catalog recipes rows because dev-docs-auditor's trigger paths (`plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, `packaging/curl-installer/`) span those three buckets. Adding a new "Internal docs" row would have introduced a routing surface that does not match how the existing rows are organized (by file-type, not by reviewer audience).
- **Bats and Docs rows untouched.** Bats sources have no internals doc — the dispatch table in `.claude/skills/dev-docs/SKILL.md` does not include `tests/bats/`. Docs sources are already routed to `technical-writer` and `fact-checker`; routing them through `dev-docs-auditor` would be a redundant pass.
- **Skills list aligned with disk.** `ls .claude/skills/` shows seven directories; the Pointers bullet listed only five and tagged them with a long-stale "(arrive Plan 01-04)" parenthetical. Replaced both as a single edit so the contributor-visible truth matches reality.
- **Conceptual section placed above Stability model.** README natural flow becomes install -> verify -> uninstall -> **why (internals)** -> stability model -> escape hatches, mirroring how a first-time visitor would mentally bucket the content.
- **Links row adjacency.** Both "Architecture decisions" and "Internals (developer docs)" point into `docs/`; grouping them keeps repo-internal reference material visually together and separated from the external links (Source, Releases, Landing page).

## Deviations from Plan

None — plan executed exactly as written. The PLAN's two Edit specs landed verbatim:

- Edit 1 / Task 1: Review Loop bullet list extended on three rows; the spec's Unicode `→` arrows preserved; quoting and bullet shape preserved.
- Edit 2 / Task 1: Pointers skills bullet replaced with the alphabetically-sorted enumeration the plan specified (agentlinux-installer, behavior-test-contract, catalog-schema, dev-docs, qemu-harness, review, workspace-cleanup); stale parenthetical dropped.
- Edit 1 / Task 2: New H2 inserted above "## Stability model" with the suggested header `## Why AgentLinux — concepts` and the suggested 2-3 line lede + See block.
- Edit 2 / Task 2: New "Internals (developer docs)" row inserted in `## Links` between "Architecture decisions" and "Test harness spec", matching the bold-label-em-dash-bracketed-link shape of surrounding rows.

No Rule 1 / Rule 2 / Rule 3 auto-fixes triggered — the plan's edits were surgical, the read-before-edit reads on CLAUDE.md and README.md did not surface any pre-existing issues that intersected with the edit footprint.

---

**Total deviations:** 0
**Impact on plan:** None.

## Issues Encountered

None.

The PreToolUse Edit hook's "READ-BEFORE-EDIT REMINDER" fired three times after successful edits — these are reminder messages from the runtime, not failures. CLAUDE.md and README.md were both read in this session before any edit was issued; all four edits applied successfully on the first attempt.

## Verification

Plan-level automated verification (PLAN §`<verification>`) all green:

```
PASS: Bash row
PASS: TS/JS row
PASS: Catalog row
PASS: Bats unchanged
PASS: Docs unchanged
PASS: dev-docs/ in skills
PASS: stale parenthetical removed
PASS: Why AgentLinux H2
PASS: docs/internals/README.md link
PASS: Internals Links row
```

Per-task acceptance criteria all green:

- Task 1: 9/9 PASS (Bash + TS/JS + Catalog rows extended; Bats + Docs rows unchanged; dev-docs/ + workspace-cleanup/ in skills; stale parenthetical removed; dev-docs-auditor appears 3 times in CLAUDE.md).
- Task 2: 6/6 PASS (Why AgentLinux H2 present; docs/internals/README.md linked from new section; Internals Links row present with correct shape; Why AgentLinux comes before Stability model; Internals row positioned between Architecture decisions and Test harness spec).

Post-commit deletion check (`git diff --diff-filter=D HEAD~1 HEAD`): no deletions on either commit.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- DOC-03 (dev-docs-auditor reviewer registered in CLAUDE.md "Review Loop" routing table) — ✓ COMPLETE.
- DOC-05 (top-level discoverability into docs/internals/ via README.md) — ✓ COMPLETE.
- Phase 12 Plan 05 (AUDIT closure + ADR-015 + footer bump) is unblocked — both wiring surfaces are in place; the audit can now grep CLAUDE.md and README.md for the wiring evidence and ADR-015 can cite `docs/internals/`, the dev-docs-auditor agent, and the dev-docs skill as the three deliverables wired by this plan.

## Self-Check: PASSED

- CLAUDE.md modifications present at HEAD: YES (commit `1efb2a9`).
- README.md modifications present at HEAD: YES (commit `b148ef3`).
- Both commits exist in `git log --oneline`: YES.
- All plan-level verification gates green: YES (10/10).

---
*Phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22*
*Plan: 04*
*Completed: 2026-05-10*
