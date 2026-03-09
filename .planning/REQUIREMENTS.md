# Requirements: AgentLinux Landing Page

**Defined:** 2026-03-09
**Core Value:** Convince visitors that running agents on today's Linux setups is painful, and that a purpose-built distro is the right solution — compelling enough to leave their email.

## v1 Requirements

### Hero

- [x] **HERO-01**: Landing page displays AgentLinux name with tagline above the fold
- [x] **HERO-02**: Clear value proposition statement explaining what AgentLinux is and who it's for
- [x] **HERO-03**: CTA button that scrolls to email signup form

### Problem

- [x] **PROB-01**: Pain point section walking through current agent runtime options (local machine, sandboxing, Docker, generic VMs) with specific friction described for each

### Features

- [x] **FEAT-01**: Feature list showcasing planned AgentLinux capabilities with descriptions
- [x] **FEAT-02**: Visual icons or illustrations accompanying each feature

### Comparison

- [x] **COMP-01**: Narrative-style comparison of AgentLinux vs current alternatives (local, Docker, VMs)

### Email

- [ ] **MAIL-01**: Email signup form integrated with Buttondown API

### FAQ

- [ ] **FAQ-01**: FAQ section with common questions about AgentLinux

### Design

- [x] **DSGN-01**: Terminal/hacker aesthetic — dark theme, monospace fonts, CLI visual style
- [ ] **DSGN-02**: Responsive design (mobile + desktop)
- [x] **DSGN-03**: Static HTML/CSS/JS — no build step, no framework

### Footer

- [ ] **FOOT-01**: Footer with copyright and basic links

### Deployment

- [ ] **DEPL-01**: Site hosted on GitHub Pages
- [ ] **DEPL-02**: Custom domain agentlinux.org configured on GitHub Pages
- [ ] **DEPL-03**: HTTPS enabled via GitHub Pages
- [ ] **DEPL-04**: GitHub Actions workflow for automated deployment on push

## v2 Requirements

### Interactive Elements

- **INTX-01**: Animated terminal demos showing agent pain points
- **INTX-02**: Before/after comparisons (current setup vs AgentLinux)
- **INTX-03**: Terminal code snippets showing how AgentLinux solves each problem

### Social Proof

- **SOCL-01**: Subscriber count display ("Join X others")
- **SOCL-02**: Community links (Discord, GitHub)

### Content

- **CONT-01**: Roadmap preview showing planned distro milestones
- **CONT-02**: Comparison matrix table (checkmarks/X) alongside narrative

## Out of Scope

| Feature | Reason |
|---------|--------|
| Blog / CMS | Not needed for validation landing page |
| User accounts / login | No user-facing app functionality |
| Mobile app | Web-only landing page |
| Actual distro builds | Validation first, build later |
| E-commerce / payments | No monetization at this stage |
| Analytics dashboard | Can add later if needed |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HERO-01 | Phase 1 | Complete |
| HERO-02 | Phase 1 | Complete |
| HERO-03 | Phase 1 | Complete |
| PROB-01 | Phase 1 | Complete |
| FEAT-01 | Phase 1 | Complete |
| FEAT-02 | Phase 1 | Complete |
| COMP-01 | Phase 1 | Complete |
| MAIL-01 | Phase 1 | Pending |
| FAQ-01 | Phase 1 | Pending |
| DSGN-01 | Phase 1 | Complete |
| DSGN-02 | Phase 1 | Pending |
| DSGN-03 | Phase 1 | Complete |
| FOOT-01 | Phase 1 | Pending |
| DEPL-01 | Phase 2 | Pending |
| DEPL-02 | Phase 2 | Pending |
| DEPL-03 | Phase 2 | Pending |
| DEPL-04 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2026-03-09*
*Last updated: 2026-03-09 after roadmap revision*
