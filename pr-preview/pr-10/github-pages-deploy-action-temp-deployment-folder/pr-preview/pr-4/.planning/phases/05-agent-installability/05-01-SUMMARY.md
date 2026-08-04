---
phase: 05-agent-installability
plan: 01
subsystem: agent-recipe
tags: [claude-code, native-installer, agt-02, agt-02b, release-gate, bats, curl, sudo, permission-invariant]

requires:
  - phase: 04-registry-cli-catalog-uninstall
    provides: runner.ts dispatchRecipe + AGENT_PATH env contract + Phase 4 scaffold install.sh/uninstall.sh files with :? guards + catalog.json pinned_version=2.1.98 claude-code entry
  - phase: 05.1-agent-user-sudo
    provides: /etc/sudoers.d/agentlinux (agent ALL=(ALL) NOPASSWD:ALL) — required for any future Playwright install-deps; not directly required by claude-code install, but Phase 5.1 is the declared precondition per ROADMAP.md
provides:
  - plugin/catalog/agents/claude-code/install.sh (real native-installer body with PIPESTATUS guard + AGT-02b version-lock)
  - plugin/catalog/agents/claude-code/uninstall.sh (symmetric inverse preserving user data at ~/.claude/)
  - tests/bats/51-agt02-release-gate.bats (THE canonical AGT-02 release-gate test — the whole reason v0.3.0 exists)
  - curl in Docker test images (Rule 3 auto-fix — Ubuntu minimal lacks curl by default)
affects: [phase-05-04 50-agents.bats consolidated bats plan (will exercise AGT-01 + AGT-02b + AGT-03 against the same install.sh this plan shipped), phase-06 TST-05 release-gate CI (will select 51-*.bats glob as blocking gate)]

tech-stack:
  added: [curl (Docker images only — runtime dep)]
  patterns:
    - "Pattern 1: native-installer pipe-to-bash with PIPESTATUS guard — `curl -fsSL <bootstrap-url> | bash -s \"${PINNED}\"` followed by `[[ ${PIPESTATUS[0]} -eq 0 && ${PIPESTATUS[1]} -eq 0 ]]` or the `if ! pipeline; then printf '... PIPESTATUS: %s' \"${PIPESTATUS[*]}\"; fi` shorthand. Catches curl-404 swallowed by bash receiving empty body."
    - "Pattern 2: in-recipe version-lock (AGT-02b) via `grep -q -F -- \"${PINNED}\"` against `<binary> --version`. Substring match (not equality) tolerates version-format drift (Pitfall 6). Exits 1 before sentinel is written."
    - "Pattern 3: destructive release-gate bats file naming — `51-*.bats` (or higher digits) reserves a filename-prefix range that Phase 6 CI can glob-select for release-blocking tests without pulling in non-destructive phase bats."
    - "Pattern 4: release-gate setup_file state recovery — `if [[ ! -L <symlink> ]]; then bash plugin/bin/agentlinux-install; fi` guard re-provisions the system when a preceding `--purge` test has destroyed it, so destructive-test ordering within a single bats run remains viable."
    - "Pattern 5: transcript capture via mktemp file (not bats $output) for destructive CLI tests — `run bash -c \"timeout Ns sudo -u agent -H bash --login -c '<cmd>' >${transcript} 2>&1\"` then `assert_no_eacces \"<req>\" \"$transcript\"`. Mitigates binary-stdio interleaving through bats's pipe buffer (Pitfall 4)."

key-files:
  created:
    - tests/bats/51-agt02-release-gate.bats
    - .planning/phases/05-agent-installability/05-01-SUMMARY.md
  modified:
    - plugin/catalog/agents/claude-code/install.sh (scaffold body → real native-installer body)
    - plugin/catalog/agents/claude-code/uninstall.sh (scaffold body → real symmetric inverse)
    - tests/docker/Dockerfile.ubuntu-22.04 (curl added to apt-get)
    - tests/docker/Dockerfile.ubuntu-24.04 (curl added to apt-get)
    - .planning/REQUIREMENTS.md (AGT-02 + AGT-02b checked)
    - .planning/ROADMAP.md (Phase 5 progress 1/4 + 05-01 plan row checked)
    - .planning/STATE.md (Current Position + Status + Performance Metrics row)

