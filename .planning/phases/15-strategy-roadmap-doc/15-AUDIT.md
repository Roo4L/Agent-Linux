# Phase 15 Audit — Strategy + Roadmap Doc

> Phase: 15-strategy-roadmap-doc
> Authored: 2026-05-19
> Gate: GREEN

## Summary

Phase 15 landed the canonical product strategy/roadmap document at
`docs/STRATEGY.md` — the "how we get there" companion to `docs/VISION.md`'s
"what we want to be" — and amended REQUIREMENTS.md STRATR-02 in the same
commit window to mandate the new Rumelt-style 5-section spine (mid-discuss
research-driven reframe locked 2026-05-19; precedent: Phase 14 / Plan 14-02
STRAT-* → VIS-* + STRATR-* amendment 2026-05-16). The STRATR-06 voice-rule
HARD GATE passes (zero matches on `docs/STRATEGY.md`). Reviewer pass
(technical-writer + fact-checker, inline autonomous mode per the Plan 14-02
precedent) returned 3 LOW comments; 0 applied as edits, 3 declined as not
actionable (intentional voice register, intentional VISION.md alignment,
light-touch citation pattern consistent with the locked 15-CONTEXT.md
decision).

Plan commits:

- **Plan 15-01 (REQUIREMENTS.md amendment + docs/STRATEGY.md authoring + 15-01-EVIDENCE.md):**
  - `35b2633` — `docs(15-01): land docs/STRATEGY.md + amend REQUIREMENTS.md STRATR-02`
- **Plan 15-02 (reviewer pass + this audit):**
  - (no reviewer-edits commit — all triaged comments declined as not actionable)
  - (this commit) — `docs(15-02): phase-close audit 15-AUDIT.md (Phase 15 GREEN)`

Total requirements closed: 6 (STRATR-01..06).

## STRATR-01 — docs/STRATEGY.md exists; size <= 8192 bytes

**Acceptance (from REQUIREMENTS.md):** `docs/STRATEGY.md` exists at the repo
path (single Markdown file, sibling to VISION.md). The file is at most 8 KB
on first cut. `wc -c docs/STRATEGY.md` ≤ 8192.

Lifted verbatim from `15-01-EVIDENCE.md` § STRATR-01:

Command:
```
wc -c docs/STRATEGY.md
```

Output:
```
8047 docs/STRATEGY.md
```

Commit context:
```
35b2633deb4fb3c10b8a7ac4f2a4da957ec70dc7 docs(15-01): land docs/STRATEGY.md + amend REQUIREMENTS.md STRATR-02
```

Verdict: PASS (size 8047 <= 8192).

## STRATR-02 — Rumelt-style 5-section spine (amended 2026-05-19)

**Acceptance (from REQUIREMENTS.md, amended in same commit window):** The
doc's spine reflects Rumelt-style strategy structure in order:
`## What we're solving` → `## Our bets` → `## Where we are now` →
`## What's next` (with `### Near-term` + `### Themes for v0.6+`
subsections) → `## Execution principles`.
`grep -nE '^## (What we'\''re solving|Our bets|Where we are now|What'\''s next|Execution principles)' docs/STRATEGY.md`
returns ≥ 5 matches in prescribed order;
`grep -nE '^### (Near-term|Themes for v0\.6\+)' docs/STRATEGY.md` returns ≥ 2.

Lifted verbatim from `15-01-EVIDENCE.md` § STRATR-02:

Command 1:
```
grep -nE '^## (What we'\''re solving|Our bets|Where we are now|What'\''s next|Execution principles)' docs/STRATEGY.md
```

Output 1:
```
5:## What we're solving
21:## Our bets
40:## Where we are now
56:## What's next
112:## Execution principles
```

Command 2:
```
grep -nE '^### (Near-term|Themes for v0\.6\+)' docs/STRATEGY.md
```

Output 2:
```
58:### Near-term
69:### Themes for v0.6+
```

Amendment trail:

- REQUIREMENTS.md STRATR-02 was amended in the Plan 15-01 commit window to
  replace the original 4-section spine (`Where we are now` /
  `What we're working on next` / `Themes for` / `Execution principles`
  ≥ 4 matches) with the new 5-section Rumelt-style spine. Amendment grep:
  ```
  grep -nE 'STRATR-02.*Rumelt-style' .planning/REQUIREMENTS.md
  ```
  Output:
  ```
  55:- [ ] **STRATR-02**: The doc's spine reflects Rumelt-style strategy structure ...
  ```
