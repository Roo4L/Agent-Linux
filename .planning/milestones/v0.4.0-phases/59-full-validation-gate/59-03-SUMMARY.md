---
phase: 59-full-validation-gate
plan: 03
subsystem: validation-gate
tags: [gate-03, gate-04, gate-05, coverage-audit, agt-02, master-ready, milestone-close]

# Dependency graph
requires:
  - phase: 59-01
    provides: "red-free suite (13-reuse 32/32, harness 118/118) — the coverage audit + AGT-02 are only truthful on a green suite"
  - phase: 59-02
    provides: "QEMU gate re-wired at the Rust provision + identity guard; Docker gates confirmed Rust-by-default — the gate is correctly wired"
  - phase: 58
    provides: "run.sh default = Rust musl provision; AGENTLINUX_LEGACY_TS=1 rollback lever"
provides:
  - "59-COVERAGE.md — behavior-coverage-auditor report: zero Uncovered across v0.4.0 + legacy families on the Rust build; TST-07 gate GREEN (GATE-03)"
  - "AGT-02 keystone validated on the RUST chain via run.sh default (false-green trap avoided): claude update exit 0, zero EACCES (GATE-04 dev floor)"
  - "59-GATE-DECLARATION.md — Rust track declared master-ready; all 5 gates scored; AGENTLINUX_LEGACY_TS=1 rollback demonstrated; TS/Bash retained; no cutover deletion (GATE-05)"
affects: [full-validation-gate, milestone-close, post-milestone-cutover]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "coverage-audit-as-durable-artifact: the behavior-coverage-auditor report is captured verbatim to 59-COVERAGE.md so the zero-Uncovered evidence survives as a phase artifact"
    - "false-green-trap avoidance: AGT-02 validated via run.sh DEFAULT (pre-provisions with Rust, creating the symlink) so 51's setup_file skips the Bash-entrypoint fallback — the keystone runs on the Rust chain, provable by the run-Rust-provisioner banner"
    - "declare-not-delete: GATE-05 is a master-ready DECLARATION; the TS/Bash rollback substrate is retained (no cutover deletion this phase)"

key-files:
  created:
    - .planning/phases/59-full-validation-gate/59-COVERAGE.md
    - .planning/phases/59-full-validation-gate/59-GATE-DECLARATION.md
  modified: []

key-decisions:
  - "The plan's Task-2 no-EACCES verify token (`! grep -qiE 'EACCES|permission denied'`) is a naive check that false-positives on the AGT-02 PASS-line test NAME ('...zero EACCES/permission-denied lines'). Confirmed by exclusion grep that there is NO real permission-denied line; assert_no_eacces passed internally + the test is `ok 1`, exit 0. Treated the token failure as a documented false positive, not a gate failure."
  - "GATE-03: HRN/DOC/TST + Rust-unit families classified 'verified elsewhere' with durable paths (tests/harness/ 118/118, cargo test 338, schemars drift-check), NOT hand-waved — every non-bats family resolves to a named evidence path; ARCH-01/PERF-01 marked deferred (v2), not uncovered."
  - "GATE-05: DECLARE-not-delete — kept plugin/cli/, plugin/bin/agentlinux-install, and plugin/lib/reuse/agents.sh (+ iterators). Reconciled PROV-02's 'Phase-59 entrypoint cutover' phrasing against CONTEXT/ROADMAP in favor of the post-milestone cutover boundary."

requirements-completed: [GATE-03, GATE-04, GATE-05]