key-decisions:
  - "Delegate SHA/GPG verification to upstream bootstrap.sh (code.claude.com documents GPG-signed manifest since 2.1.89) — adding hand-rolled SHA256 verification in our recipe would be duplication without benefit and a maintenance burden on upstream format drift."
  - "Use positional version arg to bootstrap (`bash -s \"${PINNED}\"`) rather than environment variable or `--version` flag — positional is the documented Anthropic interface (code.claude.com/docs/en/setup#install-a-specific-version) and least likely to drift."
  - "AGT-02 samples once per release-gate run (one @test, no INVOKE_MODES loop). Looping 8 MB fetch × 6 modes would cost ~50 MB network per CI run with zero additional signal — the update path is identical regardless of invocation mode."
  - "Uninstall intentionally preserves ~/.claude/ (user data: session history, settings, OAuth credentials). Users wanting a full wipe run Phase 4's INST-04 `--purge` which sweeps the entire agent home."
  - "51-*.bats filename prefix chosen so Phase 6 `bats tests/bats/51-*.bats` release-gate glob can select destructive tests separately from Phase 5 non-destructive tests (50-agents.bats in Plan 05-04 will test AGT-01/02b/03/04/05 non-destructively)."
  - "setup_file in 51-*.bats re-runs plugin/bin/agentlinux-install when the agentlinux symlink is absent. This recovers from 40-registry-cli.bats's INST-04 --purge tests which run earlier in filename sort and destroy /opt/agentlinux, /home/agent/.npm-global/bin/agentlinux symlink, and the agent user."
  - "AGT-02b is verified BOTH in-recipe (install.sh asserts `claude --version` contains pinned_version as a substring) AND will be verified bats-side in Plan 05-04's 50-agents.bats. In-recipe enforcement catches upstream bootstrap drift before the CLI writes a success sentinel; bats enforcement satisfies TST-07's observable-behavior contract."

patterns-established:
  - "Pipe-to-bash recipe pattern (install.sh) — set -euo pipefail at top + :? fail-fast on all inputs + curl|bash with PIPESTATUS guard + post-install binary-exists check + version-lock assertion against --version output."
  - "Symmetric uninstall pattern — rm -f/rm -rf idempotent on missing targets; remove binary + first-install artefacts + scratch dirs; PRESERVE user data (session history, credentials, settings) — user-data wipe is INST-04 --purge's job, not per-recipe uninstall."
  - "Destructive release-gate bats file conventions — filename prefix reserves Phase 6 glob range; setup_file recovers from preceding --purge; mktemp transcript file (not $output); timeout Ns wall-time bound; single @test (don't multiply fetches); cleanup on pass only."

requirements-completed: [AGT-02, AGT-02b]

duration: 59min
completed: 2026-04-19
---

# Phase 05 Plan 01: Claude Code Native Installer + AGT-02 Canonical Release Gate — Summary

**Real native-installer body for claude-code (curl | bash -s pinned + PIPESTATUS + in-recipe AGT-02b version-lock) plus tests/bats/51-agt02-release-gate.bats running REAL `claude update` against Anthropic CDN — the canonical v0.3.0 acceptance test is green end-to-end.**

## Performance

