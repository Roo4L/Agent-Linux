---
phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
plan: 05
subsystem: docs
tags: [requirements, adr, audit, doc-xx, post-v0.4.0-addendum, phase-close, AL-22]

# Dependency graph
requires:
  - phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
    plan: 01
    provides: docs/internals/README.md + 4 install/runtime-layer component docs (cited as DOC-01 + DOC-02 evidence)
  - phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
    plan: 02
    provides: 5 catalog-layer component docs (cited as DOC-02 evidence; completed the docs/internals/ tree)
  - phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
    plan: 03
    provides: .claude/agents/dev-docs-auditor.md + .claude/skills/dev-docs/SKILL.md (cited as DOC-03 + DOC-04 evidence; the no-new-hook stance ADR-015 records)
  - phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
    plan: 04
    provides: CLAUDE.md "Review Loop" wiring + Pointers + README.md "Why AgentLinux — concepts" section + Links row (cited as DOC-03 + DOC-05 evidence)
provides:
  - DOC-01..DOC-07 enumerated in REQUIREMENTS.md as a post-v0.4.0 addendum (new H2 + H3); v0.4.0 milestone count remains 21
  - ADR-015 (docs/decisions/015-developer-internals-docs.md) — design decision archive (no-new-hook + embed-in-review-loop + flat-extend-not-new-CLAUDE.md-section)
  - 12-AUDIT.md emitting GATE GREEN — Phase 12 closed with one row of cited evidence per DOC-XX
affects:
  - All future phases that reference REQUIREMENTS.md DOC-XX coverage gates
  - Future readers of docs/decisions/ — ADR-015 archives the rationale for the absence of .claude/hooks/dev-docs-reminder.sh
  - Phase 12 itself — this plan emits the phase-close gate

# Tech tracking
tech-stack:
  added: []  # docs only — no new libraries / runtime tech
  patterns:
    - "Post-v0.4.0 addendum requirements pattern: new H2 below the v0.4.0 sections + matching H3 traceability sub-section inside the existing ## REQ-ID Traceability H2; v0.4.0 totals stay frozen so the milestone gate count remains honest"
    - "Phase-close audit shape (mirrors 11-AUDIT.md): frontmatter status block -> ## Evidence per requirement table with one row per REQ-ID citing artifacts + commit hashes -> ## Deviations from PLAN -> ## Phase-close gate emitting GATE: GREEN"
    - "ADR shape (mirrors ADR-014): Drives + Companion to lines in the frontmatter; richer Consequences with named sub-sections (### What changes / ### Why no third hook / ### Why a flat extend / ### Reversibility)"

key-files:
  created:
    - "docs/decisions/015-developer-internals-docs.md (67 lines)"
    - ".planning/phases/12-developer-documentation-for-installer-runtime-and-cli-al-22/12-AUDIT.md (46 lines)"
  modified:
    - ".planning/REQUIREMENTS.md (+23 lines: new ## Post-v0.4.0 Addendum Requirements H2 with DOC-01..DOC-07; new ### Post-v0.4.0 Addendum Traceability H3 inside the existing ## REQ-ID Traceability H2)"

key-decisions:
  - "DOC-XX requirements added as a post-v0.4.0 addendum, not merged into the v0.4.0 milestone traceability table — the milestone closed at commit c8a2787 on 2026-05-02 with 21 requirements, and that count must remain honest. New separate H3 traceability sub-section captures the addendum's 7/1-phase coverage without disturbing the existing 21/5-phase totals."
  - "ADR-015 frontmatter mirrors ADR-014's shape (Status / Date / Drives / Companion to) rather than the bare ADR-template (only Status + Date) — ADR-014 is the closest recent v0.4.0-era analog and the milestone-framing lines are useful for future readers tracing back from a DOC-XX gate."
  - "12-AUDIT.md cites per-plan commit hashes (9c00061, 4598b4a, 3f6e329, e71d8cc, 6891a5f, 191cc21, 1efb2a9, b148ef3) in each evidence row so a reader following the audit can ground each DOC-XX claim in a concrete commit, not just a file path. Shape mirrors 11-AUDIT.md's evidence-table convention."
  - "Three Rule 1 source-truth deviations from Plan 12-02 (playwright/gsd/registry-cli) recorded in the AUDIT's Deviations section by reference to 12-02-SUMMARY.md, not re-narrated in full — the Deviations section is shaped as 'document material drift from the plan narrative,' not 'recap every per-plan SUMMARY.'"

