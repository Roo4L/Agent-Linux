# Requirements: AgentLinux v0.3.3 — Agenda Redefinition

**Defined:** 2026-05-09
**Milestone:** v0.3.3 Agenda Redefinition
**Triggered by:** Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7)
**Core Value (carried from PROJECT.md):** An agent can be dropped into any supported Linux system and just work — provisioned correctly the first time. v0.3.3 broadens the framing of what AgentLinux *is*: from a single-pillar product (separated, correctly-owned agent environment — v0.3.0 core) to a multi-pillar product whose pillar count and contents are decided by this milestone's exploration phases. The deliverable is *framing* — a canonical strategy document, an ADR, and a refreshed public landing page propagating the new framing — not new product capabilities.

## Design Philosophy (read first)

**This is a planning + framing milestone. Most evidence is documents, not bats @tests.**

- The exploration phases (12, 13) come *first* and produce written conclusions docs. The strategy-doc authoring phase (14) consumes those conclusions; it does not pre-decide them. The website-refresh phase (15) propagates whatever framing landed in 14.
- **Pillar count is not pre-decided.** AL-7 proposed three pillars (env + stability + security). The milestone may land on 2 or 3 — Phase 13's verdict on "is security a pillar?" determines this.
- **Pillar contents are not pre-decided.** The research SUMMARY.md surfaces the landscape (eval suites, attack inventory, defense inventory, named precedents) as **raw material**; the exploration phases decide what AgentLinux actually commits to.
- **The voice rule is non-negotiable.** Per PITFALLS.md: every claim about an unshipped behaviour MUST appear in a sentence whose grammatical subject is "we" / "our roadmap" / an explicit milestone identifier — never "AgentLinux + present-tense verb." An automated grep gate enforces this on the strategy doc and on the rendered website HTML. This is the single most important defence against shipping vaporware.
- **Phase-close gate convention carries over from v0.3.0/v0.4.0.** Every requirement closes with a cited evidence artefact in its phase's `<phase-NN>-AUDIT.md` before the gate emits GREEN. For documentation-only requirements the evidence is a file path + line range or a commit hash.
- **The strategy doc is a living document.** Pitfall #12 / #23 — strategy doc never updates again — is flagged for the milestone retrospective + a `/gsd-complete-milestone` template amendment, not as an in-milestone requirement. The strategy doc itself includes a `Last reviewed:` header (STRAT-10) so the cadence binding has a place to land.
- **User-stated direction (locked at milestone-open):** Pillar 1 = `foundational` (settled by v0.3.0 reality). Pillar 2 (framed by user as **stability + time-to-productive — automation of package installations + problem reconciliations across upstream drift**) = `next-milestone` priority. Pillar 3's existence and priority are decided by Phase 13.

## v0.3.3 Requirements

Grouped by category. Each `XXX-NN` is a verifiable outcome — a document section, a cross-link, a grep result, a screenshot, or a commit hash — auditable before the phase closes.

### Pillar Exploration (EXPL) — Phases 12, 13

- [x] **EXPL-01**: A `docs/exploration/PILLAR-2-NOTES.md` file exists. It captures the discussion and verdict on pillar 2 (stability + time-to-productive) — what value AgentLinux brings (e.g. package-install automation, problem reconciliation across upstream drift, curated combo testing), what scope is in/out, what AgentLinux would actually measure, and named references drawn from `.planning/research/SUMMARY.md` §4 + `FEATURES.md` (terminal-bench, Multi-Docker-Eval, τ-bench `pass^k`, the time-to-productive vs SWE-bench-Verified honesty rule, Helicone/Langfuse observability). The file ends with a **"Decision summary"** section authoritative for downstream Phase 14 — naming the pillar, listing its committed table-stakes (≥2), differentiators (≥1, may be empty if intentionally so), explicit non-goals (≥2), and the "Today / Direction" content seed. Pillar 2's `next-milestone` priority tag is reaffirmed (or the user's direction is explicitly revisited).

- [ ] **EXPL-02**: A `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` file exists. It treats security as a *candidate* pillar — the file's first decision is the verdict: (a) yes, security is a full pillar; (b) no, fold into pillar 2 as a sub-concern; (c) no, address as cross-cutting concern (like CI/CD); (d) no, explicitly out-of-scope for AgentLinux's product framing. The exploration draws from `.planning/research/SUMMARY.md` §5 + `FEATURES.md` raw material (OWASP LLM Top 10 v2025, Lethal Trifecta, Agents Rule of Two, Shai-Hulud + chalk/debug + TrustFall + Cline-via-markdown attack landscape, npm provenance + SLSA + cosign + Anthropic devcontainer + bubblewrap defense landscape, the ADR-012 NOPASSWD tension). The file ends with a **"Decision summary"** section authoritative for Phase 14 — the verdict, the rationale, and (if a/b/c) the committed table-stakes / differentiators / non-goals + the recommended priority tag (`next-milestone` / `opportunistic`).

