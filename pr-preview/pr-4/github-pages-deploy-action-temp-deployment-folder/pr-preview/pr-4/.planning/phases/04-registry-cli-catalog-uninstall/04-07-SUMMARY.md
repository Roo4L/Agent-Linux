---
phase: 04-registry-cli-catalog-uninstall
plan: 07
subsystem: testing
tags: [bats, integration, tst-07, phase-close, docker-matrix, jq, commander, positional-options]

# Dependency graph
requires:
  - phase: 04-registry-cli-catalog-uninstall
    provides: "CLI + catalog + provisioner + --purge + test-dummy fixture (Plans 04-01..04-06)"
  - phase: 02-installer-foundation-agent-user
    provides: "bats helpers invoke_modes.bash + assertions.bash (__fail + six INVOKE_MODES)"
  - phase: 03-nodejs-per-user-npm-prefix
    provides: "assert_user_prefix_in_home helper + Docker harness"
provides:
  - "tests/bats/40-registry-cli.bats — 22 @tests covering CLI-01..07 + CAT-01..04 + INST-04"
  - "INST-02 byte-stability extension with 4 deterministic Phase-4 artefacts (catalog.json, test-dummy/install.sh, agentlinux symlink target, dist/index.js shebang)"
  - "Three Rule 1 CLI fixes that together unblock install/remove/upgrade/pin on a provisioned host: schema.json resolution, agent-self-sudo elimination, --version flag scope"
  - "jq in both Docker images (Rule 3 auto-fix — prerequisite for JSON-asserting bats)"
affects: [phase 05-agents, phase 06-release, CI matrix, catalog-auditor rubric]

# Tech tracking
tech-stack:
  added: [jq]
  patterns:
    - "Every bats @test name prefixed with requirement ID (behavior-test-contract skill rule) — enforced for TST-07 auditor discoverability"
    - "Destructive --purge @tests placed LAST in bats file so subsequent @tests cannot observe a purged filesystem"
    - "setup/teardown guards on symlink presence so post-purge cleanup cannot crash on a missing binary"
    - "CAT-03 fixture pattern: mktemp + AGENTLINUX_CATALOG_DIR env override + production schema.json copy — proves the catalog-is-data contract"
    - "Commander .enablePositionalOptions() for disambiguating subcommand --version from program-level --version"
    - "Invoker==target short-circuit in asUser() to satisfy 'run as X' contract when already X without sudo-to-self"
    - "LOCKED four-item deterministic hash set for INST-02 Phase 4 extension (no whole-tree recursion)"

key-files:
  created:
    - "tests/bats/40-registry-cli.bats (505 lines, 22 @tests)"
  modified:
    - "tests/bats/10-installer.bats (INST-02 extended with 4 Phase-4 artefacts)"
    - "plugin/cli/src/catalog/schema.ts (schema resolver default-candidate fix)"
    - "plugin/cli/src/state/dispatcher.ts (invoker-equals-target short-circuit)"
    - "plugin/cli/src/index.ts (enablePositionalOptions + --json moved to subcommands)"
    - "tests/docker/Dockerfile.ubuntu-22.04 (jq added)"
    - "tests/docker/Dockerfile.ubuntu-24.04 (jq added)"

key-decisions:
  - "LOCKED INST-02 hash set — four specific items (catalog.json, test-dummy/install.sh, readlink symlink, dist/index.js shebang first line) instead of whole-tree recursion, to prevent tsc-output-ordering flakiness."
  - "enablePositionalOptions() is the Commander idiom for the --version conflict; it ALSO requires moving --json from program level to each subcommand (list, upgrade) since positional options no longer accept program-level options after a subcommand name."
  - "Agent→agent sudo is never correct under CONTEXT.md's 'zero sudoers drop-in' rule; asUser() MUST short-circuit when invoker equals target. The CLI-05 guard in guard/user.ts already ensures invoker is the agent user, so the short-circuit can never drop an intended privilege boundary."
  - "TST-07 gate: GREEN — every Phase 4 req ID (CLI-01..07, CAT-01..04, INST-04) has ≥1 bats @test citing it via the `@test \"ID: ...\"` prefix; total bats count 49 (Phase 3 baseline 27 + 22 new); Docker matrix green on both Ubuntu 22.04 and 24.04."