patterns-established:
  - "Post-v0.4.0 addendum pattern: when AL-NN scope adds REQs after a milestone closes, capture them under a new ## Post-v0.4.0 Addendum Requirements H2 + a new ### Post-v0.4.0 Addendum Traceability H3 inside the existing ## REQ-ID Traceability H2; do NOT modify the v0.4.0 totals or its prose Coverage check sentence"
  - "Phase-close audit cites per-plan commit hashes alongside file paths so the evidence chain is grep-able from a single audit doc back to the originating commits"

requirements-completed: [DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07]

# Metrics
duration: ~7min
completed: 2026-05-10
---

# Phase 12 Plan 05: REQUIREMENTS.md DOC-XX addendum + ADR-015 + 12-AUDIT.md GATE GREEN

**Phase 12 closed: REQUIREMENTS.md gains DOC-01..DOC-07 as a post-v0.4.0 addendum (v0.4.0 milestone count stays at 21); ADR-015 archives the no-new-hook + embed-in-review-loop + flat-extend design decision; 12-AUDIT.md emits GATE: GREEN with cited evidence for every DOC-XX requirement.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-10T08:55:00Z (approx)
- **Completed:** 2026-05-10T09:02:00Z
- **Tasks:** 2
- **Files created:** 2 (ADR-015 + 12-AUDIT.md)
- **Files modified:** 1 (REQUIREMENTS.md)

## Accomplishments

- DOC-01..DOC-07 enumerated in REQUIREMENTS.md with verifiable contracts mirroring the v0.4.0 LIC/SEC/CLEAN/CIPUB/PUB style.
- The v0.4.0 milestone count is untouched: `**Total v0.4.0** | | **21**` and the prose `21 requirements mapped to 5 phases. Zero orphans.` remain. The post-v0.4.0 addendum lives in a separate H2 (`## Post-v0.4.0 Addendum Requirements`) with a sibling traceability H3 (`### Post-v0.4.0 Addendum Traceability`, 7 reqs / 1 phase).
- ADR-015 records the design decision behind Phase 12 (Status: Accepted, Date: 2026-05-09, Drives: DOC-01..DOC-07, Companion to: ADR-010). Sections cover Context (the AL-22 60-second-answer goal + the two adjacent decisions on docs sync and stop-hook posture), Decision (5-point spec including "no new hook / no settings.json edit"), and a richer Consequences with four sub-sections (What changes / Why no third hook / Why a flat extend / Reversibility).
- 12-AUDIT.md emits `GATE: GREEN` with one row of cited evidence per DOC-XX requirement. Each row cites both the artifact path and the originating commit hash from Plans 12-01..04. The Deviations section records the three Rule 1 source-truth fixes from Plan 12-02 (playwright/gsd/registry-cli) by reference to 12-02-SUMMARY.md.
- DOC-06 invariants verified at commit time and documented in the AUDIT: no `.claude/hooks/dev-docs-reminder.sh`, `.claude/settings.json` last touched 2026-04-26 (commit `a812a02`, well before Phase 12 began).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add DOC-01..DOC-07 to REQUIREMENTS.md** — `bbf7929` (docs)
2. **Task 2: Write ADR-015 + 12-AUDIT.md** — `b62c0b0` (docs)

**Plan metadata commit (this SUMMARY + STATE/ROADMAP/REQUIREMENTS bookkeeping):** committed after this file lands.

## Files Created/Modified

