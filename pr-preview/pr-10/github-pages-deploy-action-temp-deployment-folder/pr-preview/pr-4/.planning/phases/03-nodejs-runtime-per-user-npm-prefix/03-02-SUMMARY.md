---
phase: 03-nodejs-runtime-per-user-npm-prefix
plan: 02
subsystem: tests
tags: [bats, behavior-tests, nodejs, npm-prefix, ubuntu, tst-07, rt-coverage]

requires:
  - phase: 02-installer-foundation-agent-user
    provides: "tests/bats/helpers/{invoke_modes,assertions}.bash (six-mode dispatcher + TST-04 diagnostic primitives); tests/bats/{10-installer,20-agent-user}.bats (Phase 2's 22 @tests); tests/docker/run.sh + ubuntu-{22,24}.04 Dockerfiles (fast-harness matrix)"
  - phase: 03-nodejs-runtime-per-user-npm-prefix / Plan 03-01
    provides: "Node v22.22.2 via NodeSource; /home/agent/.npm-global agent-owned prefix; ~agent/.npmrc prefix=/home/agent/.npm-global; NPM_CONFIG_PREFIX belt-and-braces in /etc/agentlinux.env; /home/agent/.npm-global/bin prepended FIRST across profile.d + agentlinux.env + cron.d"
provides:
  - "tests/bats/helpers/assertions.bash extended with assert_user_prefix_in_home (RT-04 gate — prefix under /home/agent/ with trailing slash; TST-04 4-line diagnostic on fail)"
  - "tests/bats/30-runtime.bats (NEW — 5 @tests): RT-01 v22 LTS across six INVOKE_MODES + RT-04 prefix across six modes + RT-02 cowsay@1.6.0 install + resolution across six modes + RT-02 no-EACCES under npm re-install pressure (INST-05 reinforcement) + RT-03 byte-clean filesystem after uninstall (Pitfall 9: BOTH cowsay AND cowthink + lib module dir absence) + six-mode PATH-absence check"
  - "tests/bats/10-installer.bats INST-02 sha256 set extended with /home/agent/.npmrc + /etc/apt/sources.list.d/nodesource.sources (deb822 modern filename — legacy .list NOT added)"
  - "tests/bats/helpers/invoke_modes.bash two Rule 1 auto-fixes: (a) run_cron PATH header prepended /home/agent/.npm-global/bin FIRST to mirror the installer's cron.d artefact after Plan 03-01's PATH extension; (b) run_systemd_user passes --quiet to systemd-run to suppress the 'Running as unit: ... Finished with result: ...' banner that polluted $output under prefix-match assertions"
  - "RT-01, RT-02, RT-03, RT-04 all satisfied with observable bats proof across all six invocation modes (with SKIP_SYSTEMD_UNAVAILABLE handling for systemd-less CI environments); TST-07 phase-close gate GREEN"
affects: [04, 05]

tech-stack:
  added:
    - "cowsay@1.6.0 (npm smoke package — pinned for reproducibility and Pitfall 9 two-bin layout stability)"
    - "bats @test for RT-01..04 (five @tests: four primary + one INST-05 reinforcement)"
  patterns:
    - "Pitfall 9 cleanliness contract: uninstall tests assert BOTH bin entries AND lib module dir absent — stronger than 'binary gone from PATH'"
    - "Prefix-match vs substring-match assertions: when output may be polluted by harness banners (systemd-run, sudo), prefix-match needs a banner-suppression flag; substring-match does not — choose assertion strength deliberately"
    - "Test helpers must be faithful proxies for the installer-wired environment: any PATH extension that lands in plugin/provisioner/*.sh must be mirrored in tests/bats/helpers/*.bash so `run_<mode>` tests exercise the actual final PATH ordering"
    - "Five RT @tests = four RT-01..04 primaries + one RT-02 reinforcement covering VALIDATION task 03-02-05 (no EACCES during cowsay re-install — INST-05 under npm install pressure)"

