# Phase 23: codex — Summary

**Status:** ✅ COMPLETE (2026-06-29)
**Requirements:** AGT-07, ENABLE-05
**Verification:** Docker bats green (`tests/bats/53-catalog-npm-cluster.bats`,
Ubuntu 24.04) — AGT-07 + ENABLE-05 @tests pass.

## Delivered

- `plugin/catalog/agents/codex/install.sh` — npm install of
  `@openai/codex@0.142.3`, PATH-resolve check, `codex --version` pin-lock, and
  the ENABLE-05 `ensure_no_startup_update_check` helper (idempotent,
  TOML-safe, mode-preserving, atomic same-dir `mktemp`+`mv`).
- `plugin/catalog/agents/codex/uninstall.sh` — symmetric `npm uninstall -g`
  + `hash -r` + PATH truth-check; `~/.codex` left intact.
- `plugin/catalog/agents/codex/preserve_paths.json` — `~/.codex/` (CAT-04).
- `catalog.json` codex entry (source_kind npm, pin, post_install_verify, tags).
- `tests/bats/53-catalog-npm-cluster.bats` — AGT-07 lifecycle @test + a
  dedicated ENABLE-05 @test.

## ENABLE-05 — self-updater coexistence (how the pin stays authoritative)

1. Codex ships `codex update` (self-replace) + a startup update notifier.
2. The recipe sets `check_for_update_on_startup = false` in
   `~/.codex/config.toml` (a config key recognized by the pinned binary —
   verified against the native binary strings), disabling the in-app notifier.
3. The binary resolves under `/home/agent/.npm-global/bin` (npm-managed, no
   `/usr/local` shim); codex's own `update` detects `CODEX_MANAGED_PACKAGE_ROOT`
   and refuses to clobber a different npm target.
4. Updates flow through `agentlinux upgrade codex` (ADR-011 pin).

The ENABLE-05 @test asserts all three legs (knob=false, npm-managed path +
pinned version, `~/.codex` preserved across remove).

## Review

bash-engineer / security-engineer / catalog-auditor / ai-deslop /
qa-engineer / behavior-coverage-auditor — all run; findings triaged & fixed:
temp-file trap + mode preservation + atomic same-dir mktemp (codex helper),
dead env guard removed from uninstall, empty-pin/exit-zero/EACCES test guards.
TST-07 gate: GREEN.

## Notes

ENABLE-05 convention is reused by later self-updater tools (openclaw, Phase 47).
