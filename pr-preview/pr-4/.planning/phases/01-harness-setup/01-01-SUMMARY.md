---
phase: 01-harness-setup
plan: 01
subsystem: infra
tags: [scaffolding, adr, claude-md, docs, research-migration, commander-js, biome, json-schema]

# Dependency graph
requires: []
provides:
  - "Repo skeleton per docs/HARNESS.md §1 (plugin/, tests/, packaging/, docs/)"
  - "CLAUDE.md at repo root (82 lines) with project identity, critical rules, review-loop pointer"
  - "ADR-001..ADR-010 seeded in docs/decisions/ (Accepted, 2026-04-18)"
  - "docs/README.md indexing docs/ tree"
  - "ADR template at docs/decisions/000-template.md"
  - "v0.3.0 and v0.2.0 research migrated to docs/research/vX.Y.Z/"
  - "Stub installer entrypoint at plugin/bin/agentlinux-install"
  - "plugin/cli/ baseline (package.json, tsconfig.json, biome.json — Commander.js + node:test)"
  - "plugin/catalog/schema.json JSON Schema 2020-12 stub"
affects: [01-02-pre-commit, 01-03-review-subagents, 01-04-skills, 01-05-harness-tests, 02-installer-foundation]

# Tech tracking
tech-stack:
  added: [commander@^12.1.0, typescript@^5.6.3, biome@^1.9.4, json-schema-2020-12]
  patterns:
    - "Copy-of-truth layout: docs/HARNESS.md §1 dictates every directory that must exist"
    - "ADR convention: one file per decision in docs/decisions/, 001..NNN, template at 000-template.md"
    - "Research routing: GSD research outputs live in .planning/research/ and graduate to docs/research/vX.Y.Z/ at milestone lock"
    - ".gitkeep sentinels for empty directories that must persist in git"

key-files:
  created:
    - CLAUDE.md
    - plugin/bin/agentlinux-install
    - plugin/cli/package.json
    - plugin/cli/tsconfig.json
    - plugin/cli/biome.json
    - plugin/catalog/schema.json
    - docs/README.md
    - docs/decisions/000-template.md
    - docs/decisions/001-pivot-distro-to-plugin.md
    - docs/decisions/002-behavior-contract-framing.md
    - docs/decisions/003-no-default-agents-installed.md
    - docs/decisions/004-per-user-npm-prefix.md
    - docs/decisions/005-system-nodejs-over-version-managers.md
    - docs/decisions/006-curl-pipe-bash-plus-deb.md
    - docs/decisions/007-docker-plus-qemu-harness.md
    - docs/decisions/008-commander-js-for-cli.md
    - docs/decisions/009-snap-disqualified.md
    - docs/decisions/010-review-loop-via-claude-md.md
    - docs/research/v0.3.0/STACK.md
    - docs/research/v0.3.0/FEATURES.md
    - docs/research/v0.3.0/ARCHITECTURE.md
    - docs/research/v0.3.0/PITFALLS.md
    - docs/research/v0.3.0/SUMMARY.md
    - docs/research/v0.2.0/STACK.md
    - docs/research/v0.2.0/FEATURES.md
    - docs/research/v0.2.0/ARCHITECTURE.md
    - docs/research/v0.2.0/PITFALLS.md
    - docs/research/v0.2.0/SUMMARY.md
    - "17 .gitkeep files across plugin/, packaging/, tests/, docs/ empty directories"
  modified: []

key-decisions:
  - "Copy research rather than move: .planning/research/ left intact so GSD tooling that references it still works; archive sweep deferred to Phase 6"
  - "CLAUDE.md skill pointers reference skills that don't yet exist (arrive in Plans 01-03 and 01-04); documented as such to set expectations"
  - "Installer stub kept minimal (echo + exit 0) per PLAN constraint — no real provisioning logic in Phase 1"

patterns-established:
  - "ADR header: # NNN: Title / **Status:** Accepted / **Date:** YYYY-MM-DD / ## Context / ## Decision / ## Consequences"
  - "docs/research/vX.Y.Z/ as the canonical destination for milestone research (STACK, FEATURES, ARCHITECTURE, PITFALLS, SUMMARY per milestone)"
  - "Per-task atomic commits via git add <files> + git commit (not gsd-tools.cjs commit — which auto-stages all changes and breaks the atomic model in sequential mode)"

requirements-completed: [HRN-01, HRN-03, HRN-04, HRN-05]

# Metrics
duration: 4m
completed: 2026-04-18
---

# Phase 1 Plan 01: Harness Skeleton + CLAUDE.md + ADRs + Research Migration Summary

