---
phase: 16-documentation-brownfield-acceptance
plan: 01
subsystem: docs
tags: [docs, readme, migration, brownfield, ux-walkthrough, dry-run, four-states]
requires: []
provides:
  - README#brownfield-install
  - docs/MIGRATION.md
affects:
  - README.md
tech-stack:
  added: []
  patterns:
    - "Pattern: dual-doc executive-summary + deep walkthrough (README is the front door; MIGRATION.md is the operator manual)."
    - "Pattern: thematic scenario ordering (B → A → C → D by difficulty) with spec letters preserved in anchor slugs for grep stability."
    - "Pattern: REQ-ID + flag-name citation surface in transcripts (T-16-01-04 mitigation against version-string drift)."
    - "Pattern: relative-path link from README → docs (not anchor) for cross-renderer stability (T-16-01-03 mitigation)."
key-files:
  created:
    - docs/MIGRATION.md (265 lines)
    - .planning/phases/16-documentation-brownfield-acceptance/16-01-SUMMARY.md
  modified:
    - README.md (+74 lines)
decisions:
  - "D-16-01 mid-doc placement honored: brownfield H2 sits between `## Install` and `## Verify` so users hit it on first scroll."
  - "D-16-02 full-transcripts schema honored: 4 scenarios × 5 sub-blocks (Setup / Pre-flight report / Decision tree / Non-interactive command / Resulting host state)."
  - "D-16-06 link wiring honored: literal `[Brownfield install](#brownfield-install)` from `## Install`; literal `[per-scenario walkthroughs](docs/MIGRATION.md)` from brownfield section to MIGRATION.md."
  - "D-16-07 four mandatory scenarios honored: B (REUSE-02), A (REUSE-01/REMEDIATE-03), C (REMEDIATE-04 PATH-MISMATCH), D (REMEDIATE-04 broken chromium cache)."
  - "Single-source-of-truth for the worked example: README Scenario C transcript is the executive summary of MIGRATION.md's Scenario C deep walkthrough."
metrics:
  duration: "~33 min"
  completed_date: "2026-05-26"
  tasks: 2
  commits: 2
  files_created: 2
  files_modified: 1
---

# Phase 16 Plan 01: README brownfield section + docs/MIGRATION.md Summary

Plan 16-01 ships the two v0.3.4 user-facing documentation deliverables (DOC-01 + DOC-02) so the milestone-close audit in Plan 16-02 has its evidence artifacts in place. README.md gains a `## Brownfield install` H2 with a Scenario C executive-summary transcript; `docs/MIGRATION.md` is a new operator-facing guide with four worked scenarios (B → A → C → D) each carrying five labelled sub-blocks per the D-16-02 schema.

## What landed

### Task 1 — README.md `## Brownfield install` section + pointer link

**Insertion point (D-16-01):** `## Brownfield install (existing user / Node.js / agents)` H2 inserted between the pre-existing `## Install` section (greenfield curl-install — untouched) and `## Verify`. Section order is now: Install → Brownfield install → Verify → Uninstall → Stability model → Requirements → Security → Contributing → License → Links → About.

**Pointer-link (D-16-06):** One-liner `If you already have an \`agent\` user, Node.js, or any of these agents installed, see [Brownfield install](#brownfield-install).` inserted in `## Install` immediately after the `AGENTLINUX_VERSION=…` example block and before the SHA256-verify paragraph.

**Section content:**

- Four-state taxonomy (Reuse / Create / Remediate / Bail) — one-sentence bullet each.
- `agentlinux install --dry-run` worked transcript (Scenario C — Claude Code under root → REMEDIATE-04 PATH-MISMATCH) mirroring the `setup_brownfield_broken_claude_code` fixture from `tests/bats/helpers/brownfield.bash`.
- `agentlinux install --yes` non-interactive worked transcript with `[REMEDIATE-01]` + `[REMEDIATE-04]` markers.
- TTY mode note describing the per-action `Proceed with this remediation? [Y/n]` prompt (UX-02 contract) and the `reused — declined remediation` listing-row consequence.
- Exit codes blurb: `0` / `64` `EX_USAGE` / `65` `EX_DATAERR` / `1` (Phase 14 UX-05 surface).
- Closing pointer to `docs/MIGRATION.md` via relative-path link (`[per-scenario walkthroughs](docs/MIGRATION.md)`).

