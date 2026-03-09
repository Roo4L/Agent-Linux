# Roadmap: AgentLinux Landing Page

## Overview

Build the complete AgentLinux landing page locally first -- every section, all content, full design, working email form -- then deploy it to GitHub Pages with the custom domain. Two phases: make it, then ship it.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Complete Website** - Build the entire landing page with all content, design, and email form working locally
- [ ] **Phase 2: Deploy to Public** - Ship to GitHub Pages with custom domain agentlinux.org

## Phase Details

### Phase 1: Complete Website
**Goal**: A fully finished landing page that a visitor could browse locally and experience the complete AgentLinux pitch from hero to footer, including working email signup
**Depends on**: Nothing (first phase)
**Requirements**: HERO-01, HERO-02, HERO-03, PROB-01, FEAT-01, FEAT-02, COMP-01, MAIL-01, FAQ-01, DSGN-01, DSGN-02, DSGN-03, FOOT-01
**Success Criteria** (what must be TRUE):
  1. Opening index.html locally shows a dark-themed, terminal-aesthetic page with monospace fonts and CLI-inspired visuals
  2. Above the fold: AgentLinux name, tagline, value proposition, and a CTA button that scrolls to the email form
  3. Scrolling down reveals the problem section (agent runtime pain points), feature showcase with icons, and narrative comparison vs alternatives
  4. Email signup form is wired to Buttondown and submits successfully
  5. FAQ section answers key questions and footer with copyright closes out the page, all responsive on mobile and desktop
**Plans**: 3 plans

Plans:
- [ ] 01-01-PLAN.md — Page foundation, CSS design system, sticky nav, and hero section with crab mascot
- [ ] 01-02-PLAN.md — Problem, features, and comparison content sections
- [ ] 01-03-PLAN.md — Email signup form, FAQ, footer, and responsive polish

### Phase 2: Deploy to Public
**Goal**: The finished site is live at agentlinux.org with HTTPS, auto-deploying on every push
**Depends on**: Phase 1
**Requirements**: DEPL-01, DEPL-02, DEPL-03, DEPL-04
**Success Criteria** (what must be TRUE):
  1. Site is hosted on GitHub Pages and accessible at agentlinux.org with HTTPS
  2. Custom domain agentlinux.org is configured and resolves correctly
  3. Pushing to the main branch triggers GitHub Actions and the live site updates automatically
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Complete Website | 0/3 | Not started | - |
| 2. Deploy to Public | 0/TBD | Not started | - |
