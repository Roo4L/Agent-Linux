---
phase: 18-detection-branching-foundation
plan: 01
subsystem: infra
tags: [distro-detection, almalinux, el9, bash, os-release, distro-family, curl-installer]

# Dependency graph
requires:
  - phase: 06-distribution-release-pipeline
    provides: curl-installer pre-gate (detect_ubuntu_version) + lockstep contract with distro_detect.sh
  - phase: 17 (v0.3.4 baseline)
    provides: Ubuntu-only distro_detect.sh gate + AGENTLINUX_DISTRO_VERSION export
provides:
  - "distro_detect.sh accepts AlmaLinux 9.x (FAMILY=rhel) alongside Ubuntu 22.04/24.04/26.04 (FAMILY=debian)"
  - "AGENTLINUX_DISTRO_FAMILY ∈ {debian, rhel} — the single fork point every later v0.3.5 layer reads"
  - "AGENTLINUX_OS_RELEASE_PATH test seam for unit-sourcing the gate off-target"
  - "escape hatch (AGENTLINUX_SKIP_DISTRO_CHECK=1) now seeds FAMILY instead of leaving it empty"
  - "curl-installer pre-gate (detect_supported_distro) accepts almalinux 9.x in lockstep"
  - "EL-01 bats unit fixtures (accept/reject/escape-hatch)"
affects: [pkg.sh, 30-nodejs.sh, 10-agent-user.sh, 20-sudoers.sh, detect/nodejs.sh, detect/user.sh, agentlinux-install, phase-19-docker, phase-20-behavior-green]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-arm case on os-release ID (ubuntu→debian, almalinux→rhel); ID-exact, never the looser similarity field"
    - "Family bucket export read by all downstream layers — never re-parse os-release at a call site"
    - "AGENTLINUX_OS_RELEASE_PATH env seam for testable os-release parsing"

key-files:
  created:
    - tests/bats/18-distro-detect.bats
  modified:
    - plugin/lib/distro_detect.sh
    - packaging/curl-installer/install.sh

key-decisions:
  - "AlmaLinux accepted at VERSION_ID 9|9.* ONLY — 8/10 explicitly rejected (v0.3.5 scope rule: Alma 9 only)"
  - "Match ID exactly, never the os-release similarity (ID_LIKE) field — Rocky/RHEL/CentOS/Fedora stay refused (T-18-01)"
  - "Escape hatch seeds FAMILY: explicit override wins, else os-release ID, else debian default — so a unit-sourced pkg.sh always has a valid dispatch arm"
  - "curl-installer function renamed detect_ubuntu_version → detect_supported_distro; name no longer claims Ubuntu-only"

patterns-established:
  - "Pattern 1: AGENTLINUX_DISTRO_FAMILY single fork point in distro_detect.sh (18-RESEARCH.md Pattern 1)"
  - "Pattern 2: two gates (lib + curl-installer) kept structurally identical (lockstep) so the 60-curl-installer fixture catches drift"

requirements-completed: [EL-01]

# Metrics
duration: 11min
completed: 2026-06-28
---

# Phase 18 Plan 01: Detection + Branching Foundation Summary

**distro_detect.sh now admits AlmaLinux 9.x with FAMILY=rhel and exports the single AGENTLINUX_DISTRO_FAMILY fork point (debian|rhel) that every later v0.3.5 layer branches on, with the curl-installer pre-gate in lockstep and Ubuntu behavior preserved.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-06-28T06:50:00Z
- **Completed:** 2026-06-28T06:53:39Z
- **Tasks:** 3
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- Added the `almalinux` arm to `detect_distro` (VERSION_ID `9|9.*` only) and the load-bearing `AGENTLINUX_DISTRO_FAMILY` export — the recognition layer the entire EL9 port hangs off.
- Preserved Ubuntu/debian-family behavior: the ubuntu arm still admits 22.04/24.04/26.04 and sets `AGENTLINUX_DISTRO_VERSION` exactly as before; `FAMILY=debian` is purely additive.
- Made the escape hatch (`AGENTLINUX_SKIP_DISTRO_CHECK=1`) seed `AGENTLINUX_DISTRO_FAMILY` (explicit override / os-release ID / debian default) so unit-sourced consumers never dispatch on an empty bucket.
- Added the `AGENTLINUX_OS_RELEASE_PATH` test seam so the gate is unit-testable off-target on the Ubuntu dev host.
- Brought the curl-installer pre-gate into lockstep: `detect_supported_distro` mirrors the two-arm case exactly (ubuntu 22.04/24.04/26.04, almalinux 9.x), rejecting the same unsupported set.
- Shipped 13 EL-01 bats fixtures (accept/reject/escape-hatch), green on the dev host.

