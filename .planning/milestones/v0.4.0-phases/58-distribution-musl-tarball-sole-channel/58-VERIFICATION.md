---
phase: 58-distribution-musl-tarball-sole-channel
verified: 2026-07-29T09:20:00Z
status: passed
score: 12/12 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: # No — initial verification
  previous_status: none
---

# Phase 58: Distribution — musl Tarball as Sole Channel — Verification Report

**Phase Goal:** Ship the Rust binary through the curl-installer as the single distribution channel — a reproducible x86_64 musl static tarball + `.sha256`, fetched, verified, and installed with **no Node prerequisite for the CLI/provisioner itself** — and remove the legacy optional fpm `.deb` path entirely.
**Verified:** 2026-07-29T09:20:00Z
**Status:** passed — GOAL ACHIEVED
**Re-verification:** No — initial verification
**Phase base:** `0f82919` (Phase 57 transition)

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
| -- | ----- | ------ | -------- |
| 1  | `build-release.sh` produces a REPRODUCIBLE x86_64-musl static tarball + `.sha256` | ✓ VERIFIED | Two back-to-back builds (with forced `touch main.rs` recompile) → BYTE-IDENTICAL sha256 `ca4aed4d…b1a0`. See two-build match below. |
| 2  | Tarball payload is the musl bin, NO TS bundle | ✓ VERIFIED | `tar tzf` payload = `plugin/bin/agentlinux` only; grep for `index.js`/`node_modules`/`.deb` → NONE |
| 3  | Shipped bin is statically linked | ✓ VERIFIED | `file`: static-pie, stripped; `readelf -l` no INTERP; `readelf -d` no NEEDED; `ldd` "statically linked" |
| 4  | curl-installer verifies sha256 BEFORE extract/exec; tamper fails closed | ✓ VERIFIED | install.sh:210 verify → :211 `die`(exit 1) → :221 `tar --extract` → :242 `exec`. Live bats 60 test #3 (tamper → abort, no extraction) GREEN both distros |
| 5  | Installer execs the musl `provision` verb with NO Node bootstrap before the bin | ✓ VERIFIED | install.sh:242 `exec "$exe" provision …`; 61-no-node-prereq #2 (steps 10/20 precede 30-nodejs; no node/npm/pnpm in preamble) GREEN both distros |
| 6  | musl bin is the sole shipped + default-staged `agentlinux` | ✓ VERIFIED | registry_cli.rs stages `bin/agentlinux`, symlink → staged musl bin; live run: `symlinked …/bin/agentlinux`; run.sh default path (no flag) |
| 7  | fpm `.deb` path fully removed | ✓ VERIFIED | `packaging/deb/` gone; no live fpm/deb refs in scripts/packaging/.github/qemu/harness (only doc-supersession comments); ADR-006 flagged not deleted |
| 8  | No Node prerequisite for CLI/provisioner; recipes still get Node | ✓ VERIFIED | 61-no-node-prereq 3/3 GREEN both distros (static-link + pre-Node ordering + recipes-get-Node) |
| 9  | GATE-05 rollback `AGENTLINUX_LEGACY_TS=1` restores Bash+TS, fail-loud | ✓ VERIFIED | Live rollback smoke: symlink → `dist/index.js`, 40-registry-cli 29/29 GREEN; run.sh:304-306 aborts if TS bundle absent (no silent musl fallback) |
| 10 | Full installer bats GREEN on Rust DEFAULT build (both distros) | ✓ VERIFIED | Per-file table below; only pre-existing #29 red (confirmed byte-identical at base) |
| 11 | bats re-points are equivalent behavioral properties, not weakenings | ✓ VERIFIED | Per-hunk equivalence table below — all equivalent-or-stronger |
| 12 | agentlinux-core PURE; Rust change confined to registry_cli.rs + Cargo.toml | ✓ VERIFIED | `git diff 0f82919..HEAD -- agentlinux-core/` empty; only `registry_cli.rs` + `rust/Cargo.toml` (`[profile.release]`) changed |

**Score:** 12/12 truths verified (0 present, behavior-unverified)

### DIST-01 — Reproducibility (the two-build invariant)

