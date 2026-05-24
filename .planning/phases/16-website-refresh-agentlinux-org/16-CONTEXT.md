# Phase 16: Website Refresh (agentlinux.org) - Context

**Gathered:** 2026-05-24
**Status:** Ready for planning
**Mode:** Smart-discuss with mid-flow scope re-cut

<domain>
## Phase Boundary

Phase 16 repairs `index.html` so it no longer contradicts the post-Phase-14
vision (two pillars, infrastructure-not-distro framing) and the post-Phase-15
strategy (installable plugin, curated combos, brownfield-aware next).
**Scope is contradiction-removal, not expansion.** The site stays
under-radar — no shipped-version bragging, no install snippet, no
GitHub-pointing CTAs, no doc-link push. Existing structure (8-card
`#features` grid, 3-block `#comparison`, dual-column human/agent
`#problem` framing, signup, FAQ) is preserved; copy inside contradicting
sections is rewritten in place.

The original SITE-01..SITE-11 spec aggressively restructured the page
(`#features` → `#pillars` with badges, new `#install` section, footer doc
links, deploy-time drift check, PR screenshot requirement). The user re-cut
that scope on 2026-05-24 to "minimum-viable conflict removal." This phase
amends REQUIREMENTS.md SITE-01..SITE-11 in the same commit window (precedent:
Phase 14 STRAT-* → VIS-* + Phase 15 STRATR-02 reframe).

</domain>

<decisions>
## Implementation Decisions

### Scope: minimum-viable contradiction removal (locked 2026-05-24)

User direction: "My main goal of this phase was to make sure that on our
website we don't have anything that contradicts our current vision and
strategy. That's it. No more than that."

**Mandatory rewrites** (text strings that contradict the v0.3.0 plugin /
two-pillar framing):

1. Hero `value-prop` paragraph — current text claims "purpose-built Linux
   distribution that runs on a dedicated machine."
2. Hero `tagline` ("Linux, for agents") — kept; still works for plugin.
3. OG/Twitter `description` meta — same "purpose-built Linux distribution"
   string.
4. `#features` cards: 5 of the 8 cards advertise distro-only behaviours
   that the plugin doesn't ship — `Minimalistic` ("no desktop environment,
   no GUI stack"), `Automatic agent user` ("Boots into a non-root user
   account"), `Agents in the repos` ("`apt install claude-code`"),
   `Frameworks and plugins` ("in distro repos"), `Multiple distribution
   formats` ("installation images, QEMU VM images, Docker micro-VMs").
   Copy inside each card is rewritten; the 8-card grid structure is
   preserved (no `#features` → `#pillars` restructure).
5. `#comparison` 3-block grid: copy is rewritten in place. All three
   solution paragraphs use distro voice ("full OS instead of a locked
   box", "ready on boot instead of provisioning"); closing line says "Not
   another general-purpose distro". Three-block structure preserved; each
   solution paragraph rewritten to the plugin reality. No "AgentLinux vs
   Docker/VM/micro-VM" framing (SITE-04 grep gate).
6. FAQ #1 ("What is AgentLinux?") — rewrite the answer to drop "Linux
   distribution... runs on a dedicated machine" framing.
7. FAQ #5 ("How is this different from Docker?") — rewrite the answer to
   drop "AgentLinux is a full operating system on a dedicated machine"
   framing.

**Explicitly NOT touching:**

- `#problem` dual-column human/agent framing — user explicit: "I like it.
  I don't want to change much about it right now." Pain points (Local
  machine / Docker / Generic VMs) still hold as places agents try to run.
- `#features` 8-card grid structure — no `#pillars` restructure, no
  status badges, no `Learn more →` doc links.
- `#install` section — not added.
- Top nav — no `Vision` link added.
- Footer — stays minimal (`© 2026 AgentLinux`). No doc-link push.
- Visual styling (dark JetBrains Mono aesthetic, crab mascot) — locked
  out-of-scope per ROADMAP.

### Hero copy (locked 2026-05-24)

- **Tagline** (under title): keep "Linux, for agents". User accepted.
- **Value-prop paragraph**: vision-flavored intent — "Linux that gives
  coding agents a stable place to run — without you having to set it up."
  Lifted lightly from VISION.md's mission line. No temporal claim. No
  shipped/roadmap framing. No version cite. Subject is "Linux"; safe
  under voice-rule grep (SITE-06).
- **CTA button**: keep "Join the waitlist" (anchors to existing
  `#signup`). No "Install now" CTA (no `#install` section to link to).

### #comparison reframe (locked 2026-05-24)

- Reframe path (not removal) — keep `id="comparison"` block.
- 3-block structure preserved (Local machine / Docker / Generic VMs as
  the three places agents try to run today).
