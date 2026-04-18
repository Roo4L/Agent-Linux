# Milestones

## v0.1.0 AgentLinux Landing Page (Shipped: 2026-03-10)

**Phases completed:** 2 phases, 5 plans
**Timeline:** 2 days (2026-03-09 → 2026-03-10)
**LOC:** 1,045 (HTML/CSS/JS/SVG/XML)

**Key accomplishments:**
- Full landing page with dark terminal aesthetic, crab mascot SVG, and sticky navigation
- Problem/features/comparison content sections with 11 inline Lucide SVG icons
- Email signup form integrated with Buttondown API, FAQ accordion, responsive design
- OG/Twitter meta tags, crab favicon SVG, GA4 analytics snippet, robots.txt, sitemap.xml
- GitHub Actions auto-deploy to GitHub Pages with custom domain agentlinux.org and HTTPS

**Git range:** `5daab9e..133cfa0`
**Archived phases:** `.planning/milestones/v0.1.0-phases/`

---

## v0.2.0 First Distro Image (Retired: 2026-04-18 — pivoted)

**Status:** Partially shipped, then retired during pivot to installable plugin (v0.3.0).

**Phases completed:** 2 of 3 (phases 3 and 4); phase 5 dropped without execution.
**Plans completed:** 5 (3 in phase 3, 2 in phase 4)
**Timeline:** 2026-03-15 → 2026-03-18 active execution

**What shipped:**
- Packer + QEMU build infrastructure for Debian 12 QCOW2 images
- 6-script provisioner chain: base → one-context → Node.js → Chrome → agent-tools → cleanup
- Node.js 22 LTS install from NodeSource (carries forward)
- Chrome install pattern for Chrome DevTools MCP server dependency (carries forward)
- fpm-built `.deb` packages for Claude Code, GSD framework, Chrome DevTools MCP server (reference material)
- Local apt repo embedded in image
- /etc/skel-based Claude Code config with Chrome DevTools MCP pre-wired

**What was dropped:**
- Phase 5 (End-to-End OpenNebula Validation) — not started, retired with pivot
- The QCOW2-image-as-product distribution model
- OpenNebula deploy / contextualize / verify pipeline

**Why retired:** Building a custom distro forces users to migrate their OS to try AgentLinux — high adoption friction, narrow reach. Shipping an installable extension on top of users' existing distros (v0.3.0) delivers the same agent-user-provisioning value with near-zero install friction, broader reach, and reuses provisioner-script logic from this milestone.

**What carries forward into v0.3.0:** Node.js install patterns, Chrome install patterns, Claude Code / GSD / MCP install patterns, /etc/skel default-config approach, fpm packaging knowledge (may apply to plugin's own `.deb` packaging), and lessons about agent-user file ownership for clean self-update.

**Git range:** `5b1cdb4..44a7f03` (approximate; ends with `wip: pause between phases (04 done, 05 not started)`)
**Archived phases:** `.planning/milestones/v0.2.0-phases/`

---

## v0.3.0 AgentLinux Plugin (Ubuntu) — IN PROGRESS

**Started:** 2026-04-18

**Goal:** Ship a one-command installable extension for Ubuntu that turns any existing system into an agent-ready environment — dedicated agent user with correctly-owned Node.js runtime, default agent (Claude Code) installed, CLI registry for installing additional agents.

See: `.planning/PROJECT.md` and `.planning/ROADMAP.md` for active scope and phases.

---
