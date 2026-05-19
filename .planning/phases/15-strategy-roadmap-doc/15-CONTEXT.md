# Phase 15: Strategy + Roadmap Doc - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning
**Mode:** Interactive discuss with mid-flow research-driven reframe

<domain>
## Phase Boundary

Phase 15 lands the canonical product strategy/roadmap document
(`docs/STRATEGY.md`) — the "how we get there" companion to `docs/VISION.md`'s
"what we want to be." It covers the strategic *choices* (diagnosis + bets), the
honest current state, near-term focus + v0.6+ themes, and the execution-level
rules cut from VISION.md as too execution-flavored for a vision doc.

**Major reframe locked 2026-05-19 (mid-discuss research finding):** The
ROADMAP-as-of-2026-05-16 STRATR-02 spec mandated a 4-section spine (`Where we
are now` / `What we're working on next` / `Themes for v0.6+` / `Execution
principles`). Strategy-doc-design research surfaced that this spine is "mostly
roadmap with execution principles bolted on" — missing the *diagnosis* +
*guiding-policy* moves that distinguish strategy from roadmap per Rumelt, Cagan,
and Pichler. User accepted the research-recommended Rumelt-style 5-section
spine; STRATR-02 amends in the same Phase 15 commit window (precedent: Phase 14
STRAT-* → VIS-* + STRATR-* reframe). The `## What's next` section fuses
near-term focus with v0.6+ themes as subsections.

</domain>

<decisions>
## Implementation Decisions

### Doc spine — 5 H2 sections (locked 2026-05-19)

`docs/STRATEGY.md` ships with this section list, in this order:

1. `## What we're solving` — the *diagnosis*. References VISION.md upstream
   for the broad value-prop, then names the specific bug-class AgentLinux
   exists to eliminate (agent-user permission failures, EACCES on
   `npm install -g`, recursive-shim self-update breakage, dependency drift
   from un-curated `npm install -g` paths). 2-3 short paragraphs.
2. `## Our bets` — the *guiding policy*. 2-3 load-bearing strategic choices
   with one line of why each. Candidates: "installable plugin over custom
   distro" (v0.2.0 → v0.3.0 pivot); "behaviors-as-spec over implementation
   pinning" (ADR-002); "curated combos over user-assembled stacks"
   (ADR-011); "infrastructure not agent product" (lifted from VISION.md
   principle, but in strategy voice — *because* of this bet, the catalog
   stays narrow and we do not race to add observability tools).
3. `## Where we are now` — honest current state, ≤ 1 paragraph. What's
   shipped (v0.3.0 plugin on Ubuntu 22/24/26 with AGT-02 green; v0.4.0 OSS
   flip 2026-05-09; v0.3.3 vision/strategy framing in flight). What is the
   load-bearing current goal: *ship the first usable AgentLinux release for
   the maintainer as canonical user* (= v0.3.4 Aware Installation per AL-38
   + AlmaLinux support). Delivered-fact voice for shipped items; "we / our
   roadmap" voice for the current-goal sentence.
4. `## What's next` — fused near-term + v0.6+ section (locked 2026-05-19).
   Two `###` subsections:
   - `### Near-term` — current-milestone tail + the next 1-2 milestones in
     order: finish v0.3.3 (Phase 16 website refresh) → v0.3.4 brownfield
     installer (AL-38) → AlmaLinux support → OSS funding application
     (parallel/meta).
   - `### Themes for v0.6+` — 4 themes (locked count; STRATR-03 ceiling).
     Each theme is a `### {Theme}` heading block with body + a
     `**Sequencing rationale:** ...` line. Themes:
     1. Security Hardening (Phase 13 opportunistic theme — capability-scoped
        sudoers replacing ADR-012 NOPASSWD ALL, cosign-signed catalog
        releases, npm provenance verification, bubblewrap-based per-recipe
        sandbox profile, iptables egress allowlist).
     2. Preset / profile framework + compat-guarded update flow (Phase 12
        differentiators — `bare` / `must-haves` / `optimum` presets,
        `web-development`-style profiles, hold-and-wait-on-upstream-breakage
        policy; covers user item 3, the catalog update pipeline).
     3. Broader agentic-dev catalog (toward critical mass — Cursor CLI,
        OpenAI Codex CLI, aider, Continue, Goose, etc.). Gates theme #4.
     4. Public engagement (mailing-list announce + feedback loop +
        community-platform basics). Sequencing rationale states explicitly:
        gated on theme #3 reaching critical mass — the user's reasoning is
        that the current 3-agent release is too tiny to engage subscribers
        meaningfully.
