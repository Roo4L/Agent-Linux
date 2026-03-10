# AgentLinux

## What This Is

AgentLinux — a Linux distribution purpose-built for running AI agents. The project includes a landing page at agentlinux.org for validation and subscriber collection, and the distro itself: a minimal Linux image where every default is configured for agents, not humans. Agents and their tooling are distributed as native packages.

## Core Value

An agent can boot into a Linux environment that works out of the box — no setup, no permission fights, no missing tools — with agent software available via the system package manager.

## Current Milestone: v0.2.0 First Distro Image

**Goal:** Produce a bootable QCOW2 image for OpenNebula/KVM that demonstrates the core AgentLinux concept — agent user, packaged agent tooling, and MCP server with dependencies.

**Target features:**
- Linux-based QCOW2 image with OpenNebula contextualization
- Automatic agent user created on first boot, SSH-ready
- `.deb` package for Claude Code
- `.deb` package for GSD framework
- `.deb` package for Chrome DevTools MCP server (Chrome as dependency)
- Automated image build process

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

### Active

- [ ] Linux-based QCOW2 image for OpenNebula/KVM
- [ ] OpenNebula contextualization (SSH key injection, network config via scripts)
- [ ] Agent user created on first boot, SSH-ready
- [ ] `.deb` package for Claude Code (wraps npm package + Node.js dependency)
- [ ] `.deb` package for GSD framework (wraps npm package)
- [ ] `.deb` package for Chrome DevTools MCP server (Chrome as dependency)
- [ ] Automated image build process

### Out of Scope

- Package groups (one-command workload installs) — future milestone
- Agent skills system — future milestone
- Agent-friendly CLI tools — future milestone
- Multiple distribution formats (ISO, Docker micro-VMs) — future milestone
- Local apt repository / PPA hosting — future milestone
- User accounts or login functionality on website
- Blog or content management system
- Mobile app
- E-commerce / payments

## Context

**Website (v0.1.0):** Shipped landing page with 1,045 LOC across HTML/CSS/JS/SVG/XML. Static HTML/CSS/JS, Buttondown API, GA4. Deployed on GitHub Pages at agentlinux.org.

**Distro (v0.2.0):** First image targeting OpenNebula/KVM at work infrastructure. Base distro TBD (research needed). Image build tooling TBD (research needed). Target packages: Claude Code (`@anthropic-ai/claude-code` npm), GSD (`get-shit-done` npm), Chrome DevTools MCP server.

Known minor issue: OG image (SVG format) doesn't render on all social platforms — convert to PNG for broader support.

## Constraints

- **Target**: OpenNebula/KVM — QCOW2 image format, virtio drivers, one-context package
- **Packaging**: `.deb` packages for agent tooling
- **Base distro**: TBD — research needed before committing
- **Image build**: Automated and reproducible (tooling TBD)
- **Website stack**: Static HTML/CSS/JS — no frameworks, no build step
- **Hosting**: GitHub Pages for website, OpenNebula for distro images

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Validate before building | De-risk the distro investment by testing demand first | ✓ Good — site shipped |
| Static site over framework | Simplicity, no build tooling, fast to ship | ✓ Good — 1,045 LOC, 2-day build |
| Buttondown for email | Simple API, good developer experience, free tier | ✓ Good — working form |
| Terminal/hacker aesthetic | Matches target audience (developers running agents) | ✓ Good — cohesive dark theme |
| SVG for OG image | Works for direct links, simpler than generating PNG | ⚠️ Revisit — doesn't render on all platforms |
| Inline CSS (no separate stylesheet) | Single-file simplicity per static site constraint | ✓ Good — easy to maintain |
| GitHub Pages + Actions | Free hosting, auto-deploy, HTTPS included | ✓ Good — zero-cost deployment |
| GA4 with placeholder ID | User configures after creating GA4 property | ✓ Good — replaced with real ID |

| Base distro TBD | Research needed — affects packaging format, image tools, ecosystem | — Pending |

---
*Last updated: 2026-03-10 after v0.2.0 milestone started*