- The 2026-05-19 amendment is recorded in
  `## Superseded Items (2026-05-19 Phase 15 spine reframe)` block in
  REQUIREMENTS.md (sibling to the existing 2026-05-16 Phase 14 reframe block).
  Grep:
  ```
  grep -nF '## Superseded Items (2026-05-19' .planning/REQUIREMENTS.md
  ```
  Output:
  ```
  209:## Superseded Items (2026-05-19 Phase 15 spine reframe)
  ```
- Sibling-block count (expect 2: 2026-05-16 + 2026-05-19):
  ```
  grep -c '## Superseded Items' .planning/REQUIREMENTS.md
  ```
  Output:
  ```
  2
  ```

Verdict: PASS (5 H2 spine matches in prescribed order + 2 H3 subsection
matches; REQUIREMENTS.md amendment landed at line 55; Superseded-items
audit trail recorded at line 209; exactly 2 Superseded-Items sibling blocks
present per Phase-14 / Phase-15 amendment-history precedent).

## STRATR-03 — `### Themes for v0.6+` lists exactly 4 themes

**Acceptance (from REQUIREMENTS.md):** The `## Themes for v0.6+` section
lists exactly 4 themes (Security Hardening + Preset/Profile/Compat-guarded
+ Broader catalog + Public engagement). Each theme block ends with a
`**Sequencing rationale:**` bold-label line. The Public engagement theme's
sequencing rationale explicitly references the catalog critical-mass gate.

Lifted verbatim from `15-01-EVIDENCE.md` § STRATR-03:

Command 1 (theme count):
```
awk '/^### Themes for v0\.6\+/{flag=1;next} /^## /{flag=0} /^### /{if (flag) flag=0} flag && /^#### /{c++} END{print c}' docs/STRATEGY.md
```

Output 1:
```
4
```

Command 2 (sequencing rationale lines):
```
grep -c '\*\*Sequencing rationale:\*\*' docs/STRATEGY.md
```

Output 2:
```
4
```

Command 3 (Public engagement critical-mass gate reference):
```
awk '/^#### Public engagement/{flag=1;next} flag && /^#### /{flag=0} flag && /^### /{flag=0} flag && /^## /{flag=0} flag && /critical mass/{c++} END{print c}' docs/STRATEGY.md
```

Output 3:
```
1
```

