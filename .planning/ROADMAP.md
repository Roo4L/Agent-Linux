# Roadmap: AgentLinux v0.3.3 — Agenda Redefinition

**Milestone:** v0.3.3 Agenda Redefinition
**Started:** 2026-05-09
**Triggered by:** Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7)
**Phase numbering:** Continues temporally from v0.4.0 (last phase 11) → v0.3.3 starts at **Phase 12**. The version number reverted from v0.4.0 → v0.3.3 per user re-numbering, but phase numbering follows real chronology so phase directories are unique. v0.3.0 directories (`.planning/phases/01-*..06-*`) and v0.4.0 directories (`.planning/phases/07-*..11-*`) remain in place; v0.3.3 phases land at `.planning/phases/12-*..16-*` alongside them.

## Overview

v0.3.3 broadens AgentLinux's framing from a single-pillar product (separated, correctly-owned agent environment — the v0.3.0 core) to a multi-pillar product whose pillar count and contents are **decided by this milestone's exploration phases**. The deliverable is *framing* — a canonical vision document, a separate strategy/roadmap document, an ADR, refreshed downstream docs, and a refreshed public landing page — not new product capabilities.

The critical shape of this roadmap is dictated by these milestone-context constraints:

1. **Pillar count is not pre-decided.** AL-7 proposed three pillars (env + stability + security). Phase 13's verdict on "is security a pillar?" decided the framing lands with 2 pillars (verdict (b) — fold into pillar 2). Phases 14+ consume that verdict.
2. **Exploration phases come FIRST.** Phases 12 and 13 are exploration/decision phases that produce written conclusions docs (`docs/exploration/PILLAR-*-NOTES.md`). Downstream phases consume those conclusions.
3. **Phase 12 → Phase 13 is sequential.** User direction: pillar 2 dug into first; pillar 3 (security) second.
4. **Vision and strategy are separate documents.** User reframed Phase 14 mid-milestone (2026-05-16): the original Phase 14 bundled vision + strategy + roadmap + framework trade-offs into one `docs/STRATEGY.md` against the Sourcegraph template. New shape: Phase 14 produces `docs/VISION.md` (vision-only — mission, pillars, principles, non-goals); a new Phase 15 produces `docs/STRATEGY.md` (strategy/roadmap — execution rules, sequencing, themes for v0.6+, current focus). Website refresh renumbers from Phase 15 → Phase 16.

The roadmap lands at **5 phases** (12 → 13 → 14 → 15 → 16). Phase 14's reframe + Phase 15 insertion locked 2026-05-16.

Key locked decisions honored by this roadmap:
- `docs/VISION.md` is the canonical "what we want to be" reference for product leadership + AI agents trying to understand the project. Vision-voice only — no roadmap, no execution detail, no framework trade-offs. Target size ≤ 6 KB.
- `docs/STRATEGY.md` is the canonical "how we get there" reference: execution rules (voice rule, behavior-tests-as-spec, evidence-cite discipline), theme sequencing for v0.6+, near-term focus. Lands AFTER Phase 14 so it can reference VISION.md as upstream. Target size ≤ 8 KB.
- Voice rule (delivered-fact vs forward-looking) applies to VISION.md, STRATEGY.md, and the rendered website. Enforced by automated grep gate on each. Aspirational drift is the single most dangerous v0.3.3 pattern.
- DOC-05 closes N/A: Phase 13 verdict (b) means no Pillar 3, no ADR-012 forward-reference edit needed.
- Documentation evidence (file paths, line ranges, commit hashes, grep transcripts) is the primary verification artifact. TST-07 phase-close discipline carries via per-phase `<phase-NN>-AUDIT.md` files.
- The bats / Docker / QEMU harness from v0.3.0 stays green throughout; a regression there blocks the milestone but no new bats are required.

## Phases

**Phase Numbering:**
- Integer phases (12, 13, 14, 15, 16): Planned milestone work, executed in numeric order
- Decimal phases (e.g., 13.1) reserved for urgent insertions discovered during the milestone (precedent: v0.3.0 Phase 5.1)

