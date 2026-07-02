---
phase: 20-behavior-test-green-on-almalinux-9
plan: 04
subsystem: testing
tags: [bats, almalinux, el9, distro-dispatch, nodesource, idempotency, reuse, family-token, par-01, el-08]

# Dependency graph
requires:
  - phase: 20-02
    provides: distro.bash family-dispatch verbs (distro_nodesource_repo_paths) + the post-Wave-2 EL9 residue inventory naming these two edits
  - phase: 20-01
    provides: EL9 substrate (diffutils for the INST-02 diff; exec-able /tmp)
  - phase: 18-distro-abstraction
    provides: shipped detect_distro (plugin/lib/distro_detect.sh) that exports AGENTLINUX_DISTRO_FAMILY; the family-aware detect::user_probe
provides:
  - "10-installer INST-02 idempotency snapshot enumerates the family-correct NodeSource repo path at BOTH find sites (pre + post) via distro_nodesource_repo_paths — green on EL9, byte-equivalent on Ubuntu"
  - "13-reuse REUSE-01 live probe seeds AGENTLINUX_DISTRO_FAMILY via the shipped detect_distro so the dnf arm is selected on EL9 — 13-reuse 32/32 on EL9"
affects: [20-05 full-suite-in-order EL9 green once the tty-driver timeout lands, 22-qemu-enforcing-selinux]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Container-side snapshot file-lists consume distro_nodesource_repo_paths (no product lib loaded) so find enumerates a present family-correct path; both pre/post blocks use the SAME verb call for a symmetric idempotency comparison"
    - "Test lib-chains that drive a live product probe seed the family token via the shipped detect_distro (never a hardcoded AGENTLINUX_DISTRO_FAMILY literal) so the probe reflects real EL9 capability"

key-files:
  created:
    - .planning/phases/20-behavior-test-green-on-almalinux-9/20-04-SUMMARY.md
  modified:
    - tests/bats/10-installer.bats
    - tests/bats/13-reuse.bats

key-decisions:
  - "10-installer uses the container-side distro_nodesource_repo_paths verb (no product lib loaded in this file); 13-reuse uses the shipped detect_distro (its lib-chain already sources distro_detect.sh) — each side draws from the family-correct single source of truth without re-hardcoding"
  - "detect_distro output redirected to /dev/null in __source_lib_chain so the [INFO] line does not pollute TAP; the override tests (DETECT_USER_CAN_SUDO_APT=...) are untouched because they force the probe result and need no seed"

requirements-completed: []  # EL-08 / PAR-01 are multi-wave phase requirements; this plan clears the INST-02 + REUSE-01 residue but the phase closes when Plan 20-05 (tty-driver timeout + DET-03) lands the full-suite-in-order EL9 green

# Metrics
duration: 20min
completed: 2026-06-28
---

# Phase 20 Plan 04: Wave 3 INST-02 Snapshot + REUSE-01 Family-Token Summary

**Two bounded EL-08/PAR-01 test edits clear the last of the Wave-2-named EL9 residue: the INST-02 idempotency snapshot now enumerates the family-correct NodeSource repo path (so `find` no longer exits 1 on the missing Debian path on EL9), and the 13-reuse REUSE-01 live probe seeds `AGENTLINUX_DISTRO_FAMILY` via the shipped `detect_distro` (so the probe selects the dnf arm on EL9 instead of defaulting to the missing `/usr/bin/apt-get`) — 10-installer 11/11 + 13-reuse 32/32 GREEN on almalinux-9, both byte-equivalent / unchanged on ubuntu-24.04.**

## Performance

- **Duration:** ~20 min (dominated by the two EL9 + Ubuntu targeted Docker boot+install+bats cycles)
- **Tasks:** 2
- **Files modified:** 2 (both test files; no product code)

## Accomplishments

- **Task 1 — INST-02 idempotency snapshot (10-installer.bats):** added `load 'helpers/distro'`; replaced the hardcoded `/etc/apt/sources.list.d/nodesource.sources` literal in BOTH INST-02 `find` snapshot blocks (pre-run and post-run) with `"$(distro_nodesource_repo_paths)"` so the snapshot enumerates the present family-correct path (EL9 → `/etc/yum.repos.d/nodesource-nodejs.repo`, Ubuntu → the same apt sources path). On EL9 the missing Debian path made `find` exit 1 and fail the snapshot; the verb yields a present path on both families. Both blocks call the SAME verb so the pre/post comparison stays symmetric (T-20-10). The explanatory comment that named the bare Debian literal was updated to reference the verb so no bare literal remains.
- **Task 2 — REUSE-01 family-token seed (13-reuse.bats):** in `__source_lib_chain`, after `source distro_detect.sh`, added a quiet `detect_distro >/dev/null 2>&1` call so the shipped detector exports `AGENTLINUX_DISTRO_FAMILY` (rhel on EL9, debian on Ubuntu) BEFORE the downstream `detect.sh` live probe runs. The REUSE-01 live-probe tests (`detect::user_can_sudo_apt` exit-0; `reuse::user_decision agent` == `reuse`) now select the EL9 `/usr/bin/dnf` arm and return `can_sudo` true at parity with Ubuntu — the residual `13-reuse 31/32` → `32/32`. No hardcoded family token (T-20-11); the family-agnostic override tests are untouched.

