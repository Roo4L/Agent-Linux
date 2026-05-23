# Phase 14: Vision Doc + ADR-015 + Downstream Surface Updates - Context

**Gathered:** 2026-05-16
**Status:** Ready for planning
**Mode:** Smart-discuss with major mid-flow reframe (vision-only)

<domain>
## Phase Boundary

Phase 14 lands the canonical product-vision document (`docs/VISION.md`),
records the framing decision in ADR-015, and propagates the new framing to
the downstream documentation surfaces (README, CONTRIBUTING, PROJECT.md,
STABILITY-MODEL.md) — all in the same milestone window so a future visitor
reading any of those surfaces sees the same coherent two-pillar story
without contradictions.

The phase is *framing*, not new product capability. The pillar contents seed
downstream roadmap themes (v0.6+) but do not ship any of them in v0.3.3.

**Major reframe locked 2026-05-16:** The original Phase 14 (per ROADMAP at
2026-05-09) bundled vision + strategy + roadmap + framework trade-offs into
a single `docs/STRATEGY.md` against the Sourcegraph template spine. The user
re-scoped during smart-discuss: this phase produces a vision-only document
named `docs/VISION.md`. The strategy/roadmap content moves to a new Phase 15
(`docs/STRATEGY.md`). Website refresh renumbers from Phase 15 → Phase 16.

</domain>

<decisions>
## Implementation Decisions

### Document scope — vision-only (locked 2026-05-16)

The doc covers:
- **Mission** — one paragraph, value-prop voice (not narrow problem-list voice).
- **Positioning** — one sentence in Geoffrey Moore form.
- **The two pillars** — as *optimization values* (e.g. `Time-to-productive`,
  `Stability`), not historical engineering vocabulary. Each pillar is one
  paragraph of identity-claim prose — no `#### Today` / `#### Direction`
  subsections inside pillars (status-report voice is wrong for the vision
  doc).
- **Guiding principles** — 4–6 vision-level principles, each a `### {Name}` +
  short paragraph. Identity claims, NOT execution rules. Specifically:
  - IN: "We are infrastructure, not an agent product"; "We meet users on
    their distribution"; "We curate, we do not aggregate"; "Value arrives
    automatically".
  - OUT: "Behavior tests are the spec" (ADR-002); "TST-07 phase-close
    discipline"; "Voice rule as authoring rule" — these are execution
    principles and live in Phase 15's STRATEGY.md `## Execution principles`.
- **What we're explicitly not** — ≥4 vision-level non-goals as bulleted
  items, each with one-line rationale. Identity-level only:
  "Not an agent product"; "Not a sandbox runtime"; "Not an observability
  vendor"; "Not a Linux-distribution-style upstream maintainer"; "Not an
  agent benchmark publisher".

