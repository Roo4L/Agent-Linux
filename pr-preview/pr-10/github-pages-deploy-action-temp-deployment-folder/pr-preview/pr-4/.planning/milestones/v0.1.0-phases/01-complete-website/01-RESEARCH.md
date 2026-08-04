# Phase 1: Complete Website - Research

**Researched:** 2026-03-09
**Domain:** Static landing page (HTML/CSS/JS), email signup integration, dark terminal aesthetic
**Confidence:** HIGH

## Summary

This phase is a greenfield static landing page -- no build tools, no frameworks, pure HTML/CSS/JS. The technical complexity is low but the design and content quality bar is high. The page must convey a terminal/hacker aesthetic (dark theme, monospace type, SVG line icons) while remaining modern and polished, not retro.

The primary technical integration is Buttondown for email signup. Buttondown provides a public `embed-subscribe` endpoint that accepts standard form POST without an API key, but this causes a page redirect. For a stay-on-page experience, the Buttondown REST API (`/v1/subscribers`) can be used via `fetch()`, but this requires exposing an API key in client-side code and only works when served over HTTP (not `file://` due to CORS). The recommended approach is the HTML form POST to the embed endpoint, which works universally including from `file://`, with progressive enhancement via JavaScript fetch when served from a real origin.

**Primary recommendation:** Build a single `index.html` with inline CSS (`<style>`) and inline JS (`<script>`), using copy-pasted Lucide SVG icons inline. Use Buttondown's embed-subscribe form POST as the baseline, with optional JS enhancement for no-redirect UX.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Dark theme with black/white/gray palette only -- no accent colors
- Terminal personality through monospace type and code-style elements, but NOT a full terminal simulation
- No ASCII art -- rely on real graphics (SVG icons, illustrations) instead
- Modern and polished with hacker personality, not retro or gimmicky
- Full-viewport sections with generous whitespace
- Smooth scroll between anchors
- Sticky nav bar at top with section links (Problem, Features, Signup, FAQ)
- SVG line icons throughout (Lucide/Feather style) -- simple outlined icons in white/gray
- Mostly calm and factual copy with strategic selling punches
- Core narrative: "Linux built for agents, not humans"
- Dual-perspective storytelling: engineer's frustrations + agent's experience
- Problem section: consolidate to three alternatives (local machine, Docker, generic VMs)
- Narrative walkthrough format for problem/comparison sections (not tables)
- Feature section: flat list with SVG icons in a grid/list
- FAQ: 3-5 questions, brief answers
- Email signup: single section near bottom, before FAQ
- Hero CTA scrolls to signup section
- Minimal form: email input + submit button only
- CTA copy: "Join the waitlist"
- Tagline: "Linux, for agents"
- Hero visual: crab mascot in a "home" visual
- Claude drafts all copy, user reviews

### Claude's Discretion
- Post-submit experience (inline message vs redirect)
- Crab mascot graphic approach (SVG illustration vs AI-generated)
- Exact spacing, typography sizes, and section transitions
- Loading/error states for email form
- Footer content and layout details
- Exact icon choices for each feature

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HERO-01 | Landing page displays AgentLinux name with tagline above the fold | Standard HTML/CSS hero section pattern; monospace font pairing |
| HERO-02 | Clear value proposition statement | Copy drafting; typography hierarchy |
| HERO-03 | CTA button that scrolls to email signup form | `scroll-behavior: smooth` + anchor links + `scroll-padding-top` for sticky nav offset |
| PROB-01 | Pain point section walking through current agent runtime options | Narrative content section; full-viewport layout pattern |
| FEAT-01 | Feature list showcasing planned AgentLinux capabilities | CSS Grid for feature cards |
| FEAT-02 | Visual icons or illustrations accompanying each feature | Lucide inline SVGs, copy-pasted from lucide.dev |
| COMP-01 | Narrative-style comparison of AgentLinux vs alternatives | Content section with narrative walkthrough design |
| MAIL-01 | Email signup form integrated with Buttondown API | Buttondown embed-subscribe POST endpoint; progressive JS enhancement |
| FAQ-01 | FAQ section with common questions | Semantic HTML with details/summary or styled divs |
| DSGN-01 | Terminal/hacker aesthetic -- dark theme, monospace fonts, CLI visual style | CSS custom properties for dark palette; monospace font stack |
| DSGN-02 | Responsive design (mobile + desktop) | CSS Grid + Flexbox; mobile-first media queries |
| DSGN-03 | Static HTML/CSS/JS -- no build step, no framework | Single index.html with inline styles and scripts |
| FOOT-01 | Footer with copyright and basic links | Standard footer pattern |
</phase_requirements>

