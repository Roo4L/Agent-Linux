# AgentLinux

## What This Is

AgentLinux is an **installable extension for Linux distributions** that turns a user's existing system into an agent-ready environment. Instead of shipping a whole distro, AgentLinux installs on top of popular distros (Ubuntu first; Fedora / CentOS / Alma / Arch later) and provisions a dedicated agent user, a correctly-owned Node.js runtime, a default agent (e.g. Claude Code), and a curated registry for installing additional agents.

The project also maintains a landing page at **agentlinux.org** for validation and subscriber collection.

## Core Value

An agent can be dropped into any supported Linux system and *just work* — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights, sudo prompts, or recursive-shim workarounds. Installing AgentLinux on your distro gives you an agent environment that was built right the first time.

See [docs/VISION.md](../docs/VISION.md) for the framing this Core Value seeds.

## Current State

**Last shipped:** v0.3.3 Agenda Redefinition (2026-05-24).
**Next milestone:** TBD — run `/gsd-new-milestone` to scope.

The vision/strategy/roadmap framing is locked: `docs/VISION.md` (the canonical "what we want to be"), `docs/STRATEGY.md` (the canonical "how we get there"), `docs/ROADMAP.md` (the time-ordered "what's next"). ADR-016 records the two-pillar framing decision. The agentlinux.org website mirrors the framing.

The next milestone is open for scoping. Candidates flagged for v0.6+ (per `docs/ROADMAP.md` themes): Security Hardening (capability-scoped sudoers, cosign-signed catalog releases, npm provenance, bubblewrap-based per-recipe sandbox profile), preset/profile framework, compat-guarded update flow.

## Previous Milestone: v0.3.3 Agenda Redefinition — Shipped 2026-05-24

**Anchor:** Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7).

Broadened AgentLinux's framing from a single-pillar product to a two-pillar product across 5 phases (Pillar 2 Exploration; Pillar 3 Candidate Exploration; Vision Doc + ADR-016 + Downstream Surface Updates; Strategy + Roadmap Doc; Website Refresh). Phase 14 verdict (b) declined a separate Pillar 3 (security folds into Pillar 2 as sub-concern). Vision/strategy/roadmap separated into three documents (VISION.md, STRATEGY.md, ROADMAP.md). The voice-rule grep gate (VIS-07, STRATR-06, SITE-06) ran green on every artefact. agentlinux.org refreshed to reflect the two pillars. ADR-016 records the framing decision with three considered-and-rejected alternatives.

**The two pillars (locked by Phase 14 verdict (b)):**
1. **Time-to-productive** — the assembly the user gets on install: agent user, runtime, permissions, curated catalog. Foundational; settled by v0.3.0.
2. **Stability** — the curated toolchain holds compatible across upstream churn. The supply-chain monitoring + curated catalog admission sub-concern folded into this pillar in Phase 14 verdict (b) — mechanism work lands in v0.6+.

**What carries forward into the next milestone:** The vision/strategy/roadmap framing locks downstream phases — any v0.6+ work scopes against `docs/STRATEGY.md` "Our bets" + `docs/ROADMAP.md` "What's next." Voice rule applies to every public-facing artefact going forward. PR-preview deployments now live on the agentlinux.org repo so framing changes can be reviewed visually before merge.

## Previous Milestone: v0.4.0 Open-Source Release — Shipped 2026-05-09

v0.4.0 took AgentLinux from a private repository to a public one across 5 phases (License + Public-Ready Documentation; Secret Scanning + History Audit; Repository Hygiene + Artifact Cleanup; Public CI/CD + Branch Protection; Public Visibility Flip + Smoke Test). MIT licensed (ADR-013). Zero verified secrets in history (gitleaks + trufflehog + targeted manual audit). gitleaks gate live in pre-commit + CI. Workflow `permissions:` blocks at least-privilege; zero `pull_request_target` usage. Branch protection applied on `master`. The visibility flip executed and the post-flip anonymous-clone + `curl | bash` smoke test against the v0.3.0 release tag both succeeded.

**What carries forward into v0.3.3:** Public-repo CI/CD spend now lives on free GitHub Actions minutes, unblocking the broader benchmark/security work that pillars 2 and 3 will eventually require. The OSS license + CONTRIBUTING surface lets external contributors begin engaging with the strategy doc and any v0.6+ work that flows from it. ADR-001..ADR-014 + the behavior-test contract (bats suite as spec) + the per-phase TST-07-style phase-close gate convention all carry forward unchanged; v0.3.3 phases follow the same evidence-cite-per-requirement pattern, with documentation artifacts substituting for bats where appropriate.