5. `## Execution principles` — bulleted list with `**Name** — ` prefix +
   one-line gloss each + cite of source ADR / test ID / doc. 5 mandated by
   STRATR-04, room for 1-2 more. Mandated: voice rule (delivered-fact vs
   forward-looking), behavior tests are the spec (ADR-002), evidence-cite
   discipline (TST-07-style phase-close audits), curated-combo testing
   (TST-08 4-gate release pipeline), no `sudo npm install -g` anywhere
   (ADR-004). Optional additions left to Claude's discretion: reviewer
   feedback loop (HARNESS.md §4), AI-agent collaboration pattern.

### Section heading names (locked 2026-05-19)

Final names: `## What we're solving`, `## Our bets`, `## Where we are now`,
`## What's next`, `## Execution principles`. The first two depart from
Rumelt's `Diagnosis` / `Guiding policy` vocabulary in favor of plainer voice
per user preference; the strategy-doc *move* (explicit diagnosis + explicit
choices) stays intact.

### "Where we are now" content posture (locked 2026-05-19)

Not a product-capability status report. Opens with the load-bearing current
goal (first usable release for the maintainer), then names what's just landed
(v0.3.0 plugin + v0.4.0 OSS flip + v0.3.3 framing). Calendar-flavored only on
the shipped-items side; goal-flavored on the forward-looking side. User
explicit on this: "what I would like to focus on is saying what is our current
goal/milestone that we are trying to achieve right now ... That's what matters
now."

### "First usable AgentLinux release for myself" definition (locked 2026-05-19)

