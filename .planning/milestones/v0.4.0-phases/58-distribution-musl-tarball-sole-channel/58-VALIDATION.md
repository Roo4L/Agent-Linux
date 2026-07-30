---
phase: 58
slug: distribution-musl-tarball-sole-channel
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-29
---

# Phase 58 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 58 is a **distribution/packaging** phase: swap the producer (cargo musl,
> not pnpm), the staging target (musl bin, not `dist/index.js`), and the installer
> handoff (exec the musl `provision`, no Node prereq), then delete the fpm/.deb
> path. Primary oracle: the curl-installer + installer `INST-*` bats on the Rust
> build + the release-build gate + the sha256-before-exec contract.

---

## ⚠️ Intentional-observable-change note (unlike Phases 53–57)

DIST-01 deliberately changes the SHIPPED ARTIFACT from a Node/TS bundle to a static
musl binary. So a SMALL, DELIBERATE set of `INST-*` bats that assert TS-bundle-specific
traits **legitimately change** — e.g. the `10-installer` INST-02 shebang assertion (a
static binary has no `#!` line) and any `dist/index.js`-path assertion. This is NOT a
weakening of the spec: it is the spec tracking an intended distribution change. Every
such bats edit MUST be: (a) minimal, (b) justified in the commit as "artifact is now a
binary", (c) still asserting an equivalent behavioral property (the command exists, is
executable, runs, exits right) — NOT deleting the check. The plan-checker + verifier
must confirm no assertion was silently dropped rather than re-pointed. `git diff
tests/bats/` will NOT be empty this phase (it was for 53–57) — that is expected here,
but every hunk must be defensible.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Frameworks** | (1) the curl-installer + installer **bats on the Rust build** (`10-installer`, `60-curl-installer`, `23-install-user`); (2) the release-build gate (`scripts/build-release.sh` produces tarball + `.sha256`); (3) `cargo test --workspace` for any Rust change (registry_cli staging swap) |
| **Config file** | `scripts/build-release.sh`, `packaging/curl-installer/install.sh`, `rust/Cargo.toml` |
| **Quick run command** | `cd rust && . "$HOME/.cargo/env" && cargo test --workspace` |
| **Release build** | `./scripts/build-release.sh vX.Y.Z` → tarball + sibling `.sha256`; verify reproducibility (two builds → identical sha256) |
| **Installer bats** | per-file `./tests/docker/run.sh <distro> 10-installer` / `60-curl-installer` — the musl bin is now the DEFAULT artifact (staging flags folded in), so these exercise Rust without an override |
| **sha256 contract** | the curl-installer verifies the `.sha256` BEFORE executing the tarball (critical rule) |
| **Full suite command** | `cargo test --workspace && cargo clippy --workspace --all-targets -- -D warnings && cargo fmt --all --check` |
| **Estimated runtime** | ~1–2 min cargo; per-file bats ~30–120 s; release build ~1–3 min |

---

## Sampling Rate

- **After every task commit:** `cargo test --workspace` (if Rust touched) + `bash -n` on changed shell
- **After the coupled staging swap:** `10-installer` + `60-curl-installer` green on the Rust build on ubuntu-24.04 AND almalinux-9
- **After the producer change:** `build-release.sh` produces tarball + `.sha256`; a second build yields the SAME sha256 (reproducibility)
- **Before verify:** installer `INST-*` bats green on the Rust build; sha256-verify-before-exec proven; no-Node-prereq proven; fpm/.deb references all gone; ADR-006 flagged
- **Max feedback latency:** ~2 min cargo / ~2 min per bats file

---

## Per-Task Verification Map

> Seeded skeleton from the researcher's 3-wave recommendation — planner refines Task IDs/waves.

