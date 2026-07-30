---
phase: 57-provisioner-port-logic-consolidation
plan: 01
subsystem: provisioner-port
tags: [rust, provisioner, idempotency, distro-detect, pkg-abstraction, prov-02, gate]
requires: [phase-56-bin, agentlinux-core-pure-gates]
provides: [sysio, distro, pkg, provision-rust-seam, prov-02-gate]
affects: [wave-1-agent_user, wave-2-sudoers, wave-3-nodejs, wave-4-path_wiring, wave-5-consolidation]
tech-stack:
  added: []
  patterns: [same-dir-atomic-rename, awk-strip-marker-emit-order, match-family-verb, argv-builder-testability, fail-loud-staging-seam]
key-files:
  created:
    - rust/crates/agentlinux/src/sysio.rs
    - rust/crates/agentlinux/src/distro.rs
    - rust/crates/agentlinux/src/pkg.rs
    - scripts/check-no-bash-canonical-map.sh
  modified:
    - rust/crates/agentlinux/src/main.rs
    - tests/docker/run.sh
decisions:
  - "std::os::unix::fs::chown for ensure_dir (nix `fs` feature not enabled; only `user` for name→uid/gid) — no new crate features"
  - "PkgCmd{env,argv} struct as the testable ARGV builder for every shell-out pkg verb (asserted without live apt/dnf)"
  - "PROV-02 gate is a green-from-Wave-0 regression guard (one def, sanctioned file), NOT an armed-to-fail gate (plan-check B-1)"
  - "run.sh provisioner seam builds+stages the musl bin at a root-owned path distinct from the RUST-03 reuse path so the two seams never collide"
metrics:
  duration_min: 40
  completed: 2026-07-28
status: complete
---

# Phase 57 Plan 01: Provisioner Systems-I/O Foundation + Staging Seam + PROV-02 Gate Summary

Wave 0 of Phase 57: ported the pre-Node Bash provisioner's systems-I/O floor to
the Rust `agentlinux` bin byte-faithfully (`sysio.rs` six idempotency primitives,
`distro.rs` exact-ID detect, `pkg.rs` apt↔dnf verb set), added the
`AGENTLINUX_PROVISION_RUST=1` fail-loud staging seam to `tests/docker/run.sh`, and
committed the PROV-02 single-source grep gate — all green, unblocking Waves 1-5.

## What was built

- **`sysio.rs`** (PROV-01) — the six `idempotency.sh` primitives with
  byte-identical observable output: `write_file_atomic` (same-dir tmpfile +
  atomic `fs::rename`, mode-before-rename, RAII `TmpGuard` mirroring the Bash
  RETURN trap), `ensure_line_in_file` (`grep -Fxq` whole-line literal),
  `ensure_marker_block` (awk-strip + Top/Bottom emit order, exact
  `# >>> {tag} begin >>>` / `# <<< {tag} end <<<` markers, written via
  `write_file_atomic(0o644)`), `ensure_user` (id-gated useradd argv), `ensure_dir`
  (create-or-reassert mode+owner drift correction), `visudo_validate`.
- **`distro.rs`** (PROV-03) — `Family{Debian,Rhel}` + `detect_distro(path,
  DetectEnv)` exact-ID match, both bats seams (`AGENTLINUX_OS_RELEASE_PATH`,
  `AGENTLINUX_SKIP_DISTRO_CHECK` + `AGENTLINUX_DISTRO_FAMILY` override).
- **`pkg.rs`** (PROV-03) — 9 apt↔dnf verbs, each a single `match family` (Pattern
  2, no inline family-`if` at any call site), ARGV factored into pure builders;
  rhel `nodesource_prereqs` installs ONLY ca-certificates (never curl, Pitfall
  5); `nodesource_repo_paths` byte-identical to `pkg.sh:144-160`;
  `nodesource_module_reset` rhel-only (Pitfall 4); `locale_ensure` C.UTF-8-only
  (fail closed), rhel writes `/etc/locale.conf` via `sysio::write_file_atomic`.
- **`tests/docker/run.sh`** — `AGENTLINUX_PROVISION_RUST=1` seam runs
  `agentlinux provision --user agent --yes` (root, via `require_root`) instead of
  the Bash entrypoint; fail-loud when the musl bin is absent (never a false-green
  Bash fallback); flag-unset keeps the Bash entrypoint authoritative.
- **`scripts/check-no-bash-canonical-map.sh`** — PROV-02 single-source gate:
  exactly one Bash canonical-map definition, only in the retained
  `plugin/lib/reuse/agents.sh`; green from Wave 0 with a documented teeth
  self-test.

## Verification (exact output per task)

**Task 1** — `cargo test -p agentlinux sysio`: `17 passed, 107 filtered out`.
Acceptance: all six primitives present, marker strings byte-exact (`# >>> ` /
`# <<< `), tmpfile-in-parent + no-residual asserted, fmt clean.

