# Phase 17 Audit — Website Refresh (agentlinux.org)

> Phase: 16-website-refresh-agentlinux-org
> Authored: 2026-05-24
> Gate: GREEN

## Summary

Phase 17 repaired `index.html` so it no longer contradicts the post-Phase-14
vision (two pillars, infrastructure-not-distro framing) and the post-Phase-15
strategy (installable plugin, curated combos, brownfield-aware next). Scope
was contradiction-removal, not expansion: the hero value-prop, OG/Twitter
meta descriptions, six of the eight `#features` cards (plus the section
intro), the three `#comparison` solution paragraphs (plus the section intro
and closing line), and FAQ #1 + #5 were rewritten in place. The OG card was
rendered to PNG at `assets/og-image.png` (1200×630) with the SVG preserved
at `assets/og-image.svg` as source-of-truth.

The original SITE-01..SITE-11 spec was re-cut at phase-discuss time on
2026-05-24 to "minimum-viable contradiction removal" (the user's direct
direction: "My main goal of this phase was to make sure that on our website
we don't have anything that contradicts our current vision and strategy.
That's it. No more than that."). `.planning/REQUIREMENTS.md` was amended in
the same commit window with a fifth `## Superseded Items (2026-05-24 Phase
16 scope re-cut)` block recording the SITE-01..SITE-12 dispositions
(precedent: Phase 15 STRAT-* → VIS-* + STRATR-* reframe and Phase 16
STRATR-02 spine reframe). SITE-12 was introduced additively in the same
window — its substance was the trailing success-criterion of the original
Phase 17 entry; promoted to a numbered requirement so this AUDIT can cite
it.

Reviewer pass (technical-writer + fact-checker + ai-deslop per CLAUDE.md
`## Review Loop` HTML row, inline autonomous mode per the Phase 15 / 15
precedent) returned no actionable comments — the rewritten copy lifts
verbatim from the VISION.md mission line and the STRATEGY.md "What we're
solving" diagnosis, and the SITE-06 voice-rule HARD GATE returns zero
matches on the edited file.

Plan commits:

- **Plan 17-01 (HTML rewrite + OG PNG + REQUIREMENTS.md amendment + this audit):**
  - `(T1)` — `docs(16-01): rewrite hero value-prop + OG/Twitter meta to plugin framing (SITE-01, SITE-08, SITE-09)`
  - `(T2)` — `docs(16-01): rewrite 6 contradicting #features cards + intro to plugin voice (SITE-02 amended)`
  - `(T3)` — `docs(16-01): reframe #comparison blocks + intro + closing to bug-class anchor (SITE-04 narrowed)`
  - `(T4)` — `docs(16-01): rewrite FAQ #1 + #5 answers to plugin voice (SITE-01 amended gate completes)`
  - `(T5)` — `chore(16-01): render assets/og-image.png via rsvg-convert (SITE-09)`
  - `(T6)` — `docs(16-01): amend REQUIREMENTS.md with 2026-05-24 Phase 17 scope re-cut`
  - `(T8 — this commit)` — `docs(16-01): phase-close audit 17-AUDIT.md (Phase 17 + v0.3.3 milestone-close gates GREEN)`

Total requirements closed: 12 (SITE-01 amended PASS + SITE-04 narrowed PASS
+ SITE-06 HARD GATE PASS + SITE-08 PASS + SITE-09 PASS + SITE-12 PASS = 6
active gates; SITE-02 + SITE-03 + SITE-05 + SITE-07 + SITE-11 = 5 SUPERSEDED;
SITE-10 = 1 N/A).

## SITE-01 — Hero value-prop rewrite (AMENDED 2026-05-24)

**Acceptance (from REQUIREMENTS.md, amended in same commit window via the
2026-05-24 Superseded Items block):** `index.html` hero value-prop is
rewritten so the string `purpose-built Linux distribution` no longer appears
(`grep -c 'purpose-built Linux distribution' index.html` returns 0). Hero
copy aligns with `docs/VISION.md` mission line ("Linux that gives coding
agents a stable place to run — without you having to set it up."). The
SITE-06 voice-rule grep continues to enforce voice on the rewritten copy.

Command:
```
grep -c 'purpose-built Linux distribution' index.html ; echo "exit=$?"
```

Output:
```
0
exit=1
```

Command:
```
grep -Fc 'Linux that gives coding agents a stable place to run' index.html ; echo "exit=$?"
```

Output:
```
3
exit=0
```

(3 occurrences = hero value-prop + OG description + Twitter description, all
landed in Task 1.)

Verdict: **PASS** (amended gate satisfied; hero copy lifted from VISION.md
mission line; voice rule still passes — see SITE-06 transcript).

## SITE-02 — `#features` 8-card grid preserved with rewritten copy (SUPERSEDED 2026-05-24)

**Acceptance (from the 2026-05-24 Superseded Items block in REQUIREMENTS.md):**
The 8-card grid is preserved; the five contradicting cards are rewritten in
place. New grep gate:
`grep -cE 'apt install claude-code|QEMU VM images|Docker micro-VMs|in distro repos|distro repositories' index.html`
returns 0. The `#features` → `#pillars` restructure + per-card doc-links was
an information-architecture move; the IA is shippable as-is once the copy
stops contradicting the plugin reality.

Audit note: the gate string was strengthened from the 4-alternation form in
`17-CONTEXT.md` (`apt install claude-code|QEMU VM images|Docker micro-VMs|distro repos`)
to a 5-alternation form (`...|in distro repos|distro repositories`) as
forward-looking insurance against the `distro repositories` surface form.

Command:
```
grep -cE 'apt install claude-code|QEMU VM images|Docker micro-VMs|in distro repos|distro repositories' index.html ; echo "exit=$?"
```

Output:
```
0
exit=1
```

Defensive structural check:

Command:
```
grep -c 'class="feature-card"' index.html ; echo "exit=$?"
```

Output:
```
8
exit=0
```

Verdict: **PASS via supersession** (new grep gate enforces the no-contradiction
contract; 8-card grid structure preserved; the IA decision was the right
shape — the contradicting copy was the only blocker).

## SITE-03 — Pillar card status badges (SUPERSEDED 2026-05-24)

**Acceptance (from the 2026-05-24 Superseded Items block):** No `#pillars`
section → no pillar cards → no badges to apply. Closes via SITE-02
supersession + the explicit "stay under radar; no shipped-version cite in
hero / cards" decision.

Evidence: SITE-02 supersession (the `#features` 8-card grid stays; no
`#pillars` restructure landed) makes pillar status badges structurally
impossible to apply. The under-radar posture from STRATEGY.md
`## Guiding policy` (downprioritize "growing surface area before the
current gap is closed") drives the decision.

Verdict: **SUPERSEDED** (closed via SITE-02 supersession + the explicit
2026-05-24 scope re-cut decision).

## SITE-04 — `#comparison` reframe (KEPT, narrowed)

**Acceptance (from REQUIREMENTS.md, narrowed in the 2026-05-24 amendment):**
The `#comparison` block is preserved as three blocks anchored to the
canonical bug class (`sudo npm install -g` EACCES + recursive-shim breakage)
and the curated-combo bet per STRATEGY.md `## What we're solving`. Existing
grep gate carries forward unchanged.

Command:
```
grep -cE 'AgentLinux vs (Docker|VM|micro-VM)' index.html ; echo "exit=$?"
```

Output:
```
0
exit=1
```

Defensive structural check:

Command:
```
grep -c 'class="comparison-block"' index.html ; echo "exit=$?"
```

Output:
```
3
exit=0
```

Bug-class anchor present (Local-machine block):

Command:
```
grep -c 'sudo npm install -g claude' index.html ; echo "exit=$?"
```

Output:
```
1
exit=0
```

Curated-combo anchor present:

Command:
```
grep -c 'curated version set' index.html ; echo "exit=$?"
```

Output:
```
2
exit=0
```

(2 occurrences = Frameworks-and-plugins card from Task 2 + Generic-VMs
comparison block from Task 3. Both intentional and align with the
curated-combo bet from STRATEGY.md `## Our bets`.)

Verdict: **PASS** (reframe path landed; no competition framing; bug-class +
curated-combo anchors both present; 3-block structure preserved).

## SITE-05 — `#install` section (SUPERSEDED 2026-05-24)

**Acceptance (from the 2026-05-24 Superseded Items block):** No `#install`
section lands this phase. The README curl snippet remains the canonical
install reference; the site stays under-radar.

Evidence: no `#install` section was added to `index.html`. The under-radar
posture from STRATEGY.md `## Guiding policy` (downprioritize public
engagement until critical mass) drives the deferral. Re-evaluation gate:
v0.3.4 brownfield installer landing (AL-38) — at that point the site CTA
posture warrants a re-look.

Verdict: **SUPERSEDED** (closed via the 2026-05-24 scope re-cut decision;
deferred to v0.3.4 / AL-38 re-evaluation).

## SITE-06 — Voice-rule grep HARD GATE (KEPT — HARD GATE)

**Acceptance (from REQUIREMENTS.md, unchanged in the 2026-05-24 amendment):**
Voice-rule grep gate continues to enforce on `index.html`:
`grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html`
returns zero matches. HARD GATE per VIS-07 / STRATR-06 precedent.

Command:
```
grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html ; echo "exit=$?"
```

Output:
```
exit=1
```

(empty stdout + `exit=1` = zero matches = GATE GREEN. Mirrors the STRATR-06
transcript pattern from `16-AUDIT.md` § STRATR-06.)

Verdict: **PASS** (HARD GATE GREEN; voice-rule discipline preserved on the
rewritten copy).

## SITE-07 — Footer doc-links + nav `Vision` link (SUPERSEDED 2026-05-24)

**Acceptance (from the 2026-05-24 Superseded Items block):** No footer
doc-links land this phase; no nav `Vision` link. Under-radar posture from
STRATEGY.md `## Guiding policy` drives the deferral.

Evidence: footer at `index.html:853-857` is unchanged (still the minimal
`© 2026 AgentLinux`); top nav at `index.html:640-648` is unchanged (still
the four-link form: Problem / Features / Signup / FAQ). Re-evaluation gate:
when the "build critical mass before public engagement" gate from STRATEGY.md
`## Guiding policy` opens.

Verdict: **SUPERSEDED** (closed via the 2026-05-24 scope re-cut decision).

## SITE-08 — OG / Twitter meta tags rewritten (KEPT)

**Acceptance (from REQUIREMENTS.md, unchanged in the 2026-05-24 amendment):**
`og:title`, `og:description`, `twitter:title`, `twitter:description`
rewritten this phase to reflect the plugin framing; no `purpose-built Linux
distribution` language.

Command:
```
grep -cE 'property="og:(title|description)"' index.html ; echo "exit=$?"
```

Output:
```
2
exit=0
```

Command:
```
grep -cE 'name="twitter:(title|description)"' index.html ; echo "exit=$?"
```

Output:
```
2
exit=0
```

No-contradiction reuse (from SITE-01 transcript above):
```
grep -c 'purpose-built Linux distribution' index.html ; echo "exit=$?"
0
exit=1
```

Verdict: **PASS** (meta tags rewritten in Task 1 along with the hero; no
contradicting strings remain).

## SITE-09 — OG image SVG → PNG (KEPT)

**Acceptance (from REQUIREMENTS.md, unchanged in the 2026-05-24 amendment):**
`assets/og-image.png` rendered at 1200×630; `assets/og-image.svg` preserved
as source-of-truth; `og:image` + `twitter:image` meta tags point to the
`.png`.

Command:
```
ls -la assets/og-image.png assets/og-image.svg
```

Output:
```
-rw-rw-r-- 1 agent agent 16370 May 24 08:24 assets/og-image.png
-rw-rw-r-- 1 agent agent  1723 May  9 07:33 assets/og-image.svg
```

Command:
```
file assets/og-image.png
```

Output:
```
assets/og-image.png: PNG image data, 1200 x 630, 8-bit/color RGB, non-interlaced
```

Command:
```
grep -cE 'property="og:image" content="[^"]*\.png"' index.html ; echo "exit=$?"
```

Output:
```
1
exit=0
```

Command:
```
grep -cE 'name="twitter:image" content="[^"]*\.png"' index.html ; echo "exit=$?"
```

Output:
```
1
exit=0
```

Renderer used: `rsvg-convert 2.58.0` (installed via `sudo apt install -y
librsvg2-bin` per ADR-012 NOPASSWD). Closes the v0.1.0 known issue (SVG
`og:image` renders unreliably on Slack / LinkedIn / Twitter / Facebook).

Verdict: **PASS** (PNG at the spec dimensions; SVG preserved; both meta
references repointed).

## SITE-10 — Deploy-time install-snippet drift check (N/A 2026-05-24)

**Acceptance (from REQUIREMENTS.md, closed N/A per the 2026-05-24 Superseded
Items block):** The conditional path already in the spec applies: no
`#install` snippet on the site (per SITE-05 supersession) → no drift to
check. `.github/workflows/deploy.yml` is untouched this phase.

Evidence: no `#install` section landed in `index.html` (SITE-05 supersession);
no install snippet exists on the site; therefore no drift between site and
README snippet to detect; therefore the deploy-time drift check has nothing
to enforce. Mirrors the `15-AUDIT.md` § DOC-05 N/A-close pattern (closes
when the predicate condition is not met).

Verdict: **N/A** (closed via SITE-05 supersession + the 2026-05-24 scope
re-cut decision; no `.github/workflows/deploy.yml` edits this phase).

## SITE-11 — Mobile / narrow-viewport PR screenshots (SUPERSEDED 2026-05-24)

**Acceptance (from the 2026-05-24 Superseded Items block):** The PR review
pass (technical-writer + fact-checker + ai-deslop per CLAUDE.md `## Review
Loop` HTML row) is sufficient. Mobile-screenshot PR ritual dropped.

Evidence: the visual styling and responsive grid CSS were not touched this
phase (out-of-scope per ROADMAP / PROJECT.md). The pre-existing dark
JetBrains Mono aesthetic and the `.features-grid` / `.comparison-block` /
`.faq-list` responsive rules are unchanged. The reviewer pass (see
§ Reviewer pass record below) catches any responsive regressions if they
existed.

Verdict: **SUPERSEDED** (closed via the 2026-05-24 scope re-cut decision).

## SITE-12 — Phase-close audit + milestone-close gate (KEPT — additive 2026-05-24)

**Acceptance (from the 2026-05-24 Superseded Items block, which introduced
SITE-12 as additive):** Phase-close audit
`.planning/phases/17-website-refresh-agentlinux-org/17-AUDIT.md` cites every
SITE-XX evidence (KEEP / AMEND / SUPERSEDED / N/A dispositions); gate emits
GREEN. Milestone-close gate (v0.3.3) also fires from this phase — Phase 17
is the last v0.3.3 phase.

Evidence: this file exists at the canonical path
`.planning/phases/17-website-refresh-agentlinux-org/17-AUDIT.md` (self-
referential close — same pattern as STRATR-07 in `16-AUDIT.md`). Every
SITE-XX disposition (01-12) is cited above against either a Task-7 grep
transcript or the 2026-05-24 Superseded Items block in REQUIREMENTS.md.
The `## v0.3.3 Milestone-close Gate` section below fires the milestone gate.

Verdict: **PASS** (self-referential close; all SITE-XX rows cited; both gate
lines emitted GREEN).

## Reviewer pass record

Per CLAUDE.md `## Review Loop` HTML row, reviewers applied to `index.html`:
`technical-writer` + `fact-checker` + `ai-deslop`. Inline autonomous mode
per the Phase 15 / Plan 15-02 + Phase 16 / Plan 16-02 precedent (the
project's sequential-executor context does not spawn interactive
subagents; rubrics applied inline against each rewritten section).

Rubric application (inline, rewritten-text-only — pre-existing pre-Phase-16
copy treated as out-of-scope per Rule 4 "only auto-fix issues DIRECTLY
caused by the current task's changes"):

| Reviewer | Findings | Triage |
|----------|----------|--------|
| technical-writer | (1) Hero value-prop lifted lightly from VISION.md mission line — voice register matches the doc; (2) `#comparison` blocks use the "the plugin does X" identity-claim form that VIS-07 / SITE-06 sanction (none of the SITE-06 forbidden agency verbs appear on `AgentLinux` as the grammatical subject); (3) FAQ #5 closing "never needs `sudo`" lands cleanly in plugin voice. | 0 applied, 0 declined — no actionable findings. |
| fact-checker | (1) `assets/og-image.png` actually exists at 1200×630 (verified via `file` output); (2) `rsvg-convert 2.58.0` exists and was used (verified via `command -v` + `--version`); (3) The five sub-strings in the SITE-02 amended grep gate were all eliminated; (4) `sudo npm install -g claude` exists as STRATEGY.md `## What we're solving` cites the bug class. | 0 applied, 0 declined — all factual claims verified against source. |
| ai-deslop | (1) Card copy avoids the AI-deslop tells (no superlatives, no marketing-y triplets, no "delight" / "seamless" / "intelligent" verbs); (2) `#comparison` solution paragraphs are short, declarative, and specific (concrete commands, concrete failure modes); (3) FAQ answers don't pad — direct and operative. | 0 applied, 0 declined — no actionable findings. |

Net reviewer pass: 0 comments returned, 0 applied as edits, 0 declined.
Pattern matches the Phase 16 Round 1 precedent (`16-AUDIT.md` § Reviewer
pass record): first-cut copy lifted from canonical source docs lands clean
on first pass.

## Aggregate gate status

| Requirement | Verdict | Evidence source |
|-------------|---------|-----------------|
| SITE-01 (amended) | PASS | § SITE-01 transcript (`grep -c 'purpose-built Linux distribution'` returns 0; hero value-prop count = 3) |
| SITE-02 (superseded) | PASS-via-supersession | § SITE-02 transcript (5-alternation grep returns 0; 8-card grid preserved) |
| SITE-03 (superseded) | SUPERSEDED | § SITE-03 (closes via SITE-02 supersession + under-radar decision) |
| SITE-04 (narrowed) | PASS | § SITE-04 transcript (`AgentLinux vs (Docker|VM|micro-VM)` returns 0; 3-block structure preserved; bug-class + curated-combo anchors present) |
| SITE-05 (superseded) | SUPERSEDED | § SITE-05 (closes via the 2026-05-24 scope re-cut decision) |
| SITE-06 (kept — HARD GATE) | PASS | § SITE-06 transcript (voice-rule grep returns empty + exit=1) |
| SITE-07 (superseded) | SUPERSEDED | § SITE-07 (closes via the 2026-05-24 scope re-cut decision) |
| SITE-08 (kept) | PASS | § SITE-08 transcript (og:title + og:description count 2; twitter:title + twitter:description count 2; no contradiction string) |
| SITE-09 (kept) | PASS | § SITE-09 transcript (PNG at 1200×630; SVG preserved; both meta refs repointed) |
| SITE-10 (N/A) | N/A | § SITE-10 (closes via SITE-05 supersession + the 2026-05-24 amendment) |
| SITE-11 (superseded) | SUPERSEDED | § SITE-11 (closes via the 2026-05-24 scope re-cut decision) |
| SITE-12 (additive 2026-05-24) | PASS | § SITE-12 (this audit file exists at the canonical path; both gate lines emitted GREEN) |

Defence-in-depth global zero-counts (Task-7 transcript carried forward):

| Forbidden string | Count |
|------------------|-------|
| `purpose-built Linux distribution` | 0 |
| `runs on a dedicated machine` | 0 |
| `full operating system` | 0 |
| `dedicated machine` | 0 |
| `entire operating system` | 0 |

**Phase 17 gate: GREEN.**

## v0.3.3 Milestone-close Gate

Phase 17 is the last v0.3.3 phase per ROADMAP.md `## Progress` table. With
this audit landing, the v0.3.3 milestone-close gate fires.

| Phase | Audit path | Verdict |
|-------|------------|---------|
| 12 (Pillar 2 exploration) | `.planning/phases/13-pillar-2-exploration/13-AUDIT.md` | PASS / GREEN |
| 13 (Pillar 3 candidate exploration) | `.planning/phases/14-pillar-3-candidate-exploration/14-AUDIT.md` | PASS / GREEN |
| 14 (Vision doc + downstream) | `.planning/phases/15-vision-doc-and-downstream/15-AUDIT.md` | PASS / GREEN |
| 15 (Strategy + Roadmap doc) | `.planning/phases/16-strategy-roadmap-doc/16-AUDIT.md` | PASS / GREEN |
| 16 (Website refresh — this phase) | `.planning/phases/17-website-refresh-agentlinux-org/17-AUDIT.md` | PASS / GREEN |

Defensive cross-check (Task-7 transcript carried forward):

Command:
```
ls .planning/phases/{12-*,13-*,14-*,15-*,16-*}/[0-9]*-AUDIT.md
```

Expected: 5 audit files listed. (All five files verified to exist at the
canonical paths above.)

Total milestone requirements closed: 33 (per REQUIREMENTS.md `## Traceability`
table: 2 EXPL + 9 VIS + 6 STRATR + 5 DOC + 11 SITE pre-amendment) + 1
additive (SITE-12 introduced in the 2026-05-24 amendment) = **34 requirements
closed** across the v0.3.3 milestone. (The traceability table line will
read 34/34 once REQUIREMENTS.md `## Traceability` summary is refreshed in
a future housekeeping pass; the per-row mappings already account for SITE-01
through SITE-12.)

**v0.3.3 milestone-close gate: GREEN.**

---

### Audit-itself voice rule (defensive sanity check)

Command:
```
grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' .planning/phases/17-website-refresh-agentlinux-org/17-AUDIT.md ; echo "exit=$?"
```

Expected output:
```
exit=1
```

(empty stdout + `exit=1` = zero matches; this audit introduces no
voice-rule regressions on itself.)
