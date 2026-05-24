# Phase 12: Developer documentation for installer, runtime, and CLI (AL-22) — Pattern Map

**Mapped:** 2026-05-09
**Files analyzed:** 13 (11 new + 2 modified)
**Analogs found:** 13 / 13

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `docs/internals/README.md` | docs-index | reference | `docs/README.md` | exact |
| `docs/internals/installer.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/agent-user.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/nodejs-runtime.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/sudo-drop-in.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/claude-code.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/gsd.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/playwright.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/registry-cli.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `docs/internals/catalog.md` | docs-component | reference | `docs/STABILITY-MODEL.md` | role-match |
| `.claude/agents/dev-docs-auditor.md` | reviewer-agent | review | `.claude/agents/catalog-auditor.md` | exact |
| `.claude/skills/dev-docs/SKILL.md` | skill | reference | `.claude/skills/catalog-schema/SKILL.md` | exact |
| `CLAUDE.md` (modify) | project-instructions | reference | existing CLAUDE.md §Review Loop + §Pointers | self |
| `README.md` (modify) | project-readme | reference | existing README.md §Stability model + §Links | self |

**Why STABILITY-MODEL.md over HARNESS.md / ADRs:** STABILITY-MODEL is the single closest single-topic concept doc in the repo today — short (~125 lines), product-first ("here's what AgentLinux does for you and why"), opens with a TL;DR, ends with cross-links. The internals docs aim for the same shape (problem → AgentLinux's answer → value vs naive). HARNESS.md is structurally heavier (numbered §1..§8 sections, table-shaped, internal-only); ADRs are explicitly decision-shaped (Context / Decision / Consequences) which is the wrong frame for a product-perspective concept doc.

## Pattern Assignments

### `docs/internals/README.md` (docs-index)

**Analog:** `docs/README.md`

**Top-level shape** (lines 1-21, the entire file):
```markdown
# AgentLinux Documentation

This directory holds all reference documentation. `.planning/` holds GSD workflow
state (plans, STATE.md, config) — not documentation. If the output of a task is
a document intended to be read later (ADR, research report, design proposal,
review summary), it goes here.

## Layout

- `HARNESS.md` — authoritative project harness spec (§1 layout, §2 docs,
  §3 systems access, §4 review loop, §5 skills, §6 CLAUDE.md, §7 checklist,
  §8 success criteria).
- `decisions/` — Architecture Decision Records (ADRs). ADR-001..ADR-010 seeded
  in Phase 1 per `HARNESS.md` §2.3. New ADRs land as decisions resolve.
- ...
```

**Pattern to copy:** H1 title → one-paragraph "what this dir is and is not" → `## Layout` section with bullet-list of files where each bullet has the filename + one-sentence one-line description. Hyphenated descriptions, not multi-paragraph.

**Adaptation for `docs/internals/README.md`:** The CONTEXT.md spec calls for "What AgentLinux is + value proposition, then a TOC linking to component docs." Per CONTEXT §"Documentation Layout," opens with a value-proposition paragraph (not a "what this dir is not" paragraph), then a `## Components` (or similar) TOC. So the pattern is **borrow the linkable-bullet TOC shape** from `docs/README.md`, but **replace the "what this is not" lede** with a product-first "What AgentLinux is" paragraph.

---

### `docs/internals/installer.md` (and the eight other component docs)

**Analog:** `docs/STABILITY-MODEL.md`

**Frontmatter / lede pattern** (lines 1-9):
```markdown
# AgentLinux Stability Model

> The TL;DR of [ADR-011](decisions/011-stability-first-version-pinning.md).

AgentLinux ships *curated combos*: every catalog agent is pinned to an exact
version that we test together end-to-end before each release. You install one
combo and everything just works. When you want to run ahead of the curated
pin, you can — and `agentlinux upgrade` + `agentlinux pin` give you a clean
way to reconcile.
```

**Pattern to copy:** H1 → optional one-line italicized cross-reference (CONTEXT says no link discipline required; an ADR mention in prose is OK but not as a `> The TL;DR of …` line) → 3-5 line plain-prose lede that answers "what is this thing for" in product voice.

**Section-flow pattern** (the H2 spine of STABILITY-MODEL.md):
```markdown
## What's a curated combo                  → "the thing itself" / definition
## The three divergence states              → "how it behaves" / mechanics
## Worked example: "I ran `claude update`"  → concrete scenario w/ shell session
## Escape hatch: `agentlinux pin`           → adjacent flexibility surface
## Why pin at all (the trade-off)           → rationale / value vs naive
## Related                                   → cross-links footer
```

