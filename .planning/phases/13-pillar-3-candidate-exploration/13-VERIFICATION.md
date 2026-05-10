---
phase: 13-pillar-3-candidate-exploration
verified: 2026-05-10T00:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 13: Pillar 3 Candidate Exploration — Verification Report

**Phase Goal:** Decide whether security is a pillar at all, and if so what it commits to. Treat the AL-7-proposed pillar 3 (security hardening) as a *candidate*. Produce a written verdict that Phase 14 can lift verbatim into either (a) `docs/STRATEGY.md` Pillar 3, (b) Pillar 2 sub-concerns, (c) cross-cutting Guiding Principles, or (d) the strategy doc's `What we're explicitly *not* working on` list — without re-deciding at authoring time.
**Verified:** 2026-05-10
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (EXPL-02 success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | File exists at exact path; body in [2 KB, 12 KB] | ✓ VERIFIED | `EXISTS`; `wc -c = 12199` (2048 ≤ 12199 ≤ 12288) |
| 2 | First section is `## Verdict`; exactly one bolded `**Verdict:**` line declaring (b) | ✓ VERIFIED | First `## ` heading at line 13 = `## Verdict`; `grep -c '^## Verdict$' = 1`; `grep -cE '\*\*Verdict:' = 1`; line reads exactly: `**Verdict:** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.` |
| 3 | Body cites ≥7 distinct grep tokens from the EXPL-02 regex set | ✓ VERIFIED | 12/12 distinct tokens present: ADR-012, Cline, Lethal Trifecta, OWASP, Rule of Two, SLSA, Shai-Hulud, TrustFall, bubblewrap, chalk, cosign, provenance |
| 4 | File ENDS with `## Decision summary` containing ≥2 table-stakes, ≥1 differentiator, ≥2 non-goals, recommended priority tag | ✓ VERIFIED | Last `## ` heading at line 159 = `## Decision summary`; ends at line 213; contains ≥2 table-stakes (curated catalog + ADR-011 + admission criteria), 1 differentiator (supply-chain monitoring + compromised-version refusal), 3 non-goals (NG-1 / NG-2 / NG-3), priority tags (`next-milestone` for the fold + `opportunistic` for Appendix B), DOC-05 N/A disposition |
| 5 | Phase-close audit at `.../13-pillar-3-candidate-exploration/13-AUDIT.md` exists with grep transcripts + GREEN verdict + verdict line in first 10 lines | ✓ VERIFIED | Audit exists (11.5K); `gate: GREEN` in frontmatter (line 6) + `**Gate: GREEN.**` body (line 306); verdict line on body line 10 (within first 10 lines): `**Verdict (Phase 13, EXPL-02):** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.`; cites file path (26 occurrences), Verdict section line range (13–24), Decision summary line range (159–213), all five SC grep transcripts |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` | ≥2 KB, ≤12 KB; first section `## Verdict`; last section `## Decision summary` | ✓ VERIFIED | 12199 bytes; `## Verdict` at line 13 (first); `## Decision summary` at line 159 (last); ends at line 213 |
| `.planning/phases/13-pillar-3-candidate-exploration/13-AUDIT.md` | Phase-close audit with single-line verdict + grep transcripts + GREEN gate | ✓ VERIFIED | 11.5K; `gate: GREEN` frontmatter + body verdict gate; verdict on body line 10; grep transcripts for all five SCs |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| PILLAR-3-CANDIDATE-NOTES.md | 13-CONTEXT.md | Verdict (b) phrasing + supply-chain monitoring + NG-1/NG-2/NG-3 + ADR-012 framing + priority tag | ✓ WIRED | Verdict text exact match to lock; `NG-1`/`NG-2`/`NG-3` all present; "supply-chain monitoring" used 8 times across body; `next-milestone` + `opportunistic` literals both present in Decision summary |
| PILLAR-3-CANDIDATE-NOTES.md | PILLAR-2-NOTES.md | Decision summary names Pillar 2 / ADR-011 / curated catalog / admission criteria as fold target | ✓ WIRED | "Pillar 2" cited 19 times; ADR-011 cited 3 times as fold-anchor; "curated catalog" + "admission criteria" referenced as table-stakes |
| 13-AUDIT.md | PILLAR-3-CANDIDATE-NOTES.md | single-line verdict header + grep transcripts + line ranges | ✓ WIRED | Audit's body line 10 records verdict; cites Verdict lines 13–24 + Decision summary lines 159–213; grep transcripts for SC1–SC5 verbatim |

### Voice-Rule Hard Gate

Command:
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output: empty (exit code 1, no matches). **PASS.** Zero forbidden `AgentLinux + present-tense verb` lines anywhere in the body. Phase 14's STRAT-11 hard gate on `docs/STRATEGY.md` will pass cleanly when Phase 14 lifts the Decision summary verbatim.

### Verdict Phrasing Lock Check