**Full repository skeleton per docs/HARNESS.md §1 with CLAUDE.md (82 lines), 10 Accepted ADRs, and v0.2.0/v0.3.0 research migrated to docs/research/.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-18T09:49:03Z
- **Completed:** 2026-04-18T09:53:16Z
- **Tasks:** 3 / 3
- **Files created:** 47 (22 skeleton + 1 CLAUDE.md + 12 docs + 10 research + 2 misc)

## Accomplishments

- Repo skeleton with all 17 directories from `docs/HARNESS.md` §1 created and persisted via `.gitkeep`
- Stub installer entrypoint at `plugin/bin/agentlinux-install` (executable, exits 0, prints Phase-1 notice)
- `plugin/cli/` baseline (Commander.js, TypeScript strict, Biome) — no source yet
- `plugin/catalog/schema.json` JSON Schema 2020-12 stub with strict `additionalProperties: false` and name pattern
- CLAUDE.md at repo root — 82 lines, under 150 budget, with all six sections from HARNESS.md §6
- 10 ADRs seeded (ADR-001..ADR-010), each Accepted + dated 2026-04-18, with mandated consequence callouts (ADR-005 cron/systemd/non-interactive SSH; ADR-010 Stop-hook misfire categories)
- ADR template at `docs/decisions/000-template.md`
- `docs/README.md` indexing the docs/ tree with the `.planning/` vs `docs/` routing rule
- v0.3.0 research (STACK, FEATURES, ARCHITECTURE, PITFALLS, SUMMARY) copied from `.planning/research/` to `docs/research/v0.3.0/` byte-for-byte
- v0.2.0 research copied from `.planning/milestones/v0.2.0-research/` to `docs/research/v0.2.0/` byte-for-byte
- Legacy v0.1.0 site files (`index.html`, `assets/`, `CNAME`, `sitemap.xml`, `robots.txt`) untouched
- Legacy v0.2.0 `packer/` directory untouched

## Task Commits

Each task was committed atomically:

1. **Task 1: Create repo skeleton + stub entrypoint + catalog schema** — `3d65cb2` (feat)
2. **Task 2: Write CLAUDE.md at repo root (<150 lines) per HARNESS.md §6** — `fa49675` (docs)
3. **Task 3: Seed ADR-001..ADR-010 + docs/README.md + ADR template + migrate research** — `d2ca481` (docs)

**Plan metadata commit:** TBD (final STATE.md / ROADMAP.md update after this SUMMARY)

## Files Created/Modified

### Created — plugin skeleton
- `plugin/bin/agentlinux-install` — executable bash stub; prints Phase-1 notice; exits 0
- `plugin/cli/package.json` — `@agentlinux/cli@0.0.0`, Commander.js + node:test, node>=22
- `plugin/cli/tsconfig.json` — ES2022, NodeNext, strict mode, noImplicitAny
- `plugin/cli/biome.json` — recommended rules, 2-space indent, 100-col line width
- `plugin/catalog/schema.json` — JSON Schema 2020-12; strict; agent name pattern `^[a-z][a-z0-9-]*$`
- `.gitkeep` placeholders in `plugin/{lib,provisioner,cli/src,cli/test,catalog/agents}`

### Created — test / packaging / docs skeleton
- `.gitkeep` in `packaging/{curl-installer,deb}`, `tests/{bats,bats/helpers,docker,qemu,qemu/cloud-init,harness,mutation}`, `docs/{proposals,analysis,reviews}`

### Created — reference documentation
- `CLAUDE.md` — 82-line project context (project identity, where-things-live, 6 critical rules, review loop, commands, pointers)
- `docs/README.md` — docs/ layout index + `.planning/` vs `docs/` routing rule
- `docs/decisions/000-template.md` — ADR template header
- `docs/decisions/001-pivot-distro-to-plugin.md` — v0.2.0 → v0.3.0 pivot rationale
- `docs/decisions/002-behavior-contract-framing.md` — BHV-XX / bats-as-spec framing
- `docs/decisions/003-no-default-agents-installed.md` — catalog-as-opt-in
- `docs/decisions/004-per-user-npm-prefix.md` — keystone ownership decision
- `docs/decisions/005-system-nodejs-over-version-managers.md` — why NodeSource, not nvm/fnm/volta (calls out cron/systemd/non-interactive SSH blast radius)
- `docs/decisions/006-curl-pipe-bash-plus-deb.md` — distribution mechanism
- `docs/decisions/007-docker-plus-qemu-harness.md` — two-layer CI; Docker-only disqualified
- `docs/decisions/008-commander-js-for-cli.md` — CLI framework pick
- `docs/decisions/009-snap-disqualified.md` — structural confinement incompatibility
- `docs/decisions/010-review-loop-via-claude-md.md` — CLAUDE.md instruction > Stop hook (explains Stop-hook misuse on interrupts/context-limits)

