---
phase: 53-rust-scaffold-de-risking-spike
plan: 01
subsystem: rust-core
tags: [rust, cargo-workspace, musl, semver, port]
requires: []
provides:
  - rust-workspace
  - agentlinux-core-crate
  - agentlinux-bin
  - semver-shim
  - classify-port
  - divergence-port
affects:
  - rust/
  - .gitignore
tech-stack:
  added:
    - "semver =1.0.28 (dtolnay)"
    - "serde 1 + serde_json 1"
    - "thiserror 1"
  patterns:
    - "pure core / thin bin split (mutation-test enabler for Phase 54)"
    - "semver compatibility shim isolating node-semver divergences behind typed errors"
key-files:
  created:
    - rust/Cargo.toml
    - rust/Cargo.lock
    - rust/rust-toolchain.toml
    - rust/.cargo/config.toml
    - rust/crates/agentlinux-core/Cargo.toml
    - rust/crates/agentlinux-core/src/lib.rs
    - rust/crates/agentlinux-core/src/types.rs
    - rust/crates/agentlinux-core/src/semver_shim.rs
    - rust/crates/agentlinux-core/src/classify.rs
    - rust/crates/agentlinux-core/src/divergence.rs
    - rust/crates/agentlinux/Cargo.toml
    - rust/crates/agentlinux/src/main.rs
  modified:
    - .gitignore
key-decisions:
  - "Rust lives at repo-root rust/ (not plugin/rust/) — keeps plugin/ the clean tarball boundary during the parallel track"
  - "semver pinned exactly to =1.0.28 (research-validated); semver_shim is the sole module touching the crate"
  - "classify/divergence validated by ported Rust golden-corpus unit tests (not wired behind live `list` — that is Phase 56)"
  - "parse_lenient coerces MAJOR.MINOR partials and strips a leading v; every entry point returns a typed error, never panics (T-53-01)"
requirements-completed: [RUST-01, RUST-03, GATE-05]
coverage:
  - deliverable: "Static musl agentlinux binary (RUST-01)"
    verification:
      - kind: command
        ref: "cargo build --release --target x86_64-unknown-linux-musl -p agentlinux && ldd <bin>"
        status: pass
    human_judgment: false
  - deliverable: "classify port — six-state verdict parity with TS golden corpus (RUST-03)"
    verification:
      - kind: test
        ref: "rust/crates/agentlinux-core/src/classify.rs#tests (7 states)"
        status: pass
    human_judgment: false
  - deliverable: "divergence port — computeDivergence + resolveLatestFor incl. typed zero-match error (RUST-03)"
    verification:
      - kind: test
        ref: "rust/crates/agentlinux-core/src/divergence.rs#tests (13 rows)"
        status: pass
    human_judgment: false
  - deliverable: "semver_shim — node-semver divergence isolation (normalize_range + parse_lenient + max_satisfying)"
    verification:
      - kind: test
        ref: "rust/crates/agentlinux-core/src/semver_shim.rs#tests (15 cases)"
        status: pass
    human_judgment: false
  - deliverable: "GATE-05 — master untouched, additive rust/ track on worktree-stack-revisiting"
    verification:
      - kind: command
        ref: "git log master --oneline -1 unchanged at f14c092"
        status: pass
    human_judgment: false
duration: 7 min
completed: 2026-07-28
---

# Phase 53 Plan 01: Rust Scaffold + De-Risking Spike (core) Summary

Stood up the repo-root `rust/` cargo workspace and proved the first v0.4.0 slice: a fully-static x86_64-musl `agentlinux` binary (RUST-01) plus the two pure-logic units — `classify` and `divergence` — ported into a separate `agentlinux-core` crate with verdicts identical to the TypeScript golden corpus, routed through a `semver_shim` that isolates the node-semver → dtolnay `semver 1.0.28` divergences behind typed errors (RUST-03 pure core).

- **Duration:** 7 min (2026-07-28T06:09:09Z → 2026-07-28T06:16:02Z)
- **Tasks:** 3/3 complete
- **Files:** 12 created, 1 modified

## Accomplishments

- **Cargo workspace + static musl (RUST-01):** `rust/` workspace (`resolver = "2"`, `members = ["crates/*"]`), pinned `rust-toolchain.toml` (channel `1.97.1`, musl target + clippy/rustfmt), and `.cargo/config.toml` setting `musl-gcc` linker + `target-feature=+crt-static`. `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux` yields a binary `ldd` reports as **statically linked**. `Cargo.lock` committed; `rust/target/` gitignored.
- **Pure core / thin bin split:** `agentlinux-core` (lib) is I/O-free — no `std::process`/`std::fs`/`std::env` (grep-confirmed) — so Phase 54's `cargo-mutants --package agentlinux-core` can scope to it. `agentlinux` (bin) is a thin `match`-on-argv entrypoint (no `clap` this phase) that exits 0 on no args.
- **semver_shim (the parity risk surface):** the ONLY module touching `semver::`. `normalize_range` converts space-separated compound ranges (`>=2.0.0 <3.0.0` → `>=2.0.0, <3.0.0`) to the comma form dtolnay requires; `parse_lenient` strips a leading `v` and coerces `MAJOR.MINOR` partials to full versions; `eq`/`gt`/`max_satisfying` route every version/range string through it. All malformed input returns a typed `SemverError` — no panics (T-53-01). 15 unit tests reproduce the research parity table.
- **classify + divergence ported (RUST-03):** `classify()` preserves the exact six-state TS branch order; `compute_divergence()` + `resolve_latest_for()` mirror the TS shapes with a typed `DivergenceError` for the empty-list and zero-match paths (mirroring the TS `throw`s). The `classify.test.ts` and `divergence.test.ts` tables are ported verbatim as `#[cfg(test)]` golden-corpus modules (7 + 13 rows). classify/divergence never call `semver::` directly (grep-confirmed — only prose in doc comments references it).
- **GATE-05:** all work on branch `worktree-stack-revisiting`; `master` untouched (still at `f14c092`); the `rust/` track is purely additive.

