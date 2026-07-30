---
phase: 59-full-validation-gate
plan: 02
subsystem: testing
tags: [qemu, ci, gate, musl, provisioner, boot.sh, gate-02]

# Dependency graph
requires:
  - phase: 59-01
    provides: "red-free bats suite (13-reuse 32/32, harness 118/118) — the QEMU/Docker matrix is only meaningful on a green suite"
  - phase: 58
    provides: "run.sh default = Rust musl provision; build-release.sh tarball payload places the musl bin at plugin/bin/agentlinux; AGENTLINUX_LEGACY_TS=1 rollback lever pattern"
provides:
  - "tests/qemu/boot.sh re-pointed at the Rust musl `provision` (default path) — the QEMU nightly/release gate now proves the RUST provisioner, not the Bash entrypoint"
  - "A static-musl provisioner-IDENTITY assertion in boot.sh that fails the run non-zero if the artifact is not the static musl bin — closes Risk #1 (false GATE-02 green on the Bash path)"
  - "AGENTLINUX_LEGACY_TS=1 rollback branch honored in boot.sh (GATE-05); Bash entrypoint retained"
  - "GATE-02 wiring status self-documented in boot.sh; Docker gates confirmed (not assumed) to run Rust by default with no workflow edit"
affects: [59-03, full-validation-gate, release-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Provisioner-identity guard: shebang reject + readelf(no PT_INTERP) → file('statically linked') → ldd('not a dynamic executable') fallback chain, fail-non-zero on any mismatch or when no tool is available"
    - "LEGACY_TS lever forwarded through the ssh hop as a POSITIONAL ARG (not SendEnv) — avoids touching the guest's AcceptEnv allowlist"

key-files:
  created: []
  modified:
    - tests/qemu/boot.sh

key-decisions:
  - "Invoke the provisioner via the explicit staged path `plugin/bin/agentlinux provision --user agent --yes` (cwd = extracted /opt/agentlinux-src) rather than a bare `agentlinux` on PATH — keeps the literal `agentlinux provision` greppable while matching run.sh's variable-path invocation"
  - "Forward AGENTLINUX_LEGACY_TS as a positional arg to the REMOTE_INSTALL heredoc instead of SendEnv, so no cloud-init AcceptEnv drop-in edit is needed (guest allowlists ANTHROPIC_API_KEY only) — keeps the edit inside boot.sh"
  - "Task 2 required no workflow edit: test.yml + release.yml + nightly-qemu.yml all call run.sh/boot.sh with no AGENTLINUX_LEGACY_TS override → Rust by default; confirmed by grep, not assumed"

patterns-established:
  - "Pattern: a CI gate that runs an artifact must mechanically PROVE the artifact's identity (static-musl vs Bash script) before running it, so a silent regression to the wrong artifact goes RED rather than false-green"

requirements-completed: [GATE-02]

coverage:
  - id: D1
    description: "tests/qemu/boot.sh runs the Rust musl `agentlinux provision --user agent --yes` by default (mirroring run.sh:337) — the QEMU gate proves the Rust provisioner"
    requirement: "GATE-02"
    verification:
      - kind: automated
        ref: "bash -n tests/qemu/boot.sh && grep 'agentlinux provision --user agent --yes' tests/qemu/boot.sh"
        status: pass
      - kind: e2e
        ref: "nightly-qemu.yml / release.yml gate-3 (bash tests/qemu/boot.sh <target>) — full in-guest QEMU run"
        status: unknown
    human_judgment: true
    rationale: "The full in-guest QEMU-on-Rust green is CI/QEMU-gated (no KVM in the dev VM); the static wiring + assertion + bash -n are verified locally, but the live QEMU boot must be confirmed on the pipeline before GATE-02 can be declared."
  - id: D2
    description: "Provisioner-IDENTITY assertion fails the run non-zero if plugin/bin/agentlinux is not the static musl bin (shebang reject + readelf/file/ldd guard) — no false GATE-02 green on the Bash path (Risk #1)"
    requirement: "GATE-02"
    verification:
      - kind: automated
        ref: "grep -E 'readelf|not a dynamic executable|statically linked' tests/qemu/boot.sh (guard present, exits 1 on mismatch); assertion logic reviewed"
        status: pass
    human_judgment: false
  - id: D3
    description: "AGENTLINUX_LEGACY_TS=1 rollback branch honored in boot.sh (execs retained Bash entrypoint); plugin/bin/agentlinux-install retained (GATE-05)"
    requirement: "GATE-02"
    verification:
      - kind: automated
        ref: "grep 'AGENTLINUX_LEGACY_TS' tests/qemu/boot.sh && test -f plugin/bin/agentlinux-install"
        status: pass
    human_judgment: false
  - id: D4
    description: "Docker gates (test.yml bats-docker, release.yml gate-2/gate-4) confirmed to run Rust by default with no LEGACY override; GATE-02 wiring status documented in boot.sh"
    requirement: "GATE-02"
    verification:
      - kind: automated
        ref: "grep run.sh/boot.sh in workflows + ! grep AGENTLINUX_LEGACY_TS + grep 'GATE-02 wiring status' tests/qemu/boot.sh"
        status: pass
    human_judgment: false

# Metrics
duration: 12min
completed: 2026-07-29
status: complete
---

# Phase 59 Plan 02: Wire the QEMU gate to the Rust build Summary

**tests/qemu/boot.sh re-pointed from the Bash entrypoint to the static-musl `agentlinux provision`, with a fail-non-zero provisioner-identity guard that closes the #1 risk — a false GATE-02 green on the Bash path.**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-07-29
- **Tasks:** 2
- **Files modified:** 1 (tests/qemu/boot.sh)

## Accomplishments
- Swapped boot.sh's in-guest install invocation (`bash plugin/bin/agentlinux-install`, formerly :531) for the staged musl bin `plugin/bin/agentlinux provision --user agent --yes` (default path), mirroring the Docker default at run.sh:337. The QEMU nightly/release gate now proves the RUST provisioner.
- Added a provisioner-IDENTITY assertion with teeth: a `#!`-shebang reject, then a `readelf -l` (no PT_INTERP) check with `file` ('statically linked') and `ldd` ('not a dynamic executable') fallbacks, and a hard `exit 1` when no tool is available. A Bash-script or dynamically-linked `agentlinux` makes the gate go RED — no false GATE-02 green on the Bash path (Risk #1 closed).
- Honored the `AGENTLINUX_LEGACY_TS=1` rollback branch (GATE-05), forwarding it through the ssh hop as a positional arg so no guest AcceptEnv change is needed; it execs the RETAINED Bash entrypoint. `plugin/bin/agentlinux-install` stays in the tree.
- Confirmed (by grep, not assumption) that the Docker gates (test.yml bats-docker, release.yml gate-2/gate-4) and the QEMU gates (nightly-qemu.yml, release.yml gate-3) call run.sh/boot.sh with NO `AGENTLINUX_LEGACY_TS` override → Rust by default. No workflow edit needed. Documented the wiring status as a comment block in boot.sh.

## Task Commits

1. **Task 1 + Task 2: re-point boot.sh + identity guard + LEGACY_TS branch + wiring-status doc** - `46b41c7` (test)

Both tasks landed in one atomic commit because Task 2's only deliverable is a documentation comment block in the same file/region Task 1 rewired (no separate artifact) — the workflow confirmation is a read-only assertion, not a code change.

## Files Created/Modified
- `tests/qemu/boot.sh` - Install-invocation region (§11) rewired to the Rust musl `provision` with a static-musl provisioner-identity guard, the AGENTLINUX_LEGACY_TS=1 Bash rollback branch, and a GATE-02 wiring-status comment block. REMOTE_BATS heredoc (§12) and the rest of boot.sh unchanged.

## Decisions Made
- **Explicit staged-path invocation:** invoke `plugin/bin/agentlinux provision --user agent --yes` (cwd = /opt/agentlinux-src in-guest) rather than a bare `agentlinux` on PATH. This keeps the literal `agentlinux provision` greppable (satisfying the verify token) while matching run.sh:337's variable-path style. The guard already `chmod +x`'d the same file.
- **Positional-arg LEGACY_TS forwarding:** the guest's sshd AcceptEnv allowlists only `ANTHROPIC_API_KEY`, so forwarding the lever via SendEnv would require editing cloud-init user-data (out of scope). Passing it as `$2` into the REMOTE_INSTALL heredoc keeps the edit entirely inside boot.sh — the plan explicitly permits this when the ssh-hop forwarding is awkward, and here it achieves full lever parity anyway.
- **No workflow edit:** Task 2's confirmation proved the research's "no Docker/QEMU wiring gap" claim — every gate job calls run.sh/boot.sh with no override, so the only GATE-02 code change is the boot.sh swap.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Verify token `agentlinux provision` vs variable invocation**
- **Found during:** Task 1 (running the verify grep)
- **Issue:** The first draft invoked `"$BIN" provision --user agent --yes` (BIN=plugin/bin/agentlinux), which is functionally correct and mirrors run.sh's variable-path style, but the plan's verify greps for the literal token `agentlinux provision --user agent --yes`, which `"$BIN"` does not contain.
- **Fix:** Changed the invocation line to the explicit `plugin/bin/agentlinux provision --user agent --yes` (same file, same cwd), so the literal intent is greppable while the `$BIN` variable still drives the identity guard.
- **Files modified:** tests/qemu/boot.sh
- **Verification:** `grep -q 'agentlinux provision --user agent --yes'` now passes; `bash -n` clean; `cargo test --workspace` green (338 passed).
- **Committed in:** 46b41c7 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — verify-token alignment)
**Impact on plan:** Cosmetic invocation-form change to satisfy the greppable-intent contract; behavior identical. No scope creep.

## Issues Encountered
None beyond the deviation above.

## Locally-verified vs CI/QEMU-gated

**Verified locally (dev VM, no KVM):**
- `bash -n tests/qemu/boot.sh` parses clean.
- `grep` confirms the default path runs `agentlinux provision --user agent --yes` (not the Bash entrypoint).
- The provisioner-identity guard is present (shebang reject + readelf/file/ldd chain) and reviewed to exit 1 on a Bash-script or dynamically-linked `agentlinux`, or when no probe tool exists — it has teeth.
- `AGENTLINUX_LEGACY_TS` branch present; `plugin/bin/agentlinux-install` retained.
- Workflows confirmed to call run.sh/boot.sh with no LEGACY override (Rust default); GATE-02 wiring-status comment present.
- `git diff` touches ONLY tests/qemu/boot.sh (no deletions); no workflow YAML edited.
- `cargo test --workspace` green (338 passed) — Rust unaffected (this wave touches shell/CI only).

**CI/QEMU-gated (NOT run locally, NOT faked):**
- The full in-guest QEMU-on-Rust boot + bats suite (nightly-qemu.yml / release.yml gate-3) — requires KVM, absent in the dev VM. The wiring + identity guard are the deliverable; the live green is proven on the pipeline.
- The full Docker matrix (test.yml bats-docker, release.yml gate-2/gate-4) across 22.04/24.04/26.04/almalinux-9.
- The live-CDN AGT-02 QEMU gate.

## Next Phase Readiness
- GATE-02's one real code change (the QEMU wiring gap) is closed; the QEMU gate now runs + proves the Rust provisioner.
- Wave 3 (59-03) can proceed: coverage audit + AGT-02 validation on the Rust chain + master-ready declaration.
- No blockers introduced. TS (plugin/cli/) and the Bash entrypoint remain retained (GATE-05).

## Self-Check: PASSED
- FOUND: .planning/phases/59-full-validation-gate/59-02-SUMMARY.md
- FOUND: commit 46b41c7 (touches tests/qemu/boot.sh)

---
*Phase: 59-full-validation-gate*
*Completed: 2026-07-29*