## Task Commits

1. **Task 1: INST-02 snapshot family-correct NodeSource repo path** — `40a3797` (test)
2. **Task 2: seed AGENTLINUX_DISTRO_FAMILY before the REUSE-01 live probe** — `0737812` (test)

**Plan metadata:** this commit (docs(20-04): complete Wave 3 INST-02 + REUSE-01 plan)

## Verification Evidence

Methodology: per the Wave-1/2/3 approach (full-suite-in-order EL9 is blocked by the `15-preflight-ux` `tty-driver.py` hang, owned by Plan 20-05), both files were verified via targeted-file runs in a freshly booted `--rm` container mirroring `tests/docker/run.sh`'s boot recipe (privileged + cgroupns + exec-able /tmp), installer run to exit 0, then `bats tests/bats/10-installer.bats tests/bats/13-reuse.bats`.

### almalinux-9 (EL9) — GREEN

- **43/43 ok, bats exit 0.** 10-installer **11/11** (INST-02 idempotency byte-stable, test 3, GREEN); 13-reuse **32/32**:
  - test 12 `detect::user_can_sudo_apt exits 0 on post-installer host` — ok
  - test 16 `reuse::user_decision returns 'reuse' on post-installer host (5 predicates pass)` — ok (was the residual RED: `remediate` via `can_sudo_apt=false`)
  - test 27 re-run `[REUSE-01]` marker — ok; tests 42-43 REUSE-03 brownfield E2E — ok.

### ubuntu-24.04 — NO REGRESSION

- **43/43 ok, bats exit 0.** The `distro_nodesource_repo_paths` verb yields the identical apt sources path on Ubuntu so the INST-02 snapshot is byte-equivalent; `detect_distro` exports `debian` so the live probe behavior is unchanged.

### Static acceptance

- `bats --count tests/bats/10-installer.bats` → 11; `bats --count tests/bats/13-reuse.bats` → 32 (both parse clean). NB: the plan's `bash -n <bats>` verify command is not applicable — `bash -n` errors on bats `@test "name" {` syntax identically at git HEAD (pre-existing), so `bats --count` is the correct parse gate.
- `grep "load 'helpers/distro'"` present in 10-installer; `distro_nodesource_repo_paths` at both find sites; **zero** `/etc/apt/sources.list.d/nodesource.sources` literals remain.
- `grep detect_distro` present in 13-reuse; **zero** `AGENTLINUX_DISTRO_FAMILY=rhel` hardcoded literal.

## Deviations from Plan

None — plan executed exactly as written. (The `bash -n` verify in the task `<automated>` block is replaced by `bats --count` because `bash -n` cannot parse bats `@test {` syntax — this is a verify-command substitution, not a behavior change; documented under Static acceptance above.)

## Threat Surface

No new shipped product surface — both edits are test-harness-only, confined to the ephemeral `--rm` read-only-bind-mounted test container. No `plugin/` code touched; no `skip` added; no `setenforce 0`.

- **T-20-10 (Tampering — wrong snapshot path masks a real idempotency mutation):** mitigated — both pre/post `find` blocks call the SAME `distro_nodesource_repo_paths` verb, the single source of truth, so the comparison stays symmetric.
- **T-20-11 (Elevation — probe mis-detecting sudo greenlights a false Reuse):** mitigated — the family token comes from the shipped `detect_distro` (the real detector), not a test literal, so the probe reflects genuine EL9 capability; the override tests stay explicit.

## Self-Check: PASSED

- `tests/bats/10-installer.bats` — FOUND (modified)
- `tests/bats/13-reuse.bats` — FOUND (modified)
- `.planning/phases/20-behavior-test-green-on-almalinux-9/20-04-SUMMARY.md` — FOUND
- commit `40a3797` (Task 1) — FOUND
- commit `0737812` (Task 2) — FOUND

---
*Phase: 20-behavior-test-green-on-almalinux-9*
*Completed: 2026-06-28*