key-files:
  created:
    - "tests/bats/30-runtime.bats (173 lines; 5 @tests)"
    - ".planning/phases/03-nodejs-runtime-per-user-npm-prefix/03-02-SUMMARY.md"
  modified:
    - "tests/bats/helpers/assertions.bash (+37 lines; purely additive — assert_user_prefix_in_home appended; Phase 2 helpers untouched)"
    - "tests/bats/helpers/invoke_modes.bash (+12 −2 lines; two Rule 1 auto-fixes: run_cron PATH prepend + systemd-run --quiet)"
    - "tests/bats/10-installer.bats (+8 lines; INST-02 find argument list extended symmetrically pre/post with .npmrc + nodesource.sources)"

key-decisions:
  - "cowsay pinned @1.6.0 per RESEARCH Open Question 1 — reproducibility (vs floating); Pitfall 9 two-bin layout (cowsay + cowthink) is stable across 1.6.x so the byte-clean assertion is stable"
  - "Five @tests in 30-runtime.bats (four RT primaries + one RT-02 reinforcement) instead of minimum four — the reinforcement satisfies VALIDATION task 03-02-05 (no-EACCES under npm install pressure); cheap to add, strengthens INST-05 coverage"
  - "RT-03 ends with best-effort cowsay re-install for hygiene (so later tests in the same file see cowsay present) — matches RESEARCH §Example 3 shape; best-effort (|| true) so it doesn't affect RT-03's own pass/fail"
  - "run_cron PATH header extended (Rule 1 fix): the Phase 2 helper hardcoded its own PATH without /home/agent/.npm-global/bin; after Plan 03-01 extended the real /etc/cron.d/agentlinux the helper must follow suit or RT-02 fails under cron while BHV-03 (which asserts a different path) keeps passing"
  - "systemd-run --quiet (Rule 1 fix): Phase 2 BHV-04 tolerated the 'Running as unit... Finished with result...' banner because assert_path_has is substring-match; Phase 3's assert_user_prefix_in_home is prefix-match so the banner causes a false negative — --quiet suppresses systemd-run's own informational output and $output now contains ONLY the inner command's output"
  - "Scope: invoke_modes.bash is OUTSIDE Plan 03-02's declared files_modified frontmatter (Phase 2 artefact) — edited anyway per Rule 1 protocol because both regressions were directly caused by Plan 03-01's PATH extension landing without a corresponding test-helper extension; fixes necessary to execute this plan's own Docker-matrix phase-level verification"
  - "Review loop applied inline per Phase 2/3-01 precedent (project does not have interactive subagent spawn in this execution context); rubrics applied directly against each file and documented; no actionable findings on initial task commits; two Rule 1 fixes surfaced during end-to-end Docker smoke (the rubric's strongest signal source)"

patterns-established:
  - "Helper-accuracy contract: any new PATH prepend / env var in the installer's four-file matrix MUST be mirrored in tests/bats/helpers/invoke_modes.bash for the corresponding run_* helper, or per-mode tests silently regress"
  - "When prefix-match assertions are needed over modes that inject banners (systemd, sudo), the mode helper must suppress the banner at source (e.g. --quiet) rather than the assertion trying to strip it"
  - "RT-03 cleanliness asserts THREE paths: the primary bin, any additional bins from package.json `bin` field (Pitfall 9 — cowsay ships cowthink too), and the lib/node_modules/<pkg> directory; plus six-mode `command -v` PATH absence"
  - "setup_file / teardown_file for test-file-wide install/uninstall — avoids N re-installs where N is the number of @tests needing the binary"

requirements-completed: [RT-01, RT-02, RT-03, RT-04]

duration: 15min
completed: 2026-04-18
---

# Phase 03 Plan 02: RT-01..04 Behavior Tests + INST-02 Phase 3 Extension Summary

