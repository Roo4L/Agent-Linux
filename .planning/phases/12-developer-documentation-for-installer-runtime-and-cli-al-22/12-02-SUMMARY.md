---
phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
plan: 02
subsystem: docs
tags: [internals, claude-code, gsd, playwright-cli, registry-cli, catalog, AL-22, DOC-02]

# Dependency graph
requires:
  - phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
    plan: 01
    provides: docs/internals/ index README + 4 foundational-layer component docs (installer, agent-user, sudo-drop-in, nodejs-runtime) + the H2 spine pattern this plan extends
  - phase: 04-registry-cli-catalog-uninstall
    provides: plugin/cli/src/{index.ts, commands/*.ts} + plugin/catalog/{schema.json, catalog.json} (the registry CLI + catalog this plan documents)
  - phase: 05-agent-installability
    provides: plugin/catalog/agents/{claude-code, gsd, playwright-cli}/install.sh — the real recipes whose product-perspective story claude-code.md / gsd.md / playwright.md tell
provides:
  - docs/internals/ tree complete (9-of-9 component docs landed; was 4-of-9 after Plan 01)
  - 5 product-perspective component docs covering the catalog layer (3 agent docs + registry-cli + catalog)
  - Mutual cross-links between registry-cli.md and catalog.md (the plan's key_links contract)
  - Worked-example shell sessions for every catalog-layer surface (claude-code's `claude update` divergence, gsd's bootstrapper-wires-skills, playwright-cli's two-part install, registry-cli's verb table, catalog's add-an-agent-in-one-PR flow)
affects:
  - 12-03-PLAN (dev-docs reviewer agent + dev-docs skill — both will now pattern-match against 9 working component docs, not 4)
  - 12-04-PLAN (CLAUDE.md wiring of dev-docs-auditor into the Review Loop table — references the now-complete docs/internals/ tree)
  - 12-05-PLAN (top-level README "Why AgentLinux — concepts" link — its target docs/internals/README.md TOC is now live with all 9 entries pointing at written docs)

# Tech tracking
tech-stack:
  added: []  # docs only — no new libraries / runtime tech
  patterns:
    - Component-doc H2 spine "problem -> answer -> value vs naive -> Related" (continued from Plan 01)
    - Bold-lead-clause numbered-list trade-off pattern (excerpt-friendly for blog/marketing reuse; same shape Plan 01 established)
    - Cross-link Related footer with no source-line deep links (CONTEXT §"Depth")
    - Sibling-component cross-references (registry-cli ↔ catalog mutual; agent docs link back to agent-user.md / sudo-drop-in.md / catalog.md / registry-cli.md)

key-files:
  created:
    - docs/internals/claude-code.md
    - docs/internals/gsd.md
    - docs/internals/playwright.md
    - docs/internals/registry-cli.md
    - docs/internals/catalog.md
  modified: []

key-decisions:
  - Three Rule 1 source-truth deviations baked into the docs (vs the plan's narrative): (a) playwright.md describes Microsoft's @playwright/cli (the real catalog entry id `playwright-cli`, pinned 0.1.11) — the recipe is npm-install + `playwright-cli install --skills` skill-bootstrap, NOT the older "playwright install --with-deps chromium" Playwright-library shape the plan narrated; the chromium-deps story still holds for the apt layer that the bootstrapper triggers, so the Value-vs-naive list keeps that thread. (b) gsd.md describes the get-shit-done-cc bootstrapper (`--global --claude`) that wires GSD skills into ~/.claude/skills/gsd-* — the intent-completion step the plan did not mention but the install.sh actually performs; the doc names the user-dogfood bug ("I installed it and Claude Code doesn't see it") this step exists to prevent. (c) registry-cli.md lists only the five verbs the CLI actually exposes (list, install, remove, upgrade, pin) — the plan mentioned `info` and `doctor` which do not exist in plugin/cli/src/index.ts; documented what ships.
  - No Mermaid diagrams in any of the five docs. The plan flagged Mermaid as optional per CONTEXT §"Diagrams" "used sparingly"; I judged each component (a sequence diagram for the registry-CLI recipe-dispatch flow, a topology for the catalog data model) and concluded prose was clearer in both cases — neither would have lifted into blog/marketing copy any better than the prose already does.
  - Worked-example shell sessions in all five docs. PATTERNS.md lists worked-example as optional, but the AL-22 litmus test ("60-second answer for what value AgentLinux adds") lands much harder with a 5-7-line transcript showing the actual observable behavior — the divergence after `claude update`, the "skill set wired" log line in gsd's install, the password-free apt install in playwright's install, the verb table in `agentlinux list`, the JSON catalog snapshot in catalog's example.
  - registry-cli.md lists every verb as a bullet with a one-paragraph explanation rather than a brief enumeration. The verbs ARE the product surface — operators touch them daily. The doc is excerpt-friendly source for the agentlinux.org "what does the CLI do" section per CONTEXT §"Reuse signal"; brief enumerations would not lift into marketing copy.
  - catalog.md uses the three-piece framing (schema.json + catalog.json + per-agent recipes) instead of a single "what is the catalog" paragraph. The catalog is structurally a tripartite contract, and the doc maps to that structure so readers can follow the data flow from "schema declares the shape" -> "catalog.json holds the entries" -> "recipes implement the install" without losing the thread.

patterns-established:
  - "Sibling-doc mutual cross-links: when two components are coupled (registry-cli reads catalog; catalog is consumed by registry-cli), both Related footers cite each other. Plan 12-03's dev-docs reviewer can grep for this bidirectional citation as a freshness signal."
  - "Source-truth-over-plan-narrative: when the plan describes an outdated impl (the playwright story moved from chromium-deps to skill-bootstrap; the registry-cli `doctor`/`info` verbs were never built), the doc grounds in the actual install.sh / index.ts and documents the deviation as a Rule 1 fix in SUMMARY. The doc must reflect what ships, not what the plan narrated months ago."

requirements-completed: [DOC-02]

# Metrics
duration: 5min
completed: 2026-05-10
---

# Phase 12 Plan 02: Internals catalog-layer docs — claude-code + gsd + playwright + registry-cli + catalog Summary

**5 product-perspective component docs that complete the docs/internals/ tree by answering "what value does AgentLinux provide for surface X" for each catalog-layer surface — the three pinned agents (claude-code, gsd, playwright-cli), the registry CLI that drives them, and the schema-validated catalog they live in.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-10T05:55:47Z
- **Completed:** 2026-05-10T06:00:40Z
- **Tasks:** 2
- **Files created:** 5
- **Files modified:** 0

## Accomplishments

- Three agent docs (claude-code, gsd, playwright) each grounded in the actual `plugin/catalog/agents/<id>/install.sh` body — every claim about install path, ownership, or post-install state is verifiable against the recipe that ships.
- Registry CLI doc covering all five real verbs (list, install, remove, upgrade, pin) — including the `preAction` guardAgentUser hook (CLI-05), the catalog snapshot path on disk, and the recipe-dispatch flow with environment-injection of `AGENTLINUX_PINNED_VERSION`.
- Catalog doc covering the three-piece data model (`schema.json` + `catalog.json` + per-agent recipes) plus the three CAT-01/CAT-02/CAT-03 invariants and the curated-combo connection to STABILITY-MODEL.md.
- Mutual cross-links between registry-cli.md and catalog.md (each Related footer cites the other), per the plan's `key_links` contract.
- Worked-example shell sessions in every doc, sized for blog/marketing excerpt reuse: claude-code shows the `claude update` divergence; gsd shows the skill-set-wired log line; playwright shows the password-free apt-deps step; registry-cli shows the `agentlinux list` table + verb cascade; catalog shows the JSON snapshot + the add-an-agent-in-one-PR flow.
- Hard contract upheld: no source-line deep links (`*.sh:NN`, `*.ts:NN`, `*.json:NN`) anywhere; no Mermaid fences; ADR mentions in prose only (playwright.md prose-cites ADR-012 with link; the rest are prose-only mentions).
- All five files easily exceed the plan's 40-line min_lines requirement (smallest: gsd at 116 lines; largest: catalog at 153 lines).

## Task Commits

Each task was committed atomically:

1. **Task 1: Write claude-code.md + gsd.md + playwright.md** — `3f6e329` (docs)
2. **Task 2: Write registry-cli.md + catalog.md** — `e71d8cc` (docs)

**Plan metadata commit (this SUMMARY + STATE/ROADMAP/REQUIREMENTS updates):** committed after this file lands.

## Files Created/Modified

- `docs/internals/claude-code.md` (121 lines) — Agent doc on Anthropic's Claude Code CLI in the catalog. Lede frames it as "the canonical AgentLinux acceptance test (AGT-02)." Problem walks through the EACCES + recursive-shim cycle that follows from `sudo npm install -g @anthropic-ai/claude-code`, naming AGT-02 as the regression test. Answer describes the recipe: pipe `claude.ai/install.sh` to bash with the running user already dropped to `agent`, install lands at `/home/agent/.local/bin/claude`, agent-owned, so `claude update` Just Works. Worked example shows `claude update` followed by `agentlinux upgrade` surfacing the override-ahead divergence. Trade-off list: (1) `claude update` breaks on root-owned trees, (2) Upstream `latest` ships immediately. Related links agent-user, catalog, registry-cli, ../STABILITY-MODEL.md.
- `docs/internals/gsd.md` (116 lines) — Agent doc on GSD (`get-shit-done-cc` on npm). Lede positions it as a Claude Code workflow framework. Problem covers both the ownership trap (sudo npm install -g) AND the upstream-cadence trap (GSD ships fast, occasional broken releases) AND the user-dogfood gap ("binary on PATH but Claude Code sees no /gsd-* commands") — the third strand grounded in the actual install.sh comment block (lines 50-65). Answer describes `npm install -g get-shit-done-cc@<pinned>` into the agent's per-user prefix + the bootstrapper invocation `get-shit-done-cc --global --claude` that copies the skill set into `~/.claude/skills/gsd-*/`. Worked example shows the install transcript ending in "skill set wired into …/gsd-*". Trade-off list: (1) The agent's own workflow tools end up root-owned, (2) Upstream regressions hit immediately. Related links agent-user, catalog, registry-cli, ../STABILITY-MODEL.md.
- `docs/internals/playwright.md` (119 lines) — Agent doc on Microsoft's `@playwright/cli` (catalog id `playwright-cli`). Lede frames it as the agent-oriented Playwright CLI plus its Claude Code skill, not the JS Playwright library. Problem covers three failure modes in sequence: ownership trap (sudo npm install -g), apt-deps password prompt (Playwright's installer auto-prepends sudo for browser-deps; non-interactive sessions stall), and intent gap (skill-set-not-wired). Answer describes the two-part install: `npm install -g @playwright/cli@<pinned>` + pre-skills version-lock + `playwright-cli install --skills` from agent home + ADR-012 NOPASSWD drop-in carries the apt step. Worked example shows the install transcript ending in "skill wired into …/playwright-cli". Trade-off list: (1) The npm install ends up root-owned, (2) The browser-deps step needs sudo, which stalls non-interactive sessions. Related links agent-user, sudo-drop-in, catalog, registry-cli.
- `docs/internals/registry-cli.md` (142 lines) — Component doc on the `agentlinux` CLI. Lede frames it as the surface developers actually touch. Problem covers fleet unmemorability (every agent has its own install command) + cross-cutting concerns having nowhere to live (stickiness, divergence, install-time invariants) + invocation discipline (must-run-as-agent, must-inject-pinned-version). Answer describes the five verbs (list, install, remove, upgrade, pin) with one-paragraph each, plus the `preAction` guardAgentUser hook (CLI-05), the catalog snapshot at `/opt/agentlinux/catalog/<version>/catalog.json`, and the runner that exports the agent environment before shelling into the recipe. Worked example shows `agentlinux list` (the verb table) -> `install gsd` -> `upgrade` (synced state). Trade-off list: (1) Per-agent commands drift, (2) No place to land cross-cutting concerns. Related links catalog, agent-user, claude-code, gsd, playwright.
- `docs/internals/catalog.md` (153 lines) — Component doc on the catalog (the schema-validated agent registry). Lede frames it as opt-in, three real entries, zero installed by default. Problem covers the two naive paths (hardcoded agent list in CLI source, README-only) + the version-pinning collapse (without per-entry pinned_version, "curated combo" reduces to "whatever npm serves today"). Answer describes the three-piece data model (`plugin/catalog/schema.json` JSON Schema 2020-12 with additionalProperties:false; `plugin/catalog/catalog.json` embedded list with three real entries + one test_only fixture; per-agent recipe pairs under `plugin/catalog/agents/<id>/`) plus the three invariants (CAT-01 available-not-installed; CAT-02 schema-validated at pre-commit + CI; CAT-03 add-agent-in-one-PR). Worked example shows the JSON snapshot + the add-a-new-agent flow. Trade-off list: (1) Hardcoding means a CLI release per agent, (2) Without schema validation, every recipe is a snowflake. Related links registry-cli, ../STABILITY-MODEL.md, claude-code, gsd, playwright.

## Decisions Made

- **Source-truth-over-plan-narrative for three claims (Rule 1 deviations).** (a) playwright.md grounds in the actual `plugin/catalog/agents/playwright-cli/install.sh` (Microsoft's `@playwright/cli`, pinned 0.1.11, npm + `--skills` bootstrap) instead of the plan's narrative about Playwright + chromium-with-deps. The chromium-deps thread is preserved in the Value-vs-naive list as the apt-layer that the bootstrapper triggers — the doc covers the real install path AND the trade-off the plan was after. (b) gsd.md adds the `get-shit-done-cc --global --claude` bootstrapper (the intent-completion step the plan did not mention but the install.sh performs) along with the user-dogfood bug ("I installed it and Claude Code doesn't see it") that motivated the recipe addition. (c) registry-cli.md lists only the verbs that ship in `plugin/cli/src/index.ts` — list, install, remove, upgrade, pin — and omits the plan's `info` and `doctor` mentions which do not exist as commands. The doc must reflect what ships, not what the plan narrated.
- **No Mermaid diagrams.** The plan flagged Mermaid as optional per CONTEXT §"Diagrams" "used sparingly." I considered a sequence diagram for registry-cli (verb -> catalog -> recipe -> sentinel) and a topology diagram for catalog (schema + manifest + recipes). Both lost to prose: the registry-cli verb-by-verb explanation is cleaner as a bullet list than as a sequence diagram, and the catalog's three-piece structure is short enough that paragraphs read faster than a topology figure. Per the AL-22 litmus test ("60-second answer"), prose was the better lift.
- **One ADR link allowed (playwright.md → ADR-012 in prose with link).** Plan 12-01 established that ADR-012 is the doc-to-ADR mapping where a direct link is justified — sudo-drop-in.md links it from Related. Playwright.md prose-cites ADR-012 because the apt-deps story directly turns on the NOPASSWD grant; a parenthetical link in prose mirrors the depth Plan 12-01 set. Other ADR mentions stay prose-only (CAT-01/CAT-02/CAT-03/ADR-003/ADR-008 referenced by name in catalog.md and registry-cli.md without links).
- **Worked examples in all five docs.** PATTERNS.md lists worked-example as optional. I included one in each because the AL-22 litmus test ("60-second answer for what value AgentLinux adds") is reinforced dramatically by a 5-7-line transcript showing the actual observable behavior. The transcripts are also the single most excerpt-friendly content for the agentlinux.org landing page per CONTEXT §"Reuse signal" — every example was sized to lift cleanly into a marketing snippet without surrounding prose.
- **Sibling cross-links rather than full-fan-out Related footers.** Each agent doc cross-links the other components most-tightly-coupled to it (claude-code → agent-user + catalog + registry-cli + STABILITY-MODEL; gsd → same set; playwright → same set + sudo-drop-in for the apt-deps thread). registry-cli and catalog mutually cross-link plus link to all three agent entries (they are the catalog the registry-cli iterates). I deliberately did NOT cross-link agent docs to each other (claude-code → gsd, etc.) — operators reading "what is GSD" do not need a "see also Claude Code" pointer; they want to learn about GSD. Cross-links serve discoverability of dependencies, not symmetry.

## Deviations from Plan

Three Rule 1 (source-truth) auto-fix deviations, all baked into the docs themselves and documented in the per-task commit messages.

### Auto-fixed Issues

**1. [Rule 1 - Bug] playwright.md grounded in @playwright/cli reality, not the plan's narrated Playwright-with-chromium-deps**

- **Found during:** Task 1 (reading `plugin/catalog/agents/playwright-cli/install.sh` per `<read_first>`)
- **Issue:** The plan narrative described installing the JS Playwright library + running `playwright install --with-deps chromium`. The actual catalog entry id is `playwright-cli`, the pinned package is `@playwright/cli` (0.1.11), and the install path is npm-install + `playwright-cli install --skills` (Claude Code skill bootstrap). The plan's narrative was from an earlier impl that the catalog moved past.
- **Fix:** Wrote the doc against the real install.sh: lede mentions `@playwright/cli` and the skill-bootstrap explicitly; problem section keeps the apt-deps story (real, since the bootstrapper triggers apt-layer browser deps via Playwright's sudo-prepended internal path); answer section describes the real two-part install. The chromium-deps thread becomes the second item in the Value-vs-naive list (preserves the plan's intent that the playwright doc carry the apt-layer / sudo-drop-in story).
- **Files modified:** `docs/internals/playwright.md`
- **Commit:** `3f6e329`

**2. [Rule 1 - Bug] gsd.md adds the bootstrapper-wires-skills story the plan did not mention**

- **Found during:** Task 1 (reading `plugin/catalog/agents/gsd/install.sh` per `<read_first>`)
- **Issue:** The plan's gsd narrative described an npm-install-only flow. The actual install.sh runs `get-shit-done-cc --global --claude` after the npm install to copy GSD's skill set into `~/.claude/skills/gsd-*/`. The install.sh comment block (lines 50-77) names the user-dogfood bug ("binary on PATH but Claude Code sees no /gsd-* commands") that motivated adding the bootstrapper invocation. Without that step, "agentlinux install gsd" succeeds technically but fails the user's intent.
- **Fix:** Added a third Problem-section paragraph naming the intent gap; added the bootstrapper invocation to the Answer section; included the "skill set wired" log line in the Worked example. The doc now reflects what the recipe actually does, including the user-dogfood-discovery story (which doubles as excellent blog material per CONTEXT §"Reuse signal").
- **Files modified:** `docs/internals/gsd.md`
- **Commit:** `3f6e329`

**3. [Rule 1 - Bug] registry-cli.md lists only the verbs that ship**

- **Found during:** Task 2 (reading `plugin/cli/src/index.ts` per `<read_first>`)
- **Issue:** The plan's registry-cli narrative listed seven verbs (list, install, remove, info, upgrade, pin, doctor). The actual `plugin/cli/src/index.ts` registers five subcommands: list, install, remove, upgrade, pin. There is no `info` and no `doctor`. Documenting verbs that do not exist would mislead operators and fail the catalog auditor's "doc freshness" rubric (Plan 12-03 will codify this rubric — a doc that names a non-shipping verb would be exactly the kind of staleness the auditor flags).
- **Fix:** Wrote the doc against the actual five-verb surface in `index.ts`. Each verb gets a one-paragraph explanation grounded in the corresponding `plugin/cli/src/commands/<verb>.ts` impl. The doc still carries the "why a CLI exists at all" framing the plan was after.
- **Files modified:** `docs/internals/registry-cli.md`
- **Commit:** `e71d8cc`

## Issues Encountered

The pre-existing `git status` snapshot showed unrelated modifications to `.planning/config.json`, three Plan 12-0[3..5] PLAN.md files, `docs/audits/v0.4.0/PUB-04-release-notes.md`, plus `.planning/{MILESTONES,ROADMAP,STATE}.md` from earlier in the day. These were left strictly untouched. Per the protocol, only the five `docs/internals/*.md` files were `git add`-ed and committed; no `git add .` / `-A` was used.

The plan-level verify block (the bash chain at the bottom of `<verification>`) and both per-task verify blocks all passed first try with no fix commits required. The acceptance criteria checks (H1 / H2 spine / mutual cross-links / no source-line deep links / no Mermaid / bold-lead-clause numbered list with ≥2 items) all passed for all five files on first write.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `docs/internals/` tree complete: 9 of 9 component docs landed (4 from Plan 01, 5 from this plan). Every TOC entry in `docs/internals/README.md` now points at a written doc.
- Plan 12-03 (dev-docs reviewer + dev-docs skill) can now pattern-match against the full set of 9 examples — the structural contract (problem -> answer -> worked example -> value vs naive -> Related; bold-lead-clause trade-off list; sibling cross-links; no source-line deep links; ADR mentions prose-by-default with one allowed link per Plan 01) is reified across 9 working component docs. The reviewer's source-to-doc dispatch table can grep for the 9 component slugs as the registry it reads.
- Plan 12-04 (CLAUDE.md wiring of dev-docs-auditor into the Review Loop table) and Plan 12-05 (top-level README "Why AgentLinux — concepts" pointer into docs/internals/) are both unblocked by this plan's completion. The README pointer Plan 05 lands now has a complete tree of nine docs to land into.
- The three Rule 1 source-truth deviations baked into this plan establish a precedent the dev-docs reviewer will codify in Plan 12-03: when an existing doc says X about the source but the source is Y, the doc must be updated to Y, and the deviation must be documented in the SUMMARY (or, post-Plan-03, in the PR description that the reviewer reads). "Doc reflects what ships, not what the plan narrated" is the freshness rule.

## Self-Check: PASSED

- `docs/internals/claude-code.md` — FOUND (121 lines)
- `docs/internals/gsd.md` — FOUND (116 lines)
- `docs/internals/playwright.md` — FOUND (119 lines)
- `docs/internals/registry-cli.md` — FOUND (142 lines)
- `docs/internals/catalog.md` — FOUND (153 lines)
- Task 1 commit `3f6e329` — FOUND in `git log`
- Task 2 commit `e71d8cc` — FOUND in `git log`
- Each component doc has the four mandated H2 sections (`## The problem`, `## What AgentLinux does`, `## Value vs the naive approach`, `## Related`) — VERIFIED via grep
- All five files have correct H1s (`# Claude Code`, `# GSD (Get Shit Done)`, `# Playwright`, `# Registry CLI`, `# Catalog`) — VERIFIED via grep
- registry-cli.md → catalog.md cross-link present (`(catalog.md)`) — VERIFIED via grep
- catalog.md → registry-cli.md cross-link present (`(registry-cli.md)`) — VERIFIED via grep
- claude-code.md mentions AGT-02 / `claude update` — VERIFIED via grep
- claude-code.md links to agent-user.md AND mentions EACCES — VERIFIED via grep
- playwright.md mentions sudo-drop-in.md cross-link — VERIFIED via grep (`(sudo-drop-in.md)`)
- catalog.md mentions CAT-01 / CAT-02 / CAT-03 / opt-in / schema-validated — VERIFIED via grep
- registry-cli.md lists install / list / remove / upgrade / pin — VERIFIED via grep
- All five `## Value vs the naive approach` sections use bold-lead-clause numbered format with exactly 2 items each — VERIFIED via `grep -cE '^[0-9]+\. \*\*'`
- No source-line deep links (`*.sh:NN`, `*.ts:NN`, `*.json:NN`) anywhere in the five new files — VERIFIED via `grep -nE`
- No Mermaid fences in the five new files — VERIFIED via `grep '^```mermaid'`

---
*Phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22*
*Completed: 2026-05-10*
