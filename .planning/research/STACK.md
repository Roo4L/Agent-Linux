# Stack Research — PM Strategy-Doc Framework, Tooling, Format, Location

**Domain:** Authoring a canonical product-strategy document for AgentLinux v0.5.0 (OSS dev-infrastructure project; multi-pillar broadening; contributor-attraction is the primary near-term goal).
**Researched:** 2026-05-09
**Confidence:** HIGH for framework selection and repo-location pick (multiple converging sources, including a near-perfect template precedent and an academic spine that backs it). MEDIUM for the OSS-exemplar set (each example was verified individually but the field itself is sparse — most OSS dev-tools projects do *not* publish strategy docs, which is itself a finding).

---

## TL;DR (for the synthesizer)

**Recommended framework:** **Sourcegraph "Strategy Page" template** as the *spine*, anchored in **Rumelt's strategy kernel** (Diagnosis → Guiding Policy → Coherent Action) for intellectual rigor, with three named *inserts*: (a) **Geoffrey Moore positioning statement** as a one-paragraph elevator-pitch block inside the Mission section; (b) **Amazon-style Tenets** as the section title for the three pillars (so each pillar reads as a foundational stance, not a feature list); (c) **Roman Pichler Product Vision Board** distilled into a one-page summary appendix for visual scanability.

**Recommended location + filename:** `docs/STRATEGY.md` — single Markdown file, flat at the top level of `docs/`, sibling to `STABILITY-MODEL.md`. Stable-by-construction (matches existing AgentLinux convention; same CamelCase-keystone format as `HARNESS.md` and `STABILITY-MODEL.md`; ADR-companion pattern already established by `STABILITY-MODEL.md` ↔ ADR-011).

**Recommended format:** Single Markdown file (4–8 KB target, on the same scale as `STABILITY-MODEL.md` 5.4 KB). No tree, no embedded README sections, no canvas image.

**Why this combination wins:** The Sourcegraph template is the only public, link-citable, in-repo strategy template that explicitly prompts for *both* mission/positioning *and* "what we are not working on & why" — the latter is structurally what AgentLinux v0.5.0 needs for its "pillar-2-and-3-implementation-is-out-of-scope-for-this-milestone" framing. Rumelt's kernel forces the doc to read as a *strategy* (a coherent response to a diagnosed challenge) rather than as a feature manifesto. Tenets language for the three pillars borrows Amazon's well-known forcing function (*"the mission says what; the tenets say how"*), which directly resolves AL-7's "single-pillar framing is too narrow" complaint by giving each pillar standalone weight.

---

## What we evaluated

### Framework comparison matrix

