---
phase: 13-reuse-wiring
plan: 01
subsystem: reuse
tags: [bash, reuse, provisioner, detection, sudo, nodejs, idempotency]

# Dependency graph
requires:
  - phase: 12-detection-layer
    provides: "detect::user_* + detect::nodejs_* + detect::npm_prefix_* readers; DETECT_* env exports populated by detect::run_once; [DET-NN] log marker convention"
provides:
  - "plugin/lib/reuse.sh + plugin/lib/reuse/{user,nodejs}.sh — reuse decision orchestrator + per-component decision functions returning {reuse, create, remediate, bail} on stdout"
  - "detect::user_can_sudo_apt reader (NOPASSWD-for-apt sudo bar — REUSE-01 amendment 2026-05-16)"
  - "REUSE-01 short-circuit at the top of 10-agent-user.sh: case-branch on reuse::user_decision wraps useradd + locale-gen in REUSED_USER guard; DOC-02 ensure_marker_block stays unconditional"
  - "REUSE-02 short-circuit at the top of 30-nodejs.sh: case-branch on reuse::nodejs_decision; reuse arm logs marker + return 0; create arm falls through (v0.3.0 byte-identical)"
  - "Phase 13 → Phase 14 dispatch-shape contract: case branches enumerate {reuse, create, remediate, bail} for users + {reuse, create} for nodejs; Phase 14 replaces remediate/bail branches WITHOUT changing the surface"
  - "[REUSE-01] + [REUSE-02] log markers (mirroring [DET-NN] key=value convention)"
affects: [Phase 14 Remediate, Phase 13-02 catalog-agent REUSE-03, Phase 15 dry-run]

# Tech tracking
tech-stack:
  added: [reuse.sh, reuse/user.sh, reuse/nodejs.sh, detect::user_can_sudo_apt reader]
  patterns:
    - "Per-component decision functions return one of {reuse, create, remediate, bail} on stdout; provisioner-side `case \"$(reuse::*_decision)\" in` block is the dispatcher"
    - "Phase 14 extends remediate/bail case arms with real handlers WITHOUT changing dispatch shape (forward-compat contract)"
    - "REUSE branch is non-mutating against the existing user: useradd + ensure_dir + locale-gen wrapped in REUSED_USER guard; DOC-02 ensure_marker_block + 40-path-wiring stay unconditional (additive)"
    - "T-13-02 mitigation: probe uses absolute /usr/bin/apt-get + raw sudo -u -n (NOT as_user -H -E) to defeat PATH-shim attack against bare apt-get + preserve passwordless-failure exit-1 surfacing"

key-files:
  created:
    - "plugin/lib/reuse.sh — orchestrator (mirrors detect.sh structure; source-once guard; sources per-component files)"
    - "plugin/lib/reuse/user.sh — REUSE-01 decision (5 predicates: present, /bin/bash, home_writable, --user-name match, NOPASSWD-for-apt) + reuse::log_user_reuse"
    - "plugin/lib/reuse/nodejs.sh — REUSE-02 decision (ANY entry: Node 22 + writable prefix) + reuse::log_nodejs_reuse with defensive fallback marker"
    - "tests/bats/13-reuse.bats — 21 @tests across 3 tasks (REUSE-01 detector x4, REUSE-01 decision x6, REUSE-02 decision x4, entrypoint order x1, dispatch-shape gates x2, marker presence x1, DOC-02 additive x1, no mode flags x1, @test-count invariant x1)"
  modified:
    - "plugin/lib/detect/user.sh — extended detect::user_probe to populate DETECT_USER_CAN_SUDO_APT + JSON can_sudo_apt field; added detect::user_can_sudo_apt reader function"
    - "plugin/lib/detect/render.sh — emits `[DET-01] user.can_sudo_apt=...` marker line"
    - "plugin/bin/agentlinux-install — sources reuse.sh AFTER detect.sh + detect::run_once, BEFORE run_provisioners"
    - "plugin/provisioner/10-agent-user.sh — REUSE-01 case-branch dispatch + REUSED_USER guard wrapping useradd + ensure_dir + locale-gen; DOC-02 stays unconditional"
    - "plugin/provisioner/30-nodejs.sh — REUSE-02 case-branch dispatch; reuse arm returns 0 with defensive npm_prefix_writable warn"
    - "plugin/provisioner/40-path-wiring.sh — 8-line documentation comment explaining unconditional execution under both branches"
    - ".planning/REQUIREMENTS.md — REUSE-01 + REUSE-02 checkbox bullets flipped [ ]→[x]; traceability table rows Pending→Complete"

