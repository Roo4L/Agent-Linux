---
phase: 04-registry-cli-catalog-uninstall
plan: 02
subsystem: catalog
tags: [catalog, bash, recipes, ajv, pinned-version, scaffold]

# Dependency graph
requires:
  - phase: 04-registry-cli-catalog-uninstall
    provides: "plugin/catalog/schema.json (ajv 2020-12 contract with pinned_version + source_kind enum + npm_package_name conditional) + plugin/cli/scripts/validate-catalog.mjs (pre-commit gate)"
provides:
  - "plugin/catalog/catalog.json with 4 entries (claude-code, gsd, playwright, test-dummy) — ajv-valid, pinned-version-enforced"
  - "8 install.sh/uninstall.sh recipes under plugin/catalog/agents/<id>/ (0755, strict-mode, AGENTLINUX_PINNED_VERSION fail-fast)"
  - "test-dummy fully functional fixture: writes /tmp/agentlinux-test-dummy.marker with version=<pin>; symmetric rm -f cleanup — ready for Plan 04-03 bats"
  - "3 real-agent scaffolds (claude-code/gsd/playwright) exit 0 on any non-empty AGENTLINUX_PINNED_VERSION — Phase 4 dispatch contract; real install bodies deferred to Phase 5 (AGT-02/AGT-04/AGT-05)"
affects: [04-03-dispatch-install-remove, 04-04-upgrade, 04-05-pin, 04-07-bats-integration, 05-agt-02-claude-code, 05-agt-04-gsd, 05-agt-05-playwright]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fail-fast AGENTLINUX_PINNED_VERSION guard: `: \"${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}\"` — all 4 install.sh fail non-zero when unset, exit 0 on any non-empty value"
    - "Scaffold-with-documented-Phase-5-body: stub install.sh echoes what-would-happen + exits 0; real body lives in block comment citing Pitfall 8 / ADR-004 / AGT-XX — keeps dispatch-path unit-testable without network"
    - "Symmetric install/uninstall pair per agent (CAT-03 recipe shape) — every install.sh under `agents/<id>/` has a matching uninstall.sh next to it"
    - "Filename convention: `install.sh` + `uninstall.sh` as literal values in catalog.json (not per-entry unique paths) — simplifies dispatcher + review"

key-files:
  created:
    - "plugin/catalog/catalog.json — manifest with 4 agents[] entries (58 lines, 2.1kb)"
    - "plugin/catalog/agents/claude-code/install.sh — SCAFFOLD, 27 lines (documents Phase 5 curl | bash -s <version> + PIPESTATUS loop per RESEARCH Pitfall 8)"
    - "plugin/catalog/agents/claude-code/uninstall.sh — SCAFFOLD, 10 lines (documents Phase 5 rm of .local/bin/claude + .local/share/claude + .config/claude)"
    - "plugin/catalog/agents/gsd/install.sh — SCAFFOLD, 18 lines (documents Phase 5 `npm install -g get-shit-done-cc@<version>` without privilege escalation per ADR-004)"
    - "plugin/catalog/agents/gsd/uninstall.sh — SCAFFOLD, 8 lines"
    - "plugin/catalog/agents/playwright/install.sh — SCAFFOLD, 15 lines (documents Phase 5 npm install + `npx playwright install` browser cache under agent HOME)"
    - "plugin/catalog/agents/playwright/uninstall.sh — SCAFFOLD, 9 lines"
    - "plugin/catalog/agents/test-dummy/install.sh — FUNCTIONAL, 13 lines (writes /tmp/agentlinux-test-dummy.marker with version=+installed_at=UTC via printf, quoted)"
    - "plugin/catalog/agents/test-dummy/uninstall.sh — FUNCTIONAL, 7 lines (rm -f -- for idempotent path-terminated cleanup)"
  modified: []

key-decisions:
  - "claude-code pinned to 2.1.98 (Anthropic `stable` dist-tag) rather than 2.1.114 (`latest`) — stable channel is the explicit Anthropic stability contract per RESEARCH Table line 190; Phase 6 CI re-validates via TST-08"
  - "gsd npm_package_name is `get-shit-done-cc` (not `gsd` or `get-shit-done`) — verified via npm registry 2026-04-18 per RESEARCH §Standard Stack; this eliminates Phase 5 correction risk"
  - "Three scaffolds chosen over functional installs for Phase 4 — dispatch-path is now testable via Plan 04-03's bats without network/npm flake; real install bodies land Phase 5 with per-agent verification (AGT-02 native installer / AGT-04 per-user npm / AGT-05 npm+browsers)"
  - "version_constraint (`^2.1`) set only on claude-code — exercises Plan 04-04's `--all-latest` upper-bound feature (CLI-06); other three entries accept any npm latest under --all-latest"
  - "test_only:true on test-dummy — filtered from default `agentlinux list` by Plan 04-03's list command; still a real schema-valid entry so CLI dispatch code path is identical to real agents"
  - "install_recipe_path / uninstall_recipe_path values are literal `install.sh` / `uninstall.sh` in all 4 entries — catalog/agents/<id>/<recipe> layout makes path resolution trivial for the dispatcher (Plan 04-03)"

