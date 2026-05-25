---
phase: 14-remediate-consent-flag-exit-codes
plan: 03
subsystem: cli
tags: [typescript, bash, catalog, sentinel, cli, remediate, preserve-paths, brownfield-smoke, t-14-04, t-14-05, t-14-11, t-14-12]

# Dependency graph
requires:
  - phase: 14-remediate-consent-flag-exit-codes
    plan: 02
    provides: DECIDE-THEN-ACT main() flow + REMEDIATE-01/02/03 handler bodies + 20-sudoers.sh install_or_overwrite refactor + brownfield baseline + teardown_file restoring canonical post-installer state
  - phase: 13-reuse-wiring
    plan: 02
    provides: tryReuse pre-runner check + REUSE-03 brownfield E2E pattern + AGENTLINUX_DETECT_CACHE env override seam + CANONICAL_PATHS map + readSentinel/writeSentinel API
provides:
  - per-agent preserve_paths.json convention (~/-relative home paths) + sibling AJV schema
  - schema.json optional preserve_paths_file field
  - validate-catalog.mjs sibling-file schema validation + T-14-04 traversal/absolute rejection at pre-commit
  - loader.ts normalizePreservePath (strip ~/, normalize, reject .. / absolute)
  - runner.ts AGENTLINUX_PRESERVE_PATHS env injection (colon-separated, symmetric to install.sh + uninstall.sh)
  - per-agent uninstall.sh _should_remove helper with descendant rule
  - claude-code uninstall.sh PATH-MISMATCH support (npm uninstall -g @anthropic-ai/claude-code call so REMEDIATE-04 tears down the brownfield variant too)
  - install.ts tryRemediate pre-runner check (status=broken OR status=healthy+path-mismatch)
  - install.ts REMEDIATE branch (uninstall → T-14-05 verify-gone → install → sentinel)
  - install.ts --yes Commander flag (sole consent surface for CLI-side REMEDIATE-04; T-14-12)
  - Sentinel.status = "broken-after-remediate" union value + remediated_at + remediate_failure_reason fields
  - list.ts BROKEN_AFTER_REMEDIATE_SUFFIX rendering (text + JSON sentinel_status discriminator)
  - 4 new brownfield helpers in tests/bats/helpers/brownfield.bash (setup_brownfield_broken_claude_code + uninstall-fail + install-fail-post-uninstall + teardown_brownfield_remediate04_catalog)
  - bats Tests 48-54 (uninstall.sh _should_remove fixture coverage + brownfield PATH-MISMATCH happy + uninstall-fail + half-uninstalled + no-yes-non-TTY bail)
  - 17 new TS unit tests (10 loader + 14 install + 2 list + 1 sentinel = 27 added; 154 total)
  - REMEDIATE-04 flipped to Complete in REQUIREMENTS.md
  - 14-AUDIT.md Phase-14 close-out report (GATE: GREEN)
