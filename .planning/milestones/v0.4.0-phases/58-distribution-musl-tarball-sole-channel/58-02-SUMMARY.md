---
phase: 58
plan: 02
subsystem: distribution / provisioner-staging / installer
tags: [DIST-01, GATE-01, GATE-05, musl-swap, coupled-staging-swap]
requires:
  - "58-01 (build-release.sh ships plugin/bin/agentlinux musl bin; fpm/.deb gone)"
provides:
  - "registry_cli.rs stages the musl bin as the default agentlinux command"
  - "install.sh execs the musl `provision` (no Node prereq); sha256-before-exec intact"
  - "the coupled installer/registry bats re-pointed to the musl artifact"
affects:
  - "58-03 (Wave 3 folds the harness flags into the default + adds AGENTLINUX_LEGACY_TS=1 rollback + 61-no-node-prereq)"
tech-stack:
  added: []
  patterns:
    - "static-bin staging (install -m0755 a single bin) replaces TS-bundle cp -R"
    - "curl-installer no-Node handoff: exec <bin> provision --user … --yes"
    - "regime-adaptive INST-02 idempotency (musl re-run vs legacy-TS re-run)"
key-files:
  created: []
  modified:
    - rust/crates/agentlinux/src/provision/registry_cli.rs
    - packaging/curl-installer/install.sh
    - tests/bats/60-curl-installer.bats
    - tests/bats/10-installer.bats
    - tests/bats/13-reuse.bats
    - tests/bats/40-registry-cli.bats
    - tests/docker/run.sh
decisions:
  - "INST-02 re-run is regime-matched (re-run the SAME provisioner that produced the state) — required for idempotency to hold on the Rust build without crossing artifact regimes"
  - "run.sh AGENTLINUX_PROVISION_RUST seam splices the built musl bin into the staged src root so registry_cli.rs finds the artifact it stages (payload/exec/stage triad)"
  - "INST-02 CLI byte-stability hash: whole staged musl bin sha256 (equal-or-stronger than the old shebang first-line hash)"
metrics:
  duration: ~25m
  completed: 2026-07-29
  files_changed: 7
  commits: 2
status: complete
---

# Phase 58 Plan 02: The Coupled Staging Swap Summary

Made the static musl binary the default shipped + staged `agentlinux` command:
`registry_cli.rs` stages `plugin/bin/agentlinux` (not `dist/index.js`),
`install.sh` execs the musl `provision --user … --yes` with no Node bootstrap,
and the four coupled installer/registry bats moved in lockstep — all green on
the Rust build on both distros while the sha256-before-exec critical gate stays
verbatim.

## What Was Built

### Task 1 — `registry_cli.rs` + `install.sh` (commit `7a3da01`)

- **`registry_cli.rs`** (the Rust provisioner step-50):
  - Malformed-tarball sanity checks re-pointed from `dist/index.js` +
    `node_modules` + `package.json` to: the musl bin at `src_root()/bin/agentlinux`
    exists + is a regular file + is executable. KEPT the `catalog.json` check.
  - CLI stage: `install -m0755 -o root -g root` the single static bin at
    `/opt/agentlinux/cli/<ver>/bin/agentlinux`, replacing the `cp -R` of
    `dist/node_modules/package.json`. `copy_tree_contents` / `chmod_recursive_ugo`
    retained (still used by the UNCHANGED catalog staging).
  - Symlink target moved from `cli/<ver>/dist/index.js` to
    `cli/<ver>/bin/agentlinux`; `ln -sfn` + `chown -h` unchanged.
  - Catalog snapshot + state dir + as-user `test -x` verify UNCHANGED
    (CAT-01/02/03/05 + CLI-01 hold).
- **`install.sh`** (curl-pipe entrypoint):
  - `exec` target re-pointed from the Bash `plugin/bin/agentlinux-install` to
    `exec "${inst}/plugin/bin/agentlinux" provision --user "$target_user" --yes "$@"`
    (Open Q2 — `--yes` for the inherently non-interactive pipe path, matching
    `run.sh:308`). No Node bootstrap before the bin runs.
  - Added `: "${AGENTLINUX_USER:=agent}"` to the env block.
  - The sha256-before-exec gate (`:210-211`), gzip magic check, `main(){}`
    wrapper, and `resolve_version` are UNTOUCHED — only the downstream exec target
    moved. Gate order preserved: sha256 verify (210) → tar extract (221) →
    exec (242).