Locked phrasing (from CONTEXT.md decisions block):
```
**Verdict:** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.
```

Actual line in PILLAR-3-CANDIDATE-NOTES.md:
```
**Verdict:** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.
```

**Match: byte-for-byte exact. PASS.**

### Forbidden-Content Disposition Check

The CONTEXT.md `<decisions>` block forbids these items from appearing as **pillar substance commitments**. They may appear only as cited/declined items.

| Item | Appearance Status | Disposition |
|------|-------------------|-------------|
| `agentlinux harden` | Line 194 only | Cited inside NG-3 ("No commitment to ship an `agentlinux harden` profile") — declined, not committed. PASS. |
| cosign-signed catalog | Lines 102, 207 | Line 102: "**cosign-signed catalog snapshots.** … Declined as pillar substance"; line 207: listed under `opportunistic` Appendix B defenses. Both declined. PASS. |
| `npm audit signatures` | Line 93 | "**npm provenance + Sigstore signing.** `npm audit signatures` … Declined as pillar substance." Cited then declined. PASS. |
| `--ignore-scripts` policy | Not present in body | Listed in CONTEXT.md `<deferred>` only; doc body does not mention it (consistent with verdict (b)). PASS. |
| capability-scoped sudoers | Lines 110, 121, 194, 207 | All four occurrences are within declined contexts (Defenses-considered, ADR-012 tension as rejected alternative, NG-3 non-goal, Appendix B opportunistic theme). Never as commitment. PASS. |

### ADR-012 Tension Framing Check

CONTEXT.md lock: "defensible at v0.3.0; debt now; revisit is opportunistic theme not pillar."

Actual phrasing in `## ADR-012 tension` section (lines 117–137):

- "ADR-012 (`agent ALL=(ALL) NOPASSWD: ALL`) was a **defensible scope choice at v0.3.0**." (line 118)
- "After Shai-Hulud, TrustFall, and the Lethal Trifecta framing in late 2025, that 'trusted coworker' framing is harder to defend." (lines 124–126) — debt-now framing
- "Position: **defensible v0.3.0 scope choice, recognized debt now**. **Resolution is a v0.6+ `opportunistic` theme in Appendix B Security Hardening, NOT a pillar commitment**." (lines 132–134)

**Lock substance present verbatim. PASS.**

### Decision Summary Verdict Restatement Bolding Check

CONTEXT.md requires the Decision summary's verdict restatement be **unbolded** so the single-match `**Verdict:**` invariant holds.

Actual: "Verdict (restated, unbolded): (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3." (line 164) — no `**Verdict:**` bolding. The single bolded `**Verdict:**` invariant holds (`grep -cE '\*\*Verdict:' = 1`). **PASS.**

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| EXPL-02 | 13-01-PLAN.md | `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` with `## Verdict` first-section anchor + ≥7 named-reference grep hits + `## Decision summary` last-section anchor with substance + phase-close audit | ✓ SATISFIED | All 5 success criteria PASS (above). 12/12 grep tokens present (≥7 required). Voice-rule hard gate passes (0 matches). |

### Anti-Patterns Found

None. The doc is a verdict deliverable (framing, not implementation). No TODOs, no FIXMEs, no placeholder content. The `## Defenses we considered` section uses "Declined as pillar substance" repeatedly — this is the *intended* framing per verdict (b), not a stub indicator.

### Behavioral Spot-Checks

SKIPPED (Step 7b) — Phase 13 is documentation-only with no runnable entry points. The verification is mechanical grep-based gates, all of which were run above.

### Human Verification Required

None. All five EXPL-02 success criteria are mechanically verifiable via grep, and all five PASS. The verdict (b) phrasing matches the locked phrasing byte-for-byte; the voice-rule hard gate returns zero matches; forbidden-content items appear only as declined citations (never as commitments); the ADR-012 tension framing matches the lock; the Decision summary verdict restatement is unbolded so the single-match invariant holds.

### Gaps Summary

No gaps. Phase 13 achieves its goal: the `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` deliverable exists at the exact path with the locked verdict (b), the locked supply-chain monitoring fold commitment, all 3 non-goals (NG-1/NG-2/NG-3), the ADR-012 tension framing, and the priority tags. Phase 14 can lift the `## Decision summary` section verbatim into `docs/STRATEGY.md` Appendix B's "Security Hardening" theme entry and close DOC-05 as N/A in `14-AUDIT.md` without re-opening any decisions.

**Path divergence note:** ROADMAP.md success-criterion-5 references `.planning/phases/13-pillar-3-exploration/13-AUDIT.md` (without "candidate"). The canonical phase directory slug is `13-pillar-3-candidate-exploration`. The audit lands at the canonical path and notes the divergence in its body. This is a ROADMAP typo predating the canonical slug, not a verification gap. Phase 14's planner reading the audit must use the canonical path.

---

_Verified: 2026-05-10_
_Verifier: Claude (gsd-verifier)_
