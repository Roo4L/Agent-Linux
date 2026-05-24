# Requirements: AgentLinux v0.3.3 — Agenda Redefinition

**Defined:** 2026-05-09
**Updated:** 2026-05-16 (Phase 15 reframed vision-only; Phase 16 inserted for strategy/roadmap doc; Phase 16 → Phase 17 renumber for website refresh; STRAT-* superseded by VIS-* + STRATR-*; DOC-05 locked N/A under Phase 14 verdict (b))
**Milestone:** v0.3.3 Agenda Redefinition
**Triggered by:** Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7)
**Core Value (carried from PROJECT.md):** An agent can be dropped into any supported Linux system and just work — provisioned correctly the first time. v0.3.3 broadens the framing of what AgentLinux *is*: from a single-pillar product (separated, correctly-owned agent environment — v0.3.0 core) to a two-pillar product (locked by Phase 14 verdict (b)). The deliverable is *framing* — a canonical vision document, a separate strategy/roadmap document, an ADR, and a refreshed public landing page — not new product capabilities.

## Design Philosophy (read first)

**This is a planning + framing milestone. Most evidence is documents, not bats @tests.**

- The exploration phases (13, 14) come *first* and produce written conclusions docs. The vision-doc authoring phase (15) consumes those conclusions; it does not pre-decide them. The strategy-doc authoring phase (16) lands after vision so it can reference VISION.md as upstream. The website-refresh phase (17) propagates whatever framing landed in 15 + 16.
- **Pillar count is settled at 2** by Phase 14 verdict (b). Security is folded into Pillar 2 as a sub-concern; security is not a separate pillar in v0.3.3.
- **Vision and strategy are separate documents** (user reframe 2026-05-16). `docs/VISION.md` is the canonical "what we want to be" — mission, two pillars as optimization values, vision-level guiding principles, vision-level non-goals. `docs/STRATEGY.md` is the canonical "how we get there" — execution rules, theme sequencing for v0.6+, near-term focus.
- **The voice rule is non-negotiable.** Per PITFALLS.md: every claim about an unshipped behaviour MUST appear in a sentence whose grammatical subject is "we" / "our roadmap" / an explicit milestone identifier — never "AgentLinux + present-tense verb." An automated grep gate enforces this on VISION.md (VIS-07), on STRATEGY.md (STRATR-06), and on the rendered website HTML (SITE-06). This is the single most important defence against shipping vaporware.
- **Phase-close gate convention carries over from v0.3.0/v0.4.0.** Every requirement closes with a cited evidence artefact in its phase's `<phase-NN>-AUDIT.md` before the gate emits GREEN. For documentation-only requirements the evidence is a file path + line range or a commit hash.
- **The vision doc is a living document.** Pitfall #12 / #23 — strategy doc never updates again — is flagged for the milestone retrospective + a `/gsd-complete-milestone` template amendment, not as an in-milestone requirement. Both VISION.md (VIS-06) and STRATEGY.md (STRATR-05) include a `Last reviewed:` header so the cadence binding has a place to land.
- **User-stated direction (locked at milestone-open + reaffirmed 2026-05-16):** Pillar 1 = `foundational` (settled by v0.3.0 reality). Pillar 2 = `next-milestone` priority. Pillar 3 does not exist (Phase 14 verdict (b)). Pillars are named by the optimization value (`Time-to-productive`, `Stability`), not by historical engineering vocabulary.

## v0.3.3 Requirements

Grouped by category. Each `XXX-NN` is a verifiable outcome — a document section, a cross-link, a grep result, a screenshot, or a commit hash — auditable before the phase closes.

### Pillar Exploration (EXPL) — Phases 13, 14

- [x] **EXPL-01**: A `docs/exploration/PILLAR-2-NOTES.md` file exists. It captures the discussion and verdict on pillar 2 (stability + time-to-productive). The file ends with a **"Decision summary"** section authoritative for downstream phases — naming the pillar, listing its committed table-stakes (≥2), differentiators (≥1, may be empty if intentionally so), explicit non-goals (≥2), and the "Today / Direction" content seed. Pillar 2's `next-milestone` priority tag is reaffirmed. (completed 2026-05-10)

- [x] **EXPL-02**: A `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` file exists. The file's first decision is the verdict: (a) yes, security is a full pillar; (b) no, fold into pillar 2 as a sub-concern; (c) no, address as cross-cutting concern; (d) no, explicitly out-of-scope. **Verdict landed: (b)** — fold into Pillar 2 as a sub-concern. The Decision summary documents the supply-chain monitoring + curated catalog admission commitment that folds into Pillar 2, the three explicit non-goals (no model guardrails, no upstream code audit, no sandbox runtime), and the ADR-012 NOPASSWD tension. (completed 2026-05-10)

### Vision Document (VIS) — Phase 15

- [ ] **VIS-01**: `docs/VISION.md` exists at the repo path (single Markdown file, sibling to `docs/STABILITY-MODEL.md` and `docs/HARNESS.md`). The file is at most 6 KB on first cut (target 4–5 KB; ~half the original STRATEGY.md target since the doc covers only the vision half of the original scope). It is a single Markdown file — not a `docs/vision/` tree, not embedded in README.

