# Research Synthesis — v0.5.0 Agenda Redefinition

**Project:** AgentLinux
**Milestone:** v0.5.0 — Agenda Redefinition (Jira epic AL-7)
**Synthesized:** 2026-05-09
**Source files:** `.planning/research/STACK.md` · `FEATURES.md` · `ARCHITECTURE.md` · `PITFALLS.md`
**Overall confidence:** HIGH on every axis (framework, location, pillar substance, propagation, and pitfall mitigation each have ≥2 converging sources and a direct in-repo precedent).

---

## 1 · Executive Summary

v0.5.0 broadens AgentLinux from a single-pillar product (separated, correctly-owned agent environment) to a three-pillar product (env + stability/benchmarks + security hardening), where pillars 2 and 3 are **forward-looking** and land in v0.6+. The milestone ships *framing*, not implementation: a canonical strategy doc at `docs/STRATEGY.md`, an ADR (slot ADR-015) recording the framing decision, and a website refresh that propagates the new positioning to agentlinux.org.

The four parallel research passes converge cleanly. The doc's spine is the **Sourcegraph "Strategy Page" template** (the only public, MIT-licensed, dev-tools-authored template that prompts for "what we're not working on & why"), anchored by **Rumelt's Diagnosis → Guiding Policy → Coherent Action kernel** as a hidden review checklist. Three named inserts give the doc its AgentLinux character: a **Geoffrey Moore positioning sentence** inside Mission, **Amazon-style Tenets** as the framing for the three pillars, and a one-page **Roman Pichler Vision Board** appendix for scanability. The doc lives at `docs/STRATEGY.md` (single Markdown file, sibling to `STABILITY-MODEL.md` and `HARNESS.md`) — the in-repo convention is too strong to deviate from.

The single highest-leverage finding from the synthesis is the **phrasing-rule glossary** PITFALLS.md introduces — the distinction between *delivered-fact voice* and *forward-looking voice*. This rule is what stops the milestone from producing vaporware: every sentence in pillar 2 / pillar 3 sections (in the strategy doc *and* on the refreshed landing page) must use forward-looking voice with subject = "we" / "our roadmap" / an explicit milestone tag — never subject = "AgentLinux" + present-tense verb. An automated grep gate enforces this. Three other AgentLinux-specific risks dominate the rest of the design space: (a) the website is two pivots stale and a half-rewrite would produce a self-contradictory page; (b) the team has historically landed `docs/`-only changes without updating README + CONTRIBUTING + ROADMAP — the strategy doc is the *most likely* doc to suffer this; (c) the team will be tempted to write three pillars in equal voice with no priority tag, which makes the doc useless for saying no. Each is addressed by a concrete acceptance criterion downstream phase plans cite verbatim.

---

## 2 · Locked Decisions

These are settled by the four-researcher convergence; downstream phases consume them as fixed inputs and do not re-decide them.