key-decisions:
  - "Dispatch contract is the surface: case branches enumerate all four tokens {reuse, create, remediate, bail} for users + {reuse, create} for nodejs; Phase 14 extends branches in-place without changing the surface"
  - "REUSE branch is non-mutating: existing user's identity + locale + .npmrc + Node install are NOT touched; only the DOC-02 CLAUDE.md marker block + PATH-wiring artefacts (root-owned + additive) attach to the existing user"
  - "Predicate ordering in reuse::user_decision puts cheap structural failures first (present → shell → home_writable → --user-name mismatch — all bail) then the only fixable failure (NOPASSWD-for-apt — remediate). Wrong-shell never reaches the remediate branch."
  - "T-13-02 mitigation locked: detect::user_can_sudo_apt uses absolute path /usr/bin/apt-get and raw `sudo -u <user> -n` (NOT as_user -H -E --) — passwordless-sudo-failure must surface as exit 1, never hang on a password prompt"
  - "REUSE-02 has no remediate branch on the Node-install layer — REMEDIATE-01 (Phase 14) handles wrong-owner npm prefix at the npm-prefix layer instead (CONTEXT.md Area 1 Q2 lock)"
  - "No mode flags introduced (no --reuse-strict / --reuse-best-effort / --no-reuse) — per CONTEXT Q4 user-locked decision; per-component decisions only"
  - "reuse::log_nodejs_reuse defensive fallback: emits marker even when no writable Node-22 entry found (would only fire if a caller bypassed the decision-function gate; surfaces partial data for debug readers rather than silent)"

patterns-established:
  - "Decision function contract: per-component reuse::<X>_decision returns one of {reuse, create, remediate, bail} on stdout; caller-side `case \"$(...)\" in` is the dispatcher; remediate/bail branches return 1 in Phase 13 (placeholder for Phase 14 handlers)"
  - "Marker line convention: [REUSE-NN] key=value... line via log_info (tee'd to /var/log/agentlinux-install.log); mirrors Phase 12's [DET-NN] format for grep-stable bats assertions + human-readable transcripts"
  - "REUSED_USER guard pattern: provisioner-level boolean wraps CREATE-path mutations in `if [[ \"${REUSED_USER:-false}\" != true ]]; then ... fi`; non-CREATE-path mutations (DOC-02 marker block) stay UNCONDITIONAL outside the guard"
  - "Source-once guard + log.sh dependency guard convention applied to reuse.sh + reuse/user.sh + reuse/nodejs.sh (mirrors detect.sh + per-component files)"

requirements-completed: [REUSE-01, REUSE-02]

# Metrics
duration: ~90min (split across 2 executor sessions due to mid-Task-3 usage-limit pause + this recovery-session continuation)
completed: 2026-05-16
---

# Phase 13 Plan 01: Reuse Decision Library + Provisioner Short-Circuits Summary

**Per-component reuse-decision library (plugin/lib/reuse.sh + reuse/user.sh + reuse/nodejs.sh) plus REUSE-01/REUSE-02 short-circuit wiring at the top of 10-agent-user.sh and 30-nodejs.sh — a brownfield host whose `agent` user already exists with `/bin/bash` + writable home + NOPASSWD-for-apt now reuses that user (skipping useradd + locale-gen) instead of clobbering, and a host whose Node 22 LTS is already installed with a writable global prefix skips both the NodeSource apt install and the per-user .npmrc bootstrap. DOC-02 CLAUDE.md anti-pattern guidance + 40-path-wiring PATH artefacts stay unconditional (additive against existing user content). The dispatch shape (case-branch enumerating all four tokens) is the binding Phase 13 → Phase 14 contract.**

## Performance

- **Duration:** ~90 min total across 2 executor sessions
- **Started:** 2026-05-16T11:54:02Z (first executor session)
- **Completed:** 2026-05-16T (this recovery session — continuation after mid-Task-3 usage-limit pause)
- **Tasks:** 3 / 3
- **Files modified:** 10 (3 new lib files + 1 new bats file + 3 modified provisioners + 1 modified detect file + 1 modified entrypoint + REQUIREMENTS.md)

