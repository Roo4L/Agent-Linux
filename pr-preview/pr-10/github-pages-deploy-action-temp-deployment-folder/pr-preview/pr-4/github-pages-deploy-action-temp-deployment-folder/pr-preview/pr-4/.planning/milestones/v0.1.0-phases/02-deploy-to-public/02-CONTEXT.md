# Phase 2: Deploy to Public - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship the finished AgentLinux landing page to GitHub Pages at agentlinux.org with HTTPS and auto-deploy on push. Includes pre-launch polish (meta tags, favicon, analytics) but no content changes to the site itself.

</domain>

<decisions>
## Implementation Decisions

### Repository setup
- Private repo `Roo4L/Agent-Linux` on GitHub Pro — supports Pages on private repos
- Deploy from main branch root — no separate gh-pages branch
- No repo restructuring needed — index.html already at root

### DNS & domain
- Apex domain: agentlinux.org (no www subdomain)
- Domain already purchased on Hostinger — DNS settings accessible
- User handles DNS configuration themselves — plan provides required record values (A records for GitHub Pages IPs + CNAME)
- HTTPS via GitHub Pages automatic certificate

### Deploy pipeline
- Deploy raw static files as-is — no minification, no build step (consistent with DSGN-03)
- GitHub Actions using official `actions/deploy-pages` workflow
- Trigger: push to main branch only — no PR previews
- CNAME file for custom domain handled by the workflow

### Pre-launch: OG & social meta tags
- Add og:title, og:description, og:image, Twitter card meta tags
- Generate a 1200x630 OG image from site design (dark theme + "Linux, for agents" tagline + crab mascot)

### Pre-launch: Favicon
- Generate favicon from existing crab-mascot.svg
- Standard favicon sizes for browser tabs and bookmarks

### Pre-launch: SEO basics
- robots.txt allowing all crawlers
- Simple sitemap.xml with agentlinux.org

### Pre-launch: Analytics
- Google Analytics 4 (GA4) integration
- GA4 property to be created as a prerequisite — plan includes setup instructions
- Add gtag.js snippet to index.html with placeholder measurement ID (G-XXXXXXX) for user to replace

### Claude's Discretion
- Exact GitHub Actions workflow YAML structure
- CNAME file placement and content
- OG image design details (layout, sizing of elements)
- Favicon generation approach (SVG favicon vs PNG conversion)
- Exact robots.txt and sitemap.xml content
- GA4 snippet placement within the HTML

</decisions>

<specifics>
## Specific Ideas

- Landing page goal is to share with friends and test internet demand — social sharing meta tags are essential for this use case
- Crab mascot is the brand identity — reuse it for both OG image and favicon for consistency
- User is comfortable with DNS but doesn't want hand-holding — just provide the record values

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `index.html`: Single-file site with inline CSS/JS — all meta tags and scripts go here
- `assets/crab-mascot.svg`: Existing SVG mascot for favicon and OG image generation

### Established Patterns
- Inline everything approach (DSGN-03) — CSS is in `<style>`, JS in `<script>`
- JetBrains Mono from Google Fonts — external dependency already present
- Dark theme color system via CSS custom properties (--bg-primary: #0a0a0a, etc.)

### Integration Points
- GitHub Pages deployment target — needs CNAME file at repo root
- Buttondown API already integrated in index.html — no conflicts with deployment
- Hostinger DNS needs to point to GitHub Pages IPs

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-deploy-to-public*
*Context gathered: 2026-03-09*
