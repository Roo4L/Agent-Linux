---
gsd_plan_version: 1.0
quick_id: 260804-lth
title: Replace the crab mascot with the pixel-art house
date: 2026-08-04
tracker: AL-146
status: planned
must_haves:
  truths:
    - No committed asset or doc contains crab pixel art, the name "Clawd", or the terracotta #D97757.
    - The pixel-art house is the sole mascot across hero, favicon, and OG card.
    - The deck build is untouched — it reads its own committed deck-house.png.
  artifacts:
    - site/assets/house-mascot.svg
    - site/assets/favicon.svg
    - site/assets/og-image.svg
    - site/assets/og-image.png
  key_links:
    - site/index.html
    - README.md
    - docs/decisions/013-license-mit.md
    - deck/brand-style.md
    - deck/README.md
---

# Quick Task 260804-lth: Replace the crab mascot with the pixel-art house

## Problem

`site/assets/crab-mascot.svg` pairs a pixel-art house with a small terracotta
crab named "Clawd", drawn in `#D97757`. That colour is Anthropic's brand
terracotta and "Clawd" is a homophone of "Claude" — together they read as
trading on Claude Code's identity rather than as an independent mark. The
favicon and the OG card are crab-only, so the crab is currently the whole
public face of agentlinux.org.

The house is already in the same artwork, is already the deck's house motif,
and carries the product's own story: *"I need my own space, not a corner of
someone else's."* Promote it to sole mascot.

## Approach

Keep the pixel grid and the monochrome palette that already exist; delete the
crab and re-centre the house. The house geometry is shared with
`deck/make-house.js`, so the site and deck stay visually consistent without
coupling their build steps.

## Tasks

### Task 1 — Redraw the three mascot assets as house-only

**Files:** `site/assets/house-mascot.svg` (new, replaces `crab-mascot.svg`),
`site/assets/favicon.svg`, `site/assets/og-image.svg`, `site/assets/og-image.png`

**Action:**
- `git mv site/assets/crab-mascot.svg site/assets/house-mascot.svg`, then rewrite
  it as the house alone on a horizon line — viewBox `0 0 24 17`, house centred at
  x-offset 5, ground row spanning full width. Drop the `.o`/`.d`/`.bl`/`.pu` crab
  colour classes.
- Rewrite `favicon.svg` as the same house on a 16-unit grid rendered at 32×32.
- Replace the crab group in `og-image.svg` with the house at `scale(16)`,
  horizontally centred on x=600.
- Regenerate `og-image.png` (1200×630) from the updated SVG via headless Chromium.

**Verify:** `grep -ril "crab\|clawd\|d97757" site/` returns nothing; each SVG
parses; `og-image.png` is 1200×630 and its pixels changed.

**Done:** No crab remains in any site asset and the OG raster matches its source.

### Task 2 — Point the site at the new mascot

**Files:** `site/index.html`

**Action:** Update the hero `<img>` `src` to `assets/house-mascot.svg` and its
`alt` to describe the house. Adjust `.hero-mascot` width/height (both the base
rule and the ≤640px media query) to the new 24:17 aspect so the pixel art is not
stretched.

**Verify:** `grep -n "hero-mascot\|house-mascot" site/index.html` shows the new
path and matching dimensions; no reference to `crab-mascot.svg` survives.

**Done:** The hero renders the house at its native aspect ratio.

### Task 3 — Retire the crab from docs and the brand system

**Files:** `README.md`, `docs/decisions/013-license-mit.md`, `deck/brand-style.md`,
`deck/README.md`

**Action:** Update the trademark reservation in `README.md` and the carve-out in
ADR-013 to name the house mascot. In `deck/brand-style.md`, delete the crab
character from the mascot section and remove the `#D97757` "signature warm" row —
the palette becomes strictly monochrome. Repoint `deck/README.md`'s provenance
references from `crab-mascot.svg` to `house-mascot.svg`.

**Verify:** `grep -ril "crab\|clawd\|d97757"` across the repo returns only
historical `.planning/` records.

**Done:** Every doc describes the house as the mascot; no terracotta remains in
the brand system.

## Out of scope

- The deck's own `deck-house.png` and `build_pptx.js` — the deck reads its
  committed raster and does not consume the site SVG.
- Any change to the site's `--accent` colour, which is already `#ffffff`.
