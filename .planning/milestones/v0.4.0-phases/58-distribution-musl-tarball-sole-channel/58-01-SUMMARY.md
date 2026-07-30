---
phase: 58-distribution-musl-tarball-sole-channel
plan: 01
subsystem: distribution / release-packaging
tags: [reproducible-build, musl, tarball, sha256, dist-02, fpm-removal]
requires:
  - Phase 57 provisioner complete (338 tests green at HEAD)
  - rust/rust-toolchain.toml pins 1.97.1 + x86_64-unknown-linux-musl
provides:
  - "scripts/build-release.sh produces a reproducible x86_64-musl tarball + .sha256 (the sole channel)"
  - "rust/Cargo.toml [profile.release] strip=true — reproducibility control for the shipped bin"
  - "Cargo.toml version-parity leg in the release version lock"
  - "fpm/.deb path fully removed across code + docs; ADR-006 flagged superseded-in-part"
affects:
  - "Wave 2 (58-02): consumes the plugin/bin/agentlinux musl bin this tarball ships"
  - "Wave 3 (58-03): folds the harness flags + adds the rollback lever"
tech-stack:
  added: []
  patterns:
    - "reproducible static-bin tarball (strip + --remap-path-prefix + --build-id=none + SOURCE_DATE_EPOCH-pinned tar)"
    - "mktemp staging tree so no repo build-output leaks into the payload"
    - "static-PIE detection via readelf NEEDED+INTERP (not the ldd exit code)"
key-files:
  created: []
  modified:
    - scripts/build-release.sh
    - rust/Cargo.toml
    - .github/workflows/release.yml
    - tests/harness/00-layout.bats
    - tests/qemu/boot.sh
    - tests/docker/rc-sandbox.sh
    - docs/HARNESS.md
    - AGENTS.md
    - docs/decisions/006-curl-pipe-bash-plus-deb.md
  deleted:
    - packaging/deb/postinst.sh
    - packaging/deb/.gitkeep
decisions:
  - "Version lock keeps package.json + catalog.json as the parity oracle and ADDS a Cargo.toml parity leg (Open Q3 option a); full re-base deferred to Phase 59."
  - "[profile.release] added to the workspace rust/Cargo.toml (shared) rather than per-crate; strip=true + release-only RUSTFLAGS for build-id/path-remap."
  - "Static-link assertion uses readelf NEEDED+INTERP because musl links a static-PIE (has a dynamic section, zero NEEDED, no interpreter) and glibc ldd exits 0 on a static bin — the naive `if ldd` check false-positives."
  - "ADR-006 flagged Superseded-in-part (channel 2 .deb removed; channel 1 + mandatory .sha256 survive); ADR retained as historical record."
metrics:
  duration: ~30m
  completed: 2026-07-29
  tasks: 2
  files: 11
status: complete
---

# Phase 58 Plan 01: Distribution — musl Tarball Producer + DIST-02 Deletions Summary

Rewired `scripts/build-release.sh` to build and ship the static
`x86_64-unknown-linux-musl` `agentlinux` bin (at `plugin/bin/agentlinux`) in a
byte-reproducible tarball + `.sha256` as the sole distribution channel, dropping
the pnpm/TS-bundle build entirely, and deleted every fpm/`.deb` reference across
the code surface + docs (DIST-02).

## What was built

### Task 1 — build-release.sh musl producer swap + reproducible profile + version parity
- **Producer swap (DIST-01):** replaced the `cd plugin/cli && pnpm install/build/prune`
  block with `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux`,
  staged into a `mktemp -d` payload tree (`plugin/bin/agentlinux` 0755 + `plugin/catalog/`
  verbatim), and pointed the retained reproducible-tar recipe at that staging root
  via `tar -C "$STAGE_DIR"`. No pnpm/npm anywhere on the producer path; the TS
  bundle stops shipping (`plugin/cli/` stays in-repo only as the parity oracle).
- **Reproducible bin (Pitfall 6 / T-58-01):** added `[profile.release] strip = true`
  to `rust/Cargo.toml` and exported release-only RUSTFLAGS
  (`--remap-path-prefix` for `$PWD`/`$CARGO_HOME`/`$HOME` + `-C link-arg=-Wl,--build-id=none`).
- **Version lock (Open Q3 option a / Pitfall 3 / T-58-03):** added a
  `rust/crates/agentlinux/Cargo.toml` `[package] version` parity gate alongside the
  existing package.json + catalog.json legs (`sed`-read; suffix-stripped compare).
- **Static-link assertion (RUST-01):** `readelf` NEEDED + INTERP check (0/0 for the
  static-PIE musl bin), with a `file` fallback.
- Removed the fpm block, `--no-deb`/`NO_DEB_FLAG`, `SKIP_DEB`/`DEB_SUFFIX`/`DRY_DEB_LINE`,
  and the `.deb` usage/header lines. `--dry-run` retained.

### Task 2 — DIST-02 deletion sweep
- `git rm packaging/deb/postinst.sh packaging/deb/.gitkeep` (dir gone).
- `release.yml`: removed the `Install fpm` step + `dist/agentlinux_*.deb` publish glob;
  updated `.deb` comments to tarball-only. `setup-node` retained (CI tooling + oracle
  still need Node).
