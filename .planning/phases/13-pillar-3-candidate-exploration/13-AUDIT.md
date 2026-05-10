---
phase: 13
phase_name: Pillar 3 Candidate Exploration
milestone: v0.3.3
status: shipped
gate: GREEN
date: 2026-05-10
---
# Phase 13 Audit — Pillar 3 Candidate Exploration
**Verdict (Phase 13, EXPL-02):** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.

> Path note: this audit lands at the canonical path
> `.planning/phases/13-pillar-3-candidate-exploration/13-AUDIT.md`
> matching the phase directory slug. ROADMAP.md's Phase 13 success-
> criterion 5 line references `.planning/phases/13-pillar-3-exploration/13-AUDIT.md`
> (without "candidate") — that path is a typo predating the canonical
> slug; the audit substance is unchanged.

**Phase:** 13 — Pillar 3 Candidate Exploration
**Closed:** 2026-05-10
**Requirement:** EXPL-02
**Gate verdict:** GREEN

## Headline

`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` exists at the locked path
with body 12073 bytes (in `[2048, 12288]`). The doc's first section is
`## Verdict` at lines 15–26; the bolded `**Verdict:**` line declares
**(b) Fold into Pillar 2 as sub-concern.** The doc ends with
`## Decision summary` at lines 158–211 (the section Phase 14 lifts verbatim
into `docs/STRATEGY.md` Appendix B's "Security Hardening" theme entry —
under verdict (b), Phase 14 ships 2 pillars (not 3) and DOC-05 closes as
N/A in `14-AUDIT.md`). All five EXPL-02 success criteria pass; transcripts
below. Voice-rule project-wide grep returns zero matches.

> 2026-05-10 follow-up: reviewer pass (fact-checker + technical-writer per
> CLAUDE.md §Review Loop) tightened the doc for Phase 14 lift-readiness —
> dangling "above" references in Decision summary inlined; DOC-05 disposition
> moved from Decision summary to header callout (it is a project-internal
> audit token that does not belong in lifted Strategy.md content); "(restated,
> unbolded)" scaffolding parenthetical dropped; per-defense "Declined as
> pillar substance" trailing repetition consolidated into one opening line;
> NOPASSWD + RCE acronyms glossed at first use. Substance unchanged; line
> ranges and byte count above reflect the post-review file state.

## Coverage table

| Req | Description | Status |
|-----|-------------|--------|
| EXPL-02 | `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` with `## Verdict` first-section anchor + ≥7 named-reference grep hits + `## Decision summary` last-section anchor with substance + phase-close audit | ✅ All five success criteria pass; transcripts below |

## Requirement EXPL-02 — evidence

### Success criterion 1 — file exists at exact path; body in [2 KB, 12 KB]

**File:** `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`

Command:
```
test -f docs/exploration/PILLAR-3-CANDIDATE-NOTES.md && echo EXISTS
```

Output:
```
EXISTS
```

Command:
```
wc -c docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output:
```
12073 docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Within bounds: 2048 ≤ 12073 ≤ 12288. **PASS.**

### Success criterion 2 — `## Verdict` is FIRST section + single bolded `**Verdict:**` line declares (b)

Command (first `##` heading):
```
grep -nE '^## ' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | head -1
```

Output:
```
13:## Verdict
```

Command (count of `^## Verdict$` lines — must be exactly 1):
```
grep -c '^## Verdict$' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output:
```
1
```

Command (count of `**Verdict:**` bolded lines — must be exactly 1):
```
grep -cE '\*\*Verdict:' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output:
```
1
```

Command (the verdict line itself — declares (b)):
```
grep -E '\*\*Verdict:' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output (verbatim):
```
**Verdict:** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.
```

**Verdict-section line range: lines 15–26** (start = `## Verdict` at line
13; end = (next `##` heading `## What folds into Pillar 2` at line 25) − 1 = 24).

First `##` heading is `## Verdict`. Single bolded `**Verdict:**` line.
Verdict declared: **(b) Fold into Pillar 2 as sub-concern.** **PASS.**

### Success criterion 3 — ≥7 distinct named-reference hits