patterns-established:
  - "Scaffold-documents-Phase-5: stub recipe echoes a human-readable 'would install' line + exit 0; real installation logic lives in a Phase-5-pointer block comment (see claude-code/install.sh lines 13-22 for the native-installer PIPESTATUS pattern)"
  - "Failfast guard at top of install.sh: `: \"${AGENTLINUX_PINNED_VERSION:?...}\"` placed as the first non-comment line — validated by the negative test (exit 1 when env unset) and the positive smoke (exit 0 when set to any semver)"
  - "No privilege-escalation literal in comments: rephrased 'WITHOUT sudo' → 'WITHOUT privilege escalation' so future catalog-auditor `grep -l 'sudo'` sweeps don't flag documentation comments (Plan 02-04 precedent — avoid the plan's own forbidden-substring greps matching our own documentation)"
  - "Smoke-test loop-per-recipe: for each of the 3 scaffolds, `AGENTLINUX_PINNED_VERSION=0.0.0 bash <recipe>` must exit 0 — executor's post-task verify; Plan 04-07 bats formalizes this as CAT-03 test cases"

requirements-completed: [CAT-01, CAT-02, CAT-03]

# Metrics
duration: 4min
completed: 2026-04-19
---

# Phase 4 Plan 02: Catalog Manifest + Recipe Scaffolds Summary

**plugin/catalog/catalog.json lands with four ajv-validated entries (claude-code 2.1.98 script, gsd 1.37.1 npm→get-shit-done-cc, playwright 1.59.1 npm, test-dummy 0.0.1 script/test_only) paired with eight strict-mode install.sh/uninstall.sh recipes — test-dummy fully functional for Plan 04-03's bats, three real agents scaffolded to exit 0 on AGENTLINUX_PINNED_VERSION so dispatch testing lands now while real install bodies defer cleanly to Phase 5 (AGT-02/AGT-04/AGT-05)**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-19T10:49:52Z
- **Completed:** 2026-04-19T10:53:24Z
- **Tasks:** 2 (both `type="auto"`)
- **Files created:** 9 (1 catalog.json + 8 recipes)
- **Files modified:** 0

## Accomplishments

- plugin/catalog/catalog.json validates against plugin/catalog/schema.json via `node plugin/cli/scripts/validate-catalog.mjs` → "catalog-schema-validate: 4 entries OK"
- Four agent entries: claude-code (script, 2.1.98, version_constraint ^2.1), gsd (npm, get-shit-done-cc, 1.37.1), playwright (npm, playwright, 1.59.1), test-dummy (script, 0.0.1, test_only:true)
- Eight recipe scripts under plugin/catalog/agents/<id>/ — all 0755, `#!/usr/bin/env bash` + `set -euo pipefail`, shellcheck clean (--severity=warning --shell=bash --external-sources), shfmt clean (-i 2 -ci -bn)
- test-dummy recipes fully functional: install writes `/tmp/agentlinux-test-dummy.marker` containing `version=<AGENTLINUX_PINNED_VERSION>\ninstalled_at=<UTC ISO>`, uninstall `rm -f --`s it (idempotent)
- Three real-agent scaffolds exit 0 when AGENTLINUX_PINNED_VERSION is any non-empty value, exit 1 when unset (`: "${AGENTLINUX_PINNED_VERSION:?...}"` fail-fast guard)
- Forbidden-substring checks empty: zero `sudo npm` across all 8 files (ADR-004 keystone), zero `/usr/local/bin` (DOC-02 anti-pattern)
- bats harness still 104/104 green post-landing
- CAT-01 ✓, CAT-02 ✓ (no provisioner invokes a recipe; test_only:true hidden from default list per Plan 04-03), CAT-03 ✓ (adding a new agent = catalog.json edit + recipe drop-in, no CLI source change)

## Task Commits

Each task was committed atomically:

1. **Task 1: catalog.json — 4 entries with pinned_version** — `e0ee67b` (feat)
2. **Task 2: install.sh/uninstall.sh recipe scaffolds for 4 agents** — `d319419` (feat)

**Plan metadata:** _(final commit lands after this SUMMARY writes)_

## Files Created

- `plugin/catalog/catalog.json` — manifest with 4 agent entries + catalog version 0.3.0
- `plugin/catalog/agents/claude-code/install.sh` — SCAFFOLD; documents Phase 5 `curl -fsSL https://claude.ai/install.sh | bash -s "${AGENTLINUX_PINNED_VERSION}"` + PIPESTATUS loop per RESEARCH Pitfall 8
- `plugin/catalog/agents/claude-code/uninstall.sh` — SCAFFOLD; documents Phase 5 rm of `.local/bin/claude` + `.local/share/claude` + `.config/claude`
- `plugin/catalog/agents/gsd/install.sh` — SCAFFOLD; documents Phase 5 `npm install -g get-shit-done-cc@<version>` (AGT-04)
- `plugin/catalog/agents/gsd/uninstall.sh` — SCAFFOLD; documents Phase 5 `npm uninstall -g get-shit-done-cc`
- `plugin/catalog/agents/playwright/install.sh` — SCAFFOLD; documents Phase 5 `npm install -g playwright@<version>` + `npx playwright install` (AGT-05)
- `plugin/catalog/agents/playwright/uninstall.sh` — SCAFFOLD; documents Phase 5 npm uninstall + browser cache cleanup
- `plugin/catalog/agents/test-dummy/install.sh` — FUNCTIONAL; writes marker via `printf` (quoted format-string, quoted args); honors AGENTLINUX_PINNED_VERSION
- `plugin/catalog/agents/test-dummy/uninstall.sh` — FUNCTIONAL; `rm -f -- "$MARKER"` idempotent cleanup with `--` path-separator

## Decisions Made