| Task ID | Plan | Wave | Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|----------|-----------|-------------------|-------------|--------|
| 58-00-01 | 00 | 0 | DIST-01 | `build-release.sh` produces a reproducible x86_64-musl tarball + `.sha256` (2 builds → same sha256) | build | `./scripts/build-release.sh vX.Y.Z; sha256sum <tarball>` ×2 | ❌ W0 | ⬜ pending |
| 58-00-02 | 00 | 0 | DIST-02 | all 15 fpm/`.deb` references deleted (packaging/deb, build-release branch, release.yml, HRN-01, boot.sh, docs); ADR-006 flagged | grep | `! grep -rn 'fpm\|\.deb\|dpkg-deb' scripts/ packaging/ .github/` (minus doc-history) | ❌ W0 | ⬜ pending |
| 58-01-01 | 01 | 1 | DIST-01 | staging swap: `registry_cli.rs` symlinks the musl bin + `install.sh` execs it + the coupled `60-curl-installer` fixture + `10-installer` INST-02 assertion move in lockstep | bats | `... run.sh {ubuntu-24.04,almalinux-9} 10-installer 60-curl-installer` | ❌ W0 | ⬜ pending |
| 58-01-02 | 01 | 1 | DIST-01 | the CLI/provisioner runs with NO Node prerequisite (static bin runs pre-Node) | bats/manual | installer run + `readelf -d` static check / provision pre-Node | ❌ W0 | ⬜ pending |
| 58-02-01 | 02 | 2 | GATE-05 | fold the forward harness flags into the default + keep ONE inverse `AGENTLINUX_LEGACY_TS=1` rollback lever | bats | `... run.sh ubuntu-24.04 10-installer` (default = Rust) + legacy lever smoke | ❌ W0 | ⬜ pending |
| 58-02-02 | 02 | 2 | GATE-01 | full installer bats green on the Rust build; parity/deletion closeout | bats | per-file 10/23/60 × {ubuntu-24.04, almalinux-9} | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `build-release.sh`: build the static musl bin (`cargo build --release --target x86_64-unknown-linux-musl`), assemble the tarball (bin + catalog + the ~25 Bash recipes + provisioner data), emit sibling `.sha256`; reproducible (sorted entries, zeroed mtimes, pinned toolchain) → stable sha256 across builds. DROP the fpm/.deb branch.
- [ ] DIST-02: delete `packaging/deb/` + the `.deb` postinst bridge + the `build-release.sh` `--deb`/fpm branch + `release.yml`'s `.deb` job/step/glob + the HRN-01 layout test's `.deb` + `boot.sh --no-deb` + the doc references; flag ADR-006 for the tarball-only revision (curl-primary + mandatory `.sha256` consequences survive).

*The reproducible-tar recipe + sha256-verify gate + `provision` verb already exist — this is wiring + deletion, not construction.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live-CDN tag push + curl-pipe real install | DIST-01 | The first release tag push IS the shipping event | Deferred — Phase 59 QEMU release gate + the release.yml gates |
| Full 4-distro + QEMU release gate | GATE-01 (full) | Docker OOM; full matrix + QEMU is Phase 59 | Per-file installer bats on ubuntu-24.04 + almalinux-9 as the in-phase floor |
| Reproducible-build determinism across machines | DIST-01 | Cross-machine reproducibility needs a clean second host | In-phase: two builds on THIS host → same sha256; cross-host → note |

---

## Validation Sign-Off

- [ ] All tasks have automated verify (build/bats/cargo) or Wave 0 deps
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Reproducible tarball: two builds → identical `.sha256`
- [ ] curl-installer verifies `.sha256` BEFORE executing (critical rule) — asserted
- [ ] The musl bin is the default staged `agentlinux`; installer bats green on the Rust build (both distros)
- [ ] No-Node-prereq for the CLI/provisioner proven (static-bin + pre-Node run)
- [ ] Every changed `INST-*` bats hunk is a re-point (artifact-is-a-binary), NOT a dropped assertion — each justified
- [ ] All fpm/.deb references gone; ADR-006 flagged; `plugin/cli/` (TS) retained as the parity oracle (delete at Phase-59 cutover)
- [ ] GATE-05 rollback lever (`AGENTLINUX_LEGACY_TS=1`) works; `agentlinux-core` untouched
- [ ] `nyquist_compliant: true` set

**Approval:** pending