- `.planning/REQUIREMENTS.md` (modified, +23 lines) — Inserted `## Post-v0.4.0 Addendum Requirements` H2 between the existing `### Public Visibility Flip & Smoke Test (PUB) — Phase 11` block and `## Future Requirements (not in this milestone)`. The new H2 wraps a one-paragraph framing (cites the v0.4.0 close at `c8a2787` / 21 reqs / AL-22 origin) and the `### Developer Documentation (DOC) — Phase 12` H3 with seven `- [ ] **DOC-NN**:` rows. Inserted `### Post-v0.4.0 Addendum Traceability` H3 inside the existing `## REQ-ID Traceability` H2, between the prose Coverage check line and the `## Verification Convention` H2 that closes the section. The addendum H3 carries its own one-row table totalling 7 and its own Coverage-check sentence (7/1 phase).
- `docs/decisions/015-developer-internals-docs.md` (created, 67 lines) — ADR archiving the design decision behind Phase 12. Frontmatter mirrors ADR-014: Status (Accepted) + Date (2026-05-09) + Drives (DOC-01..DOC-07) + Companion to (ADR-010, refined 2026-05-02). Sections: ## Context (the 60-second-answer goal + the two adjacent decisions), ## Decision (5-point spec naming "no new hook / no settings.json edit" explicitly), ## Consequences (### What changes, ### Why no third hook, ### Why a flat extend, ### Reversibility), ## References (ADR-010 + 12-CONTEXT.md + the three artifacts this ADR drives).
- `.planning/phases/12-developer-documentation-for-installer-runtime-and-cli-al-22/12-AUDIT.md` (created, 46 lines) — Phase-close audit. Frontmatter status block names GATE: GREEN, Closed 2026-05-09, all seven DOC-XX requirement IDs, all five plans, and the source spec. `## Evidence per requirement` table has one row per DOC-XX with verifiable contract + concrete artifact path + per-plan commit hash + Closed status. `## Deviations from PLAN` records the three Rule 1 source-truth fixes from Plan 12-02 by reference. `## Phase-close gate` emits GATE: GREEN and frames the addendum as not reopening the v0.4.0 milestone gate. `## References` cites ADR-015 + ADR-010 + 12-CONTEXT.md + REQUIREMENTS.md DOC section + all four prior plan SUMMARYs.

## Decisions Made

- **DOC-XX as post-v0.4.0 addendum, not v0.4.0 traceability merge.** The plan was explicit (`<action>` Part B: "leave the existing `## REQ-ID Traceability` table UNCHANGED"). The v0.4.0 milestone closed at `c8a2787` on 2026-05-02 with 21 requirements; rewriting that closed milestone's count would be dishonest bookkeeping. The addendum pattern (separate H2 with framing paragraph + separate H3 traceability sub-section) keeps both records intact.
- **ADR-014 as the analog over the bare ADR template.** ADR-014 (`014-secret-remediation-noop.md`) is the closest recent v0.4.0-era ADR — it carries the same "Drives + Companion to" frontmatter shape and a richer Consequences body with named sub-sections. ADR-015 inherits both. The 000-template.md is the minimum spec; ADR-014 is the contemporary precedent.
- **Per-plan commit hashes inside the AUDIT evidence table.** 11-AUDIT.md's evidence rows cite artifact paths but not commit hashes (it's a flip-event audit, not a multi-plan accumulation). 12-AUDIT.md aggregates work across five plans (12-01..05); citing each plan's task commits inline gives a reader following the audit a direct grep path back to origin without needing to cross-reference each per-plan SUMMARY first.
- **Deviations recorded by reference, not re-narration.** The three Rule 1 source-truth fixes from Plan 12-02 (playwright grounded in `@playwright/cli` reality, gsd's bootstrapper-wires-skills story, registry-cli's actual five-verb surface) are documented in 12-02-SUMMARY.md "Auto-fixed Issues" with full per-deviation detail. The AUDIT cites those deviations in its `## Deviations from PLAN` section by name + by reference to that SUMMARY rather than re-narrating each one — the AUDIT's job is the phase-close evidence chain, not deviation post-mortem.
- **AUDIT does not reopen the v0.4.0 milestone gate.** The `## Phase-close gate` section explicitly frames Phase 12's GATE: GREEN as separate from the v0.4.0 milestone close (PUB-XX, commit `c8a2787`, 2026-05-02). DOC-XX is post-milestone documentation work; closing it does not retroactively change the milestone scope or count.

## Deviations from Plan

None — plan executed exactly as written.

