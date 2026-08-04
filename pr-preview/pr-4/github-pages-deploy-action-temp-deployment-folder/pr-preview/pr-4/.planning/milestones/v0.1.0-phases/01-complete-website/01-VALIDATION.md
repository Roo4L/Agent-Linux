---
phase: 1
slug: complete-website
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-09
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual browser testing (static HTML page — no automated test framework) |
| **Config file** | None |
| **Quick run command** | `open index.html` or `python3 -m http.server 8000` |
| **Full suite command** | Manual checklist verification (all 13 requirements) |
| **Estimated runtime** | ~60 seconds (visual walkthrough) |

---

## Sampling Rate

- **After every task commit:** Open `index.html` in browser, verify new section renders correctly
- **After every plan wave:** Full manual walkthrough of all sections on desktop + mobile viewport (DevTools)
- **Before `/gsd:verify-work`:** Complete checklist of all 13 requirements verified visually
- **Max feedback latency:** ~5 seconds (page load)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| TBD | 01 | 1 | HERO-01 | manual | Open index.html, verify name + tagline above fold | N/A | ⬜ pending |
| TBD | 01 | 1 | HERO-02 | manual | Open index.html, verify value proposition | N/A | ⬜ pending |
| TBD | 01 | 1 | HERO-03 | manual | Click CTA button, verify scroll to signup | N/A | ⬜ pending |
| TBD | 01 | 1 | DSGN-01 | manual | Visual inspection: dark theme, monospace, CLI style | N/A | ⬜ pending |
| TBD | 01 | 1 | DSGN-02 | manual | Resize browser / DevTools responsive mode | N/A | ⬜ pending |
| TBD | 01 | 1 | DSGN-03 | manual | Verify index.html opens in browser directly | N/A | ⬜ pending |
| TBD | 01 | 1 | PROB-01 | manual | Scroll to problem section, verify content | N/A | ⬜ pending |
| TBD | 01 | 1 | FEAT-01 | manual | Scroll to features, verify content | N/A | ⬜ pending |
| TBD | 01 | 1 | FEAT-02 | manual | Verify SVG icons render alongside features | N/A | ⬜ pending |
| TBD | 01 | 1 | COMP-01 | manual | Scroll to comparison, verify narrative format | N/A | ⬜ pending |
| TBD | 01 | 1 | MAIL-01 | manual | Submit test email, verify in Buttondown dashboard | N/A | ⬜ pending |
| TBD | 01 | 1 | FAQ-01 | manual | Scroll to FAQ, verify questions and answers | N/A | ⬜ pending |
| TBD | 01 | 1 | FOOT-01 | manual | Scroll to bottom, verify footer | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. This is a static HTML page — no test framework needed. Validation is visual/manual by nature.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Dark theme renders correctly | DSGN-01 | Visual aesthetic judgment | Open page, verify dark background, monospace fonts, no accent colors |
| Responsive layout works | DSGN-02 | Requires visual viewport testing | Use DevTools responsive mode at 320px, 768px, 1440px widths |
| CTA scrolls to signup | HERO-03 | Requires interaction testing | Click "Join the waitlist" button, verify smooth scroll to signup section |
| Email form submits | MAIL-01 | Requires Buttondown account | Enter test email, submit, verify in Buttondown dashboard |
| Sticky nav doesn't obscure content | All | UX issue only visible visually | Click each nav link, verify section heading is visible (not hidden under nav) |
| Content readability | DSGN-01 | Subjective quality check | Read all copy at normal distance — text should be comfortable to read |

---

## Validation Sign-Off

- [x] All tasks have manual verification steps mapped
- [x] Sampling continuity: visual check after every task commit
- [x] Wave 0 covers all MISSING references (none — manual only)
- [x] No watch-mode flags
- [x] Feedback latency < 5s (page load)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