## Task Commits

Each task was committed atomically (Tasks 1+2 follow the TDD RED→GREEN cycle):

1. **Task 1: EL-01 distro-detect bats fixtures (RED)** - `58d1210` (test)
2. **Task 2: distro_detect.sh almalinux arm + family export + escape-hatch seed + os-release seam (GREEN)** - `3fbb4f7` (feat)
3. **Task 3: curl-installer lockstep distro gate** - `9223178` (feat)

## Files Created/Modified
- `tests/bats/18-distro-detect.bats` - 13 EL-01 unit fixtures driving `detect_distro` via the `AGENTLINUX_OS_RELEASE_PATH` seam in a fresh subshell (ubuntu accept, almalinux 9/9.x accept, alma 8/10 + rocky/rhel/centos/fedora reject, escape-hatch FAMILY seed).
- `plugin/lib/distro_detect.sh` - Replaced the `ID != ubuntu` gate with a two-arm `case "$ID"` (ubuntu→debian, almalinux→rhel); added `AGENTLINUX_DISTRO_FAMILY` export, the os-release path seam, and FAMILY-seeding in the escape hatch; reworded the header to drop the "Ubuntu only" framing.
- `packaging/curl-installer/install.sh` - Renamed `detect_ubuntu_version` → `detect_supported_distro`, generalized to a `case "$id"` two-arm matching `distro_detect.sh`, updated the call site and the lockstep header comment.

## Decisions Made
- **AlmaLinux 9.x only** (`9|9.*`): 8/10 rejected — matches the v0.3.5 "Alma 9 only" scope rule, keeps the test matrix small.
- **ID-exact matching:** never the os-release similarity field, so EL-family siblings (Rocky/RHEL/CentOS/Fedora) are not silently admitted (threat T-18-01).
- **Escape-hatch FAMILY seed precedence:** explicit `AGENTLINUX_DISTRO_FAMILY` override > os-release `ID` > `debian` default.
- **Function rename in curl-installer** to `detect_supported_distro` so the name reflects the ubuntu|almalinux matrix; no stale references remain.

## Deviations from Plan

None - plan executed exactly as written. Three minor implementation notes (not scope changes):
- The plan's Task 2/3 acceptance criteria state `shellcheck … exits 0`. The repo runs shellcheck at `--severity=warning` (`.pre-commit-config.yaml`); a pre-existing info-level `SC2317` on the untouched `return 1 2>/dev/null || exit 1` precondition line is present in the original file and is suppressed at the repo's configured severity. Both files are clean at `--severity=warning` (the pre-commit `ShellCheck` hook passed on every commit).
- The plan's `grep -q 'ID_LIKE' … returns NOTHING` discipline check required removing the literal `ID_LIKE` token from explanatory comments — reworded to "the looser os-release similarity field". `grep -rn 'ID_LIKE' plugin/ packaging/` is now empty repo-wide.
- The Ubuntu-arm `log_info` line gained a `(family=debian)` suffix; no test or code depends on the prior exact string (verified via repo-wide grep).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `AGENTLINUX_DISTRO_FAMILY` fork point is live and unit-verified — the foundation Plan 18-02 (`lib/pkg.sh` verb dispatcher + the 13 call-site conversions) builds on.
- **Open verification (carried, Phase 19):** the EL9 NodeSource `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` substring (`nodesource`) is still unverified on a live `almalinux:9`; confirm on the Docker arm before locking the DET-02 classifier. Tracked in STATE.md Blockers.
- Real EL9 validation requires the Phase 19 `almalinux:9` Docker substrate; dev-host unit-sourcing only proves the abstraction surface.

## Self-Check: PASSED

- Files: `tests/bats/18-distro-detect.bats`, `plugin/lib/distro_detect.sh`, `packaging/curl-installer/install.sh`, `18-01-SUMMARY.md` — all present.
- Commits `58d1210`, `3fbb4f7`, `9223178` — all in git history.

---
*Phase: 18-detection-branching-foundation*
*Completed: 2026-06-28*
