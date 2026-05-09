# Roadmap: AgentLinux v0.3.3 — Agenda Redefinition

**Milestone:** v0.3.3 Agenda Redefinition
**Started:** 2026-05-09
**Triggered by:** Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7)
**Phase numbering:** Continues temporally from v0.4.0 (last phase 11) → v0.3.3 starts at **Phase 12**. The version number reverted from v0.4.0 → v0.3.3 per user re-numbering, but phase numbering follows real chronology so phase directories are unique. v0.3.0 directories (`.planning/phases/01-*..06-*`) and v0.4.0 directories (`.planning/phases/07-*..11-*`) remain in place; v0.3.3 phases land at `.planning/phases/12-*..15-*` alongside them.

## Overview

v0.3.3 broadens AgentLinux's framing from a single-pillar product (separated, correctly-owned agent environment — the v0.3.0 core) to a multi-pillar product whose pillar count and contents are **decided by this milestone's exploration phases**. The deliverable is *framing* — a canonical strategy document, an ADR, refreshed downstream docs, and a refreshed public landing page — not new product capabilities.

The critical shape of this roadmap is dictated by three milestone-context constraints that override the synthesizer's first-cut suggestions:

1. **Pillar count is not pre-decided.** AL-7 proposed three pillars (env + stability + security). Phase 13's verdict on "is security a pillar?" decides whether the strategy doc lands with 2 or 3 pillars. Phases 14+ consume Phase 13's output; they do not pre-assume a count.
2. **Exploration phases come FIRST.** Phases 12 and 13 are exploration/decision phases that produce written conclusions docs (`docs/exploration/PILLAR-*-NOTES.md`). The strategy-doc authoring phase (Phase 14) consumes those conclusions. Inverting this order would force the strategy doc to be re-rewritten after-the-fact, which is the failure mode this milestone exists to prevent.
3. **Phase 12 → Phase 13 is sequential, not parallel.** User direction: "first dig into Pillar 2 ... then do the same with Pillar 3 ... then try to understand priority." Pillar 2 is the user's stated top priority and is explored first; pillar 3 (security) is treated as a candidate and explored after.

The roadmap lands at **4 phases** (12 → 13 → 14 → 15), matching the `coarse` granularity setting in `.planning/config.json` (3-5 phases). The synthesizer's §10 recommendation to keep STRAT + DOC inside a single Phase 14 is honored: splitting them would re-create the exact PITFALLS.md #22 risk this milestone is designed to mitigate (strategy doc lands without updating downstream surfaces). Internal plan splits inside Phase 14 separate STRAT-authoring from DOC-propagation; both close before Phase 14 emits GREEN.

Key locked decisions honored by this roadmap:
- The strategy doc (`docs/STRATEGY.md`) is a single Markdown file at the repo path locked by research §1 L3-L4 — not a `docs/strategy/` tree, not a canvas image, not embedded in README.
- The Sourcegraph "Strategy Page" template + Rumelt's kernel + three named inserts (Geoffrey Moore positioning, Amazon-style Tenets, Roman Pichler Vision Board) are the framework spine; Phase 14 fills in, does not re-decide.
- Voice rule (delivered-fact vs forward-looking) is enforced by **automated grep gate** on `docs/STRATEGY.md` AND on the rendered `index.html` per PITFALLS.md #6 / #14. Aspirational drift is the single most dangerous v0.3.3 pattern; the grep gate is the structural defense.
- DOC-05 is **conditional** on EXPL-02's verdict (only fires if pillar 3 survives as a full pillar). Phase 14's success criteria handle the conditional cleanly: if pillar 3 dropped, DOC-05 closes as N/A with the decision recorded; if pillar 3 surviving, the forward-reference exists in ADR-012.
- Documentation evidence (file paths, line ranges, commit hashes, grep transcripts, screenshots) is the primary verification artifact for this milestone — most v0.3.3 work is documentation, not behavior. The TST-07 phase-close discipline carries over via per-phase `<phase-NN>-AUDIT.md` files that cite the evidence per requirement.
- The bats / Docker / QEMU harness from v0.3.0 stays green throughout; a regression there blocks the milestone but no new bats are required.

## Phases

**Phase Numbering:**
- Integer phases (12, 13, 14, 15): Planned milestone work, executed in numeric order
- Decimal phases (e.g., 13.1) reserved for urgent insertions discovered during the milestone (precedent: v0.3.0 Phase 5.1)

