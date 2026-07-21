---
brand: AgentLinux
slug: agentlinux
website: https://agentlinux.org
extracted_via: manual — from agentlinux.org + the Agent-Linux repo (assets/, docs/VISION.md)
---

# AgentLinux — Brand Style

## Visual Theme & Atmosphere

Terminal-native and unapologetically technical. A near-black canvas, monospace type
everywhere, and a single white accent — it reads like a well-lit shell. Flat and quiet:
no gradients, no drop shadows, no decorative color, no accent stripes. Hierarchy comes from
size, weight, and whitespace, not hue. The one reserve of warmth is the pixel-art mascot
(a terracotta crab, "Clawd", and a little house), used sparingly. Mood: precise, calm,
confident — developer-tool seriousness with dry wit.

## Colors

| Role | Hex | Notes |
|---|---|---|
| Background | `#0A0A0A` | primary canvas (near-black), ~60% of the surface |
| Surface / panel | `#121212` | cards, tint panels (steps: `#141414`, `#1E1E1E`) |
| Border | `#2A2A2A` | hairlines (`#383838` for a touch stronger) |
| Text — faint | `#555555` | decorative only (rules, `//` comment prefixes, index totals) |
| Text — muted | `#7D7D7D` | de-emphasised labels / kickers (large text) |
| Text — secondary | `#A8A8A8` | captions, secondary copy (~7:1 on bg) |
| Text — body | `#E0E0E0` | body text (~13:1 on bg) |
| Accent (one only) | `#FFFFFF` | pure white — the single emphasis color |
| Signature warm | `#D97757` | terracotta from the crab mascot; mascot-only, optional |

**Color scheme:** dark
**Accent rule:** one accent per surface, and it is **white**. Monochrome by default —
never introduce a second hue for emphasis; use weight/size/whitespace and the white
highlight. `#D97757` belongs to the mascot art only; the core system is strictly monochrome.
Split roughly 60-30-10 (background / grays / white).

## Typography

- **Display:** JetBrains Mono (the site's brand font, via Google Fonts). Fallback:
  Consolas / `ui-monospace` / monospace. *(For PowerPoint output, ship in **Consolas** —
  it's a monospace that installs with MS Office, so it renders true off the web.)*
- **Body:** the same. This is a **monospace-forward identity** — do not pair with a
  proportional font.

| Role | Size |
|---|---|
| Mega / hero | 92 / 73 px |
| Title | 59 px |
| Subhead | 38 px |
| Body | 24 px |
| Meta / caption | 19 px |

Sizes derive from **one modular ratio, 1.25**, off a 24px base → {19, 24, 38, 59, 73, 92};
keep ≤6 sizes in play. Line-height 1.4–1.6 for body, 1.05–1.2 for display. Kickers and
labels are UPPERCASE with wide letter-spacing, often prefixed `// ` like a code comment.

## Spacing & Shape

- Base grid: **8px** — spacing ∈ {8, 16, 24, 32, 48, 64, 96, 128}
- Border radius: 6–10px on panels/chips (subtle); pixel-art motif uses hard edges
- Shadows: **no** — flat surfaces, hairline borders instead
- Framework hint: custom CSS / design tokens (no UI kit)
- Avoid: gradients, drop shadows, accent stripes, under-title rules (all read as off-brand / AI-filler)

## Voice & Personality

- Tone: precise, technical, confident, dry
- Energy: low-to-medium — declarative, not hype
- Audience: developers and operators running coding agents on Linux

## Voice samples (real copy from the brand)

- "Linux, for agents."
- "Agent-ready Ubuntu, one command."
- "Linux that gives coding agents a stable place to run — without you having to set it up."
- "We curate, we do not aggregate."
- "Time-to-productive" / "Stability" — the two pillars.

## Motif

Chunky **pixel art** (`shape-rendering: crispEdges`). A little **house** = an environment
that's already set up and maintained for you (rendered grayscale, extracted from
`assets/crab-mascot.svg`). The **crab "Clawd"** (terracotta `#D97757`) is the character
mascot. Commit to **one** motif and repeat it sparingly — a cover, a hero moment, a small
footer mark — never on every element. A blinking block cursor (`█`) and `$`/`#` terminal
prompts are on-brand accents.

## Quick Reference (for Claude)

```css
:root {
  --bg:      #0A0A0A;   /* dominant ~60% */
  --surface: #121212;
  --border:  #2A2A2A;
  --faint:   #555555;   /* decorative only */
  --muted:   #7D7D7D;
  --text-2:  #A8A8A8;   /* secondary ~30% */
  --text:    #E0E0E0;   /* body */
  --accent:  #FFFFFF;   /* the one accent ~10% */
  --font:    'JetBrains Mono', Consolas, ui-monospace, monospace;
  --radius:  8px;
  --grid:    8px;       /* spacing multiples */
}
/* dark · monospace · flat · one white accent · 60-30-10 · no gradients/shadows/stripes */
```

---

## Reference

**Website:** [https://agentlinux.org](https://agentlinux.org)
**Source repo:** [github.com/Roo4L/Agent-Linux](https://github.com/Roo4L/Agent-Linux) — brand assets in `assets/`, framing in `docs/VISION.md`
**Slide principles applied:** [power-design](https://github.com/ItsssssJack/power-design) (20 codified slide rules)
