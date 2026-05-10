---
name: dev-docs
description: Use when the task touches plugin/bin/, plugin/lib/, plugin/provisioner/, plugin/cli/src/, plugin/catalog/, or packaging/curl-installer/ — verify the matching docs/internals/<component>.md is still accurate. Documents the four-section contract (problem -> answer -> value vs naive -> related), the source-path -> doc-path dispatch table, the product-perspective lens (the AL-22 litmus question), and the explicit decision to NOT add a stop-hook for docs sync. Grows when new top-level surfaces land under plugin/ in future milestones.
---

# dev-docs — docs/internals/ contract for AgentLinux developer docs

**Status:** Active. Established in Phase 12 (DOC-01..DOC-07). The `docs/internals/` tree shipped 9 component docs alongside this skill and the `dev-docs-auditor` reviewer.

Authoritative spec: `docs/HARNESS.md` §4 (review loop) + this skill body. Decisions: ADR-010 (review loop via CLAUDE.md, refined 2026-05-02 to allow reminder hooks with `stop_hook_active` guard) — and the deliberate Phase 12 decision to NOT add a third reminder hook (recorded in `docs/decisions/015-developer-internals-docs.md`, lands in Phase 12 Plan 05).
Requirements this skill helps enforce: DOC-01 (index doc), DOC-02 (component docs), DOC-03 (reviewer agent registered), DOC-04 (skill exists), DOC-05 (top-level discoverability), DOC-06 (no new hook), DOC-07 (ADR captures the design).

## When to use this skill

Use when the task touches any file under:

- `plugin/bin/agentlinux-install` — installer entrypoint -> `docs/internals/installer.md`.
- `plugin/lib/*.sh` — shared bash helpers -> `docs/internals/nodejs-runtime.md` (PATH/as_user) or `installer.md` (logging/idempotency).
- `plugin/provisioner/*.sh` — ordered installer steps -> dispatch by step (see table below).
- `plugin/cli/src/**` — the registry CLI source -> `docs/internals/registry-cli.md`.
- `plugin/catalog/{schema,catalog}.json` — the catalog data model -> `docs/internals/catalog.md`.
- `plugin/catalog/agents/<name>/*` — per-agent recipes -> `docs/internals/<name>.md`.
- `packaging/curl-installer/install.sh` — the curl-pipe-bash entrypoint -> `docs/internals/installer.md`.

Or when authoring or reviewing any file under `docs/internals/`.

## Why this exists (DOC-02, AL-22)

The `docs/internals/` tree is the project owner's 60-second answer to "what value does AgentLinux provide for surface X" (the AL-22 litmus question). It's the source of insight for blog posts, marketing emails, and the agentlinux.org landing page (CONTEXT §"Reuse signal"). For the docs to stay useful, they must stay in sync with the source — which means a contract for what each doc contains, a dispatch table mapping source paths to docs, and a reviewer (`dev-docs-auditor`) that checks the contract on relevant PRs. This skill owns all three.

## Per-component file structure (the four-part contract)

Every `docs/internals/<component>.md` has four mandatory H2 sections:

1. `## The problem` — what a developer hits without AgentLinux when reaching for this surface.
2. `## What AgentLinux does` — the mechanics in product terms (not line-by-line code).
3. `## Value vs the naive approach` — the trade-off, written as a numbered list with **bold lead clause** items, excerpt-friendly for blog/marketing copy.
4. `## Related` — bulleted cross-links to sibling internals docs, top-level README, and (optionally) ADRs.

Optional fifth section: `## Worked example` — a fenced shell session with realistic prompts and truncated output. Include only when prose alone leaves the mechanics ambiguous; drop when prose suffices.

Tone: product-perspective, project-owner audience first, future contributor second. The opening lede (3-5 lines under the H1) sets the value proposition in plain prose before any H2.

## Source-path -> doc-path dispatch table

The `dev-docs-auditor` reviewer reads this table to decide which component doc a source change implicates.

| Source path glob | Component doc |
|---|---|
| `packaging/curl-installer/install.sh`, `plugin/bin/agentlinux-install` | `docs/internals/installer.md` |
| `plugin/provisioner/10-agent-user.sh` | `docs/internals/agent-user.md` |
| `plugin/provisioner/20-sudoers.sh` | `docs/internals/sudo-drop-in.md` |
| `plugin/provisioner/30-nodejs.sh`, `plugin/provisioner/40-path-wiring.sh`, `plugin/lib/as_user.sh` | `docs/internals/nodejs-runtime.md` |
| `plugin/catalog/agents/claude-code/*` | `docs/internals/claude-code.md` |
| `plugin/catalog/agents/gsd/*` | `docs/internals/gsd.md` |
| `plugin/catalog/agents/playwright-cli/*`, `plugin/catalog/agents/playwright/*` | `docs/internals/playwright.md` |
| `plugin/cli/src/**`, `plugin/provisioner/50-registry-cli.sh` | `docs/internals/registry-cli.md` |
| `plugin/catalog/schema.json`, `plugin/catalog/catalog.json` | `docs/internals/catalog.md` |
| `plugin/lib/log.sh`, `plugin/lib/idempotency.sh`, `plugin/lib/distro_detect.sh` | `docs/internals/installer.md` (shared installer infrastructure) |

