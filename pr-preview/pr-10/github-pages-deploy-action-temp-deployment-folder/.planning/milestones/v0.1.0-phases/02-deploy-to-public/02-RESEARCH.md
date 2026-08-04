# Phase 2: Deploy to Public - Research

**Researched:** 2026-03-09
**Domain:** GitHub Pages deployment, DNS, pre-launch SEO/analytics
**Confidence:** HIGH

## Summary

Phase 2 deploys the existing static HTML site to GitHub Pages at agentlinux.org with HTTPS and auto-deploy via GitHub Actions. The site is a single `index.html` with one SVG asset -- no build step required. The deployment uses the official `actions/upload-pages-artifact@v4` and `actions/deploy-pages@v4` actions. Pre-launch polish adds OG meta tags, favicon, GA4 analytics, robots.txt, and sitemap.xml.

This is a well-trodden path with stable tooling. GitHub Pages deployment via Actions is the standard approach (classic branch-based deployment is being deprecated). The main manual step is DNS configuration on Hostinger, which the user will handle given the A record IP addresses.

**Primary recommendation:** Use the official GitHub Actions Pages workflow (upload-pages-artifact v4 + deploy-pages v4) with `path: '.'` to deploy the repo root directly. No build step, no gh-pages branch.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Private repo `Roo4L/Agent-Linux` on GitHub Pro -- supports Pages on private repos
- Deploy from main branch root -- no separate gh-pages branch
- No repo restructuring needed -- index.html already at root
- Apex domain: agentlinux.org (no www subdomain)
- Domain already purchased on Hostinger -- DNS settings accessible
- User handles DNS configuration themselves -- plan provides required record values (A records for GitHub Pages IPs + CNAME)
- HTTPS via GitHub Pages automatic certificate
- Deploy raw static files as-is -- no minification, no build step (consistent with DSGN-03)
- GitHub Actions using official `actions/deploy-pages` workflow
- Trigger: push to main branch only -- no PR previews
- CNAME file for custom domain handled by the workflow
- Add og:title, og:description, og:image, Twitter card meta tags
- Generate a 1200x630 OG image from site design (dark theme + "Linux, for agents" tagline + crab mascot)
- Generate favicon from existing crab-mascot.svg
- Standard favicon sizes for browser tabs and bookmarks
- robots.txt allowing all crawlers
- Simple sitemap.xml with agentlinux.org
- Google Analytics 4 (GA4) integration
- GA4 property to be created as a prerequisite -- plan includes setup instructions
- Add gtag.js snippet to index.html with placeholder measurement ID (G-XXXXXXX) for user to replace

### Claude's Discretion
- Exact GitHub Actions workflow YAML structure
- CNAME file placement and content
- OG image design details (layout, sizing of elements)
- Favicon generation approach (SVG favicon vs PNG conversion)
- Exact robots.txt and sitemap.xml content
- GA4 snippet placement within the HTML

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DEPL-01 | Site hosted on GitHub Pages | GitHub Actions workflow with upload-pages-artifact@v4 + deploy-pages@v4; repo settings set source to "GitHub Actions" |
| DEPL-02 | Custom domain agentlinux.org configured on GitHub Pages | CNAME file at repo root containing `agentlinux.org`; DNS A records pointing to GitHub Pages IPs; custom domain setting in repo |
| DEPL-03 | HTTPS enabled via GitHub Pages | Automatic after DNS propagation and custom domain verification; "Enforce HTTPS" checkbox in repo settings |
| DEPL-04 | GitHub Actions workflow for automated deployment on push | Workflow triggered on push to main; uses official actions; no build step needed |

</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `actions/upload-pages-artifact` | v4 | Package static files into deployable artifact | Official GitHub action for Pages |
| `actions/deploy-pages` | v4 | Deploy artifact to GitHub Pages | Official GitHub action for Pages |
| `actions/configure-pages` | v5 | Configure Pages settings during workflow | Official; handles CNAME and base URL |
| `actions/checkout` | v4 | Check out repo code | Standard checkout action |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `gh` CLI | Enable Pages via API, set custom domain | One-time repo setup (can also be done in GitHub UI) |
| GA4 gtag.js | Analytics tracking | Loaded from Google CDN, no npm install |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| actions/deploy-pages | peaceiris/actions-gh-pages | Third-party; pushes to gh-pages branch (not wanted) |
| SVG favicon | ICO-only favicon | SVG has broad modern support and works with existing asset |

