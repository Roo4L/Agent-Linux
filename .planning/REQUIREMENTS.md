# Requirements: AgentLinux v0.3.3 — Agenda Redefinition

**Defined:** 2026-05-09
**Updated:** 2026-05-16 (Phase 14 reframed vision-only; Phase 15 inserted for strategy/roadmap doc; Phase 15 → Phase 16 renumber for website refresh; STRAT-* superseded by VIS-* + STRATR-*; DOC-05 locked N/A under Phase 13 verdict (b))
**Milestone:** v0.3.3 Agenda Redefinition
**Triggered by:** Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7)
**Core Value (carried from PROJECT.md):** An agent can be dropped into any supported Linux system and just work — provisioned correctly the first time. v0.3.3 broadens the framing of what AgentLinux *is*: from a single-pillar product (separated, correctly-owned agent environment — v0.3.0 core) to a two-pillar product (locked by Phase 13 verdict (b)). The deliverable is *framing* — a canonical vision document, a separate strategy/roadmap document, an ADR, and a refreshed public landing page — not new product capabilities.

## Design Philosophy (read first)

**This is a planning + framing milestone. Most evidence is documents, not bats @tests.**

- The exploration phases (12, 13) come *first* and produce written conclusions docs. The vision-doc authoring phase (14) consumes those conclusions; it does not pre-decide them. The strategy-doc authoring phase (15) lands after vision so it can reference VISION.md as upstream. The website-refresh phase (16) propagates whatever framing landed in 14 + 15.
- **Pillar count is settled at 2** by Phase 13 verdict (b). Security is folded into Pillar 2 as a sub-concern; security is not a separate pillar in v0.3.3.
- **Vision and strategy are separate documents** (user reframe 2026-05-16). `docs/VISION.md` is the canonical "what we want to be" — mission, two pillars as optimization values, vision-level guiding principles, vision-level non-goals. `docs/STRATEGY.md` is the canonical "how we get there" — execution rules, theme sequencing for v0.6+, near-term focus.
- **The voice rule is non-negotiable.** Per PITFALLS.md: every claim about an unshipped behaviour MUST appear in a sentence whose grammatical subject is "we" / "our roadmap" / an explicit milestone identifier — never "AgentLinux + present-tense verb." An automated grep gate enforces this on VISION.md (VIS-07), on STRATEGY.md (STRATR-06), and on the rendered website HTML (SITE-06). This is the single most important defence against shipping vaporware.
- **Phase-close gate convention carries over from v0.3.0/v0.4.0.** Every requirement closes with a cited evidence artefact in its phase's `<phase-NN>-AUDIT.md` before the gate emits GREEN. For documentation-only requirements the evidence is a file path + line range or a commit hash.
- **The vision doc is a living document.** Pitfall #12 / #23 — strategy doc never updates again — is flagged for the milestone retrospective + a `/gsd-complete-milestone` template amendment, not as an in-milestone requirement. Both VISION.md (VIS-06) and STRATEGY.md (STRATR-05) include a `Last reviewed:` header so the cadence binding has a place to land.
- **User-stated direction (locked at milestone-open + reaffirmed 2026-05-16):** Pillar 1 = `foundational` (settled by v0.3.0 reality). Pillar 2 = `next-milestone` priority. Pillar 3 does not exist (Phase 13 verdict (b)). Pillars are named by the optimization value (`Time-to-productive`, `Stability`), not by historical engineering vocabulary.

## v0.3.3 Requirements

Grouped by category. Each `XXX-NN` is a verifiable outcome — a document section, a cross-link, a grep result, a screenshot, or a commit hash — auditable before the phase closes.

### Pillar Exploration (EXPL) — Phases 12, 13

- [x] **EXPL-01**: A `docs/exploration/PILLAR-2-NOTES.md` file exists. It captures the discussion and verdict on pillar 2 (stability + time-to-productive). The file ends with a **"Decision summary"** section authoritative for downstream phases — naming the pillar, listing its committed table-stakes (≥2), differentiators (≥1, may be empty if intentionally so), explicit non-goals (≥2), and the "Today / Direction" content seed. Pillar 2's `next-milestone` priority tag is reaffirmed. (completed 2026-05-10)

