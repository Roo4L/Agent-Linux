---
phase: 20-behavior-test-green-on-almalinux-9
plan: 06
subsystem: testing
tags: [bats, almalinux, el9, par-01, brownfield, distro-dispatch, ux-04, wrong-shell, tcsh, dpkg-query, pre-commit, ci-guard]

# Dependency graph
requires:
  - phase: 20-05
    provides: first complete in-order EL9 run (251/257) + deferred-items.md pinpointing the 6 residual reds (5 UX-04 + 1 BHV-52b)
  - phase: 20-02
    provides: distro.bash family-dispatch fork point (distro_family, distro_pkg_is_installed) + the original (manual, single-file) distro-leak grep guard
  - phase: 18-distro-abstraction
    provides: family-correct product code (reuse::user_decision readlink -f shell check, as_user_login login-shell semantics) — verified correct on EL9, not edited
provides:
  - "PAR-01 MET: bash tests/docker/run.sh almalinux-9 = 257/257 GREEN (exit 0), full bats contract in filename order, zero fail, no hang"
  - "UX-04 alt-user EL9 reds (137-141) closed via distro_wrong_shell: family-correct non-bash FUNCTIONAL login shell (/bin/sh dash on Debian, /usr/bin/tcsh on EL9) — fixture generalization, no plugin/ edit"
  - "BHV-52b EL9 red (253) closed: 52-agt02:122 bare dpkg-query routed through distro_pkg_is_installed"
  - "Enforced cross-suite distro-leak guard (scripts/check-distro-leak.sh + pre-commit hook): scans the WHOLE bats tree, not just brownfield.bash — prevents the inline-Debian-package-op class from regressing"