Both `<verify>` automated checks passed first try; both `<acceptance_criteria>` lists were green on first write; both `<done>` criteria were met. Zero auto-fix commits; zero Rule 1/2/3/4 deviations were necessary.

The pre-existing `git status` snapshot at session start showed unrelated modifications to `.planning/config.json`, three Plan 12-0[3..5] PLAN.md files, `docs/audits/v0.4.0/PUB-04-release-notes.md`, plus `.planning/{MILESTONES,ROADMAP,STATE}.md` from earlier in the day. These were left strictly untouched per the scope-boundary rule. Per the protocol, only the three files this plan owned were `git add`-ed and committed; no `git add .` / `-A` was used.

## Issues Encountered

None.

The PreToolUse Edit hook's "READ-BEFORE-EDIT REMINDER" fired after both REQUIREMENTS.md edits — these are reminder messages from the runtime, not failures. REQUIREMENTS.md was read once at the start of the session and a second time (lines 50-107) before the second edit; both edits applied successfully on first attempt.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 12 is closed. The phase-close gate emits GREEN; all seven DOC-XX requirements are evidenced.
- Future phases that touch `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, or `packaging/curl-installer/` will trigger the `dev-docs-auditor` reviewer (wired into the CLAUDE.md Review Loop in Plan 12-04). The reviewer reads `.claude/skills/dev-docs/SKILL.md` for the source-path → doc-path dispatch table and the four-section per-component contract.
- ADR-015 is the canonical reference for the "no third stop-hook" stance — future contributors who consider adding a `dev-docs-reminder.sh` should be redirected to ADR-015 §"Why no third hook" first.
- The post-v0.4.0 addendum pattern is now established: when future AL-NN scope adds REQs after a milestone closes, the precedent is to add a sibling addendum H2 + traceability H3, not to retroactively grow the closed milestone's totals.

## Self-Check: PASSED

Created files exist:

- FOUND: `docs/decisions/015-developer-internals-docs.md` (67 lines)
- FOUND: `.planning/phases/12-developer-documentation-for-installer-runtime-and-cli-al-22/12-AUDIT.md` (46 lines)

Modified files match expectations:

- FOUND: `.planning/REQUIREMENTS.md` carries DOC-01..DOC-07 in `## Post-v0.4.0 Addendum Requirements` H2; `## REQ-ID Traceability` v0.4.0 row UNCHANGED at `**Total v0.4.0** | | **21**`; new H3 `### Post-v0.4.0 Addendum Traceability` totalling `**Total addendum** | | **7**` present; both Coverage check prose lines (21/5 and 7/1) present.

Commits exist:

- FOUND: `bbf7929` (docs(12-05): add DOC-01..DOC-07 to REQUIREMENTS.md as post-v0.4.0 addendum)
- FOUND: `b62c0b0` (docs(12-05): add ADR-015 + Phase 12 AUDIT (GATE: GREEN))

Plan-level verification (per plan's `<verification>` block):

- For each `n` in 01..07: `\*\*DOC-${n}\*\*` present in REQUIREMENTS.md PASS
- `**Total v0.4.0** | | **21**` present (UNCHANGED) PASS
- `21 requirements mapped to 5 phases` prose present (UNCHANGED) PASS
- `### Post-v0.4.0 Addendum Traceability` H3 present PASS
- `**Total addendum** | | **7**` present PASS
- `7 addendum requirements mapped to 1 phase` prose present PASS
- ADR-015 file exists, H1 `# 015:` PASS, `**Status:** Accepted` PASS, H2s `## Context` + `## Decision` + `## Consequences` all present PASS, references ADR-010 PASS
- 12-AUDIT.md file exists, H1 `# Phase 12 AUDIT` PASS, `GATE: GREEN` present PASS, all DOC-01..07 referenced PASS, ADR-015 cited PASS
- DOC-06 invariants: `! test -f .claude/hooks/dev-docs-reminder.sh` PASS; `.claude/hooks/` contains only `review-reminder.sh` and `session-tracker-reminder.sh`; `.claude/settings.json` last touched at commit `a812a02` (well before Phase 12) PASS

---
*Phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22*
*Plan: 05*
*Completed: 2026-05-10*