- [x] **EXPL-02**: A `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` file exists. The file's first decision is the verdict: (a) yes, security is a full pillar; (b) no, fold into pillar 2 as a sub-concern; (c) no, address as cross-cutting concern; (d) no, explicitly out-of-scope. **Verdict landed: (b)** — fold into Pillar 2 as a sub-concern. The Decision summary documents the supply-chain monitoring + curated catalog admission commitment that folds into Pillar 2, the three explicit non-goals (no model guardrails, no upstream code audit, no sandbox runtime), and the ADR-012 NOPASSWD tension. (completed 2026-05-10)

### Vision Document (VIS) — Phase 14

- [ ] **VIS-01**: `docs/VISION.md` exists at the repo path (single Markdown file, sibling to `docs/STABILITY-MODEL.md` and `docs/HARNESS.md`). The file is at most 6 KB on first cut (target 4–5 KB; ~half the original STRATEGY.md target since the doc covers only the vision half of the original scope). It is a single Markdown file — not a `docs/vision/` tree, not embedded in README.

- [ ] **VIS-02**: The doc's spine reflects vision-only structure: `## Mission` (with a Geoffrey-Moore-form `### Positioning` subsection), `## The two pillars`, `## Guiding principles`, `## What we're explicitly not`. No `## Strategy and plans`, no `## Trade-offs / rejected alternatives`, no `## Appendix A — Vision Board`, no `## Appendix B — Roadmap themes` — those belong to Phase 15's STRATEGY.md, not to the vision doc.