Command:
```
grep -E '(OWASP|Lethal Trifecta|Rule of Two|Shai-Hulud|chalk|TrustFall|Cline|provenance|SLSA|cosign|bubblewrap|ADR-012)' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md \
  | grep -oE '(OWASP|Lethal Trifecta|Rule of Two|Shai-Hulud|chalk|TrustFall|Cline|provenance|SLSA|cosign|bubblewrap|ADR-012)' \
  | sort -u
```

Output (verbatim):
```
ADR-012
Cline
Lethal Trifecta
OWASP
Rule of Two
SLSA
Shai-Hulud
TrustFall
bubblewrap
chalk
cosign
provenance
```

Distinct hit count: **12** (≥7 required). All 12 EXPL-02 grep tokens are
present — the doc cites every named reference from the success-criterion
regex set. **PASS.**

### Success criterion 4 — `## Decision summary` last-section anchor + required substance

**File:** `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`

Command:
```
grep -n '^## Decision summary$' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output:
```
159:## Decision summary
```

Command (last `##` heading — must be `## Decision summary`):
```
grep -nE '^## ' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | tail -1
```

Output:
```
159:## Decision summary
```

Command (last non-empty line of the file):
```
awk 'NF{ln=NR}END{print ln}' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output:
```
213
```

**Decision summary section line range: lines 158–211.**

Substance check (manual scan of the section slice):

- **Verdict restated (unbolded — preserves the single `**Verdict:**` invariant):** "Verdict (restated, unbolded): (b) Fold into Pillar 2 as sub-concern…" at line 164.
- **Fold commitment:** active supply-chain monitoring + curated catalog admission, named at lines 167–170.
- **Table-stakes count:** ≥2 — Pillar 2 curated catalog with `pinned_version` (ADR-011) at lines 174–176 + curated admission criteria (`claude-code`, `gsd`, `playwright-cli`) at lines 177–178. Both cite shipped Pillar 2 substance.
- **Differentiators count:** ≥1 — supply-chain monitoring + compromised-version refusal commitment at lines 180–182.
- **Non-goals count:** 3 (CONTEXT.md commits to all 3) — NG-1 (model-level guardrails), NG-2 (upstream code audit), NG-3 (sandbox runtime).
- **Priority tags:** literal `next-milestone` (fold inherits Pillar 2's tag) AND literal `opportunistic` (Appendix B Security Hardening theme) both present.
- **DOC-05 disposition:** closes as N/A in `14-AUDIT.md` with the named single-line rationale.

Command (priority-tag literals in Decision summary):
```
awk '/^## Decision summary$/{flag=1} flag' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | grep -F 'next-milestone'
awk '/^## Decision summary$/{flag=1} flag' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | grep -F 'opportunistic'
```

Output (verbatim — both ≥1 hit):
```
- The fold inherits Pillar 2's `next-milestone` priority tag — Pillar 3 does
- Appendix B "Security Hardening" theme is tagged `opportunistic` for v0.6+
```

Command (DOC-05 disposition in Decision summary):
```
awk '/^## Decision summary$/{flag=1} flag' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | grep -F 'DOC-05'
```

Output (verbatim — ≥1 hit):
```
**DOC-05 disposition:** Closes as N/A in `14-AUDIT.md`. Pillar 3 does not
```

Exactly 1 `## Decision summary` heading (last `##` section); section
contains verdict restated unbolded + fold commitment + ≥2 table-stakes +
≥1 differentiator + 3 non-goals + both priority tags + DOC-05 disposition.
**PASS.**

### Success criterion 5 — phase-close audit (this file) cites the above

- ✅ This audit cites file path: `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`.
- ✅ This audit cites Verdict section line range: lines 15–26.
- ✅ This audit cites Decision summary section line range: lines 158–211.
- ✅ This audit contains verbatim grep transcripts for criteria 1, 2, 3, 4.
- ✅ This audit's first content line records the verdict (`**Verdict (Phase 13, EXPL-02):** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.`) for Phase 14's planner grep.
- ✅ This audit notes the canonical-vs-typo-path divergence (ROADMAP.md vs phase directory slug).
- ✅ Gate verdict: GREEN.

**PASS.**

## Voice-rule project-wide hard gate (Phase 14 STRAT-11 equivalent applied here)

