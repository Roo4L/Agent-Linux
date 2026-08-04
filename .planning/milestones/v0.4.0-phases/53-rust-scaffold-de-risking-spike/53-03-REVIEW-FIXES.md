---
phase: 53
plan: 53-03
subsystem: rust-spike-review-fixes
tags: [rust, reuse, shim, ci, review-fixes, GATE-01, RUST-03]
status: complete
requires: [53-02-SUMMARY]
provides: [fail-safe-reuse-shim, ci-rust-hardening, bats-docker-rust-staging]
affects:
  - plugin/lib/reuse/agents.sh
  - tests/docker/run.sh
  - .github/workflows/test.yml
  - rust/crates/agentlinux-core/Cargo.toml
key-files:
  modified:
    - plugin/lib/reuse/agents.sh
    - tests/docker/run.sh
    - .github/workflows/test.yml
    - rust/crates/agentlinux-core/Cargo.toml
    - rust/Cargo.lock
completed: 2026-07-28
---

# Phase 53 Plan 03: Review-Fixes (4-reviewer consolidated pass) Summary

One-liner: made the Phase 53 reuse shim PREFER the Rust binary but FALL BACK to
the original in-shell logic (non-breaking + fail-safe), staged the real Rust
binary in the bats-docker harness so CI exercises the Rust path (GATE-01),
hardened the CI rust job, and dropped the unused `serde_json` dependency.

## The core problem being fixed

The Phase 53 shim replaced `reuse::agent_decision` with a bare 3-line call to the
Rust `agentlinux reuse-decision <id>` binary. But the binary is NOT staged in the
install path or the CI `bats-docker` harness (real staging is Phase 56/57), so the
committed branch would (a) break the brownfield-reuse install path and (b) fail
`13-reuse.bats` with exit 127 in CI. The shim also had no timeout/validation/
logging — an absent/hung/garbage binary would hang or misroute. Fixed by
try-Rust-else-bash + harness staging.

## What changed

### FIX 1 — `plugin/lib/reuse/agents.sh` (try-Rust-else-bash) — commit 1b5cd86
- `reuse::agent_decision` now resolves a binary defensively: `AGENTLINUX_RUST_BIN`
  is honoured ONLY if it is an ABSOLUTE path (`${bin:0:1} == /`) AND `-x`
  (security L1 — a bare relative name is rejected so a poisoned PATH entry can't
  be resolved); otherwise `command -v agentlinux`.
- If a usable binary resolves: run under a bounded `timeout 10s`, capture stdout +
  exit status. Trust the result ONLY when exit==0 AND the token is exactly one of
  `reuse|remediate|create`. Otherwise `log_error` a SPECIFIC message naming the
  failing `$bin`, `$id`, and exit code, then fall through.
- New `reuse::_agent_decision_bash()` holds the ORIGINAL master decision body
  VERBATIM (predicate-1 status via `detect::agent_status`, predicate-2 canonical
  lookup, broken→remediate, wrong-path→remediate except gsd
  `REUSE_GSD_SYSTEM_PATH`→reuse, path-match→reuse, empty-id→create). Sourced from
  `git show master:plugin/lib/reuse/agents.sh`.
- Non-breaking: environments without the staged binary (today's installer,
  current CI) behave exactly as master did.
- `REUSE_AGENT_CANONICAL_PATHS` / `REUSE_GSD_SYSTEM_PATH` maps + their
  `# shellcheck disable=SC2034` retained (remediate.sh:288 iterates them; the
  bash fallback reads both).

### FIX 2 — `tests/docker/run.sh` bats-docker staging (GATE-01) — commit d292407
- After the installer runs (which creates the `agent` user) and before the bats
  suite, build the static-musl binary on the host if a prebuilt one is absent
  (`cargo build --release --target x86_64-unknown-linux-musl -p agentlinux`) and
  `docker cp` it to `/home/agent/.local/bin/agentlinux` (agent-owned, NOT a
  /usr/local shim), `chown agent:agent`, `chmod +x`.
- Export `AGENTLINUX_RUST_BIN=/home/agent/.local/bin/agentlinux` into the bats
  `docker exec` env so the shim resolves the absolute path.
- Guarded: a missing/failed build is NON-FATAL — the shim falls back to bash and
  the suite still runs (exactly as master did). This makes the bats-docker job run
  the reuse tests against the REAL Rust binary.

### FIX 3 — `.github/workflows/test.yml` rust job hardening — commit 574c567
- Added `timeout-minutes: 15` to bound a hung rust job.
- Wrapped the `musl-tools` `apt-get` install in a `for i in 1 2 3` retry loop
  (5s backoff) so a transient mirror hiccup doesn't fail the gate.
- Gating/guard shape unchanged.

### FIX 4 — remove dead `serde_json` — commit 13e16d8
- `rust/crates/agentlinux-core/Cargo.toml`: removed `serde_json = "1"` (confirmed
  unused — no source references anywhere under `rust/crates/*/src/`). Kept `serde`
  + derives as cheap groundwork.
