# Phase 15 Audit — Vision Doc + ADR-016 + Downstream Surface Updates

> Phase: 14-vision-doc-and-downstream
> Authored: 2026-05-16
> Gate: GREEN

## Summary

Phase 15 landed the canonical product-vision document at `docs/VISION.md`,
recorded the AL-7 framing decision in ADR-016 (`docs/decisions/016-agenda-redefinition.md`),
and propagated the two-pillar framing to the four downstream documentation
surfaces (README, CONTRIBUTING, .planning/PROJECT.md, docs/STABILITY-MODEL.md).
DOC-05 closed N/A under Phase 14 verdict (b) — Pillar 3 did not survive, so
no edit to ADR-012 was required. The VIS-07 voice-rule hard gate passes (zero
matches on `docs/VISION.md`) and the same grep returns zero matches on every
Plan-14-02-edited file (defensive practice — not a formal gate but captured
under DOC-01..DOC-04 below).

Plan commits:

- **Plan 15-01 (vision-doc verification + ADR-016 authoring):**
  - `864d64c` — `docs(14): draft docs/VISION.md (Phase 15 reframe — vision-only)`
  - `0b6e744` — `docs(14-01): author ADR-016 + capture VIS-01..07 evidence`
  - `289e12a` — `docs(14-01): phase-close summary 15-01-SUMMARY.md`
- **Plan 15-02 (downstream surface updates + this audit):**
  - (this commit) — `docs(14-02): propagate vision framing + 15-AUDIT.md GREEN`

Total requirements closed: 14 (9 VIS + 5 DOC, of which DOC-05 is N/A).

## VIS-01 — docs/VISION.md exists; size <= 6144 bytes

**Acceptance (from REQUIREMENTS.md):** `docs/VISION.md` exists at the repo
path (single Markdown file, sibling to `docs/STABILITY-MODEL.md` and
`docs/HARNESS.md`). The file is at most 6 KB on first cut (target 4–5 KB).

Lifted verbatim from `15-01-EVIDENCE.md` § VIS-01:

Command:
```
wc -c docs/VISION.md
```

Output:
```
4500 docs/VISION.md
```

Commit context:
```
864d64c9d6018d8a9589a60ae15529ff8630ec12 docs(14): draft docs/VISION.md (Phase 15 reframe — vision-only)
```

Verdict: PASS (size 4500 <= 6144).

## VIS-02 — Spine: Mission / Positioning / two pillars / Guiding principles / What we're explicitly not

**Acceptance (from REQUIREMENTS.md):** The doc's spine reflects vision-only
structure: `## Mission` (with `### Positioning` subsection), `## The two
pillars`, `## Guiding principles`, `## What we're explicitly not`.

Lifted verbatim from `15-01-EVIDENCE.md` § VIS-02:

Command 1:
```
grep -nE '^## (Mission|The two pillars|Guiding principles|What we'\''re explicitly not)' docs/VISION.md
```

Output 1:
```
5:## Mission
24:## The two pillars
48:## Guiding principles
79:## What we're explicitly not
```

Command 2:
```
grep -nE '^### Positioning' docs/VISION.md
```

Output 2:
```
15:### Positioning
```

Verdict: PASS (4 H2 spine matches in prescribed order + 1 Positioning subsection).

## VIS-03 — Exactly 2 pillars; no Today/Direction subsections

**Acceptance (from REQUIREMENTS.md):** The Pillars section contains exactly 2
pillars (locked by Phase 14 verdict (b)). Pillars are named by the optimization
value. No `#### Today` / `#### Direction` subsections inside pillars.

Lifted verbatim from `15-01-EVIDENCE.md` § VIS-03:

Command 1 (count):
```
grep -cE '^### Pillar [0-9]+' docs/VISION.md
```

Output 1:
```
2
```

Command 2 (list):
```
grep -nE '^### Pillar [0-9]+' docs/VISION.md
```

Output 2:
```
29:### Pillar 1 — Time-to-productive
39:### Pillar 2 — Stability
```

Command 3 (negative):
```
grep -nE '^#### (Today|Direction)' docs/VISION.md ; echo "exit=$?"
```