- Each `solution` paragraph rewritten to the plugin reality. Anchor each
  rewrite to the canonical bug class (`sudo npm install -g` EACCES +
  recursive-shim self-update breakage) and the curated-combo bet — not
  "full OS" / "dedicated machine" framing.
- Voice: forward-looking / intent voice for what we do (no shipped-version
  cites); avoid the `AgentLinux (benchmarks|measures|defends|protects|
  prevents|hardens)` verbs (SITE-06 grep gate).
- Closing line: drop "Not another general-purpose distro hoping agents
  will figure it out. A go-to Linux distro choice..."; replace with a
  one-line link back to the `#signup` section.

### OG image SVG → PNG (locked 2026-05-24)

User accepted SITE-09 retention after the rationale was explained:
social-card preview platforms (Slack, LinkedIn, Facebook, Twitter Cards)
render SVG `og:image` unreliably. PNG is the safe default.

- `assets/og-image.png` rendered once locally (rsvg-convert / magick at
  1200×630).
- `assets/og-image.svg` preserved as source-of-truth.
- `index.html` `og:image` + `twitter:image` meta tags point to the `.png`.

### REQUIREMENTS.md SITE-* amendment (locked 2026-05-24)

Same commit window as Phase 16 implementation. Mirrors the Phase 14
STRAT-* → VIS-* + Phase 15 STRATR-02 reframe precedent. A
`## Superseded items` note appended to REQUIREMENTS.md with the same
2026-05-16 audit-trail style.