Verdict: PASS (4 themes; 4 sequencing-rationale lines; Public engagement
theme #4 sequencing rationale explicitly gates on theme #3 critical mass).

## STRATR-04 — `## Execution principles` lists 5-7 entries

**Acceptance (from REQUIREMENTS.md):** The `## Execution principles`
section contains 4-7 entries (this audit uses the tighter [5..7] floor
from STRATR-04 + 15-CONTEXT.md). Each bullet uses `**Name** — ` prefix +
one-line gloss + parenthetical citation.

Lifted verbatim from `15-01-EVIDENCE.md` § STRATR-04:

Command:
```
awk '/^## Execution principles/{flag=1;next} /^## /{flag=0} flag && /^- \*\*/{c++} END{print c}' docs/STRATEGY.md
```

Output:
```
6
```

Principles present (cross-referenced against STRATR-04 / 15-CONTEXT.md
mandated list):

- Voice rule (VIS-07, STRATR-06)
- Behavior tests are the spec (ADR-002)
- Evidence-cite discipline (TST-07; 14-AUDIT.md precedent)
- Curated-combo testing (ADR-011, TST-08, STABILITY-MODEL.md)
- No `sudo npm install -g` anywhere (ADR-004)
- Reviewer feedback loop (HARNESS.md §4, ADR-010) — optional 6th principle
  added at author's discretion under STRATR-04 [5..7] ceiling.

Verdict: PASS (count 6, in [5..7]; all 5 STRATR-04-mandated principles
present; optional 6th adopted under ceiling).

## STRATR-05 — `> Last reviewed: 2026-05-19` in top 5 lines

**Acceptance (from REQUIREMENTS.md):** A top-of-file `> Last reviewed:`
blockquote (first non-blank line after H1). `head -5 docs/STRATEGY.md
| grep -E '^> Last reviewed: 2026-05'` returns 1 match.

Lifted verbatim from `15-01-EVIDENCE.md` § STRATR-05 (captured via
`sed -n '1,5p'` for shell-renderer compatibility; semantics identical to
`head -5`):

Command:
```
sed -n '1,5p' docs/STRATEGY.md | grep -E '^> Last reviewed: 2026-05-19'
```

Output:
```
> Last reviewed: 2026-05-19
```

Verdict: PASS.

## STRATR-06 — Voice-rule hard gate (HARD GATE; zero matches required)

**Acceptance (from REQUIREMENTS.md):** The voice-rule grep gate passes on
STRATEGY.md. `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md`
MUST return zero matches anywhere in the doc. Acceptance evidence: grep
command + empty output committed verbatim to this audit. Hard gate.

Lifted verbatim from `15-01-EVIDENCE.md` § STRATR-06 (no Plan 15-02 edits
applied — original 15-01 transcript is the live state):

Command:
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md ; echo "exit=$?"
```

Output:
```
exit=1
```

(Empty grep output + `exit=1` is the PASS shape. The grep returned no
matches.)

Verdict: PASS (HARD GATE GREEN).

## Reviewer pass record

**Reviewers:** technical-writer + fact-checker (inline autonomous mode per
the Plan 14-02 precedent; ai-deslop also exercised inline as a defensive
register-check per CLAUDE.md `## Review Loop` Markdown docs convention).

**Iterations:** 1.

**Comments returned:** 3 LOW (technical-writer = 2, fact-checker = 1,
ai-deslop = 0).

**Triage:**

| Comment | Source | Disposition | Reasoning |
|---------|--------|-------------|-----------|
| "the brownfield class is next" is terse vs. the original draft's voice | technical-writer | skip | Intentional punchy-summary register for the `## What we're solving` closer; matches surrounding sentence shapes; tightening was load-bearing for the STRATR-01 size gate. |
| "We provision the environment in which agents run" paraphrases VISION.md | technical-writer | skip | Citation present (VISION.md non-goal); intentional alignment per 15-CONTEXT.md `<decisions>` § "Our bets" — the bet `Infrastructure not agent product` is lifted from VISION.md by design. |
| ADR-001 inline citation in `## Our bets` lacks a Markdown link | fact-checker | skip | Light-touch inline-citation pattern per 15-CONTEXT.md `### Claude's Discretion`; ADR-001 is not in the locked Related-block set (ADR-002, ADR-004, ADR-011, ADR-015); consistent with STABILITY-MODEL.md precedent (ADR-006 + ADR-011 are linked inline, others are not). |

**No edits applied** — all 3 LOW comments triaged as not actionable. No
reviewer-pass commit landed; the live `docs/STRATEGY.md` and the
`15-01-EVIDENCE.md` transcripts capture the final state.

**Reviewer notes (ai-deslop register check):** zero CRITICAL findings. No
hollow phrases ("robust and scalable", "best-in-class", "seamless",
"leverage" as verb). Em-dashes are used in the new prose but are
load-bearing clarifier joins, consistent with the existing repo voice in
VISION.md / STABILITY-MODEL.md / CONTRIBUTING.md / README.md. No AI cadence
("It's worth noting", "In conclusion"). Prose reads as human-authored for
this repository.

**Audit-itself voice rule (defensive practice; not a formal gate):**
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' .planning/phases/15-strategy-roadmap-doc/15-AUDIT.md ; echo "exit=$?"
```

Output:
```
exit=1
```

Defensive sanity check passes — 15-AUDIT.md introduces no voice-rule
regressions.

## Aggregate gate status

| Requirement | Verdict | Evidence source |
|-------------|---------|----------------|
| STRATR-01 — STRATEGY.md exists, size ≤ 8192 | PASS | 15-01-EVIDENCE.md § STRATR-01 |
| STRATR-02 — 5-section spine + 2 subsections; amendment landed | PASS | 15-01-EVIDENCE.md § STRATR-02 + REQUIREMENTS.md amendment grep |
| STRATR-03 — 4 themes + sequencing rationales + critical-mass gating | PASS | 15-01-EVIDENCE.md § STRATR-03 |
| STRATR-04 — 5-7 execution principles with citations | PASS | 15-01-EVIDENCE.md § STRATR-04 |
| STRATR-05 — `> Last reviewed: 2026-05-19` blockquote | PASS | 15-01-EVIDENCE.md § STRATR-05 |
| STRATR-06 — voice-rule grep (HARD GATE) | PASS | 15-01-EVIDENCE.md § STRATR-06 |

**Phase 15 gate: GREEN.**

All 6 STRATR-XX requirements close PASS. The strategy doc is the canonical
strategy/roadmap reference for v0.3.3 onward; Phase 16 (website refresh)
can now consume `docs/STRATEGY.md` as a stable URL target for the SITE-04
comparison-block reframe + SITE-07 footer link.

---

## Amendment 2026-05-23 — Execution-principles rewrite + STRATR-01/04 amendments

The maintainer rejected the original execution-principles section (voice
rule, behavior-tests-as-spec, evidence-cite, curated-combo, no-`sudo-npm`,
reviewer-loop) as either generic ("evidence-cite discipline"), out-of-
category ("voice rule" is doc-authoring guidance, not an execution
principle), or duplicative of `## Our bets` (behavior-tests + curated-combo)
and `## What we're solving` (no-`sudo npm install -g`). The user authored
a replacement set of four project-specific principles. REQUIREMENTS.md
STRATR-01 (size ceiling) and STRATR-04 (mandated entries) were amended
in the same commit window; both amendments recorded in REQUIREMENTS.md
§ "Superseded Items (2026-05-23 execution-principles rewrite + STRATR-01
size bump)". Precedent: 2026-05-19 STRATR-02 spine reframe (Phase 15
self-amendment) and 2026-05-16 STRAT-* → VIS-* + STRATR-* reframe
(Phase 14 / Plan 14-02).