coverage:
  - id: T1
    description: "behavior-coverage-auditor rubric run over REQUIREMENTS.md (v0.4.0) + legacy bats @test families + HRN meta-suite on the Rust build; 59-COVERAGE.md emitted, zero Uncovered, TST-07 gate GREEN"
    requirement: "GATE-03"
    verification:
      - kind: automated
        ref: "grep 'TST-07 gate: GREEN' 59-COVERAGE.md && ! grep '| <ID> | Uncovered' + V040/legacy families present"
        status: pass
  - id: T2
    description: "AGT-02 (51-agt02-release-gate) validated on the Rust chain via run.sh default provisioning (Rust-provision banner fired; Bash-entrypoint fallback did NOT fire); claude update exit 0, zero EACCES; dev-host claude update smoke 2.1.195->2.1.220 no EACCES"
    requirement: "GATE-04"
    verification:
      - kind: automated
        ref: "./tests/docker/run.sh ubuntu-24.04 51-agt02-release-gate -> ok 1, == PASS ==, 'run Rust provisioner [default]' banner present; dev smoke exit 0 no EACCES"
        status: pass
      - kind: e2e
        ref: "release.yml gate-2 (Docker) + gate-3 (QEMU) live-CDN AGT-02 on the Rust path"
        status: unknown
    human_judgment: true
    rationale: "The enforcing live-CDN gate at full fidelity (Docker x4 + QEMU x4 against the live Anthropic CDN) is the CI pipeline gate — no KVM/full-suite in the dev VM. The dev floor (Docker per-file 51 on Rust + a real claude update smoke) is green here; the scaled live-CDN pass is proven in CI, documented not faked."
  - id: T3
    description: "59-GATE-DECLARATION.md declares the Rust track master-ready; all 5 gates scored; AGENTLINUX_LEGACY_TS=1 rollback lever demonstrated green (Bash+TS banner, 10-installer 11/11); TS/Bash substrate retained (no deletion); cutover boundary + dev-vs-CI split documented"
    requirement: "GATE-05"
    verification:
      - kind: automated
        ref: "grep master-ready + rollback-retained + all 5 gates + test -d plugin/cli + test -f agentlinux-install; AGENTLINUX_LEGACY_TS=1 run.sh 10-installer -> 11/11, exit 0"
        status: pass
    human_judgment: false

# Metrics
duration: 7min
completed: 2026-07-29
status: complete
---

# Phase 59 Plan 03: Wave 3 — Close the Gate (GATE-03/04/05) Summary

**The FINAL wave of the FINAL phase of the v0.4.0 Rust rewrite.** The
behavior-coverage-auditor reports zero Uncovered on the Rust build (TST-07 gate
GREEN); the canonical AGT-02 self-update acceptance test is green on the RUST
chain (`claude update` exit 0, zero EACCES, false-green trap avoided); and the
Rust track is declared master-ready with the TS/Bash rollback substrate retained.
The v0.4.0 milestone gate is met.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | behavior-coverage-auditor -> 59-COVERAGE.md (GATE-03) | b7f8d28 | 59-COVERAGE.md |
| 2 | AGT-02 keystone on the Rust chain (GATE-04) | a14b613 (findings folded into T3 artifact) | (test run + smoke; no source change) |
| 3 | 59-GATE-DECLARATION.md master-ready (GATE-05) | a14b613 | 59-GATE-DECLARATION.md |

