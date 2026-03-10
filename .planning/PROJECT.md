# AgentLinux

## What This Is

A live landing page for AgentLinux — a Linux distribution purpose-built for running AI agents. The site is deployed at agentlinux.org, pitches the concept with a terminal-aesthetic design, explains agent runtime pain points, showcases planned features, and collects email subscribers via Buttondown.

## Core Value

Convince visitors that running agents on today's Linux setups is unnecessarily painful, and that a purpose-built distro is the right solution — compelling enough to leave their email.

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

(None — define next milestone with `/gsd:new-milestone`)

### Out of Scope

- Building the actual Linux distribution — this is validation only
- User accounts or login functionality
- Blog or content management system
- Mobile app
- E-commerce / payments

## Context

Shipped v0.1.0 with 1,045 LOC across HTML/CSS/JS/SVG/XML.
Tech stack: Static HTML/CSS/JS, Buttondown API, Google Fonts (JetBrains Mono), GA4.
Deployed: GitHub Pages with GitHub Actions, custom domain agentlinux.org via Hostinger DNS.
Live at: https://agentlinux.org

Known minor issue: OG image (SVG format) doesn't render on all social platforms — convert to PNG for broader support.

## Constraints

- **Scope**: Landing page only — no distro work yet
- **Stack**: Static HTML/CSS/JS — no frameworks, no build step
- **Email**: Buttondown integration for subscriber collection
- **Hosting**: GitHub Pages with custom domain agentlinux.org

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

---
*Last updated: 2026-03-10 after v0.1.0 milestone*