## Standard Stack

### Core
| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| HTML5 | - | Page structure | Required by DSGN-03; semantic elements for accessibility |
| CSS3 (inline `<style>`) | - | All styling | No build step; CSS custom properties for theming |
| Vanilla JS (inline `<script>`) | ES6+ | Form enhancement, smooth scroll fallback | No framework constraint; minimal JS needed |

### Supporting
| Resource | Version | Purpose | When to Use |
|----------|---------|---------|-------------|
| Lucide Icons | Latest | SVG line icons for features | Copy SVG markup from lucide.dev, paste inline |
| Buttondown embed-subscribe | - | Email signup | Form POST to `https://buttondown.com/api/emails/embed-subscribe/{USERNAME}` |
| Google Fonts / system fonts | - | Monospace typography | `JetBrains Mono` or `Fira Code` for headings; system monospace for body |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline SVGs | Lucide CDN via `<img>` tags | CDN adds external dependency; inline allows color control via `currentColor` |
| System monospace | Google Fonts monospace | Google Fonts adds polish but requires network; use with `font-display: swap` |
| Single HTML file | Separate CSS/JS files | Separate files are cleaner for large projects, but single file is simpler for a landing page and loads faster |

## Architecture Patterns

### Recommended Project Structure
```
/
├── index.html           # Everything: HTML + inline CSS + inline JS
├── assets/
│   └── crab-mascot.svg  # Hero illustration (if SVG)
└── .planning/           # Planning docs (not deployed)
```

### Pattern 1: CSS Custom Properties for Dark Theme
**What:** Define all colors as CSS variables on `:root` for consistent dark theming
**When to use:** Always -- this is the foundation of DSGN-01
**Example:**
```css
:root {
  --bg-primary: #0a0a0a;
  --bg-secondary: #141414;
  --bg-tertiary: #1e1e1e;
  --text-primary: #e0e0e0;
  --text-secondary: #a0a0a0;
  --text-muted: #666666;
  --border: #2a2a2a;
  --accent: #ffffff;  /* White as the only "accent" */
}

* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: var(--bg-primary);
  color: var(--text-primary);
  font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', monospace;
  line-height: 1.6;
}
```

### Pattern 2: Full-Viewport Sections
**What:** Each content section takes up at least the full viewport height
**When to use:** All major sections (hero, problem, features, comparison, signup, FAQ)
**Example:**
```css
section {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 6rem 2rem;
  max-width: 900px;
  margin: 0 auto;
}
```

### Pattern 3: Sticky Nav with Scroll Offset
**What:** Fixed navigation that doesn't obscure anchor targets when scrolling
**When to use:** Required -- sticky nav is a locked decision
**Example:**
```css
html {
  scroll-behavior: smooth;
  scroll-padding-top: 80px; /* Height of sticky nav */
}

nav {
  position: sticky;
  top: 0;
  z-index: 1000;
  background: var(--bg-primary);
  border-bottom: 1px solid var(--border);
  backdrop-filter: blur(10px);
}
```

### Pattern 4: Responsive Feature Grid
**What:** CSS Grid that adapts from multi-column on desktop to single column on mobile
**When to use:** Feature list (FEAT-01)
**Example:**
```css
.features-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 2rem;
}

@media (max-width: 640px) {
  .features-grid {
    grid-template-columns: 1fr;
  }
}
```