- [x] **Phase 7: License & Public-Ready Documentation** — MIT license (ADR-013), LICENSE file, README license badge + section, SPDX headers on 16 first-party source files, CONTRIBUTING.md with DCO-equivalent affirmation. ✓ 2026-04-26 (commit `c52b3c1`; 4/4 LIC-XX evidenced; phase-close gate: GREEN; `.planning/phases/07-license-and-public-docs/07-AUDIT.md`).
- [x] **Phase 8: Secret Scanning & History Audit** — gitleaks (1 finding, triaged false positive — OpenNebula API hostname matched `generic-api-key` regex) + trufflehog (0 verified, 0 unverified) + targeted manual audit (8 patterns × 255 commits = 0 matches). SEC-04 closes as no-op (ADR-014). gitleaks gate wired in pre-commit + CI; smoke-test confirms gate fires on contrived secrets. ✓ 2026-04-26 (commit `c94920a`; 5/5 SEC-XX evidenced; phase-close gate: GREEN; `.planning/phases/08-secret-scanning/08-AUDIT.md`).
- [x] **Phase 9: Repository Hygiene & Artifact Cleanup** — 2 branches (no stale, no merged-but-unpurged); zero blobs >500 KB anywhere in history; .gitignore hardened (env/npmrc/credentials/SSH keys/editor cruft/coverage/caches with deliberate allow-lists); `.planning/` retention is deliberate per CLAUDE.md convention. ✓ 2026-04-26 (commit `158e465`; 4/4 CLEAN-XX evidenced; phase-close gate: GREEN; `.planning/phases/09-repo-hygiene/09-AUDIT.md`).
- [x] **Phase 10: Public CI/CD Verification & Branch Protection** — workflow `permissions:` blocks at least-privilege (test.yml gained explicit top-level); `pull_request_target` = 0; fork-PR exfiltration surface = empty. Branch protection on `master` designed and **staged for maintainer apply** via single `gh api -X PUT` command (CIPUB-03; Option A/B documented). CIPUB-04 de facto GREEN from PR #2 + recent nightly runs (<24h). ✓ 2026-04-26 (commit `446c89b`; 4/4 CIPUB-XX evidenced or staged; phase-close gate: GREEN-pending-2-maintainer-tasks; `.planning/phases/10-public-cicd/10-AUDIT.md`).
- [x] **Phase 11: Public Visibility Flip & Smoke Test** — Repository visibility flipped to PUBLIC at 2026-04-26T15:30Z; squash-merged as `c8a2787` on master; branch protection re-applied as Option A (enforce_admins, linear, no force-push, gitleaks status check). Public release published as **`v0.3.1 — Open-Source Flip`** (2026-05-02; the originally-tagged `v0.4.0` was renamed to `v0.3.1` for version-constant lockstep — see release notes). Post-flip smoke (anonymous clone + raw curl-installer fetch + SHA + syntax) green. End-to-end `curl … | sudo bash` install deferred to v0.3.x final-release event. ✓ shipped 2026-05-02 (commit `c8a2787`, tag `v0.3.1`; 4/4 PUB-XX evidenced; phase-close gate: GREEN; `.planning/phases/11-public-flip/11-AUDIT.md`).
- [x] **Phase 12: Pillar 2 Exploration** — Dig into the user-prioritized pillar 2 (stability + time-to-productive). Produce `docs/exploration/PILLAR-2-NOTES.md` with a Decision summary section authoritative for downstream phases: pillar name, ≥2 table-stakes commitments, ≥1 differentiator, ≥2 explicit non-goals, "Today / Direction" content seed, priority tag. (completed 2026-05-10)
- [x] **Phase 13: Pillar 3 Candidate Exploration** — Treat security as a *candidate* pillar; explore the post-Shai-Hulud / OWASP-LLM-Top-10-v2025 / Lethal-Trifecta landscape; produce `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`. Verdict locked at (b): fold into pillar 2 as sub-concern; security is not a separate pillar in v0.3.3. (completed 2026-05-10)
- [ ] **Phase 14: Vision Doc + ADR-015 + Downstream Surface Updates** — Author `docs/VISION.md` as the canonical vision document (mission, two pillars as optimization values, vision-level guiding principles, vision-level non-goals). Author ADR-015 recording the framing decision. Propagate the framing via back-pointers in README, CONTRIBUTING, .planning/PROJECT.md, docs/STABILITY-MODEL.md. DOC-05 closes N/A. Voice-rule grep gate enforced on VISION.md as phase-close hard gate.
- [x] **Phase 15: Strategy + Roadmap Doc** — Author `docs/STRATEGY.md` as the canonical strategy/roadmap document: execution rules (voice rule, behavior-tests-as-spec, evidence-cite discipline, curated-combo testing, no `sudo npm install -g`), theme sequencing for v0.6+ (Security Hardening, preset/profile framework, compat-guarded update flow), current focus. References VISION.md as upstream "what." Voice-rule grep gate enforced. (completed 2026-05-19)
- [x] **Phase 16: Website Refresh (agentlinux.org)** — Reframe `index.html` (currently two pivots stale) to mirror the post-Phase-14 vision (two pillars) + post-Phase-15 strategy. Replace `#features` 8-card grid with `#pillars` 2-card section carrying status badges; reframe or remove `#comparison`; rewrite hero + OG/Twitter meta tags; convert OG image SVG → PNG (closes v0.1.0 known issue); add `#install` snippet + deploy-time anti-drift check; voice-rule grep gate on rendered HTML; mobile screenshots in PR body. (completed 2026-05-24)

