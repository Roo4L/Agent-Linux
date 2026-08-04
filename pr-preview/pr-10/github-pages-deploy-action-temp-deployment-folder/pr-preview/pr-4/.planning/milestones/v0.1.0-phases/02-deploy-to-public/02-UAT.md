---
status: complete
phase: 02-deploy-to-public
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md]
started: 2026-03-10T12:00:00Z
updated: 2026-03-10T12:10:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Site Live at Custom Domain
expected: Visit https://agentlinux.org in your browser. The landing page loads with the full content (hero section, features, etc.). The URL stays as agentlinux.org (not redirected elsewhere).
result: pass

### 2. HTTPS Certificate Valid
expected: The browser shows a lock icon (or no security warnings) when visiting https://agentlinux.org. No mixed content warnings. The certificate is valid and issued for agentlinux.org.
result: pass

### 3. Social Sharing Preview
expected: Paste https://agentlinux.org into a social sharing debugger (e.g., https://www.opengraph.xyz/) or a messaging app. A preview card should appear showing: title "Agent Linux", description about the AI-powered Linux environment, and the crab mascot OG image.
result: issue
reported: "OG mascot image doesn't show, but that's fine for now."
severity: minor

### 4. Favicon in Browser Tab
expected: When the site is loaded, the browser tab shows a small crab icon (SVG favicon). It should be visible and recognizable as the crab mascot.
result: pass

### 5. robots.txt Accessible
expected: Visit https://agentlinux.org/robots.txt in your browser. It should display a text file allowing all crawlers and referencing the sitemap URL.
result: pass

### 6. sitemap.xml Accessible
expected: Visit https://agentlinux.org/sitemap.xml in your browser. It should display valid XML listing https://agentlinux.org/ as a URL entry.
result: pass

### 7. Auto-Deploy on Push
expected: After pushing a commit to master, check the GitHub Actions tab in your repo. A "Deploy to GitHub Pages" workflow should run and complete successfully (green checkmark). The change should appear on the live site shortly after.
result: pass

## Summary

total: 7
passed: 6
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "Social sharing preview shows crab mascot OG image"
  status: failed
  reason: "User reported: OG mascot image doesn't show, but that's fine for now."
  severity: minor
  test: 3
  artifacts: []
  missing: []
