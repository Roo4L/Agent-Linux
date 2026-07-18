---
phase: 28-rtk
plan: 03
subsystem: catalog
tags: [catalog, prebuilt-binary, rtk, recipe, opt-in-hook, symmetric-remove, supply-chain]

# Dependency graph
requires:
  - phase: 28-01
    provides: "source_kind enum extended to [npm, script, binary] (schema.json + types.ts) so the catalog validates a binary entry"
  - phase: 28-02
    provides: "plugin/catalog/lib/prebuilt-binary.sh + al_pb_install <tool> <repo> <tag> <bin_path_in_archive> <bin_name> <dest_dir>"
provides:
  - "plugin/catalog/agents/rtk/install.sh — first source_kind:binary recipe; sources the shared helper, installs rtk-ai/rtk@<pin> to ~/.local/bin, prints the opt-in hook instruction"
  - "plugin/catalog/agents/rtk/uninstall.sh — symmetric remove: hook revert FIRST, then binary + config/cache + settings.json.bak; idempotent"
  - "catalog.json rtk entry (source_kind binary, pin 0.42.4) — proves ENABLE-01 end-to-end and the WORK-02 opt-in/symmetric-remove contract"
affects: [28-04-bats-lifecycle, 29-gh, 30-glab, 31-trivy, 32-gitleaks, 33-sentry-cli]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Thin binary recipe = set repo/tag/bin vars + one al_pb_install call (per-tool variety stays in shell; zero CLI source edits per CAT-03)"
    - "Opt-in hook via post-install echo (never auto-runs `rtk init`); defensive `rtk init --uninstall` BEFORE binary deletion on remove"
    - "Idempotent symmetric remove: every destructive step guarded / || true; hash -r + command -v truth check"

key-files:
  created:
    - plugin/catalog/agents/rtk/install.sh
    - plugin/catalog/agents/rtk/uninstall.sh
  modified:
    - plugin/catalog/catalog.json

key-decisions:
  - "No preserve_paths.json for rtk — ENABLE-01 requires remove to delete config/cache, so there is no user state to preserve across REMEDIATE-04 (matches ccusage, which also ships none)"
  - "Added compatibility_window >=0.42.0 <0.43.0 (REUSE-03) even though the plan's literal JSON omitted it — mirrors every other curated entry and keeps the pin one minor behind 0.43.0"
  - "Pin derived from AGENTLINUX_PINNED_VERSION (tag = v${pin}); the literal version string never appears in the recipe (ADR-011 single source of truth)"

requirements-completed: [WORK-02, ENABLE-01]

# Metrics
duration: 7min
completed: 2026-06-30
---

# Phase 28 Plan 03: rtk catalog recipe pair Summary

**rtk lands as the catalog's first `source_kind: "binary"` tool: `install.sh` sources the Plan 02 shared helper and `al_pb_install`s `rtk-ai/rtk@v${AGENTLINUX_PINNED_VERSION}` (never the crates.io same-named tool, never `cargo`) to `~/.local/bin/rtk`, prints the OPT-IN `rtk init -g` instruction without touching `~/.claude`; `uninstall.sh` reverts that opt-in hook FIRST then deletes the binary + `~/.config/rtk` + `~/.local/share/rtk` + the `settings.json.bak` residue, idempotently — proving ENABLE-01 end-to-end and the WORK-02 opt-in/symmetric-remove contract.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-06-30T18:51:22Z
- **Completed:** 2026-06-30T18:57:52Z
- **Tasks:** 3
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- `plugin/catalog/agents/rtk/install.sh` (44 lines) — sources `${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh` and calls `al_pb_install rtk rtk-ai/rtk "v${AGENTLINUX_PINNED_VERSION}" rtk rtk "${AGENTLINUX_AGENT_HOME}/.local/bin"`. The pin is never hardcoded; the crates.io path is never referenced; the recipe prints `rtk init -g` as an OPT-IN instruction and never invokes the rtk hook initializer as a command. shellcheck + shfmt clean.
- `plugin/catalog/agents/rtk/uninstall.sh` (45 lines) — load-bearing order: (1) `command -v rtk` guard → `rtk init --uninstall -g --auto-patch` (revert the Claude hook while the binary still exists), (2) `rm -f ~/.local/bin/rtk`, (3) `rm -rf ~/.config/rtk ~/.local/share/rtk`, (4) `rm -f ~/.claude/settings.json.bak` (never `settings.json` itself), (5) `hash -r` + on-PATH truth check. Every step guarded / `|| true` → idempotent. shellcheck + shfmt clean.
- `catalog.json` rtk entry — `source_kind: "binary"`, `pinned_version: "0.42.4"`, `compatibility_window: ">=0.42.0 <0.43.0"`, no `npm_package_name`, no `preserve_paths_file`. ajv schema validation + version-lockstep (catalog `0.3.4` == `plugin/cli/package.json` `0.3.4`) both pass; manifest version unchanged.

## Task Commits

Each task committed atomically (hooks ON — shellcheck `--severity=warning --shell=bash --external-sources`, shfmt `-i 2 -ci -bn`, ajv catalog-schema, version-lockstep, secret-scan):

1. **Task 1: rtk install.sh** — `e766129` (feat)
2. **Task 2: rtk uninstall.sh** — `89db467` (feat)
3. **Task 3: catalog.json rtk entry** — `d20efb2` (feat)

**Plan metadata:** (final commit — SUMMARY + STATE + ROADMAP + deferred-items)

## Files Created/Modified

