# Phase 58: Distribution — musl Tarball as Sole Channel - Research

**Researched:** 2026-07-29
**Domain:** Release packaging / distribution (reproducible tarball, sha256 trust chain, curl-pipe-bash installer, the Q1 musl-artifact staging swap)
**Confidence:** HIGH (every claim below is grounded in a `file:line` read this session; no external package research needed — this phase installs no new dependencies)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **DIST-01** — `scripts/build-release.sh` produces a reproducible x86_64 musl static tarball + `.sha256`; the curl-installer (`packaging/curl-installer/install.sh`) fetches it, verifies the sha256 BEFORE executing, and installs it — with **NO Node prerequisite for the CLI/provisioner itself**; this is the SOLE distribution channel.
- **DIST-02** — the legacy optional fpm `.deb` path is removed: `packaging/deb/`, the `build-release.sh` `--deb`/`fpm` branch, and the `.deb` postinst bridge deleted; ADR-006 flagged for an update to the tarball-only channel.
- **GATE-01 / GATE-05** — full bats green (incl. the curl-installer `INST-*` tests) on the Rust build, no regression / no newly-skipped; master shippable; per-phase rollback.
- **The Q1 musl-artifact swap (crux):** the musl binary becomes THE shipped + staged artifact by default. `registry_cli.rs` (provisioner staging) + `build-release.sh` (tarball contents) + the curl-installer stage the musl binary, and `agentlinux <verb>` IS the Rust binary in production.
- **CRITICAL RULE:** the curl-installer must verify the `.sha256` before executing the tarball.
- **The irreducible boundary (survives the rewrite):** the ~25 per-agent Bash recipes stay in the tarball. Node is still provisioned for THEM (`nodejs.rs`), not for the AgentLinux binary itself.

### Claude's Discretion (infrastructure/packaging phase)
Parity pinned by the curl-installer `INST-*` bats + the release-build gate. Recommended shape is not binding:
- `build-release.sh`: build the static musl bin, assemble the tarball, emit the sibling `.sha256`, DROP the fpm/.deb branch. Reproducibility: pin the toolchain, sort tar entries, strip mtimes.
- `curl-installer/install.sh`: fetch tarball + `.sha256`, VERIFY before executing, unpack, run the musl `agentlinux provision`. No Node bootstrap before the binary runs.
- DELETE `packaging/deb/` + the `.deb` branch in `build-release.sh` + `release.yml`'s `.deb` job; flag ADR-006 for a tarball-only revision.
- The `AGENTLINUX_STAGE_RUST_CLI`/`AGENTLINUX_PROVISION_RUST` harness flags: fold into the default (Rust is now the artifact) OR keep as a no-op/rollback lever — research to weigh against GATE-05.
- The TS source (`plugin/cli/`) likely STAYS in the repo as the parity oracle until the Phase-59 cutover — Phase 58 stops SHIPPING it, it does not necessarily delete it.

### Deferred Ideas (OUT OF SCOPE)
- Full 4-distro Docker + QEMU release gate + AGT-02 self-update against the live CDN → **Phase 59**.
- The final TS-source removal + the Bash-provisioner/reuse-map deletion (the PROV-02 Phase-59-cutover residual) → **Phase 59 cutover**, once full validation is green.
- Per-arch packaging + arch-detecting installer (ARM) → ARCH-01 (v2), permanently out of scope this milestone.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DIST-01 | Reproducible x86_64 musl static tarball + `.sha256`; curl-installer fetches/verifies/installs; NO Node prereq for the CLI/provisioner itself; sole channel. | §build-release.sh map (tarball assembly, SOURCE_DATE_EPOCH recipe), §curl-installer map (sha256-before-exec), §musl swap (the `no-Node` proof), §Architecture Patterns 1-3 |
| DIST-02 | Remove the fpm `.deb` path — `packaging/deb/`, the `build-release.sh` `--deb`/`fpm` branch, the postinst bridge; flag ADR-006. | §DIST-02 Deletion Inventory (every reference enumerated with `file:line`) |
| GATE-01 | Full bats green (incl. curl-installer `INST-*`) on the Rust build; no regression / no newly-skipped. | §Acceptance Oracle, §No-Node-Prereq Proof |
| GATE-05 | master shippable; per-phase rollback to the Bash+TS build. | §The Rollback Lever (keep-flag-vs-remove analysis), §Risks |
</phase_requirements>

## Summary

Phase 58 is a **packaging + staging-swap** phase, not a logic phase. Three artifacts change and one directory is deleted. `scripts/build-release.sh:1-361` today builds the **TS bundle** (`pnpm install --frozen-lockfile && pnpm run build && pnpm prune --prod` at lines 207-225), tars `plugin/` reproducibly (lines 269-278), emits a GNU-`sha256sum` sidecar (lines 287-290), and — optionally — wraps the tarball in an fpm `.deb` (lines 336-356). Phase 58 replaces the TS-bundle build with `cargo build --release --target x86_64-unknown-linux-musl`, ships the musl bin **plus** the catalog and the ~25 Bash recipes in the tarball, keeps the reproducible-tar recipe (which already gives a stable `.sha256`), and **deletes the fpm branch entirely** (DIST-02).

The **crux** is the Q1-deferred staging swap. `provision/registry_cli.rs:9-14` documents the locked Phase-57 decision: the provisioner keeps symlinking the TS bundle's `dist/index.js` (registry_cli.rs:85, :122, :157), and the harness re-points that symlink at the Rust bin only behind `AGENTLINUX_STAGE_RUST_CLI=1` (run.sh:341-395). Phase 58 makes the musl binary the default staged `agentlinux` command: `registry_cli.rs` stages the bin (not `dist/index.js`), the curl-installer execs the musl bin's `provision` (main.rs:188 already routes `Command::Provision` through `require_root`), and the two harness override flags collapse into the default path. Node stops being a prerequisite to *run* AgentLinux — it is provisioned only *for the agent recipes* (`nodejs.rs`, unchanged), which closes the chicken-and-egg DIST-01 calls out.

The acceptance oracle is the existing bats suite — chiefly `60-curl-installer.bats` (INST-03 sha256-before-exec + happy-path + partial-download safety), `10-installer.bats` (INST-01/02/05 + CAT-05), and `23-install-user.bats` (CLI-01/05). The reproducible-tar and sha256 machinery is already proven; the risk surface is entirely in the **staging swap** (does the installer still hand off cleanly once the artifact is a static bin instead of a Node script) and the **GATE-05 rollback lever**.

