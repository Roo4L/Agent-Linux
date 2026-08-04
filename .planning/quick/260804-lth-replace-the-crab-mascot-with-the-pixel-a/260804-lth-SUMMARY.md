---
gsd_summary_version: 1.0
quick_id: 260804-lth
status: complete
date: 2026-08-04
tracker: AL-146
branch: feat/al-146-house-mascot
commits:
  - a008a50 feat(site): replace the crab mascot with the pixel-art house
  - e5bf555 feat(site): point the hero at the house mascot
  - 5f265b9 docs: retire the crab from the docs and the brand system
---

# Quick Task 260804-lth — Summary

## What shipped

The pixel-art house is now the sole AgentLinux mascot. The terracotta crab
"Clawd" is gone from every live asset and document.

| Surface | Before | After |
|---|---|---|
| Hero | `crab-mascot.svg` — house + terracotta crab | `house-mascot.svg` — house on a horizon line |
| Favicon | crab only | the same house motif |
| OG card | crab only | house at `scale(16)`, centred |
| Brand palette | monochrome + a `#D97757` mascot exception | strictly monochrome, no exception |

## Why it mattered

The crab was not incidental. The original v0.1.0 plan states the intent
outright — *"The crab represents Claude Code's mascot finding its 'home' in
AgentLinux"* — and the artwork carried it through: the character was named
"Clawd" and drawn in `#D97757`, Anthropic's brand terracotta. Because the
favicon and OG card were crab-only, that borrowed identity was the entire
public face of agentlinux.org.

The house replaces it with something the project already owns. It was in the
same artwork, it is already the deck's motif, and it states the product's own
argument: *"I need my own space, not a corner of someone else's."*

## How

House geometry is a pure translation of `deck/make-house.js` (verified
rect-by-rect: offset x+5, y+1), so the site and the deck stay visually
consistent without coupling their builds — the deck still reads only its own
committed `deck-house.png`.

- `site/assets/house-mascot.svg` — `git mv` from `crab-mascot.svg`, rewritten
  as the house alone in a 24×17 viewBox; the `.o`/`.d`/`.bl`/`.pu` crab colour
  classes are gone.
- `site/assets/favicon.svg` — same motif on a 16-unit grid at 32×32.
- `site/assets/og-image.svg` + `og-image.png` — the crab group replaced by the
  house; the PNG regenerated at 1200×630 via headless Chromium.
- `site/index.html` — new `src`/`alt`; `.hero-mascot` resized to the 24:17
  aspect in both the base rule and the ≤640px query (360×255 / 200×142).
- `README.md`, `docs/decisions/013-license-mit.md` — trademark reservation now
  names the house mascot.
- `deck/brand-style.md` — crab character deleted from the motif section; the
  `#D97757` "signature warm" row removed, making the palette strictly
  monochrome.
- `deck/README.md`, `AGENTS.md` — provenance repointed at `house-mascot.svg`.

## Verification

- `grep -rniI "crab\|clawd\|d97757"` across the repo, excluding `.planning/`:
  no matches. Historical `.planning/` records are deliberately untouched —
  they document what was true at the time.
- All three SVGs parse; every declared CSS class is used; no dead classes left.
- Hero rendered at 1280×900 and 390×780 — the house sits above the fold at
  both breakpoints and is not stretched.
- OG card rendered and inspected at 1200×630.
- Every referenced site asset resolves except two pre-existing gaps (below).
- `pre-commit` hooks passed on all three commits.

## Review

Ran the `review` skill's matched rubrics — `technical-writer`, `fact-checker`,
`ai-deslop`, `external-audience-auditor` (the dispatch table matches
`README.md`, `docs/decisions/`, and `AGENTS.md`; `site/`/`deck/` paths are not
in it). **Limited pass:** the rubrics were applied by the main agent rather
than dispatched as subagents. No actionable findings; the geometry and
link-target claims above were fact-checked directly.

## Deferred

Both pre-existing on `master` and unrelated to the mascot swap — recorded on
AL-146 for follow-up:

1. `site/index.html:16` links `/favicon.ico`, which has never existed in
   `site/`. Browsers fall back to the SVG favicon, so the tab icon is correct,
   but the request 404s.
2. `site/index.html:17` links `/assets/apple-touch-icon.png`, which also does
   not exist. iOS home-screen bookmarks get no icon.

Fixing both means rasterising the house at 32×32 (ICO) and 180×180 (PNG).

## Operational note

`og-image.png` kept its URL, so Facebook, LinkedIn, Slack, and X will keep
serving the cached **crab** card until their scrapers refresh. Re-scrape via
each platform's sharing debugger after the site deploys.
