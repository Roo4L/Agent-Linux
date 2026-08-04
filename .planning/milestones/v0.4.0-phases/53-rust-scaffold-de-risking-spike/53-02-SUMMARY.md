---
phase: 53-rust-scaffold-de-risking-spike
plan: 02
subsystem: rust-provisioner
tags: [rust, provisioner, bats, ci, reuse, metrics, musl, gate-01]
requires:
  - rust-workspace
  - agentlinux-core-crate
  - agentlinux-bin
provides:
  - reuse-decision-port
  - agents-sh-rust-shim
  - rust-ci-job
  - phase-53-metrics
  - bulk-port-verdict
affects:
  - rust/crates/agentlinux-core/
  - rust/crates/agentlinux/
  - plugin/lib/reuse/agents.sh
  - .github/workflows/test.yml
tech-stack:
  added: []
  patterns:
    - "pure decision (agentlinux-core::reuse) / adapter I/O (bin reads env + owns canonical map) split"
    - "bash→Rust shim via env-var-in / stdout-token-out contract preserving the language-agnostic bats spec (ADR-002)"
    - "AGENTLINUX_RUST_BIN env override (absolute-path pin) with bare-name PATH fallback; fail-closed on missing binary"
    - "gated CI job mirroring cli-unit guard shape (no job-level if → required-check always reports)"
key-files:
  created:
    - rust/crates/agentlinux-core/src/reuse.rs
    - .planning/phases/53-rust-scaffold-de-risking-spike/53-METRICS.md
  modified:
    - rust/crates/agentlinux-core/src/lib.rs
    - rust/crates/agentlinux/src/main.rs
    - plugin/lib/reuse/agents.sh
    - .github/workflows/test.yml
key-decisions:
  - "reuse::agent_decision decision body computed in Rust (agentlinux-core::reuse); the ~3-line agents.sh shim forwards the id and the DETECT_AGENT_* env to the bin"
  - "REUSE_AGENT_CANONICAL_PATHS + REUSE_GSD_SYSTEM_PATH deliberately KEPT in agents.sh (remediate.sh:288 iterates the map); consolidating the duplication is Phase 57"
  - "RUST-02 resolved to the literal reading: a separate gated rust job on every PR; the per-distro in-container musl build is Phase 59 GATE-02"
  - "bulk-port verdict for phases 54-59: GO (iterations-to-green=1 for all 5 units, 0 hallucinations, 0 cargo-timeouts on Opus 4.8)"
requirements-completed: [RUST-02, RUST-03, GATE-01, GATE-05]
coverage:
  - deliverable: "reuse::agent_decision ported to Rust (6 REUSE-03 branches) + reuse-decision subcommand (RUST-03 provisioner)"
    verification:
      - kind: test
        ref: "rust/crates/agentlinux-core/src/reuse.rs#tests (9 unit tests, 6 REUSE-03 branches)"
        status: pass
      - kind: command
        ref: "AGENTLINUX_RUST_BIN=<musl> agentlinux reuse-decision claude-code (healthy+canonical) → reuse"
        status: pass
    human_judgment: false
  - deliverable: "13-reuse.bats green on the Rust build behind the shim, zero bats edits (GATE-01)"
    verification:
      - kind: test
        ref: "tests/bats/13-reuse.bats (32/32 pass, 0 fail, 0 skip) in agentlinux-test:ubuntu-24.04 container with AGENTLINUX_RUST_BIN=<musl>"
        status: pass
      - kind: command
        ref: "git diff --name-only tests/bats/ → empty (zero bats edits)"
        status: pass
    human_judgment: false
  - deliverable: "14-remediate.bats smoke green (downstream consumer of reuse::agent_decision at remediate.sh:288)"
    verification:
      - kind: test
        ref: "tests/bats/14-remediate.bats (53/56 completed green, 0 fail; tests 54-56 are non-ported REMEDIATE-04 E2E exceeding per-run wall-clock — deferred to CI matrix)"
        status: pass
    human_judgment: true
    rationale: "3 of 56 tests (REMEDIATE-04 uninstall/reinstall E2E, NOT the ported surface) exceeded the 5-min per-run wall-clock in this VM; the reuse-consuming foundation tests incl. collect_all_decisions all passed. Full-matrix confirmation deferred to the CI rust + bats-docker jobs on fresh runners."
  - deliverable: "Gated rust CI job (fmt/clippy/test/static-musl-ldd) + rust/** changes filter (RUST-02)"
    verification:
      - kind: command
        ref: "python3 yaml.safe_load(test.yml): rust job present, needs=changes, no job-level if, all cost steps gated on guard.ready; rust/** in filter"
        status: pass
    human_judgment: false
  - deliverable: "53-METRICS.md — agent-loop cost + bulk-port verdict + GATE-05 rollback note (RUST-03, GATE-05)"
    verification:
      - kind: command
        ref: "grep: Verdict for the bulk port + GATE-05 rollback + RUST-02 Docker-matrix decision + per-unit table (classify/divergence/reuse-decision)"
        status: pass
    human_judgment: false
  - deliverable: "GATE-05 — master untouched; rust track additive + revertible"
    verification:
      - kind: command
        ref: "git log master --oneline -1 → f14c092 (unchanged); revert path db219d0+a1f9618 + rm rust/ documented"
        status: pass
    human_judgment: false