```
Build 1: ca4aed4d1401d97eccbad2227d3f82308196ee2e0a39579a6f30e58d6c45b1a0  agentlinux-v0.3.6.tar.gz
Build 2: ca4aed4d1401d97eccbad2227d3f82308196ee2e0a39579a6f30e58d6c45b1a0  agentlinux-v0.3.6.tar.gz
REPRODUCIBLE: IDENTICAL  (forced recompile between runs)
```
Reproducibility controls confirmed present: `[profile.release] strip = true` (rust/Cargo.toml) +
`REPRO_RUSTFLAGS` (`--remap-path-prefix` ×4 + `-C link-arg=-Wl,--build-id=none`) in build-release.sh;
tar recipe `--sort=name --owner=0 --group=0 --numeric-owner --mtime=@$SOURCE_DATE_EPOCH | gzip -n`;
GNU `sha256sum` sidecar. Three-way version lock (package.json + catalog.json + Cargo.toml) present and
fail-loud (tested: `build-release.sh v9.9.9` → "version mismatch … abort").

### DIST-01 — sha256-before-exec gate (critical, NOT weakened)

install.sh ordering (fail-closed): `sha256sum -c` (line 210) → `die` on failure = `exit 1` (line 58, under
`set -euo pipefail`) BEFORE any `tar --extract` (line 221) → `exec "$exe" provision` (line 242). The tamper
case aborts with no extraction. Confirmed by static read AND live bats 60 test #3 on both distros.

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `scripts/build-release.sh` | musl tarball producer, reproducible, DIST-02 sweep | ✓ VERIFIED | 403 lines; builds musl bin, no pnpm; two-build byte-identity confirmed live |
| `rust/Cargo.toml` | `[profile.release] strip=true` | ✓ VERIFIED | 18-line reproducible-profile block added |
| `rust/…/registry_cli.rs` | stages musl bin as default | ✓ VERIFIED | guards re-pointed (bin present+executable), `install -m0755` single bin, symlink → staged bin; core stays pure |
| `packaging/curl-installer/install.sh` | fetch/verify/exec musl provision | ✓ VERIFIED | sha256-before-exec intact; execs `agentlinux provision` |
| `tests/docker/run.sh` | flag-fold + rollback lever | ✓ VERIFIED | forward-flag override conditionals removed; `AGENTLINUX_LEGACY_TS=1` fail-loud both ways |
| `tests/bats/61-no-node-prereq.bats` | real negative assertion | ✓ VERIFIED | 3 genuine checks; `__fail` (not skip) guards against tautology; GREEN both distros |

### bats Re-Point Equivalence (KEY SKEPTICAL CHECK)

| File / hunk | Old assertion | New assertion | Verdict |
| ----------- | ------------- | ------------- | ------- |
| 10-installer INST-02 | sha256 of dist/index.js FIRST LINE (shebang) stable across re-run | sha256 of WHOLE staged musl bin stable across re-run (regime-detected; ts path retained) | EQUIVALENT-OR-STRONGER (whole-artifact vs first-line) |
| 10-installer INST-02 | re-run `bash $INSTALLER` | re-run regime-matched provisioner (`$staged_bin provision` for musl) | EQUIVALENT (same idempotency property, regime-correct) |
| 13-reuse REUSE-03 (:647) | glob `dist/index.js`, `[[ -n ]]` | resolve `agentlinux` on agent login PATH, `[[ -n ]]` else `__fail` | EQUIVALENT (staged CLI resolves + runs no-op) |
| 13-reuse REUSE-03 (:673) | glob `dist/index.js`, `skip` if missing | resolve on PATH, `__fail` (not skip) if missing | STRONGER (skip → hard fail) |
| 40-registry-cli CLI-01 | `--version` == PKG_VERSION (Node shebang chain) | `--version` == PKG_VERSION (musl bin) | EQUIVALENT (comment-only + same assertion) |
| 60-curl-installer fixture + INST-03 | stub `agentlinux-install`, exec Bash entrypoint | stub `agentlinux` accepting `provision`, exec musl provision | EQUIVALENT (exec-handoff sentinel); tamper/main/resolve_version tests UNCHANGED |
| 00-layout HRN-01 | `packaging/deb directory exists` @test | @test DELETED (dir removed by DIST-02) | LEGITIMATE REMOVAL (keeping it = false red) |

No dropped/weakened assertion found. Every re-point preserves an equivalent-or-stronger behavioral property.

### Per-File bats (Rust DEFAULT build, no override)

