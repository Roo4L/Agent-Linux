# Phase 16: Strategy + Roadmap Doc - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 15-strategy-roadmap-doc
**Mode:** Interactive discuss (`/gsd-autonomous --interactive --only 15`)
**Areas discussed:** Content for the 2 status sections, Themes section count + format, Execution principles structure, Cross-reference / ADR-citation density, Doc spine reframe (research-driven mid-discuss)

---

## Gray area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Content for the 2 status sections | `## Where we are now` + `## What we're working on next` — content focus + horizon | ✓ |
| Themes section — count + format | STRATR-03 floor 2 themes; markdown structure for each | ✓ |
| Execution principles structure | `### {Name}` + paragraph vs bulleted list | ✓ |
| Cross-reference / ADR-citation density | Heavy audit-trail flavor vs lighter touch | ✓ |

**User's choice:** All four (multiSelect).

---

## Area 1 — Content for the 2 status sections

### Round 1 — `## Where we are now` content emphasis

| Option | Description | Selected |
|--------|-------------|----------|
| Product-capability summary | Lead with what AgentLinux delivers today: v0.3.0 + v0.4.0 capabilities; one paragraph per pillar status | |
| Milestone-progress (status-report) | Lead with what's in flight in v0.3.3 — calendar-flavored | |
| Combined: product first, milestone second | Product paragraph + milestone paragraph | |
| **Other (user free-text)** | — | ✓ |

**User's choice / free-text:** "Tbh, I am not sure if we even need this information in the first place. What I would like to focus on is saying what is our current goal/milestone that we are trying to achieve right now (which is shipping first usable agentlinux version for myself). That's what matters now."

**Notes:** Major content reframe. `## Where we are now` becomes goal-flavored, not status-report-flavored. Captured in CONTEXT.md `<decisions>` "Where we are now content posture."

### Round 1 — `## What we're working on next` horizon

| Option | Description | Selected |
|--------|-------------|----------|
| Both: rest of v0.3.3 + first v0.6+ work | Two short paragraphs | |
| Current-milestone tail only | Just Phase 17 website refresh | |
| v0.6+ peek only | Skip v0.3.3 tail | |
| **Other (user free-text)** | — | ✓ |

**User's choice / free-text:** Dump of 6 forward ideas:
1. Make first usable release of AgentLinux for myself
2. Extend the package list with most popular projects for Agentic development
3. Establish pipeline for proper tests and updates of those packages, so that we would have promised stability for the maintained packages list.
4. Extend agentlinux support beyond ubuntu: make it support AlmaLinux at least (because on my work place I use AlmaLinux for running agents).
5. Ship first release updates to all mail list subscribers, so that they could review what I've built and I could get some feedback from potential users.
6. Apply for OSS funding.
"Those points are not listed in their direct order. This is just dump of ideas that I have in my head. We need to figure out their priority and order later together."

### Round 2 — Definition of "first usable AgentLinux release for myself"

| Option | Description | Selected |
|--------|-------------|----------|
| Broader catalog (more agentic-dev tools) | Cursor CLI, Codex CLI, aider, Continue, Goose, etc. | |
| AlmaLinux support | Work-env distro | ✓ |
| Catalog update pipeline that doesn't break | Watches upstream, runs bats, advances pin only when green | |
| Something else / it's the combination | — | ✓ ("This Jira task: https://copiedwonder.atlassian.net/browse/AL-38") |

**User's choice:** AlmaLinux + AL-38 (Jira task — v0.3.4 Aware Installation Process, brownfield-aware installer).

**Notes:** AL-38 fetched live from Jira and confirmed = v0.3.4 milestone trigger (5 phases: Detection, Reuse, Remediate+Consent, Pre-flight UX, Docs + Brownfield Acceptance Gate). User noted v0.3.4 work is in a separate worktree — STRATEGY.md just references AL-38 by Jira key.

### Round 3 — Sequencing of 6 forward items

| Option | Description | Selected |
|--------|-------------|----------|
| Looks right — go with it | Near-term: v0.3.3 tail → AL-38 → AlmaLinux → mail-list announce. Parallel: OSS funding. v0.6+: broader catalog + update pipeline. | |
| Swap something — I'll describe | — | |
| Mail-list announce should be earlier (pre-v0.3.4) | Announce v0.3.0/v0.4.0 to the subscriber list NOW | |
| AlmaLinux should be a v0.6+ theme, not near-term | Push it after the brownfield milestone | |
| **Other (user free-text)** | — | ✓ |

**User's choice / free-text:** "I believe that mail-list announce should be done later for one simple reason: current release is so tiny that it will basically get no one interested. I believe we need to build critical mass of projects before coming up with any public announcement."

