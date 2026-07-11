---
phase: 03-bootable-image-with-agent-user
plan: 03
subsystem: infra
tags: [packer, qemu, opennebula, one-context, hcl]

# Dependency graph
requires:
  - phase: 03-bootable-image-with-agent-user (plan 01)
    provides: Packer template with shell provisioner and one-context install script
provides:
  - var.one_context_version wired into shell provisioner via environment_vars
  - Build-time control of one-context version via -var flag
affects: [03-bootable-image-with-agent-user, 05-end-to-end-validation]

# Tech tracking
tech-stack:
  added: []
  patterns: [packer-environment-vars-wiring]

key-files:
  created: []
  modified:
    - packer/agentlinux.pkr.hcl

key-decisions:
  - "No changes to 02-one-context.sh -- its fallback default is correct defensive coding"

patterns-established:
  - "Packer variable -> environment_vars -> shell script: use environment_vars in provisioner block to pass Packer variables as env vars to scripts via {{ .Vars }}"

requirements-completed: [ONE-01]

# Metrics
duration: 1min
completed: 2026-03-16
---

# Phase 03 Plan 03: Wire one_context_version Variable Summary

**Wired orphaned var.one_context_version into Packer shell provisioner via environment_vars so build-time version override actually reaches the install script**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-16T11:43:50Z
- **Completed:** 2026-03-16T11:45:01Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Closed the wiring gap where var.one_context_version was declared but never referenced in the build template
- Added environment_vars attribute to shell provisioner passing ONE_CONTEXT_VERSION=${var.one_context_version}
- Build with -var one_context_version=X.Y.Z now correctly controls which one-context version gets installed

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire var.one_context_version into shell provisioner via environment_vars** - `62e19c8` (fix)

## Files Created/Modified
- `packer/agentlinux.pkr.hcl` - Added environment_vars attribute to shell provisioner wiring var.one_context_version to ONE_CONTEXT_VERSION env var

## Decisions Made
- Kept 02-one-context.sh unchanged -- its `${ONE_CONTEXT_VERSION:-6.10.0-3}` fallback is correct defensive coding and should remain as a safety net

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- packer validate initially failed due to pre-existing output directory from prior build (not related to our change) -- validated with alternate output_dir override to confirm template correctness

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 03 fully complete (all 3 plans done)
- Packer template now has complete variable wiring for all configurable parameters
- Ready for Phase 04 (Agent Tool Packages) or Phase 05 (End-to-End Validation)

---
*Phase: 03-bootable-image-with-agent-user*
*Completed: 2026-03-16*