duration: 20 min
completed: 2026-07-28
---

# Phase 53 Plan 02: Rust Scaffold + De-Risking Spike (provisioner) Summary

Ported the gnarly REUSE-03 provisioner unit — `reuse::agent_decision`, the exact
sync-pain exemplar the stack-reconsideration decision quotes — into the Rust
binary behind the unchanged bats acceptance oracle with **zero bats edits**,
wired the gated Rust CI job into `test.yml`, and captured the agent-loop metrics
that return a **GO verdict** for the phases-54–59 bulk port.

- **Duration:** 20 min (2026-07-28T06:22:39Z → 2026-07-28T06:43:07Z)
- **Tasks:** 4/4 complete (Task 2 was the GATE-01 human-verify checkpoint — green)
- **Files:** 2 created, 4 modified

## Accomplishments

- **`agentlinux-core::reuse` — pure decision port (RUST-03 provisioner):** a
  `Decision { Reuse, Remediate, Create }` enum (lowercase `as_str`/`Display`
  tokens) + `agent_decision(id, status, detected_path, canonical, gsd_system_path)`
  that preserves the bash predicate order byte-for-byte (empty/absent/unknown →
  Create; broken → Remediate; healthy path-mismatch → Remediate except the
  gsd-at-VERSION-path → Reuse; else Reuse). Predicate 3 (semver) is NOT evaluated
  — the bash contract stops at predicates 1+2 and the CLI layers version-in-window
  on later; parity kept. The crate stays pure (no `std::env`/`fs`/`process`);
  9 `#[cfg(test)]` unit tests cover the six REUSE-03 branches + defensive cases.
