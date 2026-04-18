# AgentLinux

## What This Is

AgentLinux is an **installable extension for Linux distributions** that turns a user's existing system into an agent-ready environment. Instead of shipping a whole distro, AgentLinux installs on top of popular distros (Ubuntu first; Fedora / CentOS / Alma / Arch later) and provisions a dedicated agent user, a correctly-owned Node.js runtime, a default agent (e.g. Claude Code), and a curated registry for installing additional agents.

The project also maintains a landing page at **agentlinux.org** for validation and subscriber collection.

## Core Value

An agent can be dropped into any supported Linux system and *just work* — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights, sudo prompts, or recursive-shim workarounds. Installing AgentLinux on your distro gives you an agent environment that was built right the first time.

## Current Milestone: v0.3.0 AgentLinux Plugin (Ubuntu)

**Goal:** Ship a one-command installable extension for Ubuntu that provisions an agent-ready environment — a dedicated agent user with a correctly-owned Node.js runtime, a default agent installed, and a CLI registry for installing additional agents. Installer success is measured by the agent user's ability to self-update Claude Code without any permission intervention.

**Target features:**
- One-command installer for Ubuntu (distribution mechanism — script / .deb / PPA — TBD in research)
- Dedicated agent user provisioning with correctly-owned Node.js runtime, npm global prefix, and default agent install (eliminates EACCES / recursive-shim class of bugs)
- Node.js LTS installed "comfortably" — writable global prefix in the agent user's home, not system-owned
- Default agent installed on install (Claude Code is the default; configurable)
- Curated agent registry — post-install CLI to list/install additional agents (Claude Code, GSD, Chrome DevTools MCP, etc.)
- Container + QEMU test harness (reproducible CI inside a clean Ubuntu Docker container and/or ephemeral QEMU VM)

## Previous Milestone: v0.2.0 First Distro Image (retired 2026-04-18 — pivot)

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

### Active

- [ ] One-command installer for Ubuntu (distribution mechanism TBD)
- [ ] Dedicated agent user provisioning with correctly-owned Node.js runtime
- [ ] npm global prefix owned by agent user (no sudo for global installs)
- [ ] Default agent install on first install (Claude Code)
- [ ] Agent registry CLI — list and install additional agents post-install
- [ ] Container-based (Docker) test harness for installer verification
- [ ] QEMU-based test harness for installer verification (optional second track)
- [ ] Canonical acceptance test: agent user can `claude` self-update without sudo

### Out of Scope

**v0.3.0 out of scope:**
- Fedora / CentOS / Alma / Arch / openSUSE targets (deferred to v0.4+)
- GUI or TUI installer (CLI only)
- Public PPA / package-signing infrastructure (local install only)
- Multi-user provisioning (one agent user per host for now)
- Sandboxing / rootless containers inside the installer
- Custom distro / ISO / QCOW2 image build path — retired with the pivot
- OpenNebula contextualization, deploy, and E2E test pipeline — retired with the pivot
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

**Plugin (v0.3.0, current):** Installer shape, distribution mechanism, and registry format are open questions for research. Core non-negotiable: agent-user + Node.js + default agent must be set up so Claude Code self-updates without permission intervention.

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
| Ubuntu as v0.3.0 target | Largest developer Linux audience; apt-based (leverages v0.2.0 learnings) | — Active |
| Canonical acceptance test: Claude Code self-update | Directly tests the motivating bug class (EACCES / recursive shim) | — Active |

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
*Last updated: 2026-04-18 — v0.2.0 → v0.3.0 pivot (distro → installable plugin).*
