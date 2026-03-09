# AgentLinux

## What This Is

A landing page for AgentLinux — a Linux distribution purpose-built for running AI agents. The site pitches the concept, explains the problems with current agent runtime environments, showcases planned features, and collects email subscribers via Buttondown to validate demand before building the distro itself.

## Core Value

Convince visitors that running agents on today's Linux setups is unnecessarily painful, and that a purpose-built distro is the right solution — compelling enough to leave their email.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Landing page with terminal/hacker aesthetic (dark theme, monospace, CLI feel)
- [ ] Problem explainer section walking through current pain points (permissions, Docker-in-Docker, VM setup friction, bloated packages, non-agent-friendly CLI tooling)
- [ ] Feature showcase section highlighting planned AgentLinux capabilities (minimalistic base, auto agent user setup, package groups for web/GUI dev, agent skills, agent-friendly CLI tooling, multiple distribution formats)
- [ ] Comparison table showing AgentLinux vs current alternatives (local machine, sandboxed local, Docker, generic VMs)
- [ ] Email subscription form integrated with Buttondown
- [ ] Static site (HTML/CSS/JS) deployable to any hosting platform
- [ ] Domain: agentlinux.org (Hostinger, not yet configured)

### Out of Scope

- Building the actual Linux distribution — this is validation only
- User accounts or login functionality
- Blog or content management system
- Community features (Discord/GitHub links) — not requested for v1
- Mobile app

## Context

**The AgentLinux Vision:**
AgentLinux is a planned Linux distro that solves the "where do I run my agent?" problem. Current options all have friction:
1. **Local machine** — permission fights, environment pollution
2. **Local sandboxing** — same permission problems
3. **Docker** — Docker-in-Docker and virtualization pain
4. **Generic VMs** — manual user setup (Claude Code can't run as root), Chrome/GUI setup, bloated default packages, CLI tools designed for humans not agents

AgentLinux would ship: minimalistic base, automatic non-root agent user with correct permissions, easy package groups for web/GUI dev, skills for popular AI agents, agent-friendly CLI tooling, and distribution via ISO, QEMU images, and Docker/Podman micro-VMs.

**Target audience:** Developers and teams running AI coding agents (starting with Claude Code users).

**Landing page goal:** Share with friends for feedback + test internet demand via email signups.

**Tech decisions:**
- Static site (HTML/CSS/JS) — simple, fast, deploy anywhere
- Buttondown for email collection
- Terminal/hacker aesthetic — dark theme, monospace fonts, CLI visuals
- Domain: agentlinux.org on Hostinger

## Constraints

- **Scope**: Landing page only — no distro work yet
- **Stack**: Static HTML/CSS/JS — no frameworks, no build step
- **Email**: Buttondown integration for subscriber collection
- **Hosting**: Must be deployable to Hostinger (or any static host)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Validate before building | De-risk the distro investment by testing demand first | — Pending |
| Static site over framework | Simplicity, no build tooling, fast to ship | — Pending |
| Buttondown for email | Simple API, good developer experience, free tier | — Pending |
| Terminal/hacker aesthetic | Matches target audience (developers running agents) | — Pending |
| Claude Code as first target agent | User's primary agent, natural starting point | — Pending |

---
*Last updated: 2026-03-09 after initialization*
