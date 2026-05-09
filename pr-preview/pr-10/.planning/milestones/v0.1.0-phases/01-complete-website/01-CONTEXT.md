# Phase 1: Complete Website - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the entire AgentLinux landing page with all content sections (hero, problem, features, comparison, FAQ, email signup, footer), full design, and working Buttondown email form. Static HTML/CSS/JS, no build step. Must work locally in a browser.

</domain>

<decisions>
## Implementation Decisions

### Visual tone & aesthetic
- Dark theme with black/white/gray palette only — no accent colors
- Terminal personality through monospace type and code-style elements, but NOT a full terminal simulation
- No ASCII art — rely on real graphics (SVG icons, illustrations) instead
- Modern and polished with hacker personality, not retro or gimmicky

### Layout & structure
- Full-viewport sections with generous whitespace — each section feels like its own screen
- Smooth scroll between anchors
- Sticky nav bar at top with section links (Problem, Features, Signup, FAQ) — always visible while scrolling

### Graphics & icons
- SVG line icons throughout (Lucide/Feather style) — simple outlined icons in white/gray
- Clean, lightweight, consistent icon style across features and problem section

### Content & copy voice
- Mostly calm and factual, but with strategic selling punches at key moments — "a go-to Linux distro choice for running your agents"
- Not dry documentation, not hype — persuasive at the right moments
- Developer-level technical specifics in feature descriptions (mention concrete things like "non-root agent user", "QEMU micro-VM images", "apt package groups")
- Core narrative: **"Linux built for agents, not humans"**
- Dual-perspective storytelling: the AI engineer's frustrations hosting agents AND the agent's experience finding a "home" in AgentLinux
- Playful but grounded — agents finding their home
- Claude drafts all copy, user reviews and approves before finalizing

### Problem section
- Consolidate alternatives to three: local machine (merged local + sandboxed), Docker, generic VMs
- Narrative walkthrough format — walk through each alternative showing what goes wrong, then how AgentLinux solves it

### Feature section
- Flat list with SVG icons — all features presented equally in a grid/list
- Each feature gets an icon + title + technical description

### Comparison section
- Narrative walkthrough style (not a table)
- Walk through each alternative as a story of friction, then show AgentLinux as the solution

### FAQ section
- Short and punchy — 3-5 questions only
- Cover essentials: What is it? When? Is it free? Open source?
- Brief answers, 1-2 sentences each

### Email signup
- Single dedicated section near bottom of page, before FAQ
- Hero CTA button scrolls down to this section
- Minimal form: email input + submit button only (no name field)
- CTA copy: "Join the waitlist"
- Post-submit experience: Claude's discretion

### Hero & first impression
- Tagline: "Linux, for agents"
- 1-2 sentence value proposition pitch below the tagline
- Hero visual: crab mascot (Claude Code's mascot) in a "home" visual — agents finding their place in AgentLinux
- "Join the waitlist" CTA button that scrolls to signup section

### Claude's Discretion
- Post-submit experience (inline message vs redirect)
- Crab mascot graphic approach (SVG illustration vs AI-generated — fit the minimal aesthetic)
- Exact spacing, typography sizes, and section transitions
- Loading/error states for email form
- Footer content and layout details
- Exact icon choices for each feature

</decisions>

<specifics>
## Specific Ideas

- "Linux, for agents" as the tagline — short, declarative, immediately communicates the concept
- Claude Code crab mascot in the hero as a visual of agents finding their "home" in AgentLinux
- Dual narrative perspective: engineer's hosting frustrations + agent's experience finding a comfortable environment
- Strategic selling phrases like "a go-to Linux distro choice for running your agents" mixed into otherwise factual copy
- "Join the waitlist" as the CTA language — implies demand and urgency

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, no existing code

### Established Patterns
- None — first phase, patterns will be established here

### Integration Points
- Buttondown API for email form submission
- GitHub Pages deployment (Phase 2 concern, but form action should work without CORS issues)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-complete-website*
*Context gathered: 2026-03-09*