### Pattern 5: Buttondown Form with Progressive Enhancement
**What:** HTML form that works without JS, enhanced with fetch for no-redirect UX
**When to use:** Email signup section (MAIL-01)
**Example:**
```html
<form
  action="https://buttondown.com/api/emails/embed-subscribe/AGENT_LINUX_USERNAME"
  method="post"
  class="embeddable-buttondown-form"
  id="signup-form"
>
  <input type="email" name="email" placeholder="you@example.com" required />
  <input type="hidden" name="embed" value="1" />
  <button type="submit">Join the waitlist</button>
</form>

<script>
// Progressive enhancement: prevent redirect, show inline message
document.getElementById('signup-form').addEventListener('submit', async (e) => {
  // Only intercept if we can make fetch requests (not file://)
  if (window.location.protocol === 'file:') return; // Let form POST normally

  e.preventDefault();
  const form = e.target;
  const email = form.querySelector('[name="email"]').value;
  const button = form.querySelector('button');
  const originalText = button.textContent;

  button.textContent = 'Submitting...';
  button.disabled = true;

  try {
    const response = await fetch(form.action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(new FormData(form)),
    });

    if (response.ok || response.redirected) {
      form.innerHTML = '<p class="success">You\'re on the list. We\'ll be in touch.</p>';
    } else {
      throw new Error('Submission failed');
    }
  } catch (err) {
    button.textContent = originalText;
    button.disabled = false;
    // Fallback: submit form normally (will redirect)
    form.submit();
  }
});
</script>
```

**Note:** The `embed-subscribe` endpoint may not return CORS headers for cross-origin fetch. If fetch fails due to CORS, the catch block falls back to normal form submission. This is the safest progressive enhancement pattern. Testing will confirm CORS behavior once the Buttondown username is configured.

### Anti-Patterns to Avoid
- **Terminal emulator simulation:** The user explicitly rejected a full terminal simulation. Use terminal *aesthetic* (monospace, dark, code-style elements) without building an actual terminal UI.
- **Color creep:** Stick to black/white/gray. No green terminal text, no syntax highlighting colors, no accent colors.
- **Tiny unreadable text:** Monospace fonts need larger sizes than proportional fonts. Base should be 16px minimum, headings significantly larger.
- **Over-animating:** Keep transitions subtle. `transition: opacity 0.3s` is fine; elaborate scroll-triggered animations are not in scope.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SVG icons | Custom icon drawings | Lucide icon SVGs (copy from lucide.dev) | Consistent stroke width, sizing, and style across 1000+ icons |
| Email signup backend | Custom email collection | Buttondown embed-subscribe endpoint | Handles validation, spam, double opt-in, subscriber management |
| Smooth scroll | Custom JS scroll animation | `scroll-behavior: smooth` CSS property | Native browser support, no JS needed, respects `prefers-reduced-motion` |
| Responsive grid | Manual percentage-based layouts | CSS Grid with `auto-fit`/`minmax` | Handles breakpoints automatically, less code |
| Monospace fonts | System font only | Google Fonts (JetBrains Mono) with system fallback | Professional look with zero-cost fallback |

**Key insight:** This is a content-heavy landing page, not an app. The "engineering" is in CSS layout, typography, and copy quality -- not in complex JavaScript logic.

## Common Pitfalls

### Pitfall 1: Sticky Nav Covers Anchor Targets
**What goes wrong:** Clicking nav links scrolls to sections, but the section heading is hidden behind the sticky nav.
**Why it happens:** `scroll-behavior: smooth` scrolls to the element's top, which is now under the fixed nav.
**How to avoid:** Set `scroll-padding-top` on `html` equal to the nav height (e.g., `80px`).
**Warning signs:** Clicking a nav link and not seeing the section heading.

### Pitfall 2: Monospace Font Sizing
**What goes wrong:** Text looks tiny and cramped because monospace fonts have wider characters but often feel smaller at the same `font-size`.
**Why it happens:** Monospace fonts have uniform character widths, making text feel denser.
**How to avoid:** Use at least `16px` base size, `1.6-1.8` line-height. Test readability on mobile.
**Warning signs:** Squinting to read body text.

### Pitfall 3: Full-Viewport Sections on Short Content
**What goes wrong:** Sections with little content (FAQ, footer) have huge empty spaces with `min-height: 100vh`.
**Why it happens:** Applying viewport height uniformly to all sections regardless of content volume.
**How to avoid:** Only use `min-height: 100vh` for major sections (hero, problem, features). Let FAQ and footer height be content-driven.
**Warning signs:** Awkward whitespace gaps near bottom of page.

