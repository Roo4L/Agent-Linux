---
phase: 28-rtk
plan: 02
subsystem: infra
tags: [catalog, prebuilt-binary, sha256, curl, tar, arch-detect, supply-chain, bash]

# Dependency graph
requires:
  - phase: 28-01
    provides: "source_kind enum extended to [npm, script, binary] (schema.json + types.ts) — the catalog now validates a binary entry"
provides:
  - "plugin/catalog/lib/prebuilt-binary.sh — generic sourced helper for prebuilt-binary installs"
  - "al_pb_install <tool> <repo> <tag> <bin_path_in_archive> <bin_name> <dest_dir> public orchestrator"
  - "verify-before-extract security gate (gzip magic + sha256sum -c) reusable by phases 29-33"
affects: [28-03-rtk-recipe, 28-04-bats-lifecycle, 29-gh, 30-glab, 31-trivy, 32-gitleaks, 33-sentry-cli]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Verify-before-extract: stage to tmpdir, gzip magic (1f8b) + sha256sum -c, abort non-zero BEFORE tar"
    - "Sourced (non-+x) shell helper staged to /opt via existing cp -R catalog copy (no provisioner edit)"
    - "trap 'rm -rf $tmp' RETURN (not EXIT) for tmpdir cleanup in a sourced-into-recipe helper"
    - "Per-tool archive layout via a bin_path_in_archive parameter (flat rtk vs nested gh/bin/gh)"

key-files:
  created:
    - plugin/catalog/lib/prebuilt-binary.sh
  modified: []

key-decisions:
  - "No set -euo pipefail at file top — sourced into recipes that own their own shell options; each function returns non-zero instead"
  - "Version-lock pin sourced from AGENTLINUX_PINNED_VERSION, falling back to the tag with leading v stripped (${tag#v}) so the 6-arg al_pb_install signature stays generic"
  - "arm64 accepted as an alias for aarch64 in the arch case (defensive — uname -m is aarch64 on Linux but arm64 elsewhere)"

patterns-established:
  - "al_pb_* function namespace for the prebuilt-binary helper"
  - "Security gate functions return non-zero and never extract on any download/magic/checksum failure"

requirements-completed: [ENABLE-01]

# Metrics
duration: 3min
completed: 2026-06-30
---

# Phase 28 Plan 02: Shared prebuilt-binary helper Summary

**Generic sourced bash helper (`al_pb_install`) that maps `uname -m` → per-arch GitHub release asset, downloads asset + `checksums.txt`, enforces a gzip-magic + `sha256sum -c` gate BEFORE any `tar`, then installs a named binary 0755 into `~/.local/bin` and asserts the pinned `--version` — the ENABLE-01 keystone reused by phases 29-33.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-30T18:43:54Z
- **Completed:** 2026-06-30T18:46:22Z
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments
- Created `plugin/catalog/lib/prebuilt-binary.sh` (173 lines) — sourced, not executable, shellcheck + shfmt clean
- Verify-before-extract structurally enforced: the only `tar` call sits after the `sha256sum -c` gate (acceptance awk check passes); both the sha256-mismatch and non-gzip paths were functionally proven to reject and never extract
- Arch detection (`x86_64`→musl, `aarch64|arm64`→gnu, die on anything else), `~/.local/bin` install via `install -m 0755`, version-lock assert, and `trap '...' RETURN` self-cleaning tmpdir
- Generic over `<tool>/<repo>/<tag>/<bin_path_in_archive>/<bin_name>/<dest_dir>` so phase 29 (gh) onward is a catalog-entry + thin-recipe change with zero CLI source edits

## Task Commits

Each task was committed atomically (hooks ON — shellcheck `--severity=warning --shell=bash`, shfmt `-i 2 -ci -bn`):

1. **Task 1: Arch detection + download + verify-before-extract** — `cab3677` (feat)
2. **Task 2: Extract + install to ~/.local/bin + version-lock + public wrapper** — `35d35dc` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `plugin/catalog/lib/prebuilt-binary.sh` — ENABLE-01 shared helper. Functions: `al_pb_die`, `al_pb_detect_asset`, `al_pb_fetch_and_verify`, `al_pb_extract_install`, `al_pb_assert_version`, `al_pb_install` (public orchestrator).

## Decisions Made
- **No `set -euo pipefail` at file top** — the helper is sourced into recipes that own their own shell options; each function is individually robust and returns non-zero so the recipe aborts cleanly.
- **Version pin via `${AGENTLINUX_PINNED_VERSION:-${tag#v}}`** — keeps `al_pb_install`'s 6-argument signature generic while letting `al_pb_assert_version` check the bare version (tags are `v`-prefixed; the binary reports the bare `0.42.4`).
- **`arm64` accepted alongside `aarch64`** — defensive alias; both map to the gnu tarball (rtk publishes no aarch64-musl asset, RESEARCH Pitfall 3).

## Deviations from Plan

None - plan executed exactly as written. The plan's per-task acceptance criteria and the `awk` verify-before-extract structural check all pass; shfmt reflowed the inline `|| { ...; return 1; }` guards onto multiple lines (cosmetic, hook-mandated), no logic change.

## Issues Encountered
- Initial ad-hoc tamper smoke was self-defeating: `al_pb_fetch_and_verify` re-`curl`s `checksums.txt` from the source each call, overwriting a checksum file tampered only in the destination tmpdir. Re-ran the test with the bad checksum (and a non-gzip body) seeded at the **source** — both correctly rejected non-zero and left no extracted file. Functional confirmation only; not a code change.

## User Setup Required
None - no external service configuration required. (The helper performs a network fetch from the GitHub release CDN only when a recipe calls `al_pb_install` at install time.)

## Next Phase Readiness
- Plan 28-03 can now ship the rtk recipe pair: `install.sh` sources `${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh` and calls `al_pb_install rtk rtk-ai/rtk "v${AGENTLINUX_PINNED_VERSION}" rtk rtk "${AGENTLINUX_AGENT_HOME}/.local/bin"`, plus the opt-in `rtk init` post-install message and the symmetric uninstall.
- Phases 29-33 reuse the same helper unchanged; per-tool archive nesting is handled by the `bin_path_in_archive` argument.

---
*Phase: 28-rtk*
*Completed: 2026-06-30*

## Self-Check: PASSED

- plugin/catalog/lib/prebuilt-binary.sh: FOUND
- .planning/phases/28-rtk/28-02-SUMMARY.md: FOUND
- Commit cab3677: FOUND
- Commit 35d35dc: FOUND