- **Duration:** 59 min
- **Started:** 2026-04-19T19:14:58Z
- **Completed:** 2026-04-19T20:14:23Z
- **Tasks:** 2 planned + 2 Rule 3 auto-fix commits
- **Files modified:** 7 (2 recipes body-replaced, 1 bats created, 2 Dockerfiles patched, 2 files for this plan's own STATE/ROADMAP/REQUIREMENTS/SUMMARY)

## Accomplishments

- **AGT-02 ✓** — The canonical v0.3.0 acceptance test runs end-to-end on live Anthropic CDN. `timeout 120s sudo -u agent -H bash --login -c 'claude update'` → exit 0, transcript has zero EACCES / permission-denied lines, post-update version ≥ pinned (sort -V monotonicity).
- **AGT-02b ✓** — In-recipe version-lock via `grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"` against `claude --version` output. Fails fast if upstream bootstrap drifts from the pin; post-install sentinel is never written on drift.
- Real native-installer body in install.sh — replaces the Phase 4 SCAFFOLD with the documented Anthropic path `curl -fsSL https://claude.ai/install.sh | bash -s "${PINNED}"` + PIPESTATUS guard against curl-404/500 swallowed by bash (Pitfall 8).
- Symmetric uninstall.sh — removes binary + share + ~/.claude/downloads; intentionally preserves ~/.claude/ (user data per CAT-04; `--purge` exists for full wipe).
- 57/57 bats green on Ubuntu 22.04 + 24.04 (up from 56/56 in Phase 5.1 baseline — the +1 is the new AGT-02 release-gate test).
- Filename prefix `51-` reserves the file for Phase 6 TST-05 release-gate glob (`bats tests/bats/51-*.bats`).

## Task Commits

Each task was committed atomically:

1. **Task 1: real claude-code install.sh + uninstall.sh** — `8f7d1bf` (feat)
2. **Task 2: AGT-02 release-gate bats** — `762f80f` (test)
3. **Rule 3 auto-fix: curl in Docker test images** — `ed46da0` (fix)
4. **Rule 3 auto-fix: 51-*.bats setup_file recovers from --purge** — `af1c4f5` (fix)

## Files Created/Modified

- `plugin/catalog/agents/claude-code/install.sh` — **replaced scaffold body** with real native-installer invocation (51 lines total). Pattern 1 from 05-RESEARCH. Preserves fail-fast `:?` guards on AGENTLINUX_PINNED_VERSION + AGENTLINUX_AGENT_HOME.
- `plugin/catalog/agents/claude-code/uninstall.sh` — **replaced scaffold body** with Pattern 2 symmetric inverse (23 lines total). rm -f binary + rm -rf share + rm -rf ~/.claude/downloads; user config at ~/.claude/ preserved.
- `tests/bats/51-agt02-release-gate.bats` — **NEW** (97 lines). One @test runs REAL `claude update` against live Anthropic CDN. Transcript captured to `mktemp /tmp/agt02-claude-update.XXXXXX.log` (Pitfall 4 mitigation — binary stderr interleaves non-deterministically through bats `$output`). Three assertions: `assert_exit_zero "AGT-02"`, `assert_no_eacces "AGT-02" "$transcript"`, and `sort -V` monotonicity (post-update version ≥ pinned). Transcript cleaned on pass only (kept on failure for post-mortem). `setup_file` re-runs `plugin/bin/agentlinux-install` when the agentlinux symlink is absent (recovery from preceding INST-04 --purge in 40-*.bats).
- `tests/docker/Dockerfile.ubuntu-22.04` — curl added to apt-get (Rule 3 auto-fix).
- `tests/docker/Dockerfile.ubuntu-24.04` — curl added to apt-get (Rule 3 auto-fix).
- `.planning/REQUIREMENTS.md` — AGT-02 + AGT-02b checkboxes marked complete with test-citation text; traceability-table rows updated.
- `.planning/ROADMAP.md` — Phase 5 progress row set to "1/4 In progress"; 05-01-PLAN.md checkbox checked.
- `.planning/STATE.md` — Current Position / Status / Last activity / progress bar / Performance Metrics table row all updated.

## RESEARCH Pattern Traceability

| File | RESEARCH section | Deviations |
|------|------------------|------------|
| plugin/catalog/agents/claude-code/install.sh | §Pattern 1 (claude-code install.sh + PIPESTATUS) | Added inline comment about 4 GB RAM upstream requirement (Pitfall 2) per plan action directive; otherwise byte-equivalent to the research sample. |
| plugin/catalog/agents/claude-code/uninstall.sh | §Pattern 2 (symmetric uninstall) | None — byte-equivalent to research sample. |
| tests/bats/51-agt02-release-gate.bats | §Pattern 8 (51-agt02-release-gate.bats destructive release-gate) | **Added symlink-presence guard in setup_file** — the RESEARCH sample assumed `agentlinux install --force claude-code` would find the binary, but end-to-end Docker smoke revealed that 40-registry-cli.bats's --purge test destroys the binary before 51-*.bats runs. Mitigation: `if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then bash plugin/bin/agentlinux-install; fi` before the `agentlinux install --force` line. Logged as Rule 3 Deviation #2 below. |

## Network Timing Observed

**End-to-end Docker run (fresh build + provision + bats including AGT-02 real `claude update`):**

- Ubuntu 24.04 first run: ~6 min (bats run, including AGT-02 ~30s)
- Ubuntu 22.04 first run: ~9 min (including full Docker build from scratch with new curl layer)

**AGT-02 `claude update` wall-time in transcript:** ≤60s (well inside our `timeout 120s` bound).

**Claude-code native-installer initial install wall-time:** ~20s (curl fetch of bootstrap + native installer resolves target + downloads ~8 MB versioned binary + symlinks `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.98/`).

## AGT-02 Transcript Sample (redacted for post-run inspection)

Because the AGT-02 @test cleans up its transcript on pass, the transcript is ephemeral. Re-running with `AGENTLINUX_DOCKER_KEEP_CONTAINER=1` and manually re-invoking `claude update` inside the kept container confirmed:

- `claude --version` before AGT-02: **2.1.98 (Claude Code)** — matches the catalog pinned_version (AGT-02b ✓).
- `claude --version` after `claude update`: **2.1.114 (Claude Code)** — upstream advanced; sort -V confirms 2.1.114 ≥ 2.1.98 (monotonicity ✓).
- Binary at `/home/agent/.local/bin/claude` is a **symlink** to `/home/agent/.local/share/claude/versions/<version>/` (native-installer versioned-directory pattern — `claude update` swings the symlink to a newly-downloaded version directory without sudo).
- `grep -Eq 'EACCES|permission denied'` in the transcript: **zero matches** — the permission invariant holds. This is THE canonical v0.3.0 result.

## AGT-02b First-Install Version Observed

`claude --version` after `agentlinux install --force claude-code` (first time, fresh container) reports:

```
2.1.98 (Claude Code)
```

— exactly the pinned_version from catalog.json. The in-recipe `grep -q -F -- "2.1.98"` assertion is satisfied; install.sh exits 0; the CLI writes the sentinel at `/opt/agentlinux/state/installed.d/claude-code.json` with `{version: "2.1.98", source: "curated", …}`.

## Decisions Made

All key decisions are captured in frontmatter `key-decisions` above. Summary:

- Delegate SHA/GPG verification to upstream bootstrap.sh (GPG-signed manifest since 2.1.89) rather than duplicating in our recipe.
- Positional version arg (`bash -s "${PINNED}"`) per Anthropic docs.
- One @test in 51-*.bats (don't multiply 8 MB fetch × 6 INVOKE_MODES).
- Uninstall preserves ~/.claude/ (user data); only `--purge` wipes.
- 51-*.bats filename convention reserves Phase 6 release-gate glob.
- setup_file recovers from preceding --purge via symlink-presence guard.
- AGT-02b verified in-recipe + bats-side (bats-side lands in Plan 05-04's 50-agents.bats).

## Deviations from Plan

Two Rule 3 auto-fixes discovered during end-to-end Docker verification. Neither was in scope during planning; both unblock Task 2's acceptance criterion.

### Auto-fixed Issues

**1. [Rule 3 — Blocking] curl missing from Ubuntu minimal Docker test images**

- **Found during:** Task 2 end-to-end Docker smoke on ubuntu-24.04
- **Issue:** claude-code install.sh's first meaningful line is `curl -fsSL https://claude.ai/install.sh | bash -s "${AGENTLINUX_PINNED_VERSION}"`. Neither Ubuntu 22.04 minimal nor Ubuntu 24.04 minimal ship curl by default (`which curl` → empty in a fresh `docker run agentlinux-test:ubuntu-24.04 which curl`). Without curl, the recipe fails at the first pipe stage → `agentlinux install --force claude-code` exits non-zero → 51-*.bats setup_file fails → `not ok 57 setup_file failed`. The AGT-02 @test never ran.
- **Fix:** Added `curl` to the `apt-get install -y --no-install-recommends` line in both `tests/docker/Dockerfile.ubuntu-22.04` and `tests/docker/Dockerfile.ubuntu-24.04` (adjacent to the existing `jq` entry, with a matching explanatory comment). ca-certificates was already present, so HTTPS TLS verify works.
- **Files modified:** tests/docker/Dockerfile.ubuntu-22.04, tests/docker/Dockerfile.ubuntu-24.04
- **Verification:** Re-ran `./tests/docker/run.sh ubuntu-24.04` after rebuild — AGT-02 @test now fires (though setup_file still failed for reason #2 below, uncovered by this fix).
- **Committed in:** ed46da0 (separate fix commit, matching the project's atomic-commit discipline: Rule 3 auto-fixes that touch infrastructure are committed separately from the task they unblock, per Plan 04-07 / Plan 02-05 precedent — jq and dbus were added this same way).
- **Shape precedent:** Same "runtime dep emerged from the new implementation, fixed forward in the same plan" pattern as Plan 04-07's jq Rule 3 and Plan 02-05's dbus Rule 3.

**2. [Rule 3 — Blocking] 40-registry-cli.bats's INST-04 --purge destroys state before 51-*.bats setup_file**

- **Found during:** Task 2 second end-to-end Docker smoke (after fix #1 made bats fire)
- **Issue:** bats auto-globs `tests/bats/` in filename-sorted order; 40-*.bats runs before 51-*.bats. 40-registry-cli.bats's final two @tests (INST-04 --purge + idempotent re-purge) intentionally destroy `/opt/agentlinux`, `/home/agent/.npm-global/bin/agentlinux` (the CLI symlink), and the agent user (`userdel -r agent`). When 51-agt02-release-gate.bats's setup_file then ran `sudo -u agent -H bash --login -c 'agentlinux install --force claude-code'`, the agent user no longer existed → sudo errored out → setup_file exited non-zero → `not ok 57 setup_file failed`. This ordering issue was not visible to the plan's design because the plan treated 51-*.bats and 40-*.bats as independent.
- **Fix:** Added a symlink-presence guard to setup_file that re-runs the raw installer (`bash /opt/agentlinux-src/plugin/bin/agentlinux-install`) when `/home/agent/.npm-global/bin/agentlinux` is absent. The guard keeps isolated runs (`bats tests/bats/51-*.bats` — the Phase 6 release-gate glob) fast: when the system is already provisioned, the ~10s re-provision is skipped. An alternative — reordering bats file prefixes so 51-*.bats runs before 40-*.bats — was rejected because it would shuffle the well-established 40-*.bats filename and violate the "destructive tests run LAST within their file" convention that 40-registry-cli.bats itself establishes.
- **Files modified:** tests/bats/51-agt02-release-gate.bats
- **Verification:** Re-ran `./tests/docker/run.sh ubuntu-24.04` and `./tests/docker/run.sh ubuntu-22.04` — 57/57 bats green on both; AGT-02 @test ran to completion with exit 0 + zero EACCES + monotonicity satisfied.
- **Committed in:** af1c4f5 (separate fix commit per atomic-commit discipline).

---

**Total deviations:** 2 auto-fixed (2 × Rule 3 blocking)
**Impact on plan:** Both auto-fixes necessary for Task 2 acceptance criterion ("51-*.bats passes when invoked via the default `bats tests/bats/` glob"). Zero scope creep — each fix was the minimum change needed to unblock the canonical AGT-02 release-gate test. Same precedent as Phase 2/3/4 Rule 3 fixes that landed in the same plans they were discovered in.

## Issues Encountered

None beyond the two deviations above. The canonical AGT-02 test exercises a live third-party CDN (claude.ai → downloads.claude.ai), so a full-offline Docker harness is not viable for this specific test file — acknowledged in the plan's CONTEXT + research. For CI, network-egress is required for 51-*.bats.

## Review Loop

**Task 1 (install.sh + uninstall.sh) — catalog-auditor + security-engineer + bash-engineer rubrics applied inline** (per Phase 2-4 precedent; rubric-inline pattern established 02-01 for project bash where external subagents produce output the main agent distills without losing fidelity):

- bash-engineer: `set -euo pipefail` at top ✓; all `$VAR` quoted ✓; PIPESTATUS printed on pipe failure ✓; no raw `echo >>` appends ✓; shfmt -i 2 -ci -bn clean ✓; exit codes consistent (exit 1 on all error paths) ✓.
- security-engineer: T-05-01 supply chain — delegates SHA/GPG verification to upstream bootstrap.sh ✓; TLS enforced via `curl -fsSL` (`-f` fails on HTTP errors) ✓; no `sudo npm install -g` ✓; T-05-03 — all writes land under `${AGENTLINUX_AGENT_HOME}/.local/…` + `.claude/`, never `/usr/local/bin` ✓; user-config preservation documented ✓; pinned version flows only into positional bash arg + grep -F (no shell interpolation) ✓.
- catalog-auditor: recipe header contract ✓; CAT-04 pinned_version consumed via `${AGENTLINUX_PINNED_VERSION:?}` fail-fast ✓; symmetric uninstall (removes binary + share + scratch dir) ✓; write only under $HOME ✓; no sudo in recipe body (runner.ts owns dispatch) ✓; idempotent rm -f/rm -rf ✓.

**Task 2 (51-*.bats) — qa-engineer + behavior-coverage-auditor rubrics applied inline:**

- qa-engineer: test-ID in name ("AGT-02 (release-gate):") ✓; multiple complementary assertions (exit + no-EACCES + monotonicity) ✓; diagnostic helpers (`__fail` four-line TST-04, `assert_exit_zero`, `assert_no_eacces`) ✓; `timeout 120s` wall-time bound ✓; transcript preserved on failure for post-mortem, cleaned on pass only ✓; `setup_file()` establishes precondition + recovers from prior --purge ✓; single @test (no inadvertent fetch multiplication) ✓.
- behavior-coverage-auditor: AGT-02 coverage — @test name cites req ID (behavior-test-contract skill requirement) ✓; exercises exact BHV guarantee (`claude update` via `sudo -u agent -H bash --login -c` → exit 0 + zero EACCES) ✓; filename prefix 51- enables Phase 6 `bats tests/bats/51-*.bats` release-gate glob ✓; AGT-02b in-recipe + scheduled bats-side in 05-04 ✓; AGT-03 (`claude --help`) deferred to 05-04's 50-agents.bats per CONTEXT decision ✓; monotonicity defends against silent downgrade ✓.

**Iterations:** One iteration per task. Zero actionable findings beyond the two Rule 3 deviations documented above.

## Self-Check

All claimed files exist and all claimed commits are present.

- `plugin/catalog/agents/claude-code/install.sh` — FOUND (51 lines, executable)
- `plugin/catalog/agents/claude-code/uninstall.sh` — FOUND (23 lines, executable)
- `tests/bats/51-agt02-release-gate.bats` — FOUND (97 lines)
- `tests/docker/Dockerfile.ubuntu-22.04` — FOUND (curl in apt-get line)
- `tests/docker/Dockerfile.ubuntu-24.04` — FOUND (curl in apt-get line)
- Commits: `8f7d1bf` FOUND, `762f80f` FOUND, `ed46da0` FOUND, `af1c4f5` FOUND
- `bash tests/harness/run.sh` → 104/104
- `./tests/docker/run.sh ubuntu-22.04` → 57/57 PASS
- `./tests/docker/run.sh ubuntu-24.04` → 57/57 PASS

## Self-Check: PASSED

## Next Phase Readiness

**Phase 5 Plan 05-02 (gsd install.sh — AGT-04):** Ready. claude-code recipe pattern is now battle-tested; the same shape (`:?` guards + post-install smoke + version-lock assertion) applies to npm-based recipes with `npm install -g get-shit-done-cc@${PINNED}` replacing the `curl | bash` line. RESEARCH §Pattern 3 already has the ready-to-drop body.

**Phase 5 Plan 05-03 (playwright install.sh — AGT-05):** Ready. Playwright recipe will need `npx --yes playwright install --with-deps chromium` which does require sudo for apt-get install-deps — Phase 5.1's sudoers drop-in covers that. RESEARCH §Pattern 5 has the full body.

**Phase 5 Plan 05-04 (50-agents.bats consolidated bats):** Ready. Will exercise AGT-01 (claude --version × 6 INVOKE_MODES + gsd --version + playwright --version), AGT-02b (bats-side version assertion), AGT-03 (claude --help substitute per RESEARCH Alternatives), AGT-04, AGT-05. 50-*.bats filename runs BEFORE 51-*.bats so 50's tests don't need --purge recovery.

**Phase 6 (release):** The `bats tests/bats/51-*.bats` glob is live and selectable. Phase 6 TST-05 can wire it into the release-gate CI job without any further bats-side coordination.

## Threat Flags

No new threat surface beyond the plan's `<threat_model>` register. T-05-01 (supply chain), T-05-02 (destructive update DoS/availability), T-05-03 (deferred) all mitigated as designed. Nothing to add.

---
*Phase: 05-agent-installability*
*Plan: 01 — claude-code native installer + AGT-02 release gate*
*Completed: 2026-04-19*