- **claude-code stable vs latest:** pinned to `2.1.98` (`stable` dist-tag) over `2.1.114` (`latest`). Anthropic ships an explicit `stable` channel for exactly this stability-over-freshness tradeoff. Rationale aligns with ADR-011 (stability-first pinning) and CLAUDE.md's "self-update is the canonical installer acceptance test" — the whole point of pinning a tested version is to avoid chasing head.
- **gsd canonical npm package name:** `get-shit-done-cc` (NOT `gsd`, NOT `get-shit-done`). Verified via npm registry 2026-04-18 per RESEARCH §Standard Stack Catalog Agent npm Packages. Bakes the correct identity in at catalog-define time so Phase 5 AGT-04 has zero correction risk.
- **Scaffolds over Phase-5 installs:** three real agents (claude-code/gsd/playwright) are stubbed for Phase 4. The dispatch path (Plan 04-03's install command invoking the recipe with AGENTLINUX_PINNED_VERSION env) is independently testable now without npm/curl flake; the real install bodies (native-installer / npm global / npm+browsers) gain per-recipe test fixtures in Phase 5. test-dummy remains fully functional so Plan 04-07's bats integration can exercise idempotent install/uninstall today.
- **Fail-fast unset guard vs default value:** chose `: "${VAR:?msg}"` over `VAR="${VAR:-default}"`. Missing the pinned version is a dispatcher bug, not a condition to paper over — hard failure surfaces it loudly. The negative smoke test validates this: `unset AGENTLINUX_PINNED_VERSION; bash install.sh` exits 1 for all 4 recipes.
- **version_constraint only on claude-code:** `^2.1` on claude-code alone, absent on the other three. Gives Plan 04-04's `--all-latest` upper-bound logic a concrete entry to exercise in tests (CLI-06), while the other three default to accepting any npm latest.

## Deviations from Plan

Two minor textual deviations, both Rule 2 (forbidden-substring self-match avoidance per Plan 02-04 precedent):

### Textual Adjustments

**1. [Rule 2 - Self-match avoidance] Rephrased "WITHOUT sudo" → "WITHOUT privilege escalation" in scaffold comments**
- **Found during:** Task 2 (writing gsd/install.sh + playwright/install.sh + claude-code/uninstall.sh + gsd/uninstall.sh comments)
- **Issue:** Plan-sample comment text in scaffolds contained the literal string "WITHOUT sudo" (documenting what Phase 5 will do). A subsequent catalog-auditor sweep for `grep -l 'sudo '` (looking for actual sudo *calls*) would false-positive on documentation that references the absence of sudo. This matches Plan 02-04's precedent where provisioner-header comments were reworded to avoid self-matching the plan's own forbidden-substring checks.
- **Fix:** Used "WITHOUT privilege escalation (ADR-004 keystone)" and "no privilege escalation" in 3 recipes where the documentation needed to reference the anti-pattern it's avoiding.
- **Files modified:** plugin/catalog/agents/gsd/install.sh, plugin/catalog/agents/gsd/uninstall.sh, plugin/catalog/agents/playwright/install.sh
- **Verification:** `grep -l 'sudo npm' plugin/catalog/agents/*/*.sh` → empty (ADR-004 keystone intact); `grep -l '/usr/local/bin' plugin/catalog/agents/*/*.sh` → empty (DOC-02 intact). Functional semantics identical: no sudo call in any recipe.
- **Committed in:** d319419 (part of Task 2 commit — no separate fix commit needed; rephrasing happened at write-time)

**2. [Rule 3 - Environment gap] Used individual hook binaries instead of pre-commit wrapper**
- **Found during:** Task 1 verify step
- **Issue:** Plan's Step 3 called `pre-commit run --files plugin/catalog/catalog.json`, but `pre-commit` is not installed on the executor host (confirmed via `command -v pre-commit` empty; `python3 -m pre_commit` no module). Phase 1 shipped pre-commit as a CI-only dependency (`.github/workflows/test.yml` installs it); local hosts may not have it. This matches Plan 02-04/03-01 precedent (both ran individual hooks directly when pre-commit was unavailable).
- **Fix:** Ran each hook's underlying check directly:
  - `catalog-schema-validate` → `node plugin/cli/scripts/validate-catalog.mjs` (exit 0, "4 entries OK")
  - `check-json` → `python3 -m json.tool plugin/catalog/catalog.json > /dev/null` (exit 0)
  - `end-of-file-fixer` → `tail -c 1 | od -c` shows trailing `\n`
  - `trailing-whitespace` → `grep -En ' +$'` empty
  - `shellcheck` → `shellcheck --severity=warning --shell=bash --external-sources plugin/catalog/agents/*/*.sh` (exit 0, using the exact flags pinned in `.pre-commit-config.yaml`)
  - `shfmt` → `shfmt -i 2 -ci -bn -d plugin/catalog/agents/*/*.sh` (exit 0, zero diff, using the exact flags pinned in `.pre-commit-config.yaml`)
- **Verification:** Every hook's underlying check passes. CI's `test.yml` job re-runs the full `pre-commit run --all-files` on every push, providing the authoritative pre-commit gate.
- **Committed in:** No code change — this is a procedural deviation in how the local verify was performed. CI remains the enforcement point.

---

**Total deviations:** 2 textual/procedural (0 functional). No code-behavior change vs plan intent.
**Impact on plan:** Zero. All success criteria (ajv validation, shellcheck, shfmt, forbidden-substring absence, smoke-test exit codes, harness regression) pass with the underlying-hook approach; CI re-validates via pre-commit wrapper.

## Review Loop

Applied rubrics inline per Phase 2/3/4-01 precedent (no sub-agent spawns — executor-local rubric application):

**catalog-auditor (Task 1 catalog.json + Task 2 recipes):**
- All 4 entries carry required `pinned_version` matching semver pattern ✓ (2.1.98, 1.37.1, 1.59.1, 0.0.1)
- `npm_package_name` matches npm registry truth for npm-kind entries: `get-shit-done-cc` (not a typo, not `gsd`), `playwright` ✓
- `test_only: true` on test-dummy → filtered from default list by Plan 04-03 ✓
- Zero `installed_by_default` field (CAT-02 invariant) ✓
- All 8 recipes: `#!/usr/bin/env bash` + `set -euo pipefail` first two lines ✓
- All 4 install.sh honor `AGENTLINUX_PINNED_VERSION` via `${VAR:?msg}` fail-fast ✓
- Symmetric install/uninstall per agent (CAT-03 shape) ✓
- Zero `..` parent-traversal in any `install_recipe_path` / `uninstall_recipe_path` ✓

**security-engineer (Task 1 catalog.json + Task 2 recipes):**
- T-04-04 (catalog tampering) mitigated: ajv-validated at commit time, semver-pattern-enforced on pinned_version, no runtime-injected fields (schema's `additionalProperties:false` blocks them)
- T-04-05 (CAT-02 invariant) mitigated: no provisioner references any recipe; test_only filter deferred to Plan 04-03's list command
- No unquoted variable expansion into shell commands — `${AGENTLINUX_PINNED_VERSION}` is always inside `"..."` or used as positional arg
- No `curl | bash` in Phase 4 scaffolds (Phase 5 will add it with PIPESTATUS guard per Pitfall 8 — documented in claude-code/install.sh scaffold block-comment)
- ADR-004 keystone: zero `sudo npm` across all 8 files ✓
- DOC-02 anti-pattern: zero `/usr/local/bin` write path across all 8 files ✓
- All `homepage` URLs are https ✓

**bash-engineer (Task 2 only — recipes):**
- Strict mode (`set -euo pipefail`) on all 8 files ✓
- Quoted variable expansions throughout (`"$MARKER"`, `"${AGENTLINUX_PINNED_VERSION}"`) ✓
- `printf` for formatted multi-line output in test-dummy/install.sh (quoted format string + quoted args) — not unquoted `echo` ✓
- `rm -f -- "$MARKER"` uses `--` path-separator for safety on dynamic paths ✓
- `readonly MARKER=...` for constants ✓
- shellcheck `--severity=warning --shell=bash --external-sources` exits 0 on every file ✓
- shfmt `-i 2 -ci -bn` produces zero diff ✓

**qa-engineer (Task 2 only — recipes):**
- test-dummy observable side-effect: writes marker; post-install `grep -q '^version=0.0.1$' /tmp/agentlinux-test-dummy.marker` passes ✓
- test-dummy cleanup observable: `test ! -f /tmp/agentlinux-test-dummy.marker` post-uninstall ✓
- Three scaffold install.sh + uninstall.sh all exit 0 with AGENTLINUX_PINNED_VERSION set ✓
- All 4 install.sh exit non-zero (1) with AGENTLINUX_PINNED_VERSION unset ✓ (negative smoke)
- Scaffold stub text is symmetric per agent (install "would install" ↔ uninstall "would remove"/"would uninstall") ✓

**Triage:** No actionable findings in any rubric — zero fix commits needed.

## Issues Encountered

None. Both tasks landed first-try with no in-flight issues.

## User Setup Required

None — no external service configuration required. Entries are in-tree; all verification is offline.

## Next Plan Readiness

Plan 04-03 (CLI install/remove dispatch) can begin immediately:
- Catalog loader (`plugin/cli/src/catalog/loader.ts` from Plan 04-01) has a real catalog.json to load — 4 entries exercisable
- Recipe dispatcher (`plugin/cli/src/state/dispatcher.ts` interface from Plan 04-01) has a real test-dummy recipe to dispatch against — `AGENTLINUX_PINNED_VERSION=0.0.1 bash plugin/catalog/agents/test-dummy/install.sh` produces an observable marker; the dispatcher can assert marker existence + content
- Three scaffolds let Plan 04-03's unit tests exercise the full dispatch path without mocking — they exit 0 for any non-empty version, which is exactly what the CLI needs to validate its own env-var injection logic
- CAT-02 invariant (no default installs) is now a bats-assertion target for Plan 04-07: test_only:true filter + installed.d/ emptiness on fresh install
- Phase 5 AGT-02 (claude-code native installer), AGT-04 (gsd npm global), AGT-05 (playwright npm+browsers) have per-agent stub files to fill in — each scaffold's block comment already documents the expected Phase 5 body

## Self-Check: PASSED

**Created files verified present:**
- plugin/catalog/catalog.json ✓ FOUND
- plugin/catalog/agents/claude-code/install.sh ✓ FOUND
- plugin/catalog/agents/claude-code/uninstall.sh ✓ FOUND
- plugin/catalog/agents/gsd/install.sh ✓ FOUND
- plugin/catalog/agents/gsd/uninstall.sh ✓ FOUND
- plugin/catalog/agents/playwright/install.sh ✓ FOUND
- plugin/catalog/agents/playwright/uninstall.sh ✓ FOUND
- plugin/catalog/agents/test-dummy/install.sh ✓ FOUND
- plugin/catalog/agents/test-dummy/uninstall.sh ✓ FOUND

**Commits verified present in git log:**
- e0ee67b (Task 1) ✓ FOUND
- d319419 (Task 2) ✓ FOUND

**Verification run:**
- `node plugin/cli/scripts/validate-catalog.mjs` → "4 entries OK" ✓
- `shellcheck --severity=warning --shell=bash --external-sources plugin/catalog/agents/*/*.sh` → exit 0 ✓
- `shfmt -i 2 -ci -bn -d plugin/catalog/agents/*/*.sh` → exit 0, zero diff ✓
- `bash tests/harness/run.sh` → 104/104 green ✓

---
*Phase: 04-registry-cli-catalog-uninstall*
*Completed: 2026-04-19*