patterns-established:
  - "Pattern: CAT-03 catalog-is-data test — fixture-catalog via AGENTLINUX_CATALOG_DIR env + schema.json copy-from-production + unique agent id + jq assertion proves no TypeScript source was edited to surface the new agent."
  - "Pattern: INST-04 purge ordering test — install test-dummy first so step-1 uninstall.sh dispatches, then assert every one of the seven teardown steps individually with its own __fail diagnostic."
  - "Pattern: invoker-equals-target short-circuit — asUser(user, argv, opts) runs argv directly when userInfo().username === user, preserving the 'run as X' contract without requiring sudoers for agent→agent."

requirements-completed: [CLI-01, CLI-02, CLI-03, CLI-04, CLI-05, CLI-06, CLI-07, CAT-01, CAT-02, CAT-03, CAT-04, INST-04]

# Metrics
duration: ~35min
completed: 2026-04-19
---

# Phase 04 Plan 07: Phase 4 Integration Bats + INST-02 Extension + TST-07 Phase Close Summary

**22 @tests in tests/bats/40-registry-cli.bats validating CLI-01..07 + CAT-01..04 + INST-04 end-to-end on Ubuntu 22.04 + 24.04; INST-02 sha256 set extended with 4 Phase-4 artefacts via a LOCKED deterministic strategy; three Rule 1 auto-fixes unblock CLI on a provisioned host (schema resolver, agent-self-sudo, --version flag scope); TST-07 phase-close gate: GREEN.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-04-19
- **Tasks:** 3 (Task 1 bats, Task 2 INST-02 extension, Task 3 TST-07 audit)
- **Files created:** 1 (tests/bats/40-registry-cli.bats)
- **Files modified:** 5 (10-installer.bats, schema.ts, dispatcher.ts, index.ts, both Dockerfiles)
- **Commits:** 4 (2 task commits + 2 Rule-1/3 auto-fix commits)

## Accomplishments

- **22 new @tests** covering every Phase 4 requirement with an ID-prefix name → discoverable by TST-07 behavior-coverage-auditor
- **49 total bats @tests** across the suite (Phase 3 baseline 27 + 22 new), green on both Ubuntu 22.04 and 24.04 Docker images
- **INST-02 byte-stability extended** with 4 LOCKED Phase-4 items (no whole-tree recursion) plus 2 separate byte-stability checks (symlink target, dist shebang) each with its own TST-04 diagnostic
- **Three Rule 1 CLI bugs fixed** — schema.ts, dispatcher.ts, index.ts — that kept install/remove/upgrade/pin from ever reaching their handlers on a freshly-provisioned host (masked in unit tests because DI mocks bypass all three)
- **Phase 4 acceptance gate: GREEN** — every CLI-XX, CAT-XX, INST-04 requirement has ≥1 bats @test citing it

## Task Commits

Each task was committed atomically:

1. **[Rule 3 - Blocking] add jq to Docker test images** — `2e7dcc1` (fix)
2. **[Rule 1 - Bug] CLI end-to-end reachability on a provisioned host** — `aec64ac` (fix)
3. **Task 1: Phase 4 integration bats — CLI-01..07 + CAT-01..04 + INST-04** — `f64f3c4` (test)
4. **Task 2: extend INST-02 sha256 set with Phase 4 artefacts** — `1a538f0` (test)

Task 3 (TST-07 phase-close audit) produced no code commit — the audit output is captured in the Review Loop section below.

## Files Created/Modified

### Created

- **`tests/bats/40-registry-cli.bats`** (505 lines, 22 @tests). Phase 4 integration suite with the three invariants codified at the top of the file: every @test name is ID-prefixed; setup/teardown guard on symlink presence so post-purge cleanup can't crash; INST-04 @tests are placed LAST so subsequent tests can't observe a nuked filesystem.

### Modified