Output 3:
```
exit=1
```

Verdict: PASS (exactly 2 pillars named by optimization value; no Today/Direction subsections).

## VIS-04 — Guiding principles: 4–6 `###` entries

**Acceptance (from REQUIREMENTS.md):** A `## Guiding principles` section with
4–6 named principles. Each is `### {Principle name}` heading + short paragraph.

Lifted verbatim from `15-01-EVIDENCE.md` § VIS-04:

Command:
```
awk '/^## Guiding principles/{flag=1;next} /^## /{flag=0} flag && /^### /{c++} END{print c}' docs/VISION.md
```

Output:
```
4
```

Verdict: PASS (count 4, in [4..6]).

## VIS-05 — What we're explicitly not: >= 4 bullet items

**Acceptance (from REQUIREMENTS.md):** A `## What we're explicitly not` section
with at least 4 vision-level non-goals as bulleted items, each with one-line
rationale.

Lifted verbatim from `15-01-EVIDENCE.md` § VIS-05:

Command:
```
awk '/^## What we'\''re explicitly not/{flag=1;next} /^## /{flag=0} flag && /^- /{c++} END{print c}' docs/VISION.md
```

Output:
```
5
```

Verdict: PASS (count 5, >= 4).

## VIS-06 — `> Last reviewed: 2026-05-...` in top 5 lines

**Acceptance (from REQUIREMENTS.md):** A top-of-file `> Last reviewed:`
blockquote (first non-blank line after H1). `head -5 docs/VISION.md | grep -E
'^> Last reviewed: 2026-05'` returns 1 match.

Lifted verbatim from `15-01-EVIDENCE.md` § VIS-06:

Command:
```
head -5 docs/VISION.md | grep -E '^> Last reviewed: 2026-05'
```

Output:
```
> Last reviewed: 2026-05-16
```

Verdict: PASS.

## VIS-07 — Voice-rule hard gate (HARD GATE)

**Acceptance (from REQUIREMENTS.md):** The voice-rule grep gate passes on
VISION.md. Run: `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/VISION.md`
MUST return zero matches anywhere in the doc. Acceptance evidence: the grep
command + its empty output committed verbatim to `15-AUDIT.md`. Hard gate.

Lifted verbatim from `15-01-EVIDENCE.md` § VIS-07:

Command:
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/VISION.md ; echo "exit=$?"
```

Output:
```
exit=1
```

(Empty grep output + `exit=1` is the PASS shape. The grep returned no matches.)

Verdict: PASS (HARD GATE GREEN).

Note: Plan 15-02 additionally re-ran the voice-rule grep against every
Plan-14-02-edited file as a defensive check; transcripts captured under
DOC-01..DOC-04 below.

## VIS-08 — Inbound cross-link map populated

**Acceptance (from REQUIREMENTS.md):** Cross-link map populated. Inbound —
`README.md` (About + Links), `CONTRIBUTING.md` (one paragraph),
`.planning/PROJECT.md` (Core Value section), `docs/STABILITY-MODEL.md`
(Related section) each gain a back-pointer to VISION.md. Phase-close audit
lists every changed file with the line range of the back-pointer edit.

Inbound back-pointer file list:

Command:
```
grep -lE 'docs/VISION\.md' README.md CONTRIBUTING.md .planning/PROJECT.md docs/STABILITY-MODEL.md
```

Output:
```
README.md
CONTRIBUTING.md
.planning/PROJECT.md
docs/STABILITY-MODEL.md
```

Per-file line-range cites (derived from `grep -n 'docs/VISION\.md' <file>`):

- **README.md** — Links row at line 141 (`- **Vision:** [docs/VISION.md](docs/VISION.md)`); About paragraph at lines 159-163 (`AgentLinux is framed around two pillars: **Time-to-productive** ... See [docs/VISION.md](docs/VISION.md) for the full framing.`).
- **CONTRIBUTING.md** — `## Why this project exists` heading at line 6; paragraph body at lines 8-18 with VISION.md link at line 11 (`across upstream churn). See [docs/VISION.md](docs/VISION.md) for the`).
- **.planning/PROJECT.md** — Core Value cross-reference at line 13 (`See [docs/VISION.md](../docs/VISION.md) for the framing this Core Value seeds.`); Current Milestone Goal link at line 19 (`See [../docs/VISION.md](../docs/VISION.md) for the canonical framing.`); Vision target-features bullet at line 28 (`- Canonical **vision document** at [\`../docs/VISION.md\`](../docs/VISION.md)`); plus additional non-link references at lines 34, 98, 112, 150.
- **docs/STABILITY-MODEL.md** — Related back-link at line 125 (`- [docs/VISION.md — Pillar 2: Stability](VISION.md)`).

