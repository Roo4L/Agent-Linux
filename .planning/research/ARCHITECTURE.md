# Architecture Research — v0.5.0 Agenda Redefinition

**Scope:** Where the canonical product-strategy document lives in the AgentLinux repo, how it cross-links to ADRs / README / CONTRIBUTING / roadmap, and how the new framing propagates to agentlinux.org under the static-site / no-build-step constraint.

**Researched:** 2026-05-09
**Overall confidence:** HIGH (repo state directly inspected; OSS exemplars verified via WebFetch)

---

## Repo state inspected (factual baseline, not re-research)

- **Site source lives at the repo root, not under `site/` or `website/`.** `index.html` (895 LOC), `CNAME`, `sitemap.xml`, `robots.txt`, and `assets/` (crab-mascot.svg, favicon.svg, og-image.svg) all sit at the repo root. There is no `site/`, `website/`, or `public/` directory. The `docs/HARNESS.md` §1.1 layout shows `website/` as the planned location, but the actual implementation never moved the files — they stayed at the root from v0.1.0. **The milestone-context's reference to a `site/` directory is incorrect.** Any v0.5.0 Site-Refresh phase touches root-level `index.html` + `assets/`, not a subfolder.
- **`.github/workflows/deploy.yml` confirms the no-build constraint.** The workflow stages files into `_site/` with `cp` only — `index.html`, `CNAME`, `sitemap.xml`, `robots.txt`, `assets/`, plus `packaging/curl-installer/install.sh` (Pattern 5: anti-drift install.sh source) — then `JamesIves/github-pages-deploy-action@v4.8.0` ships the bundle to the `gh-pages` branch. Zero build step. Zero markdown→HTML rendering. PR previews share the gh-pages branch under `pr-preview/*`.
- **`docs/` already houses one user-facing companion to an ADR.** `docs/STABILITY-MODEL.md` (124 LOC) is the TL;DR of ADR-011, written in plain prose, lives at `docs/STABILITY-MODEL.md` (single file, uppercase, top of `docs/`). It is the closest precedent in-tree for what the strategy doc will look like, and it sits comfortably alongside `docs/HARNESS.md` (internal harness spec) at the same level. README.md links to it from two places (the "Stability model" section + the "Links" section).
- **ADR catalog covers 001–014.** `docs/decisions/000-template.md` defines the ADR template (Status / Date / Context / Decision / Consequences / References). The next ADR will be **ADR-016** for the v0.5.0 framing decision.
- **`README.md` (157 LOC) is install-focused.** Sections in order: Install / Verify / Uninstall / Stability model (3-paragraph summary + link out to `docs/STABILITY-MODEL.md` + link out to ADR-011) / Escape hatch / Requirements / Security / Contributing / License / Links / About. The "About" section at the bottom is the only place product *rationale* (the EACCES/recursive-shim story) appears, and it's a single paragraph. The README does **not** carry the three-pillar framing today.
- **`CONTRIBUTING.md` (101 LOC) references behavior-test contract + review loop**, points at `docs/HARNESS.md` and `docs/decisions/013-license-mit.md`. It does not currently reference any "strategy" or "vision" document.
- **`index.html` is pre-pivot in framing.** The hero says "A purpose-built Linux distribution" (distro framing, retired in ADR-001). The Features section shows 8 cards including "Multiple distribution formats" with QEMU/Docker micro-VMs (also retired). Sections in nav order: Hero → Problem → Features → Comparison → Signup → FAQ. **The site is roughly two pivots behind product reality** — it still positions AgentLinux as a custom distro and does not mention pillars, plugin/curl-install, or the v0.3.0 catalog. A site refresh is not optional in v0.5.0; even without the strategy doc, the current site contradicts the README.

---

## Part A — Where the strategy doc lives

### Recommendation: **`docs/STRATEGY.md`** (Option 2, single file in `docs/`)

