---
phase: 28
slug: rtk
status: ready
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-30
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Extracted from `28-RESEARCH.md § Validation Architecture` (the research phase
> authored the validation map inline). `workflow.nyquist_validation: true`.

## Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core (behavior suite under `tests/bats/`) + node:test (CLI unit) |
| Config file | none — runner is `tests/docker/run.sh <image>` / `tests/qemu/boot.sh` |
| Quick run command | `./tests/docker/run.sh ubuntu-24.04` |
| Full suite command | `./tests/docker/run.sh ubuntu-24.04` (Docker matrix) + QEMU before release |
| CLI unit tests | `cd plugin/cli && pnpm test` (covers the `types.ts`/schema enum change) |

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Wave |
|--------|----------|-----------|-------------------|------|
| ENABLE-01 | install fetches pinned release, verifies checksum BEFORE extract, lands binary in `~/.local/bin`, no root, no `/usr/local` shim | integration (bats) | `./tests/docker/run.sh ubuntu-24.04` (new `57-catalog-binary.bats`) | 0 |
| ENABLE-01 | `remove` deletes binary + `~/.config/rtk` + `~/.local/share/rtk`; idempotent second remove | integration (bats) | same file | 0 |
| ENABLE-01 | tampered/mismatched checksum aborts BEFORE extract (negative test on a local tampered copy) | integration (bats) | same file | 0 |
| WORK-02 | `rtk --version` reports the pin `0.42.4` | integration (bats) | same file | 0 |
| WORK-02 | opt-in: install does NOT mutate `~/.claude`; after manual `rtk init -g` the hook exists; `remove` reverts it (no orphan hook) | integration (bats) | same file | 0 |
| ENABLE-01 (schema) | catalog validates with `source_kind: "binary"`; `types.ts` union compiles + round-trips | unit (node:test) | `cd plugin/cli && pnpm test` | extend |
| OPS-01 | real offline op (`rtk gain` / `rtk ls <tmpdir>`) runs as the agent user, sensible output | integration (bats) | same file | 0 |

## Sampling Rate

- **Per task commit:** `cd plugin/cli && pnpm test` (fast; schema/types) + `pre-commit run shellcheck/shfmt` on the recipes + helper.
- **Per wave merge:** `./tests/docker/run.sh ubuntu-24.04` running `57-catalog-binary.bats`.
- **Phase gate (TST-07 + OPS-01):** full Docker matrix green + the OPS-01 smoke run-and-passed at least once (no credential needed — recorded in SUMMARY). QEMU before any release.

## Wave 0 Gaps

- [ ] `tests/bats/57-catalog-binary.bats` — ENABLE-01 + WORK-02 + OPS-01 lifecycle; modelled on `tests/bats/53-catalog-npm-cluster.bats` (jq-derived pin from the provisioned catalog, six-invocation-mode PATH discipline, `__fail` four-line diagnostics, `assert_no_eacces`).
- [ ] Negative checksum test — install once (real network), then a recipe path pointing at a deliberately-wrong/corrupted LOCAL copy; assert non-zero exit + "verification failed" + binary NOT replaced. One real download only; tamper check stays offline → green in Docker.
- [ ] Extend `plugin/cli/test/` schema/loader unit test: `source_kind: "binary"` validates and a binary entry round-trips through `loadCatalog`.
- [ ] No framework install needed — bats + node:test already present.