= v0.3.4 Aware Installation Process (per Jira [AL-38](https://copiedwonder.atlassian.net/browse/AL-38)
— brownfield-aware installer that detects existing agent user / Node.js /
catalog packages, reuses what's compatible, remediates what's broken, with a
consent gate for mutations) + AlmaLinux support (separate distro-expansion
increment, lands after v0.3.4). AL-38's planning state is being handled in a
separate worktree — STRATEGY.md references AL-38 by Jira key and the
brownfield scenario without claiming current in-repo authoritative plan state.

### Forward-item sequencing (locked 2026-05-19)

User dumped 6 forward ideas mid-discuss; sequenced into near-term + themes:

- **Near-term:** v0.3.3 tail (Phase 16 site refresh) → v0.3.4 brownfield
  (AL-38) → AlmaLinux → OSS funding (parallel/meta).
- **v0.6+ themes:** broader catalog → public engagement (gated on critical
  mass). Plus the STRATR-03-mandated themes (Security Hardening + Preset/
  Profile/Compat-guarded).
- User explicit on deferring public announce: "current release is so tiny
  that it will basically get no one interested. We need to build critical
  mass of projects before coming up with any public announcement."

### Security Hardening theme clarification (locked 2026-05-19)

User raised concern that we "ditched security hardening pillar" in VISION.md.
Resolved: Phase 13 verdict (b) declined a separate *Pillar 3* (no honest
already-shipped table-stakes for security as a pillar identity claim), but
explicitly *kept* Security Hardening as a v0.6+ `opportunistic` *theme*
(declined defenses eligible to mature into milestones). REQUIREMENTS.md
STRATR-03 mandates it as a theme; the distinction is pillar = identity
commitment we ship now vs theme = forward-looking direction our roadmap might
commit to later. Theme stays.

### Doc location, size, voice rule (locked upstream by REQUIREMENTS.md)

- Location: `docs/STRATEGY.md` sibling to VISION.md / HARNESS.md /
  STABILITY-MODEL.md (STRATR-01).
- Size ≤ 8 KB on first cut (STRATR-01). With the new 5-section spine plus
  Diagnosis + Bets content, target 6-7 KB.
- First non-blank line after H1 = `> Last reviewed: 2026-05-19` blockquote
  (STRATR-05).
- Voice-rule grep gate (STRATR-06) — same regex as VIS-07 on VISION.md.
  Hard gate; command + empty output committed verbatim to `15-AUDIT.md`.

### STRATR-02 amendment (Phase 15 commit window)

REQUIREMENTS.md STRATR-02 amends to mandate the new 5-section spine. New grep
gate: `grep -nE '^## (What we'\''re solving|Our bets|Where we are now|What'\''s next|Execution principles)' docs/STRATEGY.md`
returns ≥ 5 matches. The original STRATR-02 grep pattern (`Where we are now|
What we'\''re working on next|Themes for|Execution principles` ≥ 4) replaced.
A small `## Superseded items` note appended to REQUIREMENTS.md per the
2026-05-16 Phase-14 reframe precedent.

### Folded todos

None — no todo matches surfaced via `todo.match-phase` and the user did not
introduce any during discuss.

### Claude's Discretion

- **Cross-reference / ADR-citation density.** Default to lighter-touch: only
  the load-bearing ADRs (ADR-002, ADR-004, ADR-011, ADR-015) and the two
  exploration verdict files get inline links inside section bodies; a
  `## Related` block at the bottom of the doc carries the wider reference
  index (per STABILITY-MODEL.md precedent). User indicated they don't care
  about format details; the research recommendation favored reference-light
  Sourcegraph/GitLab handbook flavor.
- **Execution-principles list format.** Bulleted with `**Name** — ` prefix
  + one-line gloss + parenthetical citation. User explicit: "I don't care
  about such details."
- Exact prose for each section body (subject to the voice-rule grep gate +
  the section spine + the substance locked above).
- Exact ordering of the 4 themes inside `### Themes for v0.6+` (the
  user-provided sequencing rationale must connect themes 3 and 4 explicitly;
  the order of themes 1 and 2 — Security Hardening vs Preset/Profile —
  is Claude's call).
- Whether to include an optional 6th or 7th execution principle (mandated
  floor is 5; ceiling is 7). Reviewer-loop discipline (HARNESS.md §4) and
  AI-agent collaboration are candidates if room permits under the 8 KB
  ceiling.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 14 upstream (consumed by Phase 15)

- `docs/VISION.md` — the canonical "what we want to be" document. STRATEGY.md
  references this as upstream in `## What we're solving`; cross-link in
  `## Related`. Voice rule (VIS-07) carries verbatim into STRATR-06.
- `docs/decisions/015-agenda-redefinition.md` — ADR-015, records the framing
  decision (two pillars + vision/strategy split). STRATEGY.md cross-links in
  `## Related`.
- `.planning/phases/14-vision-doc-and-downstream/14-CONTEXT.md` — Phase 14
  locked decisions; reference for voice-rule discipline + pillar names.
- `.planning/phases/14-vision-doc-and-downstream/14-AUDIT.md` — Phase 14
  audit; reference for the STRATR-06 grep-gate evidence pattern.

### Substance sources for the 4 themes

- `docs/exploration/PILLAR-2-NOTES.md` — Phase 12 verdict; source of the
  Preset/Profile/Compat-guarded theme content (D-1/D-2/D-3 differentiators).
- `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` — Phase 13 verdict (b);
  source of the Security Hardening theme content (declined defenses eligible
  for v0.6+).
- Jira [AL-38](https://copiedwonder.atlassian.net/browse/AL-38) — v0.3.4
  Aware Installation Process anchor; defines "first usable release" for
  the Near-term subsection.
- Jira [AL-7](https://copiedwonder.atlassian.net/browse/AL-7) — v0.3.3
  Agenda Redefinition epic; the milestone trigger.

### Execution principles sources (cited inline in STRATEGY.md)

- `docs/decisions/002-behavior-tests-are-spec.md` — ADR-002. Source for the
  "behavior tests are the spec" principle.
- `docs/decisions/004-per-user-npm-prefix.md` — ADR-004. Source for the
  "no `sudo npm install -g` anywhere" principle.
- `docs/decisions/011-stability-first-version-pinning.md` — ADR-011. Source
  for the "curated combos over user-assembled stacks" bet AND the
  "curated-combo testing" execution principle.
- `docs/HARNESS.md` §4 — reviewer feedback loop (optional 6th principle).
- `.planning/REQUIREMENTS.md` §"v0.3.3 Requirements" — STRATR-01..06 spec
  text; gates auditable against AUDIT.md.

### Spec / requirements / state

- `.planning/REQUIREMENTS.md` — STRATR-01..STRATR-06 + STRATR-02 amendment
  landing in this phase. Read before planning.
- `.planning/PROJECT.md` — milestone framing; Out-of-Scope list to honor.
- `.planning/ROADMAP.md` — Phase 15 entry; the canonical phase boundary.

### Sibling docs (cross-reference index targets)

- `docs/STABILITY-MODEL.md` — sibling user-facing doc; cross-link in
  `## Related` since STRATEGY.md's "curated combos" bet implements what
  STABILITY-MODEL.md mechanizes.
- `docs/HARNESS.md` — sibling internal doc; source for review-loop +
  reviewer-applied-by-file-type discipline; cross-link in `## Related`.

</canonical_refs>

<code_context>
## Existing Code Insights

No code changes in Phase 15 — doc-only.

### Reusable assets

- `docs/VISION.md` (4.4 KB) — voice + structure reference. The committed
  Phase 14 draft sets the canonical pattern: short H2 sections, identity-prose
  paragraphs, vision-level non-goals. STRATEGY.md inherits the same voice
  rule and `> Last reviewed:` blockquote convention but uses strategy-doc-
  flavored content (diagnosis + bets + near-term).
- `docs/STABILITY-MODEL.md` (5.6 KB) — sibling-doc shape reference. Uses a
  `## Related` cross-reference block at the bottom (pattern to copy);
  mid-doc has a worked example block (good model for `## Where we are now`
  if needed but probably not used here).
- `docs/decisions/015-agenda-redefinition.md` — recently authored; voice +
  citation pattern reference for any inline ADR links inside STRATEGY.md.
- `docs/exploration/PILLAR-2-NOTES.md`, `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`
  — Decision-summary sections are the substance source for themes #1 and
  #2; lifted (paraphrased to fit doc voice) into STRATEGY.md theme bodies.

### Established patterns

- Voice rule: `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md`
  returns zero matches. Same regex as VIS-07. Every claim about an unshipped
  behaviour MUST use "we" / "our roadmap" / an explicit milestone identifier
  as the grammatical subject.
- Phase-close audit (`15-AUDIT.md`) cites file path + line range / commit
  hash / grep transcript per STRATR-XX requirement. Same pattern as
  `14-AUDIT.md` (Plan 14-02 precedent).
- Reviewer pass on docs: technical-writer + fact-checker before commit.
  Same convention used on `docs/VISION.md` (committed `f95a4ee` 2026-05-16
  after parallel reviewer pass).

### Integration points

- **Phase 16 (Website Refresh)** — consumes `docs/STRATEGY.md` for the
  `#comparison` block reframe (SITE-04) and footer link (SITE-07). Phase
  15 must close before Phase 16 starts.
- **REQUIREMENTS.md STRATR-02 amendment** — same commit window as STRATEGY.md
  drafting. Mirrors Phase 14's mid-milestone REQUIREMENTS.md reframe
  (STRAT-* superseded by VIS-* + STRATR-* on 2026-05-16).
- **`<phase>-AUDIT.md` convention** — Phase 15 emits
  `.planning/phases/15-strategy-roadmap-doc/15-AUDIT.md` with STRATR-01..06
  evidence + GREEN gate.

</code_context>

<specifics>
## Specific Ideas

- **The 5-section spine is a research-driven reframe.** Strategy-doc design
  research (Rumelt, Cagan, Pichler; GitLab/Sourcegraph handbook patterns;
  Stripe-memo style) identified the original STRATR-02 4-section spine as
  "roadmap with execution principles bolted on" — missing the diagnosis +
  guiding-policy moves that distinguish strategy from roadmap. The new spine
  IS the load-bearing change.
- **`## What we're solving` does NOT duplicate VISION.md.** VISION.md was
  *deliberately* purged of diagnosis content during Phase 14 (user pushback
  2026-05-16). The narrow problem-list (EACCES, recursive shim, self-update
  breakage) was cut from VISION.md Mission to keep it broad-value-prop. It
  belongs in STRATEGY.md where it grounds the bets that follow.
- **"First usable for myself" = v0.3.4 brownfield (AL-38) + AlmaLinux.**
  Not v0.3.0 (already shipped, but the user's brownfield work-env scenario
  + non-Ubuntu distro is unhandled). The strategy doc names this goal
  explicitly in `## Where we are now`.
- **Public engagement is gated on catalog critical mass.** Mail-list
  announce intentionally NOT in near-term despite being a "next" item. User
  reasoning preserved verbatim in DISCUSSION-LOG.md.
- **Themes use `### {Theme}` heading + `**Sequencing rationale:**` bold-label
  line.** Not nested `#### Sequencing rationale` sub-headers — flatter
  hierarchy, more readable. Each theme = one heading block.
- **`## Where we are now` is goal-flavored, not status-report-flavored.**
  User explicit: emphasize current-goal-milestone (first usable release),
  not delivered-capability summary. Three-paragraph max.
- **Execution principles cite their source.** Each bullet ends with a
  parenthetical (e.g. `(ADR-004)` or `(TST-08, HARNESS.md §3)`) so the
  evidence trail is one click away.

</specifics>

<deferred>
## Deferred Ideas

- **`/gsd-complete-milestone` cadence binding** — update the
  `> Last reviewed:` header automatically on every milestone close.
  Deferred to v0.3.3 retrospective per ADR-015 Consequences. Pitfall
  #12 / #23 mitigation.
- **Strategy-doc periodic-review cadence** — separate from the cadence
  binding above; how often the doc gets re-walked end-to-end (every milestone?
  every quarter? on substance changes?). Not addressed in Phase 15.
- **Public-facing "How we work with AI agents" addendum** — could be its
  own doc or could fold into Execution principles. Out of scope for Phase
  15; revisit if v0.6+ public engagement theme matures into a milestone.
- **External-link-rot guard** — Jira links (AL-7, AL-38) and Anthropic CDN
  references in STRATEGY.md could rot. Not addressed in Phase 15; the doc
  is mutable so rot can be fixed in-place.
- **Detailed roadmap document separate from STRATEGY.md** — research surfaced
  that some shops split strategy + roadmap into two files. Not adopted; one
  fused doc fits the small-team / one-maintainer scale per the research
  trade-off finding.

### Reviewed todos (not folded)

None — no todos surfaced via `todo.match-phase`.

</deferred>

---

*Phase: 15-strategy-roadmap-doc*
*Context gathered: 2026-05-19*