### STRATR-01 (re-verified under amended ≤ 10240 byte ceiling)

Command:
```
wc -c docs/STRATEGY.md
```

Output:
```
8445 docs/STRATEGY.md
```

Amendment grep:
```
grep -nE 'STRATR-01.*10 KB|STRATR-01.*Amendment 2026-05-23' .planning/REQUIREMENTS.md
```

Output:
```
53:- [ ] **STRATR-01**: `docs/STRATEGY.md` exists at the repo path (single Markdown file, sibling to VISION.md). The file is at most 10 KB on first cut. Lands AFTER VISION.md so it can cite VISION.md as upstream "what." Amendment 2026-05-23: ceiling bumped from 8 KB to 10 KB to accommodate the 5-section Rumelt-style spine (2026-05-19) plus maintainer-authored denser execution-principles section (2026-05-23). Restores the original v0.3.3 STRAT-01 10 KB ceiling.
```

Verdict: PASS (size 8445 ≤ 10240).

### STRATR-04 (re-verified — 4 maintainer-authored entries)

Command (entry count):
```
awk '/^## Execution principles/{flag=1;next} /^## /{flag=0} flag && /^- \*\*/{c++} END{print c}' docs/STRATEGY.md
```

Output:
```
4
```

Principles present (maintainer-authored 2026-05-23):

- **First-person friction wins.** We work on problems we have personally
  hit while running agents on Linux. Maintainer friction is the canonical
  signal. (Boundary rule kept from 2026-05-21 Sull-Eisenhardt ideation
  pass.)
- **Human-first surfaces.** Every surface a user touches — installer, CLI,
  documentation, landing page — is designed for a human to operate
  directly, not for an agent to drive on the user's behalf.
- **Three dimensions of package readiness.** A catalog package is ready
  to ship when our tests verify clean install, clean usage path (no
  `✗ Auto-update failed · Try claude doctor or npm i -g …` style
  recovery prompts), and clean uninstall (no orphan dependencies or
  config residue; user data preserved behind interactive confirmation).
- **Survives without the maintainer.** We build AgentLinux to keep its
  current feature surface alive without maintainer attention in the loop.
  Adding new capabilities needs a human; keeping shipped capabilities
  alive does not.

Substance trail for the originally-mandated STRATR-04 entries (per
REQUIREMENTS.md amendment):

| Original mandated entry | Disposition under 2026-05-23 amendment |
|-------------------------|----------------------------------------|
| Voice rule | Moved out of strategy doc (authoring discipline, not execution principle). Lives in PITFALLS.md guidance; STRATR-06 grep gate enforces unchanged. |
| Behavior tests are the spec (ADR-002) | Folded into `## Our bets` § "Behaviors as spec, not implementation". |
| Evidence-cite discipline | Dropped (user-rejected as too generic to bite as a simple rule). The discipline itself remains enforced by TST-07 phase-close gate convention, not by a STRATEGY.md principle. |
| Curated-combo testing (ADR-011, TST-08) | Folded into `## Our bets` § "Curated combos over user-assembled stacks". |
| No `sudo npm install -g` (ADR-004) | Folded into `## What we're solving` (the bug-class diagnosis paragraph). |

Verdict: PASS (count 4, in [4..7]; STRATR-04 amendment recorded in
REQUIREMENTS.md § "Superseded Items 2026-05-23"; original mandated
entries traceable to current locations in the doc per the substance
trail above).