- [ ] **VIS-03**: The Pillars section contains exactly 2 pillars (locked by Phase 13 verdict (b)). Pillars are named by the optimization value: `### Pillar 1 — Time-to-productive`, `### Pillar 2 — Stability`. No `#### Today` / `#### Direction` subsections inside pillars — those are status-report voice and belong in STRATEGY.md, not in the vision doc. The pillar body is one paragraph of identity-claim prose (what the pillar means we *are*, not what we've shipped or what we promise).

- [ ] **VIS-04**: A `## Guiding principles` section with 4–6 named principles. Each principle is a `### {Principle name}` heading + a short paragraph (1–4 sentences). Principles are vision-level (identity claims about what AgentLinux is) — not execution-level. Specifically, principles like "Behavior tests are the spec" (ADR-002), "TST-07 phase-close discipline," "Voice rule as authoring rule" — those are execution principles and belong in STRATEGY.md's `## Execution principles` section, not here. Vision-level seeds: "We are infrastructure, not an agent product," "We meet users on their distribution," "We curate, we do not aggregate," "Value arrives automatically."

- [ ] **VIS-05**: A `## What we're explicitly not` section with at least 4 vision-level non-goals as bulleted items, each with a one-line rationale. Non-goals reflect *identity* ("not an agent product," "not a sandbox runtime," "not an observability vendor," "not a Linux-distribution-style upstream maintainer," "not an agent benchmark publisher"), not roadmap deferrals.

- [ ] **VIS-06**: A top-of-file `> Last reviewed:` blockquote (first non-blank line after the H1). `head -5 docs/VISION.md | grep -E '^> Last reviewed: 2026-05'` returns 1 match. Forcing function for the future `/gsd-complete-milestone` cadence binding (Pitfall #12 / #23 mitigation).

- [ ] **VIS-07**: The voice-rule grep gate passes on VISION.md. Run: `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/VISION.md` MUST return zero matches anywhere in the doc. Acceptance evidence: the grep command + its empty output committed to `.planning/phases/14-vision-doc-and-downstream/14-AUDIT.md`. Hard gate.

- [ ] **VIS-08**: Cross-link map populated. Outbound — pillar / principle / non-goal claims in VISION.md that ground in an ADR may carry a Markdown link (light hand — vision-voice keeps most claims abstract; no requirement to link every claim). Inbound — `README.md` (About + Links), `CONTRIBUTING.md` (one paragraph), `.planning/PROJECT.md` (Core Value section), `docs/STABILITY-MODEL.md` (Related section) each gain a back-pointer to VISION.md. Phase-close audit lists every changed file with the line range of the back-pointer edit.

- [ ] **VIS-09**: `docs/decisions/015-agenda-redefinition.md` (ADR-015) lands in the same milestone window as VISION.md (same Phase 14 commit window). ADR-015 contains: `Status: Accepted`, `Context` (the AL-7 framing question + why the original single-pillar framing was getting in the way), `Decision` (the two-pillar landing — citing the EXPL-01 + EXPL-02 verdicts; vision-only document separated from strategy/roadmap per 2026-05-16 reframe), at least 3 considered-and-rejected alternatives (e.g. "stay single-pillar"; "ship vision+strategy+roadmap in one doc per original Phase 14 plan"; "pivot security-first to a Pillar 3"), `Consequences` (downstream effects on Phase 15 insertion + Phase 15 → Phase 16 renumber + downstream surface updates), and a back-link to AL-7 + VISION.md.

### Strategy / Roadmap Document (STRATR) — Phase 15

- [ ] **STRATR-01**: `docs/STRATEGY.md` exists at the repo path (single Markdown file, sibling to VISION.md). The file is at most 8 KB on first cut. Lands AFTER VISION.md so it can cite VISION.md as upstream "what."

- [ ] **STRATR-02**: The doc's spine reflects strategy/roadmap content. At minimum: `## Where we are now` (current state of v0.3.0/v0.4.0 + recently shipped), `## What we're working on next` (near-term focus, milestone-level), `## Themes for v0.6+` (forward-looking themes with sequencing rationale), `## Execution principles` (the process-level principles cut from VISION.md). `grep -nE '^## (Where we are now|What we'\''re working on next|Themes for|Execution principles)' docs/STRATEGY.md` returns ≥ 4 matches.

- [ ] **STRATR-03**: The `## Themes for v0.6+` section lists 2–4 forward-looking themes with `### Sequencing rationale` lines. At minimum:
   - `Security Hardening` (Phase 13 opportunistic theme — capability-scoped sudoers replacing ADR-012 NOPASSWD ALL, cosign-signed catalog releases, npm provenance verification, bubblewrap-based per-recipe sandbox profile, iptables egress allowlist).
   - Preset / profile framework + compat-guarded update flow (Phase 12 differentiators — `bare` / `must-haves` / `optimum` presets, `web-development`-style profiles, hold-and-wait-on-upstream-breakage policy).

- [ ] **STRATR-04**: The `## Execution principles` section contains the execution-level rules cut from VISION.md. 4–7 entries. At minimum:
   - Voice rule (delivered-fact vs forward-looking — never "AgentLinux + present-tense verb" for unshipped behaviour).
   - Behavior tests are the spec (ADR-002).
   - Evidence-cite discipline (TST-07-style phase-close audits cite file paths, line ranges, commit hashes, grep transcripts).
   - Curated-combo testing (TST-08 4-gate release pipeline — pre-commit → docker matrix → QEMU matrix → pinned-combo gate).
   - No `sudo npm install -g` anywhere (ADR-004 — always `sudo -u agent -H npm install -g`).

- [ ] **STRATR-05**: A top-of-file `> Last reviewed:` blockquote (first non-blank line after the H1). `head -5 docs/STRATEGY.md | grep -E '^> Last reviewed: 2026-05'` returns 1 match.

- [ ] **STRATR-06**: The voice-rule grep gate passes on STRATEGY.md. Run: `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md` MUST return zero matches. Acceptance evidence: grep + empty output committed to `.planning/phases/15-strategy-roadmap-doc/15-AUDIT.md`. Hard gate.

### Downstream Surface Updates (DOC) — Phase 14

- [ ] **DOC-01**: `README.md` is updated. The `## About` section (or equivalent) gains a single sentence naming the two pillars and linking to `docs/VISION.md`. The `## Links` section gains a `Vision: [docs/VISION.md](docs/VISION.md)` row. No other README copy is rewritten in this requirement.

- [ ] **DOC-02**: `CONTRIBUTING.md` is updated. A "Why this project exists" paragraph (one short paragraph) links to `docs/VISION.md` and names which pillar(s) currently accept contributions today (Pillar 1 = yes, the existing v0.3.0 surface; Pillar 2 = early-stage, contributions welcome with a heads-up that the framing locked in v0.3.3).

- [ ] **DOC-03**: `.planning/PROJECT.md` Core Value / Current Milestone sections cross-reference `docs/VISION.md` (one link in each section). The Out-of-Scope list reflects any new non-goals that EXPL-01 / EXPL-02 surfaced.

- [ ] **DOC-04**: `docs/STABILITY-MODEL.md` gains a `Related` section (or equivalent) with a back-link to `docs/VISION.md` Pillar 2 (since STABILITY-MODEL.md is the ADR-011 user companion and ADR-011 is the pillar-2 seed).

- [x] **DOC-05 (closed N/A 2026-05-16)**: Phase 13 verdict (b) — Pillar 3 did not survive. No edit to `docs/decisions/012-agent-user-full-sudo.md` (ADR-012) needed. The audit records DOC-05 as N/A with a one-line decision: "no edit needed because pillar 3 did not survive Phase 13"; the audit explicitly cites EXPL-02's `## Verdict` line. The unresolved ADR-012 tension is recorded inside Pillar 2's section in VISION.md as a known limitation, not via an ADR file edit.

### Website Refresh (SITE) — Phase 16

- [ ] **SITE-01**: `index.html` hero section is rewritten so the headline + subhead reflect the current product framing (no longer "purpose-built Linux distribution that runs on a dedicated machine"). Hero carries a delivered-fact line (what AgentLinux is today, v0.3.0/v0.4.0) AND a forward-looking line (where the strategy points). Voice rule applies (forward-looking line uses "we" / "our roadmap" / explicit milestone tag).

- [ ] **SITE-02**: The `#features` 8-card grid is replaced with a `#pillars` section presenting exactly 2 cards (matching VISION.md pillar count). Each card title matches the vision doc's pillar name (`Time-to-productive`, `Stability`); each card body is ≤ 3 sentences + a "Learn more →" link to `docs/VISION.md#pillar-N`.

- [ ] **SITE-03**: Each pillar card carries a visible status badge — `[SHIPPED v0.3.0]` for Pillar 1, `[v0.6+ ROADMAP]` for Pillar 2. Badge style is consistent across cards. PITFALLS #14 + #18 enforcement.

- [ ] **SITE-04**: The `#comparison` block is reframed or removed. Reframing aligns with the post-Phase-15 STRATEGY.md "Where we are now" content.

- [ ] **SITE-05**: A new `#install` section mirrors the README curl-pipe-bash + verify snippet, including the SHA256 verify line. Optional: keep `#install` minimal and link to README for the canonical reference.

- [ ] **SITE-06**: The voice-rule grep gate applies to the rendered HTML. Run: `grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html` MUST return zero matches anywhere on the page. Acceptance evidence: grep + empty output committed to `.planning/phases/16-website-refresh/16-AUDIT.md`. Hard gate.

- [ ] **SITE-07**: Footer adds links to `docs/VISION.md`, `docs/STRATEGY.md`, `docs/STABILITY-MODEL.md`, and `docs/decisions/` (ADR index) alongside the existing repo / releases links. The `Vision` link is also added to the top nav.

- [ ] **SITE-08**: OG / Twitter meta tags rewritten — `og:title`, `og:description`, `twitter:title`, `twitter:description` all reflect the broadened positioning (no "purpose-built Linux distribution" language). PITFALLS #20 enforcement.

- [ ] **SITE-09**: OG image converted SVG → PNG (closes v0.1.0 known issue). PNG sized per platform conventions (1200×630 for og:image). SVG preserved alongside as source-of-truth.

- [ ] **SITE-10**: Deploy-time install-instruction drift check is wired into `.github/workflows/deploy.yml` (or equivalent). The check fails the deploy if the install-snippet version stamp in `index.html` diverges from `README.md`'s `<!-- VERSION_START --><!-- VERSION_END -->` block. (If `index.html` doesn't carry an install snippet per SITE-05, this requirement closes as N/A.)

- [ ] **SITE-11**: PR body for the website-refresh PR includes mobile + narrow-viewport screenshots (≤ 375 px wide) of every changed section. PITFALLS #19 enforcement.

## Future Requirements (not in this milestone)

- **Pillar 2 implementation milestone (v0.6+)** — preset/profile framework, compat-guarded update flow mechanism, supply-chain monitoring policy codification. Strategy doc's Themes-for-v0.6+ section commits to it; this milestone does not deliver it.
- **Security Hardening milestone (v0.6+)** — capability-scoped sudoers replacing ADR-012 NOPASSWD ALL, cosign-signed catalog releases, npm provenance verification, bubblewrap-based per-recipe sandbox, iptables egress allowlist. Strategy doc's Themes-for-v0.6+ section commits to it; this milestone does not deliver it.
- **Distro Reach milestone (v0.6+)** — Fedora / Alma / Arch support — Pillar 1 expansion.
- **Vision-and-strategy-doc cadence binding** — `/gsd-complete-milestone` template gains "Vision doc + Strategy doc reviewed; pillar Today/Direction sections updated" steps. Process change to GSD itself, not an AgentLinux product change. Flagged for the v0.3.3 retrospective.

## Out of Scope (explicit exclusions)

**v0.3.3 out of scope:**
- *Implementing* preset/profile framework or compat-guarded update mechanism (Pillar 2 forward differentiators) — v0.3.3 surfaces them in the strategy doc; the actual implementation lands in a v0.6+ milestone.
- *Implementing* security-hardening countermeasures (the Phase 13 opportunistic theme) — supply-chain and prompt-injection mitigations land in a v0.6+ milestone.
- New distro targets, new catalog agents, new installer features — Pillar 1 stays at its v0.3.0 surface for this milestone.
- A full website redesign — the website-refresh phase keeps the existing dark JetBrains-Mono aesthetic + crab mascot.
- Renaming, restructuring, or moving the vision or strategy docs after Phase 14 / 15 land — locations lock at `docs/VISION.md` and `docs/STRATEGY.md`.
- Authoring a Code of Conduct, SECURITY.md, or full issue / PR templates — track separately as a community-platform milestone.
- *Resolving* the ADR-012 NOPASSWD tension. The vision doc + ADR-015 *document* the tension; the *resolution* belongs to the v0.6+ Security Hardening milestone.

**v0.4.0 out of scope (carried forward):**
- New distro targets (Fedora / CentOS / Alma / Arch / openSUSE)
- Mutation testing promotion to release gate — still v0.5+ per ADR-010
- Multi-arch (ARM) — x86_64 only for now
- Repo migration to a different GitHub organization or rename

**v0.3.0 out of scope (carried forward):**
- GUI or TUI installer (CLI only)
- Public PPA / package-signing infrastructure beyond curl-installer + GitHub Releases
- Multi-user provisioning (one agent user per host for now)
- Sandboxing / rootless containers inside the installer
- Custom distro / ISO / QCOW2 image build path

**Permanently out of scope (carried from prior milestones):**
- User accounts or login functionality on website
- Blog or content management system
- Mobile app
- E-commerce / payments
- Multi-arch (ARM) — x86_64 only for now
- Docker-in-Docker inside the agent environment

## Traceability

Each requirement is mapped to exactly one phase. Phase numbering continues from v0.4.0's last phase (11 → 12).

| Req | Phase | Plan |
|-----|-------|------|
| EXPL-01 | 12 | 12-01-PLAN.md |
| EXPL-02 | 13 | 13-01-PLAN.md |
| VIS-01 | 14 | 14-01-PLAN.md |
| VIS-02 | 14 | 14-01-PLAN.md |
| VIS-03 | 14 | 14-01-PLAN.md |
| VIS-04 | 14 | 14-01-PLAN.md |
| VIS-05 | 14 | 14-01-PLAN.md |
| VIS-06 | 14 | 14-01-PLAN.md |
| VIS-07 | 14 | 14-01-PLAN.md |
| VIS-08 | 14 | 14-02-PLAN.md |
| VIS-09 | 14 | 14-01-PLAN.md |
| DOC-01 | 14 | 14-02-PLAN.md |
| DOC-02 | 14 | 14-02-PLAN.md |
| DOC-03 | 14 | 14-02-PLAN.md |
| DOC-04 | 14 | 14-02-PLAN.md |
| DOC-05 | 14 | N/A — closed 2026-05-16 (Phase 13 verdict (b) — no pillar 3 → no ADR-012 forward-reference edit) |
| STRATR-01 | 15 | 15-01-PLAN.md |
| STRATR-02 | 15 | 15-01-PLAN.md |
| STRATR-03 | 15 | 15-01-PLAN.md |
| STRATR-04 | 15 | 15-01-PLAN.md |
| STRATR-05 | 15 | 15-01-PLAN.md |
| STRATR-06 | 15 | 15-01-PLAN.md |
| SITE-01 | 16 | 16-01-PLAN.md |
| SITE-02 | 16 | 16-01-PLAN.md |
| SITE-03 | 16 | 16-01-PLAN.md |
| SITE-04 | 16 | 16-01-PLAN.md |
| SITE-05 | 16 | 16-01-PLAN.md |
| SITE-06 | 16 | 16-01-PLAN.md |
| SITE-07 | 16 | 16-01-PLAN.md |
| SITE-08 | 16 | 16-01-PLAN.md |
| SITE-09 | 16 | 16-01-PLAN.md |
| SITE-10 | 16 | 16-01-PLAN.md (or N/A close if SITE-05 omits the install snippet) |
| SITE-11 | 16 | 16-01-PLAN.md |

**Coverage:** 33 / 33 requirements mapped (2 EXPL + 9 VIS + 6 STRATR + 5 DOC + 11 SITE). Zero orphans, zero duplicates. Conditional closes (DOC-05, SITE-10) recorded inline above.

## Superseded Items (2026-05-16 reframe)

The following requirements were superseded by the 2026-05-16 vision/strategy split. They are listed here as audit trail; their substance is preserved across VIS-* + STRATR-* + DOC-* as noted.

| Old ID | Disposition |
|--------|-------------|
| STRAT-01 (STRATEGY.md size ≤10 KB) | Split: VIS-01 (≤6 KB) + STRATR-01 (≤8 KB) |
| STRAT-02 (Sourcegraph spine) | Dissolved (template no longer the spine); VIS-02 + STRATR-02 define new spines |
| STRAT-03 (Pillars Today/Direction split) | Reshaped: VIS-03 (vision pillars without Today/Direction); STRATR-02 + STRATR-03 carry status + roadmap content separately |
| STRAT-04 (Pillar priority subsection) | Folded: pillar priority lives in STRATR-03 themes sequencing; vision doc does not tag priorities |
| STRAT-05 (Guiding principles 4-7) | Split: VIS-04 (vision-level principles 4-6) + STRATR-04 (execution principles 4-7) |
| STRAT-06 (What we're not working on, ≥5) | Reshaped: VIS-05 (vision-level non-goals, ≥4); STRATR may add execution-level exclusions but not required |
| STRAT-07 (Trade-offs / rejected alternatives) | Dropped per user direction 2026-05-16 ("framework-shape trade-offs are of no concern to the document readers") |
| STRAT-08 (Appendix A Vision Board) | Dropped per user direction 2026-05-16 (recognized as ceremony; doc is short enough to read end-to-end) |
| STRAT-09 (Appendix B Roadmap themes) | Moved to STRATR-03 (now lives in STRATEGY.md, not VISION.md) |
| STRAT-10 (Last reviewed header) | Split: VIS-06 + STRATR-05 (both docs carry the header) |
| STRAT-11 (Voice-rule grep gate on STRATEGY.md) | Split: VIS-07 (gate on VISION.md) + STRATR-06 (gate on STRATEGY.md) |
| STRAT-12 (Cross-link map) | Reshaped: VIS-08 (back-pointers point to VISION.md) |
| STRAT-13 (ADR-015) | Renamed: VIS-09 (same substance, references VISION.md) |

## Deferred Items

- **`/gsd-complete-milestone` template amendment** (Pitfall #12 / #23) — adds a "Vision doc + Strategy doc reviewed" step that updates pillar Today / Direction sections at every milestone close. Process change to GSD itself; flagged for the v0.3.3 retrospective.
- **CI lint that warns if VISION.md or STRATEGY.md `Last reviewed:` header is older than the latest release tag by >90 days** — defer until the cadence binding is in place.
- **Bidirectional ADR back-references** — ADR-011 forward-reference to VISION.md (recommended in original SUMMARY.md §6 as optional). Defer unless VIS-08 author finds it valuable.