## Accomplishments

- **REUSE decision library** — `plugin/lib/reuse.sh` orchestrator + `plugin/lib/reuse/{user,nodejs}.sh` per-component decision functions returning `{reuse, create, remediate, bail}` on stdout. Each function is testable in isolation by overriding DETECT_* exports; the provisioner-side `case "$(reuse::*_decision)" in` block is the dispatcher.
- **NEW detection reader: `detect::user_can_sudo_apt`** — the REUSE-01 NOPASSWD-for-apt sudo bar (CONTEXT.md Area 1 Q1 user amendment 2026-05-16). Probe in `detect::user_probe` uses absolute path `/usr/bin/apt-get` + raw `sudo -u <user> -n` (T-13-02 mitigation). DET-01 JSON gains `can_sudo_apt` field; text emits `[DET-01] user.can_sudo_apt=...` marker.
- **REUSE-01 short-circuit in `10-agent-user.sh`** — case-branch dispatching on `reuse::user_decision`. The `reuse)` arm logs `[REUSE-01]` marker via `reuse::log_user_reuse`, sets `REUSED_USER=true`, and skips Steps 1+2 (useradd + ensure_dir + locale-gen). Step 3 (DOC-02 CLAUDE.md `ensure_marker_block`) stays unconditional — additive against existing user content. The `remediate|bail` arms `log_warn + return 1` (placeholders for Phase 14 handlers that replace these arms WITHOUT changing the dispatch shape).
- **REUSE-02 short-circuit in `30-nodejs.sh`** — case-branch dispatching on `reuse::nodejs_decision`. The `reuse)` arm logs `[REUSE-02]` marker + defensive `detect::npm_prefix_writable_by_install_user` warn + `return 0`. The `create)` arm falls through to the v0.3.0 NodeSource path BYTE-IDENTICAL (greenfield invariant preserved).
- **40-path-wiring.sh** — 8-line documentation comment explaining unconditional execution under both REUSE and CREATE paths (PATH artefacts are additive via `ensure_marker_block` against `.bashrc`; the three installer-owned files — `profile.d`, `agentlinux.env`, `cron.d` — are root-owned and written-or-overwritten regardless).
- **21 bats @tests across the 3 tasks** in `tests/bats/13-reuse.bats`:
  - Task 1 (4 @tests): detect::user_can_sudo_apt happy/sad path, JSON field, DET-01 text marker.
  - Task 2 (10 @tests): all 5 reuse::user_decision predicate paths (reuse, create on absent, remediate on no-sudo, bail on shell/home/--user-mismatch), reuse::nodejs_decision matrix (reuse, create on no-write, create on count=0, create on Node 20), entrypoint sourcing order.
  - Task 3 (7 @tests): re-run [REUSE-01] marker present + zero real useradd, DOC-02 still ensured after REUSE branch, dispatch-shape check on both provisioners, no mode flags, greenfield @test count invariant.
- **REQUIREMENTS.md updated** — REUSE-01 + REUSE-02 checkbox bullets flipped `- [ ]` → `- [x]` (canonical "Complete" marker); traceability table rows REUSE-01 + REUSE-02 flipped `Pending` → `Complete`. REUSE-03 stays `Pending` (Plan 13-02 owns).
- **Docker matrix GREEN** on both Ubuntu 22.04 + 24.04 — **118/118** bats @tests (97 baseline + 21 new from this plan).
- **No regressions** to any pre-existing @test (greenfield invariant + Phase 12 read-only invariant + INST-02 idempotency invariant all preserved).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add detect::user_can_sudo_apt reader + extend detect::user_probe** — `ecb2018` (feat)
2. **Task 2: Create plugin/lib/reuse.sh orchestrator + reuse/{user,nodejs}.sh decision functions; wire entrypoint** — `b2c3c6d` (feat)
3. **Task 3: Wire REUSE-01/02 short-circuits into 10-agent-user.sh + 30-nodejs.sh + 40-path-wiring.sh doc comment + bats Task-3 @tests + REQUIREMENTS.md flips** — `69655fd` (feat)