## Earlier Milestones

### v0.3.0 AgentLinux Plugin (Ubuntu) — Shipped 2026-04-20

v0.3.0 shipped the installable Ubuntu plugin in 6 phases (Harness, Installer Foundation + Agent User, Node.js Runtime, Registry CLI + Catalog, Agent Installability, Distribution + Release Pipeline) plus one inserted phase (5.1 Agent User Sudo Drop-In). All 54 v0.3.0 requirements have observable bats coverage; Ubuntu 22.04 + 24.04 + 26.04 Docker matrices and the QEMU release-gate suite green; AGT-02 (the canonical "Claude Code self-updates without sudo / EACCES" acceptance test) passes end-to-end against the live Anthropic CDN. 4-gate `release.yml` (pre-commit → Docker matrix → QEMU release gate → pinned-combo gate). Carries forward: behavior-test contract (bats suite as spec), curl-pipe-bash installer, catalog + registry CLI, ADR-001..ADR-012, TST-07 phase-close gate convention.

### v0.2.0 First Distro Image (retired 2026-04-18 — pivot)

The v0.2.0 milestone aimed to ship a custom Linux distribution (Debian 12 QCOW2 for OpenNebula/KVM) with agent tooling pre-baked as `.deb` packages. Phases 1–4 shipped (Packer infrastructure, Node.js install, Chrome install, Claude Code / GSD / Chrome DevTools MCP fpm packaging). Phase 5 (end-to-end OpenNebula validation) was dropped along with the distro-as-product approach.

**Why the pivot:** Building a distro forces users to migrate their OS to try AgentLinux — high adoption friction, narrow reach. Shipping an installable extension on top of their existing distro delivers the same agent-user-provisioning value with a fraction of the friction, and lets AgentLinux ride on top of the distro ecosystem's existing packaging/update infrastructure.

**What carries forward:** Provisioner script logic from v0.2.0 (Node.js install, Chrome install, Claude Code / GSD / MCP install patterns, correct-ownership-for-the-agent-user lessons) ports directly into the v0.3.0 plugin installer. fpm packaging experience may inform the plugin's own `.deb` packaging if that distribution mechanism is chosen.

## Requirements

### Validated