- Regenerated `Cargo.lock` (serde_json gone). Build/test/clippy/fmt all green.

## Verification evidence

### 1. Rust workspace (host, `. "$HOME/.cargo/env"`)
- `cargo test --workspace` → **44 passed** (3 suites), 0 failed.
- `cargo clippy --workspace --all-targets -- -D warnings` → **No issues found**.
- `cargo fmt --all -- --check` → clean.
- `grep 'name = "serde_json"' rust/Cargo.lock` → **GONE from Cargo.lock**.
- `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux` → built
  `target/x86_64-unknown-linux-musl/release/agentlinux` (562 KB); smoke
  `agentlinux reuse-decision ""` → `create` (exit 0).

### 2. Bash lint (both changed files)
- `shellcheck --severity=warning plugin/lib/reuse/agents.sh tests/docker/run.sh`
  → clean.
- `shfmt -i 2 -ci -bn -d` on the CHANGED function → no diff. (Two pre-existing
  shfmt quirks remain — hyphenated `REUSE_AGENT_CANONICAL_PATHS` keys in
  agents.sh and `SECRET_ALLOWLIST` comment alignment in run.sh — both confirmed
  identical on master via `git show master:… | shfmt -d`; NOT introduced here and
  NOT in the changed function.)

### 3. Host-side shim logic test (both paths, function-isolated)
Stubbed `detect::agent_status` + `log_error`, sourced the shim, and asserted
tokens. **12/12 pass**:
- (a) Rust path (`AGENTLINUX_RUST_BIN=<abs musl bin>`): absent→create,
  canonical→reuse, other-path→remediate, broken→remediate, gsd-syspath→reuse.
- (b) Bash fallback (`AGENTLINUX_RUST_BIN` unset, no `agentlinux` on PATH):
  identical tokens for all of the above + empty-id→create.
- (c) Security L1: bare-relative `AGENTLINUX_RUST_BIN=agentlinux` is REJECTED →
  bash fallback (returns create). Both paths return identical tokens.

### 4. Authoritative GATE-01 — `13-reuse.bats` in Docker against the REAL Rust bin
Docker WAS available in-session. Targeted run (run.sh runs the full suite which
OOMs this VM): started a container as run.sh does (`agentlinux-test:ubuntu-24.04`,
--privileged, cgroupns=host), staged `/opt/agentlinux-src` + CLI splice, ran the
installer (creates `agent` user), staged the host-built musl binary at
`/home/agent/.local/bin/agentlinux`, then:

```
docker exec <cid> bash -c 'cd /opt/agentlinux-src && \
  env AGENTLINUX_RUST_BIN=/home/agent/.local/bin/agentlinux bats tests/bats/13-reuse.bats'
```

Result: **32/32 ok, BATS_RC=0.** (14-remediate optional — the 3 long E2E were
already deferred in 53-02.)

**Proof the Rust path (not silent fallback) was exercised:** in a follow-up
in-container probe, `reuse::agent_decision claude-code` with a valid absolute
`AGENTLINUX_RUST_BIN` returned `reuse` while `detect::agent_status` was
deliberately left UNSTUBBED — the only stderr was
`detect::agent_status: command not found`, yet the correct token still came back.
That is only possible if the RUST binary computed the decision (it reads
`DETECT_AGENT_*` env vars directly and never calls the bash `detect::agent_status`);
the bash fallback would have errored out. Pointing `AGENTLINUX_RUST_BIN` at a
non-existent path then produced the same `reuse` via the bash fallback (with
`detect::agent_status` stubbed), no error. Both paths confirmed live and
token-identical.

## Deferred (recorded, not implemented)

- **main.rs always exits 0 on degraded decisions** (reliability #4, MEDIUM):
  defensible for a spike — the FIX-1 token validation makes the shim safe
  regardless of the binary's exit code (only exit==0 AND a valid token is
  trusted). Left as-is.
- **Cross-file CANONICAL_PATHS map duplication + a cross-language parity test**
  (security L3 / simplicity): the map now lives in three places
  (agents.sh, detect.ts, main.rs). Consolidation + a drift-guard parity test is
  correctly Phase 57 work, not this spike.

## Deviations from plan

None beyond the plan's own contingency: the GATE-01 Docker run required running
the installer FIRST (it creates the `agent` user that owns
`/home/agent/.local/bin`) before staging the binary — matching run.sh's own
ordering. This is exactly how FIX 2 sequences it in run.sh (stage after the
installer step), so the harness and the in-session proof agree.

## Commits

- 1b5cd86 fix(53): reuse::agent_decision prefers Rust bin, falls back to bash
- 13e16d8 chore(53): drop unused serde_json dep from agentlinux-core
- d292407 test(53): stage Rust agentlinux binary in bats-docker harness (GATE-01)
- 574c567 ci(53): harden rust job — timeout-minutes + apt retry loop

## Self-Check: PASSED

- `.planning/phases/53-rust-scaffold-de-risking-spike/53-03-REVIEW-FIXES.md` present.
- All 4 commits verified in `git log` on `worktree-stack-revisiting`.
- master untouched; no PR opened.