- [ ] **Phase 12: Pillar 2 Exploration** — Dig into the user-prioritized pillar 2 (stability + time-to-productive — automation of package installations + problem reconciliations across upstream drift). Produce `docs/exploration/PILLAR-2-NOTES.md` with a Decision summary section authoritative for Phase 14: pillar name, ≥2 table-stakes commitments, ≥1 differentiator (may be empty if intentionally so), ≥2 explicit non-goals, "Today / Direction" content seed, `next-milestone` priority tag reaffirmed (or revisited).
- [ ] **Phase 13: Pillar 3 Candidate Exploration** — Treat security as a *candidate* pillar; explore the post-Shai-Hulud / OWASP-LLM-Top-10-v2025 / Lethal-Trifecta landscape; produce `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` whose first-section verdict is one of (a) yes full pillar, (b) fold into pillar 2 sub-concern, (c) cross-cutting concern, (d) explicitly out-of-scope. If verdict ∈ {a, b, c}: Decision summary names committed table-stakes, differentiators, non-goals, recommended priority tag.
- [ ] **Phase 14: Strategy Doc + ADR-015 + Downstream Surface Updates** — Author `docs/STRATEGY.md` against the Sourcegraph spine + three named inserts; consume Phase 12 + Phase 13 outputs verbatim into the Pillars section; produce ADR-015 (Three-pillar product framing) alongside; propagate the framing in the same milestone window to README + CONTRIBUTING + .planning/PROJECT.md + docs/STABILITY-MODEL.md + (conditionally) docs/decisions/012-agent-user-full-sudo.md. Voice-rule grep gate enforced on STRATEGY.md as the phase-close gate.
- [ ] **Phase 15: Website Refresh (agentlinux.org)** — Reframe `index.html` (currently two pivots stale) to mirror the strategy doc's pillar shape (mise.jdx.dev IA pattern). Replace `#features` 8-card grid with `#pillars` N-card section carrying status badges; reframe or remove `#comparison`; rewrite hero + OG/Twitter meta tags; convert OG image SVG → PNG (closes v0.1.0 known issue); add `#install` snippet + deploy-time anti-drift check; voice-rule grep gate on rendered HTML; mobile screenshots in PR body.

## Phase Details