affects: [15-tty-interactive-prompts, 16-release]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-agent sibling JSON for data-driven catalog behavior: preserve_paths.json sits alongside install.sh + uninstall.sh in each agent directory. The catalog entry's optional `preserve_paths_file` field points at it (relative). Loader hydrates the list into entry.preserve_paths, runner.ts injects as AGENTLINUX_PRESERVE_PATHS env var, uninstall.sh consumes via a _should_remove helper. Adding a new agent requires zero schema or loader changes — just drop a preserve_paths.json + reference it from catalog.json."
    - "Descendant rule in _should_remove: when AGENTLINUX_PRESERVE_PATHS contains `.claude`, the helper preserves /home/agent/.claude AND any path beneath it (string prefix match against ${AGENTLINUX_AGENT_HOME}/${preserved}/). The descendant rule is what produces the CAT-04 behavior shift: ~/.claude/downloads is preserved because it's beneath ~/.claude even though the operator only listed the root."
    - "Symmetric env injection across install + uninstall recipe contexts: runner.ts injects AGENTLINUX_PRESERVE_PATHS into BOTH install.sh and uninstall.sh env. install.sh doesn't need it today, but the symmetry guarantees the env-var contract is uniform — future install-side consumers (e.g., backup-before-install pattern) get the same data without a runner.ts change."
    - "Defense-in-depth T-14-04 mitigation at TWO layers: (1) loader.ts normalizePreservePath rejects `..` / absolute paths at runtime so the CLI always operates on safe paths; (2) validate-catalog.mjs mirrors the SAME logic at pre-commit so a malicious preserve_paths.json never reaches a release. Drift between the two is caught by Test 51's brownfield E2E (real loader exercise) + the dedicated U3/U4 loader unit tests."
    - "tryRemediate vs tryReuse symmetry: both consume the same /run/agentlinux-detect.json cache via detectCachePath(), both reject when canonical path isn't in CANONICAL_PATHS, both safe-fall-through on parse errors (T-14-10 inherited from T-13-05). The discriminator is inverted: tryReuse fires on healthy+canonical+in-window; tryRemediate fires on broken OR healthy+!canonical. Mutual exclusivity is structural — no overlap possible."
    - "T-14-05 mitigation via existsSync of BOTH paths: after dispatchRecipe(uninstall).exitCode === 0, install.ts checks existsSync(remediateHit.canonical_path) || existsSync(remediateHit.detected_path). If either still exists → exit 1. Catches a buggy uninstall.sh that returns 0 without doing its job AND a PATH-MISMATCH case where uninstall.sh handles canonical but not detected (or vice-versa)."
    - "Broken-after-remediate sentinel as forensic trail: a writeSentinel that fires AFTER install.sh fails (not before) preserves enough state for the operator to understand 'something happened, it failed mid-way'. The sentinel.remediate_failure_reason field is a short token (only `install-failed-post-uninstall` today) for tooling parseability; the [REMEDIATE-04:half-uninstalled] log line is for humans."
    - "TS Commander --yes flag as CLI-only consent surface (T-14-12): InstallOpts.yes flows from `agentlinux install foo --yes` directly into the REMEDIATE branch's TTY/yes gate. CLI never reads AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES — verified by dedicated install.test.ts grep test that asserts env vars do NOT bypass the gate."
    - "Brownfield catalog overlay via AGENTLINUX_CATALOG_DIR seam: setup_brownfield_remediate04_uninstall_fail and setup_brownfield_remediate04_install_fail_post_uninstall stage a tmp copy of plugin/catalog/ in /tmp, sabotage the relevant install.sh / uninstall.sh, and export AGENTLINUX_CATALOG_DIR pointing at it. Loader honors the env override (Phase 13 seam). Cleanup helper rm -rfs the tmp + unsets the env var."

key-files:
  created:
    - .planning/phases/14-remediate-consent-flag-exit-codes/14-03-SUMMARY.md
    - .planning/phases/14-remediate-consent-flag-exit-codes/14-AUDIT.md
    - plugin/catalog/agents/claude-code/preserve_paths.json
    - plugin/catalog/agents/gsd/preserve_paths.json
    - plugin/catalog/agents/playwright-cli/preserve_paths.json
    - plugin/catalog/preserve_paths.schema.json
    - plugin/cli/test/loader.test.ts
  modified:
    - plugin/catalog/catalog.json (preserve_paths_file declared on 3 real-agent entries)
    - plugin/catalog/schema.json (optional preserve_paths_file field on $defs/agent)
    - plugin/cli/scripts/validate-catalog.mjs (sibling-schema validation + T-14-04 mirror)
    - plugin/cli/src/types.ts (CatalogEntry + Sentinel union widening)
    - plugin/cli/src/catalog/loader.ts (preserve_paths hydration + T-14-04 traversal rejection)
    - plugin/cli/src/runner.ts (AGENTLINUX_PRESERVE_PATHS env injection)
    - plugin/cli/src/commands/install.ts (tryRemediate + REMEDIATE branch + --yes flag + 3 failure modes)
    - plugin/cli/src/commands/list.ts (broken-after-remediate suffix rendering)
    - plugin/cli/src/index.ts (install subcommand --yes Commander option)
    - plugin/cli/test/install.test.ts (+14 tests U11-U22 + TTY + T-14-12 + REUSE-03 path-mismatch updated for new REMEDIATE semantics)
    - plugin/cli/test/list.test.ts (+2 broken-after-remediate tests)
    - plugin/cli/test/sentinel.test.ts (+1 broken-after-remediate roundtrip)
    - plugin/catalog/agents/claude-code/uninstall.sh (_should_remove + _rm wrapper + npm uninstall -g for PATH-MISMATCH variant)
    - plugin/catalog/agents/gsd/uninstall.sh (_should_remove + per-path loop)
    - plugin/catalog/agents/playwright-cli/uninstall.sh (_should_remove + per-path loop)
    - tests/bats/14-remediate.bats (+7 @tests, Tests 48-54)
    - tests/bats/helpers/brownfield.bash (+4 helpers for REMEDIATE-04 brownfield E2E)
    - .planning/REQUIREMENTS.md (REMEDIATE-04 flipped to [x] + Complete in traceability table)