### Pitfall 4: Buttondown Form on file:// Protocol
**What goes wrong:** JavaScript fetch to Buttondown fails silently when opening `index.html` as a local file.
**Why it happens:** `file://` protocol triggers CORS restrictions on cross-origin fetch requests.
**How to avoid:** Progressive enhancement pattern -- detect `file://` and let the form POST normally (which redirects but works). Or use `python3 -m http.server` for local testing.
**Warning signs:** Email form submit does nothing when opened as a local file.

### Pitfall 5: Missing Viewport Meta Tag
**What goes wrong:** Page looks tiny/zoomed out on mobile devices.
**Why it happens:** Forgetting `<meta name="viewport" content="width=device-width, initial-scale=1">`.
**How to avoid:** Include it in `<head>`. This is non-negotiable for responsive design.
**Warning signs:** Everything looks desktop-sized on a phone.

### Pitfall 6: Dark Theme Contrast Issues
**What goes wrong:** Text is unreadable against dark backgrounds, or sections blend together.
**Why it happens:** Insufficient contrast between text and background, or between adjacent sections.
**How to avoid:** Use WCAG AA contrast ratios (4.5:1 for body text). Alternate section backgrounds between `--bg-primary` and `--bg-secondary` to create visual separation.
**Warning signs:** Failing accessibility contrast checkers; sections looking like one continuous block.

## Code Examples

### Inline Lucide SVG Icon
```html
<!-- Copy SVG from lucide.dev/icons/terminal -->
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"
     viewBox="0 0 24 24" fill="none" stroke="currentColor"
     stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polyline points="4 17 10 11 4 5"/>
  <line x1="12" x2="20" y1="19" y2="19"/>
</svg>
```
Source: lucide.dev -- each icon page has a "Copy SVG" button.

### Responsive Nav Bar
```html
<nav>
  <div class="nav-inner">
    <a href="#" class="nav-logo">AgentLinux</a>
    <div class="nav-links">
      <a href="#problem">Problem</a>
      <a href="#features">Features</a>
      <a href="#signup">Signup</a>
      <a href="#faq">FAQ</a>
    </div>
  </div>
</nav>
```
```css
.nav-inner {
  max-width: 900px;
  margin: 0 auto;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem 2rem;
}

.nav-logo {
  font-weight: 700;
  font-size: 1.2rem;
  color: var(--accent);
  text-decoration: none;
}

.nav-links a {
  color: var(--text-secondary);
  text-decoration: none;
  margin-left: 2rem;
  font-size: 0.875rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.nav-links a:hover {
  color: var(--accent);
}

@media (max-width: 640px) {
  .nav-links a { margin-left: 1rem; font-size: 0.75rem; }
}
```

### Google Fonts Loading (JetBrains Mono)
```html
<head>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
</head>
```