**Primary recommendation:** Do the swap in three waves — (1) `build-release.sh` musl tarball + fpm-branch deletion + `release.yml`/harness meta-test/`docs` deletions; (2) `registry_cli.rs` stages the musl bin as the default `agentlinux` command + curl-installer execs the musl `provision` with no Node prereq; (3) fold the two harness flags into the default, keep a single `AGENTLINUX_LEGACY_TS=1` inverse lever for GATE-05 rollback, full-suite bats closeout. Keep `plugin/cli/` (TS source) in the repo as the parity oracle — delete at the Phase-59 cutover.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Build the release tarball | Build/CI (`build-release.sh` + `release.yml`) | — | Reproducibility + sha256 are a build-time contract; the installer only consumes the output |
| Fetch + verify + unpack | Installer (`curl-installer/install.sh`) | — | The sha256-before-exec trust gate lives at the download boundary (install.sh:204-209) |
| Stage `agentlinux` onto PATH | Provisioner (`registry_cli.rs`) | Build (produces the bin the provisioner stages) | The provisioner is the numeric-dispatch-50 step that symlinks the command (registry_cli.rs:64-182) |
| Run the pre-Node provisioner | Rust binary (`main.rs`→`provision`) | Bash entrypoint (rollback) | The static musl bin runs before Node exists — that is the whole point of the rewrite |
| Provision Node FOR the recipes | Provisioner (`nodejs.rs`) | — | Node is a dependency of the ~25 Bash recipes, NOT of the AgentLinux binary — unchanged this phase |
| Rollback to Bash+TS | Build + Harness (GATE-05 lever) | — | A broken Phase-58 must revert to the TS-bundle distribution |

## Standard Stack

No new external packages. This phase is Bash + an existing Rust toolchain target. The relevant "stack" is the toolchain and flags already in the repo:

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `cargo` + `x86_64-unknown-linux-musl` target | pinned by `rust/rust-toolchain.toml` (verify — see Env Availability) | Build the fully-static `agentlinux` bin (RUST-01, already green) | musl → no dynamic libc → runs pre-Node; `ldd` reports "not a dynamic executable" (RUST-01) |
| GNU `tar` | system | Reproducible archive (`--sort=name --owner=0 --group=0 --numeric-owner --mtime=@$epoch`) | Already the proven recipe at build-release.sh:269-278 |
| `gzip -n` | system | Deterministic gzip frame (no embedded mtime/filename) | build-release.sh:278 — the subtle reproducibility fix already documented |
| `sha256sum` (coreutils) | system | The `.sha256` sidecar + `-c` round-trip verify | build-release.sh:287-290; install.sh:207 |
| `curl -fsSL` | system | Fetch tarball + sidecar over HTTPS | install.sh:183-187, mandatory `-f` (Pitfall 2) |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `jq` | Three-way version lock in build-release.sh:128-150 | Still needed if the version lock is retained (see Open Questions — the lock reads `package.json`, which becomes ambiguous once TS stops shipping) |
| `head`/`od` | gzip magic-byte check (install.sh:198-202) | Keep verbatim — a static-bin tarball is still gzip; the check is artifact-agnostic |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `cargo build --target musl` inline in build-release.sh | Pre-built bin copied from a CI cache | Inline build is simpler + reproducible-by-toolchain-pin; CI-cache adds a staleness class. run.sh:256-275 `host_build_musl` already does inline-build-always (never early-returns on a stale bin) — mirror that discipline. |
| Keep the fpm `.deb` as SKIP-by-default | Delete entirely (DIST-02) | DIST-02 mandates deletion — the `.deb` was optional + unused; keeping dead code invites drift. |
| curl-installer execs the Bash `agentlinux-install` entrypoint | curl-installer execs the musl bin's `provision` directly | Bash entrypoint sources the Bash provisioners (superseded by Rust in Phase 57); execing the musl `provision` is the clean no-Node path. See §Architecture Pattern 2 + Open Questions. |

**No `npm install` / `pnpm` in the shipped path** once the swap lands — that is the DIST-01 "no Node prerequisite" win. (`pnpm` stays in the repo only to rebuild the TS parity oracle for the bats.)

## Package Legitimacy Audit

> Not applicable — this phase installs no external packages. It removes a packaging path (fpm/.deb) and swaps a build target. The `x86_64-unknown-linux-musl` target and `cargo`/`tar`/`gzip`/`sha256sum`/`curl` are all pre-existing, already exercised by the green Phase-53..57 CI. No registry lookup required.

## Architecture Patterns

### System Architecture Diagram

```
  RELEASE (build-release.sh + release.yml)
  ───────────────────────────────────────
  git tag vX.Y.Z
      │
      ▼
  [version gate] ── jq: TAG == package.json.version == catalog.json.version   (build-release.sh:128-150)
      │                 ⚠ package.json is the TS source's — see Open Questions Q3
      ▼
  cargo build --release --target x86_64-unknown-linux-musl   ◄── REPLACES pnpm build (lines 207-225)
      │        (produces rust/target/.../release/agentlinux — static, ldd: not a dynamic executable)
      ▼
  assemble tarball payload:
      ├── agentlinux            (the musl bin)          ◄── NEW
      ├── catalog/catalog.json + agents/*/install.sh    (the ~25 Bash recipes — UNCHANGED)
      └── (provisioner data the recipes still need)
      │
      ▼
  tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@$SOURCE_DATE_EPOCH | gzip -n   (lines 269-278)
      │        → reproducible bytes → STABLE .sha256
      ▼
  sha256sum > agentlinux-vX.Y.Z.tar.gz.sha256   (lines 287-290)
      │
      ▼
  publish: tarball + .sha256 + catalog snapshot + VERSION   (release.yml:352-357)
      ✗ NO agentlinux_*.deb                                 ◄── DELETED (DIST-02)

  INSTALL (curl-installer/install.sh)
  ────────────────────────────────────
  curl -fsSL .../install.sh | sudo bash
      │
      ▼
  main(){...}; main "$@"   (partial-download safety, install.sh:144-232)
      │
      ├─ check_root + detect_supported_distro   (install.sh:62-109)
      ├─ resolve_version (first-hop redirect)   (install.sh:120-142)
      ├─ curl tarball + .sha256                 (install.sh:183-187)
      ├─ gzip magic check                       (install.sh:198-202)
      ├─ ★ sha256sum -c  BEFORE extraction ★    (install.sh:204-209)   ◄── CRITICAL GATE (unchanged)
      ├─ tar --extract                          (install.sh:218-222)
      └─ exec <the musl bin> provision          ◄── REPLACES exec plugin/bin/agentlinux-install (install.sh:224-229)
                │        NO Node needed to reach or run this
                ▼
         provision (main.rs:188 → require_root → 10→20→30→40→50 steps)
                └─ 30-nodejs.rs provisions Node FOR THE RECIPES only
```

### Recommended Project Structure (tarball payload)
```
agentlinux-vX.Y.Z.tar.gz
├── agentlinux                    # the static musl bin (was: plugin/cli/dist/index.js + node_modules/)
├── catalog/
│   ├── catalog.json              # unchanged; CAT-05 byte-stable contract
│   └── agents/<name>/install.sh  # the ~25 Bash recipes — UNCHANGED (the irreducible boundary)
└── (any provisioner data files the recipes read)
```
Open decision: whether the tarball keeps the `plugin/` top-level prefix (install.sh:224 currently expects `${inst}/plugin/bin/agentlinux-install`) or flattens. See Open Questions Q1.