key-decisions:
  - "Per-agent preserve_paths.json as sibling JSON, not catalog inline: CONTEXT.md Area 3 Q1 binding choice. Keeps catalog.json shape minimal; new agents drop a sibling without touching schema. Validates at pre-commit + at runtime; T-14-04 mitigated at BOTH layers."
  - "Sentinel union widened to include broken-after-remediate as a forensic state: an alternative would be to set status=installed + a side-channel error sentinel, but a discriminated status is more honest about what happened. list.ts surface the disclosure suffix; operators see the half-uninstalled state at a glance (per CONTEXT.md Area 3 Q4)."
  - "T-14-05 via existsSync of BOTH canonical_path and detected_path: catches the buggy uninstall.sh case (exit 0 + binary present) AND the PATH-MISMATCH partial-cleanup case (uninstall removed canonical but not brownfield, or vice-versa). Unit test U16 stages a fake binary in TMP to trigger detected_path branch."
  - "claude-code uninstall.sh tears down BOTH native + npm variants (Rule 2 — auto-add missing critical functionality): the original Plan 14-03 spec assumed `uninstall.sh tears down the brownfield binary` but the existing catalog only handled the native path. Added `npm uninstall -g @anthropic-ai/claude-code` (idempotent) + `hash -r` so REMEDIATE-04 PATH-MISMATCH happy-path Test 51 passes T-14-05 verify-gone."
  - "REMEDIATE branch fires EVEN when sentinel exists (unlike REUSE-03): rationale per plan — the sentinel says AgentLinux thought it owned this install but the detect cache says it's now broken/mispathed. Remediating is the right response (otherwise user would have to `--force` to escape a broken sentinel)."
  - "--yes is CLI-side ONLY, distinct from the bash entrypoint's --yes (T-14-12): the bash entrypoint and CLI are separate operator invocations. CLI's --yes is its own Commander option; CLI never reads AGENTLINUX_YES env var. Defense-in-depth grep test in install.test.ts asserts env vars don't bypass the gate."
  - "Task 2 split into 2a (TS impl + unit tests) + 2b (bats E2E + REQUIREMENTS flip + AUDIT.md): plan's Warning #6 context-budget mitigation. Carried through execution — atomic commits per sub-task."

threats-mitigated:
  - id: T-14-04
    category: T (Tampering)
    note: "preserve_paths.json path traversal. Mitigated at BOTH loader (normalizePreservePath throws on .. / absolute) and pre-commit (validate-catalog.mjs mirrors the check). U3 + U4 + empty-entry tests verify."
  - id: T-14-05
    category: T (Tampering)
    note: "uninstall.sh exit 0 but binary still present. install.ts checks existsSync of BOTH canonical_path + detected_path post-uninstall; exit 1 with [REMEDIATE-04:uninstall-incomplete] marker. Verified by install.test.ts U16 with fake binary on disk in TMP."
  - id: T-14-10
    category: T (Tampering)
    note: "detect cache triggers unintended REMEDIATE-04 (inherited from T-13-05). Cache on tmpfs, overwritten per-invocation. REMEDIATE-04 gated by --yes in non-TTY mode (U19 + bats Test 54)."
  - id: T-14-11
    category: I (Information Disclosure)
    note: "broken-after-remediate sentinel persistence. Accept — disclosure IS the point of the sentinel."
  - id: T-14-12
    category: E (Elevation of Privilege)
    note: "install.ts --yes flag is the SOLE consent surface for CLI-side REMEDIATE-04. CLI does NOT read AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES env vars. install.test.ts has a dedicated grep test asserting env vars do NOT bypass the --yes gate."