- `plugin/catalog/agents/rtk/install.sh` — first binary recipe; sources the shared helper, version-locked install to `~/.local/bin`, opt-in hook message.
- `plugin/catalog/agents/rtk/uninstall.sh` — symmetric remove; hook-revert-first ordering, config/cache + backup cleanup, idempotent.
- `plugin/catalog/catalog.json` — appended the `rtk` binary entry after `ccusage` (manifest version untouched).

## Decisions Made

- **No `preserve_paths.json`.** The orchestrator's generic file list named one, but the plan, RESEARCH (Runtime State Inventory + Pitfall 5), and the ENABLE-01 contract all require `remove` to *delete* `~/.config/rtk` + `~/.local/share/rtk`. There is therefore no user state to preserve across a REMEDIATE-04 reinstall, and a `preserve_paths.json` would directly contradict the delete-config/cache clause. `ccusage` (the npm precedent that also owns no kept state) ships none either. Judgment: omit it.
- **Added `compatibility_window: ">=0.42.0 <0.43.0"`.** The plan's literal JSON omitted it, but the orchestrator constraint says "compatibility_window per REUSE-03" and every other curated entry carries one. The window adopts any detected `0.42.x` install while keeping the pin one minor behind the upstream `0.43.0` (ADR-011 curation). Schema-optional; ajv + lockstep stay green.
- **Pin via `AGENTLINUX_PINNED_VERSION`, tag `v${pin}`.** The bare version literal never appears in the recipe — ADR-011 stays the single source of truth (verified by `! grep -q '0.42.4'`).

## Deviations from Plan

### Clarifications / Rule-2 additions (no user permission needed)

**1. [Clarification] No preserve_paths.json artifact.** See Decisions Made. The orchestrator file list named it; the plan + research + ENABLE-01 contract dictate none. Following the plan's explicit "NO `preserve_paths_file`".

**2. [Rule 2 — consistency] Added `compatibility_window` to the catalog entry.** Not in the plan's literal JSON; added per the orchestrator's REUSE-03 constraint and to match every other curated entry. Files: `plugin/catalog/catalog.json`. Commit: `d20efb2`.

**3. [Acceptance-check clarification] Self-contradictory `rtk init` negative grep.** The plan's per-task check `! grep -Eq '^[^#]*rtk init( |$)'` cannot coexist with the must-have truth "install prints the opt-in instruction `rtk init -g`": any line that prints the literal `rtk init -g` contains the token `rtk init ` (trailing space) and therefore matches the regex. The binding contract (must_have truth + threat T-28-10) is that install must **never invoke** `rtk init` as a *command* while **printing** the instruction — both of which hold: the only `rtk init` occurrence in `install.sh` is inside an `echo` string, never a bare command. Satisfied the truth + the real threat intent; the literal regex is left unsatisfied by design (it is unsatisfiable alongside the truth).

**4. [Cosmetic] Reworded two post-`rm` comments in uninstall.sh.** The plan's awk ordering check (`u<b` on the *last* textual occurrence of `rtk init --uninstall`) was tripped by explanatory comments that re-quoted the command after the binary-`rm` line. Reworded those comments ("the hook-revert step above", "the hook revert") so the check passes. The actual command ordering — revert hook (line 23) before binary rm (line 27) — is unchanged and correct.

## Issues Encountered

- **Pre-existing CLI unit-test failure (out of scope).** `cd plugin/cli && pnpm test` reports 157 pass / 1 fail; the failing file is `plugin/cli/test/install.test.js` (suite `installCmd — REUSE-03 pre-runner check (Plan 13-02)`). Proven independent of this plan: stashing the rtk `catalog.json` entry yields the identical 157 / 1, and `rtk` is absent from the committed `HEAD` catalog, so the new binary entry cannot be the cause. The rtk entry itself validates against the schema (ajv) and round-trips through `loadCatalog`. Logged to `.planning/phases/28-rtk/deferred-items.md`; not fixed here per the scope-boundary rule.

## User Setup Required

None for install/remove themselves. The optional Claude Code hook is user-driven: after `agentlinux install rtk`, a user who wants the rtk hook runs `rtk init -g` themselves (the recipe prints this). `agentlinux remove rtk` reverts it automatically.

## Next Phase Readiness

- Plan 28-04 can write `tests/bats/57-catalog-binary.bats` exercising the full lifecycle on a provisioned host: `agentlinux install rtk` → `rtk --version` reports the pin → install left `~/.claude` untouched → manual `rtk init -g` wires the hook → `agentlinux remove rtk` reverts the hook + deletes binary/config/cache → second remove is a no-op. Plus the negative checksum-tamper test and the OPS-01 offline smoke.
- Phases 29-33 (gh, glab, trivy, gitleaks, sentry-cli) now have a worked example: a catalog entry + a thin `install.sh`/`uninstall.sh` pair against the same `al_pb_install` helper, with per-tool archive nesting handled by the `bin_path_in_archive` argument.

---
*Phase: 28-rtk*
*Completed: 2026-06-30*

## Self-Check: PASSED

- plugin/catalog/agents/rtk/install.sh: FOUND
- plugin/catalog/agents/rtk/uninstall.sh: FOUND
- plugin/catalog/catalog.json (rtk entry): FOUND
- .planning/phases/28-rtk/28-03-SUMMARY.md: FOUND
- Commit e766129 (install.sh): FOUND
- Commit 89db467 (uninstall.sh): FOUND
- Commit d20efb2 (catalog entry): FOUND