- [ ] **VIS-02**: The doc's spine reflects vision-only structure: `## Mission` (with a Geoffrey-Moore-form `### Positioning` subsection), `## The two pillars`, `## Guiding principles`, `## What we're explicitly not`. No `## Strategy and plans`, no `## Trade-offs / rejected alternatives`, no `## Appendix A — Vision Board`, no `## Appendix B — Roadmap themes` — those belong to Phase 16's STRATEGY.md, not to the vision doc.

- [ ] **VIS-03**: The Pillars section contains exactly 2 pillars (locked by Phase 14 verdict (b)). Pillars are named by the optimization value: `### Pillar 1 — Time-to-productive`, `### Pillar 2 — Stability`. No `#### Today` / `#### Direction` subsections inside pillars — those are status-report voice and belong in STRATEGY.md, not in the vision doc. The pillar body is one paragraph of identity-claim prose (what the pillar means we *are*, not what we've shipped or what we promise).

- [ ] **VIS-04**: A `## Guiding principles` section with 4–6 named principles. Each principle is a `### {Principle name}` heading + a short paragraph (1–4 sentences). Principles are vision-level (identity claims about what AgentLinux is) — not execution-level. Specifically, principles like "Behavior tests are the spec" (ADR-002), "TST-07 phase-close discipline," "Voice rule as authoring rule" — those are execution principles and belong in STRATEGY.md's `## Execution principles` section, not here. Vision-level seeds: "We are infrastructure, not an agent product," "We meet users on their distribution," "We curate, we do not aggregate," "Value arrives automatically."

- [ ] **VIS-05**: A `## What we're explicitly not` section with at least 4 vision-level non-goals as bulleted items, each with a one-line rationale. Non-goals reflect *identity* ("not an agent product," "not a sandbox runtime," "not an observability vendor," "not a Linux-distribution-style upstream maintainer," "not an agent benchmark publisher"), not roadmap deferrals.

- [ ] **VIS-06**: A top-of-file `> Last reviewed:` blockquote (first non-blank line after the H1). `head -5 docs/VISION.md | grep -E '^> Last reviewed: 2026-05'` returns 1 match. Forcing function for the future `/gsd-complete-milestone` cadence binding (Pitfall #12 / #23 mitigation).

- [ ] **VIS-07**: The voice-rule grep gate passes on VISION.md. Run: `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/VISION.md` MUST return zero matches anywhere in the doc. Acceptance evidence: the grep command + its empty output committed to `.planning/phases/15-vision-doc-and-downstream/15-AUDIT.md`. Hard gate.

- [ ] **VIS-08**: Cross-link map populated. Outbound — pillar / principle / non-goal claims in VISION.md that ground in an ADR may carry a Markdown link (light hand — vision-voice keeps most claims abstract; no requirement to link every claim). Inbound — `README.md` (About + Links), `CONTRIBUTING.md` (one paragraph), `.planning/PROJECT.md` (Core Value section), `docs/STABILITY-MODEL.md` (Related section) each gain a back-pointer to VISION.md. Phase-close audit lists every changed file with the line range of the back-pointer edit.

- [ ] **VIS-09**: `docs/decisions/016-agenda-redefinition.md` (ADR-016) lands in the same milestone window as VISION.md (same Phase 15 commit window). ADR-016 contains: `Status: Accepted`, `Context` (the AL-7 framing question + why the original single-pillar framing was getting in the way), `Decision` (the two-pillar landing — citing the EXPL-01 + EXPL-02 verdicts; vision-only document separated from strategy/roadmap per 2026-05-16 reframe), at least 3 considered-and-rejected alternatives (e.g. "stay single-pillar"; "ship vision+strategy+roadmap in one doc per original Phase 15 plan"; "pivot security-first to a Pillar 3"), `Consequences` (downstream effects on Phase 16 insertion + Phase 16 → Phase 17 renumber + downstream surface updates), and a back-link to AL-7 + VISION.md.

### Strategy / Roadmap Document (STRATR) — Phase 16

- [ ] **STRATR-01**: `docs/STRATEGY.md` exists at the repo path (single Markdown file, sibling to VISION.md). The file is at most 10 KB on first cut. Lands AFTER VISION.md so it can cite VISION.md as upstream "what." Amendment 2026-05-23: ceiling bumped from 8 KB to 10 KB to accommodate the 5-section Rumelt-style spine (2026-05-19) plus maintainer-authored denser execution-principles section (2026-05-23). Restores the original v0.3.3 STRAT-01 10 KB ceiling.

- [ ] **STRATR-02**: The doc's spine reflects strategy-only content (diagnosis + bets + guiding policy + execution principles), in this order: `## What we're solving` (the multi-year diagnosis — the integration gaps between distro / language / agent vendors that no infrastructure layer currently owns), `## Our bets` (the load-bearing strategic choices with one-line why each, plus a closing paragraph showing how they reinforce each other), `## Guiding policy` (priorities + downprioritize list + falsifiability — "how we'd know the strategy was wrong"), `## Execution principles`. `grep -nE '^## (What we'\''re solving|Our bets|Guiding policy|Execution principles)' docs/STRATEGY.md` returns ≥ 4 matches in the prescribed order. Amendment 2026-05-23 (Round 2): supersedes the previous 5-section spine (2026-05-19 reframe); "Where we are now" + "What's next" sections moved to `docs/ROADMAP.md` per STRATR-07. Diagnosis sharpened from "the narrow bug class AgentLinux eliminates" to the multi-year integration-gap framing. `## Guiding policy` (new) replaces the time-ordered status content with prioritize / downprioritize / falsifiability — the strategy-doc traits per Rumelt's "good strategy" criteria (clear diagnosis, chosen battlefield, explicit trade-offs, reinforcing actions, falsifiability).

- [ ] **STRATR-03**: The `## Themes for v0.6+` section lists 2–4 forward-looking themes with `### Sequencing rationale` lines. At minimum:
   - `Security Hardening` (Phase 14 opportunistic theme — capability-scoped sudoers replacing ADR-012 NOPASSWD ALL, cosign-signed catalog releases, npm provenance verification, bubblewrap-based per-recipe sandbox profile, iptables egress allowlist).
   - Preset / profile framework + compat-guarded update flow (Phase 13 differentiators — `bare` / `must-haves` / `optimum` presets, `web-development`-style profiles, hold-and-wait-on-upstream-breakage policy).

- [ ] **STRATR-04**: The `## Execution principles` section contains 4–7 entries, each anchored in a project-specific decision pattern (not generic software-development conventions). Amendment 2026-05-23: the original mandated entries (voice rule, behavior tests, evidence-cite, curated-combo, no sudo npm install -g) were superseded by maintainer-authored principles. Substance preserved: behavior-tests-as-spec + curated-combo testing both live in `## Our bets`; no-`sudo npm install -g` lives in `## What we're solving`. Voice rule moved out of strategy doc per user direction (authoring-discipline rule, not an execution principle). Evidence-cite dropped (user-rejected as too generic to bite). The maintainer-authored replacements are listed in 16-AUDIT.md § STRATR-04.

- [ ] **STRATR-05**: A top-of-file `> Last reviewed:` blockquote (first non-blank line after the H1). `head -5 docs/STRATEGY.md | grep -E '^> Last reviewed: 2026-05'` returns 1 match.

- [ ] **STRATR-06**: The voice-rule grep gate passes on STRATEGY.md AND on ROADMAP.md. Run: `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md docs/ROADMAP.md` MUST return zero matches across both files. Acceptance evidence: grep + empty output committed to `.planning/phases/16-strategy-roadmap-doc/16-AUDIT.md`. Hard gate. Amendment 2026-05-23 (Round 2): extended from STRATEGY.md-only to both STRATEGY.md and ROADMAP.md following the strategy / roadmap split.

- [ ] **STRATR-07** (added 2026-05-23 Round 2): `docs/ROADMAP.md` exists at the repo path (single Markdown file, sibling to STRATEGY.md and VISION.md). The file is at most 6 KB on first cut. Contains the time-ordered work that follows from STRATEGY.md: `## Where we are now` (current state + recently shipped) and `## What's next` (with `### Near-term` and `### Themes for v0.6+` subsections; ≥ 4 themes with `**Sequencing rationale:**` lines, mirroring the STRATR-03 themes that originally lived in STRATEGY.md). `grep -nE '^## (Where we are now|What'\''s next)' docs/ROADMAP.md` returns ≥ 2 matches; `grep -nE '^### (Near-term|Themes for v0\.6\+)' docs/ROADMAP.md` returns ≥ 2 matches; `grep -c '\*\*Sequencing rationale:\*\*' docs/ROADMAP.md` returns ≥ 4. A top-of-file `> Last reviewed:` blockquote (first non-blank line after H1) is also present. Voice-rule grep gate (STRATR-06) extends to ROADMAP.md.

### Downstream Surface Updates (DOC) — Phase 15

- [ ] **DOC-01**: `README.md` is updated. The `## About` section (or equivalent) gains a single sentence naming the two pillars and linking to `docs/VISION.md`. The `## Links` section gains a `Vision: [docs/VISION.md](docs/VISION.md)` row. No other README copy is rewritten in this requirement.

- [ ] **DOC-02**: `CONTRIBUTING.md` is updated. A "Why this project exists" paragraph (one short paragraph) links to `docs/VISION.md` and names which pillar(s) currently accept contributions today (Pillar 1 = yes, the existing v0.3.0 surface; Pillar 2 = early-stage, contributions welcome with a heads-up that the framing locked in v0.3.3).

- [ ] **DOC-03**: `.planning/PROJECT.md` Core Value / Current Milestone sections cross-reference `docs/VISION.md` (one link in each section). The Out-of-Scope list reflects any new non-goals that EXPL-01 / EXPL-02 surfaced.

- [ ] **DOC-04**: `docs/STABILITY-MODEL.md` gains a `Related` section (or equivalent) with a back-link to `docs/VISION.md` Pillar 2 (since STABILITY-MODEL.md is the ADR-011 user companion and ADR-011 is the pillar-2 seed).

- [x] **DOC-05 (closed N/A 2026-05-16)**: Phase 14 verdict (b) — Pillar 3 did not survive. No edit to `docs/decisions/012-agent-user-full-sudo.md` (ADR-012) needed. The audit records DOC-05 as N/A with a one-line decision: "no edit needed because pillar 3 did not survive Phase 14"; the audit explicitly cites EXPL-02's `## Verdict` line. The unresolved ADR-012 tension is recorded inside Pillar 2's section in VISION.md as a known limitation, not via an ADR file edit.

### Website Refresh (SITE) — Phase 17

- [x] **SITE-01**: `index.html` hero section is rewritten so the headline + subhead reflect the current product framing (no longer "purpose-built Linux distribution that runs on a dedicated machine"). Hero carries a delivered-fact line (what AgentLinux is today, v0.3.0/v0.4.0) AND a forward-looking line (where the strategy points). Voice rule applies (forward-looking line uses "we" / "our roadmap" / explicit milestone tag).

- [x] **SITE-02**: The `#features` 8-card grid is replaced with a `#pillars` section presenting exactly 2 cards (matching VISION.md pillar count). Each card title matches the vision doc's pillar name (`Time-to-productive`, `Stability`); each card body is ≤ 3 sentences + a "Learn more →" link to `docs/VISION.md#pillar-N`.

- [x] **SITE-03**: Each pillar card carries a visible status badge — `[SHIPPED v0.3.0]` for Pillar 1, `[v0.6+ ROADMAP]` for Pillar 2. Badge style is consistent across cards. PITFALLS #14 + #18 enforcement.

- [x] **SITE-04**: The `#comparison` block is reframed or removed. Reframing aligns with the post-Phase-15 STRATEGY.md "Where we are now" content.

- [x] **SITE-05**: A new `#install` section mirrors the README curl-pipe-bash + verify snippet, including the SHA256 verify line. Optional: keep `#install` minimal and link to README for the canonical reference.

- [x] **SITE-06**: The voice-rule grep gate applies to the rendered HTML. Run: `grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html` MUST return zero matches anywhere on the page. Acceptance evidence: grep + empty output committed to `.planning/phases/17-website-refresh/17-AUDIT.md`. Hard gate.

- [x] **SITE-07**: Footer adds links to `docs/VISION.md`, `docs/STRATEGY.md`, `docs/STABILITY-MODEL.md`, and `docs/decisions/` (ADR index) alongside the existing repo / releases links. The `Vision` link is also added to the top nav.

- [x] **SITE-08**: OG / Twitter meta tags rewritten — `og:title`, `og:description`, `twitter:title`, `twitter:description` all reflect the broadened positioning (no "purpose-built Linux distribution" language). PITFALLS #20 enforcement.

- [x] **SITE-09**: OG image converted SVG → PNG (closes v0.1.0 known issue). PNG sized per platform conventions (1200×630 for og:image). SVG preserved alongside as source-of-truth.

- [x] **SITE-10**: Deploy-time install-instruction drift check is wired into `.github/workflows/deploy.yml` (or equivalent). The check fails the deploy if the install-snippet version stamp in `index.html` diverges from `README.md`'s `<!-- VERSION_START --><!-- VERSION_END -->` block. (If `index.html` doesn't carry an install snippet per SITE-05, this requirement closes as N/A.)

- [x] **SITE-11**: PR body for the website-refresh PR includes mobile + narrow-viewport screenshots (≤ 375 px wide) of every changed section. PITFALLS #19 enforcement.

## Post-v0.4.0 Addendum Requirements

The v0.4.0 milestone closed at commit `c8a2787` on 2026-05-02 with 21 requirements (LIC/SEC/CLEAN/CIPUB/PUB). The following requirement set is a *post-v0.4.0 addendum* added under issue AL-22 ("Create documentation on what AgentLinux does") — captured in this file because REQUIREMENTS.md is still the active per-project requirements doc, but tracked separately so the v0.4.0 milestone gate count stays honest.

### Developer Documentation (DOC) — Phase 13

- [x] **DOC-01**: A `docs/internals/README.md` exists at the documented location, opens with a one-paragraph "What AgentLinux is" lede in product voice, and contains a `## Components` H2 with a TOC linking to all nine component docs (installer, agent-user, sudo-drop-in, nodejs-runtime, claude-code, gsd, playwright, registry-cli, catalog). Verified by file-existence check + grep for the nine `(*.md)` link targets.
- [x] **DOC-02**: Nine component docs exist under `docs/internals/` — one per surface listed in the index. Each follows the four-section structural contract: `## The problem` → `## What AgentLinux does` → `## Value vs the naive approach` → `## Related`. Each `## Value vs the naive approach` is a numbered list with **bold lead clause** items (excerpt-friendly per the AL-22 reuse-as-blog-source signal). No source-line deep links anywhere in `docs/internals/` (per the dev-docs depth contract). Verified by grep across the nine files.
- [x] **DOC-03**: A new project-scoped reviewer agent `.claude/agents/dev-docs-auditor.md` exists with read-only tools (`tools: Read, Grep, Glob, Bash`) and a frontmatter description triggering it on changes under `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, and `packaging/curl-installer/`. The reviewer is registered in CLAUDE.md "Review Loop" by extending the Bash, TS/JS, and Catalog recipes rows of the reviewer-by-file-type table. Verified by file existence + `grep -E '^- Bash → .*dev-docs-auditor' CLAUDE.md` and equivalents for the other two extended rows.
- [x] **DOC-04**: A new project-scoped skill `.claude/skills/dev-docs/SKILL.md` exists, documenting the docs/internals/ contract (per-component four-section structure, source-path → doc-path dispatch table, when to update, product-perspective lens, and the explicit decision to not add a stop-hook). The skill is enumerated in CLAUDE.md "Pointers" alongside the other project-scoped skills. Verified by file existence + grep for the dispatch-table entries covering all 9 component docs.
- [x] **DOC-05**: Top-level discoverability — top-level `README.md` gains a "Why AgentLinux — concepts" H2 section linking `docs/internals/README.md`, AND a `## Links` row labelled `**Internals (developer docs):**` linking `docs/internals/`. Verified by grep across `README.md`.
- [x] **DOC-06**: No new stop-hook was added — `.claude/hooks/dev-docs-reminder.sh` does not exist; `.claude/settings.json` is unchanged across the Phase 13 commit range. The dev-docs sync check rides inside the existing `review-reminder.sh`-triggered review loop per the ADR-010 2026-05-02 refinement and per ADR-016 (DOC-07). Verified by `! test -f .claude/hooks/dev-docs-reminder.sh` and `git diff <phase-12-base>..HEAD -- .claude/settings.json | wc -l` returning 0.
- [x] **DOC-07**: A new ADR `docs/decisions/015-developer-internals-docs.md` records the design decision behind Phase 13 — what `docs/internals/` is for, why a reviewer + skill instead of a hook, why a flat embed inside the existing Review Loop instead of a new top-level CLAUDE.md section. Status `Accepted`. Verified by file existence + `grep -q '^## Decision' docs/decisions/015-developer-internals-docs.md`.

## Future Requirements (not in this milestone)

- **Pillar 2 implementation milestone (v0.6+)** — preset/profile framework, compat-guarded update flow mechanism, supply-chain monitoring policy codification. Strategy doc's Themes-for-v0.6+ section commits to it; this milestone does not deliver it.
- **Security Hardening milestone (v0.6+)** — capability-scoped sudoers replacing ADR-012 NOPASSWD ALL, cosign-signed catalog releases, npm provenance verification, bubblewrap-based per-recipe sandbox, iptables egress allowlist. Strategy doc's Themes-for-v0.6+ section commits to it; this milestone does not deliver it.
- **Distro Reach milestone (v0.6+)** — Fedora / Alma / Arch support — Pillar 1 expansion.
- **Vision-and-strategy-doc cadence binding** — `/gsd-complete-milestone` template gains "Vision doc + Strategy doc reviewed; pillar Today/Direction sections updated" steps. Process change to GSD itself, not an AgentLinux product change. Flagged for the v0.3.3 retrospective.

## Out of Scope (explicit exclusions)

**v0.3.3 out of scope:**
- *Implementing* preset/profile framework or compat-guarded update mechanism (Pillar 2 forward differentiators) — v0.3.3 surfaces them in the strategy doc; the actual implementation lands in a v0.6+ milestone.
- *Implementing* security-hardening countermeasures (the Phase 14 opportunistic theme) — supply-chain and prompt-injection mitigations land in a v0.6+ milestone.
- New distro targets, new catalog agents, new installer features — Pillar 1 stays at its v0.3.0 surface for this milestone.
- A full website redesign — the website-refresh phase keeps the existing dark JetBrains-Mono aesthetic + crab mascot.
- Renaming, restructuring, or moving the vision or strategy docs after Phase 15 / 15 land — locations lock at `docs/VISION.md` and `docs/STRATEGY.md`.
- Authoring a Code of Conduct, SECURITY.md, or full issue / PR templates — track separately as a community-platform milestone.
- *Resolving* the ADR-012 NOPASSWD tension. The vision doc + ADR-016 *document* the tension; the *resolution* belongs to the v0.6+ Security Hardening milestone.

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
| EXPL-01 | 12 | 13-01-PLAN.md |
| EXPL-02 | 13 | 14-01-PLAN.md |
| VIS-01 | 14 | 15-01-PLAN.md |
| VIS-02 | 14 | 15-01-PLAN.md |
| VIS-03 | 14 | 15-01-PLAN.md |
| VIS-04 | 14 | 15-01-PLAN.md |
| VIS-05 | 14 | 15-01-PLAN.md |
| VIS-06 | 14 | 15-01-PLAN.md |
| VIS-07 | 14 | 15-01-PLAN.md |
| VIS-08 | 14 | 15-02-PLAN.md |
| VIS-09 | 14 | 15-01-PLAN.md |
| DOC-01 | 14 | 15-02-PLAN.md |
| DOC-02 | 14 | 15-02-PLAN.md |
| DOC-03 | 14 | 15-02-PLAN.md |
| DOC-04 | 14 | 15-02-PLAN.md |
| DOC-05 | 14 | N/A — closed 2026-05-16 (Phase 14 verdict (b) — no pillar 3 → no ADR-012 forward-reference edit) |
| STRATR-01 | 15 | 16-01-PLAN.md |
| STRATR-02 | 15 | 16-01-PLAN.md |
| STRATR-03 | 15 | 16-01-PLAN.md |
| STRATR-04 | 15 | 16-01-PLAN.md |
| STRATR-05 | 15 | 16-01-PLAN.md |
| STRATR-06 | 15 | 16-01-PLAN.md |
| SITE-01 | 16 | 17-01-PLAN.md |
| SITE-02 | 16 | 17-01-PLAN.md |
| SITE-03 | 16 | 17-01-PLAN.md |
| SITE-04 | 16 | 17-01-PLAN.md |
| SITE-05 | 16 | 17-01-PLAN.md |
| SITE-06 | 16 | 17-01-PLAN.md |
| SITE-07 | 16 | 17-01-PLAN.md |
| SITE-08 | 16 | 17-01-PLAN.md |
| SITE-09 | 16 | 17-01-PLAN.md |
| SITE-10 | 16 | 17-01-PLAN.md (or N/A close if SITE-05 omits the install snippet) |
| SITE-11 | 16 | 17-01-PLAN.md |

**Coverage:** 33 / 33 requirements mapped (2 EXPL + 9 VIS + 6 STRATR + 5 DOC + 11 SITE). Zero orphans, zero duplicates. Conditional closes (DOC-05, SITE-10) recorded inline above.

### Post-v0.4.0 Addendum Traceability

| Phase | Requirements | Count |
|-------|--------------|-------|
| 12 Developer Documentation (AL-22) | DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07 | 7 |
| **Total addendum** | | **7** |

**Coverage check:** 7 addendum requirements mapped to 1 phase. Zero orphans. (v0.4.0 milestone total remains 21 requirements across 5 phases — see the table above.)

## Verification Convention

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
| STRAT-13 (ADR-016) | Renamed: VIS-09 (same substance, references VISION.md) |

## Superseded Items (2026-05-19 Phase 16 spine reframe)

The following requirement was amended in the Phase 16 commit window per the mid-discuss research-driven spine reframe (precedent: 2026-05-16 STRAT-* → VIS-* + STRATR-* reframe in Phase 15 / Plan 15-02 commit window).

| Old ID | Disposition |
|--------|-------------|
| STRATR-02 (4-section spine: `Where we are now` / `What we're working on next` / `Themes for` / `Execution principles`; ≥ 4 grep matches) | Amended in-place: STRATR-02 (5-section Rumelt-style spine: `What we're solving` / `Our bets` / `Where we are now` / `What's next` / `Execution principles`; ≥ 5 grep matches; `### Near-term` + `### Themes for v0.6+` as subsections under `## What's next`). Substance preserved (status content moves into `## Where we are now`; near-term content moves into `### Near-term` subsection; themes move into `### Themes for v0.6+` subsection); diagnosis + guiding-policy moves added (`## What we're solving` + `## Our bets`). |

## Superseded Items (2026-05-23 execution-principles rewrite + STRATR-01 size bump)

The maintainer authored a new `## Execution principles` section in the Phase 16 amendment window after rejecting the originally-mandated entries as generic ("evidence-cite," "behavior tests are spec") or out-of-category ("voice rule"). STRATR-01 ceiling bumped to accommodate denser principle prose. Precedent: 2026-05-19 STRATR-02 spine reframe and 2026-05-16 STRAT-* → VIS-* + STRATR-* reframe.

| Old ID | Disposition |
|--------|-------------|
| STRATR-01 (≤ 8 KB ceiling) | Amended in-place: STRATR-01 (≤ 10 KB ceiling). The 8 KB ceiling was set when the doc was scoped for the original 4-section spine + brief bulleted principles. The 5-section Rumelt-style spine (2026-05-19) + maintainer-authored execution principles (2026-05-23) push the natural landing past 8 KB. Restores the original v0.3.3 STRAT-01 10 KB ceiling pre-Phase-14 split. |
| STRATR-04 (mandated entries: voice rule, behavior tests, evidence-cite, curated-combo, no sudo npm install -g) | Amended in-place: STRATR-04 (4-7 entries; project-specific patterns; no mandated entries). Substance preserved: behavior-tests-as-spec + curated-combo testing folded into `## Our bets`; no-`sudo npm install -g` folded into `## What we're solving`. Voice rule moved out of strategy doc per user direction (lives as authoring discipline, not execution principle). Evidence-cite dropped (user-rejected as too generic to bite). Maintainer-authored replacements: First-person friction wins; Human-first surfaces; Three dimensions of package readiness; Survives without the maintainer. |

## Superseded Items (2026-05-23 Round 2 — strategy / roadmap split)

The strategy doc was diagnosed as combining strategy with roadmap content; the maintainer asked to split them. STRATEGY.md now carries strategy-only content (diagnosis at altitude, bets, guiding policy, execution principles); ROADMAP.md (new) carries the time-ordered work (where we are now, near-term, themes for v0.6+). The diagnosis was sharpened from a narrow bug-class framing to a multi-year integration-gap framing per Rumelt's "good strategy" traits (clear diagnosis, chosen battlefield, explicit trade-offs, reinforcing actions, falsifiability). Pre-split state preserved at git tag `strategy-pre-gaps-rewrite`. Precedent: 2026-05-19 STRATR-02 spine reframe and 2026-05-16 STRAT-* → VIS-* + STRATR-* reframe.

| Old ID | Disposition |
|--------|-------------|
| STRATR-02 (5-section Rumelt-style spine: `What we're solving` / `Our bets` / `Where we are now` / `What's next` / `Execution principles`; ≥ 5 grep matches; `### Near-term` + `### Themes for v0.6+` subsections under `## What's next`) | Amended in-place: STRATR-02 (4-section strategy-only spine: `What we're solving` / `Our bets` / `Guiding policy` / `Execution principles`; ≥ 4 grep matches). Diagnosis sharpened to multi-year integration-gap framing. `## Our bets` gains a closing paragraph showing how the bets reinforce each other. `## Guiding policy` (new) replaces "Where we are now" + "What's next" — carries prioritize / downprioritize / falsifiability content. |
| STRATR-03 (4 themes under `### Themes for v0.6+` in STRATEGY.md) | Moved (no substantive change): the four themes (Security Hardening / Preset+Profile / Broader catalog / Public engagement) and their sequencing rationales relocate to `docs/ROADMAP.md` § `### Themes for v0.6+`. STRATR-03 grep verifies against ROADMAP.md going forward; the STRATR-07 acceptance includes the ≥ 4 sequencing-rationale check. |
| STRATR-06 (voice-rule grep gate on STRATEGY.md only) | Amended in-place: STRATR-06 (voice-rule grep gate on STRATEGY.md AND ROADMAP.md). Same regex; both files included as gate targets. |
| (none — additive) | New STRATR-07: `docs/ROADMAP.md` exists at the repo path. ≤ 6 KB. Carries `## Where we are now` + `## What's next` (with `### Near-term` + `### Themes for v0.6+` subsections; ≥ 4 themes with `**Sequencing rationale:**` lines). `> Last reviewed:` blockquote at the top. Voice-rule grep gate per STRATR-06. |

## Superseded Items (2026-05-24 Phase 17 scope re-cut)

The Phase 17 SITE-* requirements were re-cut at phase-discuss time on
2026-05-24 to "minimum-viable contradiction removal." The original spec
aggressively restructured the page (`#features` → `#pillars` with status
badges, new `#install` section with curl snippet, footer doc-link push,
deploy-time install-snippet drift check, mobile-screenshot PR ritual).
The maintainer re-scoped to contradiction-removal only — the 8-card grid
stays, copy inside contradicting cards is rewritten in place, no `#install`
snippet lands, no footer doc-links, no nav `Vision` link, no PR screenshot
ritual. The under-radar posture from STRATEGY.md `## Guiding policy`
(downprioritize "growing surface area before the current gap is closed")
is the governing decision; deferred items go to `<deferred>` in 17-CONTEXT.md.
Precedent: Phase 15 STRAT-* → VIS-* + STRATR-* reframe (2026-05-16),
Phase 16 STRATR-02 spine reframe (2026-05-19), Phase 16 execution-principles
rewrite + STRATR-01 size bump (2026-05-23), and Phase 16 strategy/roadmap
split (2026-05-23 Round 2). SITE-12 (Phase-close audit + milestone-close
gate) is added in the same window — its substance was the trailing
success-criterion of the original Phase 17 entry; promoted to a numbered
requirement here so the AUDIT can cite it.

| Old ID | Disposition |
|--------|-------------|
| SITE-01 (hero rewrite carries delivered-fact line + forward-looking line; voice rule applies) | Amended in-place: SITE-01 (hero value-prop is rewritten so the string `purpose-built Linux distribution` no longer appears; `grep -c 'purpose-built Linux distribution' index.html` returns 0). Hero copy aligns with `docs/VISION.md` mission line ("Linux that gives coding agents a stable place to run — without you having to set it up."); SITE-06 voice-rule grep continues to enforce voice on the rewritten copy. The two-line "delivered-fact + forward-looking" structure was dropped in favour of a single-line vision-flavoured value-prop because the under-radar posture (STRATEGY.md `## Guiding policy`) means no shipped-version cite belongs in the hero. |
| SITE-02 (8-card `#features` grid replaced with 2-card `#pillars`; ≤ 3-sentence card body + `Learn more →` doc-link per card) | Superseded. The 8-card grid is preserved; the five contradicting cards are rewritten in place. New grep gate: `grep -cE 'apt install claude-code\|QEMU VM images\|Docker micro-VMs\|in distro repos\|distro repositories' index.html` returns 0. The `#features` → `#pillars` restructure + per-card doc-links was an information-architecture move; the IA is shippable as-is once the copy stops contradicting the plugin reality. Closes via the new SITE-02 grep gate + the explicit decision recorded in 17-AUDIT.md. |
| SITE-03 (status badges `[SHIPPED v0.3.0]` + `[v0.6+ ROADMAP]` per pillar card) | Superseded. No `#pillars` section → no pillar cards → no badges to apply. Closes via SITE-02 supersession + the explicit "stay under radar; no shipped-version cite in hero / cards" decision recorded in 17-AUDIT.md. |
| SITE-04 (reframe or remove `#comparison`; align with STRATEGY.md `## Where we are now`) | Kept, narrowed: SITE-04 (reframe path locked; `#comparison` block is preserved as three blocks anchored to the canonical bug class — `sudo npm install -g` EACCES + recursive-shim breakage — and the curated-combo bet per STRATEGY.md `## What we're solving`). Existing grep gate `grep -cE 'AgentLinux vs (Docker\|VM\|micro-VM)' index.html` returns 0 carries forward unchanged. |
| SITE-05 (new `#install` section with curl snippet + SHA256 verify line) | Superseded. No `#install` section lands this phase. The README curl snippet remains the canonical install reference; the site stays under-radar. Closes via the explicit decision recorded in 17-AUDIT.md. |
| SITE-06 (voice-rule grep gate on rendered HTML; zero matches required — HARD GATE) | Kept unchanged. Voice-rule grep gate continues to enforce on `index.html`: `grep -nE 'AgentLinux (benchmarks\|measures\|defends\|protects\|prevents\|hardens)\b' index.html` returns zero matches. HARD GATE per VIS-07 / STRATR-06 precedent. |
| SITE-07 (footer doc-links to VISION/STRATEGY/STABILITY-MODEL/decisions; nav `Vision` link) | Superseded. No footer doc-links land this phase; no nav `Vision` link. Under-radar posture from STRATEGY.md `## Guiding policy` (downprioritize public engagement until critical mass) drives the deferral. Closes via the explicit decision recorded in 17-AUDIT.md. |
| SITE-08 (OG / Twitter meta tags rewritten; no `purpose-built Linux distribution` language) | Kept. `og:title`, `og:description`, `twitter:title`, `twitter:description` rewritten this phase to reflect the plugin framing; same grep gates as the original. |
| SITE-09 (OG image SVG → PNG; 1200×630; SVG preserved as source-of-truth) | Kept. `assets/og-image.png` rendered (rsvg-convert / magick / inkscape at the build host's discretion); `assets/og-image.svg` preserved; `og:image` + `twitter:image` meta tags repointed to `.png`. Closes the v0.1.0 known issue. |
| SITE-10 (deploy-time install-snippet drift check wired into `.github/workflows/deploy.yml`) | Closed N/A. The conditional path already in the spec applies: no `#install` snippet on the site (per SITE-05 supersession) → no drift to check. `.github/workflows/deploy.yml` is untouched this phase. |
| SITE-11 (PR body for the website-refresh PR includes mobile + narrow-viewport screenshots ≤ 375 px wide of every changed section) | Superseded. The PR review pass (technical-writer + fact-checker + ai-deslop per CLAUDE.md `## Review Loop` HTML row) is sufficient. Closes via the explicit decision recorded in 17-AUDIT.md. |
| (none — additive) | New SITE-12: Phase-close audit `.planning/phases/17-website-refresh-agentlinux-org/17-AUDIT.md` cites every SITE-XX evidence (KEEP / AMEND / SUPERSEDED / N/A dispositions); gate emits GREEN. Milestone-close gate (v0.3.3) also fires from this phase — Phase 17 is the last v0.3.3 phase, so the audit closes the milestone-coverage gate alongside its own phase-close gate. The audit-file path uses the SDK-derived directory slug (`16-website-refresh-agentlinux-org`), not the abbreviated form in the original SITE-06 / SITE-10 / SITE-12 spec language (`16-website-refresh`). |

Net active SITE requirements after the 2026-05-24 amendment: SITE-01 (amended), SITE-04 (narrowed), SITE-06 (kept; HARD GATE), SITE-08 (kept), SITE-09 (kept), SITE-12 (new). Six active, five superseded, one N/A (SITE-10). Phase-16 traceability table (line 172-182 above) reads forward against this disposition.

## Deferred Items

- **`/gsd-complete-milestone` template amendment** (Pitfall #12 / #23) — adds a "Vision doc + Strategy doc reviewed" step that updates pillar Today / Direction sections at every milestone close. Process change to GSD itself; flagged for the v0.3.3 retrospective.
- **CI lint that warns if VISION.md or STRATEGY.md `Last reviewed:` header is older than the latest release tag by >90 days** — defer until the cadence binding is in place.
- **Bidirectional ADR back-references** — ADR-011 forward-reference to VISION.md (recommended in original SUMMARY.md §6 as optional). Defer unless VIS-08 author finds it valuable.