**Notes:** Mail-list announce moves to v0.6+ themes (gated on broader-catalog critical mass). Public engagement becomes a separate v0.6+ theme with explicit sequencing rationale tying it to broader-catalog.

### Round 3 — v0.3.4 / AL-38 planning state

| Option | Description | Selected |
|--------|-------------|----------|
| v0.3.4 plans were superseded by the v0.3.3 reframe | Replan after v0.3.3 | |
| v0.3.4 plans are still on file, just paused | Pick up unchanged | |
| Not sure — mention AL-38 brownfield work without claiming current plan state | — | |
| **Other (user free-text)** | — | ✓ |

**User's choice / free-text:** "The work is being done about this task in a separate git worktree, so never mind."

**Notes:** Phase 16 references AL-38 by Jira key only; does not claim authoritative in-repo plan state.

---

## Area 2 — Themes section: count + format

### Round 1 — Theme count

| Option | Description | Selected |
|--------|-------------|----------|
| 4 themes (Security Hardening + Preset/Profile + Broader catalog + Public engagement) | Full list | |
| 3 themes — fold broader catalog + public engagement into one | "Broader catalog → community engagement" | |
| 2 themes (the STRATR-03 minimum) | Just the mandated two | |
| **Other (user free-text)** | — | ✓ |

**User's choice / free-text:** "I believe some information might got outdated in the phase requirements. If you look up our VISION.md, you will find out and that we ditched security hardening pillar. Do I miss something and this topic is about something else?"

**Notes:** Triggered Security-Hardening pillar-vs-theme clarification:
- Phase 14 verdict (b) declined Security as a separate Pillar 3 (no honest already-shipped table-stakes).
- Phase 14 explicitly *kept* Security Hardening as a v0.6+ *opportunistic theme* (declined defenses eligible to mature into milestones later).
- REQUIREMENTS.md STRATR-03 mandates it as a theme.
- Distinction: pillar = identity commitment we ship now; theme = forward-looking direction our roadmap might commit to later.

User accepted the clarification; theme stays.

### Round 1 — Theme markdown structure

| Option | Description | Selected |
|--------|-------------|----------|
| `### {Theme Name}` + bold `**Sequencing rationale:**` line | Flatter hierarchy | |
| `### {Theme Name}` + nested `#### Sequencing rationale` sub-header | Literal STRATR-03 reading | |
| Bulleted list with `Sequencing rationale:` line per bullet | Most compact | |
| **Other (user free-text)** | — | ✓ |

**User's choice / free-text:** "I don't care about format. Please, conduct the research on best-practices, templates and guidelines on how to design strategy documents for organization, what is the difference between strategy and roadmap and re-organize you job accordingly."

**Notes:** Major mid-discuss reframe request. Triggered the research pass (delegated to a subagent).

---

## Mid-discuss research pass — Strategy doc design

**Spawn:** general-purpose subagent, 2026-05-19. Capped under 600 words.

**Findings:**
- Strategy vs roadmap = "why this/why not that" (decisions, beliefs, bets) vs "what ships when" (time-ordered delivery). Sources: Rumelt *Good Strategy/Bad Strategy*; Pichler "Product Strategy vs Product Roadmap"; Cagan SVPG (*Empowered*, *Transformed*).
- Canonical short-strategy shapes: Rumelt's Kernel (Diagnosis → Guiding policy → Coherent actions); GitLab/Sourcegraph handbook (Vision-linked → Where we are → What's next → Not doing → How we work); Stripe-style internal memo (Context → Bets → Non-bets → Operating principles); Basecamp/Shape-Up (Appetite + Boundaries + Rabbit holes + No-gos — cycle-scoped, less applicable).
- Most online templates (Aha!, ProductPlan, Atlassian, Asana) are Rumelt's "bad strategy" — generic Vision/Mission/Values/Themes/Initiatives/Metrics checklists.
- Fusing strategy + roadmap content works at small scale if time-bound content is demarcated; splitting keeps strategy stable but adds drift risk.
- **Recommendation for AgentLinux:** Current 4-section spine is "mostly roadmap with execution principles bolted on" — missing diagnosis + guiding-policy moves. Proposed 5-section spine: Diagnosis → Guiding policy → Where we are now → What's next + Themes → Execution principles.

### Round 2 — Doc spine

| Option | Description | Selected |
|--------|-------------|----------|
| Adopt the 5-section Rumelt-style spine | Reframes the doc; STRATR-02 amends in same commit window | ✓ |
| Keep the 4-section spine, smuggle Diagnosis + Guiding-policy as subsections | Cheaper change but blurs structure | |
| Keep the 4-section spine as-is | Accept the "roadmap masquerading as strategy" trade-off | |
| Different shape — I'll describe | — | |