**Plan metadata commit:** pending (this SUMMARY.md + STATE.md + ROADMAP.md final commit)

## Files Created/Modified

**Created:**
- `plugin/lib/reuse.sh` — Reuse-decision orchestrator (sources reuse/user.sh + reuse/nodejs.sh; Phase 13-02 will append reuse/agents.sh)
- `plugin/lib/reuse/user.sh` — REUSE-01 decision function with the 5 ordered predicates + reuse::log_user_reuse helper
- `plugin/lib/reuse/nodejs.sh` — REUSE-02 decision function + reuse::log_nodejs_reuse helper with defensive fallback marker
- `tests/bats/13-reuse.bats` — 21 @tests covering decoder, decision, dispatch-shape, marker presence, greenfield invariant

**Modified:**
- `plugin/lib/detect/user.sh` — extended detect::user_probe (can_sudo_apt probe + JSON field + DETECT_USER_CAN_SUDO_APT export) + new detect::user_can_sudo_apt reader function
- `plugin/lib/detect/render.sh` — added `__det_field DET-01 user.can_sudo_apt=$DETECT_USER_CAN_SUDO_APT` line alongside existing DET-01 user.* markers
- `plugin/bin/agentlinux-install` — sources `reuse.sh` AFTER `detect.sh` + AFTER `detect::run_once "$INSTALL_USER"`, BEFORE `run_provisioners`
- `plugin/provisioner/10-agent-user.sh` — REUSE-01 case-branch at top; REUSED_USER guard wraps Steps 1+2; Step 3 (DOC-02) stays unconditional
- `plugin/provisioner/30-nodejs.sh` — REUSE-02 case-branch at top; `reuse)` arm `return 0` with defensive warn; `create)` arm falls through to v0.3.0 byte-identical
- `plugin/provisioner/40-path-wiring.sh` — 8-line documentation comment on unconditional execution
- `.planning/REQUIREMENTS.md` — REUSE-01 + REUSE-02 checkbox bullets `[ ]`→`[x]`; traceability table rows `Pending`→`Complete`

## Decisions Made

See `key-decisions` frontmatter list. Highlights:

- **Dispatch contract IS the surface.** The Phase 13 → Phase 14 contract that the case branches enumerate `{reuse, create, remediate, bail}` (users) and `{reuse, create}` (nodejs) means Phase 14 extends remediate/bail branches in-place without changing the dispatch shape. This is binding (CONTEXT.md "Phase 13 → Phase 14 contract").
- **REUSE branch is non-mutating against the existing user.** Identity + locale + .npmrc + Node install are NOT touched; only DOC-02 CLAUDE.md marker block + PATH artefacts attach additively. This is the "we already have it, do nothing" semantics from PROJECT.md.
- **T-13-02 mitigation locked.** Absolute path `/usr/bin/apt-get` + raw `sudo -u <user> -n` (NOT `as_user` which adds `-H -E --`) — passwordless-sudo-failure must surface as exit 1, never hang on a password prompt.
- **No remediate branch on the Node-install layer.** REMEDIATE-01 (Phase 14) handles wrong-owner npm prefix at the npm-prefix layer instead (CONTEXT.md Area 1 Q2 lock).
- **No mode flags.** Per CONTEXT Q4 user-locked decision — no `--reuse-strict` / `--reuse-best-effort` / `--no-reuse`; per-component decisions only.

## Deviations from Plan

None — plan executed exactly as written. All three tasks landed at their specified injection points with the documented case-branch dispatch shape, REUSED_USER guard placement, and bats coverage scope. Pre-commit + Docker matrix GREEN on both Ubuntu versions with zero rule-1/2/3 auto-fix deviations triggered.

The plan itself was revised once during execution (commit `4929149` — fix(13): plan revision — address blockers B-1..B-3 + warnings W-1, W-2, W-5) BEFORE Task 1 started; the revision is part of the plan's authored state, not an in-execution deviation.

The recovery session (this one) inherited Tasks 1 + 2 from the previous executor (commits `ecb2018` + `b2c3c6d`) and finished Task 3 (commit `69655fd`) — verified all uncommitted work against acceptance criteria, ran pre-commit (PASS), ran the Docker matrix (118/118 PASS on both 22.04 + 24.04), applied the inline review-loop rubric (clean one iteration, zero actionable findings), and committed Task 3 as one coherent commit. No fix commits.