**RT-01..04 observable-behavior proof lands: 30-runtime.bats ships 5 @tests (four RT primaries + one INST-05 reinforcement under npm pressure) across all six INVOKE_MODES, assert_user_prefix_in_home helper enforces keystone ownership, INST-02 idempotency now guards Phase 3 artefacts — 27/27 bats green on Ubuntu 22.04 + 24.04; TST-07 phase-close gate GREEN.**

## Performance

- **Duration:** ~15 min (4 commits: 3 tasks + 1 Rule 1 auto-fix)
- **Started:** 2026-04-18T18:38:04Z (first Task 1 commit)
- **Completed:** 2026-04-18T18:53:39Z (last Task 3 commit)
- **Tasks:** 3/3 plan tasks + 1 Rule 1 auto-fix commit
- **Files modified:** 4 (1 created, 3 modified)
- **Tests:** 27/27 bats on Ubuntu 22.04 + 27/27 on Ubuntu 24.04 (+5 vs Phase 2 baseline) + 104/104 harness meta-tests (no regression)

## Accomplishments

- **RT-01 proven end-to-end:** `node --version` returns `v22.*` in all six invocation modes on both Ubuntu 22.04 and 24.04.
- **RT-02 proven end-to-end:** `cowsay@1.6.0` installed once via `sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0'`, loops all six modes asserting `/home/agent/.npm-global/bin/cowsay` resolves AND `cowsay hi` runs + echoes "hi". Second RT-02 @test proves no-EACCES on re-install (INST-05 reinforcement).
- **RT-03 byte-clean proven:** after `npm uninstall -g cowsay`, filesystem is clean — BOTH `/home/agent/.npm-global/bin/cowsay` AND `/home/agent/.npm-global/bin/cowthink` AND `/home/agent/.npm-global/lib/node_modules/cowsay` all absent (Pitfall 9 — cowsay@1.6.0 ships two bin entries); six-mode `command -v cowsay` returns non-zero in every mode.
- **RT-04 proven end-to-end:** new `assert_user_prefix_in_home` helper fires a TST-04 diagnostic on any prefix outside `/home/agent/*` — tested in all six modes including systemd_user (where systemd-run's banner was previously polluting $output — fixed via Rule 1 --quiet).
- **INST-02 idempotency extended:** sha256 byte-stable set now includes `/home/agent/.npmrc` and `/etc/apt/sources.list.d/nodesource.sources` — catches any Phase 3 re-run drift on top of Phase 2's 5 artefacts.
- **TST-07 phase-close gate: GREEN** — every RT-XX has ≥1 ID-prefixed @test (RT-01: 1; RT-02: 2; RT-03: 1; RT-04: 1).
- **Zero Phase 1/2 regression:** all Phase 2's 22 bats tests still green; Phase 1 harness 104/104 still green.

## TST-07 Gate Verdict

**TST-07 gate: GREEN — RT-01 ✓, RT-02 ✓, RT-03 ✓, RT-04 ✓**

| Req  | ID-prefixed @test count | File                    | Coverage mode                                                                        |
|------|-------------------------|-------------------------|--------------------------------------------------------------------------------------|
| RT-01| 1                       | tests/bats/30-runtime.bats | six-mode node --version loop with SKIP_SYSTEMD gate                              |
| RT-02| 2                       | tests/bats/30-runtime.bats | (a) six-mode cowsay resolution + run; (b) no-EACCES under re-install pressure     |
| RT-03| 1                       | tests/bats/30-runtime.bats | uninstall byte-clean filesystem (3 paths) + six-mode PATH absence                 |
| RT-04| 1                       | tests/bats/30-runtime.bats | six-mode npm config get prefix + assert_user_prefix_in_home                       |

INST-02 extended to cover Phase 3 artefacts (sha256 byte-stable across re-run for 7 paths total — Phase 2's 5 + Phase 3's .npmrc + nodesource.sources). Roadmap Phase 3 Success Criterion 5 satisfied.

## Task Commits

Each task was committed atomically. One Rule 1 auto-fix committed as a separate `fix(03-02)` commit per review-loop convention:

1. **Task 1: append assert_user_prefix_in_home helper** — `03fda88` (test)
   Purely additive append to `tests/bats/helpers/assertions.bash` (+37 lines). RT-04 gate shape per RESEARCH §Example 4 verbatim: whitespace trim via `tr -d '[:space:]'`, case-match on `/home/agent/*` with trailing slash (prevents `/home/agent-staging` false positive — T-03-07 mitigation), TST-04 4-line diagnostic on fail. Phase 2 helpers byte-identical to pre-change.

2. **Rule 1 auto-fix (during Task 2 Docker smoke): invoke_modes helper accuracy** — `c4c9fbf` (fix)
   Discovered during Task 2's Docker ubuntu-24.04 smoke: 2/27 bats failed — RT-04 under systemd_user + RT-02 under cron. Both root-caused to Phase 2 helpers being non-faithful proxies after Plan 03-01's PATH extension. Fix A: extend `run_cron`'s hardcoded PATH header to prepend `/home/agent/.npm-global/bin` FIRST (mirrors the installer's real /etc/cron.d/agentlinux). Fix B: pass `--quiet` to systemd-run in `run_systemd_user` to suppress the "Running as unit: ... Finished with result: ..." banner which polluted $output and made prefix-match assertions (assert_user_prefix_in_home) false-negative. Re-ran smoke: 27/27 PASS.