### Pattern 1: Reproducible static-bin tarball (stable `.sha256`)
**What:** The existing tar recipe already produces byte-identical output across runs; swapping the payload from a Node bundle to a single static bin *simplifies* reproducibility (a compiled bin is one deterministic file vs. a `node_modules/` tree whose pnpm bookkeeping files carry wall-clock timestamps — build-release.sh:259-266 excludes `.modules.yaml` / `.pnpm-workspace-state-v1.json` precisely for this reason; those excludes become dead once TS stops shipping).
**When to use:** Every release build.
**Determinism checklist (carry forward verbatim from build-release.sh:242-278):**
- `--sort=name` — deterministic entry order `[VERIFIED: build-release.sh:270]`
- `--owner=0 --group=0 --numeric-owner` — erase builder uid/gid `[VERIFIED: build-release.sh:271]`
- `--mtime=@$SOURCE_DATE_EPOCH` (default `git log -1 --pretty=%ct HEAD`) — pin mtimes `[VERIFIED: build-release.sh:238, :272]`
- `--pax-option=...delete=atime,delete=ctime` — strip pax jitter `[VERIFIED: build-release.sh:273]`
- `gzip -n` — no gzip-header timestamp `[VERIFIED: build-release.sh:278]`
- **NEW for a compiled bin:** the musl bin itself must be reproducible → pin the toolchain (`rust-toolchain.toml`), and consider stripping the binary (`strip` or `cargo` profile `strip = true`) so build-host-path debug metadata does not leak non-determinism. `[ASSUMED — verify the current profile]`

### Pattern 2: curl-installer execs the musl `provision` (the no-Node handoff)
**What:** Today install.sh:224-229 execs the Bash `plugin/bin/agentlinux-install`, which sources the Bash provisioners and *derives its version from `plugin/cli/package.json` via sed* (agentlinux-install:29-37) — i.e. it structurally assumes the TS bundle is present. Phase 58 points the installer's `exec` at the musl bin's `provision` verb. `main.rs:104-141` already dispatches `provision` pre-clap-safe through `require_root` (main.rs:188), so `<bin> provision --user agent --yes` is the entrypoint — exactly what run.sh:308 already invokes under `AGENTLINUX_PROVISION_RUST=1`.
**When to use:** The install handoff.
**Why it removes the Node prereq:** The musl bin is static (RUST-01: `ldd` → "not a dynamic executable"); reaching and running `provision` requires no interpreter. Node is provisioned *inside* `provision` (`nodejs.rs`) for the recipes only.
**Reference:** run.sh:289-308 is the working proof-of-concept of this exact invocation shape.

### Pattern 3: The staging swap in `registry_cli.rs`
**What:** registry_cli.rs stages `agentlinux` onto the install user's PATH. Today (Phase-57-locked, registry_cli.rs:9-14) it symlinks `.../cli/<ver>/dist/index.js` (the TS bundle): the malformed-tarball guards check `dist/index.js` + `node_modules` + `package.json` (registry_cli.rs:85-103), it stages the CLI bundle (lines 111-140), and symlinks `dist/index.js` (lines 154-159). Phase 58 swaps this to stage the **musl bin** as `/opt/agentlinux/bin/<ver>/agentlinux` (or similar) and symlink `~/.npm-global/bin/agentlinux → that bin`.
**When to use:** The provisioner's step-50.
**Migration notes (be surgical — this is the highest-risk edit):**
- The `dist/index.js`/`node_modules`/`package.json` sanity checks (registry_cli.rs:85-103) become "musl bin present + executable" checks.
- The symlink TARGET changes (registry_cli.rs:157) → this affects `10-installer.bats:97,133` (INST-02 asserts `readlink .../agentlinux` is stable) and `:104,123` (INST-02 asserts the `dist/index.js` shebang is stable — **that assertion must be revised**, a static bin has no shebang).
- CAT-01/02/03/05 catalog staging (registry_cli.rs:142-152) is UNCHANGED — the catalog + recipes still stage identically.
- The `agentlinux_version()` source (registry_cli.rs:60-62) reads `$AGENTLINUX_VERSION` else `CARGO_PKG_VERSION` — already Rust-native, no TS dependency.

### Anti-Patterns to Avoid
- **A `/usr/local/bin` shim for the musl bin.** Forbidden by CLAUDE.md + AGENTS.md (the canonical self-update-breaking bug). Stage under `/opt/agentlinux/...` and symlink into the agent's `~/.npm-global/bin` exactly as today.
- **Silent fallback to the Bash+TS path on a musl-build failure.** run.sh:292-295 + :377-379 already established the fail-loud discipline (`AGENTLINUX_PROVISION_RUST`/`STAGE_RUST_CLI` abort rather than false-green). The default path must inherit that: a missing/broken bin is a hard build/install error, never a quiet TS fallback.
- **Running `jq .` on the catalog snapshot.** build-release.sh:301 uses `cp` (byte-for-byte); CAT-05 (`10-installer.bats:237-257`) locks it. Keep `cp`.
- **`sudo npm install -g` anywhere.** Not introduced here, but the swap must not regress the no-sudo-npm contract.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reproducible archive | A custom tar-normalizer | The existing `--sort=name`/`--numeric-owner`/`--mtime`/`gzip -n` recipe (build-release.sh:269-278) | Already proven byte-stable across re-runs; reproducible-builds.org canonical |
| sha256 sidecar + verify | A bespoke hash check | GNU `sha256sum` + `sha256sum -c` (build-release.sh:287-290; install.sh:207) | Round-trips; the `-c` format is what the installer already reads |
| Partial-download safety | Ad-hoc truncation guards | The `main(){}; main "$@"` wrapper (install.sh:144-232), asserted by `60-curl-installer.bats:108-127` | Bash parses the whole file before dispatch; a truncated download syntax-errors before any command runs |
| Static-bin build | Hand-linked musl | `cargo build --release --target x86_64-unknown-linux-musl` (already green, RUST-01) | The toolchain guarantees the static link; `ldd` verification is the RUST-01 contract |
| Pre-Node provisioner entry | A new install shim | The musl bin's `provision` verb (main.rs:188), already invoked by run.sh:308 | Exists and is exercised; Phase 58 just makes it the default handoff |

**Key insight:** Almost nothing new is *built* in Phase 58 — the reproducible-tar recipe, the sha256 gate, the `main`-wrapper, and the `provision` verb all already exist and are green. The phase *rewires* the producer (musl instead of pnpm), the staging target (bin instead of `dist/index.js`), and the installer handoff (musl `provision` instead of Bash entrypoint), and *deletes* the fpm path. Treat it as a wiring + deletion phase, not a construction phase.