**Installation:** No npm packages needed. This phase involves only configuration files and HTML modifications.

## Architecture Patterns

### Files to Create/Modify
```
.
├── .github/
│   └── workflows/
│       └── deploy.yml        # GitHub Actions workflow
├── CNAME                     # Custom domain file (agentlinux.org)
├── robots.txt                # SEO: allow all crawlers
├── sitemap.xml               # SEO: site URL listing
├── assets/
│   ├── crab-mascot.svg       # (existing)
│   ├── favicon.svg           # Favicon (derived from crab mascot)
│   ├── favicon.ico           # 32x32 ICO fallback
│   ├── apple-touch-icon.png  # 180x180 for iOS
│   └── og-image.png          # 1200x630 OG social image
└── index.html                # (modify: add meta tags, favicon links, GA4 snippet)
```

### Pattern 1: GitHub Actions Static Deploy Workflow

**What:** A two-job workflow (build + deploy) that uploads the repo root as a Pages artifact and deploys it.
**When to use:** Any static site without a build step.

```yaml
# Source: https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
name: Deploy to GitHub Pages

on:
  push:
    branches: ["main"]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Pages
        uses: actions/configure-pages@v5
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v4
        with:
          path: '.'
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

**Key details:**
- `path: '.'` uploads the entire repo root (no build output directory)
- Single job is sufficient since there is no build step
- `workflow_dispatch` allows manual re-deploys from GitHub UI
- `concurrency` prevents overlapping deployments
- `cancel-in-progress: false` ensures the latest deploy completes even if a newer push arrives

### Pattern 2: CNAME File for Custom Domain

**What:** A file named `CNAME` at repo root containing the custom domain.
**Content:** Single line: `agentlinux.org`

This file tells GitHub Pages which custom domain to use. The `actions/configure-pages` action respects this file. Without it, GitHub Pages serves at the default `*.github.io` URL.

### Pattern 3: DNS Configuration for Apex Domain

**What:** A records pointing the apex domain to GitHub Pages servers.

| Record Type | Host | Value |
|-------------|------|-------|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |

Optional AAAA records for IPv6:
| Record Type | Host | Value |
|-------------|------|-------|
| AAAA | @ | 2606:50c0:8000::153 |
| AAAA | @ | 2606:50c0:8001::153 |
| AAAA | @ | 2606:50c0:8002::153 |
| AAAA | @ | 2606:50c0:8003::153 |

### Pattern 4: Minimal Favicon Set (3 files)

**What:** Modern favicon approach requiring only 3 files.

```html
<!-- Source: https://evilmartians.com/chronicles/how-to-favicon-in-2021-six-files-that-fit-most-needs -->
<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
```

Files needed:
1. `favicon.ico` (32x32) -- for legacy browsers
2. `assets/favicon.svg` -- SVG version of crab mascot for modern browsers
3. `assets/apple-touch-icon.png` (180x180) -- for iOS

The SVG favicon can be a simplified version of the existing `crab-mascot.svg`. For the ICO and PNG, the SVG needs to be converted/rasterized.

### Pattern 5: OG Meta Tags

**What:** OpenGraph and Twitter Card meta tags for social sharing.

```html
<!-- Open Graph -->
<meta property="og:type" content="website">
<meta property="og:url" content="https://agentlinux.org">
<meta property="og:title" content="AgentLinux -- Linux, for agents">
<meta property="og:description" content="A purpose-built Linux distribution for AI coding agents. Full OS isolation, pre-configured toolchains, agents in the repos.">
<meta property="og:image" content="https://agentlinux.org/assets/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="AgentLinux -- Linux, for agents">
<meta name="twitter:description" content="A purpose-built Linux distribution for AI coding agents.">
<meta name="twitter:image" content="https://agentlinux.org/assets/og-image.png">
```

**Placement:** Inside `<head>`, after the `<title>` tag.

### Pattern 6: GA4 gtag.js Snippet

**What:** Google Analytics 4 tracking code.

```html
<!-- Google tag (gtag.js) -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXXX"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'G-XXXXXXX');
</script>
```

**Placement:** Immediately after the opening `<head>` tag (before other elements) for earliest loading. The `async` attribute prevents render blocking.

**User action required:** Replace `G-XXXXXXX` with actual GA4 Measurement ID after creating a GA4 property at https://analytics.google.com.

### Anti-Patterns to Avoid
- **Pushing to gh-pages branch:** The modern approach uses Actions artifacts, not a deploy branch. Avoids repo pollution and branch management.
- **Using jekyll-build-pages for non-Jekyll sites:** This action runs Jekyll processing. For raw static files, skip it and upload directly.
- **Hardcoding absolute URLs in CNAME or workflow:** The CNAME file should contain just the domain name (no protocol, no trailing slash).
- **Committing .nojekyll file unnecessarily:** When using the Actions workflow (not classic deployment), Jekyll processing is not applied by default.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pages deployment | Custom rsync/scp scripts | actions/deploy-pages@v4 | Handles artifact deployment, environment URLs, status checks |
| HTTPS certificates | Manual cert management | GitHub Pages auto-SSL | Free, automatic renewal, zero config after DNS |
| Favicon generation | Manual pixel editing | Convert from SVG (ImageMagick or online tool) | SVG source is already available |
| OG image | Complex automated generation | Static PNG file created once | Site content is static; no need for dynamic OG images |

## Common Pitfalls

### Pitfall 1: DNS Propagation Delay
**What goes wrong:** Site shows 404 or certificate errors immediately after DNS changes.
**Why it happens:** DNS propagation takes 15 minutes to 48 hours. GitHub also needs time to provision the SSL certificate.
**How to avoid:** Set DNS records first, then configure custom domain in GitHub. Wait for DNS verification (green checkmark in repo settings). HTTPS certificate provisioning can take up to 24 hours.
**Warning signs:** "DNS check unsuccessful" message in repo Pages settings.

### Pitfall 2: CNAME File Gets Deleted
**What goes wrong:** Custom domain stops working after a deployment.
**Why it happens:** If the workflow uploads an artifact that doesn't include the CNAME file, GitHub removes the custom domain setting.
**How to avoid:** Always include the CNAME file in the repo root so it's included in `path: '.'` upload. The `actions/configure-pages` action also helps maintain the CNAME.
**Warning signs:** Site reverts to `*.github.io` URL after deploy.

### Pitfall 3: Pages Not Enabled in Repo Settings
**What goes wrong:** Workflow runs but deploy step fails with "Page not found" or permissions error.
**Why it happens:** GitHub Pages must be enabled in repo Settings > Pages before the workflow can deploy.
**How to avoid:** Enable Pages in repo settings and set source to "GitHub Actions" before first workflow run. Can be done via: `gh api -X PUT "/repos/OWNER/REPO/pages" -f build_type=workflow`
**Warning signs:** Deploy action fails with 404 or "Not Found" error.

### Pitfall 4: Private Repo Pages Visibility
**What goes wrong:** Pages site not accessible publicly.
**Why it happens:** On GitHub Pro, private repo Pages are publicly accessible by default. But the setting "GitHub Pages site visibility" must be set to "Public."
**How to avoid:** Verify in Settings > Pages that visibility is set to Public.
**Warning signs:** 404 when accessing the site from an unauthenticated browser.

### Pitfall 5: OG Image Not Showing in Social Previews
**What goes wrong:** Shared links show no image or broken image.
**Why it happens:** OG image URL must be an absolute URL (with https://), and the image must be publicly accessible. Social platforms cache aggressively.
**How to avoid:** Use full absolute URL in og:image meta tag. Test with Facebook Sharing Debugger and Twitter Card Validator after deployment.
**Warning signs:** Meta tags use relative paths; image file not in deployed artifact.

### Pitfall 6: GA4 Placeholder Not Replaced
**What goes wrong:** Analytics not recording any data.
**Why it happens:** User forgets to replace `G-XXXXXXX` placeholder with actual Measurement ID.
**How to avoid:** Add a clear HTML comment near the snippet and document the replacement step prominently in the plan.
**Warning signs:** No data in GA4 dashboard after deployment.

## Code Examples

### robots.txt
```
# Source: standard robots.txt for public sites
User-agent: *
Allow: /