### Task 2 — the four coupled bats + one harness deviation (commit `bc08d62`)

- **HUNK A — `60-curl-installer.bats`**: fixture stages `build/plugin/bin/agentlinux`
  (a fake bin stub accepting `provision …`); happy-path asserts the exec handoff to
  the musl bin (sentinel survives). Tamper / main-wrapper / resolve_version @tests
  UNCHANGED.
- **HUNK B — `10-installer.bats` INST-02**: CLI byte-stability hash re-pointed from
  the `dist/index.js` shebang first line to the **sha256 of the whole staged musl
  bin** (equal-or-stronger). The re-run is regime-matched (musl:
  `<staged-bin> provision --user agent --yes`; legacy-TS: the Bash entrypoint).
  9-file find-set + symlink-target assertion UNCHANGED.
- **HUNK C — `13-reuse.bats` REUSE-03**: both blocks resolve the CLI via
  `sudo -u agent -H bash --login -c 'command -v agentlinux'` (the staged musl
  command on the agent PATH) instead of globbing `find … -name index.js -path
  '*/dist/*'`. The list-suffix guard is `__fail` (not `skip`) so REUSE-03 is NOT
  silently skipped. Behavioral assertions (no-op / reused-suffix) UNCHANGED.
- **HUNK D — `40-registry-cli.bats`**: comment-only correction of the CLI-01 head
  comment; @test body UNCHANGED.
- **Harness deviation — `tests/docker/run.sh`**: the `AGENTLINUX_PROVISION_RUST`
  seam now splices the built musl bin into `/opt/agentlinux-src/plugin/bin/agentlinux`
  so the swapped `registry_cli.rs` sanity-check finds the artifact it stages (see
  Deviations).

## How It Was Verified

`cargo test --workspace` (338 passed), `cargo clippy -p agentlinux --all-targets
-- -D warnings` (clean), `cargo fmt --all --check` (clean).

Coupled bats on the Rust build (`AGENTLINUX_PROVISION_RUST=1` [+ `STAGE_RUST_CLI=1`
for the CLI bats]) on **both** distros:

| bats | ubuntu-24.04 | almalinux-9 |
|------|-------------|-------------|
| 60-curl-installer | 4/4 ✓ | 4/4 ✓ |
| 10-installer (incl. INST-02) | 11/11 ✓ | 11/11 ✓ |
| 40-registry-cli | 29/29 ✓ | 29/29 ✓ |
| 23-install-user | 9/9 ✓ | 9/9 ✓ |
| 13-reuse | 31/32 ✓ (only #29) | 31/32 ✓ (only #29) |

- The `60-curl-installer` sha256-tamper @test still fails closed (exit non-zero,
  "SHA256 verification failed", no extraction) — the critical rule holds.
- 13-reuse's only red is the pre-existing **#29** schema `compatibility_window`
  test (Phase-57 `deferred-items.md`, red on BOTH builds, out of scope). The
  re-pointed REUSE-03 brownfield E2E tests (31, 32) are GREEN — REUSE-03 is not
  silently skipped.

## Deviations from Plan

### Auto-fixed / added (beyond the enumerated 5 hunks)

**1. [Rule 3 — blocking harness plumbing] `tests/docker/run.sh` musl-bin splice into the staged src root**
- **Found during:** Task 2 baseline run of `10-installer` under `AGENTLINUX_PROVISION_RUST=1`.
- **Issue:** After the Task-1 swap, the Rust provisioner's step-50 stages the
  musl bin from `$AGENTLINUX_SRC_ROOT/bin/agentlinux` (default
  `/opt/agentlinux-src/plugin/bin/agentlinux`). run.sh copies the read-only
  `/workspace` tree, which carries only the Bash entrypoint under `plugin/bin/`
  (the musl bin is gitignored / produced by build-release.sh). Without staging
  the bin there, the swapped sanity-check dies "release tarball malformed?".
- **Fix:** Inside the existing `AGENTLINUX_PROVISION_RUST` block, `docker cp` the
  built `$HOST_MUSL_BIN` to `/opt/agentlinux-src/plugin/bin/agentlinux` (0755) —
  mirrors the existing TS-oracle CLI-bundle splice. Scoped to the Rust-provision
  seam only. This is harness plumbing (not a bats spec re-point) implementing the
  payload/exec/stage triad the swap couples.
- **Files modified:** `tests/docker/run.sh`
- **Commit:** `bc08d62`

**2. [In-scope extension of HUNK B — required for a green INST-02] regime-matched INST-02 re-run**
- **Found during:** Task 2 baseline — with only the shebang→sha256 re-point,
  INST-02's surviving symlink-target stability check FAILED
  (`before=.../bin/agentlinux after=.../dist/index.js`).
- **Root cause (a real missed coupling, per the W-1 warning):** INST-02 re-runs
  `bash "$INSTALLER"` (the Bash entrypoint), but the initial install on the Rust
  build is the Rust provisioner. The Bash re-run re-stages `dist/index.js` and
  flips the symlink, crossing artifact regimes.
- **Fix:** Make the re-run regime-matched — detect the staged artifact
  (`bin/agentlinux` = musl, else `dist/index.js` = legacy-TS) and re-run the SAME
  provisioner (musl: `<staged-bin> provision --user agent --yes`; legacy-TS: the
  Bash entrypoint). This keeps INST-02 green under BOTH the Rust default and the
  Wave-3 `AGENTLINUX_LEGACY_TS=1` rollback without dropping any assertion. It is
  intrinsic to "re-point INST-02 to the musl artifact" (the re-run mechanism IS
  part of the idempotency assertion being re-pointed), not an unrelated spec edit.
- **Files modified:** `tests/bats/10-installer.bats`
- **Commit:** `bc08d62`

**3. [gitleaks false-positive rewording] `install.sh` `--user` comment**
- **Issue:** The first Task-1 commit tripped gitleaks' `curl-auth-user` rule
  because the comment adjacency of `curl` + `--user "…"` looked like a curl
  credential.
- **Fix:** Reworded the comment (removed the `curl` adjacency) and hoisted
  `local target_user="${AGENTLINUX_USER:-agent}"`; the exec behavior is identical.
- **Files modified:** `packaging/curl-installer/install.sh`
- **Commit:** `7a3da01`

No architectural (Rule 4) deviations were needed.

## Invariants Preserved

- **sha256-before-exec (critical rule):** UNTOUCHED — verify (210) precedes
  extract (221) precedes exec (242); tamper still fails closed.
- **`agentlinux-core`:** 0 files changed this wave (pure).
- **`plugin/cli/` (TS oracle):** retained (deletion deferred to Phase 59).
- **`plugin/bin/agentlinux-install` (Bash rollback entrypoint):** retained (GATE-05).
- **No `/usr/local/bin` shim:** the bin stays under `/opt/agentlinux/cli/<ver>/bin/`
  + the agent-home symlink (T-58-06 mitigation preserved).

## Known Stubs

The `60-curl-installer.bats` fixture uses a shell `agentlinux` stub in place of
the real musl bin — this is an intentional, pre-existing test fixture pattern
(the test exercises install.sh's fetch/verify/extract/exec handoff, not the real
provision). Not a product stub.

## Notes for Wave 3 (58-03)

- Fold `AGENTLINUX_STAGE_RUST_CLI` / `AGENTLINUX_PROVISION_RUST` into the run.sh
  default (Rust becomes the no-flag artifact) — the src-root splice added here
  should move with the fold.
- Add the `AGENTLINUX_LEGACY_TS=1` inverse rollback lever (the INST-02
  regime-detection already supports the legacy-TS re-run path).
- Add `61-no-node-prereq.bats` (static-link + no-node-before-bin negative
  assertion).

## Self-Check: PASSED

- Created `58-02-SUMMARY.md` — FOUND.
- All 7 modified files — FOUND.
- Commits `7a3da01`, `bc08d62` — FOUND.
