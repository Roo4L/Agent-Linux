---
phase: 03-bootable-image-with-agent-user
plan: 02
subsystem: infra
tags: [packer, qemu, kvm, debian, qcow2, one-context, opennebula, boot-verification]

# Dependency graph
requires:
  - phase: 03-01
    provides: Packer HCL template, provisioning scripts, build tooling
provides:
  - Bootable Debian 12 QCOW2 image at output/agentlinux-0.2.0-amd64.qcow2
  - Verified image boots on KVM/QEMU to login prompt
  - one-context installed and enabled for OpenNebula contextualization
affects: [phase-4, phase-5]

# Tech tracking
tech-stack:
  added: []
  patterns: [first-boot-cleanup-via-systemd-oneshot, shutdown-command-for-packer-user-cleanup]

key-files:
  created: []
  modified:
    - packer/agentlinux.pkr.hcl
    - packer/scripts/03-cleanup.sh
    - packer/variables.pkr.hcl
    - .gitignore

key-decisions:
  - "Packer user cleanup via first-boot systemd oneshot service (userdel fails during SSH session)"
  - "OpenNebula contextualization deferred to Phase 5 end-to-end validation"

patterns-established:
  - "First-boot cleanup pattern: systemd oneshot service runs before login, deletes build-time user, removes sudoers, self-removes"

requirements-completed: [IMG-02]

# Metrics
duration: 10min
completed: 2026-03-16
---

# Phase 3 Plan 2: Build and Verify QCOW2 Image Summary

**Debian 12 QCOW2 image built with Packer, verified booting on QEMU with one-context enabled and cloud-init purged, ready for OpenNebula deployment**

## Performance

- **Duration:** ~10 min (including Packer build and boot verification)
- **Started:** 2026-03-16T05:50:00Z
- **Completed:** 2026-03-16T11:27:19Z
- **Tasks:** 3 (2 auto + 1 checkpoint approved)
- **Files modified:** 4

## Accomplishments
- Built the AgentLinux QCOW2 image (298 MiB on disk, 10 GiB virtual) via `packer build` with exit code 0
- Verified image boots on KVM/QEMU to a login prompt within 60 seconds
- Confirmed one-context 6.10.0-3 installed and enabled, cloud-init purged, packer user removed after first boot
- Resolved packer user cleanup challenge with a first-boot systemd oneshot service pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Build the QCOW2 image with Packer** - `759c824` (feat)
2. **Task 2: Verify image boots and one-context is installed** - `b628c16` (fix)
3. **Task 3: Verify OpenNebula contextualization readiness** - checkpoint approved (no commit, human verification)

## Files Created/Modified
- `packer/agentlinux.pkr.hcl` - Updated shutdown_command and output_dir; refined provisioner ordering
- `packer/scripts/03-cleanup.sh` - Added first-boot systemd oneshot service for packer user cleanup
- `packer/variables.pkr.hcl` - Updated output_dir to ../output for project-root placement
- `.gitignore` - Added QCOW2 artifacts and Packer cache exclusions

## Decisions Made
- **Packer user cleanup via first-boot systemd oneshot:** `userdel` fails during the Packer build because the SSH session holds the user active. Moved cleanup to a systemd oneshot service that runs on first real boot, deletes the packer user, removes sudoers file, then self-removes the service.
- **OpenNebula contextualization deferred to Phase 5:** The image is verified locally (boots, one-context present). Full OpenNebula contextualization testing (user creation, SSH key injection, networking) will happen in Phase 5 end-to-end validation. Requirements ONE-02, USR-01, USR-02, USR-03 remain pending.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed packer user cleanup timing**
- **Found during:** Task 1 (Build the QCOW2 image with Packer)
- **Issue:** 03-cleanup.sh tried to delete the packer user during provisioning, but SSH was still connected as packer, causing userdel to fail
- **Fix:** Moved shutdown_command to handle cleanup; then when that also failed (same SSH session issue), created a first-boot systemd oneshot service pattern
- **Files modified:** packer/agentlinux.pkr.hcl, packer/scripts/03-cleanup.sh
- **Verification:** Image boots, packer user absent after first boot
- **Committed in:** `759c824` (initial fix), `b628c16` (final solution)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Fix was necessary for image correctness. Established a reusable first-boot cleanup pattern.

## Issues Encountered
- Packer user deletion timing required iterating through three approaches (in-provisioner, shutdown_command, first-boot service) before finding the correct solution. The SSH session holds the user active in all cases during the build.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- QCOW2 image artifact ready at output/agentlinux-0.2.0-amd64.qcow2
- Phase 4 can add agent tool packages to the image build pipeline
- Phase 5 will deploy to OpenNebula and verify full contextualization (ONE-02, USR-01, USR-02, USR-03)

## Self-Check: PASSED

All 4 modified files verified present. Commits `759c824` and `b628c16` verified in git log.

---
*Phase: 03-bootable-image-with-agent-user*
*Completed: 2026-03-16*