(Task 2 modifies no tracked source/spec — its AGT-02 findings are recorded in the
single Task-3 declaration artifact, per the plan's single-authored-artifact rule.)

## Verification Results

### GATE-03 — coverage audit (Task 1)
- `59-COVERAGE.md` ends `TST-07 gate: GREEN`; zero Uncovered.
- v0.4.0 families (RUST/TEST/CORE/VERB/PROV/DIST/GATE) all Covered; legacy bats
  families (BHV/RT/AGT/CLI/CAT/INST/DET/REUSE/REMEDIATE/MCP/ENABLE/WIRE/OPS/EL/UX/
  DEVT/ASST/WORK/DOC/TST) all Covered on the Rust build; HRN verified-elsewhere
  (`tests/harness/` 118/118); ARCH-01/PERF-01 deferred (v2), not uncovered.
- `cargo test --workspace` = 338 passed (backs CORE/TEST/DIST golden evidence).

### GATE-04 — AGT-02 keystone on the Rust chain (Task 2)
- `./tests/docker/run.sh ubuntu-24.04 51-agt02-release-gate`:
  - `== run Rust provisioner (agentlinux provision) [default] ==` banner fired
    (run.sh:310) — the RUST chain, not the Bash entrypoint.
  - Rust provision ran 30-nodejs / 40-path-wiring / 50-registry-cli; the
    provision created the `~agent/.npm-global/bin/agentlinux` symlink, so 51's
    setup_file (51:37-39) took the symlink-PRESENT branch and the Bash-entrypoint
    fallback (51:38) did NOT fire — the isolated-invocation false-green trap is
    avoided.
  - Result: `ok 1 AGT-02 (release-gate): claude update exits 0 with zero EACCES/
    permission-denied lines` -> `== PASS ==`, exit 0.
- Dev-host `claude update` smoke (live CDN): 2.1.195 -> 2.1.220, exit 0, no EACCES
  — a real self-update, no sudo, npm-prefix under `$HOME`.
- The ENFORCING live-CDN gate is `release.yml` gate-2/gate-3 (CI) — documented,
  not faked.

### GATE-05 — master-ready declaration (Task 3)
- `59-GATE-DECLARATION.md` declares the Rust track master-ready; scores all 5
  gates (GATE-01..05) with evidence.
- `AGENTLINUX_LEGACY_TS=1 ./tests/docker/run.sh ubuntu-24.04 10-installer`: the
  `== run installer (Bash+TS rollback) [AGENTLINUX_LEGACY_TS] ==` banner fired
  (NOT the Rust default); 10-installer 11/11, exit 0 — the rollback works.
- Substrate retained (no deletion): `plugin/cli/`, `plugin/bin/agentlinux-install`,
  `plugin/lib/reuse/agents.sh` all PRESENT.
- Cutover boundary + honest dev-runnable-vs-CI split documented.

## Deviations from Plan

### Auto-fixed / documented

**1. [Rule 1 - naive-verify-token false positive] Task-2 no-EACCES grep matches the AGT-02 PASS-line test name**
- **Found during:** Task 2 verify.
- **Issue:** The plan's `! grep -qiE 'EACCES|permission denied' /tmp/agt02-run.log`
  token reports a match — but the ONLY matching line is the AGT-02 PASS line
  itself (`ok 1 ... zero EACCES/permission-denied lines`), i.e. the test NAME,
  not a real permission error.
- **Resolution:** verified by exclusion grep (`grep -v` the pass-line name) that
  there is NO real EACCES/permission-denied error in the transcript; the test's
  own `assert_no_eacces` passed and the test is `ok 1`, exit 0. Documented the
  false positive in the declaration; treated GATE-04 as GREEN (the substantive
  invariant — zero real EACCES — holds). No source changed (the AGT-02 bats file
  and run.sh were not touched).

No other deviations. No source, spec, or workflow was modified this wave — the
auditor ran read-only, AGT-02 + the rollback lever ran existing tests, and two
`.planning/` docs were written.

## Cutover Boundary (explicit)

Phase 59 DECLARES the Rust track master-ready. It performs NO deletion. The
master-merge + TS/Bash deletion (`plugin/cli/` + the Bash entrypoint + the Bash
reuse map/shim/iterators) is the POST-milestone cutover, taken once the maintainer
green-lights it. GATE-05 explicitly retains the rollback substrate.

## Dev-runnable vs CI/QEMU-gated (honest split)

- **Dev-runnable, proven this wave:** coverage audit (GATE-03); AGT-02 Docker
  per-file on the Rust chain + dev-host `claude update` smoke (GATE-04 floor);
  `AGENTLINUX_LEGACY_TS=1` rollback smoke (GATE-05).
- **CI/QEMU-gated, documented not faked:** the full Docker matrix (× 4 distros),
  the full QEMU matrix (× 4, needs KVM), and the scaled live-CDN AGT-02 gate —
  all on the RUST path after the Wave-2 boot.sh re-wire. The dev VM OOMs on the
  full Docker suite (~test 131) and has no KVM; no local full-matrix/QEMU pass is
  claimed.

## This is the FINAL wave

Phase 59 is the final phase of v0.4.0. On this green gate the milestone proceeds
to audit -> complete -> cleanup (the actual master-merge + TS/Bash cutover
deletion is the post-milestone step, out of scope here).

## Self-Check: PASSED

- `.planning/phases/59-full-validation-gate/59-COVERAGE.md` — FOUND (TST-07 GREEN)
- `.planning/phases/59-full-validation-gate/59-GATE-DECLARATION.md` — FOUND (master-ready, 5 gates)
- Commit b7f8d28 — FOUND
- Commit a14b613 — FOUND

---
*Phase: 59-full-validation-gate · Plan 03 · Completed: 2026-07-29*