- **`tests/bats/10-installer.bats`** — INST-02 @test extended from 7 to 9 files in the sha256 set (+2 Phase-4 items: catalog.json, test-dummy/install.sh) plus 2 new byte-stability checks (symlink target via readlink, dist/index.js shebang via head -1 | sha256sum). LOCKED 4-item deterministic strategy — no whole-tree recursion.
- **`plugin/cli/src/catalog/schema.ts`** — resolveSchemaPath() now lists `/opt/agentlinux/catalog/<AGENTLINUX_VERSION>/schema.json` as a first-class candidate (mirrors loader.ts's defaultCatalogDir). Without this, every loadCatalog({validate:true}) threw on the production layout.
- **`plugin/cli/src/state/dispatcher.ts`** — asUser() short-circuits to direct execFile when invoker === target, eliminating agent→agent sudo attempts that fail under "zero sudoers drop-in" policy.
- **`plugin/cli/src/index.ts`** — `.enablePositionalOptions()` disambiguates the program-level `--version` flag from the install subcommand's `--version <semver>` override. Required moving `--json` from program level to each subcommand that supports it (list, upgrade).
- **`tests/docker/Dockerfile.ubuntu-22.04`** and **`Dockerfile.ubuntu-24.04`** — jq added to the apt install line (needed by the new bats file for JSON assertions + sentinel inspection).

## Decisions Made

- **LOCKED INST-02 Phase 4 hash strategy.** Four specific items hashed rather than whole-tree recursion. Rationale: tsc output across compilations can vary in file ordering / mtime; `find /opt/agentlinux/cli -type f -exec sha256sum` would be flaky across CI runs. The four items chosen — catalog.json, test-dummy/install.sh, readlink target, dist/index.js shebang first line — are all deterministic by construction (cp of checked-in files; fixed string; shebang line is stable regardless of tsc internal reordering).

- **enablePositionalOptions() over --version rename.** The plan required `agentlinux install --version 9.9.9 foo`. Two fix options: (a) rename the subcommand option to `--pin`/`--at`, breaking the plan spec; (b) use Commander's positional-options mode to make the program-level `--version` only recognized before the subcommand and the subcommand's `--version` only recognized after. Option (b) preserves the plan spec, but forces moving `--json` from program level to each subcommand that supports it — a small UX refactor captured in the same commit.

- **Invoker-equals-target short-circuit in asUser().** The dispatcher mirrors plugin/lib/as_user.sh's `sudo -u <user> -H -E --` form verbatim, but in CLI context the invoker is ALREADY the agent user (guard/user.ts CLI-05 enforces). Agent→agent sudo fails without a sudoers entry, and CONTEXT.md locks "zero sudoers drop-in." The short-circuit honors the 'run as X' contract without the sudo hop.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added jq to Docker test images**
- **Found during:** Task 1 (bats test file creation)
- **Issue:** Neither Ubuntu 22.04 nor 24.04 Docker image shipped jq. The new bats file depends on jq for JSON list/sentinel assertions — without it the suite can't run.
- **Fix:** Added jq to the apt install line in both Dockerfiles alongside bats/sudo/dbus.
- **Files modified:** tests/docker/Dockerfile.ubuntu-22.04, tests/docker/Dockerfile.ubuntu-24.04
- **Verification:** Docker build succeeds; bats JSON assertions pass on both images.
- **Committed in:** 2e7dcc1

**2. [Rule 1 - Bug] schema.ts resolver could not locate schema.json on provisioned host**
- **Found during:** Task 1 (Docker smoke of new bats file)
- **Issue:** schema.ts resolveSchemaPath() walked UP from /opt/agentlinux/cli/0.3.0/dist/catalog/schema.js looking for `catalog/schema.json` or `plugin/catalog/schema.json`, but the 50-registry-cli.sh provisioner stages schema.json in a SEPARATE subtree at /opt/agentlinux/catalog/0.3.0/. Result: every `loadCatalog({validate:true})` call (install/remove/upgrade/pin) threw "unable to locate catalog schema.json". This was masked in unit tests because DI mocks bypass the schema resolver, and masked in Plan 04-06's Docker smoke because the smoke only exercised `agentlinux --version` and `agentlinux list` (validate:false).
- **Fix:** Added `/opt/agentlinux/catalog/<AGENTLINUX_VERSION>/schema.json` as a first-class candidate in the resolver's candidates list (mirrors loader.ts's defaultCatalogDir).
- **Files modified:** plugin/cli/src/catalog/schema.ts
- **Verification:** pnpm test 112/112 still green; Docker bats 49/49 green on both Ubuntu versions.
- **Committed in:** aec64ac

**3. [Rule 1 - Bug] asUser() attempted agent→agent sudo on a production host**
- **Found during:** Task 1 (Docker smoke of new bats file)
- **Issue:** dispatcher.ts's asUser() always ran `sudo -u <user> -H -E -- <argv>`. Every CLI call site runs AS THE AGENT USER (guard/user.ts CLI-05 refuses any other invoker), so this attempted agent→agent sudo. Default Ubuntu hosts don't have agent in sudoers, and CONTEXT.md locks "zero sudoers drop-in." Every install.sh / uninstall.sh dispatch failed with "agent is not in the sudoers file."
- **Fix:** Short-circuit when `userInfo().username === user` — execFile the argv directly without the sudo hop. The sudo path still fires when called from a different invoker (provisioner tests as root; future non-agent automation).
- **Files modified:** plugin/cli/src/state/dispatcher.ts
- **Verification:** pnpm test 112/112 still green (DI mocks unaffected); Docker bats 49/49 green — install test-dummy + remove + upgrade + pin all reach their handlers.
- **Committed in:** aec64ac