- `tests/harness/00-layout.bats`: deleted the HRN-01 `packaging/deb` `@test` (left a note).
- `tests/qemu/boot.sh`: dropped `SKIP_DEB=1 ... --no-deb` from the build-release call.
- `tests/docker/rc-sandbox.sh`: dropped `--no-deb` from the build-one-first hint (Rule 3 —
  flag-surface consistency; an unknown `--no-deb` now exits 64).
- `docs/HARNESS.md` + `AGENTS.md`: sole-channel description; corrected the tarball-payload
  text (musl bin, not the esbuild TS bundle).
- `docs/decisions/006-*`: flagged Superseded-in-part by Phase 58; ADR retained.

## Verification results

- **Two-build reproducibility:** back-to-back `build-release.sh v0.3.6` → byte-identical
  `.sha256` (`8f401a03…`). **Cross-$PWD:** the compiled musl bin is byte-identical across
  a different absolute build path (`6778cf54…` both), and with a pinned `SOURCE_DATE_EPOCH`
  the entire tarball is byte-identical cross-$PWD (`cc448823…` both) — the strongest tier;
  the strip/remap/build-id controls fully defuse Pitfall 6.
- **Payload:** contains `plugin/bin/agentlinux`; does NOT contain `plugin/cli/dist/index.js`;
  `sha256sum -c` round-trips OK.
- **Static bin:** `readelf -d` NEEDED count = 0 (static-PIE, `file`: "static-pie linked, stripped").
- **Version gate:** a throwaway `9.9.9` Cargo.toml bump fails the build with the parity message.
- **Producer:** 0 non-comment pnpm/npm references; `[profile.release] strip` present.
- **DIST-02:** `packaging/deb` gone; zero LIVE (non-comment) fpm/`.deb`/`SKIP_DEB` refs across
  `scripts/ packaging/ .github/ tests/` (6 remaining matches are all supersession comment-history);
  ADR-006 flagged; `tests/harness/00-layout.bats` green 19/19.
- **Workspace gates:** `cargo fmt --all --check` clean; `cargo clippy -p agentlinux --all-targets -- -D warnings`
  no issues; `cargo test --workspace` 338 passed. `agentlinux-core` untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Static-link check false-positive on musl static-PIE**
- **Found during:** Task 1 (first two-build run)
- **Issue:** The plan's suggested `ldd`-based static check treats exit-0 as "dynamic",
  but glibc `ldd` prints "statically linked" and exits **0** for a fully static musl
  bin — so the naive check aborted the build on a correctly-static bin. musl also links
  a static-PIE, which has an ELF dynamic *section* (self-relocation) yet zero NEEDED libs
  and no PT_INTERP.
- **Fix:** replaced with a `readelf -d`/`readelf -l` NEEDED+INTERP check (both must be 0),
  with a `file` "statically\|static-pie" fallback. Documented inline.
- **Files modified:** scripts/build-release.sh (Task 1 commit e2710f0)

**2. [Rule 3 - Blocking] rc-sandbox.sh --no-deb hint would break post-swap**
- **Found during:** Task 2 (grep sweep found a `--no-deb` beyond the 15-item inventory)
- **Issue:** `tests/docker/rc-sandbox.sh:134` printed `SKIP_DEB=1 ... --no-deb` as a
  build-one-first hint; once Task 1 removes the `--no-deb` parse, following that hint
  exits 64.
- **Fix:** dropped `SKIP_DEB=1` + `--no-deb` from the hint to keep the flag surface consistent.
- **Files modified:** tests/docker/rc-sandbox.sh (Task 2 commit f66c41d)

**3. [Rule 2 - Missing accuracy] docs/HARNESS.md tarball-payload description was stale**
- **Found during:** Task 2 (editing the `.deb` doc lines)
- **Issue:** the adjacent §1.4 lines still described the tarball as the esbuild `dist/`
  TS bundle — now false after the musl swap.
- **Fix:** corrected the Release-tarball + Registry-CLI bullets to describe the musl-bin
  payload + the retained-oracle status of `plugin/cli/`.
- **Files modified:** docs/HARNESS.md (Task 2 commit f66c41d)

### Process note (non-deviation)
An accidental `git stash`/`git stash pop` was run during verification (prohibited in a
worktree). The working tree round-tripped cleanly with all edits intact; a pre-existing
`stash@{0}` from a sibling `feat/generalize-detection` worktree was observed and left
untouched (not created or popped by this session). No contamination.

## Deferred Issues

Two pre-existing `tests/harness/run.sh` reds are unrelated to DIST-02 (they reference
files this wave never touched) and are logged to
`.planning/phases/58-distribution-musl-tarball-sole-channel/deferred-items.md`:
- HRN-05: missing `.planning/research/SUMMARY.md` (byte-match test has no source).
- HRN-06: `security-engineer.md` rubric lacks a `0440|sudoers` mention.

The DIST-02-relevant layout test (`00-layout.bats`, HRN-01) is green 19/19.

## Known Stubs

None — this wave produces a working reproducible tarball and removes dead code; no
placeholder/empty-data stubs introduced. The Wave-2 installer/staging handoff (execing
the musl `provision`, retargeting the registry_cli symlink) is intentionally out of scope
for this wave per the plan.

## Self-Check: PASSED

- All modified/created files verified present on disk (11 files + SUMMARY + deferred-items).
- Both deletions (`packaging/deb/postinst.sh`, `packaging/deb/.gitkeep`) confirmed absent.
- Both commits verified in git log: `e2710f0` (Task 1), `f66c41d` (Task 2).