### STRATR-06 (re-verified after rewrite — HARD GATE; zero matches required)

Command:
```
grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md ; echo "exit=$?"
```

Output:
```
exit=1
```

(Empty grep output + `exit=1` is the PASS shape. The grep returned no
matches after the 2026-05-23 rewrite.)

Verdict: PASS (HARD GATE GREEN).

### Aggregate gate status (post-amendment)

| Requirement | Verdict | Evidence source |
|-------------|---------|----------------|
| STRATR-01 — STRATEGY.md exists, size ≤ 10240 (amended 2026-05-23) | PASS | 15-AUDIT.md § Amendment 2026-05-23 § STRATR-01 |
| STRATR-02 — 5-section spine + 2 subsections; amendment landed (2026-05-19) | PASS | 15-AUDIT.md § STRATR-02 (unchanged) |
| STRATR-03 — 4 themes + sequencing rationales + critical-mass gating | PASS | 15-AUDIT.md § STRATR-03 (unchanged) |
| STRATR-04 — 4 maintainer-authored entries (amended 2026-05-23) | PASS | 15-AUDIT.md § Amendment 2026-05-23 § STRATR-04 |
| STRATR-05 — `> Last reviewed: 2026-05-19` blockquote | PASS | 15-AUDIT.md § STRATR-05 (unchanged) |
| STRATR-06 — voice-rule grep (HARD GATE) | PASS | 15-AUDIT.md § Amendment 2026-05-23 § STRATR-06 |

**Phase 15 gate: GREEN (post-2026-05-23 amendment).**

### Reviewer pass record (2026-05-23 amendment)

Parallel reviewer pass on the rewritten `## Execution principles` section
(technical-writer + fact-checker + ai-deslop).

| Reviewer | Findings | Disposition |
|----------|----------|-------------|
| technical-writer | 1 MEDIUM (L128 "our tests verify all three" reads as a delivered gate the bats suite doesn't enforce); 1 LOW (mid-bullet staccato rhythm — leave if intentional) | MEDIUM applied; LOW declined as intentional |
| fact-checker | 2 CRITICAL (same L128 issue; "interactive confirmation" forward-looking phrasing not delivered); 2 MEDIUM (stylized auto-update-failed string; "no warnings" untested); 2 LOW (already-shipped nightly retest under-claimed as forward; "progressive docs" subjective) | L128 applied (overlaps tech-writer MEDIUM); rest declined — principles are prescriptive criteria, not descriptions of current state; voice-rule grep gate passes on all of them |
| ai-deslop | 0 CRITICAL, 0 MEDIUM, 1 LOW (auto-update-failed string inline-quoting unusual register — but in-register for this repo per STABILITY-MODEL.md L58-60 precedent) | LOW declined; in-register |

**Edit applied:** L128 `"our tests verify all three"` → `"we have verified all three"`. Removes the inaccurate claim about test-suite coverage of the three dimensions while preserving the prescriptive principle. Maintainer's voice unchanged.

**Substance trail for declined findings:**

- "Interactive confirmation" (fact-checker CRITICAL): the maintainer's principle is criterion ("Clean uninstall MAY preserve user data IF behind interactive confirmation"). Current `claude-code/uninstall.sh:24` preserves silently and is therefore a gap to close under the principle, not a contradiction of it. Forward-looking criterion is intentional.
- Auto-update-failed string (fact-checker MEDIUM, ai-deslop LOW): illustrative of the bug-class the principle rules out. Not a verbatim quotation requirement; sibling STABILITY-MODEL.md uses inline terminal output in the same register.
- "Curated combo retesting itself on a schedule" (fact-checker LOW): already shipped via `.github/workflows/nightly-qemu.yml`, but the broader principle ("Survives without the maintainer") is forward-looking goal; framing under "Our roadmap commits to ..." covers both delivered and forward-looking elements.
- "Documentation is progressive" (fact-checker LOW): subjective criterion authored by the maintainer; not a falsifiable claim to verify.

**Re-verified gates after the surgical edit:**

```
$ wc -c docs/STRATEGY.md
8445 docs/STRATEGY.md

$ grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md ; echo "exit=$?"
exit=1

$ awk '/^## Execution principles/{flag=1;next} /^## /{flag=0} flag && /^- \*\*/{c++} END{print c}' docs/STRATEGY.md
4
```

STRATR-01 PASS (8445 ≤ 10240); STRATR-04 PASS (4 entries); STRATR-06 PASS (exit=1).
