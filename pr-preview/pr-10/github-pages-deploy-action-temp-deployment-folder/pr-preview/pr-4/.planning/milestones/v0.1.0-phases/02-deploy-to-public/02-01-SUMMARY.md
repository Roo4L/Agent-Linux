---
phase: 02-deploy-to-public
plan: 01
subsystem: seo
tags: [og-meta, twitter-card, favicon, ga4, robots-txt, sitemap, seo]

# Dependency graph
requires:
  - phase: 01-complete-website
    provides: index.html landing page with head section
provides:
  - OG and Twitter meta tags for social sharing previews
  - SVG favicon derived from crab mascot
  - OG social sharing image (1200x630)
  - robots.txt and sitemap.xml for search engine indexing
  - GA4 analytics placeholder ready for measurement ID
affects: [02-deploy-to-public]

# Tech tracking
tech-stack:
  added: [google-analytics-4]
  patterns: [absolute-urls-to-agentlinux-org]

key-files:
  created:
    - assets/favicon.svg
    - assets/og-image.svg
    - robots.txt
    - sitemap.xml
  modified:
    - index.html

key-decisions:
  - "SVG format for OG image -- works for direct links, user can convert to PNG for broader platform support later"
  - "Forward-compatible favicon.ico and apple-touch-icon.png link tags -- files don't exist yet but links are ready"
  - "GA4 with G-XXXXXXX placeholder -- user replaces after creating GA4 property"

patterns-established:
  - "Absolute URLs: all meta tag URLs use https://agentlinux.org prefix"

requirements-completed: [DEPL-01]

# Metrics
duration: 1min
completed: 2026-03-09
---

# Phase 2 Plan 1: Pre-Launch SEO and Social Summary

**OG/Twitter meta tags, crab favicon SVG, GA4 analytics placeholder, robots.txt, and sitemap.xml for agentlinux.org launch readiness**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-09T15:56:34Z
- **Completed:** 2026-03-09T15:57:35Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Added complete Open Graph (7 tags) and Twitter Card (4 tags) meta tags with absolute agentlinux.org URLs
- Created simplified pixel-art crab favicon SVG optimized for 32x32 display and 1200x630 OG social image
- Added GA4 gtag.js snippet with clear G-XXXXXXX placeholder and setup comment
- Created robots.txt (allows all crawlers) and sitemap.xml (lists agentlinux.org)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create favicon SVG, OG image SVG, robots.txt, and sitemap.xml** - `0e35976` (feat)
2. **Task 2: Add meta tags, favicon links, and GA4 snippet to index.html** - `fbc495b` (feat)

## Files Created/Modified
- `assets/favicon.svg` - Simplified crab mascot pixel art favicon (32x32 viewBox)
- `assets/og-image.svg` - 1200x630 social sharing image with crab, title, subtitle on dark background
- `robots.txt` - Allows all crawlers, references sitemap at agentlinux.org
- `sitemap.xml` - Lists agentlinux.org homepage for search engine indexing
- `index.html` - Added GA4 snippet, favicon links, OG meta tags, Twitter Card meta tags to head

## Decisions Made
- Used SVG for OG image -- works for direct links and many modern platforms; user can convert to PNG later for broader compatibility
- Added forward-compatible link tags for favicon.ico and apple-touch-icon.png that don't exist yet
- GA4 placeholder approach with G-XXXXXXX -- user configures after creating their GA4 property

## Deviations from Plan

None - plan executed exactly as written.

## User Setup Required

**Google Analytics 4 requires manual configuration:**
1. Create GA4 property at https://analytics.google.com -> Admin -> Create Property
2. Get Measurement ID (format: G-XXXXXXX)
3. Replace `G-XXXXXXX` placeholder in `index.html` (appears twice) with actual Measurement ID

## Next Phase Readiness
- All pre-launch SEO and social sharing assets are in place
- Ready for deployment plan (02-02) to push site live
- GA4 will begin tracking once user replaces placeholder with real Measurement ID

---
*Phase: 02-deploy-to-public*
*Completed: 2026-03-09*
