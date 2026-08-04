---
phase: 03-bootable-image-with-agent-user
plan: 01
subsystem: infra
tags: [packer, qemu, kvm, debian, cloud-init, one-context, qcow2]

# Dependency graph
requires: []
provides:
  - Packer HCL template for Debian 12 QCOW2 image build
  - Layered provisioning scripts (base, one-context, cleanup)
  - Build tooling installed on build machine (Packer 1.15.0, QEMU 9.1.0)
affects: [03-02, phase-4, phase-5]

# Tech tracking
tech-stack:
  added: [packer-1.15.0, qemu-9.1.0, packer-plugin-qemu-1.1.4]
  patterns: [packer-disk-image-from-cloud-qcow2, cd-content-cloud-init, layered-shell-provisioners]

key-files:
  created:
    - packer/agentlinux.pkr.hcl
    - packer/variables.pkr.hcl
    - packer/scripts/01-base.sh
    - packer/scripts/02-one-context.sh
    - packer/scripts/03-cleanup.sh
  modified: []

key-decisions:
  - "Symlinked /usr/libexec/qemu-kvm to /usr/local/bin/qemu-system-x86_64 for Packer QEMU plugin compatibility on AlmaLinux 9"
  - "Scripts use relative paths from packer/ directory -- packer validate/build must be run from packer/"

patterns-established:
  - "Packer template pattern: disk_image=true with Debian genericcloud QCOW2 base, cd_content for build-time cloud-init, shell provisioners for layered config"
  - "Provisioner script ordering: 01-base (system setup), 02-one-context (contextualization), 03-cleanup (minimize image)"

requirements-completed: [IMG-01, ONE-01]

# Metrics
duration: 3min
completed: 2026-03-16
---

# Phase 3 Plan 1: Packer Build Infrastructure Summary

**Packer HCL template with QEMU builder targeting Debian 12 genericcloud QCOW2, layered provisioners for base setup, one-context install, and image cleanup**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-16T05:20:02Z
- **Completed:** 2026-03-16T05:23:12Z
- **Tasks:** 2
- **Files created:** 5

## Accomplishments
- Installed Packer 1.15.0 and QEMU 9.1.0 on the AlmaLinux 9.7 build machine with KVM acceleration
- Created complete Packer HCL template using disk_image=true with Debian 12 genericcloud base and cd_content for cloud-init bootstrapping
- Created three layered provisioning scripts: base system config, one-context installation (with cloud-init purge), and cleanup/minimization
- packer validate passes successfully with QEMU plugin v1.1.4

## Task Commits

Each task was committed atomically:

1. **Task 1: Install Packer and QEMU on build machine** - (system packages only, no project files)
2. **Task 2: Create Packer template and provisioning scripts** - `5052aa9` (feat)

## Files Created/Modified
- `packer/agentlinux.pkr.hcl` - Main Packer template with QEMU source and build blocks
- `packer/variables.pkr.hcl` - Variable definitions for image URL, checksum, one-context version, output config
- `packer/scripts/01-base.sh` - Base system config: disk resize, locale, timezone, essential packages
- `packer/scripts/02-one-context.sh` - Purge cloud-init, install one-context 6.10.0-3 .deb
- `packer/scripts/03-cleanup.sh` - Remove packer user, clean apt, zero free space for compression

## Decisions Made
- Symlinked `/usr/libexec/qemu-kvm` to `/usr/local/bin/qemu-system-x86_64` because AlmaLinux 9 installs QEMU at a non-standard path that Packer's QEMU plugin cannot find by default
- Packer validate/build must be run from the `packer/` directory since script paths in the template are relative to the working directory

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created qemu-system-x86_64 symlink for QEMU binary path**
- **Found during:** Task 1 (Install Packer and QEMU)
- **Issue:** AlmaLinux 9 installs QEMU as `/usr/libexec/qemu-kvm`, not `qemu-system-x86_64` on PATH. Packer QEMU plugin expects `qemu-system-x86_64`.
- **Fix:** Created symlink: `/usr/local/bin/qemu-system-x86_64` -> `/usr/libexec/qemu-kvm`
- **Files modified:** System symlink only (no project files)
- **Verification:** `qemu-system-x86_64 --version` returns QEMU 9.1.0

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary for QEMU/Packer interoperability on AlmaLinux 9. No scope creep.

## Issues Encountered
None beyond the QEMU binary path issue documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Packer template and scripts validated and ready for `packer build`
- Plan 03-02 can proceed to build the actual QCOW2 image and verify it boots
- Build machine has all required tools: Packer 1.15.0, QEMU 9.1.0, /dev/kvm

## Self-Check: PASSED

All 5 created files verified present. Commit `5052aa9` verified in git log.

---
*Phase: 03-bootable-image-with-agent-user*
*Completed: 2026-03-16*