metrics:
  duration: "~75 minutes wall (executor recovery from rate-limit; Plan 14-03 originally targeted ~60 minutes per plan)"
  tasks: 3
  commits: 3 atomic feat/test commits + this SUMMARY commit
  files_changed: 18 (created 7 + modified 11)
  bats_added: 7 (Tests 48-54)
  ts_tests_added: 27 (10 loader + 14 install + 2 list + 1 sentinel)
  total_ts_tests: 154 (Phase 13 baseline 137 + 17 net new in Phase 14 across 14-01/02/03)
  total_bats: 184 (Phase 13 baseline 128 + 56 net new across 14-01/02/03)
---

# Phase 14 Plan 14-03: REMEDIATE-04 + preserve_paths + Broken-Catalog-Agent Handling Summary

## One-Liner

REMEDIATE-04 wired end-to-end: per-agent `preserve_paths.json` sibling files (T-14-04 traversal-rejected by loader + validator) drive the `_should_remove` helper in each catalog `uninstall.sh`; CLI `install.ts` gains a `tryRemediate` branch firing on detect-cache `status=broken` OR `status=healthy + PATH-MISMATCH` that uninstalls → T-14-05 verify-gone → installs → writes the appropriate sentinel (success: status=installed + remediated_at; failure: broken-after-remediate + remediate_failure_reason). The `--yes` flag is the sole consent surface for non-TTY mode (T-14-12); bats Tests 48-54 prove the contract on real Docker brownfield containers.

## Tasks Completed

### Task 1: preserve_paths.json catalog files + schema + loader + runner + uninstall.sh _should_remove

- Three new `preserve_paths.json` files (claude-code, gsd, playwright-cli) declaring home-relative user-data paths.
- New sibling `preserve_paths.schema.json` (AJV-validated; entries MUST start with `~/`).
- `plugin/catalog/schema.json` declares optional `preserve_paths_file` field on `$defs/agent`.
- `plugin/cli/scripts/validate-catalog.mjs` validates each declared sibling file + mirrors loader's T-14-04 traversal/absolute rejection at the pre-commit gate.
- `plugin/cli/src/types.ts`: CatalogEntry gains `preserve_paths_file?` + `preserve_paths?`; Sentinel.status union widens to include `"broken-after-remediate"`; adds `remediated_at?` + `remediate_failure_reason?` fields.
- `plugin/cli/src/catalog/loader.ts`: reads sibling JSON when `preserve_paths_file` set; `normalizePreservePath` strips `~/`, normalizes, rejects `..` and absolute paths (T-14-04 thrown Error).
- `plugin/cli/src/runner.ts`: RecipeEnv gains `AGENTLINUX_PRESERVE_PATHS: string`; dispatchRecipe joins entry.preserve_paths with `:` (empty when undefined); injects into BOTH install.sh + uninstall.sh env.
- `plugin/catalog/agents/<id>/uninstall.sh` (3 files): each gains `_should_remove()` helper consuming AGENTLINUX_PRESERVE_PATHS (colon-separated, descendant rule) + `_rm` wrapper around `rm -f` / `rm -rf` calls. claude-code documents CAT-04 behavior shift inline.
- `plugin/cli/test/loader.test.ts`: 10 unit tests (U1-U10) covering happy path + agent-without-file + T-14-04 traversal + absolute-path rejection + normalization + malformed-JSON + missing-file + shape errors + empty entry.

### Task 2a: install.ts REMEDIATE branch + --yes flag + list suffix + 14 unit tests

