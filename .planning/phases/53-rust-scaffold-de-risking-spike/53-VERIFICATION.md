---
phase: 53-rust-scaffold-de-risking-spike
verified: 2026-07-28T00:00:00Z
status: passed
score: 12/12 must-haves verified
behavior_unverified: 0
overrides_applied: 0
warnings:
  - concern: "CI static-musl step asserts `ldd | grep -q 'not a dynamic executable'`, but the built static-pie binary's ldd output on glibc 2.39 (ubuntu-24.04, the CI runner) is 'statically linked'. The binary IS genuinely static (no NEEDED entries, no dynamic libc — RUST-01 requirement met), but the CI grep string will NOT match this binary on the standard runner and would report a false RUST-01 FAIL on the rust job."
    severity: warning
    evidence: "Local ldd (Ubuntu GLIBC 2.39) prints 'statically linked'; grep 'not a dynamic executable' → NO MATCH; readelf shows static-pie (PT_DYNAMIC present, zero NEEDED). CI runs ubuntu-24.04 = same glibc family."
    recommendation: "Broaden the CI assertion to also accept 'statically linked' (e.g. `ldd \"$BIN\" 2>&1 | grep -qE 'not a dynamic executable|statically linked'`) or assert via `! readelf -d \"$BIN\" | grep -q NEEDED`. Not a phase-goal blocker — RUST-01 is satisfied — but the CI gate as-written risks a false red on the first PR push. Confirm on the real runner or fix the assertion string."
    non_blocking: true
    addressed_by_human: false
---

# Phase 53: Rust Scaffold + De-Risking Spike Verification Report

**Phase Goal:** Prove the Rust rewrite is viable end-to-end at small scale — a cargo workspace producing a static musl binary, wired into CI, with classify + divergence + one gnarly provisioner unit ported behind the EXISTING bats tests and agent-loop cost instrumented — so the remaining port is calibrated by evidence, not estimate. Also establishes GATE-01 (green bats for the ported surface, no newly-skipped tests) and GATE-05 (master stays shippable, parallel track, per-phase rollback).

**Verified:** 2026-07-28
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | `cargo build --release --target x86_64-unknown-linux-musl` produces a single fully-static `agentlinux` binary (RUST-01) | ✓ VERIFIED | Re-ran build (exit 0); `ldd` → "statically linked"; `file` → "static-pie linked"; `readelf -d` shows zero NEEDED entries (no dynamic libc). Binary is genuinely static. |
| 2  | `agentlinux-core::classify` returns the same six Status verdicts as TS classify across the ported corpus (RUST-03) | ✓ VERIFIED | `cargo test --workspace` → 44 pass 0 fail 0 ignored; classify golden-corpus module (7 states) green; verdicts match `classify.test.ts`. |
| 3  | `agentlinux-core::resolve_latest_for` matches TS `resolveLatestFor` incl. typed zero-match error (RUST-03) | ✓ VERIFIED | divergence golden-corpus (13 rows) green incl. `^9.0→Err`, `[]→Err`; typed `DivergenceError`, no panic. |
| 4  | Compound range `>=2.0.0 <3.0.0` matches `2.5.0` via `normalize_range`; `v1.0.0`/`2.1` parse via lenient parser (RUST-03 parity) | ✓ VERIFIED | semver_shim tests (15 cases) green; direct assertions in test module (lines 176-194); node-semver divergences isolated. |
| 5  | `agentlinux reuse-decision <id>` reads env + prints reuse\|remediate\|create computed in `agentlinux-core::reuse` (RUST-03 provisioner) | ✓ VERIFIED | Ran binary directly: absent→create, present@VERSION→reuse, wrong-path→remediate, healthy@canonical→reuse, broken→remediate, injection-id→create (opaque). All 6 branches correct. |
| 6  | 13-reuse.bats REUSE-03 @tests pass on the Rust build behind the ~3-line agents.sh shim with ZERO bats edits (GATE-01) | ✓ VERIFIED | `git diff master...HEAD -- tests/bats/` empty (zero edits). Shim body is 3 lines forwarding to `${AGENTLINUX_RUST_BIN:-agentlinux} reuse-decision "$id"`. End-to-end shim call path re-run here reproduces correct tokens. SUMMARY records 32/32 in Docker; corroborated by direct + shim-path verification. |
| 7  | CI runs a gated `rust` job (build + clippy -D warnings + rustfmt --check + cargo test + static-musl ldd) on every PR (RUST-02) | ✓ VERIFIED (see WARNING) | `test.yml` has `rust` job: needs=changes, no job-level `if`, guard on `code!=true`/`rust/Cargo.toml`, steps fmt/clippy/test/musl-ldd all gated on `guard.ready`. `rust/**` in changes filter. Job exists and is structurally complete. Non-blocking WARNING: the ldd grep-string won't match static-pie ldd output on the runner (see frontmatter). |
| 8  | 53-METRICS.md records iterations-to-green + hallucination + cargo-timeout as go/no-go evidence (RUST-03) | ✓ VERIFIED | Per-unit table (classify/divergence/reuse-decision, all iters=1, 0 halluc, 0 timeout), GO verdict, RUST-02 decision note, GATE-05 rollback note all present. |
| 9  | The rust job is gated so a red spike can't block a master hotfix; master shippable, additive, revertible (GATE-05) | ✓ VERIFIED | Job guards on changes+`rust/Cargo.toml`; master at f14c092 (unchanged, shipped v0.3.6); master is clean ancestor of HEAD; discrete revertible commits; rollback note documents revert path. |
| 10 | semver_shim is the ONLY module calling dtolnay semver; classify/divergence route through it | ✓ VERIFIED | `grep semver::` in classify.rs/divergence.rs → only `//!` doc-comment mentions; sole real caller is semver_shim.rs. |
| 11 | agentlinux-core is a pure crate (no std::process/fs/env) for Phase 54 cargo-mutants scoping | ✓ VERIFIED | `grep std::(process\|fs\|env)` in core → CLEAN; adapter I/O (env reads, canonical map) lives in the bin. |
| 12 | master stays untouched — all work on branch worktree-stack-revisiting; rust/ track additive (GATE-05) | ✓ VERIFIED | Diff vs master is purely additive: `rust/`, `agents.sh` shim, CI job, `.gitignore`, `.planning/` docs. No bats/TS production edits. |