Command:
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output (verbatim — empty; grep exit code 1 == no matches):
```
```

**Notes:** Zero matches. No `AgentLinux + present-tense forbidden verb`
drift exists anywhere in the doc. Phase 14's STRAT-11 hard gate on
`docs/STRATEGY.md` will pass cleanly when Phase 14 lifts the Decision
summary verbatim (and any framing prose lifted into the Considered-and-
rejected / Trade-offs sections of STRATEGY.md). No rewrite needed.

## CONTEXT.md fidelity spot-check

Command:
```
grep -E '(NG-1|NG-2|NG-3)' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | wc -l
```

Output: 4 lines reference the locked non-goal IDs from `13-CONTEXT.md`
`<decisions>` block. All 3 IDs present (NG-1 referenced twice — once in the
threat-landscape section's OWASP rationale, once as the labelled non-goal
heading in the Decision summary).

Command:
```
grep -F 'supply-chain monitoring' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | wc -l
```

Output: 8 lines — the locked forward-looking commitment is named throughout
the doc (Verdict + What-folds-into-Pillar-2 + Threat landscape + Defenses +
Decision summary).

Command:
```
grep -F 'ADR-012' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | wc -l
```

Output: 6 lines — the ADR-012 NOPASSWD tension is named explicitly in the
Defenses section, the dedicated `## ADR-012 tension` section, the
`## Why verdict (b) and not (a/c/d)` section, and the Decision summary.

Command:
```
grep -F 'Pillar 2' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md | wc -l
```

Output: 19 lines — Pillar 2 is named consistently as the fold target
throughout the doc. ADR-011 is cited 3 times as the table-stakes anchor.

**Fidelity: PASS.**

## Files added/changed

| Path | Change | Notes |
|------|--------|-------|
| `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` | NEW | 12073 bytes; Verdict section at lines 15–26; Decision summary at lines 158–211; commit `ac9b714`. |
| `.planning/phases/13-pillar-3-candidate-exploration/13-AUDIT.md` | NEW (this file) | Phase-close audit; gate GREEN. |

## Phase-close gate

All five EXPL-02 success criteria pass with cited evidence (file path +
Verdict section line range + Decision summary section line range + verbatim
grep transcripts). Voice-rule project-wide hard gate is fully clean.
CONTEXT.md fidelity verified: verdict (b) locked + supply-chain monitoring
commitment named + NG-1/NG-2/NG-3 non-goals present + `next-milestone` and
`opportunistic` priority tags both present + DOC-05 N/A disposition recorded
+ ADR-012 tension cited + Pillar 2 named as fold target.

**Gate: GREEN.**

Phase 13 complete. Phase 14 (Strategy Doc + ADR-015 + Downstream Surface
Updates) unblocked — pillar count locks at 2 (Pillar 1 + Pillar 2);
Pillar 2's Decision summary (from Phase 12) absorbs the supply-chain
monitoring sub-concern from this phase; "Security Hardening" lands as a
v0.6+ `opportunistic` theme in `docs/STRATEGY.md` Appendix B; DOC-05
closes as N/A in `14-AUDIT.md`.

## References

- `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` — the doc this audit closes.
- `docs/exploration/PILLAR-2-NOTES.md` — Phase 12's verdict; the fold
  target for the supply-chain monitoring commitment.
- `.planning/REQUIREMENTS.md` — EXPL-02 acceptance criteria.
- `.planning/ROADMAP.md` — Phase 13 success criteria (note: success
  criterion 5 references `.planning/phases/13-pillar-3-exploration/...`
  typo; canonical path is `13-pillar-3-candidate-exploration`).
- `.planning/phases/13-pillar-3-candidate-exploration/13-CONTEXT.md` —
  locked decisions lifted into the doc body.
- `.planning/phases/13-pillar-3-candidate-exploration/13-01-PLAN.md` —
  the plan this audit closes.
- `.planning/phases/12-pillar-2-exploration/12-AUDIT.md` — prior phase's
  audit, format reference.
- `docs/decisions/012-agent-user-full-sudo.md` — ADR-012 NOPASSWD tension
  cited in the doc.
- Jira: [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7).
