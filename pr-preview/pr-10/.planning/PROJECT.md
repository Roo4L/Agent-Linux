# AgentLinux

## What This Is

AgentLinux is an **installable extension for Linux distributions** that turns a user's existing system into an agent-ready environment. Instead of shipping a whole distro, AgentLinux installs on top of popular distros (Ubuntu first; Fedora / CentOS / Alma / Arch later) and provisions a dedicated agent user, a correctly-owned Node.js runtime, a default agent (e.g. Claude Code), and a curated registry for installing additional agents.

The project also maintains a landing page at **agentlinux.org** for validation and subscriber collection.

## Core Value

An agent can be dropped into any supported Linux system and *just work* — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights, sudo prompts, or recursive-shim workarounds. Installing AgentLinux on your distro gives you an agent environment that was built right the first time.

## Current Milestone: v0.4.0 Open-Source Release

**Goal:** Open-source the AgentLinux GitHub repository — establish OSS licensing, eliminate any leaked secrets from git history, clean up build artifacts and stale branches, verify CI/CD operates correctly under public-repo permissions, and flip visibility to public so AgentLinux can ride free GitHub Actions minutes and accept community contributions.

**Target features:**
- OSS licensing (MIT recommended) — `LICENSE` file at repo root, README updated with license badge/section, SPDX headers on source files where appropriate
- Full git-history secret-scanning sweep (gitleaks + trufflehog) with explicit attention to Buttondown API tokens, GitHub / Anthropic / npm / package-registry credentials, and `.env` / `.npmrc` / `.git-credentials` artifacts
- Remediation of any found secrets (rotate + decide between accept-with-rotation and history rewrite per severity); pre-commit + CI guard to prevent re-introduction
- Repository hygiene cleanup — stale branches, large binary artifacts, accidentally-committed build outputs; `.gitignore` audit
- CI/CD public-readiness — verify all GitHub Actions workflows run correctly under public-repo permissions, harden any `pull_request_target` usage against fork-PR exfiltration, configure branch-protection on `main`
- Public visibility flip + post-flip smoke (anonymous clone + `curl | bash` install path against the v0.3.0 release tag)

## Previous Milestone: v0.3.0 AgentLinux Plugin (Ubuntu) — feature-complete 2026-04-20

v0.3.0 shipped the installable Ubuntu plugin in 6 phases (Harness, Installer Foundation + Agent User, Node.js Runtime, Registry CLI + Catalog, Agent Installability, Distribution + Release Pipeline) plus one inserted phase (5.1 Agent User Sudo Drop-In). All 54 v0.3.0 requirements have observable bats coverage, both Ubuntu 22.04 + 24.04 Docker matrices and the QEMU release-gate suite are green, and AGT-02 (the canonical "Claude Code self-updates without sudo / EACCES" acceptance test) passes end-to-end against the live Anthropic CDN. The v0.3.0 release pipeline is wired (4-gate `release.yml`: pre-commit → Docker matrix → QEMU release gate → pinned-combo gate) and awaits its first `v0.3.0-rc1` tag push as the shipping event. v0.4.0 (open-sourcing) does not block on the rc1 tag — repo cleanup runs in parallel.

**What carries forward:** The behavior-test contract (bats suite as spec), curl-pipe-bash installer, catalog + registry CLI, ADR-001..ADR-012, and the phase-close TST-07 behavior-coverage-auditor gate. v0.4.0 phases follow the same per-phase TST-07 pattern: every requirement gets at least one verifiable check (bats @test, CI-gate citation, or auditable artifact) before the phase closes.

## Earlier Milestones

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

### Active (v0.4.0 — Open-Source Release)

- [ ] OSI-approved OSS license (MIT recommended) — `LICENSE` file at repo root, README updated, SPDX headers where appropriate
- [ ] Full git-history secret scan (gitleaks + trufflehog) with zero confirmed High/Critical findings (or all findings triaged with documented decision)
- [ ] Buttondown API tokens, GitHub / Anthropic / npm credentials, `.env` / `.npmrc` / `.git-credentials` artifacts specifically audited
- [ ] Any leaked secrets rotated; severity decides between accept-with-rotation vs. history rewrite (`git filter-repo`)
- [ ] Pre-commit and/or CI gate runs gitleaks on every PR going forward
- [ ] Stale branches, large binaries (>1 MB outside release artifacts), and accidentally-committed build outputs removed; `.gitignore` audited
- [ ] All GitHub Actions workflows verified to run correctly under public-repo permissions; fork-PR exfiltration paths hardened
- [ ] Branch protection on `main` (require review, require CI green, no force-push)
- [ ] Repository visibility flipped to public via `gh repo edit --visibility public` (or GitHub UI)
- [ ] Post-flip smoke: anonymous HTTPS clone + `curl | bash` install path against v0.3.0 release tag both succeed

### Out of Scope

**v0.4.0 out of scope:**
- New distro targets (Fedora / CentOS / Alma / Arch / openSUSE) — deferred to a later milestone; the public flip is a repo/process milestone, not a feature milestone
- New agent recipes or catalog entries — catalog churn happens in feature milestones, not the open-sourcing one
- Mutation testing promotion to release gate — still v0.5+ per ADR-010
- Multi-arch (ARM) — x86_64 only for now
- Repo migration to a different GitHub organization or rename — out of scope; this milestone keeps the repo in place and only flips visibility

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

**Plugin (v0.3.0, feature-complete 2026-04-20):** All 6 phases plus inserted phase 5.1 shipped. 54/54 requirements covered. Awaits the first `v0.3.0-rc1` tag push as the runtime-shipping event.

**Open-Source Release (v0.4.0, current):** Repo is currently private. Going public delivers two things: free GitHub Actions minutes (private-repo CI/CD spend has become non-trivial as the QEMU release-gate matrix grew) and an unblocked path to community contributions and outside marketing/outreach. Non-negotiables before flipping: a recognized OSS license, zero verifiable secrets in git history (with rotation of anything that did leak), CI/CD verified to keep working under public-repo permissions and fork-PR exfiltration patterns. The visibility flip is the milestone's shipping event.

Known minor issue: OG image (SVG format) doesn't render on all social platforms — convert to PNG for broader support (website todo).

## Constraints

- **Target OS (v0.3.0):** Ubuntu (LTS). Fedora/CentOS/Alma/Arch deferred.
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
| **Open-source the repo (v0.4.0)** (2026-04-26) | Private-repo CI/CD spend is non-trivial; public repos get free Actions minutes; unblocks community contributions and outside marketing | — Active |
| MIT as recommended OSS license | Permissive, dependency-friendly, low-friction for community adoption (vs. Apache-2.0 patent grant or GPL copyleft) | — Active (final pick confirmed in Phase 7) |
| Visibility flip is irreversible-in-practice | Re-private is possible but third parties may have already cloned/forked; treat as one-way | — Active (drives Phase 11 pre-flight checklist) |

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
*Last updated: 2026-04-26 — v0.3.0 feature-complete; v0.4.0 (Open-Source Release) milestone planned.*
