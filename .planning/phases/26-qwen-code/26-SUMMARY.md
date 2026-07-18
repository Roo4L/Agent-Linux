# Phase 26: qwen-code — Summary

**Status:** ✅ COMPLETE (2026-06-29)
**Requirements:** AGT-08
**Verification:** Docker bats green (`tests/bats/53-catalog-npm-cluster.bats` AGT-08).

## Delivered
- `plugin/catalog/agents/qwen-code/{install.sh,uninstall.sh,preserve_paths.json}`
  — npm `@qwen-code/qwen-code@0.19.2`, bin `qwen`, `--version` pin-lock,
  symmetric + idempotent remove, `~/.qwen/` preserved (CAT-04).
- `catalog.json` qwen-code entry.
- `tests/bats/53-catalog-npm-cluster.bats` AGT-08 lifecycle @test.

## OPS-01 operational smoke
`tests/bats/54-catalog-npm-smoke.bats` — **PASS** under AgentLinux: `qwen
--auth-type anthropic` answered a real prompt → "paris" via ANTHROPIC_API_KEY
(OpenAI-compatible + native DashScope also supported), as the agent user.

## Review
Cluster review loop — clean. TST-07: GREEN.