Verdict: PASS (4 files, 4 inbound back-pointer edits, each line-range cited).

## VIS-09 — ADR-016 authored

**Acceptance (from REQUIREMENTS.md):** `docs/decisions/016-agenda-redefinition.md`
(ADR-016) lands in the same Phase 15 commit window as VISION.md. Contains:
`Status: Accepted`, `Context`, `Decision`, `Considered alternatives` (≥3),
`Consequences`, back-links to AL-7 + VISION.md.

Commit:
```
git log --oneline -- docs/decisions/016-agenda-redefinition.md | head -1
```

Output:
```
0b6e744 docs(14-01): author ADR-016 + capture VIS-01..07 evidence
```

H2 spine check:
```
grep -nE '^## (Status|Context|Decision|Considered alternatives|Consequences)' docs/decisions/016-agenda-redefinition.md
```

Output:
```
8:## Status
12:## Context
22:## Decision
30:## Considered alternatives
44:## Consequences
```

Considered-alternatives count (≥3 required):
```
grep -cE '^### Alternative [0-9]' docs/decisions/016-agenda-redefinition.md
```

Output:
```
3
```

Back-link checks:
```
grep -c 'AL-7' docs/decisions/016-agenda-redefinition.md
```

Output:
```
4
```

```
grep -c 'VISION.md' docs/decisions/016-agenda-redefinition.md
```

Output:
```
9
```

Verdict: PASS (5 H2 spine sections, 3 considered alternatives, 4 AL-7 references, 9 VISION.md references; Status Accepted set at file head).

## DOC-01 — README.md About + Links

**Acceptance (from REQUIREMENTS.md):** `README.md` is updated. The `## About`
section gains a single sentence naming the two pillars and linking to
`docs/VISION.md`. The `## Links` section gains a `Vision: [docs/VISION.md](docs/VISION.md)`
row. No other README copy is rewritten in this requirement.

Links row evidence:
```
grep -nE '^- \*\*Vision:\*\* \[docs/VISION\.md\]\(docs/VISION\.md\)$' README.md
```

Output:
```
141:- **Vision:** [docs/VISION.md](docs/VISION.md)
```

About paragraph evidence:
```
grep -nE 'AgentLinux is framed around two pillars' README.md
```

Output:
```
159:AgentLinux is framed around two pillars: **Time-to-productive** (the
```

The full About-paragraph spans lines 159-163 and contains both pillar names
plus a `[docs/VISION.md](docs/VISION.md)` link. The pre-existing About
paragraph (the EACCES / recursive-shim narrative at lines 148-157) is
preserved byte-for-byte; the new paragraph is additive framing context.

Voice-rule grep on README.md (defensive — should be empty):
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' README.md ; echo "exit=$?"
```

Output:
```
exit=1
```

Commit: this audit + the four DOC edits ship together in the Plan 15-02 commit.

Verdict: PASS.

## DOC-02 — CONTRIBUTING.md "Why this project exists"

**Acceptance (from REQUIREMENTS.md):** `CONTRIBUTING.md` is updated. A "Why
this project exists" paragraph (one short paragraph) links to `docs/VISION.md`
and names which pillar(s) currently accept contributions today (Pillar 1 =
yes; Pillar 2 = early-stage).

Heading evidence:
```
grep -nE '^## Why this project exists$' CONTRIBUTING.md
```

Output:
```
6:## Why this project exists
```

Per-pillar contribution status evidence:
```
grep -nE 'Pillar 1 is what v0\.3\.0|Pillar 2 is early-stage' CONTRIBUTING.md
```

Output:
```
12:full framing. Pillar 1 is what v0.3.0 already shipped — contributions
14:today. Pillar 2 is early-stage — the supply-chain monitoring + curated
```

VISION.md link inside the paragraph:
```
grep -nE '\[docs/VISION\.md\]\(docs/VISION\.md\)' CONTRIBUTING.md
```

Output:
```
11:across upstream churn). See [docs/VISION.md](docs/VISION.md) for the
```

Voice-rule grep on CONTRIBUTING.md (defensive — should be empty):
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' CONTRIBUTING.md ; echo "exit=$?"
```