### Phase 12: Pillar 2 Exploration
**Goal**: Decide what AgentLinux's pillar 2 actually commits to — what value it brings (e.g. package-install automation, problem reconciliation across upstream drift, curated combo testing, observability), what scope is in/out, what AgentLinux would actually measure, which named precedents from research it draws on. Produce a written verdict that Phase 14 can lift verbatim into `docs/STRATEGY.md` Pillar 2 without re-deciding.
**Depends on**: Nothing (first v0.3.3 phase; previous milestone v0.4.0 fully closed)
**Requirements**: EXPL-01
**Success Criteria** (what must be TRUE):
  1. File `docs/exploration/PILLAR-2-NOTES.md` exists at that exact path. The file body is ≥ 2 KB and ≤ 12 KB (substantive but not unbounded). — EXPL-01.
  2. The file's body cites named references drawn from `.planning/research/SUMMARY.md` §4 + `.planning/research/FEATURES.md` — at minimum: terminal-bench, Multi-Docker-Eval, τ-bench `pass^k`, the time-to-productive vs SWE-bench-Verified honesty rule, Helicone OR Langfuse for observability. `grep -E '(terminal-bench|Multi-Docker-Eval|tau-bench|pass\^k|time-to-productive|SWE-bench|Helicone|Langfuse)' docs/exploration/PILLAR-2-NOTES.md` returns ≥ 5 distinct hits. — EXPL-01.
  3. The file ends with a `## Decision summary` section (heading literal — Phase 14's grep depends on this anchor). The section names the pillar, lists ≥ 2 table-stakes commitments, ≥ 1 differentiator (may be the literal text "(none — intentional)" if the discussion lands there), ≥ 2 explicit non-goals, and a "Today / Direction" content seed. — EXPL-01.
  4. The Decision summary explicitly reaffirms the `next-milestone` priority tag for pillar 2 (or explicitly re-opens the user's stated direction with a one-line rationale). The literal string `next-milestone` appears in the section. — EXPL-01.
  5. Phase-close audit `.planning/phases/12-pillar-2-exploration/12-AUDIT.md` cites the file path + the line range of the Decision summary section + the grep transcript above; gate emits GREEN.
**Plans**: estimated 1 plan
- [ ] 12-01-PLAN.md — Author `docs/exploration/PILLAR-2-NOTES.md` from research raw material; produce Decision summary; phase-close audit (EXPL-01)

### Phase 13: Pillar 3 Candidate Exploration
**Goal**: Decide whether security is a pillar at all, and if so what it commits to. Treat the AL-7-proposed pillar 3 (security hardening) as a *candidate*. Produce a written verdict that Phase 14 can lift verbatim into either (a) `docs/STRATEGY.md` Pillar 3 + `## Pillar priority` subsection + Appendix B "Security Hardening" theme, OR (b) the strategy doc's Pillar 2 sub-concerns / cross-cutting Guiding Principles, OR (c) the strategy doc's `What we're explicitly *not* working on` list — without re-deciding at authoring time.
**Depends on**: Phase 12 (sequential per user direction — pillar 2 is dug into first; pillar 3 second; priority is then understood from both)
**Requirements**: EXPL-02
**Success Criteria** (what must be TRUE):
  1. File `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` exists at that exact path. The file body is ≥ 2 KB and ≤ 12 KB. — EXPL-02.
  2. The file's FIRST section is a `## Verdict` heading (literal, anchor for Phase 14) declaring exactly one of: (a) yes, security is a full pillar; (b) no, fold into pillar 2 as a sub-concern; (c) no, address as cross-cutting concern (like CI/CD); (d) no, explicitly out-of-scope. The chosen verdict appears as a single bolded line within the section so a downstream `grep -E '\\*\\*Verdict:' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` returns exactly one match. — EXPL-02.
  3. The file body cites named references drawn from `.planning/research/SUMMARY.md` §5 + `.planning/research/FEATURES.md` — at minimum: OWASP LLM Top 10 v2025, Lethal Trifecta OR Agents Rule of Two, ≥ 2 named attacks from {Shai-Hulud, chalk/debug, TrustFall, Cline-via-markdown}, ≥ 2 named defenses from {npm provenance, SLSA, cosign, Anthropic devcontainer, bubblewrap, capability-scoped sudoers}, the ADR-012 NOPASSWD tension. `grep -cE '(OWASP|Lethal Trifecta|Rule of Two|Shai-Hulud|chalk|TrustFall|Cline|provenance|SLSA|cosign|bubblewrap|ADR-012)' docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` returns ≥ 7. — EXPL-02.
  4. The file ends with a `## Decision summary` section (heading literal). Contents depend on the Verdict: if (a/b/c): committed table-stakes (≥ 2), differentiators (≥ 1, may be "(none — intentional)"), explicit non-goals (≥ 2), recommended priority tag (`next-milestone` or `opportunistic`); if (d): single-line rationale + the explicit recommendation that DOC-05 close as N/A. — EXPL-02.
  5. Phase-close audit `.planning/phases/13-pillar-3-exploration/13-AUDIT.md` cites the file path + the line range of the `## Verdict` section + the line range of the `## Decision summary` section + the grep transcripts; gate emits GREEN. The audit also records the verdict in a single line at the top so Phase 14's planner can read it in one grep.
**Plans**: estimated 1 plan
- [ ] 13-01-PLAN.md — Author `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` from research raw material; produce Verdict + Decision summary; phase-close audit (EXPL-02)

### Phase 14: Strategy Doc + ADR-015 + Downstream Surface Updates
**Goal**: Land the canonical product-strategy document (`docs/STRATEGY.md`), record the framing decision in ADR-015, and propagate the new framing to every downstream documentation surface — all in the same milestone window so a future visitor reading any of {README, CONTRIBUTING, PROJECT.md, STABILITY-MODEL.md, ADR-012, STRATEGY.md} sees the same coherent N-pillar story without contradictions or stale references. Voice-rule grep gate enforced as a phase-close hard gate; aspirational drift is the single most dangerous failure mode and is structurally prevented, not just "reviewed for".
**Depends on**: Phase 12 (consumes EXPL-01 Decision summary verbatim into Pillar 2) + Phase 13 (consumes EXPL-02 Verdict to set N-pillar count and EXPL-02 Decision summary verbatim into Pillar 3 — or omits Pillar 3 entirely if Verdict was (b/c/d))
**Requirements**: STRAT-01, STRAT-02, STRAT-03, STRAT-04, STRAT-05, STRAT-06, STRAT-07, STRAT-08, STRAT-09, STRAT-10, STRAT-11, STRAT-12, STRAT-13, DOC-01, DOC-02, DOC-03, DOC-04, DOC-05
**Success Criteria** (what must be TRUE):
  1. `docs/STRATEGY.md` exists at the exact repo path (single Markdown file, NOT a `docs/strategy/` tree, NOT embedded in README). File size ≤ ~10 KB on first cut (target 4–8 KB). `wc -c docs/STRATEGY.md` ≤ 10240. — STRAT-01.
  2. The doc's spine matches the Sourcegraph "Strategy Page" template. `grep -nE '^## (Mission|The [a-z]+ pillars|Guiding principles|Where we are now|Strategy and plans|Trade-offs|Appendix A|Appendix B)' docs/STRATEGY.md` returns ≥ 7 matches in the prescribed order; `grep -nE '^### Positioning' docs/STRATEGY.md` returns ≥ 1 match (Geoffrey Moore form). — STRAT-02.
  3. The Pillars section contains exactly the pillar count decided in EXPL-02. Specifically: `grep -cE '^### Pillar [0-9]+' docs/STRATEGY.md` returns either 2 (if EXPL-02 Verdict was b/c/d — pillars 1+2 only) or 3 (if EXPL-02 Verdict was a — pillars 1+2+3). Pillar 1 always present (env, foundational); Pillar 2 always present (contents from EXPL-01 Decision summary); Pillar 3 present iff EXPL-02 Verdict was (a). Each pillar section contains both a `#### Today` and a `#### Direction` subsection (per L9 in SUMMARY.md). — STRAT-03.
  4. A `### Pillar priority` subsection inside Pillars exists and tags every pillar present with one of `foundational` / `next-milestone` / `opportunistic`. Pillar 1 is tagged `foundational`; Pillar 2 is tagged `next-milestone`; Pillar 3 (if present) is tagged per EXPL-02. `grep -E '(foundational|next-milestone|opportunistic)' docs/STRATEGY.md` returns ≥ 2 distinct tags (or ≥ 3 if Pillar 3 survived). — STRAT-04.
  5. The `## Guiding principles` section contains 4–7 principles, each as a declarative sentence + a one-line "why this matters" + a Markdown back-link to a grounding artefact (an ADR, a bats convention, a GSD-workflow rule). `grep -cE '^### ' docs/STRATEGY.md` against the principles subsection returns 4..7. — STRAT-05.
  6. The `## Strategy and plans → ### What we're explicitly *not* working on` subsection lists ≥ 5 entries; each entry has a one-line rejection reason that goes beyond "scope creep". — STRAT-06.
  7. The `## Trade-offs / rejected alternatives` section records ≥ 3 considered-and-rejected framings, including at minimum "stay single-pillar (rejected)" + the framework-spine alternatives (Lean Canvas / BMC / OKRs / PR-FAQ) each rejected with a concrete reason. — STRAT-07.
  8. `## Appendix A — One-page Vision Board` exists as a Markdown table with at least 4 rows (Target Group / Needs / Product / Business Goals — Roman Pichler form). — STRAT-08.
  9. `## Appendix B — Roadmap themes` lists 2–4 forward-looking themes for v0.6+ and contains a `### Sequencing rationale` subsection. — STRAT-09.
  10. The first non-blank line after the H1 is a `> Last reviewed:` blockquote. `head -5 docs/STRATEGY.md | grep -E '^> Last reviewed: 2026-05-09'` returns 1 match. — STRAT-10.
  11. **Voice-rule grep gate (HARD GATE).** `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md` returns zero matches in any pillar-2 or pillar-3 `Direction` subsection. The exact command + its empty output is committed verbatim to `.planning/phases/14-strategy-doc-and-downstream/14-AUDIT.md`. Phase-close gate fails if the grep returns even one match. — STRAT-11.
  12. Cross-link map populated. Outbound: every pillar / principle / rejection in STRATEGY.md that grounds in an ADR or STABILITY-MODEL.md or research file carries a Markdown link. Inbound: each of `README.md` (About + Links), `CONTRIBUTING.md`, `.planning/PROJECT.md` (Core Value section), `docs/STABILITY-MODEL.md` (Related), and (conditional on EXPL-02 Verdict (a)) `docs/decisions/012-agent-user-full-sudo.md` carries a back-pointer to STRATEGY.md. The Phase-14 audit lists each changed file with the line range of the back-pointer edit. — STRAT-12.
  13. `docs/decisions/015-agenda-redefinition.md` (ADR-015) lands in the same milestone window as STRATEGY.md (same Phase 14 commit window). The ADR contains: `Status: Accepted`, `Context` (the AL-7 framing question + why a single-pillar framing was getting in the way), `Decision` (the N-pillar landing — citing the EXPL-02 verdict), ≥ 3 considered-and-rejected alternatives (e.g. "stay single-pillar"; "pivot security-first"; "four-or-more pillars including observability" — Phase 14 picks the actually-weighed three), `Consequences`, and a back-link to AL-7 + STRATEGY.md. `grep -cE '^## (Status|Context|Decision|Considered alternatives|Consequences)' docs/decisions/015-agenda-redefinition.md` returns ≥ 5. — STRAT-13.
  14. **DOC propagation.** Each of these files shows a commit in the Phase 14 window touching the named section: `README.md` (About + Links sections gain pillar-naming sentence + Strategy link — DOC-01); `CONTRIBUTING.md` ("Why this project exists" paragraph + pillar-status callout — DOC-02); `.planning/PROJECT.md` (Core Value + Current Milestone sections cross-reference STRATEGY.md; Out-of-Scope reflects EXPL-01/02-surfaced non-goals — DOC-03); `docs/STABILITY-MODEL.md` (Related section with back-link to STRATEGY.md Pillar 2 — DOC-04). Phase-close audit cites the commit hash + line range for each. — DOC-01..04.
  15. **DOC-05 conditional close.** If EXPL-02 Verdict was (a) — pillar 3 is a full pillar — `docs/decisions/012-agent-user-full-sudo.md` (ADR-012) gains a forward-reference to ADR-015 + STRATEGY.md Pillar 3 documenting the NOPASSWD-vs-security-pillar tension and the milestone where the tension is intended to be resolved (`grep -E '(ADR-015|STRATEGY.md)' docs/decisions/012-agent-user-full-sudo.md` returns ≥ 1 hit). If EXPL-02 Verdict was (b/c/d) — pillar 3 did NOT survive — DOC-05 closes as N/A in the audit with a one-line decision recording the verdict + the explicit "no edit needed because pillar 3 did not survive Phase 13" rationale; the audit explicitly cites EXPL-02's `## Verdict` line. — DOC-05.
  16. Phase-close audit `.planning/phases/14-strategy-doc-and-downstream/14-AUDIT.md` cites every STRAT-XX + DOC-XX evidence (file path / line range / commit hash / grep transcript per requirement); gate emits GREEN.
**Plans**: estimated 2 plans
- [ ] 14-01-PLAN.md — Author `docs/STRATEGY.md` from Sourcegraph spine + three named inserts; consume EXPL-01 Decision summary into Pillar 2 + EXPL-02 Decision summary into Pillar 3 (if surviving); author ADR-015 alongside; voice-rule grep gate verified locally (STRAT-01..13)
- [ ] 14-02-PLAN.md — Downstream surface updates: README + CONTRIBUTING + PROJECT.md + STABILITY-MODEL.md back-pointers; conditional ADR-012 forward-reference (or N/A close); Phase 14 phase-close audit (DOC-01..05)

### Phase 15: Website Refresh (agentlinux.org)
**Goal**: Repair the agentlinux.org landing page so its framing matches the post-Phase-14 strategy doc, the v0.3.0/v0.4.0 product reality, and the current pillar count. The site is currently two pivots stale (hero says "purpose-built Linux distribution"; features advertise QEMU/Docker micro-VM distribution) — refreshing it is required regardless. Voice-rule grep gate applies to the rendered HTML, with the same hard-gate semantics as Phase 14 STRAT-11. Visual redesign is explicitly out of scope; the dark JetBrains Mono aesthetic + crab mascot stay.
**Depends on**: Phase 14 (so the site can link to a stable `docs/STRATEGY.md` URL with a stable pillar count)
**Requirements**: SITE-01, SITE-02, SITE-03, SITE-04, SITE-05, SITE-06, SITE-07, SITE-08, SITE-09, SITE-10, SITE-11
**Success Criteria** (what must be TRUE):
  1. `index.html` hero section is rewritten. The string "purpose-built Linux distribution" is gone (`grep -c 'purpose-built Linux distribution' index.html` returns 0). The hero carries a delivered-fact line (citing v0.3.0/v0.4.0 reality) AND a forward-looking line whose grammatical subject is "we" / "our roadmap" / explicit milestone tag (per voice rule). — SITE-01.
  2. The 8-card `#features` grid is replaced with a `#pillars` section. `grep -cE 'id="(pillars|features)"' index.html` returns exactly 1 hit on `id="pillars"` and 0 hits on `id="features"`. The `#pillars` section contains exactly N cards matching `### Pillar N` count in `docs/STRATEGY.md` (i.e. 2 if EXPL-02 Verdict was b/c/d, 3 if (a)). Each card body is ≤ 3 sentences + a "Learn more →" link to `docs/STRATEGY.md#pillar-N` anchor (or the GitHub-rendered equivalent). — SITE-02.
  3. Each pillar card carries a visible status badge. `grep -cE '\\[(SHIPPED v0\\.3\\.0|v0\\.6\\+ ROADMAP|COMING SOON — v0\\.6\\+)\\]' index.html` returns N hits matching the pillar count. Pillar 1's badge reads `[SHIPPED v0.3.0]` (or equivalent shipped marker); pillars 2 / 3 carry `[v0.6+ ROADMAP]` (or equivalent forward marker). Badge style is consistent across cards (single CSS class or single inline style pattern). — SITE-03.
  4. The `#comparison` block is reframed or removed. If reframed: it no longer mentions QEMU/Docker micro-VM distribution as alternatives to AgentLinux (`grep -cE 'AgentLinux vs (Docker|VM|micro-VM)' index.html` returns 0); the new content aligns with `docs/STRATEGY.md` "Where we are now". If removed: `grep -c 'id="comparison"' index.html` returns 0. Either is acceptable. — SITE-04.
  5. A new `#install` section exists OR a deliberate decision to omit is recorded in the audit. If present: `grep -cE 'curl -fsSL' index.html` returns ≥ 1; the snippet includes a SHA256 verify line. — SITE-05.
  6. **Voice-rule grep gate on rendered HTML (HARD GATE).** `grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html` returns zero matches anywhere on the page. The command + its empty output is committed verbatim to `.planning/phases/15-website-refresh/15-AUDIT.md`. Phase-close gate fails if the grep returns even one match. — SITE-06.
  7. Footer adds links to `docs/STRATEGY.md`, `docs/STABILITY-MODEL.md`, and `docs/decisions/` alongside the existing repo / releases links. The top nav also gains a `Strategy` link. `grep -cE 'href="[^"]*docs/STRATEGY' index.html` returns ≥ 2 hits (one in nav, one in footer). — SITE-07.
  8. OG / Twitter meta tags rewritten. `grep -cE 'property="og:(title|description)"' index.html` returns ≥ 2; `grep -c 'purpose-built Linux distribution' index.html` returns 0 (already enforced by SITE-01); the new descriptions reflect the broadened positioning. — SITE-08.
  9. OG image converted SVG → PNG. `ls assets/*.png 2>/dev/null | xargs -I{} file {}` shows a PNG sized for OG conventions (1200×630 typical); the SVG is preserved alongside as the source-of-truth. `grep -cE 'property="og:image" content="[^"]*\\.png"' index.html` returns ≥ 1. Closes the v0.1.0 known issue. — SITE-09.
  10. Deploy-time install-instruction drift check. `.github/workflows/deploy.yml` (or equivalent) contains a step that fails the deploy if the install-snippet version stamp in `index.html` diverges from `README.md`'s `<!-- VERSION_START --><!-- VERSION_END -->` block. Same shape as the existing Pattern 5 anti-drift check on `install.sh`. If `index.html` does NOT carry an install snippet per SITE-05, this requirement closes as N/A in the audit with a one-line decision. — SITE-10.
  11. PR body for the website-refresh PR includes mobile + narrow-viewport screenshots (≤ 375 px wide) of every changed section, demonstrating the responsive design holds. Audit records the PR URL + the screenshot count (≥ 1 per changed section). — SITE-11.
  12. Phase-close audit `.planning/phases/15-website-refresh/15-AUDIT.md` cites every SITE-XX evidence; gate emits GREEN. Milestone-close gate also fires from this phase (last v0.3.3 phase).
**Plans**: estimated 1 plan (split possible at phase-discuss time if SITE-09 PNG conversion or SITE-10 drift wiring proves heavier than expected)
- [ ] 15-01-PLAN.md — `index.html` IA restructure (#pillars replacing #features, hero rewrite, footer + nav additions, OG/Twitter rewrite); OG image PNG conversion + commit; deploy-time anti-drift check wiring; voice-rule grep gate run + committed; mobile screenshots in PR body; Phase 15 phase-close audit + milestone-close gate (SITE-01..11)
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 12 → 13 → 14 → 15. Phase 12 → Phase 13 is a hard sequencing constraint (user direction); Phase 14 depends on both. Phase 15 depends on Phase 14.

| Phase | Plans Estimated | Status | Notes |
|-------|-----------------|--------|-------|
| 12. Pillar 2 Exploration | 1 | Not started | Produces `docs/exploration/PILLAR-2-NOTES.md` with Decision summary anchor for Phase 14 |
| 13. Pillar 3 Candidate Exploration | 1 | Not started | Produces `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` with `## Verdict` anchor (a/b/c/d) decisive for Phase 14 pillar count + DOC-05 conditional close |
| 14. Strategy Doc + ADR-015 + Downstream Surface Updates | 2 | Not started | Largest phase by req count (18 reqs: 13 STRAT + 5 DOC); plans split STRAT-authoring from DOC-propagation; voice-rule grep gate is the hard gate |
| 15. Website Refresh | 1 | Not started | Depends on stable `docs/STRATEGY.md` URL + locked pillar count; voice-rule grep gate on rendered HTML; OG image SVG→PNG closes v0.1.0 known issue |
| **Total** | **~5 plans** | 0/4 phases done | — |

## Coverage Summary

**Total v0.3.3 requirements:** 31 (2 EXPL + 13 STRAT + 5 DOC + 11 SITE)
**Mapped:** 31 / 31
**Orphaned:** 0
**Duplicated across phases:** 0

> **Note on count discrepancy:** The milestone-context prompt mentions "32 reqs" / "STRAT × 14"; the actual `.planning/REQUIREMENTS.md` lists STRAT-01..STRAT-13 (13 STRAT requirements). The roadmap maps the 13 actually-defined STRAT entries. STRAT-10 is the `Last reviewed:` header requirement (one of the EXPL-01 prose body lines references it as "STRAT-14" — that prose reference is a stale numbering inside REQUIREMENTS.md and is harmless; the STRAT-10 success criterion in Phase 14 covers the actual cadence-binding header). If a STRAT-14 is later added (e.g. for the deferred CI lint or the deferred `/gsd-complete-milestone` template amendment), it lands in Phase 14 alongside the existing STRAT requirements without changing the phase split.

Requirement allocation per phase:

| Phase | Requirements | Count |
|-------|--------------|-------|
| 12 Pillar 2 Exploration | EXPL-01 | 1 |
| 13 Pillar 3 Candidate Exploration | EXPL-02 | 1 |
| 14 Strategy Doc + ADR-015 + Downstream Surface Updates | STRAT-01..STRAT-13, DOC-01..DOC-05 | 18 |
| 15 Website Refresh | SITE-01..SITE-11 | 11 |
| **Total** | | **31** |

## Notes on verification

- Most v0.3.3 work is documentation. Evidence is documentation artifacts under `docs/exploration/PILLAR-*-NOTES.md`, `docs/STRATEGY.md`, `docs/decisions/015-agenda-redefinition.md`, plus per-phase `.planning/phases/<NN>-*/<NN>-AUDIT.md` files. No new bats @tests are required.
- The bats / Docker / QEMU harness from v0.3.0 is **not** the primary verification surface for v0.3.3. It is still required to stay green throughout — a regression there blocks the milestone, but the milestone does not add new bats.
- Phase 15's only "real product code" change is HTML/CSS/JS in `index.html` + `assets/`. The existing GitHub Pages auto-deploy pipeline (v0.1.0) carries it.
- Phase-close gate convention (TST-07-style) carries forward unchanged: every requirement closes with a cited evidence artifact in its phase's AUDIT doc before the gate emits GREEN. For documentation-only requirements the evidence is a file path + line range, a commit hash, or a grep transcript.
- **Voice-rule grep gates (STRAT-11 + SITE-06) are the load-bearing structural defense for the milestone.** They are run as part of the phase-close audit and their command + output is committed verbatim to the audit file. A future visitor can re-run the same grep against any future commit and get the same answer. The grep is the spec.
- **Pillar 3 conditional handling.** Phase 13's `## Verdict` section is the single decision point that drives downstream conditionals: (i) the `### Pillar 3` section in STRATEGY.md exists iff Verdict was (a); (ii) DOC-05 fires (ADR-012 forward-reference) iff Verdict was (a); (iii) the `#pillars` section on the website carries 2 vs 3 cards iff Verdict was (a). All three downstream conditionals key off the same audit-recorded Verdict line — one decision, one verifiable cascade.

## Open Questions for Discuss-Phase

These are open questions to resolve in `/gsd-discuss-phase 12` (and subsequent phases). User-direction-locked answers are noted; remaining open questions to resolve at the named phase-discuss:

- **Phase 12 — pillar 2 contents (in/out):** which of {package-install automation, problem reconciliation across upstream drift, curated combo testing, observability, terminal-bench-style benchmarks} ride inside pillar 2's Decision summary as table-stakes vs differentiators vs non-goals? User direction is "stability + time-to-productive — automation of package installations + problem reconciliations across upstream drift" as the headline; benchmarks are *one possible measurement layer*, not the headline. Phase-discuss locks the exact split.
- **Phase 13 — pillar 3 verdict (a/b/c/d):** the central question of the milestone. User direction (locked at milestone-open): existence and priority decided by Phase 13. No default. Phase-discuss frames the alternatives + rationale; Phase 13 plan execution authors the verdict.
- **Phase 14 — pillar priority (locked partially):** Pillar 1 = `foundational` (locked, settled by v0.3.0 reality); Pillar 2 = `next-milestone` (locked per user direction, reaffirmed in EXPL-01); Pillar 3 (if surviving Phase 13) = `next-milestone` OR `opportunistic`? Resolved at Phase 14 discuss using Phase 13's Verdict + Decision summary.
- **Phase 14 — guiding principles count + list:** Sourcegraph template recommends 4–7. Synthesizer's seed list (5): "Behavior tests are the spec" (ADR-002), "We test exactly what we ship" (ADR-011), "Curated combos, not thin wrappers" (ADR-011 negative space), "No silent drift" (`agentlinux upgrade` contract), "Trust through evidence, not assertion" (provenance). Phase 14 discuss locks the actual list.
- **Phase 14 — DOC-05 conditional close mechanics:** if EXPL-02 Verdict was (b/c/d), is the N/A close acceptable as just an audit line, or does the milestone-close gate want a more explicit artefact (e.g. a one-line PR comment in the Phase 14 PR linking the audit)? Default: audit-line-only is sufficient; revisit if reviewer pushes.
- **Phase 15 — `#install` section presence (SITE-05):** include the curl-pipe-bash + SHA256 verify snippet on the landing page, or keep it minimal and link to README? Decision affects whether SITE-10 (deploy-time anti-drift check) is required or closes as N/A. Synthesizer recommendation: include `#install` so the page is self-contained for the canonical install flow; minimal version (one snippet + link to README for full options) is acceptable.
- **Phase 15 — comparison block treatment (SITE-04):** reframe in place vs delete entirely? Both pass the success criterion. Default: reframe in place (preserves the page's existing IA shape) unless the reframed content is shorter than ~3 sentences, in which case delete. Phase-discuss locks.
- **Jira sub-tasks under AL-7 (post-roadmap):** file 4 sub-tasks (one per phase) under AL-7 now that phase identifiers are stable, per the session-tracker convention in CLAUDE.md? Synthesizer recommendation: yes, file post-roadmap so AL-7 has the phase-level breakdown visible.

---

*Last updated: 2026-05-09 — v0.3.3 ROADMAP authored after parallel-research synthesis + scope correction.*