## Phase Details

### Phase 12: Pillar 2 Exploration
**Goal**: Decide what AgentLinux's pillar 2 actually commits to. Produce a written verdict that downstream phases lift verbatim.
**Depends on**: Nothing (first v0.3.3 phase; previous milestone v0.4.0 fully closed)
**Requirements**: EXPL-01
**Success Criteria**: see commit history; phase completed 2026-05-10 with `docs/exploration/PILLAR-2-NOTES.md` authoritative.
**Plans**:
- [x] 12-01-PLAN.md — Author `docs/exploration/PILLAR-2-NOTES.md`; produce Decision summary; phase-close audit (EXPL-01)

### Phase 13: Pillar 3 Candidate Exploration
**Goal**: Decide whether security is a pillar at all. Produce a written verdict.
**Depends on**: Phase 12 (sequential per user direction)
**Requirements**: EXPL-02
**Verdict (locked 2026-05-10)**: (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.
**Success Criteria**: see commit history; phase completed 2026-05-10 with `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` authoritative.
**Plans**:
- [x] 13-01-PLAN.md — Author `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`; produce Verdict + Decision summary; phase-close audit (EXPL-02)

### Phase 14: Vision Doc + ADR-015 + Downstream Surface Updates
**Goal**: Land the canonical product-vision document (`docs/VISION.md`), record the framing decision in ADR-015, and propagate the new framing to every downstream documentation surface so a future visitor reading any of {README, CONTRIBUTING, PROJECT.md, STABILITY-MODEL.md, VISION.md} sees the same coherent two-pillar story without contradictions or stale references. Voice-rule grep gate enforced as a phase-close hard gate.
**Depends on**: Phase 12 (consumes EXPL-01 pillar-2 verdict into Pillar 2 framing) + Phase 13 (consumes EXPL-02 verdict to set pillar count = 2)
**Requirements**: VIS-01..VIS-09, DOC-01..DOC-05
**Success Criteria** (what must be TRUE):
  1. `docs/VISION.md` exists at the exact repo path. Single Markdown file, not a `docs/vision/` tree, not embedded in README. File size ≤ 6 KB. `wc -c docs/VISION.md` ≤ 6144. — VIS-01.
  2. The doc's spine reflects vision-only structure: `## Mission` → `### Positioning` → `## The two pillars` → `## Guiding principles` → `## What we're explicitly not`. `grep -nE '^## (Mission|The two pillars|Guiding principles|What we'\''re explicitly not)' docs/VISION.md` returns ≥ 4 matches in the prescribed order; `grep -nE '^### Positioning' docs/VISION.md` returns ≥ 1 match. — VIS-02.
  3. The Pillars section contains exactly 2 pillars (matching the Phase 13 (b) verdict). `grep -cE '^### Pillar [0-9]+' docs/VISION.md` returns exactly 2. Pillars are named by the optimization value (e.g. `### Pillar 1 — Time-to-productive`, `### Pillar 2 — Stability`). No `#### Today` / `#### Direction` subsections inside pillars (vision-doc voice, not status-report voice). — VIS-03.
  4. The `## Guiding principles` section contains 4–6 principles, each as a `### {Principle name}` heading + a short paragraph. Principles are vision-level (identity claims), not execution-level — no "behavior tests are the spec," no "TST-07 phase-close discipline," no process rules. `grep -cE '^### ' docs/VISION.md` against the principles subsection returns 4..6. — VIS-04.
  5. The `## What we're explicitly not` section lists ≥ 4 vision-level non-goals as bulleted items, each with a one-line rationale. Non-goals reflect identity ("not an agent product," "not a sandbox runtime"), not roadmap deferrals. — VIS-05.
  6. The first non-blank line after the H1 is a `> Last reviewed:` blockquote. `head -5 docs/VISION.md | grep -E '^> Last reviewed: 2026-05'` returns 1 match. — VIS-06.
  7. **Voice-rule grep gate (HARD GATE).** `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/VISION.md` returns zero matches. The exact command + its empty output is committed verbatim to `.planning/phases/14-vision-doc-and-downstream/14-AUDIT.md`. Phase-close gate fails on any match. — VIS-07.
  8. Cross-link map populated. Outbound: pillar / principle / non-goal claims in VISION.md that ground in an ADR may carry a Markdown link (light hand — vision-voice keeps most claims abstract). Inbound: each of `README.md` (About + Links), `CONTRIBUTING.md`, `.planning/PROJECT.md` (Core Value section), `docs/STABILITY-MODEL.md` (Related section) carries a back-pointer to VISION.md. Phase-14 audit lists each changed file with the line range of the back-pointer edit. — VIS-08.
  9. `docs/decisions/015-agenda-redefinition.md` (ADR-015) lands in the same milestone window as VISION.md (same Phase 14 commit window). The ADR contains: `Status: Accepted`, `Context` (the AL-7 framing question + why the original single-pillar framing was getting in the way), `Decision` (the two-pillar landing — citing the EXPL-01 + EXPL-02 verdicts; vision-only document separated from strategy/roadmap), ≥ 3 considered-and-rejected alternatives (e.g. "stay single-pillar," "ship vision+strategy+roadmap in one doc per original Phase 14 plan," "pivot security-first to a Pillar 3"), `Consequences` (including the Phase 15 strategy-doc insertion + Phase 15 → Phase 16 renumber of the website-refresh phase), and a back-link to AL-7 + VISION.md. `grep -cE '^## (Status|Context|Decision|Considered alternatives|Consequences)' docs/decisions/015-agenda-redefinition.md` returns ≥ 5. — VIS-09.
  10. **DOC propagation.** Each of these files shows a commit in the Phase 14 window touching the named section: `README.md` (About + Links sections gain pillar-naming sentence + Vision link — DOC-01); `CONTRIBUTING.md` ("Why this project exists" paragraph + pillar-status callout — DOC-02); `.planning/PROJECT.md` (Core Value + Current Milestone sections cross-reference VISION.md; Out-of-Scope reflects EXPL-01/02-surfaced non-goals — DOC-03); `docs/STABILITY-MODEL.md` (Related section with back-link to VISION.md Pillar 2 — DOC-04). Phase-close audit cites the commit hash + line range for each. — DOC-01..04.
  11. **DOC-05 closes N/A.** Phase 13 verdict (b) — pillar 3 did NOT survive. No edit to `docs/decisions/012-agent-user-full-sudo.md` (ADR-012) needed. Phase 14 audit records DOC-05 as N/A with a one-line decision: "no edit needed because pillar 3 did not survive Phase 13"; audit explicitly cites EXPL-02's `## Verdict` line. — DOC-05.
  12. Phase-close audit `.planning/phases/14-vision-doc-and-downstream/14-AUDIT.md` cites every VIS-XX + DOC-XX evidence (file path / line range / commit hash / grep transcript per requirement); gate emits GREEN.