Output:
```
exit=1
```

Commit: this audit + the four DOC edits ship together in the Plan 15-02 commit.

Verdict: PASS.

## DOC-03 — .planning/PROJECT.md Core Value + Current Milestone + Out-of-Scope refresh

**Acceptance (from REQUIREMENTS.md):** `.planning/PROJECT.md` Core Value /
Current Milestone sections cross-reference `docs/VISION.md` (one link in each
section). The Out-of-Scope list reflects any new non-goals that EXPL-01 /
EXPL-02 surfaced.

VISION.md occurrence count (>= 3 required):
```
grep -c 'docs/VISION\.md' .planning/PROJECT.md
```

Output:
```
7
```

Stale "three pillars" string absent:
```
grep -c 'The three pillars (per AL-7)' .planning/PROJECT.md
```

Output:
```
0
```

Stale "measurable benchmarks" string absent:
```
grep -c 'measurable benchmarks' .planning/PROJECT.md
```

Output:
```
0
```

(Note: one historical "three pillars" mention persists at line 185 inside the
**preserved** Key Decisions audit-trail row `Agenda redefinition (v0.3.3)
(2026-05-09, AL-7)`. Plan 15-02 explicitly preserved that historical row and
appended a new 2026-05-16 reframe row so the decision-evolution trail
remains visible. The acceptance criterion targets `The three pillars (per
AL-7)` specifically — zero matches confirmed.)

Two-pillar lock line:
```
grep -n 'The two pillars (locked by Phase 14 verdict (b))' .planning/PROJECT.md
```

Output:
```
21:**The two pillars (locked by Phase 14 verdict (b)):**
```

Post-reframe requirement categories present:
```
grep -nE 'EXPL-XX|VIS-XX|STRATR-XX|DOC-XX|SITE-XX' .planning/PROJECT.md
```

Output:
```
97:- **EXPL-XX** (Phase 13 + 13): Pillar exploration verdicts — `docs/exploration/PILLAR-2-NOTES.md`, `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`. Completed 2026-05-10.
98:- **VIS-XX** (Phase 15): `docs/VISION.md` content + voice-rule grep gate (VIS-07) + ADR-016 (VIS-09).
99:- **DOC-XX** (Phase 15): Downstream surface back-pointers to VISION.md (README, CONTRIBUTING, PROJECT.md, STABILITY-MODEL.md). DOC-05 closed N/A (Phase 14 verdict (b)).
100:- **STRATR-XX** (Phase 16): `docs/STRATEGY.md` content + voice-rule grep gate (STRATR-06).
101:- **SITE-XX** (Phase 17): Website refresh at agentlinux.org reflecting the two-pillar framing + voice-rule grep gate (SITE-06) on rendered HTML.
```

Reframe row append:
```
grep -n '2026-05-16 reframe' .planning/PROJECT.md
```

Output:
```
188:| **2026-05-16 reframe — two pillars + vision/strategy split** (ADR-016) | ... | — Active (Phase 15 lands the vision doc + ADR-016; Phase 16 lands the strategy doc; Phase 17 renumbered from old Phase 16) |
```

Footer date update:
```
grep -n 'Last updated: 2026-05-16' .planning/PROJECT.md
```

Output:
```
208:*Last updated: 2026-05-16 — v0.4.0 (Open-Source Release) shipped; v0.3.3 (Agenda Redefinition, AL-7) reframed to two-pillar vision-only Phase 15 + strategy-doc Phase 16 + website-refresh Phase 17. ADR-016 records the framing decision.*
```