| Framework | Origin | Sections it prescribes | Fit for AgentLinux v0.5.0 | Verdict |
|-----------|--------|------------------------|---------------------------|---------|
| **Lean Canvas** ([Maurya, 2010](https://leanstack.com/lean-canvas)) | Startup MVP validation; adapted from Osterwalder's Business Model Canvas | 9 blocks: Problem, Customer Segments, UVP, Solution, Channels, Revenue Streams, Cost Structure, Key Metrics, Unfair Advantage | Poor fit — the four monetization blocks (Channels, Revenue, Cost, Unfair Advantage) are dead weight for a pre-monetization OSS project; the 1-page canvas form factor doesn't survive translation to Markdown well. | **Reject.** |
| **Business Model Canvas** ([Osterwalder, 2010](https://www.strategyzer.com/library/the-business-model-canvas)) | Established business strategy | 9 blocks centered on infrastructure (Key Partners, Key Activities, Key Resources, Channels, etc.) | Worse fit than Lean Canvas — built explicitly for "infrastructure of a business" per Maurya's own contrast; AgentLinux is pre-business. | **Reject.** |
| **Roman Pichler Product Vision Board** ([Pichler, 2023 v01](https://www.romanpichler.com/tools/product-vision-board/)) | Agile product management | 5 sections: Vision, Target Group, Needs, Product, Business Goals (extended adds: Competitors, Revenue, Cost, Channels) | Decent fit on the core 5 — Vision/Target/Needs/Product map cleanly to AgentLinux's "what / for whom / why / how" — but it stops at "business goals" without prompting for *non-goals* or *positioning vs alternatives*, both of which AL-7 explicitly needs. | **Borrow as one-page appendix only.** |
| **Amplitude North Star Framework** ([Amplitude Playbook](https://amplitude.com/books/north-star/about-north-star-framework)) | Product analytics; metric-driven product orgs | North Star Metric + Inputs (typically 3–5 input metrics that ladder up) | Premature — pillar 2's "measurable benchmarks vs vanilla setups" is exactly an NSM candidate (e.g., *p50 task-success-rate uplift over baseline*), but the NSM should be picked *during the v0.6+ benchmarks milestone*, not at the framing stage. v0.5.0 should mention it as a roadmap-theme placeholder, not commit to one. | **Borrow as forward-looking note in roadmap-themes appendix only.** |
| **OKRs** ([Doerr, *Measure What Matters*](https://www.whatmatters.com/get-started)) | Quarterly execution alignment | Objectives (qualitative) + Key Results (3–5 measurable) per cycle | Wrong granularity. OKRs are quarterly execution; the strategy doc is a multi-milestone framing artifact. OKRs would belong in milestone planning (`.planning/MILESTONES.md`), not in the strategy doc. | **Reject for strategy doc.** May surface in v0.6+ milestones. |
| **Amazon Working Backwards / PR-FAQ** ([Bryar & Carr, 2021](https://workingbackwards.com/concepts/working-backwards-pr-faq-process/)) | Product-launch ideation | Press release written from a future launch date + FAQ section anticipating customer/exec questions | Excellent for *single product launches*, awkward for *project-wide multi-pillar framing*. A PR-FAQ would force AgentLinux into one launch narrative, which is the opposite of the broadening AL-7 wants. Also, the future-dated press-release voice clashes with AgentLinux's existing engineer-authored README voice. | **Reject as primary spine.** Consider reusing PR-FAQ form for individual v0.6+ pillar-2/pillar-3 milestone kickoffs. |
| **Geoffrey Moore positioning statement** ([Moore, *Crossing the Chasm*](https://geoffreyamoore.com/positioning/)) | B2B tech-product positioning | One sentence: *For [target] who [need], [product] is a [category] that [benefit]. Unlike [alternative], our product [differentiation].* | Tightly scoped, single-paragraph. Does one job (positioning) extremely well and doesn't try to be the whole strategy. AgentLinux currently has no canonical positioning sentence — README and PROJECT.md hint at one but don't crystallize it. | **Adopt as a one-paragraph block inside the Mission section.** |
| **Stripe / Atlas "What we believe" docs** | Founder-essay tradition (less formal than the others) | Free-form essay: "We believe X. Therefore Y." Repeated for 3–7 beliefs. | Good *voice*, weak *structure*. Useful as a stylistic reference for how the three pillars get phrased, but doesn't give us a TOC. | **Borrow voice; don't adopt as spine.** |
| **Amazon-style Tenets** ([Sheridan / Pedro Delgallego writeup](https://pedrodelgallego.github.io/blog/amazon/mental-models/decision-making/tenets-at-amazon/)) | Amazon internal decision-making framework | 5–7 short principles per program/product, each phrased as a *stance* the team takes when in conflict. *"The mission says what; the tenets say how."* Tagged "unless you know better ones" so they remain revisable. | **Strong fit for the three pillars.** Phrasing each pillar as a tenet (e.g., *"Pillar 2: Stability over novelty — we ship a benchmarked combo, not the latest of everything"*) gives each pillar a forcing-function flavor and resolves AL-7's complaint that the single-pillar framing was too narrow. Public OSS precedent: [Jujutsu's `docs/core_tenets.md`](http://docs.jj-vcs.dev/latest/core_tenets/) (12 tenets, ~1 page, pure bullet list). | **Adopt as the "Three Pillars" section header style.** |
| **Sourcegraph "Strategy Page" template** ([handbook/page_templates/strategy_template.md](https://github.com/sourcegraph/handbook/blob/main/page_templates/strategy_template.md)) | Internal product-team strategy at Sourcegraph (developer-tools company) | TOC: Mission → Guiding Principles → Where we are now (incl. Customer issues, Competitive landscape) → Strategy and Plans (Goals, Themes, What's next, **What we're not working on & why**) | **Best overall fit.** Built by a dev-tools company for dev-tools strategy docs. The "What we're not working on & why" prompt is structurally exactly AgentLinux v0.5.0's "out-of-scope" framing for pillar-2/pillar-3 implementation. The "Themes" prompt is the natural home for the v0.6+ roadmap themes that AL-7 wants surfaced as a forward-looking appendix. License-permissive (MIT, public repo). | **Adopt as spine.** |
| **Rumelt's Strategy Kernel** ([*Good Strategy Bad Strategy*, 2011](https://www.amazon.com/Good-Strategy-Bad-Difference-Matters/dp/0307886239)) | Strategy theory (academic) | Diagnosis → Guiding Policy → Coherent Action — the *kernel* that any good strategy must contain | Not a template, a *test*. Use it as a sanity-check overlay on the Sourcegraph spine: Mission+"Where we are now" must read as a Diagnosis; Guiding Principles must read as a Guiding Policy; Themes + What's next must read as Coherent Action. Forces the doc to be a strategy and not a feature list. | **Adopt as a hidden review checklist, not a section.** |

### What's *not* in the list (and why)

- **Jobs-to-be-Done framework** ([Christensen](https://hbr.org/2016/09/know-your-customers-jobs-to-be-done)) — a research method for understanding user motivations, not a strategy-doc structure. JTBD findings would *populate* the Mission and Guiding Principles sections; they don't replace them. AL-7's milestone scope mentions JTBD as a section topic in PROJECT.md ("vision, target users, jobs-to-be-done…") — fine; that lives inside Mission.
- **GIST planning, Now/Next/Later roadmap, etc.** — execution-layer roadmap formats. Belong in milestone planning, not the strategy doc.
- **Vision/Mission/Values triad (corporate templates)** — too generic; the Sourcegraph template covers Mission and uses "Guiding Principles" instead of "Values," which is the better word for engineering-team strategy.

---

## Recommended TOC skeleton (the deliverable Phase A authors fills in)

The synthesizer should hand this directly to the requirements-definition pass. Each `>` is an authoring prompt taken or adapted from the Sourcegraph template, with AgentLinux-specific framing.

```markdown
# AgentLinux Product Strategy

> One-paragraph elevator opener: what AgentLinux is, who it serves, and why
> v0.5.0 broadened from one pillar to three. Anchor link to AL-7 and to the
> framing ADR (slot reserved for ADR-016).

Quicklinks:
- ADR-016 — Three-pillar product framing (the framing decision)
- docs/STABILITY-MODEL.md — pillar 2 seed (ADR-011)
- README.md — install + verify story
- agentlinux.org — public landing page (refreshed to mirror this framing)

## Mission

> Why AgentLinux exists. The 3-to-10-year horizon. Fundamental value provided.
> Key audiences, and audiences we're explicitly *not* serving (e.g., desktop
> end-users, ARM-only deployments today).

### Positioning statement

> One paragraph in Geoffrey Moore form:
> *"For [agent operators / dev-tools engineers / OSS contributors building
> on top of LLM coding agents] who [need a Linux host where agent toolchains
> install, self-update, and run without permission breakage or version drift],
> AgentLinux is a [installable Ubuntu plugin] that [provisions a dedicated
> agent user with a curated, benchmarked, security-hardened toolchain].
> Unlike [a hand-rolled `sudo npm install -g` setup, or a generic devcontainer,
> or a vendor's bundled CLI installer], AgentLinux [pins what it ships, tests
> the combo end-to-end before release, and surfaces drift explicitly via
> `agentlinux upgrade`]."*

## The three pillars (tenets)

> Each pillar is phrased as a tenet — a stance, not a feature. Each one is
> 3–6 sentences, ends with a "what this rules out" clause, and links to
> existing in-repo evidence (ADR / requirement / behavior test).

### Pillar 1: Separated, correctly-owned agent environment

> The v0.3.0 core. Foundational, not changing in v0.5.0.
> Cite: ADR-004 (per-user npm prefix), ADR-005 (system Node.js), ADR-012
> (agent sudo), AGT-02 (canonical self-update test), README "About" section.

### Pillar 2: Stability + best-tested setup with measurable benchmarks

> The v0.3.0 stability model (ADR-011) is the seed. v0.5.0 commits to
> *measurable* benchmarks vs vanilla setups along three axes:
> token consumption, throughput/speed, task success rate. The harness,
> dataset, and scoring methodology land in a v0.6+ Benchmarks milestone.
> Cite: ADR-011, docs/STABILITY-MODEL.md, ADR-007 (Docker+QEMU harness),
> v0.3.0 TST-08 pinned-combo gate.

### Pillar 3: Security hardening

> Two threat surfaces: (a) supply-chain attacks on the agent toolchain
> (npm registry compromise, recipe tampering, transitive deps), and
> (b) prompt/tool-injection attacks against the agent itself
> (OWASP LLM Top 10 territory, Anthropic tool-use safety guidance).
> v0.5.0 surfaces threat models + roadmap themes; mitigations land in a
> v0.6+ Security Hardening milestone.
> Cite: ADR-006 (curl-pipe-bash + SHA256), ADR-014 (secret remediation),
> ADR-013 (MIT license — community trust surface).

## Guiding principles

> 4–7 short stances that thread through all three pillars.
> Examples to consider (Phase A picks the actual list):
> - "Behavior tests are the spec" (already ADR-002)
> - "We test exactly what we ship" (the ADR-011 stability contract)
> - "Curated combos, not thin wrappers" (ADR-011 negative space)
> - "No silent drift" (the agentlinux upgrade contract)
> - "Trust through evidence, not assertion" (provenance for pillars 2+3)

## Where we are now

> v0.4.0 OSS-released; v0.5.0 broadens framing; v0.6+ implements pillars
> 2 and 3. Honest current-state assessment per pillar:
> - Pillar 1: production-ready (54 requirements, all bats-covered)
> - Pillar 2: stability seed shipped (ADR-011); benchmarks not yet built
> - Pillar 3: baseline hygiene shipped (gitleaks gate, MIT, branch
>   protection); threat model not yet authored

### Top issues / contributor pain points

> What external observers / contributors are likely to ask. Optional;
> Phase A may collapse this if we don't yet have signal.

### Competitive landscape

> Devcontainer / GitHub Codespaces / Coder.com / Daytona / Devbox / Nix
> shells / hand-rolled provisioners. AgentLinux's differentiated position:
> "we're the only one designed for agents-as-primary-users, not humans-as-
> primary-users-occasionally-running-agents."

## Strategy and plans

### Themes for v0.6+

> 3–5 themed buckets, each with a 1–2 sentence rationale. Likely seeds:
> - **Benchmarks Harness** (pillar 2 implementation milestone)
> - **Security Hardening** (pillar 3 implementation milestone)
> - **Distro Reach** (Fedora/Alma/Arch — pillar 1 expansion)
> Themes are *directional*, not committed phases. Phase commits happen at
> the next /gsd-new-milestone.

### What we're explicitly *not* working on & why

> - Multi-arch (ARM): demand insufficient; x86_64 only for now.
> - Desktop / GUI agent installer: out of scope; CLI is the contract.
> - Custom distro / ISO: retired in the v0.2.0 → v0.3.0 pivot
>   (ADR-001).
> - Per-agent .deb packages as standalone distro artifacts: superseded
>   by curated combos (ADR-011).
> - Pillar 2 + pillar 3 *implementation* in v0.5.0: deferred to v0.6+
>   so the framing locks before implementation picks scope.

## Appendix A: One-page Vision Board

> A condensed Roman Pichler Product Vision Board (Vision / Target Group /
> Needs / Product / Business Goals) on a single page, for fast scanning
> by people who don't read the whole strategy. Pure markdown table form.

## Appendix B: Roadmap themes (forward-looking)

> Re-statement of "Themes for v0.6+" with 1-2 paragraph elaboration each.
> Lives in the strategy doc rather than ROADMAP.md so the website +
> CONTRIBUTING can link to one canonical forward-looking surface.
```

**Authoring effort estimate:** 1 phase, ~3–6 hours of writing, ~6–8 KB final size. The framework is now decided; Phase A is fill-in-the-blanks against the TOC above.

---

## Tooling / format decision

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Single Markdown file** (`docs/STRATEGY.md`) | Stable URL; one canonical link from website + CONTRIBUTING + ADRs; renders natively in GitHub; matches `STABILITY-MODEL.md` precedent. | Long-doc cognitive load if it bloats past ~10 KB. Mitigation: discipline + Appendix A as a TL;DR. | ✓ **Recommended.** |
| **`docs/strategy/` tree of MD files** (e.g., `MISSION.md`, `PILLARS.md`, `ROADMAP.md`) | Each file fits on one screen; easier to PR-review individually. | URL fragmentation — "the strategy doc" becomes 5 URLs. Cross-linking from ADRs / website / contributing gets messy. Premature for ~6 KB total content. Adds an extra navigation step. | ✗ Reject — only worth it if doc grows past 15+ KB, which it shouldn't at this milestone. |
| **README.md embedded sections** | Maximum visibility on the GitHub front page. | README is already 156 lines and doing install/verify/uninstall + stability + security + contributing duty; adding strategy bloats it. README's job is "how do I use this on my Ubuntu box right now"; strategy's job is "what is this project trying to be." Two different reader intents. | ✗ Reject — link to STRATEGY.md from a short "Project strategy" line in README instead. |
| **Graphical canvas image** (Pichler board, Lean Canvas, etc.) | Scannable; impressive to non-technical viewers. | Not git-diffable, breaks accessibility, becomes stale silently. AgentLinux's audience is engineers who read Markdown. | ✗ Reject as primary; allow a static rendered image *in addition to* the Appendix A markdown table if a contributor enjoys making one. |
| **Notion / Confluence / external doc** | Rich formatting. | Repo loses ownership, link-rot risk, fork-unfriendly, defeats AL-7's "canonical in-repo" goal. | ✗ Reject. |

**Recommended format:** **Single Markdown file**, target 4–8 KB (same scale as `docs/STABILITY-MODEL.md`'s 5.4 KB). All visual structure inside the file uses standard MD: H2/H3 headings, tables for the appendix, blockquotes for tenet-restatement.

---

## Repo location decision

| Candidate path | Pros | Cons | Verdict |
|----------------|------|------|---------|
| **`docs/STRATEGY.md`** | Sibling to existing `docs/STABILITY-MODEL.md` and `docs/HARNESS.md` — same "ALL-CAPS keystone doc in `docs/`" convention already established and link-cited from README. Stable URL. Matches the existing voice/format pattern. | None substantive. | ✓ **Recommended.** |
| `docs/strategy/STRATEGY.md` | Future-proofs for sub-files. | Premature directory; introduces a one-file folder for no current benefit; URL changes vs flat path. | ✗ Reject. |
| `docs/PRODUCT.md` | Generic name. | "Product" overloads with a noun AgentLinux doesn't currently use anywhere; introduces new vocabulary instead of leaning on the established "strategy" framing AL-7 already uses. | ✗ Reject. |
| `docs/MISSION.md` | Short, scannable. | Mission is *one section* of the doc, not the whole doc. Mis-naming the file by its smallest section. | ✗ Reject. |
| `docs/VISION.md` | Common OSS pattern (e.g., armistice/VISION.md). | Same problem as MISSION — vision is a section, not the doc. Also implies aspirational/forward-looking, but the doc is also retrospective ("where we are now"). | ✗ Reject. |
| `STRATEGY.md` at repo root | Maximum visibility. | Breaks the existing `docs/`-houses-prose-docs convention (only README, LICENSE, CONTRIBUTING, CHANGELOG, CODE_OF_CONDUCT live at root). README + LICENSE are GitHub-first-class; STRATEGY isn't. | ✗ Reject. |
| `README.md` embedded section | Visibility. | See "tooling" table above — wrong reader intent. | ✗ Reject. |

**Stability argument for `docs/STRATEGY.md`:** AgentLinux's `docs/` already has three keystone all-caps prose docs (`HARNESS.md`, `STABILITY-MODEL.md`, plus the older retired-to-archive variants). Adding `STRATEGY.md` continues that convention and inherits its stability properties — links from the website, CONTRIBUTING, future ADRs, and external blog posts will all use one URL that doesn't move. The convention is already cemented; we're not setting precedent, we're reinforcing it. The only thing that could move this URL is a wholesale `docs/` → `documentation/` rename, which has zero precedent in the repo or in any considered alternative.

---

## Cross-link plan

The doc is the hub of a small star network. Phase A wires these in *both directions* (the strategy doc cites them; they get a back-pointer to the strategy doc).

### ADRs the strategy doc cites (in approximate order of appearance)

| Section in STRATEGY.md | ADRs cited | Why |
|------------------------|------------|-----|
| Mission > Positioning statement | (none — uses competitor names, not ADRs) | Positioning doesn't need ADR backing |
| Pillar 1 | ADR-001 (pivot), ADR-004 (per-user npm prefix), ADR-005 (system Node.js), ADR-012 (agent sudo) | The four foundational v0.3.0 decisions that *are* pillar 1 |
| Pillar 2 | ADR-011 (stability-first pinning), ADR-007 (Docker+QEMU harness) | The seeds the v0.6+ benchmarks milestone builds on |
| Pillar 3 | ADR-006 (curl-pipe-bash + SHA256), ADR-013 (MIT), ADR-014 (secret remediation) | Existing baseline hygiene; the v0.6+ security milestone extends |
| Guiding principles | ADR-002 (behavior contract), ADR-011 (stability-first), ADR-010 (review loop) | The principles already shipping as decisions |
| Where we are now > pillar status | ADR-002 (bats as spec), ADR-011, ADR-013 | Cite the audit trail for the maturity claims |
| What we're not working on > "Custom distro" | ADR-001 (pivot) | The decision that closed that direction |
| What we're not working on > "Per-agent .debs" | ADR-011 | The decision that superseded that path |
| Themes > "Distro Reach" | ADR-009 (Snap disqualified) | Negative-space precedent for the future distro-reach work |

### New ADR slot reserved

**ADR-016 — Three-pillar product framing (v0.5.0 agenda redefinition).** Authored alongside `STRATEGY.md` in Phase A. Captures: the framing decision, the rejected single-pillar alternative ("stay at v0.3.0 framing forever"), the rejected over-broad alternative ("five pillars including DX and ecosystem"), and the AL-7 connection. Both `docs/STRATEGY.md` and ADR-016 cross-link to each other. Same pattern as `STABILITY-MODEL.md` ↔ ADR-011.

### Documents that gain a back-pointer to STRATEGY.md

| File | Where the back-pointer goes |
|------|------------------------------|
| `README.md` | New short paragraph between "About" and "License" sections: *"Project strategy & roadmap themes: see [docs/STRATEGY.md](docs/STRATEGY.md)."* |
| `CONTRIBUTING.md` | New "Why this project exists" paragraph linking to STRATEGY.md, so external contributors land on framing before code. |
| `.planning/PROJECT.md` | "Core Value" section gains a one-liner: *"Full strategy doc: docs/STRATEGY.md (since v0.5.0)."* |
| `docs/STABILITY-MODEL.md` | "Related" section gains a bullet pointing to STRATEGY.md pillar 2. |
| `docs/decisions/011-stability-first-version-pinning.md` | "Status" or "References" section gains a STRATEGY.md pillar-2 link. |
| `agentlinux.org` (website refresh phase) | Homepage three-pillar section links each pillar header to its `STRATEGY.md#pillar-N` anchor. |

---

## OSS exemplars (downstream phases use these as authoring references)

The field of OSS dev-tools projects with explicit, in-repo strategy docs is **sparse** — that's itself a finding. Most projects (mise, devbox, ripgrep, uv, ruff, headscale) communicate strategy implicitly through README taglines + benefit lists, not via a dedicated document. The exemplars below are the projects that *do* publish something formal enough to copy patterns from.

| # | Project | Doc | What works | What doesn't | Lesson for AgentLinux |
|---|---------|-----|------------|--------------|------------------------|
| 1 | **Jujutsu (jj-vcs)** | [docs/core_tenets.md](http://docs.jj-vcs.dev/latest/core_tenets/) + [docs/roadmap.md](http://docs.jj-vcs.dev/latest/roadmap/) | Tenets are *short* (12 bullets, ~1 page), each a stance not a feature. Roadmap is themed (8 themes), not date-committed. Both files live flat in `docs/`. | Tenets and roadmap don't cross-link to each other. No positioning statement; no "what we're not working on." Reads as engineer-to-engineer, not contributor-onboarding. | **Direct precedent for `docs/STRATEGY.md` location convention.** Steal: tenet-bullet style for the three pillars; themed-not-dated roadmap form for Appendix B. |
| 2 | **Sourcegraph handbook** | [page_templates/strategy_template.md](https://github.com/sourcegraph/handbook/blob/main/page_templates/strategy_template.md) | Best public, MIT-licensed strategy template by a dev-tools company. Explicit prompts for "what we're not working on & why." Authoring guidance baked in as blockquoted instructions. | It's a *template*, not a filled-in instance — you don't see a real strategy doc, only the skeleton. (Sourcegraph's per-team filled instances are scattered across their handbook's product pages.) | **The skeleton AgentLinux's strategy doc adopts.** Already mapped in the TOC above. |
| 3 | **Prettier** | [docs/option-philosophy.md](https://github.com/prettier/prettier/blob/main/docs/option-philosophy.md) | Single-page opinion-anchoring doc that lives in `docs/`. Public, citable, gets pointed to in every "why won't Prettier add option X" issue. Voice is opinionated and direct ("Prettier is opinionated. Options are frozen. Why."). | Narrow scope — only addresses the option-philosophy question, not whole-product strategy. | **Voice precedent for AgentLinux's pillar tenets.** Be explicit, take a stance, name the negative space. |
| 4 | **Tailscale** | [tailscale.com/opensource](https://tailscale.com/opensource) (web page, not in-repo) | Conversational, candid ("we're still figuring this out"). Mixes principles with concrete actions. Self-aware about closed-source pieces. | Lives on the marketing site, not in the repo — link-stable but not git-tracked, harder for forks to inherit. | **What *not* to do for AgentLinux.** AL-7 explicitly wants the strategy doc *in the repo* so it's git-tracked and ADR-citable. Borrow Tailscale's candid tone but keep the doc in `docs/`. |
| 5 | **Sigstore** | [docs.sigstore.dev/about/overview](https://docs.sigstore.dev/about/overview/) + project [governance docs](https://github.com/sigstore/community) | Foundation-backed, multi-stakeholder; mission ("make it easy for developers to sign releases") + project goals (short-term, medium-term) split across overview page and community repo. | Spread across multiple locations (overview page + community repo + project docs) — exactly the fragmentation problem AL-7 wants to avoid. | **Negative example for repo-location.** Cohere your strategy in *one* file; don't spread it across an overview page + a community repo + a roadmap page. |
| 6 | **Headscale** | [README "Design goals" section](https://github.com/juanfont/headscale#design-goals) | Single short section in README; explicit about *narrowness* of scope ("personal use, single tailnet"); tells contributors what won't be accepted. | Lives in README, so it competes for attention with install/usage. Short enough that this works *here*, but doesn't scale. | **Validates the "what we're not doing & why" prompt.** Headscale's narrowness statement is exactly the forcing function AL-7 wants for "pillar-2-and-3-implementation-is-not-v0.5.0." But put it in `STRATEGY.md`, not the README. |

**Field-level finding:** the OSS dev-tools world *under-invests* in published strategy docs. AgentLinux publishing one is itself a differentiator — the doc becomes a contributor-recruitment tool, not just a planning artifact. This reinforces AL-7's framing that the strategy doc *is* the v0.5.0 deliverable, not a side-effect.

---

## What to actively avoid

| Anti-pattern | Why bad | Use instead |
|--------------|---------|-------------|
| **Future-dated press-release voice** (Amazon PR-FAQ form) | Clashes with AgentLinux's existing engineer-author voice in README + ADRs; forces single-launch framing on a multi-pillar broadening | Sourcegraph-template prose voice — present-tense, declarative, evidence-cited |
| **Five+ pillars** | The whole point of AL-7 is broadening *to three* — five would dilute and re-trigger the "too narrow / too broad" oscillation | Lock at exactly three; reserve a "themes" section for everything else |
| **Quantitative commitments without baselines** ("benchmark X% faster than vanilla") | Pillar 2 implementation hasn't built the benchmark harness yet; strategy doc is the wrong place to commit a number | Use directional language ("measurable benchmarks vs vanilla on three axes: tokens, speed, success rate") and defer the numbers to the v0.6+ benchmarks milestone |
| **Mixing strategy with tactics** | Strategy doc bloats with how-to detail and stops being strategy (Rumelt's #1 bad-strategy failure mode: confusing goals with strategy) | Tactics live in milestone planning (`.planning/MILESTONES.md`, ROADMAP.md). STRATEGY.md sticks to *what* and *why* |
| **Linking to private/internal sources** (Jira AL-7 from public-facing strategy doc paragraph) | Public OSS contributors can't read Jira; broken-trust signal | Reference AL-7 as the *authoring origin* in ADR-016 (which is metadata) but make STRATEGY.md self-contained for any public reader |
| **Adding the strategy doc to `.planning/`** | `.planning/` is GSD workflow state, not documentation (per CLAUDE.md project context) — would hide the doc from external contributors | `docs/STRATEGY.md` per the location decision above |

---

## Sources

### Frameworks (HIGH confidence — direct primary sources)

- [Roman Pichler — Product Vision Board (v01/2023)](https://www.romanpichler.com/tools/product-vision-board/) — Vision / Target Group / Needs / Product / Business Goals, 5 sections
- [Roman Pichler — Product Vision Board PDF + checklist](https://www.romanpichler.com/downloads/tools/Product-Vision-Board-with-Checklist.pdf)
- [Working Backwards — PR/FAQ process](https://workingbackwards.com/concepts/working-backwards-pr-faq-process/) — Bryar & Carr, *Working Backwards*
- [Working Backwards — PR/FAQ template + instructions](https://workingbackwards.com/resources/working-backwards-pr-faq/)
- [Geoffrey Moore — positioning statement](https://geoffreyamoore.com/positioning/) — *Crossing the Chasm* template (For/Who/Is a/That/Unlike)
- [Amplitude — North Star Framework overview](https://amplitude.com/books/north-star/about-north-star-framework)
- [Amplitude — North Star Metric & Inputs](https://amplitude.com/books/north-star/amplitudes-north-star-metric-and-inputs)
- [Lean Canvas — Ash Maurya PDF](https://s3.amazonaws.com/leanstack/v4/Lean-Canvas.pdf) — 9 building blocks, 2010
- [Tenets at Amazon — Pedro Delgallego writeup](https://pedrodelgallego.github.io/blog/amazon/mental-models/decision-making/tenets-at-amazon/)
- [Tenets supercharging decision-making — AWS Executive in Residence Blog](https://aws.amazon.com/blogs/enterprise-strategy/tenets-supercharging-decision-making/)
- [Sourcegraph handbook — strategy_template.md](https://github.com/sourcegraph/handbook/blob/main/page_templates/strategy_template.md) — primary template adopted as spine
- [Sourcegraph handbook — strategy_template.md (raw)](https://raw.githubusercontent.com/sourcegraph/handbook/main/page_templates/strategy_template.md) — full text fetched
- [Richard Rumelt — *Good Strategy Bad Strategy*](https://www.amazon.com/Good-Strategy-Bad-Difference-Matters/dp/0307886239) — kernel framework (Diagnosis / Guiding Policy / Coherent Action)
- [Rumelt strategy kernel — Fred Perrotta summary](https://www.fredperrotta.com/kernel-of-strategy/)

### OSS exemplars (HIGH confidence — direct repo links)

- [Jujutsu — Core Tenets](http://docs.jj-vcs.dev/latest/core_tenets/) — 12-bullet tenet list, in-repo at `docs/core_tenets.md`
- [Jujutsu — Roadmap](http://docs.jj-vcs.dev/latest/roadmap/) — 8 themed sections, no dates
- [Jujutsu — docs/ tree](https://github.com/jj-vcs/jj/tree/main/docs)
- [Prettier — Option Philosophy](https://github.com/prettier/prettier/blob/main/docs/option-philosophy.md) — single-page opinion-anchoring doc in `docs/`
- [Tailscale — Open Source page](https://tailscale.com/opensource) — conversational principles on marketing site (negative example for in-repo authoring)
- [Sigstore — overview](https://docs.sigstore.dev/about/overview/) — fragmented multi-stakeholder mission (negative example for cohesion)
- [Headscale — README design goals](https://github.com/juanfont/headscale) — narrowness-of-scope precedent
- [Devbox — README](https://github.com/jetify-com/devbox) — surveyed; no dedicated mission/vision doc (field-level finding)
- [mise-en-place — README](https://github.com/jdx/mise/blob/main/README.md) — surveyed; no dedicated philosophy doc (field-level finding)
- [ripgrep — README](https://github.com/BurntSushi/ripgrep) — surveyed; design goals embedded in README, no separate doc

### Field-level / methodological (MEDIUM confidence — multiple converging secondary sources)

- [Linux Foundation — Setting an Open Source Strategy](https://www.linuxfoundation.org/resources/open-source-guides/setting-an-open-source-strategy)
- [TODO Group — Setting an Open Source Strategy guide](https://github.com/todogroup/todogroup.org/blob/main/content/en/guides/strategy.md)
- [Red Hat — Crafting an open source product strategy](https://www.redhat.com/en/blog/crafting-open-source-product-strategy)

---

*PM-strategy-doc framework research for AgentLinux v0.5.0 agenda redefinition (anchored on Jira epic AL-7).*
*Researched: 2026-05-09. Synthesizer: feed the TL;DR block and the recommended TOC skeleton into SUMMARY.md and the requirements-definition pass.*
