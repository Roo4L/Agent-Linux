---
phase: 20-behavior-test-green-on-almalinux-9
plan: 01
subsystem: testing
tags: [docker, almalinux, el9, bats, tmpfs, dnf, openssh, diffutils, substrate]

# Dependency graph
requires:
  - phase: 19-almalinux-docker-row
    provides: tests/docker/Dockerfile.almalinux-9 + run.sh almalinux-9 row (systemd-in-Docker EL9 image)
  - phase: 18-distro-abstraction
    provides: family-aware plugin/ product code (pkg.sh, detect/*, distro_detect.sh) + the Phase-18 PATH-stub bats files
provides:
  - "EL9 test image ships diff (diffutils), the ssh client (openssh-clients), and ss (iproute)"
  - "Shared docker run mounts an exec-able /tmp (--tmpfs /tmp:exec) so PATH-stub harnesses can execve stubs under BATS_TEST_TMPDIR"
  - "18-pkg-dispatch (20/20) and 18-detect-el9 (7/7) green on EL9 with the bats stubs UNTOUCHED"
  - "Post-Wave-1 EL9 red/green inventory delineating the Wave-2/3 helper-generalization work-list"
affects: [20-02 brownfield helper generalization, 20-03 BHV-01/INST-02 assertion generalization, 20-04/05 restorecon+DET-03+TTY, 22-qemu-enforcing-selinux]

# Tech tracking
tech-stack:
  added: [diffutils, openssh-clients, iproute]
  patterns:
    - "Substrate-first sequencing: fix the test image + tmpfs default before editing any assertion — flips ~40 false-RED green with zero assertion edits"
    - "Shared/unconditional run.sh flags (one entrypoint for all four targets); exec-on-/tmp is the normal default outside Docker so Ubuntu rows execute identically"

key-files:
  created:
    - .planning/phases/20-behavior-test-green-on-almalinux-9/20-01-SUMMARY.md
  modified:
    - tests/docker/Dockerfile.almalinux-9
    - tests/docker/run.sh

key-decisions:
  - "Omitted the optional policycoreutils package — the Wave-3 restorecon call is guarded (command -v restorecon || true), so a no-op on Docker keeps the image minimal; Phase 22 QEMU exercises real restorecon under enforcing SELinux"
  - "Applied --tmpfs /tmp:exec unconditionally (not branched per-target) — the same noexec /tmp silently broke the Debian arm of the Phase-18 stub files too"

patterns-established:
  - "Substrate vs assertion triage: a stub test passing on the dev host but failing only inside Docker is a noexec/exec-mount difference, not a logic bug"

requirements-completed: []  # PAR-01/EL-06/EL-08 are multi-wave phase requirements; Wave 1 lands their substrate prerequisite only — not closed until Waves 2-3 land. Tracked, not marked complete.

# Metrics
duration: 38min
completed: 2026-06-28
---

# Phase 20 Plan 01: Wave 1 Substrate Summary

**EL9 test image gains `diff`/`ssh`/`ss` and the shared docker run mounts an exec-able `/tmp`, flipping the two Phase-18 PATH-stub files fully green (20/20, 7/7) on AlmaLinux 9 with the bats stubs untouched and zero Ubuntu regression.**

## Performance

- **Duration:** 38 min (dominated by Docker build + full-suite verification cycles)
- **Started:** 2026-06-28T18:24:50Z
- **Completed:** 2026-06-28T19:03:01Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `diffutils` (`diff`), `openssh-clients` (the `ssh` CLIENT — the image previously shipped only `openssh-server`), and `iproute` (`ss`) to the EL9 dnf set, inside the existing single `--setopt=install_weak_deps=False` invocation (no new RUN layer). `curl`/`coreutils` stay deliberately absent (minimal-vs-full file conflict).
- Flipped the shared `tests/docker/run.sh` tmpfs from the Docker-default `--tmpfs /tmp` (noexec) to `--tmpfs /tmp:exec`, unconditionally for all four targets.
- **Verified live in a booted `almalinux:9` container:** systemd reaches `running`; `/tmp` is no longer `noexec`; `diff`/`ssh`/`ss` all resolve; `agentlinux-install` runs to exit 0; `18-pkg-dispatch` reports **20/20** and `18-detect-el9` reports **7/7** with the stub harnesses unedited — confirming the noexec-/tmp + missing-package substrate root cause, not an assertion edit.
- Confirmed the substrate cascades cleared: BHV-02 SSH assertions now pass (20-agent-user's only residual RED is the BHV-01 `/etc/default/locale` path), `60-curl-installer` 4/4, `22-agent-sudo` 7/7.
- **Ubuntu no-regression CONFIRMED:** the full `tests/docker/run.sh ubuntu-24.04` row exited **0** — `== PASS: agentlinux-install + bats on ubuntu-24.04 ==`, **257/257 tests green, 0 failures** (Dockerfile.ubuntu-24.04 unchanged; only the shared run.sh flag moved). The Ubuntu suite sailed past test ~138 (the EL9 `15-preflight-ux` hang point) without hanging, proving the hang is EL9-fixture-specific and not introduced by the shared tmpfs change. systemd booted to running/degraded (the suite ran to completion).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add diffutils + openssh-clients + iproute to the EL9 dnf block** - `411e1c1` (feat)
2. **Task 2: Flip the shared run.sh tmpfs to /tmp:exec** - `f7574ca` (feat)

**Plan metadata:** this commit (docs(20-01): complete Wave 1 substrate plan)

## Files Created/Modified

- `tests/docker/Dockerfile.almalinux-9` - added `diffutils openssh-clients iproute` to the dnf set; extended both package-rationale comment blocks documenting why each is present (and why `curl`/`coreutils` remain absent).
- `tests/docker/run.sh` - `--tmpfs /tmp` → `--tmpfs /tmp:exec` on the single shared `docker run` invocation; added an explanatory comment (requirement #3) alongside the existing systemd-in-Docker recipe notes.

## Verification Evidence

### Headline substrate proof (booted `almalinux:9`, run.sh flags, stubs UNTOUCHED)

| File | Result | Was (research, noexec /tmp) |
|------|--------|------------------------------|
| `18-pkg-dispatch.bats` | **20/20 green** | 14 RED |
| `18-detect-el9.bats` | **7/7 green** | 3 RED |

`findmnt -no OPTIONS /tmp` → `rw,nosuid,nodev,relatime,inode64` (no `noexec`). `command -v diff/ssh/ss` → `/usr/bin/diff`, `/usr/bin/ssh`, `/usr/sbin/ss`. systemd `is-system-running` → `running`. installer → exit 0.

### Post-Wave-1 EL9 inventory (the Wave-2/3 work-list)

Captured via targeted in-container runs (exec-able `/tmp` = my fix is live). Per research §Methodology, per-file isolated counts can over-report RED from `--purge`/`userdel -r` teardown in earlier-sorted files; full-suite-in-order on EL9 is blocked by the known `15-preflight-ux` TTY hang (Plan 20-05 item, sorts *before* 18-*), so these are the authoritative targeted figures:

| File | EL9 result | Residual RED | Category → owner |
|------|-----------|--------------|------------------|
| `18-pkg-dispatch` | 20/20 ✅ | — | **[SUBSTRATE] resolved this plan** |
| `18-detect-el9` | 7/7 ✅ | — | **[SUBSTRATE] resolved this plan** |
| `22-agent-sudo` | 7/7 ✅ | — | positive anchor (family-agnostic) |
| `60-curl-installer` | 4/4 ✅ | — | positive anchor |
| `10-installer` | 10/11 | INST-02 idempotency | **[HELPER-GEN]** nodesource repo path in the `find` snapshot list → Wave 2 (`distro_nodesource_repo_paths`). `diff` substrate now present. |
| `15-detection` | 24/25 | DET-03 npm-prefix probe | **[INVESTIGATE/spike]** → Wave 2 (Plan 20-05 Task 1: assertion fix vs `as_user.sh` product escalation). DET-read-only now passes (`diff` present). |
| `20-agent-user` | 12/14 | BHV-01 `/etc/default/locale` ×2 | **[HELPER-GEN]** → Wave 2 (`distro_assert_locale` → `/etc/locale.conf`). BHV-02 SSH now **passes** (openssh-clients). |
| `30-runtime` | 3/5 observed (1 SSH test timed out standalone) | RT-02 cowsay; SSH-mode key-seeding | **[FIXTURE/HARNESS]** RT-02 cowsay is an npm fixture install (research-flagged non-substrate); the SSH-mode timeout reflects standalone key-seeding order — re-verify in full-suite order after Wave 2. |
| `13-reuse` / `14-remediate` / `15-preflight-ux` | not re-run (helper-gen + TTY hang) | per research | **[HELPER-GEN]** → Wave 2 (`brownfield.bash` generalization); `15-preflight-ux` TTY hang → Plan 20-05 tty-driver timeout. |
| `40-registry-cli` / `50-agents` / `51` / `52` | not re-run (SSH-heavy back half) | per research (A1) | **[SUBSTRATE-likely + restorecon]** → re-verify in full-suite order post-Wave-2; restorecon sites → Wave 3. `diff`/`ssh` substrate now present. |

**Read:** the substrate buckets (`diff`/`ssh`/`ss` + exec `/tmp`) are now fully cleared. Every residual RED above is genuine Wave-2 helper-generalization or Wave-3 restorecon — exactly the smaller, well-bounded set the research predicted. SSH-heavy back-half files (40/50/51/52) and the brownfield files (13/14/15) need full-suite-order re-verification once the Wave-2 helpers land.

## Decisions Made

- **Omitted optional `policycoreutils`.** The Wave-3 restorecon call is guarded (`command -v restorecon >/dev/null && … || true`), making it a deliberate no-op on the Docker row where enforcing SELinux is structurally unavailable (AppArmor host kernel). Adding the package would only exercise a binary against no policy; the real enforcing-SELinux proof is Phase 22 QEMU. Kept the image minimal. (Plan listed it as explicitly optional.)
- **`--tmpfs /tmp:exec` applied unconditionally**, not branched per-target. `run.sh` is the single entrypoint for all four rows; exec-on-/tmp is the normal default outside Docker, so Ubuntu rows execute identically — and the same noexec /tmp was silently breaking the Debian arm of the Phase-18 stub files (which were only ever validated by dev-host unit-sourcing).

## Deviations from Plan

None - plan executed exactly as written. (The `policycoreutils` package was explicitly optional in the plan; omitting it is a documented discretion decision, not a deviation.)

## Issues Encountered

- Standalone (non-full-suite) runs of the SSH-mode tests (`30-runtime`) can stall on SSH connection because key-seeding/sshd readiness is normally established by `20-agent-user`'s `setup()` in filename order. Resolved methodologically: seeded keys + started `sshd` before the targeted run, and flagged the SSH-mode/back-half files for full-suite-order re-verification in Wave 2. Not a substrate defect — `ssh` resolves and BHV-02 passes.
- The full-suite-in-order EL9 run is blocked by the research-documented `15-preflight-ux` TTY hang (~13 min, sorts before 18-*); inventory was therefore gathered via targeted clean-container runs, exactly as the research did. The hang is owned by Plan 20-05 (bounded pexpect timeout in `tty-driver.py`).

## Threat Surface

No new shipped surface. The exec-able `/tmp` and extra dnf packages are confined to the ephemeral (`--rm`), read-only-bind-mounted test container — accepted per the plan's threat register (T-20-01, T-20-02). T-20-03 (DoS via tmpfs change breaking systemd boot) is **mitigated**: systemd verified reaching `running` on EL9 and the Ubuntu row booted to running/degraded post-change.

## Next Phase Readiness

- **Wave 2 (helper generalization)** is unblocked and its surface is now precisely scoped by the inventory above: `tests/bats/helpers/distro.bash` (NEW) + `brownfield.bash` + the BHV-01 locale assertion + the INST-02 snapshot path + the REUSE-01 family token + the DET-03 spike.
- **Wave 3 (guarded restorecon)** at the two SSH-seeding sites (`20-agent-user.bats`, `50-agents.bats`).
- **Plan 20-05**: bounded pexpect timeout in `tty-driver.py` to convert the EL9 `15-preflight-ux` hang into a fast failure, enabling full-suite-in-order EL9 verification.
- No `plugin/` product code was touched; no bats assertions were edited — substrate only, as scoped.

## Self-Check: PASSED

- `tests/docker/Dockerfile.almalinux-9` — FOUND
- `tests/docker/run.sh` — FOUND
- `.planning/phases/20-behavior-test-green-on-almalinux-9/20-01-SUMMARY.md` — FOUND
- commit `411e1c1` (Task 1) — FOUND
- commit `f7574ca` (Task 2) — FOUND

---
*Phase: 20-behavior-test-green-on-almalinux-9*
*Completed: 2026-06-28*