**Adaptation for component docs:** CONTEXT §"Documentation Scope & Format" mandates "problem → AgentLinux's answer → value vs the naive approach" as the structural contract. Map STABILITY-MODEL's spine to that contract:

| CONTEXT contract slot | Suggested H2 (analog source) |
|---|---|
| Problem | `## The problem` (no analog; new) |
| AgentLinux's answer (mechanics) | `## What AgentLinux does` (mirrors STABILITY-MODEL's "What's a curated combo" + "The three divergence states") |
| Worked example | `## Worked example` (mirrors STABILITY-MODEL's "I ran `claude update`" — keep the shell-session-with-prompts shape) |
| Value vs naive | `## Value vs the naive approach` (mirrors STABILITY-MODEL's "Why pin at all (the trade-off)") |
| (optional) Adjacent surface | only if genuinely useful |
| Cross-links | `## Related` (footer with bullet list, exact STABILITY-MODEL shape) |

**Worked-example shape** (STABILITY-MODEL.md lines 51-74):
~~~markdown
## Worked example: "I ran `claude update`"

The canonical path. Claude Code ships with its own self-updater that writes
into the agent-owned install tree — that is the whole point of AgentLinux
(AGT-02). After `claude update`, the curated pin and the installed version
disagree; `agentlinux upgrade` surfaces the diff rather than silently
overwriting your choice:

```
$ claude update                               # Claude Code's own updater
✓ Claude Code 2.1.114 installed

$ agentlinux upgrade
Per-agent divergence (report-only; pass --reset-all-curated or per-agent
choice to mutate):
...
```
~~~

**Pattern to copy:** prose framing → fenced shell session with realistic prompts (`$ cmd` lines + truncated output) → no post-explanation needed when the session itself reads. Each component doc gets one or two of these (or none, if prose suffices).

**Trade-off / "value vs naive" pattern** (STABILITY-MODEL.md lines 97-115):
```markdown
## Why pin at all (the trade-off)

Without pinning, AgentLinux would be a thin wrapper around `npm install -g`.
Two problems:

1. **It provides no value over what users could do themselves.** Running
   `sudo -u agent -H npm install -g <pkg>` by hand is a one-liner. A CLI
   that only forwards the call adds no product surface.
2. **Upstream instability hits users immediately.** Claude Code, GSD, and
   Playwright publish daily-to-weekly...

Pinning is the explicit contract: **we test exactly what we ship, and you
decide when to move.**
```

**Pattern to copy:** Lede sentence framing the naive alternative ("Without X, AgentLinux would be Y") → numbered list of 2-3 problems with the naive approach, **bold-leading-clause** style (`**It provides no value...**` then explanation) → bold one-line resolution sentence. This is the AL-22 litmus test ("What value does AgentLinux provide installing GSD vs `npm install` directly?") rendered as a doc pattern. Excerpt-friendly per CONTEXT §"Reuse signal" — each numbered item lifts cleanly into blog/marketing copy.

**Cross-links footer pattern** (STABILITY-MODEL.md lines 117-124):
```markdown
## Related

- [ADR-011 — Stability-first version pinning with explicit reconciliation](decisions/011-stability-first-version-pinning.md)
  — the full decision record, including considered alternatives (private
  apt/dpkg repo, Nix-style symlink profiles, thin-wrapper baseline).
- [ADR-006 — curl-pipe-bash primary + optional .deb distribution](decisions/006-curl-pipe-bash-plus-deb.md)
  — how the release tarball + catalog snapshot + SHA256 sidecar get to users.
- [README.md](../README.md) — the top-level install + verify story.
```

**Pattern to copy:** Markdown link as bullet head + em-dash + one-line explanation of what's there. Three to five entries. Per CONTEXT §"Depth": **do not cross-link to source files (`file_path:line`)** — only ADRs, sibling internals docs, README. A doc may *name* an ADR in prose but linking is optional.

**Mermaid usage** (CONTEXT §"Diagrams"): no analog in STABILITY-MODEL.md (it's prose-only). CONTEXT explicitly says use sparingly — only when a diagram genuinely illustrates (install-time sequence, agent-user permission topology). The executor's call per CONTEXT §"Claude's Discretion."

---

### `.claude/agents/dev-docs-auditor.md` (reviewer-agent)

**Analog:** `.claude/agents/catalog-auditor.md` (closest match — has the same "audits a specific surface for drift" flavor as the new agent's intended job)

**Frontmatter pattern** (lines 1-5):
```markdown
---
name: catalog-auditor
description: Reviews AgentLinux catalog entries and per-agent install recipes for JSON Schema validity, privilege-drop correctness (as_user usage, no sudo npm install -g), symmetric uninstall paths, and absence of /usr/local shim patterns. Use on any change under plugin/catalog/agents/*, plugin/catalog/catalog.json, plugin/catalog/schema.json, or plugin/cli/scripts/validate-catalog.mjs.
tools: Read, Grep, Glob, Bash
---
```

**Pattern to copy:**
- Triple-dash YAML frontmatter
- `name:` matches the filename slug (kebab-case)
- `description:` is one long sentence — first half states the review focus and rubric domain; second half is `Use on/when …` with the exact path globs that should trigger this reviewer. Keep paths concrete (CONTEXT lists them: `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, `packaging/curl-installer/`).
- `tools:` is **read-only** for review usage: `Read, Grep, Glob, Bash` — no `Write` / `Edit`. (Same as all six existing reviewers.)

**Body section spine** (catalog-auditor.md H2s):
```markdown
# Catalog Auditor                            (H1: Title-Case role name)

[1-2 sentence opener: who I am, what I review, what makes this surface special]

## When to spawn                              [bullet list of file globs]
## What to look for                           [numbered rubric, 6-8 items]
## Common gotchas (AgentLinux-specific)       [bullet list of pitfalls]
## Validation workflow                         [optional: numbered shell-step list]
## Output format                              [free-form summary contract + example]
```

The same H2 spine appears in `bash-engineer.md`, `node-engineer.md`, `qa-engineer.md`, `security-engineer.md`. The `behavior-coverage-auditor.md` variant adds an `## Exit behavior` section because it gates phase close — `dev-docs-auditor` does not gate, so omit that H2.

**Opener pattern** (catalog-auditor.md lines 7-9):
```markdown
# Catalog Auditor

Project-scoped review subagent for the AgentLinux agent catalog. The catalog is the opt-in agent registry — it ships claude-code, gsd, and playwright as *available* (CAT-01), none installed by default (CAT-02), validated against a published JSON Schema (CAT-03). This auditor verifies the machine-readable contract and the per-agent install recipes that implement it.
```

**Pattern to copy:** Sentence 1 = "Project-scoped review subagent for X." Sentence 2 = one-line context on why X matters (with requirement IDs cited inline). Sentence 3 = what the auditor verifies. Three sentences max.

**`## When to spawn` pattern** (catalog-auditor.md lines 11-19):
```markdown
## When to spawn

- Any change under `plugin/catalog/agents/<name>/install.sh` or `plugin/catalog/agents/<name>/remove.sh`.
- Any change under `plugin/catalog/agents/<name>/recipe.json` (per-agent catalog metadata).
- Any change to `plugin/catalog/catalog.json` (the embedded agent list).
- Any change to `plugin/catalog/schema.json` (the JSON Schema — breaking changes need an ADR).
- Any change to `plugin/cli/scripts/validate-catalog.mjs` (the validator that gates the pre-commit hook and CI).
- When a **new agent is added** to the catalog — full pass on the new entry + its install/remove scripts.
```

**Pattern to copy:** Each bullet starts with "Any change under/to" + path + parenthetical clarifier. Last bullet often expresses a categorical condition (e.g. "When X is added"). For `dev-docs-auditor` the bullets enumerate the source paths from CONTEXT §"New reviewer agent": `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`, `plugin/catalog/`, `packaging/curl-installer/`. Plus the **skip-conditions** from CONTEXT (pure refactors, typos, comment-only changes, `.planning/`-only changes) which can either go in `## When to spawn` as "Skip when…" inverse bullets or in their own `## When NOT to spawn` H2 (the latter is cleaner — see `workspace-cleanup` skill's `## What this skill never does` for the inverse-list precedent).

**`## What to look for` rubric pattern** (catalog-auditor.md lines 21-35, numbered 1-8):
```markdown
## What to look for

Rubric (copy-of-truth from `docs/HARNESS.md` §4.2):

1. **JSON Schema validity.** Every entry in `plugin/catalog/catalog.json` AND every `recipe.json`...
2. **`as_user` helper usage in every `install.sh`.** Every catalog `install.sh` must source `plugin/lib/as_user.sh`...
3. **Symmetric uninstall path.** For every `install.sh`, a sibling `remove.sh` MUST exist that undoes...
```

**Pattern to copy:** Lede line "Rubric (copy-of-truth from `docs/HARNESS.md` §4.2):" → numbered list with **bold lead-clause** (the rule name) followed by a multi-sentence explanation of the rule + how to verify it. 6-8 items per reviewer is the convention. For `dev-docs-auditor`, candidate rubric items distilled from CONTEXT:

1. **Component coverage.** Every changed source path under `plugin/{bin,lib,provisioner,cli/src,catalog}/` or `packaging/curl-installer/` must map to a `docs/internals/<component>.md` (registry per the dispatch table the skill defines). A change with no matching component doc is a flag.
2. **Doc freshness.** The component doc still describes what the source actually does (problem → answer → value spine still valid; no stale claims like "uses npm" when the implementation now uses something else).
3. **Skip conditions honored.** Pure refactors, comment-only changes, typo fixes, formatting-only diffs do not require docs updates — flag in the skip column, not the action column.
4. **Product-perspective lens.** The doc still answers "what value does AgentLinux add" — not "here is the line-by-line implementation."
5. **No source cross-references.** Per CONTEXT §"Depth," `file_path:line` deep links are out of scope for this layer.
6. **TOC in `docs/internals/README.md` updated** when a new component doc is added or removed.

**`## Output format` pattern** (catalog-auditor.md lines 56-77):
~~~markdown
## Output format

Free-form summary per HARNESS.md §4.3. File:line citations. Begin with validator result (`validate-catalog.mjs` exit code) then list findings by severity.

Example:

```
## catalog-auditor review summary

Files reviewed: plugin/catalog/agents/claude-code/install.sh, plugin/catalog/agents/claude-code/recipe.json

Validator: `node plugin/cli/scripts/validate-catalog.mjs` → exit 0 (all recipes valid).

Findings:
- plugin/catalog/agents/claude-code/install.sh:14 — `sudo npm install -g @anthropic-ai/claude-code`. Critical. Replace with `as_user agent npm install -g @anthropic-ai/claude-code`. ...
```

Two blockers (sudo-npm, /usr/local shim), one missing file, one metadata gap.
~~~

Main agent triages; reviewer documents.
```

**Pattern to copy:** "Free-form summary per HARNESS.md §4.3" boilerplate → "File:line citations" → optional reviewer-specific opening line (validator result, etc) → fenced example block titled `## <reviewer-name> review summary` → `Files reviewed:` line → `Findings:` bulleted list with `path:line — <one-sentence finding>. <one-sentence severity/fix>.` → trailing one-line summary line → outside the fence: `Main agent triages.` (closing motto, present in every existing reviewer).

---

### `.claude/skills/dev-docs/SKILL.md` (skill)

**Analog:** `.claude/skills/catalog-schema/SKILL.md` (closest match — same shape: a skill that owns a contract a reviewer reads at decision time, plus a "growth plan" footer)

**Frontmatter pattern** (lines 1-4):
```markdown
---
name: catalog-schema
description: Use when adding, modifying, or validating a catalog entry under plugin/catalog/. Documents the JSON Schema layout, required fields, install.sh/uninstall.sh contract, symmetric uninstall (CLI-04), the "no agents installed by default" invariant (CAT-02), and the convention for adding a new agent without touching CLI source (CAT-03). Every install recipe runs via as_user — never sudo npm install -g. Grows once the schema is finalized in Phase 4.
---
```

**Pattern to copy:**
- Triple-dash frontmatter, only two keys: `name:` (kebab-case, matches dirname) and `description:` (one long sentence + a second optional sentence).
- The description sentence pattern: `Use when X. Documents Y. <Most-important rule one-liner>. Grows <when>.` Last clause is the growth signal — appears in all four other skill files.
- No `tools:` key on skill frontmatter (skills are not subagents — they document conventions, not invoked actions).

**Body section spine** (catalog-schema/SKILL.md H2s):
```markdown
# catalog-schema — Catalog entry format          (H1: <slug> — <one-line title>)

**Status:** Skeleton. ...                         (Status block, single bold line)

Authoritative spec: `docs/HARNESS.md` §...        (one-line cross-link sentence)
Decisions: ADR-XXX (...).                          (one-line ADR enumeration)
Requirements this skill helps enforce: ...         (one-line requirement-ID enumeration)

## When to use this skill                         [bullet list of file globs]
## Why this exists ([REQ-ID])                     [paragraph naming the requirement this skill backs]
## Current ([phase]) <topic>                      [code/json block + bullet explanations]
## <topic-specific section>                       [varies — schema fields, install contract, etc]
## <topic-specific section>                       [more]
## Growth plan                                    [bulleted phase-by-phase plan]
## Related                                        [bulleted cross-links footer]
```

The same skeleton appears in `agentlinux-installer/SKILL.md`, `behavior-test-contract/SKILL.md`, `qemu-harness/SKILL.md`. `review/SKILL.md` is the closest *operational* (vs *contract*) skill — slightly different shape (it has a `## Dispatch rules` table + `## Triage rules` instead of `## Why this exists`).

**`## When to use this skill` pattern** (catalog-schema/SKILL.md lines 12-21):
```markdown
## When to use this skill

Use when the task touches any file under:

- `plugin/catalog/schema.json` — the JSON Schema.
- `plugin/catalog/catalog.json` — the catalog manifest (arrives Phase 4).
- `plugin/catalog/agents/<name>/install.sh` — per-agent install recipe.
- `plugin/catalog/agents/<name>/remove.sh` — per-agent symmetric uninstall.
...
```

**Pattern to copy:** "Use when the task touches any file under:" lede → bullet list of `path` + em-dash + one-line description. (Same shape as the reviewer-agent's `## When to spawn` but framed as a use-when-skill rather than spawn-on-trigger.)

**`## Growth plan` pattern** (catalog-schema/SKILL.md lines 91-95):
```markdown
## Growth plan

- **Phase 4:** Finalizes the schema, adds the three real entries (claude-code, gsd, playwright), upgrades `validate-catalog.mjs` to ajv, and ships the first install+remove recipes. This skill absorbs the final field list and concrete `install.sh` / `remove.sh` templates.
- **Phase 5:** First AGT-XX tests exercise every recipe. This skill adds the "what a working install.sh looks like" example section.
- **v0.4+:** Multiple install backends per entry...
```

**Pattern to copy:** `- **Phase N:** <what lands>. This skill absorbs/adds <what>.` — pairs each phase's deliverable with the skill content that gets unlocked. For `dev-docs/SKILL.md`, growth-plan entries naturally map to: future component docs as new `plugin/` modules land (e.g. mutation harness in v0.4, new agents added to catalog).

**`## Related` footer pattern** (catalog-schema/SKILL.md lines 97-103):
```markdown
## Related

- `docs/HARNESS.md` §1.1 (plugin/catalog/ layout), §5.2 (skill table), §4.2 (catalog-auditor + security-engineer rubrics).
- ADRs: 003 (no default agents), 004 (per-user npm prefix), 008 (Commander.js CLI that consumes this catalog).
- Subagents: `catalog-auditor` (every catalog PR), `security-engineer` (install-recipe injection review).
- Sibling skills: `agentlinux-installer` (...), `behavior-test-contract` (...), `qemu-harness` (...).
- Validator: `plugin/cli/scripts/validate-catalog.mjs`.
```

**Pattern to copy:** Bulleted list grouped by category — HARNESS pointers, ADRs by number, subagents that consume this skill, sibling skills, scripts/files. Each line has the reference + parenthetical context. For `dev-docs/SKILL.md`, the categories trivially become: HARNESS pointers, ADR (014 may be added per CONTEXT §"Claude's Discretion"), Subagent (`dev-docs-auditor`, the new reviewer), sibling skills (`agentlinux-installer`, `catalog-schema`, `review`), top-level docs (`docs/internals/README.md`).

**Skill content (dev-docs-specific):** the skill body must enumerate the docs contract per CONTEXT §"Maintenance Tooling — Skill, Reviewer, CLAUDE.md (NO new hook)":

- Per-component file structure (file path + what each must contain — problem / answer / value vs naive / optional worked example / cross-links footer).
- Product-perspective lens (the AL-22 litmus test: "what value does AgentLinux add for X").
- When to update (when source changes meaningfully under the source-to-doc dispatch table; not on typos / refactors).
- What each doc must contain (the four-part contract from CONTEXT).
- The source-path → doc-path dispatch table (this is the registry the `dev-docs-auditor` reads).

---

### `CLAUDE.md` (modify)

**Analog:** the existing `CLAUDE.md` itself — specifically the `## Review Loop` table and the `## Pointers` bullet list.

**Existing `## Review Loop` table** (CLAUDE.md lines 53-59):
```markdown
Reviewers applied by file type:

- Bash → `bash-engineer`, `security-engineer`, `qa-engineer`
- TS/JS → `node-engineer`, `security-engineer`, `qa-engineer`
- Bats → `qa-engineer`, `behavior-coverage-auditor`
- Catalog recipes → `catalog-auditor`, `security-engineer`
- Docs → `technical-writer`, `fact-checker`
```

**Pattern to apply:** Per CONTEXT §"CLAUDE.md wiring" the new reviewer is wired by extending each existing row whose paths are under the dev-docs trigger set, not by adding a new "Internal docs" row. Concretely: the bullet shape is `- <file-type> → <comma-separated reviewer list>`. The `dev-docs-auditor` adds to:
- `Bash` (covers `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `packaging/curl-installer/`)
- `TS/JS` (covers `plugin/cli/src/`)
- `Catalog recipes` (covers `plugin/catalog/`)

So the modified rows look like:
```markdown
- Bash → `bash-engineer`, `security-engineer`, `qa-engineer`, `dev-docs-auditor`
- TS/JS → `node-engineer`, `security-engineer`, `qa-engineer`, `dev-docs-auditor`
- Catalog recipes → `catalog-auditor`, `security-engineer`, `dev-docs-auditor`
```

(`Bats` and `Docs` rows are left unchanged — bats tests do not have an internals doc; docs reviewers already exist.)

**Existing `## Pointers` bullet list** (CLAUDE.md lines 84-94):
```markdown
- `@.planning/ROADMAP.md` — phase plan (1 Harness → 2 Installer → 3 Node → 4 CLI → 5 Agents → 6 Release)
- `@.planning/REQUIREMENTS.md` — behavior contract (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC)
- `@docs/HARNESS.md` — authoritative harness spec (...)
- `@docs/research/v0.3.0/SUMMARY.md` — v0.3.0 research synthesis
- `@docs/decisions/` — ADR-001..ADR-010
- Skills (arrive Plan 01-04): `.claude/skills/agentlinux-installer/`,
  `.claude/skills/behavior-test-contract/`, `.claude/skills/catalog-schema/`,
  `.claude/skills/qemu-harness/`, `.claude/skills/review/`
```

**Pattern to apply:** Add a new bullet for the internals tree (e.g. `- @docs/internals/ — per-component developer docs (what each AgentLinux surface does and why)`) and extend the trailing `Skills (...)` bullet's enumeration with `.claude/skills/dev-docs/`. Keep bullet shape consistent (leading `@`-prefixed path for top-level pointers; flat path for the comma-separated skill enumeration).

---

### `README.md` (modify — top-level)

**Analog:** the existing `README.md` `## Stability model` section (lines 67-83) and `## Links` section (lines 136-143).

**Existing `## Stability model` lede** (README.md lines 67-82):
```markdown
## Stability model

AgentLinux ships *curated combos*: every catalog agent is pinned to an exact
version that we test together end-to-end (Docker × {22.04, 24.04, 26.04} +
QEMU × {22.04, 24.04, 26.04}) before each release. ...

See [docs/STABILITY-MODEL.md](docs/STABILITY-MODEL.md) for the user-facing
one-page summary and [docs/decisions/011-stability-first-version-pinning.md](docs/decisions/011-stability-first-version-pinning.md)
for the full architectural decision record.
```

**Pattern to apply** (per CONTEXT §"Top-level README discoverability" → "Why AgentLinux — concepts" link): Add a new H2 section `## Why AgentLinux — concepts` (or similar — header text is implementer's call per CONTEXT §"Claude's Discretion") modeled on the existing `## Stability model` shape: 2-3 line lede that names the concept-doc series, then a `See [docs/internals/README.md](docs/internals/README.md) for ...` line. Place above the existing `## Stability model` section so the conceptual story flows: install → verify → uninstall → **why** (internals) → stability model → escape hatches.

**Existing `## Links` section** (README.md lines 136-143):
```markdown
## Links

- **Source + issues:** https://github.com/Roo4L/Agent-Linux
- **Releases:** https://github.com/Roo4L/Agent-Linux/releases
- **Architecture decisions:** [docs/decisions/](docs/decisions/)
- **Test harness spec:** [docs/HARNESS.md](docs/HARNESS.md)
- **Stability model (user-facing):** [docs/STABILITY-MODEL.md](docs/STABILITY-MODEL.md)
- **Landing page:** https://agentlinux.org
```

**Pattern to apply:** Add a row `- **Internals (developer docs):** [docs/internals/](docs/internals/)` with the bold-label-em-dash-bracketed-link convention. Place it adjacent to the "Architecture decisions" row (both are repo-internal reference material).

---

## Shared Patterns

### Frontmatter discipline (reviewer agents and skills)

**Source:** `.claude/agents/*.md` (six files), `.claude/skills/*/SKILL.md` (six files)

**Apply to:** `.claude/agents/dev-docs-auditor.md`, `.claude/skills/dev-docs/SKILL.md`

```markdown
---
name: <kebab-case-slug-matching-filename>
description: <single long sentence stating focus + Use when/Use on/Use with directive with concrete path globs>
[tools: Read, Grep, Glob, Bash]    # subagents only — skills omit this key
---
```

The description must be one sentence that the Claude Code subagent dispatcher can match against a query. No Markdown inside frontmatter values. Keep ≤ 400 characters.

### "Free-form summary, no BLOCK/FLAG/PASS" output contract

**Source:** `docs/HARNESS.md` §4.3 → echoed in every reviewer's `## Output format` section.

**Apply to:** `.claude/agents/dev-docs-auditor.md` `## Output format`

The phrase to copy (verbatim, with reviewer name swapped):
```
Free-form summary per HARNESS.md §4.3. File:line citations, short sentences, no rigid BLOCK/FLAG/PASS scheme.
```

Followed by a fenced example block of `## dev-docs-auditor review summary` shape, ending with a one-line closing motto: `Main agent triages.` (or near equivalent — `Main agent triages; reviewer documents.` is the catalog-auditor variant).

### "Common gotchas (AgentLinux-specific)" section

**Source:** all six existing reviewer agents have this H2 with bulleted gotcha entries written in `**lead clause.** explanation` form.

**Apply to:** `.claude/agents/dev-docs-auditor.md`

For dev-docs the gotchas distill the CONTEXT §"Specifics" + §"Deferred Ideas" cautions, e.g.:
- **Source-line cross-references slipped in.** CONTEXT §"Depth" rules them out for the initial cut. Flag.
- **Implementation detail leaking through.** "Uses Commander.js" is wrong frame; "ships a registry CLI" is right frame. Product perspective trumps tool name.
- **A new component shipped without a doc.** When a new top-level surface lands under `plugin/` (new provisioner, new CLI command class, new catalog backend), the matching `docs/internals/<surface>.md` should ship in the same PR.

### Cross-link footer convention

**Source:** end of every existing reviewer, every existing skill, `docs/STABILITY-MODEL.md`.

**Apply to:** all 11 new docs files + `.claude/agents/dev-docs-auditor.md` + `.claude/skills/dev-docs/SKILL.md`.

`## Related` H2 → bullet list. Each bullet is `- [<readable name>](<path>) — <one-sentence what's there>`. Three to five entries. Per CONTEXT §"Depth": no `path:line` deep links in the docs/internals/ files; ADR mentions in prose are fine, links are optional.

## No Analog Found

None — every new file has a workable analog in the existing codebase. The `docs/internals/` tree has no exact prior (it's a new directory), but `docs/STABILITY-MODEL.md` is a strong single-topic concept-doc analog and `docs/README.md` is the exact analog for `docs/internals/README.md`.

## Metadata

**Analog search scope:**
- `.claude/agents/` — six existing reviewers (all read)
- `.claude/skills/` — six existing skills (four fully read, two cross-referenced)
- `docs/` — `HARNESS.md`, `STABILITY-MODEL.md`, `README.md`, `decisions/000-template.md`, `decisions/004-per-user-npm-prefix.md`, `decisions/010-review-loop-via-claude-md.md`, `decisions/012-agent-user-full-sudo.md`
- top-level `README.md`, `CLAUDE.md`

**Files scanned:** ~25
**Pattern extraction date:** 2026-05-09