Voice-rule grep on .planning/PROJECT.md (defensive — should be empty):
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' .planning/PROJECT.md ; echo "exit=$?"
```

Output:
```
exit=1
```

Preserved sections (byte-stable): `## Previous Milestone: v0.4.0`, `### v0.3.0
AgentLinux Plugin`, `### v0.2.0 First Distro Image`, `## Requirements ##
Validated` list, `## Constraints`, `## Evolution`, and the historical Key
Decisions rows above line 188.

Commit: this audit + the four DOC edits ship together in the Plan 15-02 commit.

Verdict: PASS.

## DOC-04 — docs/STABILITY-MODEL.md Related back-link

**Acceptance (from REQUIREMENTS.md):** `docs/STABILITY-MODEL.md` gains a
`Related` section (or equivalent) with a back-link to `docs/VISION.md` Pillar 2
(since STABILITY-MODEL.md is the ADR-011 user companion and ADR-011 is the
pillar-2 seed).

Back-link evidence:
```
grep -nE '\[docs/VISION\.md — Pillar 2: Stability\]' docs/STABILITY-MODEL.md
```

Output:
```
125:- [docs/VISION.md — Pillar 2: Stability](VISION.md)
```

The bullet sits inside the `## Related` section (line 117 onward) — its
two-line body at lines 125-126 names "Pillar 2 — Stability" in the link text
and adds the framing/mechanism rationale. Existing Related entries (ADR-011
at lines 119-121, ADR-006 at lines 122-123, README.md at line 124) are
preserved byte-for-byte.

Voice-rule grep on docs/STABILITY-MODEL.md (defensive — should be empty):
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STABILITY-MODEL.md ; echo "exit=$?"
```

Output:
```
exit=1
```

Commit: this audit + the four DOC edits ship together in the Plan 15-02 commit.

Verdict: PASS.

## DOC-05 — Closed N/A (Phase 14 verdict (b))

**Acceptance (from REQUIREMENTS.md, pre-locked closed-N/A form):** Phase 14
verdict (b) — Pillar 3 did not survive. No edit to
`docs/decisions/012-agent-user-full-sudo.md` (ADR-012) needed. The audit
records DOC-05 as N/A with a one-line decision: "no edit needed because pillar
3 did not survive Phase 14"; the audit explicitly cites EXPL-02's `## Verdict`
line. The unresolved ADR-012 tension is recorded inside Pillar 2's section in
VISION.md as a known limitation, not via an ADR file edit.

**Disposition: N/A.** No edit needed because pillar 3 did not survive Phase 14.

Phase 14 verdict line, cited verbatim from `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`
line 17:

```
sed -n '17p' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md
```

Output:
```
**Verdict:** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.
```

The ADR-012 NOPASSWD tension surfaced by EXPL-02 is recorded inside
`docs/VISION.md` Pillar 2 prose and inside ADR-016's `## Consequences` section
(per `15-CONTEXT.md` § Decisions — ADR-016 Consequences), not via an edit to
ADR-012 itself.

Verdict: N/A (closed per Phase 14 verdict (b)).

## Aggregate gate status

| Requirement | Verdict |
|-------------|---------|
| VIS-01 — VISION.md exists, ≤ 6 KB | PASS |
| VIS-02 — Spine: Mission / Positioning / two pillars / Guiding principles / What we're explicitly not | PASS |
| VIS-03 — Exactly 2 pillars; no Today/Direction | PASS |
| VIS-04 — Guiding principles 4–6 entries | PASS |
| VIS-05 — What we're explicitly not ≥ 4 bullets | PASS |
| VIS-06 — `> Last reviewed:` header | PASS |
| VIS-07 — Voice-rule grep (HARD GATE) | PASS |
| VIS-08 — Inbound cross-link map populated | PASS |
| VIS-09 — ADR-016 authored | PASS |
| DOC-01 — README.md About + Links | PASS |
| DOC-02 — CONTRIBUTING.md "Why this project exists" | PASS |
| DOC-03 — .planning/PROJECT.md three-pillar → two-pillar rewrite | PASS |
| DOC-04 — docs/STABILITY-MODEL.md Related back-link | PASS |
| DOC-05 — Closed N/A (Phase 14 verdict (b)) | N/A |