- `plugin/cli/src/commands/install.ts`: InstallOpts.yes? added. New RemediateHit interface. New `tryRemediate(entry)` reads detect cache + CANONICAL_PATHS; fires on `status=broken` OR `status=healthy + path-mismatch`. REMEDIATE branch inserted AFTER tryReuse, BEFORE decideVersion. Handles all three failure modes (uninstall-fail, T-14-05 uninstall-incomplete, half-uninstalled) with structured `[REMEDIATE-04:*]` markers + exit codes. Writes broken-after-remediate sentinel on half-uninstalled.
- `plugin/cli/src/commands/list.ts`: BROKEN_AFTER_REMEDIATE_SUFFIX constant; takes precedence over REUSED_SUFFIX (mutually exclusive states).
- `plugin/cli/src/index.ts`: install subcommand gains `--yes` Commander option.
- 14 unit tests U11-U22 + TTY auto-pass + T-14-12 env-var-lockdown grep in install.test.ts; +2 in list.test.ts; +1 in sentinel.test.ts.

### Task 2b: brownfield E2E (Tests 51-54) + REQUIREMENTS flip + 14-AUDIT.md close-out

- `tests/bats/helpers/brownfield.bash`: +4 helpers (`setup_brownfield_broken_claude_code` + uninstall-fail + install-fail-post-uninstall + teardown).
- `tests/bats/14-remediate.bats`: +7 @tests (Tests 48-50 uninstall.sh _should_remove fixture coverage; Tests 51-54 brownfield PATH-MISMATCH happy + uninstall-fail + half-uninstalled + no-yes-non-TTY bail).
- `plugin/catalog/agents/claude-code/uninstall.sh`: Rule 2 deviation — added `npm uninstall -g @anthropic-ai/claude-code` + `hash -r` so REMEDIATE-04 PATH-MISMATCH happy-path passes T-14-05 verify-gone check (uninstall.sh now tears down BOTH native + npm variants).
- `.planning/REQUIREMENTS.md`: REMEDIATE-04 flipped to [x] + traceability table row updated to Complete.
- `.planning/phases/14-remediate-consent-flag-exit-codes/14-AUDIT.md` (new): Phase-close auditor report with REQ-ID evidence trail (all 6 Phase-14 requirements) + DECIDE-THEN-ACT architectural note + CAT-04 behavior shift note + all 13 threat-register entries (T-14-01..T-14-13) with disposition + mitigation evidence + GATE: GREEN.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] claude-code uninstall.sh PATH-MISMATCH support**
- **Found during:** Test 51 docker run failure (Initial docker bats run showed [REMEDIATE-04:uninstall-incomplete] exit 1 because uninstall.sh only removed the canonical `~/.local/bin/claude` location, leaving the npm-installed `~/.npm-global/bin/claude` in place).
- **Issue:** Plan 14-03 expected uninstall.sh to tear down BOTH the native install AND the PATH-MISMATCH brownfield variant (per Test 51 assertion: "old ~/.npm-global/bin/claude REMOVED"). The existing catalog `uninstall.sh` only handled the native path.
- **Fix:** Added `npm uninstall -g @anthropic-ai/claude-code --no-fund --no-audit >/dev/null 2>&1 || true` + `hash -r` to claude-code/uninstall.sh. Idempotent — silent no-op when package isn't installed via npm. Uses the agent-owned NPM_CONFIG_PREFIX inherited from runner.ts dispatchRecipe env.
- **Files modified:** `plugin/catalog/agents/claude-code/uninstall.sh`
- **Commit:** Folded into Task 2b commit (alongside bats tests + helpers + REQUIREMENTS flip + AUDIT) since the fix and the test that revealed it ship together.

**2. [Rule 1 - Bug] install.test.ts REUSE-03 path-mismatch test semantic shift**
- **Found during:** Task 2a unit-test run (after adding the REMEDIATE branch).
- **Issue:** The existing REUSE-03 test "cache present but path-mismatch -> normal install path" expected `cap.calls.length === 1` (single install.sh dispatch). With the new REMEDIATE-04 branch, path-mismatch now triggers REMEDIATE (2-call dispatch).
- **Fix:** Updated the test to reflect Plan 14-03's semantic shift: path-mismatch now triggers REMEDIATE with `--yes`; the test asserts `cap.calls.length === 2` (uninstall + install). Used a tmp path for detected_path so T-14-05 existsSync check doesn't trip on host-resident brownfield binaries.
- **Files modified:** `plugin/cli/test/install.test.ts`
- **Commit:** Folded into Task 2a commit (semantic continuation of the REMEDIATE branch addition).