### Accessible Reduced Motion
```css
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| jQuery smooth scroll plugins | `scroll-behavior: smooth` CSS | 2020+ (full browser support) | Zero JS needed for smooth scrolling |
| Float-based layouts | CSS Grid + Flexbox | 2018+ | Responsive grids in a few lines |
| Icon fonts (Font Awesome) | Inline SVGs (Lucide) | 2020+ | Better accessibility, tree-shakeable, no font loading |
| Media query breakpoint systems | `auto-fit` + `minmax()` CSS Grid | 2018+ | Self-adapting layouts without breakpoints |
| JS-based sticky nav | `position: sticky` CSS | 2019+ (full support) | No scroll event listeners needed |

**Deprecated/outdated:**
- jQuery for DOM manipulation -- vanilla JS covers all needs for a landing page
- CSS vendor prefixes for flexbox/grid -- no longer needed for modern browsers
- `position: fixed` for sticky nav -- `position: sticky` is simpler and more correct

## Open Questions

1. **Buttondown Username**
   - What we know: The form action URL requires a Buttondown username/account ID
   - What's unclear: What is the actual AgentLinux Buttondown username?
   - Recommendation: Use a placeholder like `agentlinux` in the form action; user will confirm the actual username

2. **Crab Mascot Illustration**
   - What we know: Hero should have a crab mascot (Claude Code's mascot) in a "home" visual
   - What's unclear: How to create this -- SVG illustration? AI-generated image? What art style?
   - Recommendation: Create a simple SVG illustration of a crab to match the minimal line-icon aesthetic. This is in Claude's discretion area. A simple geometric/line-art crab keeps consistent with the Lucide icon style.

3. **Buttondown embed-subscribe CORS behavior**
   - What we know: The endpoint accepts form POST without API key. It likely redirects on success.
   - What's unclear: Whether `fetch()` to the embed-subscribe URL works cross-origin (CORS headers unknown)
   - Recommendation: Implement progressive enhancement. Try fetch first; on CORS failure, fall back to normal form POST. Test once Buttondown username is set up.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual browser testing (no automated test framework -- static HTML page) |
| Config file | None |
| Quick run command | `open index.html` or `python3 -m http.server 8000` |
| Full suite command | Manual checklist verification |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HERO-01 | AgentLinux name + tagline visible above fold | manual | Open index.html, verify visually | N/A |
| HERO-02 | Value proposition statement visible | manual | Open index.html, verify visually | N/A |
| HERO-03 | CTA button scrolls to signup form | manual | Click CTA, verify scroll target | N/A |
| PROB-01 | Pain point section with runtime alternatives | manual | Scroll to problem section, verify content | N/A |
| FEAT-01 | Feature list with descriptions | manual | Scroll to features, verify content | N/A |
| FEAT-02 | Visual icons with features | manual | Verify SVG icons render alongside features | N/A |
| COMP-01 | Narrative comparison section | manual | Scroll to comparison, verify narrative format | N/A |
| MAIL-01 | Email signup form submits to Buttondown | manual | Submit test email, verify in Buttondown dashboard | N/A |
| FAQ-01 | FAQ section with questions | manual | Scroll to FAQ, verify questions and answers | N/A |
| DSGN-01 | Dark theme, monospace fonts, CLI style | manual | Visual inspection of theme, fonts, aesthetic | N/A |
| DSGN-02 | Responsive mobile + desktop | manual | Resize browser / use DevTools responsive mode | N/A |
| DSGN-03 | Static HTML/CSS/JS, no build step | manual | Verify single index.html opens in browser directly | N/A |
| FOOT-01 | Footer with copyright | manual | Scroll to bottom, verify footer | N/A |

### Sampling Rate
- **Per task commit:** Open `index.html` in browser, verify new section renders correctly
- **Per wave merge:** Full manual walkthrough of all sections on desktop + mobile viewport
- **Phase gate:** Complete checklist of all 13 requirements verified visually

### Wave 0 Gaps
None -- this is a static HTML page with no test framework. Validation is visual/manual by nature. Automated testing would be overkill for a single-page landing with no dynamic logic beyond the email form.

## Sources

### Primary (HIGH confidence)
- [Buttondown Docs - Building Subscriber Base](https://docs.buttondown.com/building-your-subscriber-base) - Form embed endpoint, HTML form structure
- [Buttondown Docs - Embed Form CORS/CSP](https://docs.buttondown.com/embed-form-cors-csp) - CORS behavior for embedded forms
- [Lucide Static Package Guide](https://lucide.dev/guide/packages/lucide-static) - CDN usage, inline SVG approach
- [MDN - scroll-behavior](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scroll-behavior) - CSS smooth scrolling
- [MDN - scroll-padding-top](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scroll-padding-top) - Sticky nav offset fix
- [Lucide Icons Browser](https://lucide.dev/icons/) - Icon search and SVG copy

### Secondary (MEDIUM confidence)
- [CSS-Tricks - Sticky, Smooth, Active Nav](https://css-tricks.com/sticky-smooth-active-nav/) - Sticky nav implementation patterns
- [CSS-Tricks - Fixed Headers and Jump Links](https://css-tricks.com/fixed-headers-and-jump-links-the-solution-is-scroll-margin-top/) - scroll-margin-top solution

### Tertiary (LOW confidence)
- Buttondown embed-subscribe CORS behavior with fetch() -- not documented, needs runtime testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - vanilla HTML/CSS/JS is well-understood; no framework risk
- Architecture: HIGH - CSS Grid, Flexbox, custom properties are mature and well-documented
- Buttondown integration: MEDIUM - embed form POST is documented; fetch/CORS behavior is uncertain
- Pitfalls: HIGH - common issues with sticky nav, dark themes, responsive design are well-catalogued

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable technologies, 30-day validity)
