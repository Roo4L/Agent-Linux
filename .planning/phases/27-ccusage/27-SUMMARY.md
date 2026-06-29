# Phase 27: ccusage — Summary

**Status:** ✅ COMPLETE (2026-06-29)
**Requirements:** WORK-01
**Verification:** Docker bats green (`tests/bats/53-catalog-npm-cluster.bats` WORK-01).

## Delivered
- `plugin/catalog/agents/ccusage/{install.sh,uninstall.sh}` — npm
  `ccusage@20.0.14`, bin `ccusage`, `--version` pin-lock, symmetric +
  idempotent remove. Read-only cost reporter: no secret accepted, no
  `preserve_paths.json` (owns no per-user state — reads Claude Code's logs).
- `catalog.json` ccusage entry (first entry with no preserve_paths_file —
  exercises the runner's empty-AGENTLINUX_PRESERVE_PATHS path).
- `tests/bats/53-catalog-npm-cluster.bats` WORK-01 lifecycle @test.

## Review
Cluster review loop — clean. TST-07: GREEN.