**Commit:** `9cb7f66` — `docs(16-01): README brownfield install section (DOC-01)`

### Task 2 — `docs/MIGRATION.md` (new file)

**Structure:**

- Top-level `# Migrating to AgentLinux on a brownfield host` heading.
- Opening paragraph: four-state taxonomy summary + cross-reference link to `../README.md#brownfield-install` (bidirectional cross-link).
- Illustrative-version-strings note (T-16-01-04 mitigation) up front: behavior + flag surface + exit codes are contractual; version literals are not.
- Table of contents linking each scenario by its GitHub-slugified anchor.
- Four H2 scenario sections in difficulty order (B → A → C → D). Spec letters preserved at the start of each H2 so `grep -i "scenario c"` finds Scenario C regardless of file order.

**Per-scenario schema (D-16-02 — each ~50-65 lines, ~150-250 words):**

| Sub-block | Content |
|-----------|---------|
| **Setup** | Concrete shell commands that produce the starting host state (`apt list`, `id agent`, `stat -c`, `which claude`, etc.) |
| **Pre-flight report** | Copy-paste of expected `agentlinux install --dry-run` output (~10-15 lines) |
| **Decision tree** | 1-2 sentence narrative pointing at the right flag (`--yes` or none) |
| **Non-interactive command** | Exact `agentlinux install [--yes]` invocation in a `bash` code block |
| **Resulting host state** | Bullet list of what was created, reused, remediated, or preserved |

**Scenarios:**

1. **Scenario B** — NodeSource Node.js already correct (REUSE-02 happy path). Every component `Reuse`, only catalog agents `Create`. No `--yes` needed.
2. **Scenario A** — Manual `useradd agent` (REUSE-01 happy path). Pre-existing user reused; canonical AgentLinux sudoers drop-in installed additively via REMEDIATE-03's missing-file branch (no `--yes` needed for additive install; `--yes` required only if a drifted sudoers file overlaps).
3. **Scenario C** — Claude Code installed under root → REMEDIATE-04 PATH-MISMATCH (the canonical bug class AgentLinux exists to fix). Uninstall root-owned `/usr/local/bin/claude`, reinstall canonically at `~agent/.local/bin/claude`, preserve `~agent/.claude/` user data per Phase 14 CAT-04 `preserve_paths.json`. Requires `--yes` in non-interactive mode.
4. **Scenario D** — Playwright with a broken chromium cache → REMEDIATE-04 reinstall + cache rebuild. Catalog `uninstall.sh` clears broken cache; `install.sh` re-runs `npm install -g playwright@<pin>` + `npx playwright install --with-deps chromium`.

**Commit:** `3454f61` — `docs(16-01): docs/MIGRATION.md 4 scenarios (DOC-02)`

## Threat mitigations honored

| Threat | Mitigation evidence |
|--------|---------------------|
| **T-16-01-03** (README link rot) | README → MIGRATION.md uses **relative-path link** `docs/MIGRATION.md`, not an anchor. Internal `#brownfield-install` anchor matches the literal H2 slug under every standard slugify algorithm (GitHub, GitLab, npm-render). |
| **T-16-01-04** (scenario version drift) | Every transcript carries `(illustrative — version strings may differ ...)` notes; scenarios cite **REQ-IDs** (REUSE-01, REUSE-02, REMEDIATE-03, REMEDIATE-04) and **flag names** (`--yes`, `--dry-run`, `--user=NAME`), never version literals as contract anchors. README has 1 inline illustrative note; MIGRATION.md has 1 opening illustrative note covering all 4 scenarios. |
| **T-16-01-07** (operator damages host via paste) | Scenario "Setup" blocks use only non-destructive inspection commands (`apt list`, `id`, `stat`, `which`); destructive setup hints (manual `useradd`, `echo > /etc/sudoers.d/local-…`) are clearly labelled as historical state, not commands to paste. |
| **T-16-01-08** (PR breaks brownfield anchor) | Plan 16-02's audit step has the literal `grep -F` pair (`"## Brownfield install"` + `"[Brownfield install](#brownfield-install)"`) wired into its acceptance criteria. |

## Verification chain (per task `<verify>` block)