**Task 2** — `cargo test -p agentlinux distro`: `14 passed`;
`cargo test -p agentlinux pkg`: `12 passed`. (The plan's `cargo test … 'distro'
'pkg'` one-liner passes two TESTNAME filters, which cargo rejects — run
separately per the substring-filter semantics; see Deviations.) Acceptance:
detect_distro accept/reject rows + both seams; rhel prereqs argv contains
ca-certificates and NOT curl; repo paths byte-identical; `locale_ensure(_,
"en_US.UTF-8")` → Err; `grep -c 'if.*family.*==\|if.*Family::' pkg.rs` = 0
(Pattern 2); fmt + clippy clean.

**Task 3** — verify one-liner output:
```
OK: exactly one Bash canonical-map definition, in plugin/lib/reuse/agents.sh (PROV-02 single-source)
PROV-02-SINGLE-SOURCE-GATE-GREEN
```
`bash -n` both scripts pass; `AGENTLINUX_PROVISION_RUST` + `refusing`/`false-green`
present; gate exits 0. Teeth self-test verified live: injecting a second
`declare -gA REUSE_AGENT_CANONICAL_PATHS=` into a second plugin/ file → exit 1
(`FAIL: … definition outside the sanctioned file`); removing it → exit 0. Diff
scope limited to `tests/docker/run.sh` + the gate script (plugin/ untouched).

**Overall** — `cargo test --workspace`: `121 passed` (core) + `150 passed`
(bin); `cargo clippy --workspace --all-targets -- -D warnings`: clean;
`cargo fmt --all --check`: clean. `nix` pinned `0.31.3` (no regression, no new
crates). `agentlinux-core` had zero changes across all three commits (pure core
stays pure).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `nix::unistd::chown` gated behind the `fs` feature**
- **Found during:** Task 1 (first `cargo test -p agentlinux sysio`)
- **Issue:** `nix::unistd::chown` requires nix's `fs` feature, which is NOT
  enabled (only `signal`/`process`/`user` are). The plan explicitly names
  `std::os::unix::fs::chown` as an acceptable syscall alternative and forbids new
  crate features.
- **Fix:** Used `std::os::unix::fs::chown(path, Some(uid), Some(gid))` with raw
  ids resolved by name via `nix::unistd::{User,Group}::from_name` (the `user`
  feature). No `Cargo.toml` change.
- **Files modified:** rust/crates/agentlinux/src/sysio.rs
- **Commit:** dc3e7aa

**2. [Rule 3 - Blocking] `unwrap_or_else` arity on `std::env::var` Result**
- **Found during:** Task 2 (first `cargo test -p agentlinux distro`)
- **Issue:** `std::env::var(...).map(...).unwrap_or_else(|| ...)` — `env::var`
  returns `Result`, so `unwrap_or_else` needs a 1-arg closure.
- **Fix:** `.unwrap_or_else(|_| PathBuf::from("/etc/os-release"))`.
- **Files modified:** rust/crates/agentlinux/src/distro.rs
- **Commit:** 90c11dd

### Verify-command note (not a code deviation)

The plan's Task-2 verify `cargo test -p agentlinux 'distro' 'pkg'` and the
overall `cargo test -p agentlinux distro pkg` pass TWO positional TESTNAME
filters; `cargo test` accepts only one and errors "unexpected argument 'pkg'".
Ran as two separate substring-filter invocations (`… distro`, `… pkg`), which is
the equivalent coverage. No behavior change; noted so the verifier reproduces it.

## Design decisions

- `PkgCmd { env, argv }` is the single testable command shape every shell-out
  pkg verb builds, so every `<behavior>` argv row is asserted without spawning
  live apt/dnf (the live spawn wraps the same builder).
- The `run.sh` provisioner seam stages the musl bin at a ROOT-owned path
  (`/usr/local/lib/agentlinux/provision/agentlinux`) distinct from the
  agent-owned RUST-03 reuse path, and factors host-build into a shared
  `host_build_musl()` so the flag-unset path is byte-unchanged.
- The PROV-02 gate filters comment lines FIRST (a doc mention of the symbol is
  never a hit) and checks both "no definition outside the sanctioned file" AND
  "exactly one definition inside it".

## Known Stubs

None. Every artifact is fully wired for its Wave-0 role; the `provision`
subcommand the seam invokes lands in Wave 5 (by design — the seam FAILS LOUD
until then, never false-greens).

## Self-Check: PASSED

- Created files exist: `sysio.rs`, `distro.rs`, `pkg.rs`,
  `scripts/check-no-bash-canonical-map.sh` — all present.
- Commits exist: dc3e7aa (Task 1), 90c11dd (Task 2), f2eadc6 (Task 3).
