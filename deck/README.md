# AgentLinux deck — design code + generator

The reusable **design code** for AgentLinux presentations, plus the generator that renders it
to slides. Strict-monochrome, terminal-styled: JetBrains Mono / Consolas, a near-black canvas,
one white accent, and the pixel-art house from [`../assets/crab-mascot.svg`](../assets/crab-mascot.svg).

- **[`brand-style.md`](brand-style.md)** — the reusable brand DNA in
  [power-design](https://github.com/ItsssssJack/power-design) format (colors, type, spacing,
  voice, motif, quick-reference CSS). **This is the design code**: feed it to power-design to
  generate a new deck or site in the exact same look.
- The generator renders that design to a **native, fully-editable PowerPoint** (pptxgenjs) —
  its design tokens mirror `brand-style.md`.

## Files

| File | What it is |
|---|---|
| `brand-style.md` | **The design code** — reusable AgentLinux brand DNA (power-design format). |
| `build_pptx.js` | Renders the deck with [`pptxgenjs`](https://gitbrent.github.io/PptxGenJS/). Design tokens live here, matching `brand-style.md`. |
| `make-house.js` | Rasterizes the pixel-art house → `deck-house.png` (Playwright/Chromium). |
| `make-viz.js` | Renders the Part II concept graphics (package-interaction graph, bug-discovery decay curve, dual-threshold stop rule) → `viz-A/B/C.png` (Playwright/Chromium). |
| `deck-house.png`, `viz-A/B/C.png` | Generated image assets, committed so the deck builds **without** a browser. |

The built `.pptx` is intentionally **not** committed — regenerate it with `node build_pptx.js`.

## Build

Requires Node 18+.

```bash
npm install pptxgenjs                # required to build the deck
node build_pptx.js                   # → AgentLinux-deck.pptx

# Regenerating the images is optional — they're committed. If you change them:
npm install playwright
npx playwright install chromium
node make-house.js                   # → deck-house.png
node make-viz.js                     # → viz-A.png, viz-B.png, viz-C.png
```

## Design system (quick reference)

See `brand-style.md` for the full spec. In short:

- **Palette** — background `#0A0A0A`, body `#E0E0E0`, secondary `#A8A8A8`, panels `#121212`,
  borders `#2A2A2A`; the single accent per slide is pure white `#FFFFFF`.
- **Type** — Consolas / JetBrains Mono (monospace), one modular scale (base 24, ratio 1.25),
  presenter-mode sparseness (one idea/slide).
- **Motif** — the pixel-art house (grayscale, from `../assets/crab-mascot.svg`) recurs on the
  cover, the solution slide, the close, and as the footer mark.
- **Restraint** — no accent stripes, under-title rules, gradients, or shadows; structure comes
  from tint panels and whitespace. `footer()` auto-numbers slides — set `TOTAL` when adding/removing.

## Credit

Slide design principles: [power-design](https://github.com/ItsssssJack/power-design) by Jack Roberts.