### Created — research migration
- `docs/research/v0.3.0/{STACK,FEATURES,ARCHITECTURE,PITFALLS,SUMMARY}.md` — copied from `.planning/research/`
- `docs/research/v0.2.0/{STACK,FEATURES,ARCHITECTURE,PITFALLS,SUMMARY}.md` — copied from `.planning/milestones/v0.2.0-research/`

### Modified — none
No existing files were modified. Legacy v0.1.0 site and retired v0.2.0 `packer/` untouched per plan.

## Decisions Made

- **Copy research rather than move.** The plan's HRN-05 language says "migrated"; leaving the source copies in `.planning/` keeps GSD tooling that scans `.planning/research/` working until the Phase 6 archive sweep. `diff -q` confirmed byte-exact copies.
- **CLAUDE.md references future skills.** The review-loop and skills sections point to `.claude/skills/review/` and the four project-scoped skill directories, which don't exist yet. Plan 01-03 creates the review skill; Plan 01-04 creates the others. Documented in CLAUDE.md as "arrives in Plan 01-0X" so agents reading it mid-phase-1 set expectations correctly.
- **Atomic commits via raw `git`, not `gsd-tools.cjs commit`.** The `gsd-tools` commit helper auto-stages *all* working-tree changes (confirmed by accidentally committing unrelated `.planning/notes/` tracked files when testing it). For sequential per-task atomic commits we used `git add <files> && git commit --no-gpg-sign`. Pattern noted for Plans 01-02..05.

## Deviations from Plan

None — plan executed exactly as written. No Rule 1 bugs, no Rule 2 missing critical functionality, no Rule 3 blocking issues, no Rule 4 architectural changes.

All files created match `files_modified` in PLAN frontmatter (minus `docs/README.md` which the PLAN task-3 body specifies but the frontmatter inadvertently omitted — the task body is authoritative per plan text, so this is not a deviation).

**Total deviations:** 0.
**Impact on plan:** None.

## Issues Encountered

- **Accidental commit via `gsd-tools.cjs commit`.** Early discovery: running `node ~/.claude/get-shit-done/bin/gsd-tools.cjs commit "test"` to verify the tool's CLI shape *actually commits* with auto-staging of all tracked changes (it created commit `1e933cd` with pre-existing `.planning/notes/` files). Reverted via `git reset --soft HEAD~1 && git reset HEAD` (non-destructive — no file contents touched). Switched to raw `git add <files> && git commit --no-gpg-sign` for all three task commits. No residual contamination; the three task commits contain only their own files. Documented as a pattern in Decisions Made above.

## User Setup Required

None — infrastructure/scaffolding only. No external services, no secrets, no auth gates.

## Next Phase Readiness

Plan 01-02 (Pre-commit + four GH Actions workflows + mutation scaffolding) unblocked. Everything 01-02 needs exists on disk:

- `plugin/bin/agentlinux-install` is executable bash → shellcheck/shfmt can target it
- `plugin/cli/biome.json` + `package.json` → biome hook has a config to read
- `plugin/catalog/schema.json` → catalog-schema-validate hook has a schema to enforce
- `.github/workflows/` directory exists at repo root (verified via `ls -la`) → 01-02 adds `test.yml`, `nightly-qemu.yml`, `nightly-mutation.yml`, `release.yml`
- `tests/mutation/` empty directory exists → 01-02 adds `bash-mutator.sh`

Plan 01-03 (review subagents + /review skill) depends on `.claude/agents/` and `.claude/skills/review/` directories — those are created on-demand by 01-03 itself; no blockers from 01-01.

Plan 01-04 (skill skeletons) likewise creates its own `.claude/skills/<name>/` directories.

Plan 01-05 (harness meta-test suite) runs against `tests/harness/` which exists as a `.gitkeep`-sentinel directory today.

## Self-Check: PASSED

All 29 claimed files exist on disk. All 3 task commits present in `git log`.

- Files verified: CLAUDE.md + 5 plugin skeleton + 1 docs/README.md + 11 ADR files (template + 10) + 10 research files (5 v0.3.0 + 5 v0.2.0) + SUMMARY.md = 29 ✓
- Commits verified: 3d65cb2 (Task 1), fa49675 (Task 2), d2ca481 (Task 3) ✓

---
*Phase: 01-harness-setup*
*Plan: 01*
*Completed: 2026-04-18*
