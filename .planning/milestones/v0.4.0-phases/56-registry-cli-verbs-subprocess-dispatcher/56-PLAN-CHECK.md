# Phase 56 — Plan Check (pre-execution, goal-backward)

**Checked:** 2026-07-28
**Plans:** 56-01 (Wave 0), 56-02 (Wave 1), 56-03 (Wave 2), 56-04 (Wave 3) — 4 plans / 14 tasks
**Gate type:** Revision Gate (bounded quality loop, max 3)

## VERDICT: GO-WITH-FIXES

The four plans are unusually strong: goal-backward coverage of VERB-01/02/03 +
GATE-01/05 is complete, the dispatcher (the #1 risk) is correctly front-loaded in
Wave 0 with all 6 `dispatcher-stream.test.ts` parity cases + the SIGKILL-escalation
case gated first, the acceptance-oracle staging trap is explicitly handled (Rust bin
staged AS the `agentlinux` command via a fail-loud symlink override, not the TS
bundle), the purity invariant is asserted every wave, and the 0→1→2→3 dependency
chain is sound with no same-wave file collision. All nine `agentlinux-core` pub fns
the plans consume were verified present. Two fixes are required before execution —
one is a hard BLOCKER that will produce a red CLI-01 across every invocation mode.

---

## BLOCKERS (must fix before execution)

**B1. [requirement_coverage / false-green] CLI-01 version mismatch — Rust crate `0.4.0` vs `package.json` `0.3.6`.**
- Plan: 56-01, Task 1.
- Evidence: `plugin/cli/package.json` version = `0.3.6`; `rust/crates/agentlinux/Cargo.toml` version = `0.4.0`. `tests/bats/40-registry-cli.bats` CLI-01 (`@test :97`) asserts `agentlinux --version` prints `$PKG_VERSION` (derived from `package.json`) across ALL invocation modes; CLI-05 (`:407`) re-asserts it.
- Problem: Plan 01 Task 1 directs the clap version to come from `CARGO_PKG_VERSION` and merely says "confirm the crate version matches" — it does NOT match. On the staged Rust build, `agentlinux --version` will print `0.4.0` and CLI-01/CLI-05 go RED. This is the exact false-green/parity trap the phase is meant to avoid, surfacing as a hard failure the executor cannot resolve without a decision.
- Fix: Decide and encode the version source of truth in Task 1 — either (a) the Rust bin must emit the `package.json` version (read it, or pin the crate `version` to `0.3.6` for the parity window), or (b) confirm CLI-01 tolerates the bumped version. Given `$PKG_VERSION` is derived live from `package.json`, option (a) pinning `agentlinux` crate to `0.3.6` (or a `version(...)` that reads package.json at build) is the parity-preserving choice. Add an explicit `cli_parse`/bats note asserting the printed version equals `$PKG_VERSION`.

## WARNINGS (should fix; execution can proceed)

**W1. [research_resolution] RESEARCH `## Open Questions` not marked RESOLVED.**
- RESEARCH.md:549 `## Open Questions` lacks the `(RESOLVED)` suffix; Q1/Q2/Q3 carry no inline `RESOLVED` marker, yet plans repeatedly cite them as "RESOLVED at plan time" (e.g. 56-01 Task 1 read_first). Dimension 11 flags this as a blocker-by-rule, but all three are in fact resolved IN the plans and I independently verified the load-bearing one:
  - Q1 (exact `--help`/usage bats assert): VERIFIED SAFE — the only `--help` greps in the CLI bats are `gsd-core --help` / `claude --help` (subprocess tools invoked by recipes), NOT `agentlinux --help` usage-body asserts. clap default help is fine.
  - Q2 (buffered npm 30s timeout): handled — 56-03 Task 1 requires the buffered path honor `Some(30_000)` and asserts it.
  - Q3 (`shouldReinstall` pure / `validateReusedBinary` I/O split): handled — 56-03 Task 3 ports `shouldReinstall` as a pure bin helper and keeps the statSync in the adapter.
- Fix: Mark the RESEARCH section `## Open Questions (RESOLVED)` with the three resolutions so the artifact is self-consistent and Dimension 11 passes cleanly. No execution impact.

**W2. [nyquist / metadata] VALIDATION.md front-matter `nyquist_compliant: false`, `wave_0_complete: false`.**
- These are correctly flipped to `true` by 56-04 Task 2 at closeout, so this is expected pre-execution state, not a gate miss. Sampling continuity holds: every one of the 14 tasks carries a single concrete automated `cargo test`/`bats` verify — there is no window of 3 consecutive tasks without an automated verify. Noting only so the executor knows the flip is a required Wave-3 deliverable.

---

## Dimension results

| Dimension | Result |
|-----------|--------|
| 1 Requirement coverage (VERB-01/02/03, GATE-01/05) | PASS — all 5 IDs in every plan's `requirements`; each maps to concrete tasks with real deliverables (not assert-only) |
| 2 Task completeness | PASS — 14/14 tasks have files+action+verify+acceptance+done |
| 3 Dependency correctness | PASS — 0→1→2→3 acyclic; `depends_on` refs all exist; wave = max(dep)+1 |
| 4 Key links planned | PASS — dispatcher↔RecipeEnv, cache↔pure gates, adapters↔verbs all wired in tasks, not just declared |
| 5 Scope sanity | PASS — 4 tasks/plan (borderline but each is a cohesive module); front-loaded risk isolates the hard part |
| 6 must_haves derivation | PASS — truths user-observable (byte-compatible stdout / exit codes), artifacts map to truths |
| 7 Context compliance | PASS — no locked decisions; deferred ideas (provisioner/musl/QEMU) correctly excluded and referenced as 57/58/59 |
| 7b Scope reduction | PASS — no v1/static/stub language reducing a requirement; "parallel-track" and "Phase-59-deferred gated set" are the CONTEXT-sanctioned boundary, not silent reduction |
| 7c Architectural tier | PASS — every capability placed per RESEARCH Responsibility Map; pure core stays free of process/fs/env (asserted by grep in 56-01/02/03/04) |
| 8 Nyquist | PASS — VALIDATION.md exists; every task has an `<automated>` verify; no watch-mode; no 3-task gap; timeout latencies bounded (~2min) |
| 9 Cross-plan data contracts | PASS — shared catalog/sentinel/cache adapters built once in Wave 1, reused by Wave 2 (no conflicting transforms) |
| 10 CLAUDE.md compliance | PASS — no `/usr/local/bin` shim; test-harness symlink override only; provisioner untouched; installer bash conventions cited |
| 11 Research resolution | WARN (W1) — section not formally marked RESOLVED, but all Qs resolved in-plan and independently verified |
| 12 Pattern compliance | N/A — no PATTERNS.md for this phase |
| Verify-format sanity | PASS — no `^`-anchored pkg-manager greps; no error-swallowing `2>/dev/null || echo` feeding comparisons; the one hard count (CLI-01 `$PKG_VERSION`) is the B1 issue |
| Numeric/factual authority | B1 — plan's "crate version matches package.json" claim contradicted by live measurement (0.4.0 vs 0.3.6) |

---

## Required fixes (bullet list)

- [ ] **B1 (blocker):** Reconcile the `agentlinux --version` source so it prints `$PKG_VERSION` (`package.json` = `0.3.6`), not `CARGO_PKG_VERSION` (`0.4.0`); add a parity assertion in 56-01 Task 1. Without this, CLI-01 + CLI-05 go red on the staged Rust build.
- [ ] **W1 (warning):** Mark RESEARCH.md `## Open Questions` as `(RESOLVED)` with the three resolutions (Q1 verified: no `agentlinux --help` body assert; Q2 buffered 30s timeout; Q3 shouldReinstall pure / statSync adapter).
- [ ] **W2 (note):** No action pre-execution — confirm 56-04 Task 2 flips `nyquist_compliant`/`wave_0_complete` to `true` at closeout (already planned).

**Recommendation:** Return to planner for B1 (single-task edit in 56-01) + W1 (RESEARCH annotation). After those, this plan set is GO — the architecture, sequencing, risk isolation, and false-green defenses are sound.
