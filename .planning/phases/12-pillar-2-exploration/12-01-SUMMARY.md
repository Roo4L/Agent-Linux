---
phase: 12-pillar-2-exploration
plan: 01
subsystem: docs
tags: [strategy, pillar-2, exploration, framing, voice-rule, expl-01]

# Dependency graph
requires:
  - phase: research
    provides: "raw-material landscape (terminal-bench / Multi-Docker-Eval / tau-bench / SWE-bench / Helicone / Langfuse) cited as considered-and-rejected; PITFALLS.md voice rule applied to Direction subsection"
  - phase: 12-discuss
    provides: "12-CONTEXT.md locked decisions (T-1/T-2 + D-1/D-2/D-3 + NG-1/NG-2/NG-3/NG-4 + Today/Direction seeds + next-milestone priority tag)"
provides:
  - "docs/exploration/PILLAR-2-NOTES.md — canonical pillar 2 exploration verdict (11400 bytes); Decision summary at lines 128–196 is Phase 14's grep anchor for verbatim lift into docs/STRATEGY.md Pillar 2"
  - "Hard-reframe paragraph (AgentLinux is infrastructure, not an agent product) that re-anchors the pillar away from agent-focused benchmarks"
  - "Three concrete differentiator commitments (D-1 compat-guarded default version set, D-2 preset framework with RTK as canonical optimum example, D-3 profile framework with web-development as canonical example)"
  - ".planning/phases/12-pillar-2-exploration/12-AUDIT.md — phase-close audit citing file path + Decision summary line range + verbatim grep transcripts; gate GREEN"
