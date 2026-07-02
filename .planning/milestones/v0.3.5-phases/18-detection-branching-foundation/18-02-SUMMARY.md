---
phase: 18-detection-branching-foundation
plan: 02
subsystem: infra
tags: [pkg-dispatch, almalinux, el9, bash, apt, dnf, nodesource, locale, verb-layer]

# Dependency graph
requires:
  - phase: 18-detection-branching-foundation
    plan: 01
    provides: distro_detect.sh exports AGENTLINUX_DISTRO_FAMILY ∈ {debian, rhel} — the single fork point pkg.sh branches on
  - phase: 17 (v0.3.4 baseline)
    provides: lib conventions (source-once guard, log.sh-first precondition) + idempotency.sh::write_file_atomic
provides:
  - "plugin/lib/pkg.sh — the single auditable apt↔dnf branch; every later v0.3.5 call site routes through one verb"
  - "verb set: pkg_install, pkg_is_installed, pkg_remove, pkg_autoremove, nodesource_prereqs, nodesource_setup, nodesource_repo_paths, nodesource_module_reset, locale_ensure"
  - "each verb is a two-arm case on AGENTLINUX_DISTRO_FAMILY; debian arm = current Ubuntu command byte-for-byte"
  - "nodesource_repo_paths — the single source of truth for the NodeSource repo-file path branch (3 lockstep sites in plans 03–05)"
  - "EL-02 bats dispatch fixtures via a PATH-stub harness (dev-host runnable, no root)"
affects: [30-nodejs.sh, 10-agent-user.sh, 20-sudoers.sh, bin/agentlinux-install, detect/nodejs.sh, phase-19-docker, phase-20-behavior-green]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Package-manager-neutral verb layer: the family fork lives once per verb in pkg.sh, never an inline if at a call site (Anti-Pattern 2)"
    - "debian arm of every verb lifted byte-for-byte from its present call site — Ubuntu behavior provably unchanged"
    - "PATH-stub bats harness: stub apt-get/dnf/rpm/dpkg-query/curl/locale to a capture file; assert dispatch by grepping the capture"
    - "nodesource_prereqs is a verb (not an inline pkg_install list) so an apt-only package name can never reach dnf"

key-files:
  created:
    - tests/bats/18-pkg-dispatch.bats
    - plugin/lib/pkg.sh
  modified: []

key-decisions:
  - "rhel nodesource_prereqs installs ONLY ca-certificates — never curl (curl-minimal conflict, Pitfall 6); gnupg/apt-transport-https do not exist on EL9"
  - "nodesource_module_reset DEFINED in pkg.sh as a rhel-only/no-op-on-debian verb so plan 03 never inlines an `if` at the AppStream-defuse call site (Pitfall 4)"
  - "locale_ensure rhel arm writes /etc/locale.conf via write_file_atomic (stdin body); both arms end with the same portable `locale -a … grep -Eiq '^c\\.utf-?8$'` gate"
  - "nodesource_repo_paths prints one path per line per family — single source of truth for the 3 lockstep repo-path sites (idempotency gate, detect gate, purge cleanup)"

patterns-established:
  - "Pattern: verb dispatch layer (18-RESEARCH.md Pattern 2) — pkg.sh is the only file that branches package-manager commands"

requirements-completed: [EL-02]

# Metrics
duration: ~6min
completed: 2026-06-28
---

# Phase 18 Plan 02: pkg.sh Verb Dispatch Layer Summary

**plugin/lib/pkg.sh is the single auditable apt↔dnf branch: nine package-manager-neutral verbs each fork exactly once on AGENTLINUX_DISTRO_FAMILY, with every debian arm lifted byte-for-byte from its current Ubuntu call site and the rhel arms covering dnf/rpm/locale.conf/NodeSource-on-EL9 — unit-proven by EL-02 PATH-stub dispatch fixtures on the dev host.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-06-28T06:56:34Z
- **Completed:** 2026-06-28T07:02:00Z (approx)
- **Tasks:** 2 (TDD RED→GREEN)
- **Files modified:** 2 (both created)

## Accomplishments
- Built `plugin/lib/pkg.sh` — the load-bearing new file the whole EL9 port routes through. Every one of the ~13 hardcoded apt-get/dpkg/locale-gen/NodeSource sites (converted in plans 03–05) now has exactly one verb to call.
- Defined the full verb set, each a two-arm `case "$AGENTLINUX_DISTRO_FAMILY"`: `pkg_install`, `pkg_is_installed`, `pkg_remove`, `pkg_autoremove`, `nodesource_prereqs`, `nodesource_setup`, `nodesource_repo_paths`, `nodesource_module_reset`, `locale_ensure`.
- Preserved Ubuntu behavior exactly: every debian arm is the current call-site command lifted verbatim (`apt-get update` + `apt-get install -y --no-install-recommends`, the `dpkg-query` presence idiom, `apt-get purge/autoremove`, `deb.nodesource.com/setup_22.x`, the whole `10-agent-user.sh` locale-gen block, the apt repo-file paths).
- Encoded the EL9 divergences as rhel arms: `dnf install --setopt=install_weak_deps=False`, `rpm -q`, `dnf remove/autoremove`, `rpm.nodesource.com/setup_22.x`, the `yum.repos.d` repo paths, and a `/etc/locale.conf` write via `write_file_atomic` (stdin body, never `cat>`/`tee`).
- Kept the NodeSource prereq divergence inside the verb: rhel installs **only** `ca-certificates` (never `curl` — curl-minimal conflict, Pitfall 6; no `gnupg`/`apt-transport-https` on EL9), so an apt-only package name can never reach `dnf`.
- Added `nodesource_module_reset` (rhel-only `dnf -y module reset nodejs || true`, no-op on debian) so plan 03 defuses the AppStream module without an inline `if` at the call site (Pitfall 4).
- Mirrored the lib conventions exactly: SPDX header, `AGENTLINUX_PKG_SH_SOURCED` source-once guard, `log.sh`-first precondition (`pkg.sh:` message prefix).
- Shipped 13 EL-02 bats fixtures driving each verb through a PATH-stub harness (stubbed apt-get/dnf/rpm/dpkg-query/curl/locale → capture file), green on the dev host; `shellcheck` clean at the repo's `--severity=warning`.