**Phase 15 gate: GREEN.**

13 PASS + 1 N/A across 14 requirements.

### Reviewer notes (Claude's discretion — 15-CONTEXT.md `### Claude's Discretion`)

**Plan 15-01 reviewer pass** (per 15-CONTEXT.md § Reviewer pass — already run
2026-05-16): VISION.md `f95a4ee` carried a parallel technical-writer +
fact-checker reviewer pass. fact-checker returned zero CRITICAL/MEDIUM/LOW
findings (all claims verified against Phase 13 + Phase 14 locked verdicts).
technical-writer returned zero CRITICAL + 4 MEDIUM + 4 LOW polish suggestions;
three small polish edits applied (drop redundant "single", British→American
"behavior", reframe the sandbox-primitives list for the product-leadership
audience). ADR-016 (Plan 15-01) likewise carried a technical-writer +
fact-checker review at commit `0b6e744` — zero CRITICAL findings; voice-rule
clean; three considered-and-rejected alternatives recorded.

**Plan 15-02 reviewer pass** (inline autonomous mode, this plan): the four
downstream surface edits (README, CONTRIBUTING, .planning/PROJECT.md,
docs/STABILITY-MODEL.md) ran technical-writer + fact-checker + ai-deslop
inline.
- **technical-writer:** zero CRITICAL findings. All four edits hold the
  surrounding-prose register (delivered-fact voice in README About + STABILITY
  Related; declarative-but-not-promise-flavored in CONTRIBUTING Why + PROJECT
  Goal/pillars). PROJECT.md's six-anchor rewrite holds register across every
  anchor.
- **fact-checker:** zero CRITICAL findings. DOC-01 pillar names exact-match
  VISION.md lines 29 + 39; DOC-02 "Pillar 1 is what v0.3.0 already shipped"
  verified against PROJECT.md `### v0.3.0 AgentLinux Plugin` (54/54
  requirements shipped, ADR-001..ADR-012 carried forward); DOC-03 Phase-13
  verdict cite matches `PILLAR-3-CANDIDATE-NOTES.md` line 17 byte-for-byte;
  Phase 16 / Phase 17 numbering verified against `.planning/ROADMAP.md` lines
  38-39; DOC-04 "ADR-011 is the pillar-2 seed" framing verified against
  ADR-011's stability-first-version-pinning content + STABILITY-MODEL.md
  header "TL;DR of ADR-011" + VISION.md Pillar 2's Stability framing.
- **ai-deslop:** zero CRITICAL findings. No hollow phrases ("robust and
  scalable," "best-in-class," "seamless," "leverage" as verb). Em-dashes are
  used in the new prose but are load-bearing (clarifier joins between subject
  and the noun-phrase context), consistent with the existing repo voice that
  uses em-dashes liberally throughout VISION.md, CONTRIBUTING.md, README.md.
  No AI cadence (no "It's worth noting," no closing "In conclusion,"). Prose
  reads as human-authored for this repository.

MEDIUM/LOW disposition (Plan 15-02): two LOW findings surfaced — (1) The
"the curated toolchain holds compatible across upstream churn" phrase appears
in three files (README About, CONTRIBUTING Why, PROJECT Current Milestone) —
intentional consistency, retained as a VIS-08 cross-link signal; (2) PROJECT
Goal sentence is long (~75 words) — matches surrounding milestone-goal
sentence shapes; register-consistent. No edits applied; both retained.

Consolidated voice-rule grep across all five Phase-14 files (defensive
sanity check; not the formal gate — VIS-07 alone is the formal gate):

```
for f in README.md CONTRIBUTING.md .planning/PROJECT.md docs/STABILITY-MODEL.md docs/VISION.md ; do
  echo "=== $f ==="
  grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' "$f"
done
```

Output (every section empty — clean):
```
=== README.md ===
=== CONTRIBUTING.md ===
=== .planning/PROJECT.md ===
=== docs/STABILITY-MODEL.md ===
=== docs/VISION.md ===
```

Defensive sanity check passes. VIS-07 hard gate holds; Plan 15-02 introduced
no voice-rule regressions on any edited file.
