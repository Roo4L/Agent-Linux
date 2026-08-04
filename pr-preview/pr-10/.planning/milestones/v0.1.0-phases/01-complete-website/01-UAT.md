---
status: resolved
phase: 01-complete-website
source: 01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md
started: 2026-03-09T11:10:00Z
updated: 2026-03-09T11:20:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

## Tests

### 1. Dark Theme and Monospace Typography
expected: Opening index.html in a browser shows a dark-themed page with monospace fonts (JetBrains Mono). Background is dark, text is light, terminal/CLI aesthetic throughout.
result: pass

### 2. Sticky Navigation
expected: A navigation bar stays fixed at the top while scrolling. Clicking nav links scrolls smoothly to the corresponding section (Problem, Features, Comparison, Signup, FAQ).
result: pass

### 3. Hero Section with Mascot and CTA
expected: Above the fold: "AgentLinux" heading, "Linux, for agents" tagline, value proposition text, a pixel-art Clawd crab mascot approaching a house, and a "Join the waitlist" CTA button.
result: pass

### 4. CTA Scrolls to Signup
expected: Clicking the "Join the waitlist" CTA button in the hero section scrolls the page down to the email signup form.
result: pass

### 5. Problem Section
expected: Scrolling past the hero reveals a "Problem" section with three subsections covering agent runtime pain points (local machine, Docker, generic VMs), each with an icon, title, and narrative text.
result: pass

### 6. Features Grid
expected: A grid of 8 feature cards, each with an SVG icon, title, and description. Cards are responsive — multiple columns on desktop, stacking on mobile.
result: issue
reported: "On mobile features don't stack, they remain in two columns."
severity: minor

### 7. Comparison Section
expected: A section contrasting alternatives (local, Docker, VMs) with AgentLinux's approach, showing what's different/better for each.
result: pass

### 8. Email Signup Form
expected: An email signup form is visible with an input field and submit button. Entering an email and submitting sends the data to Buttondown (form action points to Buttondown endpoint).
result: pass

### 9. FAQ Section
expected: FAQ section with question/answer pairs covering key visitor questions about AgentLinux.
result: pass

### 10. Footer
expected: Page ends with a footer containing copyright text and branding.
result: pass

### 11. Responsive Mobile Layout
expected: Resizing the browser to mobile width (~375px) shows the page adapts: nav adjusts, feature cards stack vertically, text remains readable, no horizontal scrolling.
result: pass

## Summary

total: 11
passed: 10
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "Feature cards stack to single column on mobile"
  status: resolved
  reason: "User reported: On mobile features don't stack, they remain in two columns."
  severity: minor
  test: 6
  root_cause: "CSS source order bug: @media (max-width: 900px) rule for .features-grid came after @media (max-width: 640px) rule, so the 2-column tablet layout overrode the 1-column mobile layout"
  artifacts:
    - path: "index.html"
      issue: "900px media query override order"
  missing:
    - "Add min-width: 641px to 900px breakpoint so it doesn't apply at mobile widths"
  debug_session: ""