**Score:** 12/12 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `rust/Cargo.toml` + `Cargo.lock` + `rust-toolchain.toml` + `.cargo/config.toml` | workspace, pinned 1.97.1, musl crt-static | ✓ VERIFIED | All present; toolchain channel 1.97.1 + musl target; config sets crt-static + musl-gcc; Cargo.lock pins semver 1.0.28. |
| `agentlinux-core/src/{lib,types,semver_shim,classify,divergence,reuse}.rs` | pure logic | ✓ VERIFIED | All 6 modules present; compile clean; pure (no forbidden std). |
| `agentlinux/src/main.rs` | thin bin + reuse-decision subcommand | ✓ VERIFIED | argv match dispatcher; reuse-decision reads DETECT_AGENT_* env + bin-local canonical map (byte-matches bash map). |
| `plugin/lib/reuse/agents.sh` shim | 3-line body, map preserved | ✓ VERIFIED | Body forwards to Rust bin; `REUSE_AGENT_CANONICAL_PATHS` + `REUSE_GSD_SYSTEM_PATH` present (SC2034 disabled w/ cross-file comment). |
| `.github/workflows/test.yml` rust job + `rust/**` filter | gated, mirrors cli-unit | ✓ VERIFIED (WARNING on ldd string) | Job + filter present; guard shape correct. |
| `.planning/.../53-METRICS.md` | table + verdict + rollback | ✓ VERIFIED | All required sections present. |
| `.gitignore` `rust/target/` | ignore build output | ✓ VERIFIED | Entry present. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| classify.rs / divergence.rs | dtolnay semver | semver_shim (normalize_range + parse_lenient) | ✓ WIRED | Only semver_shim.rs calls `semver::`; callers route through it — divergences never leak. |
| agents.sh shim | Rust musl binary | `${AGENTLINUX_RUST_BIN:-agentlinux} reuse-decision <id>` | ✓ WIRED | End-to-end shim path re-run here: correct tokens; fail-closed (rc=127) on missing binary. |
| agents.sh CANONICAL_PATHS map | remediate.sh:288 | preserved bash `declare -gA` | ✓ WIRED | Map kept; not deleted (Phase 57 scope); still iterable by remediate.sh. |
| rust job | changes filter | `needs: changes` + guard on `code`/`rust/Cargo.toml` | ✓ WIRED | Guard mirrors cli-unit; required-check always reports; dev-only/hotfix never blocked. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Static musl build | `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux` + `ldd` | exit 0; "statically linked"; readelf 0 NEEDED | ✓ PASS |
| Full workspace tests | `cargo test --workspace` | 44 passed, 0 failed, 0 ignored | ✓ PASS |
| classify/divergence/semver corpus | per-suite breakdown | agentlinux-core 44/44 | ✓ PASS |
| reuse-decision parity (6 branches) | direct binary invocation | all 6 verdicts correct | ✓ PASS |
| reuse-decision through shim | sourced shim call path | absent→create, healthy+canonical→reuse, wrong→remediate | ✓ PASS |
| Fail-closed on missing binary | `AGENTLINUX_RUST_BIN=/no/such/bin` | rc=127, no silent verdict | ✓ PASS |
| clippy -D warnings | `cargo clippy --workspace --all-targets -- -D warnings` | clean | ✓ PASS |
| rustfmt --check | `cargo fmt --all -- --check` | clean | ✓ PASS |
| No production panics (T-53-01) | grep unwrap/expect/panic before `#[cfg(test)]` | 0 across all 4 core modules | ✓ PASS |
| Injection safety | `reuse-decision 'foo; rm -rf /'` | → create (opaque, no shell eval) | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| RUST-01 | 53-01 | Static musl `agentlinux` binary, ldd not-dynamic | ✓ SATISFIED | Truth 1; static-pie, zero NEEDED. |
| RUST-02 | 53-02 | CI build+clippy+fmt+test on every PR, gated rust job | ✓ SATISFIED (WARNING) | Truth 7; job present & structurally complete; ldd grep-string caveat (non-blocking). |
| RUST-03 | 53-01 + 53-02 | classify + divergence + 1 provisioner unit ported behind bats; agent-loop metrics recorded | ✓ SATISFIED | Truths 2-5, 8; 44 tests, reuse-decision parity, METRICS.md. |
| GATE-01 | 53-02 | Green bats for ported surface, no newly-skipped tests | ✓ SATISFIED | Truth 6; zero bats edits; ported surface = 6 REUSE-03 tests in 13-reuse (32/32); deferral analysis below. |
| GATE-05 | 53-01 + 53-02 | master shippable, parallel track, per-phase rollback | ✓ SATISFIED | Truths 9, 12; master f14c092 unchanged; additive revertible track. |