**User's choice:** Adopt the 5-section Rumelt-style spine.

**Notes:** Major mid-discuss reframe. REQUIREMENTS.md STRATR-02 amends in the same Phase 16 commit window. Precedent: Phase 15 STRAT-* → VIS-* + STRATR-* reframe 2026-05-16.

### Round 3 — Diagnosis vs duplication of VISION.md

| Option | Description | Selected |
|--------|-------------|----------|
| Keep `## Diagnosis` with one-line VISION.md reference + specific bug-class content | No duplication risk (VISION.md was deliberately purged of diagnosis content during Phase 15) | ✓ |
| Drop `## Diagnosis`; let Guiding policy carry alone | Reverts to "roadmap with execution principles" | |
| Fold Diagnosis content into top of Guiding policy as preamble | Tighter; loses Rumelt-clarity | |

**User's choice:** Keep `## Diagnosis` with reference back to VISION.md.

**Notes:** Confirmed VISION.md does not contain diagnosis content. The narrow problem-list (EACCES, recursive shim, self-update breakage) was deliberately cut from VISION.md Mission during Phase 15 to keep it broad-value-prop.

### Round 3 — Section heading names

| Option | Description | Selected |
|--------|-------------|----------|
| `## Diagnosis` + `## Guiding policy` | Rumelt vocabulary verbatim | |
| `## The problem` + `## How we choose` | Plainer English | |
| `## What we're solving` + `## Our bets` | Outcome + Stripe-memo flavor | ✓ |

**User's choice:** `## What we're solving` + `## Our bets`.

### Round 2 — Fuse What's next + Themes or keep separate

| Option | Description | Selected |
|--------|-------------|----------|
| Keep as separate H2s | Two scoped sections | |
| Fuse into one section `## What's next` (with subsections) | One section, `### Near-term` + `### Themes for v0.6+` | ✓ |

**User's choice:** Fuse.

### Round 2 (revisit) — Theme count under new spine

| Option | Description | Selected |
|--------|-------------|----------|
| 3 themes (Security Hardening + Preset/Profile + Broader catalog) | Drops standalone Public-engagement | |
| 4 themes (full list including Public engagement) | Hits STRATR-03 ceiling | ✓ |
| 2 themes (minimum) | Move broader catalog talk to Near-term | |

**User's choice:** 4 themes.

### Round 2 (revisit) — Execution principles format

| Option | Description | Selected |
|--------|-------------|----------|
| Bulleted list with `**Name** — ` prefix | Compact | |
| `### {Principle name}` + short paragraph each | Mirrors VISION.md guiding principles | |
| **Other (user free-text)** | — | ✓ |

**User's choice / free-text:** "I don't care about such details."

**Notes:** Claude's discretion. Defaulted to bulleted list (research-recommended; saves ~1 KB vs paragraph blocks).

---

## Area 3 — Execution principles structure

Folded into Area 2 Round 2 revisit. User deferred to Claude's discretion.

---

## Area 4 — Cross-reference / ADR-citation density

Not explicitly asked after the doc-spine reframe absorbed it; user's "I don't care about such details" answer on principles format generalized. Claude's discretion (captured in CONTEXT.md):

- Lighter-touch citation flavor (Sourcegraph/GitLab handbook style).
- Only load-bearing ADRs (ADR-002, ADR-004, ADR-011, ADR-016) + the two exploration verdict files get inline links inside section bodies.
- `## Related` block at the bottom of the doc carries the wider reference index (STABILITY-MODEL.md precedent).

---

## Claude's Discretion

- Cross-reference / ADR-citation density — light touch with `## Related` index at bottom.
- Exact execution-principles list format — bulleted with `**Name** — ` prefix and inline `(ADR-XX)` citation per entry.
- Exact prose for each section body (subject to voice-rule grep gate + section spine + locked substance).
- Theme ordering inside `### Themes for v0.6+` — explicit Sequencing-rationale link between themes 3 and 4 required; order of themes 1 and 2 is Claude's call.
- Whether to include a 6th or 7th execution principle (mandated floor 5; ceiling 7) — reviewer-loop and AI-agent collaboration are candidates if room permits under the 8 KB ceiling.

## Deferred Ideas

- `/gsd-complete-milestone` cadence binding for `> Last reviewed:` header.
- Strategy-doc periodic-review cadence.
- Public-facing "How we work with AI agents" addendum.
- External-link-rot guard for Jira / Anthropic CDN references.
- Separate roadmap document split from STRATEGY.md (research surfaced; not adopted).