**Plans**: 2 plans
- [ ] 14-01-PLAN.md — Verify committed `docs/VISION.md` against VIS-01..VIS-07 (capture transcripts in `14-01-EVIDENCE.md`); author ADR-015 (VIS-09); reviewer pass (VIS-01..07, VIS-09)
- [ ] 14-02-PLAN.md — Downstream surface updates: README + CONTRIBUTING + PROJECT.md + STABILITY-MODEL.md back-pointers (VIS-08, DOC-01..04); DOC-05 N/A close; Phase 14 phase-close audit `14-AUDIT.md` (gate emits GREEN)

### Phase 15: Strategy + Roadmap Doc
**Goal**: Land the canonical product strategy/roadmap document (`docs/STRATEGY.md`) — the "how we get there" companion to `docs/VISION.md`'s "what we want to be." Covers execution rules (the process-level principles cut from the vision doc), theme sequencing for v0.6+, near-term focus, what we're working on now and next. Voice-rule grep gate enforced.
**Depends on**: Phase 14 (consumes VISION.md as the upstream "what"; cannot author "how to achieve the vision" before the vision is locked)
**Requirements**: STRATR-01..STRATR-06
**Success Criteria** (what must be TRUE):
  1. `docs/STRATEGY.md` exists at the exact repo path. Single Markdown file. File size ≤ 8 KB on first cut. `wc -c docs/STRATEGY.md` ≤ 8192. — STRATR-01.
  2. The doc's spine reflects strategy/roadmap content. At minimum: `## Where we are now` (current state + recently shipped); `## What we're working on next` (near-term focus, milestone-level); `## Themes for v0.6+` (forward-looking themes, with sequencing rationale); `## Execution principles` (the process-level principles that were cut from VISION.md as too execution-flavored). `grep -nE '^## (Where we are now|What we'\''re working on next|Themes for|Execution principles)' docs/STRATEGY.md` returns ≥ 4 matches. — STRATR-02.
  3. The `## Themes for v0.6+` section lists 2–4 forward-looking themes — at minimum: `Security Hardening` (Phase 13 opportunistic theme — capability-scoped sudoers, cosign-signed catalog releases, npm provenance, etc.); preset/profile framework + compat-guarded update flow (Phase 12 differentiators). Each theme has a `### Sequencing rationale` line. — STRATR-03.
  4. The `## Execution principles` section contains the execution-level rules cut from VISION.md. At minimum: voice rule (delivered-fact vs forward-looking), behavior tests are the spec (ADR-002), evidence-cite discipline (TST-07-style phase-close audits), curated-combo testing (TST-08 4-gate release pipeline), no `sudo npm install -g` (ADR-004). 4–7 entries. — STRATR-04.
  5. The first non-blank line after the H1 is a `> Last reviewed:` blockquote. `head -5 docs/STRATEGY.md | grep -E '^> Last reviewed: 2026-05'` returns 1 match. — STRATR-05.
  6. **Voice-rule grep gate (HARD GATE).** `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md` returns zero matches. Command + output committed verbatim to `.planning/phases/15-strategy-roadmap-doc/15-AUDIT.md`. Phase-close gate fails on any match. — STRATR-06.
  7. Phase-close audit `.planning/phases/15-strategy-roadmap-doc/15-AUDIT.md` cites every STRATR-XX evidence; gate emits GREEN.