| Req | Status | Amendment |
|-----|--------|-----------|
| SITE-01 | **AMEND** | Drop "delivered-fact line" + "forward-looking line" mandates. New text: `index.html` hero value-prop is rewritten so the string `purpose-built Linux distribution` no longer appears (`grep -c 'purpose-built Linux distribution' index.html` returns 0). Hero copy aligns with VISION.md mission line; voice-rule grep (SITE-06) passes. |
| SITE-02 | **SUPERSEDED** | No `#features` → `#pillars` restructure. `#features` 8-card grid preserved; contradicting card copy rewritten in place. New grep gate: `grep -cE 'apt install claude-code\|QEMU VM images\|Docker micro-VMs\|distro repos' index.html` returns 0. |
| SITE-03 | **SUPERSEDED** | No status badges added. Closes via SITE-02 supersession (no `#pillars` cards to badge). |
| SITE-04 | **KEEP, narrow** | Reframe path locked (not removal). Existing grep gate (`grep -cE 'AgentLinux vs (Docker\|VM\|micro-VM)' index.html` returns 0) carries forward. |
| SITE-05 | **SUPERSEDED** | No `#install` section. Closes via explicit decision recorded in audit. |
| SITE-06 | **KEEP** | Voice-rule grep gate unchanged. Hard gate. |
| SITE-07 | **SUPERSEDED** | No footer doc-links added; no nav `Vision` link. Closes via explicit "stay under radar" decision recorded in audit. |
| SITE-08 | **KEEP** | OG/Twitter meta tags rewritten; same grep gates. |
| SITE-09 | **KEEP** | OG image SVG → PNG conversion. |
| SITE-10 | **N/A** | No install snippet on the site → no drift to check. Closes N/A per the conditional path already in the spec. |
| SITE-11 | **SUPERSEDED** | Mobile/narrow-viewport screenshot requirement dropped. PR review pass is enough. |
| SITE-12 | **KEEP** | Phase-close audit + milestone-close gate fires from this phase (last v0.3.3 phase). Audit cites every SITE-XX evidence (including supersession decisions). Path: `.planning/phases/16-website-refresh-agentlinux-org/16-AUDIT.md` (slug differs from spec's `16-website-refresh` — uses SDK-derived directory name). |

Net active SITE requirements after amendment: SITE-01 (amended), SITE-04,
SITE-06, SITE-08, SITE-09, SITE-12. Six active, five superseded, one N/A.

### Claude's Discretion

- Exact prose for each rewritten card body, each rewritten comparison
  solution paragraph, the new FAQ #1 and #5 answers — subject to: (i) no
  `purpose-built Linux distribution` string; (ii) no v0.3.0/v0.4.0
  version cite; (iii) no `apt install claude-code` / "in distro repos" /
  "QEMU VM images" / "Docker micro-VMs" / "Boots into a non-root user"
  language; (iv) voice-rule grep (SITE-06) passes.
- Card icon retention — the existing Lucide icons stay unless the
  underlying card concept changes; icon replacement is per-card editorial.
- Whether to merge any of the 8 `#features` cards if the rewrite makes
  two cards say the same thing (e.g., "Easy-to-install package groups"
  and "Multiple distribution formats" both reduce to "curated catalog");
  default is to keep 8 cards and rewrite each, but a merge is acceptable
  if it improves the page. Cap at 8, floor at 4 (visual balance on the
  3-col / 2-col / 1-col responsive grid).
- Tooling for SVG → PNG conversion (rsvg-convert vs magick vs inkscape) —
  whichever the build host has available.
- Whether to update the `title` element ("AgentLinux -- Linux, for
  agents") — currently fine for the plugin framing; rewrite only if a
  conflict surfaces.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 14 + 15 upstream (consumed by Phase 16)

- `docs/VISION.md` — canonical "what we want to be"; the mission line is
  the source for the new hero value-prop. Voice rule carries verbatim
  into SITE-06.
- `docs/STRATEGY.md` — canonical "how we get there"; the "What we're
  solving" diagnosis (EACCES + recursive-shim + `npm install -g` bug
  class) is the substance source for `#comparison` solution paragraphs.
- `.planning/phases/14-vision-doc-and-downstream/14-CONTEXT.md` — locked
  voice-rule discipline + pillar names.
- `.planning/phases/15-strategy-roadmap-doc/15-CONTEXT.md` — locked
  diagnosis voice + the "first usable AgentLinux release for the
  maintainer" framing.
- `.planning/phases/14-vision-doc-and-downstream/14-AUDIT.md`,
  `.planning/phases/15-strategy-roadmap-doc/15-AUDIT.md` — reference
  pattern for grep-gate evidence committed verbatim.

### Site source

- `index.html` (31.3 KB at HEAD) — the single editable site source.
  GitHub Pages auto-deploy (`.github/workflows/deploy.yml`) ships
  whatever lands on `master`.
- `assets/og-image.svg` (1.7 KB) — SVG source for the PNG conversion.
- `assets/crab-mascot.svg`, `assets/favicon.svg` — visual assets;
  out-of-scope (no visual redesign).
- `README.md` — voice + framing reference for the plugin description
  (used as wording inspiration, not lifted verbatim).

### Spec / requirements / state

- `.planning/REQUIREMENTS.md` — SITE-01..SITE-11 + SITE-12 (Phase 16
  Coverage block at line ~81); the SITE-* amendment lands in this phase.
- `.planning/ROADMAP.md` — Phase 16 entry; the canonical phase boundary.
- `.planning/PROJECT.md` — milestone framing; Out-of-Scope list (note:
  "A full website redesign — the website-refresh phase keeps the existing
  dark JetBrains-Mono aesthetic + crab mascot").

### Sibling work in this milestone

- `docs/decisions/015-agenda-redefinition.md` — ADR-015, the framing
  decision; the site no longer contradicts it after this phase closes.
- `docs/STABILITY-MODEL.md` — referenced for the "curated combos" bet
  voice; not linked from the site this phase (per "stay under radar").

</canonical_refs>

<code_context>
## Existing Code Insights

No new code patterns to discover. `index.html` is a single 895-line file
with inline `<style>` and `<script>` blocks; the site has no build step,
no JS framework, no asset pipeline beyond `cp` in
`.github/workflows/deploy.yml`. Editing is straight HTML/CSS in place.

### Existing-content map (where contradictions live)

| Section | Line(s) | Contradiction |
|---------|---------|---------------|
| `<title>` | 14 | OK — "AgentLinux -- Linux, for agents" |
| OG meta | 22 | "purpose-built Linux distribution" — must rewrite |
| OG image src | 23, 30 | `.svg` — must repoint to `.png` |
| Twitter meta | 29 | "purpose-built Linux distribution" — must rewrite |
| Nav | 642-648 | OK — no Vision link added |
| Hero value-prop | 656 | "purpose-built Linux distribution that runs on a dedicated machine" — rewrite to vision-flavored intent line |
| `#problem` section | 661-722 | OK — explicitly kept |
| `#features` Minimalistic | 730-735 | "no desktop environment, no GUI stack" — distro voice; rewrite |
| `#features` Automatic agent user | 737-742 | "Boots into a non-root user" — distro voice; rewrite to "agent user the plugin provisions" |
| `#features` Easy-to-install package groups | 744-749 | Vague but borderline; "everything for web development, GUI testing" sounds like preset/profile framework (a v0.6+ theme, not shipped). Rewrite to the v0.3.0 catalog reality + the curated-combo bet. |
| `#features` Agent skills | 751-756 | Borderline; "Built-in skills for popular AI agents" — not contradicted by plugin framing, but vague. Light rewrite or leave. |
| `#features` Agents in the repos | 758-763 | "apt install claude-code" — wrong; rewrite to the `agentlinux install <name>` plugin verb |
| `#features` Frameworks and plugins | 765-770 | "in distro repos" — wrong; rewrite |
| `#features` Agent-friendly CLI tools | 772-777 | OK — "Custom command-line tooling designed to be operated by agents". Maps to `agentlinux` CLI. |
| `#features` Multiple distribution formats | 779-784 | "QEMU VM images, Docker micro-VMs" — heavily wrong; rewrite to "Ubuntu 22/24/26 plugin install path" |
| `#comparison` Local machine | 794-797 | "give the agent its own AgentLinux instance" — "dedicated machine" voice; rewrite |
| `#comparison` Docker | 799-802 | "complete operating system... starts services with systemctl" — distro voice; rewrite |
| `#comparison` Generic VMs | 804-807 | "AgentLinux images boot with everything pre-configured" — boot/image voice; rewrite |
| `#comparison` closing | 809 | "Not another general-purpose distro... A go-to Linux distro choice" — rewrite or drop |
| `#signup` | 813-823 | OK — keep waitlist |
| FAQ #1 | 830-832 | "Linux distribution purpose-built... runs on a dedicated machine" — rewrite |
| FAQ #2 (When?) | 833-836 | OK — "in early development" |
| FAQ #3 (Free?) | 837-840 | OK |
| FAQ #4 (Agents?) | 841-844 | OK — "Any agent that runs on Linux" |
| FAQ #5 (vs Docker?) | 845-848 | "AgentLinux is a full operating system on a dedicated machine" — rewrite |
| Footer | 853-857 | OK — minimal, no doc-link push |

### Established patterns

- Voice rule (carried from VIS-07 / STRATR-06): `grep -nE 'AgentLinux
  (benchmarks|measures|defends|protects|prevents|hardens)\b' index.html`
  returns zero matches. Forward-looking claims use "we" / "our roadmap"
  as the grammatical subject; identity claims use "Linux" / "the plugin"
  / "AgentLinux" with neutral verbs.
- Phase-close audit cites file path + line range / grep transcript per
  SITE-XX requirement. Same pattern as `14-AUDIT.md` / `15-AUDIT.md`.
- Reviewer pass per `docs/HARNESS.md` §4: HTML/CSS edits route via
  `technical-writer` + `fact-checker` + `ai-deslop`; no `bash-engineer` /
  `node-engineer` triggered (the `.github/workflows/deploy.yml` is
  untouched this phase).

### Integration points

- **GitHub Pages auto-deploy** — `master` push deploys to `gh-pages`
  branch via `JamesIves/github-pages-deploy-action@v4.8.0`. No
  workflow edit needed (no SITE-10 drift check to wire).
- **REQUIREMENTS.md SITE-* amendment** — same commit window as the HTML
  edits. Mirrors Phase 14 / 15 mid-milestone reframes.
- **`.planning/phases/16-website-refresh-agentlinux-org/16-AUDIT.md`** —
  phase-close audit emits here; cites SITE-01 + SITE-04 + SITE-06 +
  SITE-08 + SITE-09 + SITE-12 evidence plus the explicit supersession
  decisions for SITE-02 / SITE-03 / SITE-05 / SITE-07 / SITE-11 and the
  N/A close for SITE-10.
- **Milestone-close gate** — Phase 16 is the last v0.3.3 phase. Audit
  closes the milestone-coverage gate alongside its own phase-close gate.

</code_context>

<specifics>
## Specific Ideas

- **Hero value-prop**: "Linux that gives coding agents a stable place to
  run — without you having to set it up." (lifted lightly from VISION.md's
  mission line). User's own "Linux plugin helping you to build home for
  your AI Agent" was withdrawn in favour of the vision-flavored line.
- **Comparison anchor**: All three solution paragraphs anchor to the
  canonical bug class (EACCES + recursive-shim) and the curated-combo
  bet, per STRATEGY.md's "What we're solving" diagnosis. Avoid
  competition framing ("AgentLinux vs Docker") — the page describes what
  the plugin does, not what it beats.

</specifics>

<deferred>
## Deferred Ideas

- **Footer doc links + nav Vision link** (was SITE-07) — deferred until
  the "build critical mass before public engagement" gate from
  STRATEGY.md `## What's next` opens. Not a vision contradiction; just
  not the right time to push.
- **`#install` section + drift check** (was SITE-05 / SITE-10) — deferred
  until v0.3.4 brownfield installer lands (AL-38). Re-evaluating site CTA
  posture at that point makes sense; right now the page is under-radar.
- **Pillar restructure of `#features`** (was SITE-02 / SITE-03) —
  deferred. The current 8-card grid is shippable with rewritten copy;
  the pillar-card move is a redesign decision that can wait until the
  site visit volume warrants it.
- **Mobile screenshot PR ritual** (was SITE-11) — dropped this phase.
  PR review pass + the existing `pr-preview` workflow is enough.
- **Full visual redesign** — explicitly out-of-scope per ROADMAP /
  PROJECT.md.

</deferred>