Sitemap: https://agentlinux.org/sitemap.xml
```

### sitemap.xml
```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemascope.org/schemas/sitemap/0.9">
  <url>
    <loc>https://agentlinux.org/</loc>
    <lastmod>2026-03-09</lastmod>
    <priority>1.0</priority>
  </url>
</urlset>
```

Note: The sitemap namespace URL is `http://www.sitemaps.org/schemas/sitemap/0.9`.

### CNAME
```
agentlinux.org
```

### Enabling Pages via gh CLI
```bash
# Enable GitHub Pages with Actions as source
gh api -X PUT "/repos/Roo4L/Agent-Linux/pages" -f build_type=workflow

# Set custom domain
gh api -X PUT "/repos/Roo4L/Agent-Linux/pages" -f cname=agentlinux.org
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Deploy from gh-pages branch | Deploy via GitHub Actions artifact | 2022-2023 | No deploy branch needed; cleaner repo |
| 20+ favicon files | 3 files (ICO + SVG + apple-touch-icon) | 2023-2024 | Massively simplified favicon management |
| Multiple favicon link tags | 3 link tags | 2023-2024 | Less HTML boilerplate |
| Universal Analytics (UA) | Google Analytics 4 (GA4) | July 2023 (UA sunset) | GA4 is the only option now |
| Classic Pages deployment | Actions-based deployment | 2025-2026 (classic being deprecated) | Must use Actions workflow going forward |

## Open Questions

1. **OG Image Creation Method**
   - What we know: Need a 1200x630 PNG with dark theme, "Linux, for agents" tagline, and crab mascot
   - What's unclear: Whether to create this programmatically (e.g., HTML-to-image) or as a manually designed static asset
   - Recommendation: Create as a static PNG file. The site content is static and won't change frequently. A one-time design is simpler and more reliable than automated generation. Can be created by rendering an HTML mockup or using a simple design tool.

2. **Favicon ICO/PNG Generation from SVG**
   - What we know: Source SVG exists at `assets/crab-mascot.svg`; need 32x32 ICO and 180x180 PNG
   - What's unclear: Whether the crab mascot SVG scales well to 32x32 (it's a detailed illustration)
   - Recommendation: Create a simplified version of the crab for small sizes, or use the full SVG and let the browser scale. For the ICO, use ImageMagick `convert` or an online tool. The SVG favicon handles modern browsers; ICO is fallback only.

3. **GitHub Pages Enablement**
   - What we know: Can be done via Settings UI or `gh api` CLI
   - What's unclear: Whether the user has already enabled Pages in the repo
   - Recommendation: Include an explicit "enable Pages" step as a prerequisite, with both UI and CLI instructions.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual validation (deployment verification) |
| Config file | none |
| Quick run command | `curl -sI https://agentlinux.org` |
| Full suite command | Manual checklist (see below) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEPL-01 | Site hosted on GitHub Pages | smoke | `curl -sI https://agentlinux.org \| grep -i "server: github"` | N/A - manual |
| DEPL-02 | Custom domain resolves | smoke | `dig agentlinux.org +short` (should return GitHub Pages IPs) | N/A - manual |
| DEPL-03 | HTTPS enabled | smoke | `curl -sI https://agentlinux.org \| grep "HTTP/2 200"` | N/A - manual |
| DEPL-04 | Auto-deploy on push | integration | Push a trivial change, verify GitHub Actions workflow completes | N/A - manual |