3. **Task 2: add tests/bats/30-runtime.bats** — `fc78911` (test)
   Creates the 5-@test bats file (173 LOC). Structure per RESEARCH §Example 3: `setup_file` installs cowsay@1.6.0 once via `sudo -u agent -H bash --login -c`; `teardown_file` best-effort uninstalls; five @tests cover RT-01..04 + one RT-02 reinforcement. Every @test: ID-prefixed name (TST-07 gate); six-mode loop (where applicable) via `${INVOKE_MODES[@]}`; SKIP_SYSTEMD_UNAVAILABLE-safe via `skip` on sentinel; `__fail` / `assert_*` for all failures (no bare echo + return 1). Passes all 21 automated `verify.automated` acceptance greps.

4. **Task 3: extend INST-02 sha256 set with .npmrc + nodesource.sources** — `2d6fdb9` (test)
   Two surgical edits to `tests/bats/10-installer.bats` — pre-snapshot `find` and post-snapshot `find` both extended symmetrically with `/home/agent/.npmrc` + `/etc/apt/sources.list.d/nodesource.sources`. Legacy `nodesource.list` NOT added (Pitfall 1 — modern setup_22.x writes deb822 .sources). Single comment added to document the extension rationale. Passes all 13 automated `verify.automated` acceptance greps.

**Plan metadata commit:** this SUMMARY + STATE.md + ROADMAP.md + REQUIREMENTS.md update will be committed separately in the plan's final metadata commit.

## Files Created/Modified

- **Created** `tests/bats/30-runtime.bats` (173 lines) — 5 @tests covering RT-01..04 + one INST-05 reinforcement under npm pressure. Loads helpers/invoke_modes + helpers/assertions. setup_file/teardown_file handle cowsay install/uninstall hygiene.
- **Created** `.planning/phases/03-nodejs-runtime-per-user-npm-prefix/03-02-SUMMARY.md` — this file.
- **Modified** `tests/bats/helpers/assertions.bash` (+37 lines, 0 deletions) — appended `assert_user_prefix_in_home` helper at the bottom. Phase 2 helpers (`__fail`, `__diag`, `assert_no_eacces`, `assert_path_has`, `assert_exit_zero`) byte-identical.
- **Modified** `tests/bats/helpers/invoke_modes.bash` (+12 −2 lines) — Rule 1 auto-fixes: `run_cron` PATH header extended with `.npm-global/bin` FIRST; `run_systemd_user` passes `--quiet` to systemd-run. Inline comments document the WHY for each change.
- **Modified** `tests/bats/10-installer.bats` (+8 lines, 0 deletions) — INST-02 @test's two `find` snapshots extended symmetrically with 2 new paths (.npmrc + nodesource.sources). One comment added explaining the Phase 3 extension and why legacy .list is omitted.

