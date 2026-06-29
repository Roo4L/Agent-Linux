# Phase 25: opencode — Summary

**Status:** ✅ COMPLETE (2026-06-29)
**Requirements:** AGT-05
**Verification:** Docker bats green (`tests/bats/53-catalog-npm-cluster.bats` AGT-05).

## Delivered
- `plugin/catalog/agents/opencode/{install.sh,uninstall.sh,preserve_paths.json}`
  — npm `opencode-ai@1.17.11`, bin `opencode` (launcher execs platform-native
  optionalDependency; resolves + reports pin on linux-x64), symmetric +
  idempotent remove, `~/.config/opencode/` + `~/.local/share/opencode/`
  preserved (CAT-04).
- `catalog.json` opencode entry.
- `tests/bats/53-catalog-npm-cluster.bats` AGT-05 lifecycle @test.

## OPS-01 operational smoke
`tests/bats/54-catalog-npm-smoke.bats` — **PASS** under AgentLinux: `opencode
run -m anthropic/claude-haiku-4-5` answered a real prompt → "paris" via
ANTHROPIC_API_KEY, as the agent user.

## Review
Cluster review loop — clean. TST-07: GREEN.

## Note
v0.3.6 reassigns the AGT-05 id to opencode; the archived Phase 5 suite
(`tests/bats/50-agents.bats`) still cites AGT-05 for playwright-cli — a
milestone-numbering collision flagged at the cluster checkpoint for the
milestone audit (does not affect this phase's coverage).
