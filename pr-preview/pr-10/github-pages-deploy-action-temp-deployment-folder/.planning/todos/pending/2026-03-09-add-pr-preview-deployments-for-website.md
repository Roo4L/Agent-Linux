---
created: 2026-03-09T15:29:25.519Z
title: Add PR preview deployments for website
area: tooling
files:
  - .github/workflows/ (to be created in Phase 2)
---

## Problem

Currently the deploy pipeline (Phase 2) only triggers on pushes to main. There's no way to preview website changes from pull requests before merging. This would be useful for reviewing design or content changes in a live environment before they go to production.

## Solution

Add a separate GitHub Actions workflow (or extend the deploy workflow) that generates preview deployments for pull requests. Options include:
- GitHub Pages preview environments
- Third-party services like Netlify Deploy Previews or Vercel Preview
- Custom workflow that deploys to a temporary URL

Evaluate after Phase 2 deploy pipeline is running and stable.