- ✓ Landing page with terminal/hacker aesthetic (dark theme, monospace, CLI feel) — v0.1.0
- ✓ Problem explainer section with current pain points (permissions, Docker-in-Docker, VM friction) — v0.1.0
- ✓ Feature showcase with 8 planned AgentLinux capabilities and SVG icons — v0.1.0
- ✓ Narrative comparison of AgentLinux vs alternatives (local, Docker, VMs) — v0.1.0
- ✓ Email subscription form integrated with Buttondown — v0.1.0
- ✓ Static site (HTML/CSS/JS) with no build step — v0.1.0
- ✓ Custom domain agentlinux.org with HTTPS on GitHub Pages — v0.1.0
- ✓ GitHub Actions auto-deploy on push to master — v0.1.0
- ✓ FAQ accordion section — v0.1.0
- ✓ Responsive design (mobile + desktop) — v0.1.0
- ✓ Crab mascot SVG and favicon — v0.1.0
- ✓ OG/Twitter meta tags for social sharing — v0.1.0
- ✓ GA4 analytics, robots.txt, sitemap.xml — v0.1.0
- ✓ Node.js 22 LTS from NodeSource install patterns — v0.2.0 (carries into v0.3.0 plugin installer)
- ✓ Claude Code / GSD / Chrome DevTools MCP install patterns via npm + /etc/skel config — v0.2.0 (carries forward)
- ✓ Chrome install pattern for MCP server dependency — v0.2.0 (carries forward)
- ✓ fpm-based `.deb` packaging workflow — v0.2.0 (reference material for plugin distribution)
- ✓ One-command Ubuntu installer (curl-pipe-bash + optional `.deb`) — v0.3.0
- ✓ Dedicated agent user with correctly-owned Node.js runtime + per-user npm prefix (no sudo for global installs) — v0.3.0
- ✓ Six-mode PATH wiring (interactive, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`) — v0.3.0
- ✓ Passwordless sudo for the agent user via `/etc/sudoers.d/agentlinux` (ADR-012) — v0.3.0 phase 5.1
- ✓ Registry CLI `agentlinux list/install/remove/upgrade/pin` with JSON-Schema-validated catalog — v0.3.0
- ✓ Three catalog agents — claude-code, gsd, playwright — opt-in installable; no defaults — v0.3.0
- ✓ Canonical acceptance test AGT-02: Claude Code self-update without sudo / EACCES — v0.3.0 (live against Anthropic CDN, both Ubuntu 22.04 + 24.04)
- ✓ Bats behavior-test suite + Docker matrix + QEMU release-gate suite + 4-gate `release.yml` — v0.3.0
- ✓ Pinned-combo release gate (TST-08) + catalog snapshot publication (CAT-05) per ADR-011 — v0.3.0
- ✓ MIT OSS license (ADR-013) — `LICENSE` at repo root, README license badge + section, SPDX headers on first-party source files (LIC-01..04) — v0.4.0
- ✓ Full git-history secret scan (gitleaks + trufflehog + targeted manual audit) — zero verified findings, one false positive triaged (SEC-01..03) — v0.4.0
- ✓ Pre-commit + CI gitleaks gate live; smoke-test confirms gate fires on contrived secrets (SEC-04..05) — v0.4.0
- ✓ Repository hygiene: `.gitignore` hardened, no stale branches, no >500 KB blobs in history (CLEAN-01..04) — v0.4.0
- ✓ Workflow `permissions:` blocks at least-privilege; zero `pull_request_target`; branch protection on `master` applied (CIPUB-01..04) — v0.4.0
- ✓ Repository visibility flipped to public; anonymous-clone + `curl | bash` smoke against v0.3.0 release tag green (PUB-01..04) — v0.4.0
- ✓ Pillar 2 verdict published with hard reframe (infrastructure, not agent product) at `docs/exploration/PILLAR-2-NOTES.md` (EXPL-01) — v0.3.3
- ✓ Pillar 3 candidate verdict (b) at `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` — security folds into Pillar 2 as sub-concern (EXPL-02) — v0.3.3
- ✓ Canonical vision document at `docs/VISION.md` — mission, two pillars as optimization values, guiding principles, non-goals (VIS-01..09) — v0.3.3
- ✓ ADR-016 at `docs/decisions/016-agenda-redefinition.md` records the two-pillar framing decision with three considered-and-rejected alternatives (VIS-09) — v0.3.3
- ✓ Downstream surface back-pointers to VISION.md across README, CONTRIBUTING, PROJECT.md, STABILITY-MODEL.md (DOC-01..04); DOC-05 closed N/A (no Pillar 3) — v0.3.3
- ✓ Canonical strategy document at `docs/STRATEGY.md` with the 4-section Rumelt-style spine (diagnosis + bets + guiding policy + execution principles); ROADMAP.md split out per Round-2 amendment (STRATR-01..07) — v0.3.3
- ✓ Website refresh at agentlinux.org reflecting the two-pillar framing; voice-rule grep gate clean on rendered HTML (SITE-01..09 + SITE-12; SITE-02/03/05/07/11 superseded under scope re-cut, SITE-10 N/A) — v0.3.3
- ✓ Voice-rule grep gate as hard gate on VISION.md, STRATEGY.md, ROADMAP.md, and rendered HTML (VIS-07, STRATR-06, SITE-06) — v0.3.3

### Active

(None — milestone open for scoping. Run `/gsd-new-milestone`.)

### Out of Scope

**v0.3.3 out of scope:**
- *Implementing* preset/profile framework or compat-guarded update mechanism (Pillar 2 forward differentiators) — v0.3.3 surfaces them in the strategy doc; the actual implementation lands in a v0.6+ milestone.
- *Implementing* security-hardening countermeasures (the Phase 14 opportunistic theme) — supply-chain and prompt-injection mitigations land in a v0.6+ milestone.
- New distro targets, new catalog agents, new installer features — Pillar 1 stays at its v0.3.0 surface for this milestone.
- A full website redesign — the website-refresh phase keeps the existing dark JetBrains-Mono aesthetic + crab mascot.
- Renaming, restructuring, or moving the vision or strategy docs after Phase 15 / Phase 16 land — locations lock at `docs/VISION.md` and `docs/STRATEGY.md`.
- *Resolving* the ADR-012 NOPASSWD tension. The vision doc and ADR-016 *document* the tension; the *resolution* belongs to the v0.6+ Security Hardening milestone.
- Authoring a Code of Conduct, SECURITY.md, or full issue / PR templates — track separately as a community-platform milestone.

**v0.4.0 out of scope (carried forward):**
- New distro targets (Fedora / CentOS / Alma / Arch / openSUSE) — deferred to a later milestone
- Mutation testing promotion to release gate — still v0.5+ per ADR-010
- Multi-arch (ARM) — x86_64 only for now
- Repo migration to a different GitHub organization or rename

**v0.3.0 out of scope (carried forward):**
- Fedora / CentOS / Alma / Arch / openSUSE targets (deferred to a later feature milestone)
- GUI or TUI installer (CLI only)
- Public PPA / package-signing infrastructure beyond curl-installer + GitHub Releases
- Multi-user provisioning (one agent user per host for now)
- Sandboxing / rootless containers inside the installer
- Custom distro / ISO / QCOW2 image build path — retired with the v0.2.0 → v0.3.0 pivot
- OpenNebula contextualization, deploy, and E2E test pipeline — retired with the v0.2.0 → v0.3.0 pivot
- `.deb` packages for Claude Code / GSD / MCP as standalone distro artifacts — superseded by in-installer npm install

**Permanently out of scope:**
- User accounts or login functionality on website
- Blog or content management system
- Mobile app
- E-commerce / payments
- Multi-arch (ARM) — x86_64 only for now
- Docker-in-Docker inside the agent environment

## Context

**Website (v0.1.0, shipped 2026-03-10):** Landing page at agentlinux.org, 1,045 LOC HTML/CSS/JS/SVG/XML, deployed via GitHub Actions. Continues to serve as top-of-funnel validation channel.

**Distro experiment (v0.2.0, retired 2026-04-18):** Packer + QEMU + fpm stack produced bootable Debian 12 QCOW2 images with three agent tools pre-packaged. Useful provisioner-script learnings. Retired because distro-as-product has too much adoption friction vs. an installable extension.

**Plugin (v0.3.0, shipped 2026-04-20):** All 6 phases plus inserted phase 5.1 shipped. 54/54 requirements covered. v0.3.0-rc1 tag pushed; release pipeline executed end-to-end.

**Open-Source Release (v0.4.0, shipped 2026-05-09):** Repository is now public. Free GitHub Actions minutes unblock the broader benchmark/security work pillars 2 and 3 will eventually require. MIT licensed (ADR-013). Zero verified secrets in history. Workflow `permissions:` blocks at least-privilege; branch protection on `master`; post-flip anonymous-clone + `curl | bash` smoke green.

**Agenda Redefinition (v0.3.3, current):** Anchored on Jira epic AL-7. Broadens AgentLinux's framing from a single-pillar product to two pillars (Time-to-productive + Stability) — Phase 14 verdict (b) declined a separate security pillar; the supply-chain monitoring sub-concern folds into Pillar 2. Captures the framing in `docs/VISION.md` (Phase 15), `docs/STRATEGY.md` (Phase 16), ADR-016, and the post-Phase-16 website refresh. Forward-looking — Pillar 2's mechanism work (preset/profile framework + compat-guarded update flow + Security Hardening) seeds v0.6+ milestones; v0.3.3 ships the framing, not the implementation.

Known minor issue (carried forward): OG image (SVG format) doesn't render on all social platforms — convert to PNG for broader support (website todo).

## Constraints

- **Target OS (v0.3.0):** Ubuntu LTS — 22.04 (Jammy), 24.04 (Noble), 26.04 (Resolute Raccoon, added 2026-04-26 per AGE-11). Fedora/CentOS/Alma/Arch deferred.
- **Install UX:** one-command from user perspective; internally may chain apt / curl / npm / fpm.
- **Node.js ownership:** must be owned by the agent user or use a writable global prefix under the agent user's home — no `sudo npm install -g`.
- **Test harness:** containerized or QEMU-based; no real-hardware / cloud-VM deploy step.
- **Website stack:** Static HTML/CSS/JS — no frameworks, no build step (unchanged from v0.1.0).
- **Hosting:** GitHub Pages for website. Plugin distribution TBD.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Validate before building | De-risk with a landing page first | ✓ Good — site shipped |
| Static site over framework | Simplicity, no build tooling | ✓ Good — 1,045 LOC, 2-day build |
| Buttondown for email | Simple API, free tier | ✓ Good — working form |
| Terminal/hacker aesthetic | Matches target audience | ✓ Good — cohesive dark theme |
| SVG for OG image | Simpler than generating PNG | ⚠️ Revisit — doesn't render on all platforms |
| Inline CSS (no separate stylesheet) | Single-file simplicity | ✓ Good |
| GitHub Pages + Actions | Free hosting, auto-deploy, HTTPS | ✓ Good |
| **v0.2.0 → v0.3.0 pivot** (2026-04-18) | Distro-as-product has high adoption friction; extension-on-top-of-distro delivers same agent-user-provisioning value with near-zero install friction and broader reach | — Active |
| Debian 12 Bookworm as distro base | Stable, widely deployed, strong apt ecosystem | Retired with pivot |
| Packer + QEMU for image build | Reproducible, industry-standard | Retired with pivot |
| fpm for .deb packaging | Pragmatic, not Debian-policy-compliant | Retired as a distribution mechanism; may return as plugin packaging |
| Node.js 22 LTS from NodeSource | LTS, stable install path | Carries forward into plugin installer |
| Local apt repo in image (no public PPA) | Sufficient for PoC | Retired with pivot |
| Ubuntu as v0.3.0 target | Largest developer Linux audience; apt-based (leverages v0.2.0 learnings) | ✓ Good — v0.3.0 shipped on Ubuntu 22.04 + 24.04 |
| Canonical acceptance test: Claude Code self-update | Directly tests the motivating bug class (EACCES / recursive shim) | ✓ Good — AGT-02 green end-to-end against Anthropic CDN |
| **Open-source the repo (v0.4.0)** (2026-04-26) | Private-repo CI/CD spend is non-trivial; public repos get free Actions minutes; unblocks community contributions and outside marketing | ✓ Shipped 2026-05-09 |
| MIT as the OSS license (ADR-013) | Permissive, dependency-friendly, low-friction for community adoption | ✓ Applied in v0.4.0 Phase 7 |
| Visibility flip treated as irreversible-in-practice | Re-private is possible but third parties may have already cloned/forked; one-way trip | ✓ Drove the v0.4.0 Phase 11 pre-flight checklist; flip executed |
| **Agenda redefinition (v0.3.3)** (2026-05-09, AL-7) | A single-pillar framing was too narrow to position AgentLinux and to attract the right contributors; broadening landed at two pillars per Phase 14 verdict (b) | ✓ Shipped 2026-05-24 — landed at two pillars (Time-to-productive + Stability) |
| Vision/strategy/roadmap split into three docs | Different audiences (product leadership / contributors + AI agents / time-ordered planning); reduces aspirational drift risk per Pitfall #12 | ✓ Shipped 2026-05-24 — VISION.md + STRATEGY.md + ROADMAP.md all landed |
| Defer pillar 2 mechanism work to v0.6+ | Framing must lock before mechanism work picks scope; otherwise the implementation ships against an unstable framing | ✓ Good — framing locked; v0.6+ themes seeded in `docs/ROADMAP.md` |
| **2026-05-16 reframe — two pillars + vision/strategy split** (ADR-016) | Phase 14 verdict (b) declined a separate security pillar (no honest already-shipped table-stakes; aspirational drift risk per Pitfall #6); user reframe split vision/strategy into separate documents because they serve different audiences. Three considered-and-rejected alternatives recorded in ADR-016. | ✓ Shipped 2026-05-24 — ADR-016 landed; vision/strategy/roadmap split executed in Phase 16 Round 2 |
| Voice-rule grep gate as hard gate on VISION.md / STRATEGY.md / ROADMAP.md / index.html | Single most important defence against shipping vaporware; the grep is the spec | ✓ Good — clean across all four artefacts at v0.3.3 close |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-24 after v0.3.3 milestone — Agenda Redefinition shipped. Two-pillar framing locked at `docs/VISION.md`; strategy + roadmap at `docs/STRATEGY.md` + `docs/ROADMAP.md`; agentlinux.org refreshed. Next milestone open for scoping via `/gsd-new-milestone`.*