**4. [Rule 1 - Bug] index.ts program-level --version flag shadowed install --version option**
- **Found during:** Task 1 (Docker smoke — CLI-03 --version override test)
- **Issue:** The program-level `.version("0.3.0", "-V, --version")` intercepted `agentlinux install --version 9.9.9 foo`, printed "0.3.0", and exited before installCmd fired. The subcommand's `--version <semver>` option (registered in index.ts) was shadowed by the global flag.
- **Fix:** Added `.enablePositionalOptions()` so global options are only recognized BEFORE the subcommand name and subcommand options only recognized AFTER it. Required moving the program-level `--json` flag onto each subcommand that supports JSON output (list, upgrade) since positional options no longer accept program-level options after a subcommand name.
- **Files modified:** plugin/cli/src/index.ts
- **Verification:** pnpm test 112/112 still green; Docker bats 49/49 green — CLI-03 --version override test asserts sentinel.source=override and sentinel.version=9.9.9.
- **Committed in:** aec64ac

---

**Total deviations:** 4 auto-fixed (1 Rule 3 blocking, 3 Rule 1 bugs). All three Rule 1 bugs were PRE-EXISTING — they landed in Plans 04-01 (schema.ts), 04-01 (dispatcher.ts), and 04-01 (index.ts), and were masked by DI-mocked unit tests + Plan 04-06's limited Docker smoke that exercised only validate:false paths. This plan was the first end-to-end bats pass that hit the mutation paths (install/remove/upgrade/pin), which is why the bugs surfaced here. Fixing them was essential — without them, zero of the CLI-03, CLI-04, CLI-06, CLI-07, CAT-01, CAT-04, CAT-03, or INST-04 @tests would have passed.

**Impact on plan:** No scope creep. All four fixes are corrective — they land the CLI contract that Plans 04-01 through 04-06 DECLARED but could not end-to-end demonstrate until the Plan 04-07 bats suite stress-tested it.

## Issues Encountered

- **Plan 04-06 smoke gap:** Plan 04-06's Docker smoke only verified `agentlinux --version` and `agentlinux list`. Neither exercised a loadCatalog({validate:true}) path nor a recipe dispatch. The three Rule 1 bugs surfaced here were therefore latent since Plan 04-01 and could have been caught earlier if 04-06's smoke had attempted `agentlinux install --include-test test-dummy`. Documented here so Phase 5's AGT-XX planning can add an explicit end-to-end smoke to its own completion criteria.

## Review Loop

### Task 1 + Task 2 (bats suite + INST-02 extension)

Rubric checks applied inline during execution:

**qa-engineer:**
- [x] Every @test has __fail diagnostic with four-line TST-04 shape (req-id / expected / observed / log hint)
- [x] setup_file / setup / teardown_file cooperate: setup() force-removes test-dummy before each test; teardown_file guards on symlink presence so post-purge cleanup can't crash
- [x] INST-04 --purge @tests placed LAST (destructive; any @test after them would see a nuked system); second-run idempotence asserted with its own @test
- [x] CAT-03 uses env-var catalog override + schema.json copy-from-production + unique fixture id — no TypeScript source touch; tmp dir cleaned up regardless of outcome
- [x] Six-mode coverage on CLI-01 (the keystone PATH test — mirrors RT-02/RT-04's precedent)
- [x] Strong assertions: sentinel fields (version + source + sticky) via jq; marker content (grep for `version=0.0.1` string); filesystem state (file presence + absence); exit codes (64 for root, 1 for not-installed, 0 for --force)
- [x] Cross-test isolation: every test resets marker + force-removes sentinel in setup()

**behavior-coverage-auditor (TST-07 gate):**

| ID       | Status  | @test Count | Test File                             |
|----------|---------|-------------|---------------------------------------|
| CLI-01   | Covered | 2           | 40-registry-cli.bats                  |
| CLI-02   | Covered | 3           | 40-registry-cli.bats                  |
| CLI-03   | Covered | 4           | 40-registry-cli.bats                  |
| CLI-04   | Covered | 2           | 40-registry-cli.bats                  |
| CLI-05   | Covered | 2           | 40-registry-cli.bats                  |
| CLI-06   | Covered | 1           | 40-registry-cli.bats                  |
| CLI-07   | Covered | 2           | 40-registry-cli.bats                  |
| CAT-01   | Covered | 1           | 40-registry-cli.bats                  |
| CAT-02   | Covered | 1           | 40-registry-cli.bats                  |
| CAT-03   | Covered | 1           | 40-registry-cli.bats                  |
| CAT-04   | Covered | 1           | 40-registry-cli.bats                  |
| INST-04  | Covered | 2           | 40-registry-cli.bats                  |

**Summary:** 12/12 Phase 4 req IDs covered. 22 @test citations across the 12 IDs. Zero uncovered. Zero partial.

**TST-07 gate: GREEN** — Phase 4 acceptance gate satisfied. All Phase 4 CLI/CAT/INST requirements have behavior coverage.

**bash-engineer (INST-02 extension):**
- [x] sha256sum multi-arg pattern consistent across pre/post snapshots; paths quoted with double quotes to tolerate future path substitutions
- [x] readlink + head -1 invocations quoted; `head -1 ... | sha256sum` produces byte-stable hash regardless of tsc internal output reordering
- [x] Three separate `[[ "$pre" == "$post" ]]` byte-stability checks each with its own __fail diagnostic (sha256 set, symlink target, shebang hash) — so a flaky artifact is pinpointable without cross-referencing the diff output
- [x] LOCKED 4-item strategy enforced: grep -Fq asserts no `/opt/agentlinux/cli -type f` or `/opt/agentlinux/catalog -type f` whole-tree recursion in the test file
- [x] shellcheck --severity=warning clean on both 10-installer.bats and 40-registry-cli.bats

No fix commits produced by the review loop beyond the auto-fixes documented above.

## User Setup Required

None — no external service configuration required. All changes are internal (CLI source, test images, test files).

## Next Phase Readiness

### What's ready for Phase 5 (Agent Installability)

- **End-to-end CLI is proven working** on Ubuntu 22.04 + 24.04. `agentlinux install <name>` / `remove` / `upgrade` / `pin` all reach their handlers, dispatch recipes correctly, and produce the expected sentinel/marker state.
- **test-dummy fixture exercises the dispatch contract** — Phase 5 can model AGT-XX tests after CLI-03/04 patterns (install → sentinel + real-tool-verify; remove → sentinel gone + tool gone from PATH).
- **CAT-03 catalog-is-data contract proven** — adding a new agent is a catalog.json edit + install.sh/uninstall.sh drop-in, zero TypeScript changes required. Phase 5's AGT-02 can drop in claude-code's real install body without touching plugin/cli/src/.
- **INST-02 extension is monotonic** — Phase 5 can add 1-2 more items to the hash set as AGT-XX provisioner artifacts land (e.g. ~/.config/<agent>/config.toml if deterministic) without changing the strategy.
- **Docker matrix stable** at 49/49 green. CI's .github/workflows/test.yml bats-docker job still passes without modification.

### Phase 4 acceptance gate

**GREEN.** All 12 Phase 4 requirements (CLI-01..07, CAT-01..04, INST-04) have behavior coverage with ≥1 bats @test each. TST-07 gate produces GREEN via the sanity-counter. Docker matrix (Ubuntu 22.04 + 24.04) is green. INST-02 extension is byte-stable across installer re-runs.

Phase 4 is ready to be marked complete.

## Self-Check: PASSED

- [x] `tests/bats/40-registry-cli.bats` exists (FOUND)
- [x] `tests/bats/10-installer.bats` modified (FOUND + 7 INST-02 references; 9-file hash set + readlink + head -1 shebang)
- [x] `plugin/cli/src/catalog/schema.ts` fix present (FOUND `/opt/agentlinux/catalog/${ver}/schema.json` candidate)
- [x] `plugin/cli/src/state/dispatcher.ts` fix present (FOUND invoker-equals-target short-circuit)
- [x] `plugin/cli/src/index.ts` fix present (FOUND enablePositionalOptions + --json on subcommands)
- [x] Both Dockerfiles modified (FOUND jq in 22.04 + 24.04)
- [x] Commits exist: 2e7dcc1 (FOUND), aec64ac (FOUND), f64f3c4 (FOUND), 1a538f0 (FOUND)
- [x] Docker 22.04 + 24.04 matrix: 49/49 green (verified)
- [x] CLI unit tests: 112/112 green (verified)
- [x] Harness meta-tests: 104/104 green (verified)
- [x] Every Phase 4 req ID has ≥1 @test (12/12)
- [x] TST-07 gate: GREEN

---
*Phase: 04-registry-cli-catalog-uninstall*
*Completed: 2026-04-19*