## Runtime State Inventory

> This is a distribution/packaging phase with a rename-adjacent surface (the shipped/staged artifact changes identity from a Node script to a static bin). The grep-audit finds files; this table finds what else carries the old artifact identity.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **None** — no datastore keys reference the artifact type. The catalog snapshot + sentinels are artifact-agnostic (they key on agent id, not on how `agentlinux` is implemented). Verified: registry_cli.rs stages state under `/opt/agentlinux/state` (registry_cli.rs:75, :150-152), owned by the install user, no TS/musl marker. | none |
| Live service config | **None** — no external service embeds the artifact identity. GitHub Releases assets are re-generated per tag by `release.yml`. | none |
| OS-registered state | The symlink `~/.npm-global/bin/agentlinux` currently targets `dist/index.js` (registry_cli.rs:157). After the swap it targets the musl bin. On a **re-provision of an existing host**, `ln -sfn` (registry_cli.rs:272-285) retargets idempotently — but INST-02 (`10-installer.bats:97,133`) asserts the symlink target is *stable across a re-run*: stable within one artifact regime, but a TS→musl transition is a one-time retarget. Fresh installs are unaffected. | code edit (registry_cli.rs symlink target) + revise the INST-02 shebang assertion (`10-installer.bats:104,123`) |
| Secrets/env vars | `AGENTLINUX_VERSION` (read by build-release.sh, install.sh, registry_cli.rs:60) — value unchanged, semantics unchanged. `AGENTLINUX_STAGE_RUST_CLI` / `AGENTLINUX_PROVISION_RUST` (run.sh:41-59) — these FOLD into the default; see §Rollback Lever. `SKIP_DEB` / `--no-deb` (build-release.sh:88-105) — DELETED with the fpm branch. | update run.sh flag handling; delete SKIP_DEB/--no-deb |
| Build artifacts | `plugin/cli/dist/` + `plugin/cli/node_modules/` (gitignored tsc/pnpm output, spliced in run.sh:238-246 + Dockerfile:137-139) — these STAY for the TS parity oracle but STOP shipping in the tarball. The Dockerfile cli-builder stage (Dockerfile.ubuntu-24.04:31-38, :137-139) still builds them for the bats oracle. | none this phase (retained as oracle); delete at Phase-59 cutover |

**The canonical question — after every file is updated, what still carries the old artifact identity?** The `~/.npm-global/bin/agentlinux` symlink target on any *already-provisioned* host, and the INST-02 shebang assertion. Fresh installs (the release path) are clean. Both are addressed by the registry_cli.rs edit + the `10-installer.bats:104/123` assertion revision.

## Common Pitfalls

### Pitfall 1: INST-02 asserts a `dist/index.js` shebang that a static bin does not have
**What goes wrong:** `10-installer.bats:99-104,123` hashes `head -1 .../dist/index.js` (the `#!/usr/bin/env node` shebang) and asserts byte-stability across a re-run. A static musl bin has no `dist/index.js` and no shebang → the test breaks.
**Why it happens:** The idempotency set was built around the TS bundle's file shape.
**How to avoid:** In the same wave that swaps registry_cli.rs, revise the INST-02 assertion to hash a stable property of the staged musl bin (e.g. `sha256sum` of the staged bin, or `readlink` of the symlink — the symlink-target assertion at `:97,133` already survives). This is a spec edit that must land WITH the staging swap, not after — GATE-01 requires no newly-red test.
**Warning signs:** `10-installer.bats` INST-02 red immediately after the registry_cli.rs edit.

### Pitfall 2: The curl-installer's `exec` target path assumes `plugin/bin/agentlinux-install`
**What goes wrong:** install.sh:224 hardcodes `${inst}/plugin/bin/agentlinux-install` and asserts it is executable (`:225`). If the tarball payload no longer contains that Bash entrypoint (or is flattened), the installer dies "corrupt release?".
**Why it happens:** The tarball layout + the exec target are coupled.
**How to avoid:** Decide the payload layout (Open Questions Q1) and update the `exe=` path + the exec line (install.sh:224-229) in lockstep. The `60-curl-installer.bats` fixture (`:35-49`) builds a fake tarball with a `plugin/bin/agentlinux-install` stub — **that fixture must be updated to stage the new artifact shape** or the INST-03 happy-path test (`:129-147`) will still assert the old sentinel.
**Warning signs:** `60-curl-installer.bats` INST-03 happy-path red; "extracted tarball missing executable" error.