## Issues Encountered

**Mid-execution usage-limit pause:** The previous executor session hit a usage limit mid-Task-3 with Task-3 work staged uncommitted in the working tree. This recovery session inherited the staged state (3 modified provisioners + 1 modified bats file + 1 modified REQUIREMENTS.md) and finished the commit. No semantic re-work needed — the staged work was complete and correct per the plan's acceptance criteria; the only outstanding step was the commit-and-verify pass that this session performed.

## TDD Gate Compliance

This plan has `type: execute` (not `type: tdd`) at the plan level, but the individual tasks have `tdd="true"` — RED/GREEN compression was inlined (tests + impl in the same task commit). Per the plan's own dispatch-shape requirements, the gate sequence is verified through git log:

- `ecb2018` (Task 1 — feat) lands the `detect::user_can_sudo_apt` reader AND its 4 bats @tests in a single commit.
- `b2c3c6d` (Task 2 — feat) lands `reuse.sh` + `reuse/user.sh` + `reuse/nodejs.sh` AND 10 bats @tests in a single commit.
- `69655fd` (Task 3 — feat) lands the provisioner short-circuits + REQUIREMENTS.md flips AND 7 bats @tests in a single commit.

This compressed-TDD pattern matches Phase 5/5.1/12 precedent (e.g., 12-01 + 12-02 + 12-03 followed the same shape per their SUMMARY.md files). All Docker-matrix @tests GREEN at every commit boundary — no `not ok` lines at any point in the plan's execution history.

## User Setup Required

None — no external service configuration required. This is bash-side wiring + bats coverage; the Docker matrix exercises the full surface in CI without operator intervention.

## Next Phase Readiness

- **Plan 13-02 is ready to start** — Plan 13-02 owns REUSE-03 (catalog-agent reuse + sentinel integration + brownfield E2E smoke). The dispatch surface this plan landed (case-branches on `reuse::*_decision`) extends naturally to a `reuse::agents_decision` per-agent function landing in `plugin/lib/reuse/agents.sh`; the orchestrator in `plugin/lib/reuse.sh` has the trailing comment `# Plan 13-02 will append a . "$REUSE_LIB_DIR/agents.sh" line here...` already in place.
- **Phase 14 dispatch shape is locked** — Phase 14 (REMEDIATE-01..04) will replace the `remediate)` and `bail)` arms in `10-agent-user.sh` (and add a `remediate)` arm to the npm-prefix layer separately, NOT to 30-nodejs.sh) without changing the surrounding case structure. The contract is binding.
- **No blockers or concerns.** REUSE-01 + REUSE-02 are fully satisfied (REQUIREMENTS.md flipped; traceability table updated; bats coverage in place; Docker matrix GREEN on both supported Ubuntu versions).

## Self-Check: PASSED

Verified files exist:
- `plugin/lib/reuse.sh` — FOUND (committed in `b2c3c6d`)
- `plugin/lib/reuse/user.sh` — FOUND (committed in `b2c3c6d`)
- `plugin/lib/reuse/nodejs.sh` — FOUND (committed in `b2c3c6d`)
- `tests/bats/13-reuse.bats` — FOUND (Task 1 created in `ecb2018`; Tasks 2+3 appended in `b2c3c6d` + `69655fd`)

Verified commits in git log:
- `ecb2018` — FOUND (Task 1)
- `b2c3c6d` — FOUND (Task 2)
- `69655fd` — FOUND (Task 3)

Verified REQUIREMENTS.md flips:
- `- [x] **REUSE-01**` — FOUND
- `- [x] **REUSE-02**` — FOUND
- `| REUSE-01 | Phase 13 | Complete |` — FOUND
- `| REUSE-02 | Phase 13 | Complete |` — FOUND
- `- [ ] **REUSE-03**` — FOUND (Plan 13-02 owns)

Verified Docker matrix:
- `./tests/docker/run.sh ubuntu-22.04` — PASS (118/118)
- `./tests/docker/run.sh ubuntu-24.04` — PASS (118/118)

---
*Phase: 13-reuse-wiring*
*Completed: 2026-05-16*
