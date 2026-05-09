# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v0.1.0 — AgentLinux Landing Page

**Shipped:** 2026-03-10
**Phases:** 2 | **Plans:** 5

### What Was Built
- Complete landing page with terminal-aesthetic dark theme, crab mascot, and sticky navigation
- Content sections: problem explainer, 8-feature showcase with SVG icons, narrative comparison
- Email signup (Buttondown), FAQ accordion, responsive design, footer
- SEO assets: OG/Twitter meta tags, favicon, GA4, robots.txt, sitemap.xml
- GitHub Actions auto-deploy to GitHub Pages with custom domain agentlinux.org

### What Worked
- Two-phase approach (build locally → deploy) kept things simple and sequential
- Inline CSS in single HTML file made iteration fast with no build tooling
- Static site constraint avoided framework complexity — shipped in 2 days
- UAT testing caught the OG image SVG issue early

### What Was Inefficient
- Requirements checkboxes fell out of sync with actual completion — traceability table also lagged
- OG image was created as SVG which many social platforms don't support — should have used PNG from the start

### Patterns Established
- Inline Lucide SVG icons for consistent visual language
- CSS custom properties for dark theme theming
- GitHub Actions deploy workflow for static sites on GitHub Pages
- Buttondown form integration pattern for email collection

### Key Lessons
1. Keep requirements checkboxes updated during execution, not just at milestone end
2. Use PNG for OG social sharing images — SVG support is inconsistent across platforms
3. Single-file static sites are surprisingly effective for validation landing pages

### Cost Observations
- Model mix: Primarily opus for planning/execution, sonnet for verification
- Sessions: ~4 sessions across 2 days
- Notable: Simple static site kept plan/execution ratio efficient — minimal rework

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v0.1.0 | 2 | 5 | Initial project — established GSD workflow |

### Top Lessons (Verified Across Milestones)

1. (Awaiting second milestone for cross-validation)