### Pitfall 3: The three-way version lock reads `plugin/cli/package.json`
**What goes wrong:** build-release.sh:133-150 gates the build on `TAG == plugin/cli/package.json.version == plugin/catalog/catalog.json.version`. Once the TS bundle stops shipping, `package.json` is no longer *in* the artifact — but it is still the version source of truth for the lock (and registry_cli.rs:60 falls back to `CARGO_PKG_VERSION`, which is synced to it). Keeping the lock is fine *if* `package.json` stays in the repo (it does, as the oracle), but the lock's *rationale comment* (build-release.sh:122-127: "the tag does not correspond to the code shipped inside the tarball") becomes half-true.
**Why it happens:** The version source of truth spans TS `package.json`, `catalog.json`, and Rust `Cargo.toml`.
**How to avoid:** Either (a) keep the lock reading `package.json` + `catalog.json` and additionally assert `Cargo.toml` version parity, or (b) re-base the lock on `Cargo.toml` as the primary. Recommend (a) for minimum churn — the TS `package.json` stays as the oracle version anchor until Phase 59. Document the decision.
**Warning signs:** A version-drift false-green (tag ships a musl bin whose `CARGO_PKG_VERSION` differs from the tarball's staged paths).

### Pitfall 4: `HRN-01` harness meta-test asserts `packaging/deb` exists
**What goes wrong:** `tests/harness/00-layout.bats:45-46` asserts `[ -d packaging/deb ]`. Deleting the directory (DIST-02) makes this test red.
**Why it happens:** The layout contract enumerated the deb dir.
**How to avoid:** Delete that `@test` in the same wave as the directory. Also update `docs/HARNESS.md:58,90,200-201,260` (the deb-mentioning lines) and `AGENTS.md:27` ("optional fpm .deb wrapper").
**Warning signs:** `tests/harness/run.sh` red on HRN-01.

### Pitfall 5: `tests/qemu/boot.sh` passes `SKIP_DEB=1 ... --no-deb`
**What goes wrong:** boot.sh:488 calls `SKIP_DEB=1 bash scripts/build-release.sh "$TAG" --no-deb`. Once `build-release.sh` no longer parses `--no-deb` (deleted with the fpm branch, build-release.sh:88-105), the unknown-flag branch (build-release.sh:98-102) exits 64.
**Why it happens:** The QEMU harness explicitly opts out of the deb build.
**How to avoid:** Drop `SKIP_DEB=1` and `--no-deb` from boot.sh:488 in the same wave. (QEMU itself is Phase-59-gated, but the source edit belongs here to keep the flag surface consistent.)
**Warning signs:** QEMU build step exits 64 "unknown flag: --no-deb".

### Pitfall 6: Reproducibility regresses because the musl bin embeds build-host paths
**What goes wrong:** A `cargo build` can embed absolute `$HOME/.cargo/...` or `/build/...` paths in debug info, making the bin (and thus the tarball, and thus the `.sha256`) non-reproducible across build hosts.
**Why it happens:** Rust debug metadata + panic messages can carry the build directory.
**How to avoid:** Ensure the release profile strips symbols (`strip = true` or a `strip` step) and/or set `--remap-path-prefix`. Verify with two back-to-back builds on different `$PWD` producing an identical `.sha256` — mirror the byte-identical-across-runs invariant build-release.sh:36 already claims for the tarball.
**Warning signs:** `.sha256` differs between the local build and the CI build for the same tag.

## Code Examples

### Reproducible tar recipe (retain verbatim, swap only the payload)
```bash
# Source: scripts/build-release.sh:269-278 (VERIFIED this session)
tar \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  --mtime="@${SOURCE_DATE_EPOCH}" \
  --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
  --create --file=- \
  <PAYLOAD: agentlinux bin + catalog/ + recipes> \
  | gzip -n >"$TARBALL"
```

### sha256-before-exec (the CRITICAL gate — unchanged)
```bash
# Source: packaging/curl-installer/install.sh:204-209 (VERIFIED this session)
if ! (cd "$tmpdir" && sha256sum -c "${tarball}.sha256") >/dev/null 2>&1; then
  die "SHA256 verification failed for ${tarball} — aborting install ..."
fi
# ...only AFTER this gate:  tar --extract ...  then  exec <bin> provision
```

### The musl `provision` handoff shape (already proven in the harness)
```bash
# Source: tests/docker/run.sh:308 (VERIFIED — the AGENTLINUX_PROVISION_RUST seam)
"$RUST_PROVISION_BIN_IN_CONTAINER" provision --user agent --yes
# Phase 58: this becomes the curl-installer's exec target, replacing
#   exec "${inst}/plugin/bin/agentlinux-install" "$@"   (install.sh:229)
```

### `provision` is already routed through require_root (no CLI-05 guard)
```rust
// Source: rust/crates/agentlinux/src/main.rs:188 (VERIFIED this session)
if let Command::Provision(args) = &command {
    let guard = guard::require_root(None);
    // ... runs the 10→20→30→40→50 provisioner steps as root
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ship the TS bundle (`dist/index.js` + `node_modules/`) as `agentlinux` | Ship the static musl bin | Phase 58 (this) | Removes the Node prerequisite to *run* AgentLinux (DIST-01) |
| curl-installer → Bash `agentlinux-install` entrypoint → source Bash provisioners | curl-installer → musl `provision` | Phase 58 | The pre-Node provisioner is compiled, not sourced |
| Two channels: curl-pipe-bash primary + optional fpm `.deb` (ADR-006) | Single channel: reproducible musl tarball | Phase 58 (DIST-02) | ADR-006 must be revised to tarball-only |
| Rust exercised only behind `AGENTLINUX_STAGE_RUST_CLI`/`AGENTLINUX_PROVISION_RUST` | Rust IS the default build; flags fold in | Phase 58 | bats exercise Rust with no override; one inverse rollback lever retained |

**Deprecated/outdated after this phase:**
- The fpm `.deb` path (`packaging/deb/`, `--deb`/fpm branch, postinst bridge) — DELETED.
- The pnpm-bookkeeping tar excludes (build-release.sh:274-275) — dead once TS stops shipping (leave harmless or remove).
- ADR-006's "optional `.deb`" stance — superseded.

## The DIST-02 Deletion Inventory (every fpm/.deb reference)

| # | Reference | `file:line` | Action |
|---|-----------|-------------|--------|
| 1 | `packaging/deb/postinst.sh` (the dpkg→installer bridge) | whole file | DELETE |
| 2 | `packaging/deb/.gitkeep` + the directory | `packaging/deb/` | DELETE dir |
| 3 | fpm build branch | build-release.sh:331-356 | DELETE the whole `## 11. Optional .deb` block |
| 4 | `--no-deb` flag parse | build-release.sh:88-105 (`NO_DEB_FLAG`, the `--no-deb` case) | DELETE |
| 5 | `SKIP_DEB` env references | build-release.sh:59, :69, :162-164, :337 | DELETE |
| 6 | `.deb` mentions in usage + header comment | build-release.sh:9, :14, :38-39, :59 | UPDATE (drop `.deb` lines) |
| 7 | dry-run `.deb` line | build-release.sh:161-164, :173 (`DRY_DEB_LINE`) | DELETE |
| 8 | `DEB_SUFFIX` in final summary | build-release.sh:336, :355, :361 | DELETE |
| 9 | fpm-install step + SKIP_DEB fallback | release.yml:271-283 | DELETE the "Install fpm" step |
| 10 | `.deb` in publish files glob + comment | release.yml:19, :258-260, :325, :356 | DELETE `dist/agentlinux_*.deb` line + comments |
| 11 | HRN-01 `packaging/deb` layout assertion | tests/harness/00-layout.bats:45-46 | DELETE the `@test` |
| 12 | `SKIP_DEB=1 ... --no-deb` in QEMU build | tests/qemu/boot.sh:481-482, :488 | DROP the flag + env |
| 13 | `.deb`/fpm docs | docs/HARNESS.md:58, :90, :200-201, :260 | UPDATE to tarball-only |
| 14 | "optional fpm .deb wrapper" | AGENTS.md:27 | UPDATE |
| 15 | ADR-006 | docs/decisions/006-curl-pipe-bash-plus-deb.md | FLAG for revision (add a "Superseded-in-part by Phase 58 (DIST-02): tarball-only; `.deb` removed" note; do not delete the ADR — it is the historical record) |

**ADR-006 current stance (quoted, `006-curl-pipe-bash-plus-deb.md:16-29`):**
> "Ship two distribution channels: (1) `curl -fsSL ... | bash` as the primary one-command path ... and (2) an optional fpm-built `.deb` uploaded to each GitHub Release." … "`.deb` is best-effort — we don't run a public apt repo … Promoting to a real PPA is deferred to post-v0.3.0."

Phase 58 removes channel (2) entirely. The ADR's channel (1) + the "every release tarball MUST ship with a sibling `.sha256`" consequence (`:24-26`) SURVIVE and are reinforced.

## The Rollback Lever (GATE-05) — fold the flags, keep ONE inverse

**Today's two flags (run.sh:41-59):**
- `AGENTLINUX_STAGE_RUST_CLI=1` — re-point the `agentlinux` symlink at the Rust bin *after* the TS-bundle install (run.sh:341-395). Exists because the provisioner still stages TS by default.
- `AGENTLINUX_PROVISION_RUST=1` — run the Rust `provision` instead of the Bash entrypoint (run.sh:289-308).

**Once Rust IS the default artifact, both become the default path** — the provisioner stages the musl bin (no post-hoc symlink override needed) and the installer execs the musl `provision` (no Bash-entrypoint branch needed). The bats then exercise Rust with **no override**, which is exactly GATE-01's intent for this phase.

**Recommendation: remove the two forward flags, add ONE inverse lever `AGENTLINUX_LEGACY_TS=1`** that restores the Bash+TS distribution (stage `dist/index.js`, exec the Bash entrypoint, build the TS tarball). Rationale:
- **GATE-05 requires a per-phase rollback to Bash+TS.** A single, clearly-named inverse flag is a cleaner rollback lever than two forward flags whose semantics invert.
- It keeps the TS oracle path *executable end-to-end* (not just compiled) so a Phase-58 regression can be diagnosed by flipping one env var, and so master's hotfix path (which is still Bash+TS until the Phase-59 cutover) stays reachable.
- The fail-loud discipline (run.sh:292-295, :377-379) transfers: `AGENTLINUX_LEGACY_TS=1` must abort if the TS bundle is absent rather than false-green on the musl bin.

**Alternative (if the planner prefers zero new flags):** delete both forward flags and rely on `git revert` of the Phase-58 commits as the rollback. Weaker — GATE-05 wants a *live* per-phase lever, and the TS oracle is retained anyway, so wiring it to a flag is nearly free. Recommend the single-inverse-flag approach.

**The TS-source question (CONTEXT leans STAY — confirmed):** `plugin/cli/` MUST stay in the repo this phase. Evidence: (1) `10-installer.bats:73,227,245` + `CAT-05` read `plugin/cli/package.json` as the version oracle; (2) the Dockerfile cli-builder stage (Dockerfile.ubuntu-24.04:31-38,137-139) builds `dist/` for the bats, and run.sh:238-246 splices it; (3) the version lock (build-release.sh:133) reads it. Deleting `plugin/cli/` now would break live bats + CI. **Recommend: STAY; delete at the Phase-59 cutover** (matches the deferred-ideas + the PROV-02 residual pattern already established at REQUIREMENTS.md:40).

## Acceptance Oracle

| bats file | Requirement family | What it locks | How it runs on the Rust build now |
|-----------|-------------------|---------------|-----------------------------------|
| `60-curl-installer.bats` | INST-03 | sha256-before-exec (`:149-188`), happy-path exec-handoff (`:129-147`), `main`-wrapper partial-download safety (`:108-127`), resolve_version first-hop (`:206-236`) | Fixture (`:35-49`) must stage the NEW artifact shape; the happy-path sentinel + `exe` path must match the swapped handoff |
| `10-installer.bats` | INST-01/02/05, DOC-02, CAT-05 | log banner, **idempotency incl. symlink-target + shebang** (`:36-140`), no-EACCES, catalog byte-stability (`:221-257`) | INST-02 shebang assertion (`:104,123`) MUST be revised for a static bin (Pitfall 1); symlink-target assertion survives |
| `23-install-user.bats` | CLI-01/05 (INST refs) | `agentlinux` resolves on PATH as the install user; the CLI-05 guard | The staged musl bin must resolve as `agentlinux`; already exercised via `AGENTLINUX_STAGE_RUST_CLI` today, becomes default |
| `40-registry-cli.bats` | CLI-* | the six verbs' stdout/exit parity | Already green on the Rust bin under the flag (Phase 56); becomes default |
| `tests/harness/00-layout.bats` | HRN-01 | repo layout | `packaging/deb` assertion (`:45-46`) DELETED (Pitfall 4) |
| `release.yml` build+verify gate | — | `.sha256` sidecar present + `sha256sum -c` round-trips (`:294-306`) | The `.deb` glob (`:356`) + fpm step (`:271-283`) DELETED; the tarball+sha256 verify SURVIVES |

**Docker-OOM note:** the full suite OOMs ~test 131 in this VM (MEMORY + run.sh:86-99) — run the swap's acceptance per-file: `bash tests/docker/run.sh ubuntu-24.04 60-curl-installer`, then `10-installer`, then `23-install-user`. The whole-suite green is the CI/Phase-59 job.

**Phase-59-gated (do NOT attempt to close here):** the 4-distro QEMU release gate (release.yml gate-3, boot.sh) + AGT-02 self-update against the live Anthropic CDN (GATE-04). Phase 58 edits the *source* those gates run (boot.sh flag drop) but the gates themselves fire in Phase 59.

## No-Node-Prereq Proof (DIST-01's central claim)

**How "the CLI/provisioner needs no Node" is asserted:**
1. **Static-link proof (RUST-01, already green):** `ldd` on the musl bin reports "not a dynamic executable" — no libc, no interpreter. This is the compile-time guarantee.
2. **Runtime proof — the installer reaches + runs `provision` before Node exists:** `nodejs.rs` is provisioner step 30 (run *inside* `provision`), so the binary is already executing before Node is installed. The existing `AGENTLINUX_PROVISION_RUST=1` harness run (run.sh:289-308) already demonstrates this ordering on a fresh container.
3. **Recommended explicit assertion for Phase 58:** add/confirm a bats check that the install path contains no `node`/`npm`/`pnpm` invocation *before* the musl bin runs. The cleanest proof is a Docker image with Node absent at install-start, running `<bin> provision`, and asserting a green provision up to the point `nodejs.rs` *installs* Node for the recipes. `10-installer.bats:142-171` (INST-05 apt-cache guard) is the pattern to mirror — a negative-assertion on the log.
4. **What still needs Node (and that is correct):** the ~25 recipes (`catalog/agents/*/install.sh`) npm/apt/curl-install the agents; `nodejs.rs` provisions Node for THEM. DIST-01's claim is scoped to "the CLI/provisioner *itself*" — the recipes are the irreducible boundary (REQUIREMENTS.md Out-of-Scope, CONTEXT decisions).

**Acceptance map:** static-link → RUST-01 (green); reaches-provision-pre-Node → the `AGENTLINUX_PROVISION_RUST` seam becoming default + a new negative-assertion bats; recipes-still-get-Node → `50-agents.bats` (already green).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The release profile does not yet strip build-host paths from the musl bin; a strip/remap step is needed for reproducibility | Pitfall 6, Pattern 1 | If already stripped, the step is a no-op — LOW risk; verify `rust/**/Cargo.toml` profile |
| A2 | `rust-toolchain.toml` pins the toolchain (needed for reproducible musl builds) | Standard Stack, Env Availability | If absent, two build hosts could produce different bytes → unstable `.sha256`; verify + add if missing |
| A3 | The tarball keeps a top-level prefix compatible with install.sh's `exe=` path derivation | Structure, Pitfall 2, Open Q1 | Wrong layout → installer "corrupt release?" — planner must fix layout + exec path together |
| A4 | Keeping the version lock reading `plugin/cli/package.json` is acceptable while TS stays as the oracle | Pitfall 3, Open Q3 | If the planner re-bases on `Cargo.toml`, more churn but no correctness risk |

**All other claims are `[VERIFIED]` against a `file:line` read this session.**

## Open Questions

1. **Tarball payload layout / prefix.**
   - What we know: install.sh:224 derives `exe="${inst}/plugin/bin/agentlinux-install"`; the fixture (`60-curl-installer.bats:35-49`) mirrors `plugin/...`.
   - What's unclear: whether to keep a `plugin/`-prefixed layout (bin at `plugin/bin/agentlinux`, catalog at `plugin/catalog/`) for minimum installer churn, or flatten to a top-level bin.
   - Recommendation: keep the `plugin/` prefix + place the musl bin at `plugin/bin/agentlinux`; update install.sh's `exe=` + exec line and the fixture in lockstep. Minimizes the diff and keeps CAT-01 catalog paths stable.

2. **Does the curl-installer exec the musl `provision` directly, or a thin wrapper?**
   - What we know: main.rs:188 routes `provision` through `require_root`; run.sh:308 invokes `<bin> provision --user agent --yes`.
   - What's unclear: whether install.sh should pass `--yes` (non-TTY consent) unconditionally (the curl-pipe context is non-interactive) or preserve today's interactive prompting.
   - Recommendation: pass `--yes` for the curl-pipe path (it is inherently non-interactive), matching run.sh:308; verify against the remediate/preflight bats consent expectations.

3. **Where does the version source-of-truth live after TS stops shipping?**
   - What we know: build-release.sh:133 locks on `plugin/cli/package.json`; registry_cli.rs:60 falls back to `CARGO_PKG_VERSION` (synced to it).
   - Recommendation: keep the lock on `package.json` + `catalog.json`, ADD a `Cargo.toml`-parity assertion. Re-base fully on `Cargo.toml` at the Phase-59 cutover when `plugin/cli/` is deleted.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `cargo` + `x86_64-unknown-linux-musl` target | musl bin build (DIST-01) | ✓ (Phase 53-57 CI green) | pin via `rust-toolchain.toml` — VERIFY it exists (A2) | none — hard requirement |
| GNU `tar`, `gzip`, `sha256sum` | reproducible tarball + sidecar | ✓ | system coreutils | none |
| `curl` | installer fetch | ✓ | system | none |
| `jq` | version lock (build-release.sh:128) | ✓ | system | build fails loud if absent (build-release.sh:128-131) |
| `fpm` / `ruby` | (being DELETED) | n/a | — | n/a — removed by DIST-02 |

**Missing dependencies with no fallback:** none identified. Confirm `rust-toolchain.toml` pins the toolchain (A2) — the only availability gap that would threaten reproducibility.

## Validation Architecture

> `.planning/config.json` was not read for a `nyquist_validation` flag this session; treating as enabled (absence = enabled). The oracle for this phase is the existing bats suite (ADR-002), not a new unit-test framework.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats (behavior contract) + `cargo test`/`node:test` for units |
| Config file | `tests/bats/` (no bats config file — files are self-contained) |
| Quick run command | `bash tests/docker/run.sh ubuntu-24.04 60-curl-installer` (per-file, Docker-OOM dodge) |
| Full suite command | `bash tests/docker/run.sh ubuntu-24.04` (whole `tests/bats/`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DIST-01 | sha256-before-exec + no-Node handoff | integration (bats) | `bash tests/docker/run.sh ubuntu-24.04 60-curl-installer` | ✅ (fixture needs update — Pitfall 2) |
| DIST-01 | staged `agentlinux` = musl bin, idempotent | integration | `bash tests/docker/run.sh ubuntu-24.04 10-installer` | ✅ (INST-02 shebang assertion needs revision — Pitfall 1) |
| DIST-01 | no Node before the bin runs | integration | new negative-assertion (mirror INST-05 log-grep) | ❌ Wave 3 |
| DIST-02 | deb path gone | layout | `bash tests/harness/run.sh` | ✅ (HRN-01 deb assertion deleted — Pitfall 4) |
| DIST-02 | release publishes no `.deb` | CI | `release.yml` build+verify gate | ✅ (glob + fpm step deleted) |
| GATE-01 | full suite green on Rust default | integration | full-suite (CI/Phase-59) | ✅ existing |
| GATE-05 | rollback to Bash+TS | manual/harness | `AGENTLINUX_LEGACY_TS=1 bash tests/docker/run.sh ...` | ❌ Wave 3 (new lever) |

### Sampling Rate
- **Per task commit:** the affected per-file bats (`60-curl-installer` / `10-installer` / `23-install-user`).
- **Per wave merge:** the three installer-facing files together.
- **Phase gate:** full suite green (CI) before `/gsd-verify-work`; QEMU/AGT-02 deferred to Phase 59.

### Wave 0 Gaps
- [ ] Update `60-curl-installer.bats` fixture (`:35-49`) + happy-path sentinel (`:129-147`) to the new artifact shape — covers DIST-01.
- [ ] Revise `10-installer.bats` INST-02 shebang assertion (`:104,123`) → stable static-bin property — covers DIST-01/GATE-01.
- [ ] New negative-assertion bats: no `node`/`npm` before the musl bin runs — covers the DIST-01 "no Node prereq" claim.
- [ ] Delete HRN-01 `packaging/deb` `@test` (`00-layout.bats:45-46`) — covers DIST-02.
- [ ] New `AGENTLINUX_LEGACY_TS=1` rollback path in run.sh + a smoke that it restores Bash+TS — covers GATE-05.

## Security Domain

> `security_enforcement` config not read this session; treating as enabled. This phase's security surface is the **software supply chain / distribution trust**, which is the dominant threat for a `curl | bash` installer.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture (supply chain) | yes | Reproducible build → deterministic `.sha256`; the artifact a user gets is bit-provable against source |
| V5 Input Validation | yes | `AGENTLINUX_VERSION`/`ORG` regex-gated before URL interpolation (install.sh:46-47, :121-123, :150-151) — KEEP |
| V6 Cryptography | yes | sha256 integrity check (build-release.sh:287-290; install.sh:207) — the trust anchor; do NOT weaken |
| V12 Files/Resources | yes | `--no-same-owner` on extract (install.sh:218-221); `mktemp -d` + `trap rm -rf` staging (install.sh:169-174) — KEEP |
| V2/V3/V4 (auth/session/access) | no | No user auth surface in the installer |

### Known Threat Patterns for the distribution channel

| Pattern | STRIDE | Standard Mitigation | Status this phase |
|---------|--------|---------------------|-------------------|
| Tampered/MITM tarball | Tampering | sha256-before-exec gate (install.sh:204-209) | UNCHANGED — the critical rule; asserted by `60-curl-installer.bats:149-188` |
| Partial-download execution | Tampering/DoS | `main(){}; main "$@"` wrapper (install.sh:144-232) | UNCHANGED — asserted by `60-curl-installer.bats:108-127` |
| 404-as-HTML masquerading as tarball | Tampering | gzip magic-byte check (install.sh:198-202) | UNCHANGED — artifact-agnostic, keep |
| Redirect-chain tag confusion | Spoofing | first-hop `%{redirect_url}` only, no `-L` (install.sh:136, AL-31) | UNCHANGED — asserted by `60-curl-installer.bats:206-236` |
| Non-reproducible bin → unverifiable supply chain | Repudiation | strip/remap build-host paths + toolchain pin (Pitfall 6, A1/A2) | NEW attention — the swap from a text bundle to a compiled bin adds this class |
| `/usr/local/bin` shim (self-update break) | Elevation/Tampering | stage under `/opt`, symlink to agent home (registry_cli.rs) | UNCHANGED — CLAUDE.md hard rule |

**The one net-new security consideration:** swapping a text Node bundle for a compiled binary shifts one reproducibility risk (pnpm bookkeeping timestamps — build-release.sh:259-266, going away) for another (compiler-embedded build-host paths — Pitfall 6). The sha256 gate protects the *user*; reproducibility protects the *auditor's ability to prove the bin matches source*. Both must hold.

## Risks + Wave Sequencing

### Top Risks
1. **#1 — The staging swap regresses the installer bats (the crux).** registry_cli.rs (symlink target + sanity checks) + install.sh (exec target) + `60-curl-installer.bats` fixture + `10-installer.bats` INST-02 shebang assertion are a *coupled set*. Editing one without the others yields a red suite. Mitigation: land them in a single wave; run the three installer bats per-file before merge.
2. **Reproducible-tarball determinism for a compiled bin (Pitfall 6/A1/A2).** A non-stripped/non-remapped musl bin breaks the stable-`.sha256` invariant. Mitigation: verify the strip profile + toolchain pin; assert two-build byte-identity.
3. **The sha256-before-exec contract must survive verbatim.** It is the project's stated critical rule. Mitigation: do not touch install.sh:204-209 except the *downstream* exec target; keep `60-curl-installer.bats:149-188` green.
4. **GATE-05 rollback if the swap regresses.** A broken Phase-58 must revert to Bash+TS. Mitigation: the single `AGENTLINUX_LEGACY_TS=1` inverse lever + retained `plugin/cli/` oracle + retained Bash entrypoint (deleted only at Phase-59).
5. **DIST-02 deletions breaking meta-tests/CI (HRN-01, boot.sh, release.yml).** Mitigation: the deletion inventory table — every reference deleted in the same wave as the fpm branch.

### Recommended Wave Breakdown (3 waves)

- **Wave 1 — Producer + deletions (low coupling, high parallelism):**
  `build-release.sh` builds the musl tarball (swap pnpm→cargo, retain the tar/sha256 recipe) + DELETE the fpm branch; delete `packaging/deb/`; update `release.yml` (drop fpm step + `.deb` glob); delete HRN-01 deb `@test`; drop `SKIP_DEB`/`--no-deb` from boot.sh; update `docs/HARNESS.md`/`AGENTS.md`; flag ADR-006. Verify: `build-release.sh --dry-run` + `tests/harness/run.sh` + a local reproducible-build byte-identity check.
- **Wave 2 — The staging swap (the crux, serialized):**
  `registry_cli.rs` stages the musl bin as the default `agentlinux` command; `curl-installer/install.sh` execs the musl `provision` (no Node prereq); update the `60-curl-installer.bats` fixture + `10-installer.bats` INST-02 assertion in lockstep. Verify per-file: `60-curl-installer`, `10-installer`, `23-install-user`, `40-registry-cli`.
- **Wave 3 — Fold the flags + GATE-05 lever + closeout:**
  Fold `AGENTLINUX_STAGE_RUST_CLI`/`AGENTLINUX_PROVISION_RUST` into the default; add the `AGENTLINUX_LEGACY_TS=1` inverse rollback lever; add the no-Node-before-bin negative-assertion bats; full-suite bats closeout (per-file sweep locally, whole-suite in CI). GATE-01/05 sign-off.

## Sources

### Primary (HIGH confidence — read this session)
- `scripts/build-release.sh:1-361` — full release-builder flow, fpm branch, reproducible tar recipe, sha256 sidecar, version lock
- `packaging/curl-installer/install.sh:1-232` — fetch/verify/exec flow, sha256-before-exec gate, `main`-wrapper
- `rust/crates/agentlinux/src/provision/registry_cli.rs:1-453` — the Q1 TS-bundle staging (the swap target)
- `rust/crates/agentlinux/src/main.rs:104-189` + `cli.rs:43-196` — the `provision` verb + require_root routing
- `packaging/deb/postinst.sh:1-38` — the dpkg bridge to delete
- `.github/workflows/release.yml:1-357` — the 4-gate pipeline, fpm step, `.deb` glob
- `tests/docker/run.sh:1-438` — the `AGENTLINUX_STAGE_RUST_CLI`/`AGENTLINUX_PROVISION_RUST` seams + `host_build_musl`
- `tests/bats/60-curl-installer.bats:1-236`, `tests/bats/10-installer.bats:1-258` — the INST-* acceptance oracle
- `tests/harness/00-layout.bats:45-46`, `tests/qemu/boot.sh:481-488` — the deb meta-test + QEMU flag
- `docs/decisions/006-curl-pipe-bash-plus-deb.md:1-30` — ADR-006 current stance
- `plugin/bin/agentlinux-install:1-40` — the Bash entrypoint (version-from-package.json, provisioner sourcing)
- `.planning/REQUIREMENTS.md` (DIST-01/02, GATE-01/05, PROV-02 residual), `.planning/ROADMAP.md` (Phase 58 criteria), CONTEXT.md

### Secondary (MEDIUM)
- MEMORY notes (Docker-OOM per-file discipline; v0.4.0 Rust rewrite decision)

### Tertiary (LOW)
- None — no external web research was required for this packaging phase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools pre-existing + CI-green; no new packages.
- Architecture (the swap): HIGH — every touch-point read at `file:line`; the `provision`-handoff is already exercised by the harness seams.
- Pitfalls: HIGH — each pitfall traced to a specific existing assertion (`file:line`) that will break.
- Reproducibility of the compiled bin: MEDIUM — depends on the toolchain pin + strip profile (A1/A2, verify).

**Research date:** 2026-07-29
**Valid until:** ~2026-08-28 (stable — the target files change only within this phase; re-verify if the branch rebases onto a changed `build-release.sh`/`install.sh`).
</content>
</invoke>