**Plans**: 2 plans
- [x] 15-01-PLAN.md — Amend REQUIREMENTS.md STRATR-02 (Rumelt-style 5-section spine + ≥ 5 grep gate; append 2026-05-19 Superseded-items block); author `docs/STRATEGY.md` from VISION.md + Phase 12 + Phase 13 substance with locked 5-section spine + 4 themes + 5-7 execution principles; voice-rule grep gate; capture 15-01-EVIDENCE.md (STRATR-01..06)
- [x] 15-02-PLAN.md — Reviewer pass on docs/STRATEGY.md (technical-writer + fact-checker, parallel; mirror Phase 14 / docs/VISION.md `f95a4ee` precedent); apply triaged feedback; author phase-close audit `15-AUDIT.md` (STRATR-01..06 lifted verbatim from 15-01-EVIDENCE.md; Phase 15 GREEN gate emission)

### Phase 16: Website Refresh (agentlinux.org)
**Goal**: Repair the agentlinux.org landing page so its framing matches the post-Phase-14 vision (two pillars), the post-Phase-15 strategy, the v0.3.0/v0.4.0 product reality, and the locked pillar count. The site is currently two pivots stale (hero says "purpose-built Linux distribution"; features advertise QEMU/Docker micro-VM distribution) — refreshing it is required regardless. Voice-rule grep gate applies to the rendered HTML, with the same hard-gate semantics as Phase 14 VIS-07 / Phase 15 STRATR-06. Visual redesign is explicitly out of scope; the dark JetBrains Mono aesthetic + crab mascot stay.
**Depends on**: Phase 14 (so the site can link to a stable `docs/VISION.md` URL) + Phase 15 (so the site can link to a stable `docs/STRATEGY.md` URL)
**Requirements**: SITE-01..SITE-11
**Success Criteria** (what must be TRUE):
  1. `index.html` hero section is rewritten. The string "purpose-built Linux distribution" is gone (`grep -c 'purpose-built Linux distribution' index.html` returns 0). The hero carries a delivered-fact line (citing v0.3.0/v0.4.0 reality) AND a forward-looking line whose grammatical subject is "we" / "our roadmap" / explicit milestone tag (per voice rule). — SITE-01.
  2. The 8-card `#features` grid is replaced with a `#pillars` section. `grep -cE 'id="(pillars|features)"' index.html` returns exactly 1 hit on `id="pillars"` and 0 hits on `id="features"`. The `#pillars` section contains exactly 2 cards (matching `### Pillar N` count in `docs/VISION.md`). Each card body is ≤ 3 sentences + a "Learn more →" link to `docs/VISION.md#pillar-N` anchor (or the GitHub-rendered equivalent). — SITE-02.
  3. Each pillar card carries a visible status badge. `grep -cE '\[(SHIPPED v0\.3\.0|v0\.6\+ ROADMAP|COMING SOON — v0\.6\+)\]' index.html` returns 2 hits matching the pillar count. Pillar 1's badge reads `[SHIPPED v0.3.0]` (or equivalent shipped marker); pillar 2 carries `[v0.6+ ROADMAP]` (or equivalent forward marker). Badge style is consistent across cards. — SITE-03.
  4. The `#comparison` block is reframed or removed. If reframed: no longer mentions QEMU/Docker micro-VM distribution as alternatives to AgentLinux (`grep -cE 'AgentLinux vs (Docker|VM|micro-VM)' index.html` returns 0); new content aligns with the post-Phase-15 strategy doc's "Where we are now". If removed: `grep -c 'id="comparison"' index.html` returns 0. Either is acceptable. — SITE-04.
  5. A new `#install` section exists OR a deliberate decision to omit is recorded in the audit. If present: `grep -cE 'curl -fsSL' index.html` returns ≥ 1; the snippet includes a SHA256 verify line. — SITE-05.
  6. **Voice-rule grep gate on rendered HTML (HARD GATE).** `grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html` returns zero matches anywhere on the page. Command + empty output committed verbatim to `.planning/phases/16-website-refresh/16-AUDIT.md`. Phase-close gate fails on any match. — SITE-06.
  7. Footer adds links to `docs/VISION.md`, `docs/STRATEGY.md`, `docs/STABILITY-MODEL.md`, and `docs/decisions/` alongside the existing repo / releases links. Top nav also gains a `Vision` link. `grep -cE 'href="[^"]*docs/(VISION|STRATEGY)' index.html` returns ≥ 3 hits (one in nav, two in footer). — SITE-07.
  8. OG / Twitter meta tags rewritten. `grep -cE 'property="og:(title|description)"' index.html` returns ≥ 2; `grep -c 'purpose-built Linux distribution' index.html` returns 0 (already enforced by SITE-01); new descriptions reflect the broadened positioning. — SITE-08.
  9. OG image converted SVG → PNG. `ls assets/*.png 2>/dev/null | xargs -I{} file {}` shows a PNG sized for OG conventions (1200×630 typical); SVG preserved alongside as source-of-truth. `grep -cE 'property="og:image" content="[^"]*\.png"' index.html` returns ≥ 1. Closes the v0.1.0 known issue. — SITE-09.
  10. Deploy-time install-instruction drift check. `.github/workflows/deploy.yml` (or equivalent) contains a step that fails the deploy if the install-snippet version stamp in `index.html` diverges from `README.md`'s `<!-- VERSION_START --><!-- VERSION_END -->` block. If `index.html` does NOT carry an install snippet per SITE-05, this requirement closes as N/A in the audit. — SITE-10.
  11. PR body for the website-refresh PR includes mobile + narrow-viewport screenshots (≤ 375 px wide) of every changed section. Audit records the PR URL + the screenshot count (≥ 1 per changed section). — SITE-11.
  12. Phase-close audit `.planning/phases/16-website-refresh/16-AUDIT.md` cites every SITE-XX evidence; gate emits GREEN. Milestone-close gate also fires from this phase (last v0.3.3 phase).