| File | ubuntu-24.04 | almalinux-9 |
| ---- | ------------ | ----------- |
| 10-installer | ✓ 11/11 | ✓ 11/11 |
| 60-curl-installer | ✓ 4/4 (incl. tamper) | ✓ 4/4 (incl. tamper) |
| 61-no-node-prereq (NEW) | ✓ 3/3 | ✓ 3/3 |
| 23-install-user | ✓ 9/9 | ✓ 9/9 |
| 40-registry-cli | ✓ 29/29 | ✓ 29/29 |
| 13-reuse | 31/32 (only #29) | 31/32 (only #29) |

**#29 red is genuinely pre-existing, not a masked regression:** test `REUSE-03: schema.json declares
compatibility_window field` asserts `.type == "string"`, but the schema declares `["string","null"]`
(an array). The schema is BYTE-IDENTICAL between `0f82919` (base) and HEAD, and the test was NOT touched by
Phase 58. Red on both builds/both distros. Phase-54 origin (per Phase-57 deferred-items).

### GATE-05 Rollback Smoke

`AGENTLINUX_LEGACY_TS=1 run.sh ubuntu-24.04 40-registry-cli` → "run installer (Bash+TS rollback)", symlink →
`/opt/agentlinux/cli/0.3.6/dist/index.js` (TS bundle, NOT musl bin), 29/29 GREEN. Retained oracle
(`plugin/cli/src/`, `package.json`) + Bash entrypoint (`plugin/bin/agentlinux-install`) present + functional
end-to-end. Fail-loud confirmed in code: aborts non-zero if TS bundle absent (no silent musl fallback).

### Requirements Coverage

| Requirement | Description | Status | Evidence |
| ----------- | ----------- | ------ | -------- |
| DIST-01 | Reproducible musl tarball + sha256, verified-before-exec, no Node prereq, sole channel | ✓ SATISFIED | Two-build byte-identity; static bin; sha256-before-exec (read + live tamper test); 61-no-node-prereq 3/3 both distros |
| DIST-02 | fpm `.deb` path removed; ADR-006 flagged | ✓ SATISFIED | `packaging/deb/` gone; no live fpm/deb refs; HRN-01 layout updated + green; ADR-006 superseded-in-part |
| GATE-01 | Green full bats on Rust build, no regression / no newly-skipped | ✓ SATISFIED | All 6 installer files green both distros except pre-existing #29 (byte-identical at base) |
| GATE-05 | master shippable, per-phase rollback | ✓ SATISFIED | `AGENTLINUX_LEGACY_TS=1` restores Bash+TS (live smoke 29/29), fail-loud, oracle+entrypoint retained |

### Rust Purity & Quality Gates

| Check | Result |
| ----- | ------ |
| `agentlinux-core/` diff since base | EMPTY (pure) |
| Rust change scope | `registry_cli.rs` (staging swap) + `rust/Cargo.toml` (`[profile.release]`) only |
| `cargo test --workspace` | ✓ 338 passed |
| `cargo clippy --workspace --all-targets` | ✓ clean (0 warnings/errors) |
| `cargo fmt --all --check` | ✓ clean |

### Anti-Patterns Found

None. All remaining `fpm`/`deb` string matches are doc-supersession comments explicitly marking the DIST-02
removal. No debt markers (TBD/FIXME/XXX), no stubs, no dropped guards in the registry_cli.rs re-point.

### Pre-existing reds (NOT Phase-58 regressions — disclosed & confirmed)

| Red | Location | Confirmed pre-existing |
| --- | -------- | ---------------------- |
| 13-reuse #29 (schema compatibility_window) | tests/bats/13-reuse.bats | Schema byte-identical at base 0f82919; test untouched by P58; red both distros/builds |
| HRN-05 (v0.3.0 SUMMARY.md byte-match) | tests/harness/run.sh | Target files untouched by P58; only harness change is 00-layout HRN-01 deb removal |
| HRN-06 (security-engineer 0440 rubric) | tests/harness/run.sh | security-engineer.md untouched by P58 |

All 19 HRN-01 layout tests GREEN (incl. the ADR-006-still-exists check).

### Gaps Summary

No gaps. Every phase truth is verified with codebase + live-execution evidence. DIST-01's reproducibility
invariant holds under a forced-recompile two-build test; the sha256-before-exec gate is intact and
fail-closed (statically read + behaviorally exercised by the tamper test on both distros); the no-Node-prereq
claim is proven by a genuine (non-tautological) negative-assertion bats file green on both distros; DIST-02's
fpm/.deb removal is complete across code, CI, boot, and harness; every re-pointed bats hunk preserves an
equivalent-or-stronger behavioral property (two are strictly stronger); the GATE-05 rollback lever works
end-to-end and is fail-loud; agentlinux-core is untouched; and the full Rust test/clippy/fmt suite is green.
The only reds anywhere are three disclosed, byte-confirmed pre-existing failures unrelated to Phase 58.

---

_Verified: 2026-07-29T09:20:00Z_
_Verifier: Claude (gsd-verifier)_