**One sentence:** Single file, uppercase, alongside the existing `docs/STABILITY-MODEL.md` and `docs/HARNESS.md` — same level, same case convention, same "user-facing companion to an ADR" mental model the project has already shipped once.

### Rationale (stability + discoverability + ergonomics + precedent)

**Stability (URLs won't break):**
- Single-file location at `docs/STRATEGY.md` is one URL. The website link-out is one anchor: `https://github.com/Roo4L/Agent-Linux/blob/master/docs/STRATEGY.md` (or `https://agentlinux.org/strategy` if we add a redirect/page). One file, one stable URL.
- A folder (`docs/strategy/`) means N URLs (VISION.md, USERS.md, PILLARS.md, ROADMAP-THEMES.md), each independently stable, each independently breakable. Renames inside the folder break inbound links from the website, ADRs, CONTRIBUTING, future ROADMAPs.
- Root-level `STRATEGY.md` (Option 5) is also one URL but pollutes the repo root — README + LICENSE + CONTRIBUTING is the conventional root-level set; adding a fourth strategy doc starts a slippery slope toward also needing root-level VISION/MISSION/values/etc. The OSS pattern (verified below) is to keep the root sparse and route reference docs into `docs/`.
- README-embedded (Option 6) means the strategy "URL" is a README anchor (`README.md#what-we-believe`) — anchors are fragile (renaming the section breaks links) and the README itself rotates with version stamps and install-instruction edits. Worst stability of all the options.

**Discoverability (a new contributor finds it):**
- A new contributor lands on README → sees a "Strategy" link in the existing **Links** section (already conventional) → finds `docs/STRATEGY.md`. One hop.
- They land on `docs/HARNESS.md` (a developer would for harness questions) → sibling file `STRATEGY.md` is visible in the same directory listing. One look.
- They land on the GitHub repo file browser → `docs/` is the first folder a curious reader opens after `README.md`; a single `STRATEGY.md` at the top of `docs/` is impossible to miss. Three discovery paths converge on the same file.
- A `docs/strategy/` folder hides the entry point one level deeper. Discoverability still works (contributors find folders) but the "where do I start in this folder?" question is non-trivial — folders demand a `README.md` index, which adds maintenance cost and a second rename trap.

**Authoring ergonomics (single MD vs tree):**
- Single MD: one diff to review, one file in PRs, one set of cross-link anchors to maintain, no inter-file ordering question. Fits the AgentLinux convention of writing reference docs as opinionated single files (HARNESS.md is 492 lines and works fine as one file; STABILITY-MODEL.md is 124 lines).
- Tree: enables independently-evolving sub-docs but creates the "where does this section go?" decision overhead for every edit and the "are USERS.md and PILLARS.md consistent with each other?" review burden. Premature for a v0.5.0 strategy doc that will probably ship under 500 lines on first cut.
- The tree decomposition (VISION.md / USERS.md / PILLARS.md / ROADMAP-THEMES.md) is reachable later as `docs/STRATEGY.md` grows, by promoting it to `docs/strategy/README.md` with the section files alongside. The single-file → folder migration is mechanical and only happens when the file's size genuinely warrants the split.

**Naming-convention precedent (OSS comparable projects, verified):**
- **OpenTelemetry Collector** ships `docs/vision.md` (single file, lowercase, in `docs/`) — explicitly described as "a living document that is expected to evolve over time" serving as guidance for design decisions. This is the **closest direct precedent** to AgentLinux's situation (CNCF infrastructure project, technical product, public ADRs, single-file strategy artifact in `docs/`). [Source](https://github.com/open-telemetry/opentelemetry-collector/blob/main/docs/vision.md)
- **OpenTelemetry Community** uses `mission-vision-values.md` (root of community repo, lowercase). [Source](https://github.com/open-telemetry/community/blob/main/mission-vision-values.md)
- **Watermelon Tools** ships a public-handbook with `Strategy.md` at its root. [Source](https://github.com/watermelontools/public-handbook/blob/main/Strategy.md)
- **AgentLinux's own precedent:** `docs/STABILITY-MODEL.md` (uppercase, single file, in `docs/`). The v0.5.0 doc should follow this convention for consistency, not the lowercase OTel convention — because deviating from the in-repo precedent costs more in cognitive overhead than mimicking external precedent gains in alignment.

### Naming choice: STRATEGY vs PRODUCT vs MISSION

| Name | What it implies | AgentLinux fit |
|------|-----------------|----------------|
| `STRATEGY.md` | Pillars, positioning, roadmap themes, who-it's-for, what-we-won't-build | **Best fit.** Matches the doc's actual content (per the v0.5.0 milestone definition: vision + target users + JTBD + three pillars + non-goals + positioning + roadmap themes). |
| `PRODUCT.md` | What it is, what it does, scope | Too narrow; doesn't carry the "and where it's going" weight of the roadmap-themes appendix. Closer to a product-marketing one-pager. |
| `MISSION.md` | Single-sentence purpose | Too narrow; mission is one section of the strategy doc, not the whole thing. |
| `VISION.md` | Aspirational long-term north star | Adjacent but narrower. OpenTelemetry Collector chose this name and the doc ended up being 23 lines — fits *that* scope (project north star) but not *this* scope (pillars + non-goals + positioning + roadmap themes). |

**Pick STRATEGY.md.** The other names create scope ambiguity that costs more than naming consistency saves.

### Hybrid-with-README (Option 7) — rejected, with a caveat

A short top-level mission paragraph in README + detailed `docs/STRATEGY.md` is tempting. Reject it as the *primary* strategy location, but **adopt a narrow form**: README's existing **About** section gets one new sentence that names the three pillars and links to `docs/STRATEGY.md`. This is README hygiene, not strategy duplication — README stays install-focused, STRATEGY.md stays canonical.

### Tie-breaker question for the user (none)

This recommendation is unambiguous. No tie-breaker needed; the in-repo precedent (STABILITY-MODEL.md) is too strong to override.

---

## Part B — Cross-link map

### A. Outbound: from `docs/STRATEGY.md` → other artifacts

| STRATEGY.md section | References (with anchor) | Why |
|---------------------|--------------------------|-----|
| **Vision / Mission** (top of doc) | — | Self-contained; no outbound links. |
| **Target users / JTBD** | README.md "About" section, agentlinux.org `#problem` section | Establishes who the pillars serve; the existing problem framing on the site + README About paragraph are the prior-art statements being broadened. |
| **Pillar 1 — Separated, correctly-owned agent environment** | `docs/decisions/001-pivot-distro-to-plugin.md` (origin of plugin shape), `docs/decisions/004-per-user-npm-prefix.md` (load-bearing technical decision), `docs/decisions/012-agent-user-full-sudo.md` (privilege posture), README.md "About" section (EACCES/recursive-shim story) | Pillar 1 is the v0.3.0 surface; ADR-001 explains the shape, ADR-004 the keystone, ADR-012 the privilege boundary. Each ADR earns a one-line callout in this section. |
| **Pillar 2 — Stability + best-tested setup, with measurable benchmarks** | `docs/decisions/011-stability-first-version-pinning.md` (the seed), `docs/STABILITY-MODEL.md` (user-facing companion), v0.6+ "Benchmarks Milestone" placeholder | ADR-011 is the seed of pillar 2; the v0.5.0 doc extends "tested combo" → "tested combo with publishable comparative benchmarks." Forward link to the v0.6+ milestone is a roadmap-themes-appendix item. |
| **Pillar 3 — Security hardening (supply chain + prompt/tool injection)** | `docs/decisions/012-agent-user-full-sudo.md` (open question — agent has root via sudoers; how does pillar 3 reconcile?), `docs/decisions/006-curl-pipe-bash-plus-deb.md` (delivery-channel trust story; SHA256 today, GPG roadmap), `docs/decisions/014-secret-remediation-noop.md` (secret-handling baseline), v0.6+ "Security Hardening Milestone" placeholder, OWASP LLM Top 10 + Anthropic tool-use safety guidance (external) | Pillar 3 is forward-looking. ADR-012 is a known tension (full sudo for the agent is great for productivity, hard to defend under a hardening framing); ADR-016 should explicitly note this and defer the resolution. |
| **Positioning vs alternatives** | README.md (the `Why not just use what exists?` section is the website's prior framing), agentlinux.org `#comparison` section | The strategy doc replaces the comparison framing with the new three-pillar one; the existing site copy is the "before" reference. |
| **Non-goals / out-of-scope** | `.planning/PROJECT.md` "Out of Scope" sections (existing canonical list), `docs/decisions/009-snap-disqualified.md` (worked example of an explicit non-goal) | Consolidates scattered "we won't do X" statements; PROJECT.md's Out of Scope remains the *operational* truth, STRATEGY.md is the *narrative* truth. |
| **Roadmap themes appendix** | (Forward links to milestones that don't exist yet — placeholders only.) | These resolve into actual `.planning/milestones/v0.6.x-*/` paths once new milestones get scoped. The strategy doc keeps placeholder names, not paths. |
| **Decision provenance** (last section) | `docs/decisions/016-agenda-redefinition.md` (the framing-decision ADR) | One-sentence pointer: "the framing decision and the discarded alternatives are recorded in ADR-016." |

### B. Inbound: artifact → STRATEGY.md (which existing files need updates)

| File | What needs updating | Edit type |
|------|---------------------|-----------|
| **`README.md`** | (a) Add a one-sentence three-pillar summary in the **About** section. (b) Add `docs/STRATEGY.md` link to the **Links** section. (c) Optionally bump the install hero tagline if the framing demands it (likely deferred — install instructions stay install instructions). | New requirement; small, surgical |
| **`CONTRIBUTING.md`** | Add a one-sentence "the project's strategic direction is documented in `docs/STRATEGY.md`" line near the top, right after "Thanks for considering a contribution. AgentLinux is small, opinionated, and behavior-test-driven." | New requirement; one-line addition |
| **`docs/decisions/016-agenda-redefinition.md`** (the new ADR) | Reference STRATEGY.md as the "implemented decision artifact" in its References section: *"`docs/STRATEGY.md` — the canonical strategy document this ADR authorizes."* | New file (the v0.5.0 ADR creation itself) |
| **`docs/decisions/011-stability-first-version-pinning.md`** | Add a forward-reference in its References section: *"`docs/STRATEGY.md` Pillar 2 — extends pinning into measurable benchmarks."* | Optional (bidirectional link); recommended |
| **`docs/decisions/012-agent-user-full-sudo.md`** | Add a forward-reference: *"`docs/STRATEGY.md` Pillar 3 — open tension under the security-hardening pillar; deferred to v0.6+ resolution."* | Optional (bidirectional link); recommended for honest documentation of the unresolved tension |
| **`docs/STABILITY-MODEL.md`** | Add `docs/STRATEGY.md` to its **Related** section. | Optional; recommended |
| **`docs/HARNESS.md`** | No update needed — HARNESS is internal harness spec, orthogonal to strategy. | None |
| **`.planning/PROJECT.md`** | The "Current Milestone v0.5.0" section already exists; add a one-line pointer to `docs/STRATEGY.md` once it lands. | Required as part of milestone close |
| **`agentlinux.org` (`index.html`)** | See Part C below — section-level rewrite. | Required as part of v0.5.0 Site-Refresh phase |
| **Future `ROADMAP.md` (v0.6+ milestones, when they exist)** | Reference `docs/STRATEGY.md#roadmap-themes` as the source for milestone selection rationale. | Future requirement; scoped at the next `/gsd-new-milestone` |

### C. Map summary (graph form)

```
              docs/STRATEGY.md  (single canonical file)
              /  |  |  |  |  \
             /   |  |  |  |   \
            v    v  v  v  v    v
       README  ADR-016  ADR-011  ADR-012  ADR-001  agentlinux.org
       (back)  (back)   (back)   (back)   (back)   (back)
       CONTRIBUTING (back)
       STABILITY-MODEL (back)
       PROJECT.md (back)
       Future ROADMAP (back, when it exists)
```

Eight in-repo files cross-link to STRATEGY.md; STRATEGY.md cross-links to nine in-repo + external artifacts. All cross-links are explicit, anchored, and survive a single-file location.

---

## Part C — Website propagation

### Recommendation: **Option 4 (restructure landing-page IA) + Option 2 (link out to in-repo strategy doc as the deep version)**, executed by hand. Reject Option 3 (CI mirror).

**One sentence:** Hand-rewrite `index.html` sections so the IA reflects the three-pillar framing, and add a "Read the full strategy" link in the appropriate section pointing to `docs/STRATEGY.md` on GitHub — same way README.md links to STABILITY-MODEL.md today.

### Per-option assessment

**Option 1 — Hand-port the existing landing-page sections to match new framing.**
- *Pros:* Honors the no-build constraint; uses the existing 895-LOC HTML/CSS/JS file; keeps the dark JetBrains Mono aesthetic intact; no new tooling.
- *Cons:* The current IA (Hero → Problem → Features → Comparison → Signup → FAQ) is built around the **distro framing** (hero says "A purpose-built Linux distribution," features section advertises QEMU/Docker micro-VM distribution formats). Hand-porting in place leaves the IA around an old skeleton. **Goes one level deeper than necessary** — the right move is restructure, not patch.
- *Verdict:* Partial fit. Patching alone produces a Frankenstein page.

**Option 2 — Embed link-out to in-repo `docs/STRATEGY.md`.**
- *Pros:* Honors no-build constraint; keeps landing page lean and conversion-focused; routes serious readers to the canonical doc; mirrors the existing README → STABILITY-MODEL pattern (works well, no maintenance overhead, never goes stale because the canonical doc is one file).
- *Cons:* The link-out only adds value once the landing page IA actually matches the three-pillar framing — otherwise the visitor reads "purpose-built Linux distribution" in the hero, then clicks through to a strategy doc that says "installable extension that broadens to three pillars" and gets whiplash. Link-out alone is insufficient.
- *Verdict:* **Necessary but not sufficient.** Pair with Option 4.

**Option 3 — CI-mirror the strategy doc to HTML at deploy time.**
- *Pros:* Single source of truth — `docs/STRATEGY.md` is rendered to `https://agentlinux.org/strategy.html` automatically; no drift possible.
- *Cons:* **Violates the no-build-step constraint** (deploy.yml is `cp` only; adding markdown→HTML rendering means adding a markdown processor — pandoc, marked-cli, or a static-site generator — which is a real toolchain change). The maintenance cost (which renderer? which CSS? which template?) is non-trivial. Also *competes* with the GitHub-hosted `docs/STRATEGY.md` URL — visitors land on `agentlinux.org/strategy.html` instead of the GitHub blob view; the rendered version's stable URL is less obvious.
- *Verdict:* **Reject.** Constraint violation, low marginal value vs. a plain GitHub link, real maintenance burden.

**Option 4 — Restructure the landing-page IA for the broadening.**
- *Pros:* The existing site is **two pivots behind product reality** anyway (still positions AgentLinux as a distro). The website-refresh phase has to touch the IA regardless. Restructuring around the three pillars produces a coherent narrative aligned with the strategy doc; small refactor in HTML/CSS, no new tooling.
- *Cons:* More work than a patch — requires deciding new section structure, new copy, possibly reshooting hero imagery (the crab mascot stays; the "Linux distribution" tagline goes). Estimated effort: medium (see below).
- *Verdict:* **Required.** This is the actual scope of the v0.5.0 site-refresh phase; the link-out (Option 2) is one element inside it.

### Recommended IA for the new landing page (3-pillar product)

Following the **mise.jdx.dev** pattern (verified — see exemplars below) which is the closest direct analogue (single tool, three explicit pillars, technical audience):

```
Nav:    AgentLinux | Pillars | Install | FAQ | Strategy (→ docs/STRATEGY.md)
Hero:   Crab mascot
        AgentLinux
        "Agent-ready Linux, one command."  (replaces "Linux, for agents")
        One paragraph: dedicated agent user + correctly-owned Node.js;
        curated stable combos with benchmarks; security hardening for the
        agent toolchain. Each clause names one pillar.
        CTA: `curl -fsSL https://agentlinux.org/install.sh | sudo bash`
             [secondary] Read the strategy → docs/STRATEGY.md

#problem:  (Keep — still resonant; broaden the "agent on your laptop /
            in Docker / in a VM" framing slightly to acknowledge
            stability + security pain points the new pillars address.)

#pillars:  (NEW SECTION replacing the old #features grid.)
           Three cards, equal weight, mise-style numbered:
             1. Separated environment   — what's shipped (v0.3.0 surface)
             2. Stability + benchmarks  — what's coming (v0.6+ pillar 2)
             3. Security hardening      — what's coming (v0.6+ pillar 3)
           Each card: 2-sentence description, one-line "available now /
           coming in v0.6+" tag, "Learn more" link to the corresponding
           STRATEGY.md anchor.

#install:  (NEW SECTION — currently the install instruction lives only
            in the hero CTA + README. The site should mirror the README
            install/verify/uninstall blocks for users who don't bounce
            to GitHub. Pulls copy directly from README; small risk of
            drift, manageable via deploy-time check.)

#signup:   (Keep Buttondown form — top-of-funnel still serves the
            broader pillars 2/3 audience that wants notifications.)

#faq:      (Update questions to reflect three-pillar framing; the
            "What is AgentLinux?" / "When will it be available?" /
            "Is it free?" trio needs new answers per the v0.3.0 + v0.4.0
            shipped reality.)

Footer:    Links to GitHub repo, releases, ADRs, STABILITY-MODEL, STRATEGY.
```

Sections **removed** vs the current site: the 8-card `#features` grid (replaced by `#pillars`), the `#comparison` block ("Local machine → dedicated machine", "Docker → full OS", "Generic VMs → ready on boot" — all phrased around the retired distro shape). Old sections worth porting copy from: the pain-point columns under `#problem` are evergreen and broaden naturally.

### Estimated v0.5.0 site-refresh phase scope

| Work item | Effort |
|-----------|--------|
| Rewrite hero copy + tagline | S |
| Rewrite `#problem` to broaden across all three pillars (keep dual-column engineer/agent format) | M |
| Replace `#features` grid with `#pillars` 3-card section (new HTML + CSS) | M |
| Add `#install` section mirroring README curl-pipe-bash + verify | S |
| Update `#faq` answers to reflect v0.3.0 + v0.4.0 reality + three pillars | S |
| Update nav to add `Pillars` + `Strategy` (link out) anchors | S |
| Add `Strategy` link to footer | S |
| Update OG description + Twitter card descriptions to new framing | S |
| Update title tag from "AgentLinux -- Linux, for agents" to "AgentLinux — Agent-ready Linux, one command" (or whatever the new tagline locks to) | S |
| Visual QA mobile + desktop after copy changes | S |

**Total: medium scope.** ~1-2 days of focused work, no new tooling, no build step added, all HTML/CSS edits inside the existing `index.html`. Phase output: a single PR that changes `index.html` (mostly content, some structure), updates OG/Twitter meta, doesn't touch `assets/` (mascot/favicon stay).

### Risk: install-instruction drift between README and site `#install` section

If the site mirrors README's install block by hand-copy, they can drift. Mitigations (any one is sufficient):

1. **Acceptable drift** — pin to "see https://github.com/Roo4L/Agent-Linux#install for canonical install instructions" with only the one-line `curl | bash` shown on the site. Lowest maintenance, slight conversion cost.
2. **Deploy-time check** — extend `deploy.yml` to grep `index.html` for the version stamp + the curl URL and fail if they don't match `README.md`'s `<!-- VERSION_START --><!-- VERSION_END -->` block. Honors no-build constraint (it's a grep, not a renderer).
3. **Single-source extraction at deploy time** — `sed` the install block out of README into a marker block in `index.html` during `cp` staging. Honors no-build constraint (`sed` is fine), but adds asymmetric authoring (edit README, site updates magically) which is a maintenance sharp edge.

Recommend **option 2 (deploy-time grep check)** — already-present pattern (deploy.yml already has the install.sh anti-drift check per Pattern 5), low cost, catches the drift class that matters (version mismatch) without coupling the two files semantically.

---

## OSS landing-page exemplars (for downstream UI/UX work)

Five real, link-citable comparable landing pages for multi-pillar developer-infrastructure products. The first two are direct hits for AgentLinux's situation; the rest are useful for specific patterns.

### 1. mise (mise.jdx.dev) — **closest direct analogue, primary reference**

- **URL:** [https://mise.jdx.dev/](https://mise.jdx.dev/)
- **Why it's relevant:** Three explicit equal-weight pillars (Tool Version Management / Environments / Tasks) for a single CLI product, technical audience, OSS, single-page landing. Identical multi-pillar messaging problem.
- **What works:**
  - Hero is one tagline + one paragraph + two CTAs + one install command above-the-fold.
  - Three pillars introduced as numbered cards in a "The Menu" section — equal visual weight, same shape, "read more" link per card.
  - **Sequential narrative** rather than equal-weight feature grid: the page demonstrates how the pillars work *together* via a realistic worked scenario, then a "Four steps to a prepped station" walk-through. AgentLinux can mirror this — pillars 1+2+3 work together for "agent-ready Linux"; show the integrated story, not three siloed feature lists.
  - Culinary metaphor (mise-en-place) unifies messaging. AgentLinux has the crab/Linux/agent metaphor space available.
- **Direct steal:** the 3-pillar card section structure.

### 2. Encore (encore.dev) — **multi-pillar tech infrastructure, mature execution**

- **URL:** [https://encore.dev/](https://encore.dev/)
- **Why relevant:** Multiple distinct value props (Infrastructure-as-Code / Local Dev / Performance / Developer Tools / Ecosystem Integration) for a single product, technical OSS audience, dual-language (TS/Go) so already grappling with multi-pillar messaging.
- **What works:**
  - Concept → Implementation → Results → Community progression.
  - Social proof immediately (11k+ stars, 100+ contributors) — AgentLinux has lower numbers but should show what it has (CI matrix coverage, public release artifacts, the AGT-02 acceptance test).
  - Concrete benchmark numbers ("9x faster than Express.js"). AgentLinux's pillar 2 will eventually publish numbers; the page can be designed to slot them in.
- **Direct steal:** social proof immediately under hero; concrete numbers when pillar 2 lands.

### 3. Devbox / Jetify (jetify.com/devbox) — **dev-environment OSS with multi-feature messaging**

- **URL:** [https://www.jetify.com/devbox](https://www.jetify.com/devbox)
- **Why relevant:** Adjacent product space (dev environment provisioning), OSS, multi-feature (isolated environments / portability / automation / multi-project / multi-language).
- **What works:** Each feature gets a focused micro-section instead of being crammed into a card grid; gives the reader room to understand *why* each capability matters.
- **Direct steal:** the "give each pillar its own micro-section instead of cramming into one card grid" pattern, if the 3-card mise-style format ends up too compressed for AgentLinux's 3 pillars (especially if pillar 2 + pillar 3 need long explanations of what's coming vs what's shipped).

### 4. OpenTelemetry Collector vision doc (`docs/vision.md`) — **directly comparable strategy-doc precedent**

- **URL:** [https://github.com/open-telemetry/opentelemetry-collector/blob/main/docs/vision.md](https://github.com/open-telemetry/opentelemetry-collector/blob/main/docs/vision.md)
- **Why relevant:** Closest in-repo precedent for what AgentLinux's `docs/STRATEGY.md` should look like. CNCF infrastructure project, technical product, single file in `docs/`, six aspirational pillars (Performant / Observable / Multi-Data / Usable Out of the Box / Extensible / Unified Codebase). Living document, evolves over time.
- **What works:**
  - Short — 23 lines total, 15 of content. Sets a high bar against bloat.
  - Each pillar gets one heading + 1-3 sentences.
  - No prose overhead, no positioning section, no roadmap-themes appendix — just pillars as design-decision guidance.
- **Use:** as the reference for what to *not* over-engineer in v0.5.0's first cut. AgentLinux's STRATEGY.md will be longer (target users + JTBD + non-goals + roadmap themes are all in scope per the milestone), but the pillar-section format is directly copyable.

### 5. Doppler (doppler.com) — **commercial-but-OSS-adjacent, multi-stakeholder messaging**

- **URL:** [https://www.doppler.com/](https://www.doppler.com/)
- **Why relevant:** Doppler's hero explicitly addresses a *broadening* situation: "For every engineer on your team, there are now dozens of AI agents and automated workflows that need secrets too." That broadening framing — adjacent to AgentLinux's "from one pillar to three" story — is well-executed.
- **What works:**
  - Three logical category groupings (Integration Hub / Core Strengths / Social Proof) instead of a flat feature list.
  - Hero clearly names the broadening rather than hiding it.
- **Direct steal:** the hero's "we used to address X, now we address X + Y + Z" rhetorical move. AgentLinux's current hero ("Linux, for agents") is monolithic; the new hero should explicitly carry the broadening.

---

## Quality gate self-check

- [x] Repo-location pick has stability argument (single file → single URL → no rename trap; precedent of STABILITY-MODEL.md surviving without churn) and discoverability argument (three converging discovery paths: README links / docs/ sibling / GitHub file browser).
- [x] Cross-link map is concrete: specific files (ADR-001/011/012/013/014/015, README.md, CONTRIBUTING.md, docs/STABILITY-MODEL.md, docs/HARNESS.md, .planning/PROJECT.md, agentlinux.org index.html), specific section names (About / Links / Stability model / References / Related), specific edit types (one-line addition / new file / forward-reference / section-level rewrite).
- [x] Website propagation pick honors static-site / no-build-step constraint — Option 4 + Option 2 are pure HTML/CSS edits + a markdown link; Option 3 (CI render) is explicitly rejected on the constraint.
- [x] OSS exemplars are real and link-citable (5 distinct URLs, each verified via WebFetch or WebSearch).

## Sources

- [OpenTelemetry Collector docs/vision.md](https://github.com/open-telemetry/opentelemetry-collector/blob/main/docs/vision.md) — primary precedent for `docs/STRATEGY.md` shape
- [OpenTelemetry community mission-vision-values.md](https://github.com/open-telemetry/community/blob/main/mission-vision-values.md) — alternative naming convention
- [Watermelon Tools public-handbook Strategy.md](https://github.com/watermelontools/public-handbook/blob/main/Strategy.md) — root-level Strategy.md precedent
- [mise — landing page](https://mise.jdx.dev/) — primary IA reference for 3-pillar dev tool
- [mise — about page](https://mise.jdx.dev/about.html) — pillar definitions
- [Encore — landing page](https://encore.dev/) — multi-feature dev infra messaging
- [Devbox / Jetify — landing page](https://www.jetify.com/devbox) — multi-feature OSS dev env page
- [Doppler — landing page](https://www.doppler.com/) — broadening-narrative hero example
- [Folder Structure Conventions reference](https://github.com/kriasoft/Folder-Structure-Conventions) — naming-convention sanity check