All automated greps return >= 1 / == 4 as specified. The README heading-order awk confirms `Install → Brownfield install → Verify → Uninstall → Stability model` in file order. Greenfield `curl | sudo bash` instruction unchanged.

| Check | Expected | Actual |
|-------|----------|--------|
| `grep -cF "## Brownfield install" README.md` | >= 1 | 1 |
| `grep -cF "[Brownfield install](#brownfield-install)" README.md` | >= 1 | 1 |
| `grep -cF "REMEDIATE-04 — reinstall under agent" README.md` | >= 1 | 1 |
| `grep -cF "(illustrative — version strings" README.md` | >= 1 | 1 |
| `grep -cF "[per-scenario walkthroughs](docs/MIGRATION.md)" README.md` | >= 1 | 1 |
| `grep -cF "EX_USAGE" README.md` / `grep -cF "EX_DATAERR" README.md` | >= 1 / >= 1 | 1 / 1 |
| README first 5 H2 headings | Install → Brownfield install → Verify → Uninstall → Stability model | matches |
| `wc -l docs/MIGRATION.md` | >= 250 | 265 |
| 4 scenario H2 greps | 1 each | 1 / 1 / 1 / 1 |
| 5 sub-block labels × 4 scenarios | 4 each | 4 / 4 / 4 / 4 / 4 |
| `grep -cF "../README.md#brownfield-install"` | >= 1 | 1 |
| `grep -cF "illustrative"` | >= 1 | 1 |
| REQ-IDs (REUSE-01 / REUSE-02 / REMEDIATE-03 / REMEDIATE-04) | >= 1 each | 2 / 2 / 5 / 8 |

## Test gates preserved (no test deltas — docs-only plan)

- `cd plugin/cli && pnpm test` → **165/165 GREEN** (baseline preserved; 25 suites).
- `./tests/docker/run.sh ubuntu-24.04` → **202/202 GREEN** (baseline preserved; ends `== PASS: agentlinux-install + bats on ubuntu-24.04 ==`).
- No code files touched (zero diff under `plugin/`, `tests/`).

## Review loop (technical-writer + fact-checker)

Per CLAUDE.md §Review Loop: docs files dispatched to `technical-writer` + `fact-checker` rubrics applied inline (Task-tool subagent dispatch unavailable on this executor host; mechanical rubric application is the established Phase 2-6 precedent).

**technical-writer findings:** zero actionable. Heading hierarchy consistent, voice/tone uniform (imperative for commands, declarative for behavior), code-block fencing consistent (`console` vs. `bash`), em-dash consistency throughout, scenario sub-block labels parallel.

**fact-checker findings:** zero actionable. Exit codes match Phase 14 contract literal-for-literal; detection state names match Phase 12-15 contract; flag names match the canonical `agentlinux install` CLI surface; all REQ-IDs cited exist in `.planning/REQUIREMENTS.md`; Scenario C transcript mirrors `setup_brownfield_broken_claude_code` fixture in `tests/bats/helpers/brownfield.bash`.

**Iterations:** 1. **Fix commits:** 0.

## Deviations from Plan

None. Plan executed exactly as written.

The README markdown nesting concern flagged in Task 1 NOTES (inner triple-backticks inside an outer-fenced section) resolved itself: the README file is plain markdown — no outer fences exist in the file body — so embedded code-block triple-backticks render correctly with no escape needed. This is identical to the resolution Plan 06-05 reached for its `## Install` curl-install code blocks.

## Self-Check: PASSED

Files asserted to exist:
- FOUND: `README.md` (modified +74 lines)
- FOUND: `docs/MIGRATION.md` (new, 265 lines)
- FOUND: `.planning/phases/16-documentation-brownfield-acceptance/16-01-SUMMARY.md` (this file)

Commits asserted to exist:
- FOUND: `9cb7f66` (`docs(16-01): README brownfield install section (DOC-01)`)
- FOUND: `3454f61` (`docs(16-01): docs/MIGRATION.md 4 scenarios (DOC-02)`)

Test baselines:
- CONFIRMED: 165/165 CLI tests (was 165 baseline)
- CONFIRMED: 202/202 Ubuntu 24.04 bats (was 202 baseline)

---

*Plan 16-01 (DOC-01 + DOC-02) closed 2026-05-26. Wave 2 Plan 16-02 (brownfield-AGT-02 acceptance gate + milestone-close audit) follows.*
