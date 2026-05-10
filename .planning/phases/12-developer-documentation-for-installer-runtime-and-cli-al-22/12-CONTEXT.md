# Phase 12: Developer documentation for installer, runtime, and CLI (AL-22) - Context

**Gathered:** 2026-05-09
**Status:** Ready for planning
**Source spec:** [AL-22](https://copiedwonder.atlassian.net/browse/AL-22) — "Create documentation on what AgentLinux does"

<domain>
## Phase Boundary

Create developer-facing internal documentation explaining **what each AgentLinux component does and why it exists** — with a product-perspective lens — and wire the docs into the existing review loop so they stay in sync with the codebase. The phase delivers:

1. A new `docs/internals/` tree with a high-level overview of AgentLinux + per-component deep-dives.
2. A project-scoped Claude Code skill (`.claude/skills/dev-docs/`) that documents the docs contract.
3. A new reviewer agent (`.claude/agents/dev-docs-auditor.md`) that the existing review loop invokes when relevant code changes — no new stop-hook is added.
4. CLAUDE.md updates wiring the new reviewer into the "Review Loop" routing table.
5. A short pointer from the top-level README to `docs/internals/`.

The phase does NOT cover: end-user usage docs (those live in README), line-by-line source annotation, or new stop-hooks (the existing `review-reminder.sh` already triggers the review loop and is the single chokepoint per ADR-010 refinement).

</domain>

<decisions>
## Implementation Decisions

### Documentation Scope & Format

- **Audience:** primarily the project owner; secondarily future contributors. Tone is product-first ("what value does AgentLinux add for X"), technical-second.
- **Structure:** one high-level overview doc explaining what AgentLinux is + per-component deep-dives. Each component answers: what problem it solves, why bundled in AgentLinux, value vs the naive (raw `npm install`, ad-hoc shell, etc.) approach.
- **Depth:** high-level concepts only. Do **not** cross-link to source files (`file_path:line`) or ADRs in this layer — that level of detail is too deep for the intended audience. Component docs may reference an ADR by name in prose if it materially explains the "why," but no link discipline is required.
- **Diagrams:** Mermaid diagrams are allowed but used sparingly — only when a diagram genuinely illustrates a concept (e.g. install-time sequence, agent-user permission topology). Skip diagrams for components where prose is clearer.
- **Reuse signal:** treat the docs as a source of insights for blog posts, marketing emails, and the `agentlinux.org` landing page. Each component doc should be excerptable into product copy.

### Documentation Layout

- **Top-level dir:** `docs/internals/` — sibling to `docs/decisions/`, `docs/research/`, `docs/audits/` (matches existing convention).
- **Entry doc:** `docs/internals/README.md` — opens with "What AgentLinux is" + value proposition, then a TOC linking to component docs.
- **Per-component files:** one per surface — `installer.md`, `agent-user.md`, `nodejs-runtime.md`, `sudo-drop-in.md`, `claude-code.md`, `gsd.md`, `playwright.md`, `registry-cli.md`, `catalog.md`. Each follows the same shape: problem → AgentLinux's answer → value vs the naive approach.
- **Top-level README discoverability:** add a short "Why AgentLinux — concepts" section in the root `README.md` linking into `docs/internals/`.

### Maintenance Tooling — Skill, Reviewer, CLAUDE.md (NO new hook)

- **No new stop-hook.** The existing `.claude/hooks/review-reminder.sh` already nudges Claude to run the review loop before stopping. Adding a third hook would multiply ADR-010 reminder noise. Embed the docs check inside the review loop instead.
- **New reviewer agent:** `.claude/agents/dev-docs-auditor.md` — sibling to the six existing reviewers (bash-engineer, node-engineer, security-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor). Read-only tools (Read, Grep, Glob, Bash). Responsibility: when changes touch `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, or `packaging/curl-installer/`, the agent checks that the affected component's `docs/internals/<component>.md` is still accurate, and flags missing or stale sections. Skips on pure refactors, typos, comment-only changes, and `.planning/`-only changes.
- **New skill:** `.claude/skills/dev-docs/SKILL.md` — documents the docs contract (per-component file structure, product-perspective lens, when to update, what each doc must contain). The dev-docs-auditor reads this skill the same way other reviewers consult their topic skills.
- **CLAUDE.md wiring:** extend the existing "Review Loop" section's reviewer-by-file-type table with `dev-docs-auditor` for `plugin/` source changes. No new top-level CLAUDE.md section is required — keeping the wiring inside the existing Review Loop routing keeps the surface flat.

### Claude's Discretion

- Exact filenames inside `docs/internals/` (slug spelling, ordering in the TOC) — implementer's call as long as the per-surface split is honored.
- Whether and where Mermaid diagrams appear — implementer judges per component.
- Exact prose templates for component docs (the "problem → answer → value vs naive" shape is the contract, not the formatting).
- Reviewer agent system-prompt phrasing — match the tone and structure of the existing six reviewers.
- Whether to capture this design as an ADR — recommended (`ADR-015-developer-internals-docs.md`) so future readers know why there's no new hook, but not strictly required.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- Review-loop infrastructure (`.claude/skills/review/SKILL.md`, `.claude/hooks/review-reminder.sh`, the six existing reviewer agents under `.claude/agents/`) is the integration target — no new hook plumbing needed.
- Docs tree convention is already in place: `docs/decisions/` (ADRs), `docs/research/`, `docs/audits/`, `docs/proposals/`, `docs/reviews/`, `docs/HARNESS.md` (top-level harness spec), `docs/STABILITY-MODEL.md`, `docs/README.md`. Adding `docs/internals/` slots cleanly into this layout.
- Existing skills under `.claude/skills/` (`agentlinux-installer/`, `behavior-test-contract/`, `catalog-schema/`, `qemu-harness/`, `review/`, `workspace-cleanup/`) are the structural template for the new `dev-docs/` skill.
- ADR-010 (review loop via CLAUDE.md) and its 2026-05-02 refinement (allowing reminder hooks with `stop_hook_active` guard) provide the precedent for the integration approach — and the rationale for *not* adding a third reminder hook.

### Established Patterns

- Project-scoped reviewers live under `.claude/agents/<name>.md` with frontmatter declaring tool whitelist; bodies follow a stable shape (Role / Inputs / Checks / Output format).
- Skills under `.claude/skills/<name>/SKILL.md` document a contract that an agent or the main loop reads at decision time.
- CLAUDE.md "Review Loop" section is the single source of truth for which reviewers run on which file types — adding a row there is the canonical wiring.
- Stop-hook reminders both implement the ADR-010 refinement: `stop_hook_active` guard (no recursion) + clear instruction text + skip conditions documented inline. The existence of two hooks (review + session-tracker) is intentional and the user has explicitly drawn the line at "no third hook."

### Integration Points

- New reviewer agent → registered by adding to `.claude/agents/` with the agreed tool whitelist; CLAUDE.md "Review Loop" table grows one row.
- New skill → `.claude/skills/dev-docs/SKILL.md` + entry in CLAUDE.md "Pointers" list (already enumerates the other project-scoped skills).
- New docs tree → `docs/internals/README.md` as index; top-level `README.md` gets a "Why AgentLinux — concepts" link.
- No changes to `.claude/settings.json` (no new hook to register).
- No changes to `tests/` (this phase ships content + tooling, not behavior).

</code_context>

<specifics>
## Specific Ideas

- The motivating question shape from AL-22 is the litmus test for the docs: *"What value does AgentLinux provide in installing GSD instead of using the GSD installation from npm directly?"* The docs must give the project owner an answer in <60 seconds.
- Component docs are explicitly intended to double as raw material for blog posts, marketing emails, and the `agentlinux.org` landing page — keep prose excerpt-friendly.
- The user pushed back on overcomplicated tooling: do NOT introduce a separate stop-hook. Embed the docs-sync enforcement inside the existing review loop via a new reviewer agent. This reuse pattern is the design centerpiece of the phase.

</specifics>

<deferred>
## Deferred Ideas

- Source-code cross-references (`file_path:line` deep links) — out of scope for the initial cut; revisit if/when the docs grow stale and we need a stronger link discipline.
- ADR cross-references in prose — out of scope; component docs may name an ADR if it explains the "why," but no link discipline is required.
- Auto-generated diagrams from source — not pursued; Mermaid is hand-authored where genuinely useful.
- Documentation site (mdBook, Docusaurus, GitHub Pages docs) — out of scope; markdown in the repo is sufficient for the project owner's stated goal.
- A pre-commit hook that hard-blocks commits touching `plugin/` without `docs/internals/` updates — explicitly rejected (would block legitimate refactors and typos).
- End-user-facing usage docs — covered by README + curl-installer docs; out of scope here.

</deferred>