## Task Commits

Each task committed atomically (TDD RED→GREEN):

1. **Task 1: EL-02 pkg-dispatch bats fixtures (RED)** — `03d7763` (test)
2. **Task 2: plugin/lib/pkg.sh verb dispatch layer (GREEN)** — `a02da45` (feat)

## Files Created/Modified
- `tests/bats/18-pkg-dispatch.bats` (created) — 13 EL-02 dispatch fixtures. A PATH-stub `setup` writes executable stubs for apt-get/dnf/rpm/dpkg-query/curl/locale/locale-gen/update-locale that echo `<tool> <args>` to a capture file; each @test sources log.sh + idempotency.sh + pkg.sh in a fresh `bash -c`, sets `AGENTLINUX_DISTRO_FAMILY`, calls one verb, then greps the capture (or stdout for `nodesource_repo_paths`). `locale_ensure`'s rhel arm is exercised with an in-test `write_file_atomic` override that lands the body in a writable temp path, keeping the fixture root-free.
- `plugin/lib/pkg.sh` (created) — the package-manager-neutral verb dispatch layer; nine verbs, each branching once on `AGENTLINUX_DISTRO_FAMILY`, debian arms byte-identical to their current call sites and rhel arms covering EL9.

## Decisions Made
- **rhel `nodesource_prereqs` = ca-certificates only:** the EL9 NodeSource path needs no `curl` (Pitfall 6 curl-minimal conflict) and `gnupg`/`apt-transport-https` do not exist on EL9. Keeping this inside the verb means plan 03's prereq step calls `nodesource_prereqs` and an apt-only package name is structurally unable to reach `dnf`.
- **`nodesource_module_reset` lives in pkg.sh:** defined as a rhel-only verb (no-op on debian) rather than an inline `if` in 30-nodejs, so the AppStream-module defuse follows the same one-branch-per-verb discipline as everything else.
- **`nodesource_repo_paths` as single source of truth:** one verb prints the family's repo-file paths (one per line) so the three lockstep sites (idempotency gate, detect gate, purge cleanup) in plans 03–05 cannot drift.
- **`locale_ensure` shared correctness gate:** both arms end with the portable `locale -a 2>/dev/null | grep -Eiq '^c\.utf-?8$'` check (accepts `C.UTF-8` and the `C.utf8` form 24.04 reports), so the BHV-01 invariant holds identically on both families.

## Deviations from Plan
None — plan executed exactly as written (TDD RED→GREEN, both tasks committed atomically). Two implementation notes (not scope changes):
- The debian arm of `locale_ensure` was lifted verbatim from `10-agent-user.sh:76-94`, which hardcodes `C.UTF-8`; the `<locale>` parameter (`$1`) is consumed by the rhel arm only. The single live caller passes `C.UTF-8`, so behavior is identical and the "lift byte-for-byte" rule is honored.
- As in plan 18-01, plain `shellcheck` (default severity) emits one info-level `SC2317` on the shared `return 1 2>/dev/null || exit 1` precondition line — identical to the same line in `as_user.sh`/`distro_detect.sh`/`idempotency.sh` and suppressed at the repo's configured `--severity=warning`. The pre-commit `ShellCheck` hook passed on the GREEN commit. No per-file disable was added, to keep pkg.sh's precondition block byte-identical to its sibling libs.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- The verb layer is live and unit-verified. Plans 03–05 can now convert their call sites: `30-nodejs.sh` (prereqs → `nodesource_prereqs`, module defuse → `nodesource_module_reset`, repo gate → `nodesource_repo_paths` + `nodesource_setup`, install → `pkg_install nodejs`), `10-agent-user.sh` (locale block → `locale_ensure C.UTF-8`), `20-sudoers.sh` (`pkg_install sudo`), and `bin/agentlinux-install` (source pkg.sh after distro_detect.sh; `ensure_jq` → `pkg_install jq`; `run_purge` → `nodesource_repo_paths` iteration + `pkg_remove`/`pkg_autoremove`).
- **Carried (Phase 19):** the rhel arms are unit-proven on the Ubuntu dev host via PATH stubs only — real `dnf`/`rpm`/`/etc/locale.conf` behavior must be confirmed on the `almalinux:9` Docker substrate. In particular the NodeSource `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` `nodesource` substring (DET-02 classifier, also flagged in 18-01) is still unverified live.

## Self-Check: PASSED

- Files: `plugin/lib/pkg.sh`, `tests/bats/18-pkg-dispatch.bats`, `18-02-SUMMARY.md` — all present.
- Commits `03d7763`, `a02da45` — both in git history.
- `bats tests/bats/18-pkg-dispatch.bats` → 13/13 green; `shellcheck --severity=warning plugin/lib/pkg.sh` → exit 0.

---
*Phase: 18-detection-branching-foundation*
*Completed: 2026-06-28*