- **`reuse-decision` subcommand (the adapter):** `agentlinux reuse-decision <id>`
  derives `DETECT_AGENT_<UPPER>_STATUS`/`_PATH` var names (`${id^^//-/_}` →
  `CLAUDE_CODE`), reads them from the env (matching `detect/agents.sh`'s contract),
  resolves the canonical path from a bin-local map mirroring the bash values, calls
  the pure core, and `print!`s one lowercase token with no trailing newline. The
  env/map reads live in the bin, the decision in core — the pure/adapter split.
- **The ~3-line `agents.sh` shim (GATE-01, zero bats edits):** the body of
  `reuse::agent_decision` now forwards to `${AGENTLINUX_RUST_BIN:-agentlinux}
  reuse-decision "$id"`. The `declare -gA REUSE_AGENT_CANONICAL_PATHS` map,
  `REUSE_GSD_SYSTEM_PATH`, the source-once guard, and the log.sh precondition are
  all preserved intact — `remediate.sh:288` still iterates the map's keys. The
  env-var-in / stdout-token-out contract is preserved so every 13-reuse.bats @test
  and the remediate.sh call site work verbatim.
- **Gated `rust` CI job + `rust/**` filter (RUST-02):** a `rust` job (`needs:
  changes`, no job-level `if` so the required-check context always reports) mirrors
  the `cli-unit` guard shape (`ready=false` when `code!=true` or `rust/Cargo.toml`
  absent), then runs `cargo fmt --check`, `cargo clippy --all-targets -- -D
  warnings`, `cargo test --all`, and a static-musl build + `ldd 'not a dynamic
  executable'` assertion — all gated on `guard.ready`. `rust/**` added to the
  `changes` paths-filter. `contents: read` least-privilege.
- **`53-METRICS.md` (RUST-03, first-class deliverable):** per-unit table
  (classify/divergence/reuse-decision, all iterations-to-green=1, 0 hallucinations,
  0 cargo-timeouts on Opus 4.8), the Docker/bats-integration friction finding, a
  **GO** bulk-port verdict for 54–59, the RUST-02 literal-reading note, and the
  GATE-05 rollback path.

## Verification Evidence

```
# RUST-03 — reuse unit + full workspace
$ cargo test -p agentlinux-core reuse   → 9 passed
$ cargo test --workspace                → 44 passed (was 35 in 53-01, +9 reuse)
$ cargo clippy --workspace --all-targets -- -D warnings  → clean
$ cargo fmt --all -- --check                              → clean

# reuse-decision token smoke (static musl bin)
$ DETECT_AGENT_CLAUDE_CODE_STATUS=healthy DETECT_AGENT_CLAUDE_CODE_PATH=/home/agent/.local/bin/claude \
    agentlinux reuse-decision claude-code   → reuse
$ agentlinux reuse-decision claude-code (status unset)  → create
$ DETECT_AGENT_GSD_PATH=/home/agent/.claude/gsd-core/VERSION ... reuse-decision gsd  → reuse
$ DETECT_AGENT_CLAUDE_CODE_STATUS=broken ... reuse-decision claude-code  → remediate

# GATE-01 — bats acceptance on the Rust build (agentlinux-test:ubuntu-24.04 container)
$ AGENTLINUX_RUST_BIN=<musl> bats tests/bats/13-reuse.bats   → 32/32 ok, 0 fail, 0 skip
    (all six REUSE-03 agent_decision branches + brownfield E2E via real agentlinux-install)
$ AGENTLINUX_RUST_BIN=<musl> bats tests/bats/14-remediate.bats → 53/56 completed green, 0 fail
    (tests 54-56 = non-ported REMEDIATE-04 E2E, exceed per-run wall-clock — deferred to CI matrix)
$ git diff --name-only tests/bats/   → empty (ZERO bats edits)

# fail-closed reliability (T-53-04)
$ AGENTLINUX_RUST_BIN=missing-bin reuse::agent_decision claude-code  → output="" rc=127 (no silent mis-verdict)

# security — id passed as quoted positional; malicious id is opaque data
$ agentlinux reuse-decision 'foo; rm -rf /'  → create (unknown id, no shell eval)

# RUST-02 — CI job
$ yaml.safe_load(test.yml): rust job present, needs=changes, no job-level if, cost steps gated on guard.ready
$ grep 'rust/\*\*' test.yml  → present in changes filter

# GATE-05
$ git log master --oneline -1  → f14c092 (unchanged)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocker] pre-commit shellcheck SC2034 on the now-externally-used map**
- **Found during:** Task 1 commit.
- **Issue:** Once the shim moved the decision body to the Rust bin,
  `REUSE_AGENT_CANONICAL_PATHS` and `REUSE_GSD_SYSTEM_PATH` are no longer read
  *inside* `agents.sh` (they are consumed cross-file by `remediate.sh:288`), so
  the pre-commit shellcheck hook flagged SC2034 "appears unused" and blocked the
  commit. Deleting them was NOT an option (the plan explicitly forbids it — the
  map iterator at remediate.sh:288 needs them; consolidation is Phase 57).
- **Fix:** added `# shellcheck disable=SC2034` directives with sibling comments
  documenting the external cross-file consumption (shellcheck cannot see it).
- **Files modified:** `plugin/lib/reuse/agents.sh`
- **Verification:** pre-commit shellcheck + shfmt pass; map still present
  (`grep -c` = 3); the collect_all_decisions bats test (which iterates the map)
  passes on the Rust build.
- **Commit:** db219d0

**Total deviations:** 1 auto-fixed (1 blocker). **Impact:** keeps the deliberately-
retained bash map lint-clean without deleting it, preserving the remediate.sh:288
contract exactly as the plan requires.

## Checkpoint Outcome (Task 2, GATE-01) — GREEN

The bats acceptance oracle ran against the Rust build inside the cached
`agentlinux-test:ubuntu-24.04` container using the OOM-safe targeted approach (the
full Docker suite OOMs ~test 131 in this VM, so `tests/docker/run.sh` was NOT
used). Built the static-musl binary, started the container with run.sh's
systemd/`--privileged` flags, staged sources, spliced the pre-built CLI bundle,
ran `agentlinux-install` (with `AGENTLINUX_RUST_BIN` exported), then ran the
ported-surface files with the env override.

**Exercised bats files + counts:**
- `tests/bats/13-reuse.bats` — **32/32 pass, 0 fail, 0 skip** (all six REUSE-03
  `agent_decision` branches + the two brownfield E2E tests that drive a real
  `agentlinux-install` provision through the Rust-backed shim).
- `tests/bats/14-remediate.bats` — **53/56 completed green, 0 fail.** Tests 54–56
  are REMEDIATE-04 uninstall/reinstall E2E (NOT the ported surface) and each
  exceeds a 5-minute per-run wall-clock in this VM (a time bound, not OOM, not a
  failure). The reuse-consuming foundation tests all pass, including
  `collect_all_decisions` (iterates the map at remediate.sh:288, calls the
  Rust-backed decision for every agent) and `reuse::user_decision predicate
  behavior unchanged`.

**Integration finding (the spike's actual signal):** the first installer run
failed at `agents.sh:75` with `agentlinux: command not found` — the installer's
own `collect_all_decisions` calls the shim, and bare `agentlinux` was not on the
installer's PATH; re-running with `AGENTLINUX_RUST_BIN` exported fixed it (exit 0).
Deployment implication (Phase 56/57): the Rust binary must be on PATH (or the env
pinned) before the provisioner's decision phase. Recorded in `53-METRICS.md`.

**Deferred to the orchestrator:** the formal full-matrix Docker-bats confirmation
across all four distro arms runs on the CI `rust` + `bats-docker` jobs on fresh
runners; the three REMEDIATE-04 E2E tail tests were not run to completion locally
due to the per-run wall-clock. No bats file was modified, so CI runs the identical
spec against the Rust build.

## Bulk-Port Verdict (from 53-METRICS.md)

**GO** for phases 54–59. Iterations-to-green = 1 for all five ported units
(workspace, semver_shim, classify, divergence, reuse-decision); zero crate
hallucinations (vs the worst-measured Opus-4 ~27%); zero cargo-timeouts. The exact
"bash stops at 2 of 3 predicates because semver is hard + hand-maintains a
CANONICAL_PATHS map" pain the decision quotes ported cleanly, and the
language-agnostic bats spec validated the Rust build unchanged. Go-with-eyes-open
caveats: the ~4.3k-LOC provisioner port (Phase 57) hits more adapter/I/O code where
the shim-binary PATH-ordering (integration finding above) needs care; token cost
per unit was not instrumented (runtime did not expose per-unit counts) — Phase 54
should capture it to close the last §7 unknown.

## Agent-Loop Metrics (53-02)

| Unit | Iterations-to-green | Crate hallucinations | cargo timeouts | Notes |
|------|---------------------|----------------------|----------------|-------|
| reuse-decision (+ bats) | 1 | 0 | 0 | 9 unit + 6 REUSE-03 branches green first `cargo test`; one clippy doc-indent + one rustfmt wrap auto-fixed pre-commit (formatting, not logic) |

No cargo-compile-timeout or crate-hallucination incidents. The logic was correct on
first `cargo test`; only mechanical formatting fixups were needed. Full cross-plan
table in `53-METRICS.md`.

## Next Phase Readiness

Phase 53 (Rust Scaffold + De-Risking Spike) is complete: RUST-01 (53-01 static
musl), RUST-02 (this plan's CI job), RUST-03 (classify/divergence/reuse-decision
ports + metrics), GATE-01 (bats-green on the Rust build), and GATE-05 (additive
revertible track) are all satisfied. The metrics return a GO verdict — ready for
`/gsd-verify-work 53` and then the phase-54 bulk-port planning.

## Deferred Issues

- The three REMEDIATE-04 E2E tail tests (14-remediate.bats 54–56) need the CI
  matrix (or a higher local wall-clock budget) for full local confirmation — a
  test-runtime cost, not a Rust-port risk. Owner: CI `bats-docker` matrix on the
  next PR push; re-check condition: green on fresh runners.

## Self-Check: PASSED

- Both created files verified present: `rust/crates/agentlinux-core/src/reuse.rs`,
  `.planning/phases/53-rust-scaffold-de-risking-spike/53-METRICS.md`.
- All 3 phase commits verified in `git log` on `worktree-stack-revisiting`:
  db219d0 (Rust port + shim), a1f9618 (CI job), 4fa37b0 (metrics).
- Plan-level verification re-run: 44 workspace tests PASS; clippy + fmt clean;
  reuse-decision tokens correct; 13-reuse.bats 32/32 on the Rust build; zero bats
  edits; master untouched (f14c092); fail-closed + injection-safe confirmed.