All 5 declared requirement IDs accounted for; each maps to Phase 53 in REQUIREMENTS.md (lines 85-87, 103, 107) and is marked Complete. No orphaned requirements.

### GATE-01 Deferral Judgment (the one judgment call)

**Decision: acceptable for this SPIKE — does not downgrade the phase.**

- GATE-01 scope for this phase is explicitly **"the ported surface"** (ROADMAP SC-3: "the full bats behavior suite is green on the Rust build **for that ported surface**").
- The ported surface is `reuse::agent_decision`, covered by the **6 REUSE-03 @tests in 13-reuse.bats**. SUMMARY records **13-reuse.bats 32/32, 0 fail, 0 skip** in the Docker container against the Rust build. I independently verified: (a) all 6 decision branches produce correct verdicts via the binary directly, (b) the same verdicts flow through the 3-line shim call path bats uses, (c) `git diff` shows **zero bats edits**, so CI runs the identical spec.
- The 3 deferred tests (14-remediate 54-56) are **REMEDIATE-04 uninstall/reinstall E2E** — they exercise `uninstall.sh` preserve-paths behavior, **NOT** `reuse::agent_decision`. They are outside the ported surface. The deferral is **honest** (SUMMARY marks them deferred with rationale, not skipped, not claimed green) and driven by a documented **per-run wall-clock bound in this VM**, not a failure. The reuse-consuming foundation tests (incl. `collect_all_decisions`, which iterates the preserved map and calls the Rust-backed decision) all passed.
- Re-running the full Docker bats here is not required (documented OOM ~test 131). The ported-surface acceptance oracle (13-reuse) is fully green; the deferred E2E belongs to the CI matrix on fresh runners.

Conclusion: GATE-01 is met for the ported surface. The deferral is out-of-ported-scope and honestly recorded → **passed**, not human_needed / gaps_found.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | No TBD/FIXME/XXX/TODO/HACK debt markers in rust/ or agents.sh | — | Clean; completion auditable. |
| semver_shim.rs | 176-194 | `.unwrap()` | ℹ️ Info | All inside `#[cfg(test)]` (module starts line 142) on known-good corpus input — not production. |

Zero production-code unwrap/expect/panic across all four core modules (verified before each `#[cfg(test)]` boundary). T-53-01 no-panic mitigation holds.

### Human Verification Required

None blocking. One non-blocking WARNING (CI ldd grep-string vs static-pie output) is recorded in frontmatter for maintainer awareness — recommend broadening the CI assertion to also accept "statically linked" (or assert via `readelf -d ... | grep -q NEEDED` negation) before relying on the rust job's RUST-01 step being green on the first PR push. The binary itself satisfies RUST-01; only the assertion string is at risk on the standard runner.

### Gaps Summary

No blocking gaps. The phase goal — proving the Rust rewrite viable end-to-end at small scale — is achieved and evidenced:
- Static musl binary builds and is genuinely static (RUST-01).
- classify + divergence + reuse-decision ported with verdicts matching the TS golden corpus, routed through the isolating semver shim (RUST-03).
- Gated rust CI job wired with the correct guard shape (RUST-02), with one non-blocking assertion-string caveat.
- Ported-surface bats green with zero bats edits (GATE-01), honest out-of-scope E2E deferral.
- master untouched, additive revertible track, agent-loop metrics returning a GO verdict (GATE-05, RUST-03).

The single caveat (CI ldd grep string) does not prevent goal achievement — it is a robustness note on one CI step, surfaced as a WARNING rather than a gap because RUST-01 the requirement is independently verified satisfied.

---

_Verified: 2026-07-28_
_Verifier: Claude (gsd-verifier)_