### Strategy Document (STRAT) — Phase 14

- [ ] **STRAT-01**: `docs/STRATEGY.md` exists at the repo path locked by research (single Markdown file, sibling to `docs/STABILITY-MODEL.md` and `docs/HARNESS.md`). The file is at most ~10 KB on first cut (target 4–8 KB; same scale as STABILITY-MODEL.md's 5.4 KB). It is a single Markdown file — not a `docs/strategy/` tree, not a canvas image, not embedded in README.

- [ ] **STRAT-02**: The doc's spine matches the Sourcegraph "Strategy Page" template. Required top-level sections in order: `Mission` (with a Geoffrey-Moore-form positioning sentence as a subsection), `The N pillars (tenets)`, `Guiding principles`, `Where we are now`, `Strategy and plans` (with `Themes for v0.6+` + `What we're explicitly not working on`), `Trade-offs / rejected alternatives`, `Appendix A — One-page Vision Board`, `Appendix B — Roadmap themes`. (`N` in "The N pillars" reflects the EXPL-02 verdict — 2 or 3.)

- [ ] **STRAT-03**: The Pillars section contains exactly the pillar count decided in EXPL-02 — pillar 1 always present (env, foundational); pillar 2 always present (stability + time-to-productive, contents from EXPL-01 Decision summary); pillar 3 present iff EXPL-02 verdict was "yes, full pillar". For each pillar: a Today / Direction subsection split (per L9 in SUMMARY.md). The `Today` block lists shipped behaviour with citations to `@tests` / ADRs / CI gates / release artefacts; the `Direction` block uses *forward-looking voice* exclusively (subject = "we" / "our roadmap" / explicit milestone tag).

- [ ] **STRAT-04**: A `Pillar priority` subsection inside Pillars tags each pillar as `foundational` / `next-milestone` / `opportunistic`. Pillar 1 = `foundational` (locked). Pillar 2 = `next-milestone` (locked per user direction). Pillar 3's tag (if pillar exists) follows EXPL-02. Deferring this assignment fails the requirement (Pitfall #4 forcing function).

- [ ] **STRAT-05**: A `Guiding principles` section with 4–7 named principles. Each principle is a single declarative sentence + a one-line "why this matters" + a back-link to the artefact that grounds it (an ADR, a bats convention, a GSD-workflow rule). Phase 14 picks the actual list; seed candidates from research: "Behavior tests are the spec" (ADR-002), "We test exactly what we ship" (ADR-011), "Curated combos, not thin wrappers" (ADR-011 negative space), "No silent drift" (`agentlinux upgrade` contract), "Trust through evidence, not assertion" (provenance principle).

- [ ] **STRAT-06**: A `Strategy and plans → What we're explicitly *not* working on` subsection with at least 5 entries. Each entry has a one-line rejection reason that goes beyond "scope creep". Sources include the research-surfaced non-goals (e.g. SWE-bench leaderboard replication, model-level guardrails, becoming a sandbox runtime, custom distro path, Snap distribution, per-agent .deb packages, ARM/multi-arch, Docker-in-Docker inside the agent environment, plus pillar-specific non-goals from EXPL-01 / EXPL-02 Decision summaries).

- [ ] **STRAT-07**: A `Trade-offs / rejected alternatives` section that records considered-and-rejected framings (per Pitfall #13). At minimum: "stay single-pillar (rejected)", the pillar-3-shape options EXPL-02 evaluated (whichever ones were considered and rejected), and the framework-spine alternatives the research considered (Lean Canvas, BMC, OKRs, PR-FAQ — each rejected with a concrete reason).

- [ ] **STRAT-08**: An `Appendix A — One-page Vision Board` (Roman Pichler form) — a markdown table summarising Target Group / Needs / Product / Business Goals on a single screen. Distilled from the body; meant for a reader who only has 60 seconds.

- [ ] **STRAT-09**: An `Appendix B — Roadmap themes` listing 2–4 forward-looking themes for v0.6+ (synthesizer's recommendation: 3 — Benchmarks Harness, Security Hardening *if* pillar 3 survives, Distro Reach). Themed-not-dated (Jujutsu exemplar). A `Sequencing rationale` subsection explains why theme X comes before theme Y (Pitfall #26 enforcement).

- [ ] **STRAT-10**: A top-of-file `Last reviewed:` header (`Last reviewed: 2026-05-09 at v0.3.3 close`). The header exists as a forcing function for the future `/gsd-complete-milestone` cadence binding (Pitfall #12 / #23 mitigation; the cadence binding itself is a deferred process change — see Deferred Items).

- [ ] **STRAT-11**: The voice-rule grep gate passes. Run on `docs/STRATEGY.md`: `grep -nE '^[^a-z]*AgentLinux (provides|offers|ensures|protects|defends|benchmarks|measures|hardens|isolates|detects|prevents)\b' docs/STRATEGY.md` MUST return zero matches in any pillar-2 or pillar-3 `Direction` subsection. Acceptance evidence: the grep command + its empty output committed to `<phase-14>-AUDIT.md`.

- [ ] **STRAT-12**: Cross-link map populated per SUMMARY.md §6. Outbound — every pillar/principle/rejection in STRATEGY.md that grounds in an ADR/STABILITY-MODEL/research file carries a Markdown link. Inbound — `README.md` (About + Links), `CONTRIBUTING.md` (one paragraph), `.planning/PROJECT.md` (Core Value section), `docs/STABILITY-MODEL.md` (Related), and `docs/decisions/012-agent-user-full-sudo.md` (forward-reference for the documented tension if pillar 3 survives) each gain a back-pointer to STRATEGY.md. Phase-close audit lists every changed file with the line range of the back-pointer edit.

- [ ] **STRAT-13**: `docs/decisions/015-agenda-redefinition.md` (ADR-015) lands in the same milestone window as STRATEGY.md. ADR-015 contains: Status (Accepted), Context (the AL-7 framing question + why a single-pillar framing was getting in the way), Decision (the N-pillar landing — see EXPL-02 verdict), at least 3 considered-and-rejected alternatives ("stay single-pillar"; "pivot security-first"; "four-or-more-pillar (incl. observability)" or whatever Phase 14 actually weighed), Consequences (downstream effects on README, website, future milestones, and — if pillar 3 survives — the ADR-012 NOPASSWD tension), and a back-link to AL-7 + STRATEGY.md.

### Downstream Surface Updates (DOC) — Phase 14 (or split as Phase 14b)

- [ ] **DOC-01**: `README.md` is updated. The `## About` section (or equivalent) gains a single sentence naming the N pillars and linking to `docs/STRATEGY.md`. The `## Links` section gains a `Strategy: [docs/STRATEGY.md](docs/STRATEGY.md)` row. No other README copy is rewritten in this requirement (the website carries the public-facing reframe; the README is the developer-facing reference and stays operationally focused).

- [ ] **DOC-02**: `CONTRIBUTING.md` is updated. A "Why this project exists" paragraph (one short paragraph) links to `docs/STRATEGY.md` and names which pillar(s) currently accept contributions today (pillar 1 = yes, the existing v0.3.0 surface; pillar 2 / pillar 3 = early-stage, contributions welcome with a heads-up that the framing locks in v0.3.3).

- [ ] **DOC-03**: `.planning/PROJECT.md` Core Value / Current Milestone sections cross-reference `docs/STRATEGY.md` (one link in each section). The Out-of-Scope list reflects any new non-goals that EXPL-01 / EXPL-02 surfaced.

- [ ] **DOC-04**: `docs/STABILITY-MODEL.md` gains a `Related` section (or equivalent) with a back-link to `docs/STRATEGY.md` Pillar 2 (since STABILITY-MODEL.md is the ADR-011 user companion and ADR-011 is the pillar-2 seed).

- [ ] **DOC-05** (conditional on pillar 3 surviving EXPL-02): `docs/decisions/012-agent-user-full-sudo.md` (ADR-012) gains a forward-reference to ADR-015 + `docs/STRATEGY.md` Pillar 3 documenting the tension (NOPASSWD ALL vs the security-pillar framing) and the milestone where the tension is intended to be resolved. Honest tension documentation per Pitfall #5 / #13. If pillar 3 does NOT survive, this requirement is closed as N/A with a one-line decision in the audit.

### Website Refresh (SITE) — Phase 15

- [ ] **SITE-01**: `index.html` hero section is rewritten so the headline + subhead reflect the current product framing (no longer "purpose-built Linux distribution that runs on a dedicated machine" — that's two pivots stale). Hero carries a delivered-fact line (what AgentLinux is today, v0.3.0/v0.4.0) AND a forward-looking line (where the strategy points). Voice rule applies (forward-looking line uses "we" / "our roadmap" / explicit milestone tag).

- [ ] **SITE-02**: The `#features` 8-card grid is replaced with a `#pillars` section presenting N cards (matching strategy-doc pillar count) using the mise.jdx.dev IA pattern (numbered cards, equal-weight visual treatment, single-page). Each card title matches the strategy doc's pillar name; each card body is ≤ 3 sentences + a "Learn more →" link to `docs/STRATEGY.md#pillar-N` anchor.

- [ ] **SITE-03**: Each pillar card carries a visible status badge — `[SHIPPED v0.3.0]` for pillar 1, `[v0.6+ ROADMAP]` (or equivalent) for any forward-looking pillar (pillar 2, and pillar 3 if it survives). Badge style is consistent across cards (CSS class or inline equivalent). PITFALLS #14 + #18 enforcement.

- [ ] **SITE-04**: The `#comparison` block is reframed or removed — its current "AgentLinux vs Docker vs VMs" framing is built around the retired distro shape and contradicts the new framing. Replacement is a competitive-landscape paragraph (or a smaller table) aligned with `docs/STRATEGY.md` "Where we are now" content.

- [ ] **SITE-05**: A new `#install` section mirrors the README curl-pipe-bash + verify snippet, including the SHA256 verify line. (Currently the site has no install section — visitors are sent to the repo for install instructions, which is OK but not great.) Optional: keep `#install` minimal and link to README for the canonical reference.

- [ ] **SITE-06**: The voice-rule grep gate applies to the rendered HTML. Run on `index.html`: `grep -nE 'AgentLinux (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html` MUST return zero matches in any pillar-2 / pillar-3 / forward-looking section. Acceptance evidence: grep command + empty output committed to `<phase-15>-AUDIT.md`.

- [ ] **SITE-07**: Footer adds links to `docs/STRATEGY.md`, `docs/STABILITY-MODEL.md`, and `docs/decisions/` (ADR index) alongside the existing repo / releases links. The `Strategy` link is also added to the top nav (per the SUMMARY.md §7 IA sketch).

- [ ] **SITE-08**: OG / Twitter meta tags are rewritten to match the new framing — `og:title`, `og:description`, `twitter:title`, `twitter:description` all reflect the broadened positioning (no "purpose-built Linux distribution" language). PITFALLS #20 enforcement.

- [ ] **SITE-09**: The OG image is converted from SVG to PNG (closes the v0.1.0 known issue carried in PROJECT.md). The PNG is sized per platform conventions (1200×630 for og:image; 1200×675 for twitter:image:large or use og:image for both). The SVG is preserved alongside as the source-of-truth.

- [ ] **SITE-10**: A deploy-time install-instruction drift check is wired into `.github/workflows/deploy.yml` (or equivalent). The check fails the deploy if the install-snippet version stamp in `index.html` diverges from `README.md`'s `<!-- VERSION_START --><!-- VERSION_END -->` block. Same shape as the existing Pattern 5 anti-drift check on `install.sh`. (If `index.html` doesn't carry an install snippet per SITE-05, this requirement closes as N/A with the decision recorded.)

- [ ] **SITE-11**: PR body for the website-refresh PR includes mobile + narrow-viewport screenshots (≤ 375 px wide) of every changed section, demonstrating the responsive design holds. PITFALLS #19 enforcement. Acceptance evidence: PR URL + screenshots embedded in the audit doc.

## Future Requirements (not in this milestone)

- **Pillar 2 implementation milestone (v0.6+ Benchmarks Harness)** — actual benchmark suite, dataset, scoring methodology, CI integration. Strategy doc Appendix B commits to it; this milestone does not deliver it.
- **Pillar 3 implementation milestone (v0.6+ Security Hardening)** — *only if* EXPL-02 keeps pillar 3 alive — `agentlinux harden` profile, capability-scoped sudoers, bubblewrap-based per-recipe sandbox, iptables egress allowlist, cosign-signed catalog snapshots, npm provenance verification. Strategy doc Appendix B commits to it; this milestone does not deliver it.
- **Distro Reach milestone (v0.6+)** — Fedora / Alma / Arch support — pillar 1 expansion. Strategy doc Appendix B may commit to it as a future theme.
- **Strategy-doc cadence binding** — `/gsd-complete-milestone` template gains a "Strategy doc reviewed; pillar Today/Direction sections updated" step. Process change to GSD itself, not an AgentLinux product change. Flagged for the v0.3.3 retrospective; tracked separately. (See Deferred Items.)

## Out of Scope (explicit exclusions)

**v0.3.3 out of scope:**
- *Implementing* benchmarks (pillar 2) — v0.3.3 surfaces benchmarks as a roadmap theme; the actual harness/dataset/scoring lands in a v0.6+ milestone.
- *Implementing* security-hardening countermeasures (pillar 3) — v0.3.3 surfaces threat models + roadmap themes; supply-chain and prompt-injection mitigations land in a v0.6+ milestone.
- New distro targets, new catalog agents, new installer features — pillar 1 stays at its v0.3.0 surface for this milestone.
- A full website redesign — the website-refresh phase keeps the existing dark JetBrains-Mono aesthetic + crab mascot. Visual redesign is a separate decision; if it proves needed it earns its own phase.
- Renaming, restructuring, or moving the strategy doc after Phase 14 lands — the doc location locks at `docs/STRATEGY.md` and stays put. Restructuring into a `docs/strategy/` tree is reachable later only if the file outgrows itself (~15 KB+).
- Authoring a Code of Conduct, SECURITY.md, or full issue / PR templates — track separately as a community-platform milestone if the contribution surface grows.
- *Resolving* the ADR-012 NOPASSWD tension. The strategy doc + ADR-015 *document* the tension if pillar 3 survives; the *resolution* belongs to the v0.6+ Security Hardening milestone.

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

Filled in by the roadmapper agent: each requirement is mapped to exactly one phase. Phase numbering continues from v0.4.0's last phase (11 → 12).

| Req | Phase | Plan |
|-----|-------|------|
| EXPL-01 | 12 | 12-01-PLAN.md |
| EXPL-02 | 13 | 13-01-PLAN.md |
| STRAT-01 | 14 | 14-01-PLAN.md |
| STRAT-02 | 14 | 14-01-PLAN.md |
| STRAT-03 | 14 | 14-01-PLAN.md |
| STRAT-04 | 14 | 14-01-PLAN.md |
| STRAT-05 | 14 | 14-01-PLAN.md |
| STRAT-06 | 14 | 14-01-PLAN.md |
| STRAT-07 | 14 | 14-01-PLAN.md |
| STRAT-08 | 14 | 14-01-PLAN.md |
| STRAT-09 | 14 | 14-01-PLAN.md |
| STRAT-10 | 14 | 14-01-PLAN.md |
| STRAT-11 | 14 | 14-01-PLAN.md |
| STRAT-12 | 14 | 14-02-PLAN.md |
| STRAT-13 | 14 | 14-01-PLAN.md |
| DOC-01 | 14 | 14-02-PLAN.md |
| DOC-02 | 14 | 14-02-PLAN.md |
| DOC-03 | 14 | 14-02-PLAN.md |
| DOC-04 | 14 | 14-02-PLAN.md |
| DOC-05 | 14 | 14-02-PLAN.md (conditional on EXPL-02 Verdict (a); else N/A close in 14-AUDIT.md) |
| SITE-01 | 15 | 15-01-PLAN.md |
| SITE-02 | 15 | 15-01-PLAN.md |
| SITE-03 | 15 | 15-01-PLAN.md |
| SITE-04 | 15 | 15-01-PLAN.md |
| SITE-05 | 15 | 15-01-PLAN.md |
| SITE-06 | 15 | 15-01-PLAN.md |
| SITE-07 | 15 | 15-01-PLAN.md |
| SITE-08 | 15 | 15-01-PLAN.md |
| SITE-09 | 15 | 15-01-PLAN.md |
| SITE-10 | 15 | 15-01-PLAN.md (or N/A close if SITE-05 omits the install snippet) |
| SITE-11 | 15 | 15-01-PLAN.md |

**Coverage:** 31 / 31 requirements mapped (2 EXPL + 13 STRAT + 5 DOC + 11 SITE). Zero orphans, zero duplicates. Plan-slot conditionals (DOC-05, SITE-10) are recorded inline above.

## Deferred Items

- **`/gsd-complete-milestone` template amendment** (Pitfall #12 / #23) — adds a "Strategy doc reviewed" step that updates pillar Today / Direction sections at every milestone close. Process change to GSD itself; flagged for the v0.3.3 retrospective. Not in v0.3.3 scope.
- **CI lint that warns if STRATEGY.md `Last reviewed:` header is older than the latest release tag by >90 days** (PITFALLS #12 mitigation, optional). Defer until the cadence binding is in place — the lint without the binding produces noise.
- **Bidirectional ADR back-references** — ADR-011 forward-reference to STRATEGY.md (recommended in SUMMARY.md §6 as optional). Defer unless STRAT-12 author finds it valuable; not blocking.