| # | Decision | Source | Notes |
|---|----------|--------|-------|
| L1 | **Strategy-doc framework spine** = Sourcegraph "Strategy Page" template, with Rumelt's kernel as a hidden review-checklist overlay. | STACK.md framework matrix; verified at github.com/sourcegraph/handbook | Built by a dev-tools company; license-permissive; explicit "what we're not working on" prompt is exactly what AL-7 needs. |
| L2 | **Three named inserts** = Geoffrey Moore positioning sentence (inside Mission), Amazon-style Tenets (as the framing for the three pillars), Roman Pichler Vision Board (one-page appendix). | STACK.md framework matrix | Each insert does one job extremely well; together they cover positioning + pillar-framing + scanability. |
| L3 | **Strategy-doc location** = `docs/STRATEGY.md` (single file, ALL-CAPS keystone, sibling to `docs/STABILITY-MODEL.md` and `docs/HARNESS.md`). | ARCHITECTURE.md Part A; STACK.md location matrix | One file, one URL, no rename trap. Folder/tree decomposition is reachable later if the doc passes ~15 KB. |
| L4 | **Strategy-doc format** = single Markdown file, target 4–8 KB on first cut (same scale as STABILITY-MODEL.md's 5.4 KB). No tree, no embedded canvas image, no Notion/external doc. | STACK.md tooling matrix | Stable, git-diffable, GitHub-rendered, ADR-citable. |
| L5 | **ADR slot reserved** = **ADR-015 — Three-pillar product framing (v0.5.0 agenda redefinition)**. Lands in the same milestone as `docs/STRATEGY.md`; the two cross-link bidirectionally. | ARCHITECTURE.md Part B; PITFALLS.md #21 | Same pattern as ADR-011 ↔ STABILITY-MODEL.md. ADR-015 records ≥3 considered alternatives (stay single-pillar / pivot security-first / four pillars including observability) per PITFALLS.md #21. |
| L6 | **Website propagation strategy** = restructure `index.html` IA to mirror the three-pillar framing (mise.jdx.dev pattern) **+** link out to `docs/STRATEGY.md` from the appropriate section. **Reject** CI-side render of MD → HTML (violates the no-build constraint). | ARCHITECTURE.md Part C | Hand-port; no new tooling; ~1–2 days of focused work. |
| L7 | **Voice rule** (verbatim from PITFALLS.md): **delivered-fact voice** = present-tense indicative naming a shipped behaviour, links to `@test` / ADR / CI gate / release artefact. **Forward-looking voice** = first-person plural commitment with explicit horizon, no present-tense product subject. NEVER write "AgentLinux benchmarks…" or "AgentLinux defends against…" for unshipped behaviour. **Aspirational drift** = any sentence that uses delivered-fact voice for an unshipped behaviour and is the single most dangerous v0.5.0 pattern. | PITFALLS.md (phrasing-rule glossary, pitfalls #6, #14) | Enforced by `grep -nE '^[^a-z]*AgentLinux (provides\|offers\|ensures\|protects\|defends\|benchmarks\|measures\|hardens\|isolates\|detects\|prevents)\b'` on pillar-2/3 sections — must return zero matches. |
| L8 | **ADR-012 (NOPASSWD ALL) position** = "Defensible scope choice for v0.3.0; *security debt now* that pillar 3 is being committed to. Pillar 3 commits to *revisiting* the trade-off in v0.6+ via an opt-in `agentlinux harden` profile (capability-scoped sudoers + bubblewrap-based per-recipe sandbox + iptables egress allowlist). v0.3.x default posture unchanged." | FEATURES.md §E (ADR-012 special call-out) | This exact framing goes into both `docs/STRATEGY.md` Pillar 3 *and* ADR-015's Consequences section. |
| L9 | **Strategy doc's `Today` / `Direction` split per pillar** — every pillar section is split into `### Today (delivered, vX.Y.Z)` and `### Direction (forward-looking)` subsections with a horizontal rule between them. Pillar 1's `Direction` block is allowed to be "this pillar is foundational; tracked via the bats suite" but the subsection MUST exist for symmetry. | PITFALLS.md #7 | Structural enforcement of the L7 voice rule. |
| L10 | **Site source location** = repo root (NOT `site/` or `website/`). `index.html`, `CNAME`, `sitemap.xml`, `robots.txt`, `assets/` all at root. | ARCHITECTURE.md "Repo state inspected" §1 | The milestone-context's reference to `site/` is incorrect; the website-refresh phase touches root-level `index.html`. |

---

## 3 · Strategy-doc TOC skeleton (recommended)

Pulled from STACK.md's recommended TOC. Authoring phase plan fills it in; section names and ordering are locked by L1+L2.

```markdown
# AgentLinux Product Strategy

> One-paragraph elevator opener (what AgentLinux is, who it serves, why
> v0.5.0 broadened from one pillar to three). Anchor links to AL-7 and ADR-015.

Quicklinks:
- ADR-015 — Three-pillar product framing
- docs/STABILITY-MODEL.md — pillar 2 seed (ADR-011)
- README.md — install + verify
- agentlinux.org — public landing page (refreshed to mirror this framing)

## Mission
  ### Positioning statement      ← Geoffrey Moore form (one paragraph)

## The three pillars (tenets)    ← Amazon-style tenets framing
  ### Pillar 1 — Separated, correctly-owned agent environment
    #### Today (delivered, v0.3.0)
    #### Direction (forward-looking)
  ### Pillar 2 — Stability + best-tested setup with measurable benchmarks
    #### Today (delivered, v0.3.0 — ADR-011 stability seed)
    #### Direction (forward-looking — v0.6+ Benchmarks milestone)
  ### Pillar 3 — Security hardening
    #### Today (delivered — gitleaks gate, MIT, branch protection, SHA256 install)
    #### Direction (forward-looking — v0.6+ Security Hardening milestone)
  ### Pillar priority                ← PITFALLS.md #4 forcing function
    foundational / next-milestone / opportunistic tagging

## Guiding principles            ← 4–7 stances; threads through the three pillars

## Where we are now
  ### Top issues / contributor pain points (optional)
  ### Competitive landscape

## Strategy and plans
  ### Themes for v0.6+
  ### What we're explicitly *not* working on & why  ← ≥5 entries (PITFALLS.md #9)

## Trade-offs / rejected alternatives  ← PITFALLS.md #13

## Appendix A — One-page Vision Board   ← Roman Pichler form (markdown table)
## Appendix B — Roadmap themes (forward-looking)
   #### Sequencing rationale         ← PITFALLS.md #26 (why pillar X before pillar Y)
```

**Authoring effort estimate:** 1 phase, ~3–6 hours of writing, ~6–8 KB final file. Framework is decided; phase A is fill-in-the-blanks.

---

## 4 · Pillar-2 substance summary

**Honest scope (the load-bearing claim).** Pillar 2's "measurable benchmarks vs vanilla setup" is principally about **time-to-productive** and **stability across upstream drift**, NOT SWE-bench-Verified score deltas. The strategy doc must include the explicit statement:

> *"We do not expect or claim that AgentLinux changes Claude's SWE-bench Verified score. The credible measurable claims are time-to-productive (AGT-02 + first-task wall-clock) and stability across upstream drift (`pass^k` + curated combos)."*

**Existing v0.3.0 capability that seeds the pillar:** ADR-011 stability model (curated `pinned_version` per catalog agent + end-to-end tested combo + TST-08 release-gate). The benchmark layer is the planned extension; the pinning is already real.

**Table-stakes commitments (3, all from FEATURES.md):**

- **P2-1** — AGT-02 as the load-bearing measurable claim. The release-gate test that the curated `claude` self-updates against the live Anthropic CDN with zero EACCES and zero sudo prompts. Already true; strategy doc restates.
- **P2-2** — Curated combos as pillar-2 seed. Cite `docs/STABILITY-MODEL.md` and ADR-011. Already true; strategy doc references.
- **P2-3** — Honesty about *what* benchmarks measure: time-to-productive + stability across drift, not Verified score. Refusing to overclaim is the trust signal.

**Differentiator commitments (3):**

- **P2-4** — Adopt one or more of: **terminal-bench** (closest analog to "agent operating a real CLI environment"), **Multi-Docker-Eval-style env-build efficiency reporting** (token + wall-clock + image size — the closest published methodological precedent), and a small AgentLinux-specific golden-task suite. Selection happens *in the v0.6 Benchmarks milestone*, not in v0.5.0.
- **P2-5** — Where appropriate, results reported as **`pass^k`** (Sierra τ-bench convention) so reliability is visible, not hidden behind best-of-k. Most agent products quote `pass@k`; pass^k is the right metric for a stability-pillar product.
- **P2-6** — Token, cost, and latency observability for users who opt in via catalog entries for **Helicone** or **Langfuse**. AgentLinux ships neither by default (no-default-agents principle, ADR-003) but the catalog makes it one command away.

**Explicit non-goals (2):**

- **P2-7** — Not replicating the SWE-bench / Aider / GAIA leaderboards. Cite them as broader landscape; pick the subset that exercises the *environment*.
- **P2-8** — Not publishing per-model scores. The curated combo's CI green light is the publishable invariant; a per-model leaderboard is a different product.

**Named eval suites worth citing (≤6 most relevant, in priority order):** terminal-bench (tbench.ai), Multi-Docker-Eval (arxiv 2512.06915), τ-bench / τ²-bench (Sierra Research, pass^k methodology), SWE-bench Verified (the field's reference, with the explicit non-claim), SWE-bench Live (Microsoft, contamination-resistant), Aider polyglot (cross-language toolchain stress).

---

## 5 · Pillar-3 substance summary

**Late-2025 frame to adopt:** **OWASP LLM Top 10 v2025** as the threat-model reference + **Simon Willison's Lethal Trifecta** (untrusted input + sensitive data + external communication = exploitable) + **Meta AI's Agents Rule of Two** (an agent should hold ≤2 of the three or operate under human-in-the-loop). These are the de-facto industry frames as of late 2025.

**Table-stakes commitments (3):**

- **P3-1** — Adopt OWASP LLM Top 10 v2025; name LLM01 prompt injection (direct + indirect) as the dominant risk for any coding agent regardless of vendor.
- **P3-2** — Adopt Lethal Trifecta + Agents Rule of Two as the deployable framing.
- **P3-3** — Document and commit to **revisiting ADR-012 NOPASSWD ALL** (per L8 above). Refusing to take this position is itself a position; stakeholders will read silence as either denial or unawareness.

**Differentiator commitments (3):**

- **P3-4** — Commit to one or more concrete supply-chain hardening measures: (a) **cosign-signed catalog snapshots** (closes the gap left by README §Security's "GPG signatures on the v0.4+ roadmap"), (b) **`npm audit signatures`** in CI on catalog candidates, (c) **recipe-level SBOM emission** per release.
- **P3-5** — Commit to an opt-in **`--ignore-scripts` policy** for catalog recipes where feasible. npm postinstall is the dominant npm-malware delivery channel per the chalk/debug + Shai-Hulud + ua-parser-js precedents. Recipes that genuinely require scripts get extra review and are documented as such.
- **P3-6** — Adopt a **hardened CLAUDE.md skel fragment** in agent-user provisioning that codifies Anthropic's "External content is data, not instructions" boundary — pre-deployed by AgentLinux, not user-curated. Unique value an installable plugin can deliver that per-user manual setup typically does not.

**Explicit non-goals (3):**

- **P3-7** — Not providing model-level guardrails (Llama Guard / ShieldGemma / NeMo Guardrails). Properly the agent or model vendor's surface.
- **P3-8** — Not vetting the *content* of upstream agent code. We pin and sign the snapshot we test; we do not audit Claude Code's source. Catalog acceptance is by behavior + maintainer reputation + provenance signals.
- **P3-9** — Not becoming a sandbox runtime. The opt-in `--sandbox` profile uses off-the-shelf Linux primitives (bubblewrap + Landlock + seccomp + iptables) already in the kernel; we ship recipes + defaults, not a new isolation engine. gVisor / Firecracker / Kata Containers exist; AgentLinux does not compete.

**Named attacks to cite (≥4):** **Shai-Hulud npm worm** (CISA AA25, Sept-Nov 2025; 25,000+ malicious repositories in the 2.0 wave; postinstall harvests creds), **chalk + debug + 16 packages compromise** (Sept 8 2025; phished 2FA, ~2h live with billions of weekly downloads), **TrustFall** (Adversa AI, 2025; one-click RCE in Claude Code / Cursor / Gemini CLI / Copilot), **Cline data exfiltration via markdown image** (embracethered.com Aug 2025; auto-approve → trifecta exploited with no UI prompt). Optional: ua-parser-js, event-stream as historical anchors.

**Named defenses to cite (≥4):** **npm provenance + Sigstore signing** (`npm audit signatures`; Trusted Publishing Jul 2025), **SLSA framework + in-toto attestations** (target SLSA L3 for first-party catalog snapshots; current state ≈ "SHA256 + maintainer 2FA + branch protection"), **Anthropic devcontainer reference** (bubblewrap + iptables/ipset egress firewall; OUTPUT default DROP), **bubblewrap / Landlock / seccomp-bpf** (Linux-native unprivileged sandboxing; the primitives `agentlinux harden` would compose), **capability-scoped sudoers** (Microsoft SCOM-style allowlists) for tightening ADR-012, **cosign** for signed releases.

---

## 6 · Cross-link map (compact form)

Eight in-repo files cross-link to STRATEGY.md; STRATEGY.md cross-links to nine in-repo + external artefacts. From ARCHITECTURE.md Part B.

### Outbound — `docs/STRATEGY.md` references…

| STRATEGY.md section | References |
|---|---|
| Mission > Positioning | (none — uses competitor names) |
| Pillar 1 | ADR-001 (pivot), ADR-004 (per-user npm prefix), ADR-005 (system Node.js), ADR-012 (agent sudo), README "About" |
| Pillar 2 | ADR-011, `docs/STABILITY-MODEL.md`, ADR-007 (Docker+QEMU harness), v0.6+ Benchmarks milestone placeholder |
| Pillar 3 | ADR-006 (curl-pipe-bash + SHA256), ADR-013 (MIT), ADR-014 (secret remediation), ADR-012 (revisit), v0.6+ Security Hardening milestone placeholder, OWASP LLM Top 10, Anthropic security guidance |
| Guiding principles | ADR-002 (behavior contract), ADR-011 (stability-first), ADR-010 (review loop) |
| Where we are now | ADR-002, ADR-011, ADR-013 |
| What we're NOT working on | ADR-001 (custom distro), ADR-009 (Snap), ADR-011 (per-agent .debs) |
| Themes > "Distro Reach" | ADR-009 |
| Decision provenance | ADR-015 |

### Inbound — these files gain a back-pointer to STRATEGY.md

| File | Edit type |
|---|---|
| `README.md` — new sentence in About + link in Links | small surgical |
| `CONTRIBUTING.md` — new "Why this project exists" paragraph linking to STRATEGY.md | one-line addition |
| `docs/decisions/015-agenda-redefinition.md` (new) | new file (the v0.5.0 ADR) |
| `docs/decisions/011-stability-first-version-pinning.md` | optional bidirectional link (recommended) |
| `docs/decisions/012-agent-user-full-sudo.md` | optional bidirectional link (recommended for honest documentation of unresolved tension) |
| `docs/STABILITY-MODEL.md` — Related section | optional, recommended |
| `.planning/PROJECT.md` — Core Value section | required as part of milestone close |
| `agentlinux.org` (`index.html`) | required as part of v0.5.0 Site-Refresh phase |
| Future `ROADMAP.md` (v0.6+ milestones, when they exist) | future requirement |

**No update needed:** `docs/HARNESS.md` (orthogonal, internal harness spec).

---

## 7 · Website refresh scope

**Critical correction.** The site source is at the **repo root**, not `site/`. `index.html` (~895 LOC), `CNAME`, `sitemap.xml`, `robots.txt`, `assets/` all sit at root. There is no `site/` or `website/` directory. The website-refresh phase touches root-level `index.html` + `assets/`.

**Current state.** `index.html` is **two pivots stale** — hero says "A purpose-built Linux distribution"; features section advertises QEMU/Docker micro-VM distribution formats. Both retired in the v0.2.0→v0.3.0 pivot (ADR-001). The site contradicts the README. A refresh is required regardless of whether the strategy doc lands.

**Recommended IA (mise.jdx.dev pattern — three pillars, equal-weight cards, single-page).** Verified at mise.jdx.dev as the primary analogue (single CLI tool, three explicit pillars, technical OSS audience, no build step).

```
Nav:    AgentLinux | Pillars | Install | FAQ | Strategy (→ docs/STRATEGY.md)
Hero:   Crab + tagline (2-line: line A delivered-fact, line B forward-looking)
        + curl-pipe-bash CTA + secondary "Read the strategy →"
#problem   keep — broaden slightly to acknowledge stability + security pain
#pillars   NEW (replaces #features grid) — 3 numbered cards, mise-style
           Each card: "Shipped v0.3.0" badge for pillar 1; "Coming v0.6+"
           badge for pillars 2/3 (PITFALLS.md #14 + #18 enforcement)
#install   NEW — mirrors README's curl-pipe-bash + verify
#signup    keep Buttondown form
#faq       update for v0.3.0/v0.4.0 reality + three-pillar framing
Footer:    repo, releases, ADRs, STABILITY-MODEL, STRATEGY
```

**Sections deleted:** the 8-card `#features` grid (replaced by `#pillars`), the `#comparison` block (phrased around the retired distro shape).

**Estimated scope: medium, ~1–2 days of focused work.** Pure HTML/CSS edits in the existing `index.html`. No new tooling. No build step added. `assets/` (mascot, favicon) untouched.

**Install-instruction drift mitigation.** Adopt **option 2 from ARCHITECTURE.md Part C**: deploy-time grep check that fails the deploy if the `index.html` install snippet's version stamp diverges from `README.md`'s `<!-- VERSION_START --><!-- VERSION_END -->` block. Same shape as the existing Pattern 5 anti-drift check on `install.sh`.

**Explicitly out of scope (deferred unless phase-discuss surfaces it):** Visual redesign. The crab mascot stays. The dark JetBrains Mono aesthetic stays. The OG-image SVG → PNG conversion (carried since v0.1.0 per PROJECT.md known-issues) **should be folded into this PR** — v0.5.0 is the right time to fix it, and the OG/Twitter meta-tag rewrite (PITFALLS.md #20) is happening anyway.

---

## 8 · Top-5 pitfalls to design out

The five most likely to bite us specifically (PITFALLS.md §"Top 5"). Each is paired with the prevention rule downstream phase plans cite **verbatim**.

| # | Pitfall | Prevention rule (cite verbatim in phase plans) |
|---|---------|------------------------------------------------|
| **1** | **#6 — Aspirational drift (overpromising forward-looking work).** Highest risk. Whole milestone exists to surface unshipped pillars; the temptation to use delivered-fact voice is structural. Public repo since v0.4.0 means mis-claims reach HN, not just internal stakeholders. | **Acceptance check (automated grep):** in `docs/STRATEGY.md`, for any line under a pillar-2 or pillar-3 heading, `grep -nE '^[^a-z]*AgentLinux (provides\|offers\|ensures\|protects\|defends\|benchmarks\|measures\|hardens\|isolates\|detects\|prevents)\b'` MUST return zero matches. **Replacement phrasing rule:** "We are committing to `<behaviour>` in `<milestone>`." / "Our roadmap commits to `<behaviour>` before `<milestone>` ships." / "AgentLinux today does not yet `<behaviour>`; v0.6+ adds `<behaviour>`." Every claim about an unshipped behaviour MUST appear in a sentence whose grammatical subject is "we" / "our roadmap" / an explicit milestone identifier — never "AgentLinux". |
| **2** | **#14 — False-advertising the broadening on the website.** Same root cause as #1, much higher visibility surface. Current site is already over-promising; site refreshes have historically been done lightly. | **Acceptance check (visual + textual):** every pillar-2 / pillar-3 section on the landing page MUST carry a visible status badge (`[v0.6+ ROADMAP]` / `[COMING SOON — v0.6+]`) at parity with how pillar 1 carries `[SHIPPED v0.3.0]`. Textual check identical to #1: `grep -nE 'AgentLinux (benchmarks\|measures\|defends\|protects\|prevents\|hardens)\b'` on the rendered HTML must return zero matches. CTA for unshipped pillars: "Follow the roadmap" / "Watch the repo" — never "Get started" / "Install now". |
| **3** | **#22 — Strategy doc lands without updating README + CONTRIBUTING + ROADMAP.** Highest probability. Team has track record of landing `docs/`-only changes; strategy doc is *most likely* to suffer because it complements rather than replaces README, so README rewrite feels optional. It isn't. | **Acceptance check:** phase plan for the strategy-doc phase MUST enumerate every downstream surface that needs updating, in the same phase or as an explicit follow-up before the milestone closes. **Enumerated list:** `README.md` (About + Links), `CONTRIBUTING.md` (link + which pillars accept contributions today), `.planning/PROJECT.md` (Core Value section), `docs/STABILITY-MODEL.md` (Related), `docs/decisions/011-…md` (forward-reference, optional), `docs/decisions/012-…md` (forward-reference, recommended for honest tension documentation), `agentlinux.org` (separate phase). Phase-close gate: each enumerated file shows a commit in the milestone window or carries an explicit "no change needed because…" entry. |
| **4** | **#4 — Listing pillars without prioritization.** Most likely structural failure. Three pillars + nothing-shipped on two + small team that doesn't want to "pre-decide" v0.6 = strong incentive to write all three in equal voice with equal length. | **Acceptance check:** pillars section MUST include a "**Pillar priority**" subsection that explicitly tags each pillar as `foundational` / `next-milestone` / `opportunistic`. **For AgentLinux this lands as:** pillar 1 = `foundational`, pillar 2 OR pillar 3 = `next-milestone`, the other = `opportunistic`. Strategy doc owner MUST commit to which is which; deferring the choice fails the gate. (See OQ-3 below — this decision is Open Questions.) |
| **5** | **#12 — Strategy doc never updates again.** Most likely long-term failure. AgentLinux has strong harness culture but no living-doc culture; ADRs are immutable by convention; strategy doc inherits that mental model when it shouldn't. | **Acceptance check (process binding):** the `/gsd-complete-milestone` template gains a mandatory step "Strategy doc reviewed; pillar `Today` sections updated for any newly-shipped behaviour; pillar `Direction` sections updated to remove now-shipped commitments." Strategy doc gains a top-of-file "**Last reviewed:** `<date>` at `<milestone close>`" header that the milestone-close gate enforces. Optionally: CI lint that fails if header date is older than the most recent release tag by >90 days. **This pitfall is NOT mitigated by an in-milestone check alone — it requires amending the milestone-close convention itself, so flag for the v0.5.0 retrospective and the `/gsd-new-milestone` template update that follows.** |

---

## 9 · Open Questions for Requirements / Roadmap pass

The synthesis did NOT resolve these; each needs a user call (or a phase-discuss decision) before downstream work locks.

| # | Question | Recommended default | Forcing function |
|---|----------|---------------------|------------------|
| **OQ-1** | **Phase split:** one phase for strategy doc + ADR-015 vs two separate phases (one for strategy doc, one for ADR)? | Single phase. ADR-015 is small (decision-statement + ≥3 considered alternatives + AL-7 link + Consequences); both artefacts are interlocked and should land in the same merge per PITFALLS.md #21. | Requirements pass needs to know whether STRAT-XX and ADR-XX requirements ladder up to one or two phase plans. |
| **OQ-2** | **Website refresh phase shape:** single phase for content + IA + meta-tag rewrites, or split content/IA from any visual work? | Single phase. Visual redesign is explicitly out of scope (see §7). The OG-image SVG→PNG fix folds in. | Roadmap pass needs to know whether SITE-XX requirements ladder up to one or two phase plans. |
| **OQ-3** | **Pillar priority decision:** which of pillar 2 / pillar 3 is `next-milestone` (v0.6+) and which is `opportunistic`? Pitfall #4 forces this call BEFORE the strategy doc lands. | **No recommended default — this is genuinely a user call.** Both have credible arguments. Pillar 2 first: free GHA minutes since v0.4.0 unblock benchmark CI cost; existing ADR-011 + STABILITY-MODEL.md provide the seed; terminal-bench + Multi-Docker-Eval are off-the-shelf-runnable. Pillar 3 first: post-Shai-Hulud landscape gives the security framing visible urgency; ADR-012 NOPASSWD revisit is overdue; Anthropic's devcontainer reference de-risks the implementation. | The strategy doc cannot write its "**Pillar priority**" subsection (PITFALLS.md #4 acceptance check) or its Appendix B sequencing-rationale paragraph (PITFALLS.md #26) without this call. The doc-authoring phase is blocked at first draft until this resolves. |
| **OQ-4** | **Number of guiding principles to commit to** (Sourcegraph template recommends 4–7). | 5. Suggested seeds from STACK.md TOC: "Behavior tests are the spec" (ADR-002), "We test exactly what we ship" (ADR-011 contract), "Curated combos, not thin wrappers" (ADR-011 negative space), "No silent drift" (`agentlinux upgrade` contract), "Trust through evidence, not assertion" (provenance for pillars 2+3). Phase-A authoring picks the actual list. | Requirements pass enumerates the principles as STRAT-XX entries. |
| **OQ-5** | **Jira sub-tasks under AL-7:** file now (one per phase deliverable) or after roadmap lands? | After roadmap lands. The session-tracker convention treats Jira tickets as artefacts of completed work (per project CLAUDE.md "Session Tracking" section), so the natural moment is post-roadmap when phase identifiers are stable. | If we file pre-roadmap, ticket IDs may need re-assignment; if we wait, the AL-7 epic remains the single inbound link until phases lock. |

---

## 10 · Roadmap implications

Synthesizer's recommendation, NOT a binding roadmap. Roadmapper agent consumes this as the starting point.

### Phase 12 — Strategy doc + ADR-015

- **Likely shape:** 2 plans:
  - **Plan 12-01: STRAT requirements** — author `docs/STRATEGY.md` against the Locked-Decisions L1–L4 spine, fill in the §3 TOC skeleton, deliver §4 + §5 pillar substance, take the L8 ADR-012 position verbatim, produce ADR-015 alongside. STRAT-XX requirement coverage.
  - **Plan 12-02: Downstream surface updates** — README + CONTRIBUTING + PROJECT.md + STABILITY-MODEL + ADR-011/012 forward-references per §6. Mitigates Top-5 pitfall #3 (PITFALLS.md #22) directly.
- **Acceptance gates:** every Top-5 pitfall mitigation in §8 cited verbatim.
- **OQ blocker:** OQ-3 (pillar priority) MUST resolve before Plan 12-01 first draft.

### Phase 13 — Website refresh

- **Likely shape:** 1 plan locked at phase-discuss after Phase 12 lands (so the site can link to a stable `docs/STRATEGY.md` URL).
- **SITE-XX requirements** cover the §7 IA restructure + the L7 voice rule applied to HTML + OG/Twitter meta-tag rewrite + OG-image PNG conversion + deploy-time install-instruction drift check.
- **Acceptance gates:** Top-5 pitfall #2 (PITFALLS.md #14) mitigation enforced via grep + visible roadmap badges; PITFALLS.md #18 cross-artefact sync (pillar visual order matches strategy doc prose order); PITFALLS.md #19 mobile/narrow viewport screenshots in PR body.

### (Optional) Phase 14 — Cross-link wiring + downstream-doc updates

- **Only needed if Plan 12-02 (Downstream surface updates) ends up too large to ride inside Phase 12.**
- Synthesizer recommendation: fold into Phase 12 (single coherent work item; splits create the exact PITFALLS.md #22 risk we're mitigating).

### Number of forward-looking themes to surface in STRATEGY.md Appendix B

**3** themes is the recommended commitment, matching the Jujutsu roadmap exemplar (themed-not-dated):

1. **Benchmarks Harness** — pillar 2 implementation milestone (v0.6+).
2. **Security Hardening** — pillar 3 implementation milestone (v0.6+).
3. **Distro Reach** — Fedora / Alma / Arch — pillar 1 expansion (cite ADR-009 Snap-disqualified as negative-space precedent).

Additional candidates to consider but not commit to: Observability (Helicone/Langfuse catalog entries), Multi-host orchestration, Per-agent telemetry. Phase A authoring picks the final list; OQ-3 fixes which of themes 1 vs 2 is `next-milestone`.

---

## 11 · Source file pointers

For downstream phases that want to drill in. All paths are absolute from the worktree root `/home/agent/agent-linux/.claude/worktrees/agenda/`:

| File | Most relevant for |
|------|-------------------|
| **`.planning/research/STACK.md`** | Framework comparison matrix (10 frameworks evaluated), Sourcegraph-template TOC source, OSS-exemplar references (Jujutsu, Sourcegraph handbook, Prettier, Tailscale, Sigstore, Headscale), tooling/format/location decision matrices, what-to-actively-avoid table. |
| **`.planning/research/FEATURES.md`** | Pillar-2 eval-suite landscape (13 suites), Multi-Docker-Eval methodological keystone, vanilla-comparison honest-assessment table, pillar-3 attack landscape (Shai-Hulud + chalk/debug + TrustFall + Cline + 3 historical), pillar-3 defense landscape (npm provenance + SLSA + cosign + Anthropic devcontainer + bubblewrap + capability-scoped sudoers), ADR-012 special call-out §E with the recommended verbatim language. |
| **`.planning/research/ARCHITECTURE.md`** | Repo state factual baseline (site at root, not `site/`), `docs/STRATEGY.md` location rationale, naming-decision matrix (STRATEGY vs PRODUCT vs MISSION vs VISION), full cross-link map (outbound + inbound + graph form), website-propagation per-option assessment (with CI-render rejection), recommended IA (mise-style 3-pillar cards), 5 OSS landing-page exemplars. |
| **`.planning/research/PITFALLS.md`** | 27-pitfall catalog (13 strategy-doc + 7 website + 7 cross-cutting), the **phrasing-rule glossary** (the load-bearing artefact for the whole milestone), Top-5 callouts with AgentLinux-specific reasoning, concrete grep rule for pitfall #6 / #14 enforcement, downstream-surface enumeration for pitfall #22. |

---

## Confidence assessment

| Area | Confidence | Reasoning |
|------|------------|-----------|
| Strategy-doc framework | **HIGH** | Sourcegraph template is a near-perfect direct precedent; multiple converging sources (Rumelt's kernel, Amazon Tenets convention, Geoffrey Moore positioning) back the inserts; OSS exemplars verified individually (Jujutsu, Prettier, Tailscale, Sigstore, Headscale). |
| Strategy-doc location | **HIGH** | In-repo precedent (`docs/STABILITY-MODEL.md`, `docs/HARNESS.md`) is unambiguous; OpenTelemetry Collector's `docs/vision.md` is the closest external precedent. |
| Pillar-2 substance | **HIGH** | Eval-suite landscape grounded in named recent papers (terminal-bench, Multi-Docker-Eval, τ-bench, SWE-bench Verified/Live/Pro); honest-assessment table prevents overclaim. |
| Pillar-3 substance | **HIGH** | OWASP LLM Top 10 v2025, Lethal Trifecta, Agents Rule of Two are the de-facto industry frames; named CVEs/incidents (Shai-Hulud + chalk/debug + TrustFall + Cline) are recent and verifiable; ADR-012 position is internally derived from ADR-012 itself + post-Shai-Hulud landscape — defensible. |
| Website propagation | **HIGH** | Repo state directly inspected; mise.jdx.dev IA verified via WebFetch; no-build constraint confirmed against `.github/workflows/deploy.yml`. |
| Pitfall catalog | **HIGH** | Each pitfall cross-checked against multiple secondary sources (Linux Foundation, Red Hat, ProductTeacher, Christensen Institute, Wikipedia vaporware page, Evil Martians dev-tool study); AgentLinux-specific application grounded in PROJECT.md + index.html + STABILITY-MODEL.md. |

**Overall confidence:** **HIGH.** The four researchers converged cleanly on every locked decision; no inter-file disagreements surfaced.

### Gaps for requirements/roadmap pass to address

- **OQ-3 (pillar priority)** — genuinely unresolved; needs user call before Phase 12 first draft. Pitfall #4 forcing function applies.
- **OQ-1 / OQ-2 (phase split shape)** — recommended defaults given but final call belongs to roadmapper.
- **OQ-4 (guiding principles count)** — recommended default of 5 with seed list; final list is Phase-A authoring decision.
- **OQ-5 (Jira sub-task timing)** — process question; defer to post-roadmap.
- **PITFALLS.md #12 / #23** — strategy-doc-never-updates-again is a process risk that requires amending `/gsd-complete-milestone` template, NOT just a v0.5.0 phase-plan acceptance criterion. Flag for the v0.5.0 retrospective + the `/gsd-new-milestone` template update that follows.