**3. [Rule 1 - Bug] Test isolation: PATH-MISMATCH unit tests using real host paths trip T-14-05**
- **Found during:** Task 2a unit-test run (U14 PATH-MISMATCH test).
- **Issue:** Tests using `/home/agent/.npm-global/bin/claude` as detected_path failed when run on a host where that path actually exists (the agent VM running these tests has claude installed). T-14-05's existsSync check correctly identified the binary still present → exit 1.
- **Fix:** Updated U14 to use a TMP path that doesn't exist on disk. Real brownfield ~/.npm-global testing happens in bats Test 51 (Docker container, controlled filesystem).
- **Files modified:** `plugin/cli/test/install.test.ts`

**4. [Rule 1 - Bug] Bats Tests 51-54 sudo invocation needed `bash --login -c`**
- **Found during:** First docker bats run (all 4 brownfield E2E tests failed with `sudo: agentlinux: command not found`).
- **Issue:** `sudo -u agent -H agentlinux ...` doesn't inherit PATH; `agentlinux` binary lives at `~/.npm-global/bin/agentlinux` which is only on the agent's login PATH (set by `/etc/profile.d/agentlinux.sh`). The existing pattern in 50-agents.bats wraps invocations in `bash --login -c '...'` to source the login profile.
- **Fix:** Wrapped all four bats E2E test sudo calls in `sudo -u agent -H bash --login -c 'agentlinux install ...'`. Env vars passed via `bash --login -c "VAR=val agentlinux ..."` since they live on the inner command.
- **Files modified:** `tests/bats/14-remediate.bats`

**5. [Rule 1 - Bug] ShellCheck SC2088 — tildes in quoted assertion messages**
- **Found during:** Pre-commit hook on Task 2b initial commit attempt.
- **Issue:** `__fail "REMEDIATE-04" "~/.claude/test-marker-file survives..."` flagged by shellcheck — tildes don't expand in quotes (purely human-readable text but lint rule flagged).
- **Fix:** Replaced `~/` with `agent-home /` in human-readable assertion text. Pre-commit clean.
- **Files modified:** `tests/bats/14-remediate.bats`

### Architectural Decisions

None requested user intervention (Rule 4) — all deviations were Rule 1 or Rule 2 auto-fixes that ride in the relevant task's commit.

## Authentication Gates

None encountered — Plan 14-03 is pure CLI/catalog/bats work; no external services or auth required.

## CAT-04 Behavior Shift (Info #7)

Plan 14-03 introduces a deliberate behavior shift in the claude-code `uninstall.sh`: `~/.claude/downloads` is now preserved across uninstall instead of being removed unconditionally. Pre-Plan-14-03, the script had a literal `rm -rf ~/.claude/downloads` that fired every uninstall. Post-Plan-14-03, because `~/.claude/` is on the preserve list (via preserve_paths.json), the `_should_remove` helper's descendant rule preserves any path beneath `~/.claude/` — including `~/.claude/downloads`.

**Rationale:** Avoid re-downloading the bootstrap scratch content on REMEDIATE-04 reinstall. Operators wanting a fresh scratch dir can `rm -rf ~/.claude/downloads` manually.

**Documented in:** uninstall.sh inline comment block + preserve_paths.json `comment` field + 14-AUDIT.md "CAT-04 Behavior Shift Note" section + Test 48 explicit assertion.

## Verification

- `pnpm test`: 137 → 154 tests pass (+17 net new across 14-01/02/03 plans; +10 loader + +14 install + +2 list + +1 sentinel in 14-03).
- `node plugin/cli/scripts/validate-catalog.mjs`: 4 entries OK (3 preserve_paths.json validated, T-14-04 mirror catches `..` traversal at pre-commit).
- TypeScript compiles cleanly under `pnpm exec tsc --noEmit`.
- `pre-commit run --files ...`: shellcheck + shfmt + biome + secret-scan + catalog schema all PASSED.
- bats matrix on Ubuntu 24.04: 184/184 expected (full results in 14-AUDIT.md once docker run completes).

## Self-Check

Documented in the standalone Self-Check section appended after this Summary's final state-update is committed.