When a new top-level surface lands under `plugin/` (a new provisioner step, a new CLI command class, a new catalog backend), this table grows AND a new `docs/internals/<surface>.md` ships in the same PR.

## When to update

**Update the matching component doc when:**

- The source change alters observable behavior described in `## What AgentLinux does` (e.g. install path moves, default version changes, a flag is added or removed).
- The source change invalidates a claim in `## The problem` or `## Value vs the naive approach` (e.g. a new naive alternative appears, or an old one is no longer the dominant path).
- A new top-level surface lands — a new component doc ships in the same PR and the index TOC grows.

**Skip docs update for:**

- Pure refactors that don't change observable behavior (rename, extract function, reformat).
- Comment-only or typo-only changes.
- Whitespace / formatting-only diffs.
- Test-only changes that don't touch `plugin/` source paths.
- `.planning/`-only changes.
- `docs/`-only changes (covered by `technical-writer` and `fact-checker`).

The `dev-docs-auditor` reviewer enforces both columns at review time.

## Product-perspective lens (the AL-22 litmus test)

The litmus question for every component doc is: *"What value does AgentLinux provide in installing GSD instead of using the GSD installation from npm directly?"* — generalised to the component at hand. The doc must answer it in <60 seconds for a project owner reading on first arrival.

Concretely:

- Lead with the value, not the implementation. "AgentLinux gives the agent its own user with its own npm prefix, so self-update Just Works" beats "AgentLinux runs `useradd agent --shell /bin/bash` and writes `~/.npmrc` with `prefix=$HOME/.npm-global`."
- Implementation detail belongs in `## What AgentLinux does` (still product-framed); never in the lede.
- Tool names (`Commander.js`, `ajv`, `bats`) are implementation; the value frame is the verb the user gets (`agentlinux install <name>`, "schema-validated catalog," "behavior-test contract"). Tool names may appear as supporting detail; they must not lead.
- The `## Value vs the naive approach` section is the most excerpt-heavy part of every doc — it lifts directly into blog posts and marketing copy. Keep it numbered, **bold lead clause** style.

## Why no new stop-hook (DOC-06)

AgentLinux already has two reminder hooks (`.claude/hooks/review-reminder.sh` and `.claude/hooks/session-tracker-reminder.sh`), both wired per the ADR-010 2026-05-02 refinement (reminder hooks with a `stop_hook_active` one-shot guard are allowed; reviewer-invoking hooks remain rejected).

Adding a third hook for docs/internals/ sync would multiply reminder noise without adding value: the existing `review-reminder.sh` already nudges Claude to run the review loop, and the review loop already routes plugin/ changes to the `dev-docs-auditor` per the CLAUDE.md "Review Loop" routing table. The dev-docs check rides inside the existing review loop; no new hook is needed. ADR-015 (lands in Phase 12 Plan 05) records this decision in full.

## Growth plan

- **Phase 12 (this phase):** Skill ships alongside the 9 initial component docs and the `dev-docs-auditor` reviewer. This skill carries the dispatch table and the four-section contract.
- **Future milestones — new components added under `plugin/`:** Each new top-level surface (a new provisioner step, a new CLI command class, a new catalog backend, a new agent in the catalog) ships its own `docs/internals/<surface>.md` in the same PR and adds a row to the dispatch table here.
- **Future milestones — if drift becomes a real problem:** The skill may absorb a stronger link discipline (e.g. mandated ADR cross-references in the Related footer). Currently out of scope per CONTEXT §"Deferred Ideas."
- **Future milestones — if the docs grow:** Consider a documentation site (mdBook, Docusaurus). Currently out of scope per CONTEXT §"Deferred Ideas" — markdown in the repo is sufficient for the project owner's stated goal.

## Related

- `docs/internals/README.md` — the docs/internals/ index (DOC-01).
- `docs/internals/<component>.md` — the 9 component docs (DOC-02).
- ADRs: 010 (review loop via CLAUDE.md, refined 2026-05-02), 015 (developer internals docs — no new hook decision; lands in Plan 05).
- Subagents: `dev-docs-auditor` (the reviewer this skill backs).
- Sibling skills: `agentlinux-installer`, `behavior-test-contract`, `catalog-schema`, `qemu-harness`, `review`, `workspace-cleanup`.
- Top-level pointers: `CLAUDE.md` "Review Loop" section (where the reviewer is wired) and "Pointers" section (where this skill is enumerated). Both are updated in Phase 12 Plan 04.