**Plans**: estimated 1 plan (split possible at phase-discuss time if SITE-09 PNG conversion or SITE-10 drift wiring proves heavier than expected)
- [x] 16-01-PLAN.md — `index.html` IA restructure (#pillars replacing #features, hero rewrite, footer + nav additions, OG/Twitter rewrite); OG image PNG conversion + commit; deploy-time anti-drift check wiring; voice-rule grep gate run + committed; mobile screenshots in PR body; Phase 16 phase-close audit + milestone-close gate (SITE-01..11)
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 12 → 13 → 14 → 15 → 16. Phase 12 → Phase 13 is sequential (user direction). Phase 14 depends on Phases 12 + 13. Phase 15 depends on Phase 14. Phase 16 depends on Phases 14 + 15.

| Phase | Plans Estimated | Status | Notes |
|-------|-----------------|--------|-------|
| 7. License & Public-Ready Documentation | 2 | ✓ Complete (commit `c52b3c1`) | LIC-01..04 evidenced |
| 8. Secret Scanning & History Audit | 3 | ✓ Complete (commit `c94920a`) | SEC-01..05 evidenced; gitleaks gate live |
| 9. Repository Hygiene & Artifact Cleanup | 2 | ✓ Complete (commit `158e465`) | CLEAN-01..04 evidenced |
| 10. Public CI/CD Verification & Branch Protection | 2 | ✓ Complete-pending-maintainer (commit `446c89b`) | CIPUB-01..02 evidenced; CIPUB-03..04 staged for maintainer apply |
| 11. Public Visibility Flip & Smoke Test | 2 | ✓ Shipped 2026-05-02 (commit `c8a2787`, tag `v0.3.1`) | PUB-01..04 evidenced; v0.4.0 originally tagged then renamed to `v0.3.1` for version-constant lockstep |
| 12. Pillar 2 Exploration | 1/1 | Complete | 2026-05-10 |
| 13. Pillar 3 Candidate Exploration | 1/1 | Complete | 2026-05-10 |
| 14. Vision Doc + ADR-015 + Downstream Surface Updates | 2 | In progress | Reframed from "Strategy Doc..." on 2026-05-16; vision-doc draft committed; ADR-015 + downstream propagation pending |
| 15. Strategy + Roadmap Doc | 2/2 | Complete    | 2026-05-19 |
| 16. Website Refresh | 1/1 | Complete   | 2026-05-24 |
| **Total v0.3.3 phases** | **~7 plans** | 2/5 phases done | — |

## Coverage Summary

**Total v0.3.3 requirements:** 33 (2 EXPL + 14 Phase 14 (VIS+DOC) + 6 Phase 15 (STRATR) + 11 Phase 16 (SITE))
**Mapped:** 33 / 33
**Orphaned:** 0
**Duplicated across phases:** 0

> **Note on requirement-ID changes (2026-05-16):** The original ROADMAP referenced STRAT-01..STRAT-13 + DOC-01..DOC-05 in Phase 14 (18 reqs). The 2026-05-16 reframe split that into Phase 14 (VIS-01..VIS-09 + DOC-01..DOC-05 = 14 reqs, vision-only) and a new Phase 15 (STRATR-01..STRATR-06 = 6 reqs, strategy/roadmap doc). The Sourcegraph-framework-spine requirements (old STRAT-02 spine, STRAT-07 framework trade-offs, STRAT-08 Vision Board, STRAT-09 Appendix B placement-inside-strategy-doc) all dissolved because the doc structure is no longer the Sourcegraph template. The original Phase 15 (Website Refresh) renumbered to Phase 16 with no requirement-ID changes (SITE-01..SITE-11 unchanged).

Requirement allocation per phase:

| Phase | Requirements | Count |
|-------|--------------|-------|
| 12 Pillar 2 Exploration | EXPL-01 | 1 |
| 13 Pillar 3 Candidate Exploration | EXPL-02 | 1 |
| 14 Vision Doc + ADR-015 + Downstream Surface Updates | VIS-01..VIS-09, DOC-01..DOC-05 | 14 |
| 15 Strategy + Roadmap Doc | STRATR-01..STRATR-06 | 6 |
| 16 Website Refresh | SITE-01..SITE-11 | 11 |
| **Total** | | **33** |

## Notes on verification

- Most v0.3.3 work is documentation. Evidence is documentation artifacts under `docs/exploration/PILLAR-*-NOTES.md`, `docs/VISION.md`, `docs/STRATEGY.md`, `docs/decisions/015-agenda-redefinition.md`, plus per-phase audit files. No new bats @tests are required.
- The bats / Docker / QEMU harness from v0.3.0 is **not** the primary verification surface for v0.3.3. It is still required to stay green throughout — a regression there blocks the milestone, but the milestone does not add new bats.
- Phase 16's only "real product code" change is HTML/CSS/JS in `index.html` + `assets/`. The existing GitHub Pages auto-deploy pipeline (v0.1.0) carries it.
- Phase-close gate convention (TST-07-style) carries forward unchanged: every requirement closes with a cited evidence artifact in its phase's AUDIT doc before the gate emits GREEN. For documentation-only requirements the evidence is a file path + line range, a commit hash, or a grep transcript.
- **Voice-rule grep gates (VIS-07 in Phase 14, STRATR-06 in Phase 15, SITE-06 in Phase 16) are the load-bearing structural defense for the milestone.** They are run as part of the phase-close audit and their command + output is committed verbatim to the audit file. The grep is the spec.
- **Pillar 3 conditional handling is resolved.** Phase 13 verdict (b) means no Pillar 3. Downstream conditionals: (i) the `### Pillar 3` section in VISION.md does not exist; (ii) DOC-05 closes N/A in Phase 14 audit; (iii) the `#pillars` section on the website carries 2 cards; (iv) ADR-012 forward-reference is not added.

---

*Last updated: 2026-05-16 — v0.3.3 ROADMAP rewritten for Phase 14 vision-only reframe + Phase 15 strategy-doc insertion + Phase 15 → Phase 16 website-refresh renumber.*

## v0.4.0 milestone-context open questions (resolved)

- **License pick**: MIT (recommended) vs. Apache-2.0 (patent grant) vs. another OSI license? — resolved in Phase 7 ADR-013.
- **Existing-file SPDX backfill**: apply headers retroactively to all source files in one big commit, or only to new files going forward? — resolved in Phase 7 ADR-013.
- **History rewrite vs. accept-and-rotate** for any leaked secrets: depends on what is found. Default-stance: rotate without rewrite unless the secret grants ongoing access — resolved in Phase 8 ADR-014.
- **Default branch rename** (`master` → `main`): explicitly out of scope for v0.4.0; raise as a separate milestone if desired. (Cosmetic; would invalidate existing URL references.)
- **Public install URL** for PUB-03 smoke: is it `agentlinux.org/install.sh` or `https://github.com/Roo4L/Agent-Linux/releases/download/v0.3.0/install.sh`? Resolve before Phase 11.

### Phase 12: Developer documentation for installer, runtime, and CLI (AL-22)

**Goal:** A reader landing on the AgentLinux repo can find a 60-second answer to "what value does AgentLinux provide for surface X" for every component (installer, agent user, sudo drop-in, Node.js runtime, the agent catalog, the registry CLI, and the curated agent set: Claude Code, GSD, Playwright). The docs stay in sync with the source via a project-scoped reviewer (`dev-docs-auditor`) embedded in the existing review loop — no new stop-hook is added (ADR-015 lands in Plan 12-05).
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07
**Depends on:** Phase 11
**Plans:** 5/5 plans complete

Plans:
- [x] 12-01-PLAN.md — docs/internals/ index + 4 install/runtime layer component docs (DOC-01, DOC-02)
- [x] 12-02-PLAN.md — 5 agent + CLI/catalog component docs (DOC-02)
- [x] 12-03-PLAN.md — dev-docs-auditor reviewer agent + dev-docs skill (DOC-03, DOC-04, DOC-06)
- [x] 12-04-PLAN.md — CLAUDE.md Review Loop + Pointers wiring + top-level README.md discoverability (DOC-03, DOC-05)
- [x] 12-05-PLAN.md — REQUIREMENTS.md DOC-XX entries + ADR-015 + Phase 12 AUDIT (DOC-01..DOC-07, phase-close) (completed 2026-05-10)
