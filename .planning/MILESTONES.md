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

## v0.3.0 AgentLinux Plugin (Ubuntu) — Feature-complete: 2026-04-20

**Phases completed:** 6 + 1 inserted (Phase 5.1)
**Plans completed:** 30
**Timeline:** 2026-04-18 → 2026-04-20 (~3 days active execution)

**Key accomplishments:**
- One-command installable Ubuntu plugin (curl-pipe-bash + optional `.deb` via fpm) with SHA256-verified release tarball
- Dedicated `agent` user provisioned with correctly-owned Node.js 22 LTS runtime, per-user npm prefix at `/home/agent/.npm-global/`, and six-mode PATH wiring (interactive, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`)
- Passwordless sudo for agent user via `/etc/sudoers.d/agentlinux` (ADR-012) — required for Playwright `install --with-deps`
- Registry CLI `agentlinux list/install/remove/upgrade/pin` with JSON-Schema-validated catalog (3 real agents available, none installed by default)
- AGT-02 canonical acceptance test green: agent user can `claude update` against the live Anthropic CDN with zero EACCES / permission-denied lines, on both Ubuntu 22.04 + 24.04
- Behavior-test contract: 66/66 bats green on both Ubuntu versions; harness 104/104; 4-gate `release.yml` (pre-commit → Docker matrix → QEMU release gate → pinned-combo gate per ADR-011)

**v0.3.0 ships when:** First `v0.3.0-rc1` tag push exercises `release.yml` end-to-end against the live GitHub Release publish path. Static gates all green; the tag push is the runtime-shipping event.

**Archived planning:** `.planning/milestones/v0.3.0-REQUIREMENTS.md` + `.planning/milestones/v0.3.0-ROADMAP.md` (preserved for traceability; phase directories remain under `.planning/phases/01-*..06-*` until v0.3.0 ships).

---

## v0.4.0 Open-Source Release — IN PROGRESS

**Started:** 2026-04-26

**Goal:** Open-source the AgentLinux GitHub repository — establish OSS licensing, eliminate any leaked secrets from git history, clean up build artifacts and stale branches, verify CI/CD operates correctly under public-repo permissions, and flip visibility to public so AgentLinux can ride free GitHub Actions minutes and accept community contributions.

**Why now:** Private-repo CI/CD spend has become non-trivial as the QEMU release-gate matrix grew (Phase 6 of v0.3.0). Public repos get free Actions minutes. Public visibility also unblocks community contributions and outside marketing/outreach.

See: `.planning/PROJECT.md` and `.planning/ROADMAP.md` for active scope and phases.

---