### Sampling Rate
- **Per task commit:** Verify workflow YAML is valid with `act --dryrun` (if available) or syntax check
- **Per wave merge:** Full deployment verification after DNS propagation
- **Phase gate:** All 4 DEPL requirements verified via curl/dig commands

### Wave 0 Gaps
- No test infrastructure needed -- this phase is infrastructure/deployment configuration
- Validation is done via external HTTP checks against the live site after deployment

## Sources

### Primary (HIGH confidence)
- [GitHub Docs: Using custom workflows with GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) - workflow structure, permissions
- [GitHub Docs: Managing a custom domain](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site) - DNS A records, CNAME setup
- [actions/upload-pages-artifact README](https://github.com/actions/upload-pages-artifact) - v4 API, path parameter
- [actions/deploy-pages README](https://github.com/actions/deploy-pages) - v4 deployment action
- [Google Analytics gtag.js docs](https://support.google.com/analytics/answer/14171598) - GA4 snippet format

### Secondary (MEDIUM confidence)
- [Evil Martians: How to Favicon in 2026](https://evilmartians.com/chronicles/how-to-favicon-in-2021-six-files-that-fit-most-needs) - 3-file favicon strategy
- [Can I Use: SVG favicons](https://caniuse.com/link-icon-svg) - browser support data

### Tertiary (LOW confidence)
- None -- all findings verified with official sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - official GitHub Actions, well-documented
- Architecture: HIGH - straightforward static file deployment, no build step
- Pitfalls: HIGH - common issues well-documented in GitHub community
- Pre-launch items (OG/favicon/GA4): HIGH - standard web practices with official documentation

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable infrastructure, unlikely to change)