affects: [13-pillar-3-exploration, 14-strategy-doc-and-downstream, 15-website-refresh]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Voice rule (Pitfall #6/#14): Direction subsections of unshipped behaviour use subject = we / our roadmap / explicit milestone tag — never AgentLinux + present-tense verb. Grep regex AgentLinux\\s(provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents) is the structural defence; this doc holds zero matches."
    - "Considered-and-rejected discipline (Pitfall #13): research raw material (named benchmark suites) is documented in body with one-line rejection rationale per item, satisfying EXPL-01 grep gate while preserving the hard reframe."
    - "Decision summary as Phase-14 grep anchor: trailing `## Decision summary` heading is exact-match required (Phase 14 lifts verbatim); the section is the canonical published verdict for downstream phases."
    - "Phase-close audit convention: 12-AUDIT.md cites file path + Decision summary line range + verbatim grep transcripts for every success criterion; gate emits GREEN before the phase closes."

key-files:
  created:
    - docs/exploration/PILLAR-2-NOTES.md
    - .planning/phases/12-pillar-2-exploration/12-AUDIT.md
    - .planning/phases/12-pillar-2-exploration/12-01-SUMMARY.md
  modified: []

key-decisions:
  - "Hard reframe locked: AgentLinux is infrastructure, not an agent product. Agent-focused benchmark suites (terminal-bench / Multi-Docker-Eval / tau-bench / SWE-bench / Aider polyglot / Helicone / Langfuse) cited as considered-and-rejected raw material, not pillar substance."
  - "Pillar 2 priority reaffirmed as next-milestone (locked at milestone-open 2026-05-09; reaffirmed in this exploration 2026-05-10)."
  - "Optional T-3 (default-set compat verification as additional table-stakes) omitted per CONTEXT.md recommendation — D-1 carries the position more cleanly as a forward-looking differentiator."
  - "Considered-and-rejected subsection rendered as bulleted list (not paragraphs) — produces all 8 grep tokens cleanly with one bullet per suite."
  - "Decision summary section ordering: Pillar name → Priority tag → Table-stakes → Differentiators → Non-goals → Today/Direction. Mirrors CONTEXT.md decisions block ordering for spot-check fidelity."

patterns-established:
  - "Voice rule applied via grammatical-subject discipline: every Direction-subsection sentence uses we / our roadmap / next-milestone as subject. Phase 14's STRAT-11 hard gate will pass cleanly when it lifts the Decision summary verbatim."
  - "EXPL-01 grep-gate satisfaction strategy: grep tokens delivered via considered-and-rejected subsection (8 of 8 distinct tokens hit) + Decision summary cross-references. ≥5 distinct hits required; 8 actual."
  - "Audit doc carries verbatim grep transcripts for all 5 success criteria (file path + size + Decision summary anchor + line range + literal next-milestone + voice-rule advisory). Re-runs reproduce the audit's quoted output; the grep IS the spec."

requirements-completed: [EXPL-01]

# Metrics
duration: 5min
completed: 2026-05-10
---

# Phase 12 Plan 01: Pillar 2 Exploration Summary

**Canonical pillar 2 verdict published with hard reframe (infrastructure, not agent product) + 8/8 EXPL-01 grep tokens + 3-times-stated next-milestone priority + voice-rule-clean Direction subsection — Phase 14's verbatim-lift target ready for consumption.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-10T08:55:41Z
- **Completed:** 2026-05-10T09:01:03Z
- **Tasks:** 3 (Task 1: author doc, Task 2: run gates, Task 3: author audit)
- **Files modified:** 0
- **Files created:** 3 (`docs/exploration/PILLAR-2-NOTES.md`, `.planning/phases/12-pillar-2-exploration/12-AUDIT.md`, this SUMMARY.md)

## Accomplishments

- Authored `docs/exploration/PILLAR-2-NOTES.md` (11400 bytes, in [2048, 12288]) with the canonical pillar 2 verdict. The doc lifts CONTEXT.md's locked decisions (T-1/T-2 table-stakes, D-1/D-2/D-3 differentiators, NG-1..NG-4 non-goals, Today/Direction seeds, `next-milestone` priority tag) into a published verdict that Phase 14 will lift verbatim into `docs/STRATEGY.md` Pillar 2.
- Hard reframe established as the load-bearing framing: AgentLinux is infrastructure, not an agent product. The research SUMMARY.md §4 agent-evaluation landscape (terminal-bench / Multi-Docker-Eval / tau-bench / SWE-bench Verified / Live / Aider polyglot / Helicone / Langfuse) is documented as considered-and-rejected raw material with one-line rejection rationales — honoring Pitfall #13 while satisfying the EXPL-01 grep gate (8 distinct tokens hit; ≥5 required).
- Voice rule applied rigorously to the Direction subsection of the Decision summary — every claim about unshipped behaviour uses subject "we" / "our roadmap" / `next-milestone`, never "AgentLinux + present-tense verb". The voice-rule advisory grep returns zero matches across the entire doc, so Phase 14's STRAT-11 hard gate will pass cleanly when it lifts the Decision summary verbatim.
- Decision summary anchor locked at lines 128–196 with literal `## Decision summary` heading exact match (Phase 14's grep anchor — exact match required).
- Phase-close audit `.planning/phases/12-pillar-2-exploration/12-AUDIT.md` published with verbatim grep transcripts for all 5 EXPL-01 success criteria (file existence + size + ≥5 distinct grep tokens + Decision summary anchor + line range + literal `next-milestone`); gate verdict GREEN.

## Task Commits

Each task was committed atomically:

1. **Task 1: Author docs/exploration/PILLAR-2-NOTES.md from CONTEXT.md decisions** — `d34bc99` (docs)
2. **Task 2: Run all EXPL-01 grep gates locally and capture transcripts** — verification-only task; no file artifacts; transcripts captured to bash session and quoted into Task 3's audit
3. **Task 3: Author phase-close audit 12-AUDIT.md with grep transcripts and GREEN gate verdict** — `e51e1ce` (docs)

_Note: Task 2 produces no committable file artifacts by design — its evidence is the verbatim grep output that Task 3's audit quotes. Two task commits land; the audit acts as Task 2's persisted artifact via embedded transcripts._

## Files Created/Modified

- `docs/exploration/PILLAR-2-NOTES.md` (NEW, 11400 bytes, 196 lines) — Canonical pillar 2 exploration verdict. Hard-reframe Framing section, T-1/T-2 Table-stakes, D-1/D-2/D-3 Differentiators (forward-looking voice), Considered-and-rejected agent-focused benchmarks subsection (8 grep tokens), trailing `## Decision summary` anchor at lines 128–196.
- `.planning/phases/12-pillar-2-exploration/12-AUDIT.md` (NEW, 225 lines) — Phase-close audit with verbatim grep transcripts for all 5 EXPL-01 success criteria; CONTEXT.md fidelity spot-check; voice-rule advisory check; gate verdict GREEN.
- `.planning/phases/12-pillar-2-exploration/12-01-SUMMARY.md` (NEW, this file) — execute-plan summary.

## Decisions Made

Decisions made under the "Claude's Discretion" portion of CONTEXT.md `<decisions>`:

- **Section ordering for PILLAR-2-NOTES.md body:** Title → Framing (hard reframe) → What pillar 2 commits to (intro) → Table-stakes (already shipped) → Differentiators (forward-looking) → Considered-and-rejected agent-focused benchmarks → Decision summary (trailing anchor). Rationale: builds the load-bearing framing first (hard reframe) so the considered-and-rejected subsection lands as a natural consequence; the Decision summary at the bottom is unambiguously trailing (Phase 14's grep anchor depends on `^## Decision summary$` matching the *trailing* heading).
- **Considered-and-rejected subsection rendered as bulleted list, not paragraphs.** Rationale: bullets surface all 8 grep tokens cleanly with one bullet per suite; paragraphs would scatter tokens across prose and obscure the rejection rationale per item. CONTEXT.md explicitly leaves this to Claude's discretion as long as ≥5 distinct hits land.
- **Optional T-3 (default-set compat verification as additional table-stakes) OMITTED**, per CONTEXT.md recommendation. Rationale: the position is most cleanly carried as forward-looking differentiator D-1 (compat-guarded default version set); doubling it as table-stakes T-3 would mix shipped + unshipped substance under one heading and undercut the voice-rule discipline.
- **Decision summary internal ordering:** Pillar name → Priority tag → Table-stakes → Differentiators → Non-goals → Today/Direction. Mirrors CONTEXT.md `<decisions>` block ordering for one-glance fidelity spot-check at audit time.
- **Voice-rule application to T-1/T-2:** delivered-fact voice ("the curated `claude` binary self-updates") used in Table-stakes since T-1/T-2 describe shipped behaviour with bats-test + ADR citations. Forward-looking voice reserved for D-1/D-2/D-3 and the Direction half of the Today/Direction seed.

## Deviations from Plan

None — plan executed exactly as written. Every CONTEXT.md locked decision (T-1, T-2, D-1, D-2, D-3, NG-1, NG-2, NG-3, NG-4, Today/Direction seeds, `next-milestone` priority tag, RTK as canonical `optimum` example, `web-development` as canonical profile example) was lifted into the doc body. All 5 EXPL-01 gates passed first-attempt; voice-rule advisory grep returned zero matches; forbidden-vocabulary check (v1 / v2 / placeholder / etc.) returned zero matches; CONTEXT.md fidelity spot-check confirmed all 9 decision IDs and both canonical examples present.

## Issues Encountered

None.

## User Setup Required

None — documentation-only plan; no external service configuration required.

## Next Phase Readiness

- **Phase 13 (Pillar 3 Candidate Exploration) unblocked.** The Phase 12 → Phase 13 sequential dependency is satisfied (per ROADMAP.md and user direction "first dig into Pillar 2 ... then do the same with Pillar 3 ... then try to understand priority").
- **Phase 14 (Strategy Doc + ADR-015 + Downstream Surface Updates) has its Pillar 2 source.** `docs/exploration/PILLAR-2-NOTES.md` Decision summary section (lines 128–196) is the canonical lift target; the heading is exact-match `## Decision summary` per Phase 14's grep anchor. STRAT-11's voice-rule grep gate will pass cleanly when Phase 14 lifts the Decision summary verbatim — this doc holds zero matches against the regex.
- **Phase 15 (Website Refresh) has its pillar 2 card source.** The Today / Direction split in the Decision summary feeds SITE-02 (#pillars 2-card or 3-card section) and SITE-03 (status badges: pillar 2 carries `[v0.6+ ROADMAP]` per next-milestone tag).

## Self-Check: PASSED

- File: `docs/exploration/PILLAR-2-NOTES.md` — FOUND
- File: `.planning/phases/12-pillar-2-exploration/12-AUDIT.md` — FOUND
- File: `.planning/phases/12-pillar-2-exploration/12-01-SUMMARY.md` — FOUND
- Commit: `d34bc99` (Task 1: PILLAR-2-NOTES.md authored) — FOUND
- Commit: `e51e1ce` (Task 3: 12-AUDIT.md GREEN) — FOUND

---
*Phase: 12-pillar-2-exploration*
*Plan: 01*
*Completed: 2026-05-10*
