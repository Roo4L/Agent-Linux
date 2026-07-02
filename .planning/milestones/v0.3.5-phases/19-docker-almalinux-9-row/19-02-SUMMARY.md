---
phase: 19-docker-almalinux-9-row
plan: 02
subsystem: ci
tags: [github-actions, ci-matrix, almalinux, el9, docker, fail-fast, harness]

# Dependency graph
requires:
  - phase: 19-docker-almalinux-9-row
    plan: 01
    provides: tests/docker/run.sh almalinux-9 target (build+boot+install exit 0 + invokable bats); Dockerfile.almalinux-9
provides:
  - .github/workflows/test.yml bats-docker matrix.target incl. almalinux-9 (PR-time Docker gate)
  - .github/workflows/release.yml gate-2-docker matrix.target incl. almalinux-9 (release Docker gate)
  - CI Docker matrix spans 3 Ubuntu rows + almalinux-9 with fail-fast:false isolating a (possibly Phase-20-red) Alma arm
affects: [20-behavior-test-green-almalinux-9, 22-qemu-release-gate, PAR-01, HARN-01]

# Tech tracking
tech-stack:
  added: []
  patterns: [CI matrix dimension rename in lockstep (matrix.ubuntu->matrix.target with run-step consumer in same edit), scoped gate edit (gate-2 only; gate-3-qemu/gate-4-pinned-combo untouched)]

key-files:
  created: []
  modified: [.github/workflows/test.yml, .github/workflows/release.yml]

key-decisions:
  - "Generalized the matrix dimension ubuntu->target (not a parallel almalinux dimension) so the four arms fan out from one neutral list and the run-step consumer is a single rename"
  - "Scoped the release.yml edit to gate-2-docker ONLY; gate-3-qemu (matrix.ubuntu) is Phase 22 and gate-4-pinned-combo (hardcoded ubuntu-24.04) is ADR-011 — both left byte-for-byte"

requirements-completed: [HARN-01]

# Metrics
duration: 2min
completed: 2026-06-28
---

# Phase 19 Plan 02: CI Docker Matrix AlmaLinux 9 Arm Summary

**Wires `almalinux-9` into the CI Docker matrix in both workflows that drive `tests/docker/run.sh` — `test.yml`'s `bats-docker` (PR gate) and `release.yml`'s `gate-2-docker` (release gate) — by generalizing each job's matrix dimension `ubuntu`→`target`, appending the Alma arm, and renaming the `${{ matrix.<name> }}` consumer in lockstep; `fail-fast: false` (already present) keeps the Ubuntu arms reporting if the Alma arm is red.**

## Performance

- **Duration:** ~2 min
- **Tasks:** 2
- **Files modified:** 2 (0 created, 2 modified)

## Accomplishments

- **`test.yml` `bats-docker`** — matrix dimension `ubuntu:` → `target:`, `almalinux-9` appended as a fourth list item after `ubuntu-26.04`; run-step consumer `bash tests/docker/run.sh ${{ matrix.ubuntu }}` → `${{ matrix.target }}` in the same edit. No `matrix.ubuntu` remains anywhere in test.yml. `fail-fast: false` retained; the `Skip if no bats suite yet` guard step untouched.
- **`release.yml` `gate-2-docker`** — inline flow-list `ubuntu: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04]` → `target: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9]`; run-step consumer renamed to `${{ matrix.target }}` (exactly one such Docker consumer). `fail-fast: false` retained.
- **gate-3-qemu and gate-4-pinned-combo left byte-for-byte unchanged** — the rename was scoped to gate-2 ONLY (see scope evidence below).

## Task Commits

1. **Task 1: test.yml bats-docker — matrix ubuntu→target + almalinux-9 arm** — `740715b` (ci)
2. **Task 2: release.yml gate-2-docker — matrix ubuntu→target + almalinux-9 (gate-3/4 untouched)** — `0fe9968` (ci)

## Files Modified

- `.github/workflows/test.yml` (modified) — `bats-docker` matrix.target incl. almalinux-9; run step consumes `matrix.target`.
- `.github/workflows/release.yml` (modified) — `gate-2-docker` matrix.target incl. almalinux-9; run step consumes `matrix.target`.

## Scope Evidence — gate-3 / gate-4 untouched (T-19-06 mitigation)

`git diff` for `release.yml` contains exactly two changed lines, both inside `gate-2-docker`:

```
-        ubuntu: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04]
+        target: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9]
-        run: bash tests/docker/run.sh ${{ matrix.ubuntu }}
+        run: bash tests/docker/run.sh ${{ matrix.target }}
```

Post-edit grep confirms the protected gate-3/gate-4 references survive:

- `gate-3-qemu` retains all four `matrix.ubuntu` references — cache key (line 204), restore-key (206), `bash tests/qemu/boot.sh ${{ matrix.ubuntu }}` (209), artifact name `qemu-artifacts-${{ matrix.ubuntu }}` (218).
- `gate-4-pinned-combo` retains its hardcoded `bash tests/docker/run.sh ubuntu-24.04` (line 238).

These surviving `matrix.ubuntu` references are the CORRECTNESS signal (RESEARCH Pitfall 3 / T-19-06), not leftovers — EL9 QEMU is Phase 22 and the pinned combo is ADR-011.

## Verification

- **test.yml:** YAML parses (`python3 yaml.safe_load`); `almalinux-9` present; `${{ matrix.target }}` present; zero `matrix.ubuntu` anywhere.
- **release.yml:** YAML parses; gate-2 `target: [ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9]` present; exactly one `tests/docker/run.sh ${{ matrix.target }}` Docker consumer; `boot.sh ${{ matrix.ubuntu }}` (gate-3) present; `tests/docker/run.sh ubuntu-24.04` (gate-4) present.
- **pre-commit `check yaml` hook** passed on both per-task commits.

## Deviations from Plan

None — plan executed exactly as written. (One verify command in Task 2 initially reported `VERIFY-FAIL`, traced to bash expanding the `${{ }}` token and BRE metacharacters inside a double-quoted compound `grep` argument; re-running each subcheck with `grep -F` fixed-string matching confirmed all four conditions pass. The workflow files were always correct — purely a shell-quoting artifact in the verification command, not a code issue.)

## Authentication Gates

None.

## Known Stubs

None — both workflow arms call the proven `tests/docker/run.sh almalinux-9` target shipped green in Plan 19-01.

## User Setup Required

None.

## Next Phase Readiness

- **HARN-01 (CI half) met:** the Alma arm now fans out on every PR (`bats-docker`) and every release tag (`gate-2-docker`), `fail-fast: false` isolating it.
- **Phase 20 (PAR-01) expectation:** the Alma CI arm may be legitimately red until PAR-01 drives the bats contract green on EL9; `fail-fast: false` keeps the three Ubuntu arms reporting in the meantime.
- **Phase 22:** gate-3-qemu (EL9 QEMU) and gate-4 pinned-combo deliberately untouched here.

## Self-Check: PASSED

- File verified present: `.github/workflows/test.yml`, `.github/workflows/release.yml`, `.planning/phases/19-docker-almalinux-9-row/19-02-SUMMARY.md`.
- Commits verified present: `740715b` (test.yml), `0fe9968` (release.yml).

---
*Phase: 19-docker-almalinux-9-row*
*Completed: 2026-06-28*