The doc does NOT cover (these moved to Phase 15's STRATEGY.md):
- "Where we are now" (current state / status report).
- "Strategy and plans" / "What we're working on next" (roadmap content).
- "Trade-offs / rejected alternatives" — explicitly dropped per user
  direction ("framework-shape trade-offs are of no concern to the document
  readers").
- "Appendix A — Vision Board" — explicitly dropped per user direction
  (recognized as ceremony; the doc is short enough to read end-to-end).
- "Appendix B — Roadmap themes for v0.6+".
- "Today" / "Direction" splits inside pillars.
- Pillar priority tags (`foundational` / `next-milestone` / `opportunistic`).

### Doc location — `docs/VISION.md`

Sibling to `docs/STABILITY-MODEL.md` and `docs/HARNESS.md`. Single Markdown
file — not a `docs/vision/` tree, not embedded in README.

### Doc size — target 4–5 KB, ceiling 6 KB (VIS-01)

The committed draft `docs/VISION.md` is at 4,500 bytes (post-reviewer
polish). Under ceiling.

### Pillar names — locked 2026-05-16

- **Pillar 1 — Time-to-productive.** Optimization target: from `curl | bash`
  to first useful agent run on a fresh box, frictionlessly. The doc names
  this pillar `### Pillar 1 — Time-to-productive`.
- **Pillar 2 — Stability.** Optimization target: the curated toolchain stays
  compatible across upstream churn. The doc names this pillar
  `### Pillar 2 — Stability`.

Phase 13 verdict (b) means there is no Pillar 3. The vision doc ships
exactly 2 pillars.

### Pillar voice — stances/tenets style, but as *values we optimize for*

The user rejected three candidate voices in smart-discuss:
- **Identity statements** ("AgentLinux is the place where ...") — too
  declarative; locks specific claims that might drift.
- **Stances "X over Y"** ("Separation over convenience") — picks a
  trade-off form; user wanted just the X (the values), not the trade-offs.
- **Promises to the user** ("Your agent stops fighting your machine") —
  too marketing-flavored.

The accepted voice is **stances as values we optimize for**: pillar names
are value words (Time-to-productive, Stability); pillar bodies describe
what AgentLinux does to deliver that value, in declarative-but-not-
promise-flavored prose.

### Mission voice — value-prop, not problem-list (locked 2026-05-16)

The user pushed back on a draft that listed specific v0.3.0 problems
(EACCES, self-update breakage, dependency drift). The locked Mission is
broader: "AgentLinux gives coding agents a stable and effective place to
run on Linux, without asking the user to set it up or operate it themselves."
Names the value proposition (stable + effective place for agents) and the
differentiator (user is not the operator); explicitly avoids narrow
problem examples that would "tie our hands."

### Voice rule — VIS-07 hard gate

`grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/VISION.md`
returns 0 matches. Verified post-polish on the committed draft. The grep
command + empty output gets committed verbatim to `14-AUDIT.md`.

### ADR-015 — agenda redefinition (VIS-09)

`docs/decisions/015-agenda-redefinition.md` lands in the same Phase 14
commit window. Contains:
- `Status: Accepted` (2026-05-16).
- `Context` — AL-7 framing question + why the original single-pillar
  framing was getting in the way + why the original 3-pillar bundle was
  getting in the way + why the original combined-vision+strategy
  document was getting in the way (the 2026-05-16 reframe).
- `Decision` — Two pillars (locked by Phase 13 verdict (b)); vision-only
  document separated from strategy/roadmap (locked by user reframe
  2026-05-16).
- `Considered alternatives` (≥3):
  1. Stay single-pillar (rejected — AL-7 explicitly called for broadening).
  2. Ship vision + strategy + roadmap + trade-offs in one `docs/STRATEGY.md`
     per the original Phase 14 plan (rejected — user reframe 2026-05-16;
     vision and strategy serve different audiences and benefit from doc-
     level separation).
  3. Pivot security-first to a Pillar 3 (rejected — Phase 13 verdict (b);
     no honest already-shipped table-stakes for security as a pillar; would
     force aspirational drift per Pitfall #6).
- `Consequences` — Phase 15 (strategy/roadmap doc) inserted; Phase 15 →
  Phase 16 renumber of website-refresh; DOC-05 closes N/A; Pillar 2
  carries the supply-chain monitoring sub-concern from Phase 13 verdict (b);
  ADR-012 NOPASSWD tension recorded in Pillar 2 body as a known limitation
  rather than via an ADR-012 file edit.
- Back-link to AL-7 and to `docs/VISION.md`.

### DOC-01..DOC-04 — back-pointers to VISION.md

Each downstream surface gains a back-pointer to `docs/VISION.md`:
- **README.md** — `## About` section gains one sentence naming the two
  pillars + linking to VISION.md; `## Links` section gains a `Vision:`
  row.
- **CONTRIBUTING.md** — "Why this project exists" paragraph (short) links
  to VISION.md; names which pillars accept contributions today (Pillar 1
  yes; Pillar 2 early-stage).
- **.planning/PROJECT.md** — Core Value + Current Milestone sections
  cross-reference VISION.md. Three-pillar text updates to two-pillar.
- **docs/STABILITY-MODEL.md** — `Related` section gains a back-link to
  VISION.md Pillar 2.

### DOC-05 — closed N/A 2026-05-16

Phase 13 verdict (b) means no Pillar 3 → no ADR-012 forward-reference
edit. The audit records DOC-05 as N/A with the explicit one-line rationale
and a cite to EXPL-02's `## Verdict` line.

### Reviewer pass — already run (2026-05-16)

Vision doc committed at `f95a4ee` (2026-05-16) after a parallel
technical-writer + fact-checker reviewer pass. Findings:
- fact-checker: all claims verified against Phase 12 + Phase 13 locked
  verdicts and v0.3.0 reality. Zero CRITICAL/MEDIUM/LOW findings.
- technical-writer: zero CRITICAL findings; 4 MEDIUM + 4 LOW polish
  suggestions. Three small polish edits applied (drop redundant "single",
  fix British→American spelling on "behavior", frame the sandbox-primitives
  list for the product-leadership audience). User's authorial voice on the
  rest preserved.

### Claude's Discretion

- Section ordering inside ADR-015 considered-alternatives (which of the
  three goes first) — Claude picks.
- Exact prose for the four DOC propagation back-pointers.
- Whether to add a one-line `### Reviewer notes` block at the bottom of
  `14-AUDIT.md` summarizing the reviewer pass (not required by VIS-* but
  helpful audit trail).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (no code changes in Phase 14 — doc-only)

- `docs/VISION.md` — already committed as draft `f95a4ee` (2026-05-16). Pre-
  audit content; user-approved; reviewer-polished. The plan executor
  validates VIS-01..VIS-08 against this file (no re-authoring needed).
- `docs/exploration/PILLAR-2-NOTES.md` — Phase 12 verdict, lifted into VISION.md
  Pillar 2 substance.
- `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` — Phase 13 verdict (b),
  lifted into the supply-chain sub-concern of VISION.md Pillar 2 and into
  the non-goals list.
- `docs/decisions/000-template.md` — ADR template, used to author ADR-015.
- `docs/decisions/014-secret-remediation-noop.md` — most recent ADR; reference
  for current ADR voice + frontmatter style.
- `docs/STABILITY-MODEL.md` (5.4 KB) — DOC-04 back-pointer target.
- `.planning/PROJECT.md` — DOC-03 back-pointer target; also needs the
  three-pillar text updated to two-pillar.
- `README.md` — DOC-01 back-pointer target.
- `CONTRIBUTING.md` — DOC-02 back-pointer target.

### Established Patterns

- Voice rule: every claim about an unshipped behaviour MUST appear in a
  sentence whose grammatical subject is "we" / "our roadmap" / an explicit
  milestone identifier — never "AgentLinux + present-tense verb." VIS-07
  hard gate enforces.
- Phase-close audit convention: `<phase-NN>-AUDIT.md` cites file path + line
  range / commit hash / grep transcript per requirement; gate emits GREEN
  before phase closes.
- ADR numbering: ADR-015 is the next slot.
- Reviewer pass on docs: technical-writer + fact-checker before commit.
  Already run on `docs/VISION.md` 2026-05-16.

### Integration Points

- **Phase 15 (Strategy + Roadmap Doc):** authors `docs/STRATEGY.md` with
  the execution principles + themes-for-v0.6+ + current-focus content that
  was cut from Phase 14. Phase 15 starts after Phase 14 closes.
- **Phase 16 (Website Refresh):** consumes both VISION.md (for pillar names
  + non-goals) and STRATEGY.md (for "Where we are now" framing in the
  `#comparison` block reframe).
- **AL-14 (Jira anchor Task):** Phase 14 status updates land as comments on
  AL-14 or as a new Subtask under AL-14 alongside AL-40 (Phase 12) and AL-42
  (Phase 13).

</code_context>

<specifics>
## Specific Ideas

- **The pillar names matter and are user-validated.** Don't rename
  Time-to-productive or Stability without going back to the user.
- **The Mission paragraph is broad on purpose.** Don't reintroduce the
  narrow problem-list (EACCES / self-update / dependency drift) during
  ADR-015 authoring or DOC-01 README updates — the user explicitly
  pushed back on that framing during smart-discuss.
- **DOC-05 N/A close cites EXPL-02's `## Verdict` line.** Audit must
  include a copy of the verdict line so a future reader can verify the
  N/A close without re-reading Phase 13.
- **The vision/strategy split is the load-bearing ADR-015 decision.**
  ADR-015's Considered alternatives must include "ship vision + strategy
  + roadmap in one doc" as a rejected alternative with the 2026-05-16
  rationale, so the split is honestly documented.
- **The committed vision doc is the spec.** VIS-01..VIS-08 are verified
  against `docs/VISION.md` at commit `f95a4ee` (or its descendants). If
  the planner finds a gap, the plan can patch VISION.md as part of
  closing the gap — but the user-validated structure stays.

</specifics>

<deferred>
## Deferred Ideas

- **Strategy/roadmap content** (execution principles, themes for v0.6+,
  near-term focus, current state) — moved to Phase 15 (STRATEGY.md).
- **Trade-offs / framework-spine rejected alternatives** (Lean Canvas, BMC,
  OKRs, PR-FAQ) — dropped per user direction. Not authored anywhere in
  v0.3.3; the Sourcegraph template choice is internal authoring trivia.
- **Vision Board appendix** — dropped per user direction.
- **Pillar priority tags inside VISION.md** — out of scope; the strategy
  doc may carry sequencing rationale in its themes section instead.
- **`Today` / `Direction` splits inside pillars** — out of scope for
  VISION.md; the equivalent content lives in STRATEGY.md's "Where we are
  now" + "What we're working on next" sections.
- **Cadence binding for `/gsd-complete-milestone`** — deferred to a v0.6+
  process-change milestone.
- **Bidirectional ADR back-references** (ADR-011 → VISION.md, ADR-012 →
  VISION.md) — deferred unless the VIS-08 author finds them load-bearing.

</deferred>