## Verification Evidence

```
# RUST-01 — static musl gate
$ cargo build --release --target x86_64-unknown-linux-musl -p agentlinux
    Finished `release` profile [optimized] target(s) in 0.76s
$ ldd target/x86_64-unknown-linux-musl/release/agentlinux
	statically linked
$ file <bin>
    ELF 64-bit LSB pie executable, x86-64, static-pie linked

# RUST-03 — full workspace test
$ cargo test --workspace
    test result: ok. 35 passed; 0 failed; 0 ignored   (agentlinux-core)
    (semver_shim 15 · classify 7 · divergence 13)

# quality gates
$ cargo clippy --workspace --all-targets -- -D warnings   → clean
$ cargo fmt --all -- --check                              → clean

# isolation
$ grep semver:: crates/agentlinux-core/src/{classify,divergence}.rs | grep -v '//'  → NONE
$ grep -E 'std::(process|fs|env)' crates/agentlinux-core/src/ | grep -v '//'         → CLEAN

# GATE-05
$ git log master --oneline -1  → f14c092 (unchanged)
```

Cargo.lock pins `semver v1.0.28` exactly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `normalize_range` was not idempotent on comma-form ranges**
- **Found during:** review loop (reliability lens), after Task 3.
- **Issue:** `normalize_range` split on whitespace only, so an already-comma'd compound range (`">=2.0.0, <3.0.0"`) became `">=2.0.0,, <3.0.0"` (doubled comma), which `VersionReq::parse` rejects. The doc comment falsely claimed idempotency. Latent for the current catalog (ranges are space-separated only per RESEARCH), but the shim is the exact surface Phase 54's parity audit re-exercises.
- **Fix:** split on whitespace AND commas, drop empty tokens, re-join with ", "; corrected the doc comment; added a round-trip idempotency test (`normalize_range_is_idempotent_on_comma_form`).
- **Files modified:** `rust/crates/agentlinux-core/src/semver_shim.rs`
- **Verification:** 15 semver_shim tests pass (was 14, +1); full workspace 35 pass; clippy + fmt clean.
- **Commit:** 584f10f

**Total deviations:** 1 auto-fixed (1 bug). **Impact:** hardens the load-bearing parity shim against a latent double-comma parse failure before the Phase-54 audit; no change to current-catalog behavior.

## Scope Notes (intentional, per plan)

- `decideVersion` (in `classify.ts`) and the `queryGlobalNpm`/`queryNpmViewLatest` suites (in `divergence.test.ts`) were **not** ported — they are impure npm-dispatcher / Phase-55/56 scope, explicitly excluded by the plan.
- classify/divergence are validated by ported unit tests, **not** wired behind live `agentlinux list` output (Phase 56).
- The `reuse::agent_decision` provisioner unit, the bash shim, the CI `rust` job, and `53-METRICS.md` are Plan 02 scope — not touched here.
- `classify`/`divergence` treat a shim parse-error as the safe non-`Synced` verdict (`unwrap_or(false)`) rather than panicking; this is the documented T-53-01 no-panic posture (node's `semver.eq` throws — the Rust side surfaces drift instead of crashing). Cannot fire for the corpus (all concrete versions).

## Agent-Loop Metrics (for 53-METRICS.md in Plan 02)

| Unit | Iterations-to-green | Crate hallucinations | cargo timeouts | Notes |
|------|---------------------|----------------------|----------------|-------|
| workspace/musl build | 1 | 0 | 0 | cold build ~11s; `ldd` static on first try |
| semver_shim | 1 | 0 | 0 | 14 tests green first run; rustfmt reflowed one chain |
| classify | 1 | 0 | 0 | 7 states green first run |
| divergence | 1 | 0 | 0 | 13 rows green first run |
| normalize_range idempotency fix | 1 | 0 | 0 | review-driven; +1 test |

No cargo-compile-timeout or crate-hallucination incidents. Cold first build ~11s; incremental test builds < 10s. All pinned crates (`semver`/`serde`/`serde_json`/`thiserror`) resolved on the first `cargo build`.

## Next Phase Readiness

Ready for **53-02** (reuse-decision provisioner unit port + bash shim + CI `rust` job + `53-METRICS.md`). The pure-core/thin-bin split, the semver shim, and the type mirrors are in place for the Plan-02 `reuse::agent_decision` port to consume.

## Deferred Issues

None.

## Self-Check: PASSED

- All 12 created files verified present on disk.
- All 4 commits verified in `git log` on branch `worktree-stack-revisiting`: 87b9938, 569ab36, c30ee20, 584f10f.
- Plan-level verification re-run: RUST-01 static musl gate PASS; 35 workspace tests PASS; clippy + fmt clean; semver isolation + no-forbidden-std confirmed; master untouched (GATE-05).