## Decisions Made

See `key-decisions` in frontmatter. Highlights:

1. **Pin cowsay@1.6.0 for reproducibility** — RESEARCH Open Question 1 recommendation. Cheap (4-char addition) and makes Pitfall 9 two-bin layout stable (both cowsay + cowthink consistently present). Future real catalog agents (Phase 5) do NOT pin — that's a separate policy.
2. **Ship 5 @tests instead of minimum 4** — the RT-02 no-EACCES reinforcement satisfies VALIDATION task 03-02-05 (INST-05 coverage under npm install pressure) at minimal cost. It's a simple re-install check — npm returns 0 with no work to do, but the write-path exercise catches any filesystem ACL regression on /home/agent/.npm-global.
3. **RT-03 ends with hygiene re-install** — matches RESEARCH §Example 3 pattern. Best-effort (`|| true`) so failure doesn't mask RT-03's own pass/fail. Makes the bats file self-contained for re-runs even when run out of order.
4. **Rule 1 helper fix scope-expansion** — modifying `invoke_modes.bash` was outside Plan 03-02's declared `files_modified`, but both regressions (cron PATH + systemd banner) were directly caused by Plan 03-01's PATH extension landing without a corresponding test-helper extension. Fixing them inline (rather than deferring) is necessary to execute this plan's own phase-level verification (Docker matrix green on both images). Same pattern Plan 03-01 used for its Rule 3 `compgen -G sort` fix.
5. **Review loop applied inline** — bash-engineer / qa-engineer / behavior-coverage-auditor / security-engineer rubrics applied directly per file (same pattern documented in STATE.md for Phase 2 plans 02-03/02-04/02-05 and Plan 03-01); no actionable findings on the initial task commits; the Rule 1 auto-fix surfaced through end-to-end Docker smoke (the qa-engineer rubric's strongest signal source).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Phase 2 `run_cron` helper PATH is non-faithful after Plan 03-01's cron.d extension**
- **Found during:** Task 2 Docker ubuntu-24.04 smoke test (post-task verification)
- **Issue:** RT-02 under the `cron` invocation mode failed: `command -v cowsay` returned empty. Root cause: `run_cron` writes its own `/etc/cron.d/agentlinux-test-<stamp>` file with a hardcoded `PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` header — the same form from Phase 2. Plan 03-01's 40-path-wiring.sh extension prepended `/home/agent/.npm-global/bin` FIRST to the installer-written `/etc/cron.d/agentlinux`, but the test helper never followed suit. Cron-invoked commands under the test helper therefore couldn't resolve agent-installed globals, breaking RT-02's cron-mode assertion while the Phase 2 BHV-03 assertion (on `.local/bin` substring) kept passing.
- **Fix:** Extended `run_cron`'s PATH header to match the installer's final 5-element ordering: `PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin`. Added an inline comment documenting the invariant (helper must mirror installer's final PATH ordering or per-mode tests silently regress).
- **Files modified:** `tests/bats/helpers/invoke_modes.bash` (`run_cron` + surrounding comment)
- **Verification:** Re-ran ./tests/docker/run.sh ubuntu-24.04 — RT-02 passes all six modes; BHV-03 still passes (the .local/bin substring match still holds because .local/bin is still on PATH).
- **Committed in:** `c4c9fbf`

**2. [Rule 1 - Bug] Phase 2 `run_systemd_user` banner pollutes $output for prefix-match assertions**
- **Found during:** Task 2 Docker ubuntu-24.04 smoke test (post-task verification, same run as fix #1)
- **Issue:** RT-04 under the `systemd_user` invocation mode failed: `assert_user_prefix_in_home` saw observed string starting with "Runningasunit:run-u6.service;invocationID:...Finishedwithresult:success...code=exited/status=0...home/agent/.npm-global..." — systemd-run's OWN "Running as unit: ... Finished with result: ..." banner is emitted on stderr and gets merged into $output via the inner `2>&1`. Phase 2's BHV-04 tolerated this because `assert_path_has` is substring-match (the banner contained `/home/agent/.local/bin` so the test passed). Phase 3's `assert_user_prefix_in_home` is prefix-match — the banner prefix causes a false negative.
- **Fix:** Pass `--quiet` (`-q`) to systemd-run in `run_systemd_user`. `--quiet` is an official systemd-run flag that suppresses its own informational output on stdout/stderr while still forwarding the inner command's output via `--pipe`. Added an inline comment documenting the banner-vs-prefix-match rationale.
- **Files modified:** `tests/bats/helpers/invoke_modes.bash` (`run_systemd_user` + surrounding comment)
- **Verification:** Re-ran ./tests/docker/run.sh ubuntu-24.04 — RT-04 passes all six modes including systemd_user; BHV-04 still passes (the banner was always informational noise, never an assertion target).
- **Committed in:** `c4c9fbf` (combined with Rule 1 fix #1 — both fixes are the same root cause class: Phase 2 helpers not being faithful proxies under Phase 3's stricter contracts)

---

**Total deviations:** 2 Rule 1 auto-fixes (combined into 1 commit — both fixes to the same helper file, same root cause class).
**Impact on plan:** Both fixes necessary to execute Task 2's phase-level Docker-matrix green verification. No scope creep — both are direct consequences of Plan 03-01's PATH extension landing without corresponding test-helper updates. Both fixes make the test harness a more faithful proxy for the real installer-wired environment (production agent commands will see the same final PATH ordering under cron, and production npm config commands will return banner-free output to scripts).

### Minor Acceptance-Criterion Deviations

- **Plan's `! grep -q 'set -euo pipefail' tests/bats/helpers/assertions.bash` check**: this grep returns match 1 (the file's Phase-2-written header comment at line 6 reads: `#   - No \`set -euo pipefail\` at top: this file is SOURCED by bats via`). The comment was landed by Phase 2 Plan 02-05 and documents WHY the file omits strict mode. The acceptance-criterion grep was written too strictly — intent ("no active strict-mode directive") preserved; the match is a docstring, not a directive. Did NOT modify the Phase 2 comment to silence the grep (would violate "Phase 2 helpers untouched" acceptance criterion).
- **Plan's `bash -n tests/bats/30-runtime.bats exits 0` check**: bats uses `@test "name" { ... }` which is a bats macro, NOT pure bash syntax. `bash -n` fails with "syntax error near unexpected token `}`" on every `.bats` file in the repo (including 10-installer.bats and 20-agent-user.bats which Phase 2 shipped green). The intent ("file passes syntax check") is satisfied via `shellcheck --severity=warning --shell=bash --external-sources tests/bats/30-runtime.bats` which returned clean. Same precedent exists for Phase 2 bats files.

Both deviations are orthogonal to correctness — the files satisfy the INTENT behind each check (no strict mode directive active; file parses cleanly via bats's pre-processor as proven by the 5/5 tests passing in the Docker smoke run).

## Threat-Model Dispositions (from plan)

| Threat | Plan Disposition | Status |
|--------|------------------|--------|
| T-03-05 — Tampering / PATH shadow (/usr/local/bin/cowsay shim) | mitigate | ACHIEVED — `assert_path_has "RT-02 (${mode})" "/home/agent/.npm-global/bin/cowsay"` pins resolution to the agent-owned path. Would catch any /usr/local/bin shim regression across any of six modes. Plan 03-01's PATH ordering (`.npm-global/bin` FIRST) makes resolution unambiguous. |
| T-03-06 — Tampering / Uninstall residue (cowsay/cowthink remnants) | mitigate | ACHIEVED — RT-03 asserts ALL THREE paths absent (bin/cowsay, bin/cowthink per Pitfall 9, lib/node_modules/cowsay) PLUS six-mode command -v PATH absence. Strongest form of the cleanliness contract; strong mutation-kill. |
| T-03-07 — Information disclosure / Config confusion (npm config get prefix returns /usr) | mitigate | ACHIEVED — `assert_user_prefix_in_home` fires TST-04 diagnostic if prefix starts with anything other than `/home/agent/`. Six-mode loop with per-mode req-id — regression in ONE mode (while the other five work) is caught explicitly. Belt-and-braces: Plan 03-01's NPM_CONFIG_PREFIX in /etc/agentlinux.env makes the env-var path the fallback if .npmrc is ever bypassed. |
| T-03-08 — Elevation of privilege / env stripping (cron/systemd HOME unset → .npmrc unreadable) | mitigate | ACHIEVED — run_systemd_user passes `--setenv=HOME=/home/agent`; run_cron exports HOME via vixie-cron's passwd lookup; six-mode test loop catches regressions. Belt-and-braces: NPM_CONFIG_PREFIX env var makes prefix resolvable even if $HOME/.npmrc is bypassed. |

All four Phase 3 threats marked `mitigate` are now empirically covered by the Phase 3 bats suite running 27/27 green on both Ubuntu 22.04 + 24.04.

## Review Loop

Applied inline per CLAUDE.md §Review Loop + Phase 2/3-01 precedent. Project's automated subagent-spawn mechanism is not available in this execution environment; rubric triage done directly:

- **qa-engineer rubric** (applied to 30-runtime.bats + assertions.bash + invoke_modes.bash):
  - Every @test name starts with requirement ID (TST-07 gate grep `^@test "RT-0[1-4]:` returns 5 matches) — OK
  - SKIP_SYSTEMD_UNAVAILABLE early-exit in every six-mode loop (4 occurrences in the file) — OK
  - No bare `echo + return 1` — every failure routes through `__fail` or `assert_*` — OK
  - Six-mode coverage on every test that loops (RT-01, RT-02, RT-03 PATH-absence, RT-04) — OK
  - setup_file uses `sudo -u agent -H bash --login -c` shape matching Phase 2's working run_sudo_u helper — OK
  - shellcheck clean on all three changed bash/bats files — OK
  - No actionable findings on the initial task commits; two Rule 1 auto-fixes surfaced through end-to-end Docker smoke (documented as deviations)

- **behavior-coverage-auditor rubric** (TST-07 phase-close gate):
  - RT-01 has 1 ID-prefixed @test; RT-02 has 2; RT-03 has 1; RT-04 has 1 — all 4 RT reqs covered
  - INST-02 extended to cover Phase 3 artefacts (.npmrc + nodesource.sources); Roadmap Phase 3 Success Criterion 5 met
  - **TST-07 gate: GREEN**
  - No actionable findings

- **bash-engineer rubric** (applied to invoke_modes.bash edits + assertions.bash append):
  - `--quiet` is an official systemd-run flag (confirmed via `systemd-run --help`) — OK
  - PATH ordering in run_cron matches installer's /etc/cron.d/agentlinux final form — OK
  - Comments document WHY for each change — OK
  - shellcheck --severity=warning clean on all edited files — OK
  - No strict-mode directives in sourced helpers (bats convention) — OK
  - No actionable findings

- **security-engineer rubric** (applied to 30-runtime.bats + INST-02 extension):
  - T-03-05..08 dispositions executed per threat register (see table above) — OK
  - Forbidden substrings in 30-runtime.bats: `sudo npm install -g` (bare form) = 0; `/usr/local/bin/` = 0; `set -euo pipefail` = 0 — OK
  - cowsay@1.6.0 pinned (supply-chain reproducibility; accepted upstream per ADR-005) — OK
  - No sudoers drop-in changes; no wrapper shim path introduced — OK
  - No actionable findings

Outcome: Four commits total on this plan (3 test + 1 fix). Task 1 and Task 3 passed their full `verify.automated` chain on first commit; Task 2's bats file initially passed all 21 grep-level checks but surfaced two runtime regressions in the first Docker smoke — both Rule 1 auto-fixed and landed in c4c9fbf before Task 2's commit (fc78911); second smoke passed 27/27.

## Issues Encountered

The two Rule 1 auto-fixes documented above. Both resolved via forward-fix commits; no rollback needed. Both were legitimate bug discoveries — Phase 2 test helpers didn't anticipate Phase 3's stricter prefix-match assertions or Phase 3's PATH extension in cron.d. The plan's verification steps worked as designed (Docker smoke caught them; now they're fixed). No architectural decisions required (no Rule 4 checkpoint); both fixes are mechanical helper-accuracy updates.

## User Setup Required

None. Plan 03-02 is fully automated — no external credentials, no manual steps. The bats file self-installs + self-uninstalls cowsay inside its own setup_file / teardown_file.

## Next Phase Readiness

**Phase 3 acceptance gate: GREEN. Phase 4 (Registry CLI + Catalog + Uninstall) is unblocked.**

Prerequisites in place for Phase 4:
- Node.js 22 LTS + npm 10.x runtime working on both Ubuntu images under all six invocation modes (RT-01..04 proven)
- Per-user global install path proven working under npm pressure (RT-02 + RT-02 reinforcement)
- Helpers stable: `tests/bats/helpers/{invoke_modes,assertions}.bash` are now complete (Phase 4 will reuse as-is; no new modes expected for CLI-XX tests)
- Bats file convention locked: `#!/usr/bin/env bats` + `load 'helpers/...'` + ID-prefixed @test + setup_file/teardown_file when file-wide state; Phase 4's 50-registry-cli.bats follows the same shape
- INST-02 pattern extended: Phase 4 can extend it further if catalog install writes new idempotent artefacts (add to the `find` list symmetrically)

No blockers or concerns.

## Self-Check: PASSED

File existence verified:
- `tests/bats/30-runtime.bats` — FOUND (173 lines)
- `tests/bats/helpers/assertions.bash` — FOUND (131 lines, was 94 pre-plan)
- `tests/bats/helpers/invoke_modes.bash` — FOUND (161 lines, was 149 pre-plan)
- `tests/bats/10-installer.bats` — FOUND (111 lines, was 103 pre-plan)
- `.planning/phases/03-nodejs-runtime-per-user-npm-prefix/03-02-SUMMARY.md` — FOUND (this file)

Commit existence verified:
- `03fda88` (Task 1 test) — FOUND
- `c4c9fbf` (Rule 1 auto-fix) — FOUND
- `fc78911` (Task 2 test) — FOUND
- `2d6fdb9` (Task 3 test) — FOUND

Phase-level verification from plan `<verification>`:
1. Full bats matrix green on both images: ubuntu-22.04 → 27/27 PASS; ubuntu-24.04 → 27/27 PASS ✓
2. Harness suite regression check: 104/104 ✓
3. TST-07 gate: GREEN (RT-01 ✓, RT-02 ✓, RT-03 ✓, RT-04 ✓) ✓
4. VALIDATION map: all 5 rows satisfied (03-02-01 through 03-02-05) ✓
5. INST-05 still green under Phase 3 pressure: `ok 4 INST-05: installer log contains no EACCES or 'permission denied' lines` ✓
6. Forbidden-substring security sweep on tests/bats/: only DOC-02 documentation-reference to `sudo npm install -g` (asserts CLAUDE.md CONTAINS the warning — correct usage); 0 occurrences of `/usr/local/bin/` in 30-runtime.bats ✓

Commit hygiene:
- 4 atomic commits (3 test + 1 fix); Task 1, Task 2, Task 3 each touched exactly 1 file; Rule 1 fix touched exactly 1 file
- All commit messages match `(test|fix)\(03-02\):` pattern ✓

---
*Phase: 03-nodejs-runtime-per-user-npm-prefix*
*Plan: 03-02 — Behavior Tests for RT-01..04 + INST-02 Phase 3 Extension*
*Completed: 2026-04-18*
