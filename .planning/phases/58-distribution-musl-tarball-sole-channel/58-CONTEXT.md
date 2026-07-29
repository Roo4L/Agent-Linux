# Phase 58: Distribution — musl Tarball as Sole Channel - Context

**Gathered:** 2026-07-29
**Status:** Ready for research
**Mode:** Smart-discuss infrastructure phase (distribution/packaging; the observable change is intentional — the shipped artifact becomes the musl binary, and the fpm .deb path is removed). Codebase scout below.

<domain>
## Phase Boundary

Ship the Rust binary through the curl-installer as the SINGLE distribution channel —
a reproducible x86_64 musl static tarball + `.sha256`, fetched/verified/installed with
**no Node prerequisite for the CLI/provisioner itself** — and remove the legacy optional
fpm `.deb` path entirely. This is where the **Q1-deferred musl-artifact swap** (Phase 57)
lands: the provisioner staging switches from the TS bundle to the musl binary.

- **DIST-01** — `scripts/build-release.sh` produces a reproducible x86_64 musl static
  tarball + `.sha256`; the curl-installer (`packaging/curl-installer/install.sh`) fetches
  it, verifies the sha256 BEFORE executing, and installs it — with NO Node prerequisite
  for the CLI/provisioner itself; this is the SOLE distribution channel.
- **DIST-02** — the legacy optional fpm `.deb` path is removed: `packaging/deb/`, the
  `build-release.sh` `--deb`/`fpm` branch, and the `.deb` postinst bridge deleted;
  ADR-006 flagged for an update to the tarball-only channel.
- **GATE-01 / GATE-05** — full bats green (incl. the curl-installer `INST-*` tests) on
  the Rust build, no regression / no newly-skipped; master shippable; per-phase rollback.

The chicken-and-egg is gone: the static musl binary runs pre-Node, so the CLI +
provisioner ship with no Node prerequisite. (Node is still provisioned FOR the agent
recipes — that's `nodejs.rs` — but the AgentLinux binary itself needs none.)

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (infrastructure/packaging phase)
Parity pinned by the curl-installer `INST-*` bats + the release-build gate. Recommended
shape below; not binding.

### The Q1 musl-artifact swap (the crux of this phase)
Phase 56/57 kept staging the TS bundle (`dist/index.js`) as the `agentlinux` command,
with the Rust bin exercised only behind `AGENTLINUX_STAGE_RUST_CLI` / `AGENTLINUX_PROVISION_RUST`
test flags. Phase 58 makes the **musl binary THE shipped + staged artifact** by default:
`registry_cli.rs` (provisioner staging) + `build-release.sh` (tarball contents) + the
curl-installer stage the musl binary, and `agentlinux <verb>` IS the Rust binary in
production. The test flags collapse into the default path (the bats no longer need the
override to exercise Rust — Rust IS the build).

### Recommended (researcher + planner to finalize)
- `build-release.sh`: build the static musl bin (`cargo build --release --target
  x86_64-unknown-linux-musl`), assemble the tarball (the bin + the catalog + recipes +
  provisioner data the recipes still need), emit the sibling `.sha256`. DROP the fpm/.deb
  branch. Reproducibility: pin the toolchain, sort tar entries, strip mtimes.
- `curl-installer/install.sh`: fetch the tarball + `.sha256`, VERIFY sha256 before
  executing (the critical-rule: never run an unverified tarball), unpack, run the musl
  `agentlinux provision`. No Node bootstrap needed before the binary runs.
- DELETE `packaging/deb/` + the `.deb` branch in `build-release.sh` + `release.yml`'s
  `.deb` job; flag ADR-006 (curl-primary + optional .deb) for a tarball-only revision.
- The `AGENTLINUX_STAGE_RUST_CLI`/`AGENTLINUX_PROVISION_RUST` harness flags: fold into
  the default (Rust is now the artifact) OR keep as a no-op/rollback lever — research to
  weigh against GATE-05 (a broken Phase-58 must still roll back to the Bash+TS build).

### The irreducible boundary (survives the rewrite)
The ~25 per-agent Bash recipes stay in the tarball (they still npm/apt/curl-install the
agents). Node is still provisioned for THEM. The TS source (`plugin/cli/`) likely STAYS
in the repo as the parity oracle until the Phase-59 cutover — Phase 58 stops SHIPPING it,
it does not necessarily delete it (research/planner to decide; the bats parity oracle may
still reference it).

</decisions>

<code_context>
## Existing Code Insights (from scout)

### Port/change targets
- `scripts/build-release.sh` (361 LOC) — the release builder; has the fpm/.deb branch
  (grep-confirmed) to remove + the tarball assembly to point at the musl bin.
- `packaging/curl-installer/install.sh` (232 LOC) — the curl-pipe installer; fetches +
  sha256-verifies + installs. Must stage the musl bin, no Node prereq.
- `packaging/deb/postinst.sh` (1.7K) — the `.deb` postinst bridge → DELETE (DIST-02).
- `.github/workflows/release.yml` — has `.deb` references → drop the `.deb` gate/job.
- `rust/crates/agentlinux/src/provision/registry_cli.rs` — the provisioner staging step
  (Phase 57 stages the TS bundle per Q1); Phase 58 swaps it to the musl bin.

### Acceptance oracle
- The curl-installer `INST-*` bats (`tests/bats/10-installer.bats`, `60-curl-installer.bats`
  if present, `23-install-user.bats`), the release-build gate (`release.yml` gates 2/3/4),
  + the sha256-verify contract. Every release tarball ships with a sibling `.sha256` the
  installer verifies BEFORE executing (a project critical rule).
- Docker OOM → per-file bats; the musl bin is now the DEFAULT build (the staging flags
  fold in), so the bats exercise Rust without an override.

</code_context>

<specifics>
## Specific Ideas

- Smaller phase than 56/57 — DIST-01/02 are 2 requirements, mostly Bash packaging + the
  staging swap. But the musl-swap is a real observable change (the shipped `agentlinux`
  becomes the Rust bin), so the full curl-installer bats must be green on it.
- Reproducibility matters for the tarball (a `.sha256` that's stable across builds).
- master shippable; branch `worktree-stack-revisiting`; recipes stay Bash; per-phase
  rollback (a broken Phase-58 must revert to the Bash+TS distribution — GATE-05).
- CRITICAL RULE: the curl-installer must verify the `.sha256` before executing the tarball.

</specifics>

<deferred>
## Deferred Ideas

- Full 4-distro Docker + QEMU release gate + AGT-02 self-update against the live CDN →
  Phase 59 (the final validation gate).
- The final TS-source removal + the Bash-provisioner/reuse-map deletion (the PROV-02
  Phase-59-cutover residual) → the Phase-59 cutover, once full validation is green.

</deferred>