affects: [22-qemu-enforcing-selinux, v0.3.5 release-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Family-correct wrong-shell selection: the 'wrong shell' observable (reuse::user_decision bails wrong-shell) must hold on BOTH families, but the shell PATH differs — /bin/sh is dash (non-bash, functional) on Debian yet bash on RHEL. Dispatch on distro_family AND keep the shell FUNCTIONAL (tcsh, not nologin) so the as_user_login detection probes complete before the alt-user gate"
    - "Enforced (not manual) cross-suite guard: a regression class proven by a single sibling-file leak is closed by a pre-commit/CI script that scans the whole tree with a comment-strip + spec-file allowlist, not a one-off grep in a plan checklist"

key-files:
  created:
    - scripts/check-distro-leak.sh
    - .planning/phases/20-behavior-test-green-on-almalinux-9/20-06-SUMMARY.md
  modified:
    - tests/bats/52-agt02-brownfield-gate.bats
    - tests/bats/helpers/distro.bash
    - tests/bats/helpers/brownfield.bash
    - tests/bats/15-preflight-ux.bats
    - .pre-commit-config.yaml
    - .planning/phases/20-behavior-test-green-on-almalinux-9/deferred-items.md

key-decisions:
  - "UX-04 fix is Branch A (test/fixture), NOT a product defect: reuse::user_decision's readlink -f shell check is correct — /bin/sh genuinely IS bash on RHEL, so a /bin/sh agent really is bash-compatible there. The fixture's /bin/sh wrong-shell was a Debian assumption. No plugin/ edit"
  - "EL9 wrong shell = /usr/bin/tcsh, NOT /sbin/nologin. nologin is non-bash but is NOT a functional login shell: as_user_login (sudo -u agent -i) refuses to exec a nologin account, so the npm-prefix detection probe dies with exit 1 BEFORE the wrong-shell gate is reached (proven live: the nologin attempt produced exit 1 instead of the expected exit 65). tcsh (AppStream) is non-bash AND a real login shell — verified sudo -u agent -i -- echo returns 0 under tcsh"
  - "distro_wrong_shell provisions tcsh on EL9 idempotently (command -v tcsh guard) — the dnf install lives in the distro.bash dispatch layer, not hardcoded in the fixture; the debian arm is verbatim /bin/sh so Ubuntu rows are byte-identical"
  - "The distro-leak guard is scoped to EXECUTED Debian package ops (dpkg-query / deb.nodesource / apt-get <subcommand>) — the actual EL9-breaking class — with full-line comments stripped and the 18-* product-dispatch SPEC + distro.bash fork point allowlisted. Bare /usr/bin/apt-get sudoers-line literals (content-based drift fixtures) are out of scope: they never execute and pass on EL9"

requirements-completed: [PAR-01]

# Metrics
duration: 95min
completed: 2026-06-28
---

# Phase 20 Plan 06: EL9 Gap-Closure → 257/257 GREEN Summary

**The 6 residual EL9 reds from the Plan 20-05 authoritative run are closed: BHV-52b's inline `dpkg-query` now routes through `distro_pkg_is_installed`, and the 5 UX-04 alt-user reds are fixed by a new `distro_wrong_shell` verb that hands the wrong-shell fixture a family-correct, genuinely-non-bash but FUNCTIONAL login shell (`/bin/sh` dash on Debian, `/usr/bin/tcsh` on EL9 — `/sbin/nologin` was proven to break the `as_user_login` detection probes). `bash tests/docker/run.sh almalinux-9` is now 257/257 GREEN (exit 0); `ubuntu-24.04` stays 257/257 with zero regression. A pre-commit/CI guard (`scripts/check-distro-leak.sh`) now scans the whole bats tree so the inline-Debian-package-op class cannot regress.**

## Performance

- **Duration:** ~95 min (dominated by three full-suite Docker boot/install/bats cycles — one stale-version EL9 run that isolated the nologin failure, the definitive EL9 run, and the Ubuntu regression run; the EL9 tail is slow because 51/52-agt02 do live-CDN `claude update` + multiple npm global installs)
- **Tasks:** 3 (A: dpkg-query routing, B: UX-04 wrong-shell, C: enforced guard)
- **Files modified:** 6 (+1 created); NO product `plugin/` code

## Accomplishments

- **(A) BHV-52b green on EL9** — `tests/bats/52-agt02-brownfield-gate.bats:122` no longer inlines `dpkg-query`; routed through `distro_pkg_is_installed nodejs` (`rpm -q` on rhel). Test 253 GREEN.
- **(B) All 5 UX-04 alt-user reds green on EL9** — root-caused the npm-prefix-remediation diversion to a Debian-only `/bin/sh` fixture assumption and fixed it with a family-dispatched, functional wrong shell (tcsh on EL9). Tests 137–141 GREEN; no `plugin/` edit.
- **(C) Cross-suite distro-leak guard enforced** — `scripts/check-distro-leak.sh` + a local pre-commit hook scan the whole bats tree (the Plan 20-02 guard was a manual grep over `brownfield.bash` only, which is exactly why the 52-agt02 sibling-file leak survived).
- **PAR-01 closed** — EL9 full bats contract 257/257 GREEN, exit 0, no hang.

## Task Commits

1. **Task A + C: route 52-agt02 dpkg-query through distro.bash + enforce cross-suite leak guard** — `3f8f65c` (fix)
   _(A and C landed together: the first commit-A attempt left 52-agt02 staged, so the guard commit included it. Amended the message to describe both — a coherent unit: the leak plus the guard that catches its class.)_
2. **Task B: family-correct UX-04 wrong-shell fixture (tcsh on EL9)** — `68775e6` (fix)

**Plan metadata:** _(final docs commit — this SUMMARY + deferred-items.md closure)_

## Files Created/Modified

- `tests/bats/52-agt02-brownfield-gate.bats` — line 122 `dpkg-query` → `distro_pkg_is_installed nodejs`.
- `tests/bats/helpers/distro.bash` — new `distro_wrong_shell` verb (debian `/bin/sh`; rhel `/usr/bin/tcsh`, idempotent AppStream install).
- `tests/bats/helpers/brownfield.bash` — `setup_brownfield_host_user_wrong_shell` uses `distro_wrong_shell` for `useradd`/`usermod -s`.
- `tests/bats/15-preflight-ux.bats` — Test 13's `:/bin/sh$` assertion generalized through `distro_wrong_shell` (exact `cut -f7` match).
- `scripts/check-distro-leak.sh` — new enforced guard (whole bats tree; comment-strip; spec-file allowlist).
- `.pre-commit-config.yaml` — local `check-distro-leak` hook (`files: ^tests/bats/...`).
- `.planning/.../deferred-items.md` — both items repointed to CLOSED (Plan 20-06).

## THE AUTHORITATIVE RUNS

| Run | Command | Result |
|-----|---------|--------|
| EL9 (definitive) | `bash tests/docker/run.sh almalinux-9` | **257/257 PASS**, `== PASS ==`, exit 0, in filename order, no hang |
| Ubuntu (regression) | `bash tests/docker/run.sh ubuntu-24.04` | **257/257 PASS**, exit 0 — zero regression (debian arms byte-identical) |

EL9 evidence: tests 137–141 (UX-04) + 142 (greenfield invariant) all `ok`; tests 252–253 (BHV-52a/b) `ok`; 0 `not ok`. An earlier stale-version EL9 run (before the tcsh fix) confirmed (A) in isolation: 253 `ok` with only the 5 nologin-version UX-04 reds remaining (252/257), which isolated (B) to the wrong-shell fixture.

## Decisions Made

See `key-decisions` frontmatter. Headline: UX-04 is a **fixture** generalization (Branch A), the EL9 wrong shell must be **functional** (tcsh, not nologin — proven by the nologin exit-1-before-gate failure), and the guard is **enforced** (pre-commit/CI), not a manual checklist grep.

## Deviations from Plan

### Adaptations (documented, no user decision required)

**1. [Rule 1 — iterate on root cause] First EL9 wrong-shell choice (`/sbin/nologin`) was wrong; corrected to `/usr/bin/tcsh`.**
- **Found during:** Task B (definitive EL9 run staging — actually surfaced from the stale run's test 140).
- **Issue:** `/sbin/nologin` is non-bash (so the wrong-shell *bail* would fire) but is NOT a functional login shell — `as_user_login` (`sudo -u agent -i`) refuses to exec a nologin account, so the npm-prefix detection probe died with **exit 1 before** the alt-user gate (observed: test 140 got exit 1, expected 65).
- **Resolution:** the EL9 base image ships no non-bash *functional* shell, so `distro_wrong_shell`'s rhel arm provisions **tcsh** (AppStream) idempotently and returns `/usr/bin/tcsh`. Verified live that `sudo -u agent -i -- echo` returns 0 under a tcsh login shell, so detection completes and the wrong-shell gate fires. No weakening, no skip.

**2. [process] Tasks A and C share commit `3f8f65c`.**
- A pre-commit "configuration is unstaged" error on the first commit-A attempt left `52-agt02` staged; the subsequent guard commit (C) swept it in. The amended message describes both changes. Functionally correct and coherent (the leak + the guard for its class); no file lost (verified `git diff HEAD` clean for the file post-commit).

**Total deviations:** 2 (1 root-cause iteration, 1 commit-grouping). **Impact:** none on correctness — both tracked, no scope creep, no `plugin/` edit.

## Issues Encountered

- The EL9 suite tail (51/52-agt02) is genuinely slow (live-CDN `claude update` + npm global installs of claude-code/gsd/playwright), so each full EL9 cycle is ~15–20 min. Handled by patient polling, not by skipping the real runs.

## Known Stubs

None — no stubs introduced; both reds closed by real fixes, no `skip`, no placeholder.

## Next Phase Readiness

- **PAR-01 is met** (EL9 257/257). The full brownfield bats contract is family-green on AlmaLinux 9 and Ubuntu.
- Phase 22 (QEMU enforcing SELinux) inherits a fully-green Docker EL9 baseline; the `distro_restore_ssh_context` / `distro_ssh_unit` verbs from Wave 2 remain ready for the SSH-under-enforcement work.

---
*Phase: 20-behavior-test-green-on-almalinux-9*
*Completed: 2026-06-28*
