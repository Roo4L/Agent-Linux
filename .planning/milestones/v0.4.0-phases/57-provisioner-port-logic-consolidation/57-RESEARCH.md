# Phase 57: Provisioner Port + Logic Consolidation - Research

**Researched:** 2026-07-28
**Domain:** Rust port of the PRE-Node Bash provisioner (agent-user, sudoers, NodeSource Node, six-mode PATH wiring, registry-CLI staging) + wiring the already-ported pure decision core (detect/remediate/reuse/idempotency) into a Rust `provision` entrypoint + consolidating the duplicated `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` maps into a single Rust source. Parity pinned by the bats behavior suite (`RT-*`/`AGT-*`/`DET-*`/`REUSE-*`/`REMEDIATE-*`/`INST-*`) across six invocation modes on Ubuntu 22/24/26 + AlmaLinux 9.
**Confidence:** HIGH — every finding is grounded in this repo's source at `file:line`; the genuinely-new surface (systems I/O: useradd/sudoers/NodeSource/PATH-files) is a byte-for-byte port of Bash whose observable output the bats already pin, and the decision layer is pure code already ported in Phases 53–56.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None locked. CONTEXT.md marks this a **Smart-discuss infrastructure-skip** phase: a like-for-like provisioner port producing **identical observable system state** — no user-facing change. The hard, non-negotiable bar is that the bats behavior suite (ADR-002) stays green for the provisioner surface (`RT-*`/`AGT-*`/`DET-*`/`REUSE-*`/`REMEDIATE-*`/`INST-*`) across all six invocation modes on both distro families. "Same observable state" = the bats assertions on file **contents + modes + owners + PATH resolution** — NOT identical internal structure. Enforced by GATE-01 (full bats green, no regression / no newly-skipped) and GATE-05 (master shippable; parallel track; per-phase rollback).

### Claude's Discretion (recommended shape below — not binding)
- The `agentlinux` bin grows a `provision` entrypoint/subcommand running the ordered steps the Bash provisioner runs today: ensure agent user → sudoers drop-in → NodeSource Node → PATH/env wiring (`/etc/agentlinux.env` + profile.d + .bashrc + cron.d) → stage the registry CLI. Each step idempotent.
- Port `plugin/lib/idempotency.sh` primitives (`ensure_marker_block`, `ensure_line_in_file`, atomic file install w/ mode+owner) as Rust helpers — the load-bearing "same observable state" primitives.
- Consolidate `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` (duplicated in `plugin/lib/reuse/agents.sh`, iterated by `remediate.sh` + `prompt.sh`) into ONE Rust source; the Bash copies deleted.
- Distro detection (`distro_detect.sh`) + the pkg abstraction (`pkg.sh`: apt↔dnf) → Rust. This is the AlmaLinux parity surface (PROV-03).

### Deferred Ideas (OUT OF SCOPE)
- musl tarball as sole channel + drop fpm `.deb` → **Phase 58.**
- Full-matrix bats (Docker 22/24/26 + AlmaLinux 9) + QEMU release gate + AGT-02 self-update against the live CDN → **Phase 59.**
- Rewriting the ~25 per-agent `install.sh`/`uninstall.sh` recipes → **permanently out of scope** (they stay Bash behind the generated env-var contract).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PROV-01 | Provisioning (agent-user, sudoers, NodeSource Node, PATH/env wiring, registry-CLI staging) leaves the same observable state as the Bash provisioner; `RT-*`/`AGT-*` bats green across all six invocation modes. | §The Entrypoint + Step Order, §Each Provisioner Step, §The Six-Mode PATH Matrix, §NodeSource Install, §Idempotency Primitives. |
| PROV-02 | detect/remediate/reuse/idempotency consolidated into Rust; the duplicated `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` maps DELETED from Bash (single source of truth in Rust). | §PROV-02 Map Consolidation — the exact three Bash sites + two external consumers + the recommended generated-output bridge. |
| PROV-03 | Distro detection + aware-install reuse/remediate/bail paths behave identically on Ubuntu 22.04/24.04/26.04 **and** AlmaLinux 9; `DET-*`/`REUSE-*`/`REMEDIATE-*` bats green. | §Distro Detection + Pkg Abstraction — every apt↔dnf branch point mapped; §The Detect/Remediate/Reuse Wiring. |
| GATE-01 | Full bats green for the provisioner surface; no red / newly-skipped. Cross-cutting. | §Acceptance Oracle + Staging — bats file map, staging strategy, Docker-only vs QEMU/Phase-59 split. |
| GATE-05 | master shippable; parallel track; per-phase rollback. Cross-cutting. | §Risks + Wave Sequencing — provision entrypoint is an ADDITIVE subcommand; Bash provisioner stays authoritative until the entrypoint is swapped under a harness flag. |
</phase_requirements>

## Summary

Phase 57 is the **systems-I/O + orchestration layer** wrapped around a decision core that is already fully ported. The heavy decision lifting is done: `classify`, `compute_divergence`, `resolve_latest_for`, the three detect gates (`reuse_gate`/`remediate_gate`/`presence_gate`), `derive_category`, `parse_pin_spec`, `reuse::agent_decision` all live in `agentlinux-core` `[VERIFIED: rust/crates/agentlinux-core/src/{classify,divergence,detect_gates,category,pin_spec,reuse}.rs]`; the bin adapters (guard/catalog/sentinel/cache/probe/npm/rewire + dispatcher + `RecipeEnv`) are present from Phase 56 `[VERIFIED: rust/crates/agentlinux/src/*.rs]`. What Phase 57 ADDS is the genuinely-new privileged systems I/O — `useradd`, the `/etc/sudoers.d/agentlinux` drop-in (visudo-gated), the NodeSource curl-pipe-bash + apt/dnf install, and the four PATH-wiring artefacts — plus a `provision` entrypoint that ORCHESTRATES the ported core + these steps, and DELETES the last Bash decision duplication.

**The crux is that this runs PRE-Node.** The final Docker/release images are bare `ubuntu:{22.04,24.04,26.04}` / `almalinux:9` — Node exists ONLY after `30-nodejs.sh` runs NodeSource `[VERIFIED: tests/docker/Dockerfile.ubuntu-24.04:58 FROM ubuntu:24.04; :96 apt-get install; plugin/provisioner/30-nodejs.sh:94-101]`. So the static musl `agentlinux` bin must create the agent user + install Node BEFORE any Node runtime exists — the entire justification for the compiled binary. The Bash provisioner boots a system from bare in a strict numeric-ordered sequence (`10`→`20`→`30`→`40`→`50`); the Rust `provision` entrypoint must reproduce that exact order and each step's idempotent, byte-stable output.

**PROV-02 is subtle and mostly already-done.** The TS `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` were absorbed into the Rust bin in Phase 56 (`main.rs::canonical_path()` + `GSD_SYSTEM_PATH` const) `[VERIFIED: rust/crates/agentlinux/src/main.rs:35-49]`. The ONE remaining Bash copy is `REUSE_AGENT_CANONICAL_PATHS` + `REUSE_GSD_SYSTEM_PATH` in `plugin/lib/reuse/agents.sh:38-53`, deliberately retained because **two external consumers** iterate its keys: `remediate.sh:286-296` (per-agent decision enumeration) and `prompt.sh:110-114` (per-agent report rendering) `[VERIFIED]`. Consolidation means: delete the Bash map + retire the Bash reuse fallback, and have the Rust bin become the single enumerator (the entrypoint calls the ported gates directly instead of shelling per-id). The map must not desync — the recommended bridge is that the Rust `provision` flow owns the per-agent iteration end-to-end (no Bash iterator survives), with a documented fallback for any Bash still needing the list (the bin can `--print-canonical-map` if truly needed, but the goal is zero Bash consumers).

**Primary recommendation:** Add a `provision` subcommand to the clap CLI (`main.rs` already dispatches; extend `cli.rs`). Port `idempotency.sh` as a Rust `sysio` module (`write_file_atomic`, `ensure_marker_block`, `ensure_line_in_file`, `ensure_user`, `ensure_dir`, `visudo_validate`) using `std::fs` + `std::process::Command` (useradd/visudo/chown) + `nix` (already a dep) for uid/gid/mode. Port `distro_detect.sh` + `pkg.sh` as a `distro` module (the apt↔dnf verb set) — the PROV-03 parity surface, mirroring the v0.3.5 AlmaLinux Bash branch byte-for-byte. Reuse the Phase-56 dispatcher for the NodeSource curl-pipe-bash + `as_user` recipe invocations. Wire the ported detect gates into the entrypoint (detect → decide RESOLUTIONS → run ordered steps). Stage the Rust provisioner by extending `tests/docker/run.sh` (currently runs the Bash `agentlinux-install` at line 238) with a `AGENTLINUX_PROVISION_RUST=1` gate that runs `agentlinux provision` instead — Bash entrypoint stays authoritative on master. This is the largest phase; recommend **6 waves** (see §Risks + Wave Sequencing).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Decision logic (classify/divergence/gates/category/pin/reuse) | Pure core (`agentlinux-core`) | — | **Already ported (Phases 53–55).** Entrypoint consumes; never re-derives. |
| Subprocess dispatch (`sudo -u`, tee, timeout, signal escalation) | Bin (`dispatcher.rs`) | OS | **Already ported (Phase 56).** Reused for NodeSource setup + `as_user` recipe/verify calls. |
| Catalog/sentinel/cache/probe/npm/rewire adapters | Bin (Phase-56 modules) | `std::fs` / subprocess | **Already ported.** The registry-staging step + adoption reuse these. |
| Idempotency primitives (atomic write, marker block, ensure_user/dir) | **Bin — NEW (`sysio.rs`)** | OS (`std::fs`+`nix`+useradd/visudo) | The load-bearing "same observable state" port. Byte-fidelity is asserted by bats on content+mode+owner. |
| Distro detection + pkg abstraction (apt↔dnf) | **Bin — NEW (`distro.rs`/`pkg.rs`)** | subprocess (apt-get/dnf) | PROV-03 parity surface. One branch per verb on family, mirroring `pkg.sh`. |
| The 5 provisioner steps (user/sudoers/node/path/registry) | **Bin — NEW (`provision/*.rs`)** | sysio + distro + dispatcher | The privileged systems I/O — the genuinely-new work. |
| Provision entrypoint (flag parse, order, detect→decide→act) | **Bin — NEW (`cmd/provision.rs`)** | pure gates + adapters | Orchestrator; reproduces `agentlinux-install`'s `main()` order. |
| Canonical-path map (`CANONICAL_PATHS`/`GSD_SYSTEM_PATH`) | Bin (`main.rs`, single source) | — (Bash copy DELETED) | PROV-02 consolidation. Rust becomes the sole source; the Bash map + fallback retire. |
| Detection probes (user/nodejs/npm-prefix/agents/sudoers state) | Bin adapters | `std::fs` / subprocess | The I/O that FEEDS the pure gates (npm prefix writable? node version? sudoers line present?). New thin readers. |
| Interactive TTY prompt (`prompt.sh`) | Thin boundary | — | Stays a thin boundary per CONTEXT; port only what bats exercises (non-TTY paths dominate CI). |

## Standard Stack

**No new crates.** Every dependency this phase needs is already in the bin's `Cargo.toml` from Phase 56 `[VERIFIED: rust/crates/agentlinux/Cargo.toml]`: `clap 4.6` (derive), `nix 0.31` (features `signal`, `process`, `user` — the last gives `User`/`Group`/`chown`/uid lookups needed for `ensure_dir`/`ensure_user`/chown-at-rename), `wait-timeout 0.2`, `serde`/`serde_json 1`, `thiserror 1`, `tempfile 3` (dev). `agentlinux-core` (path dep) supplies the pure gates.

### Core (bin `agentlinux` — reused, no new deps)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `nix` | `0.31` (features `signal`,`process`,`user`) | `chown` (owner at atomic-rename), uid/gid resolution for `ensure_dir`/`ensure_user`, mode bits | Already present; `user` feature covers `User::from_name`/`chown`. `std::fs` alone cannot set owner. `[VERIFIED: crates.io — nix OK, 11.9M weekly dl, github.com/nix-rust/nix, no postinstall]` |
| `std::process::Command` | std | `useradd --create-home --shell /bin/bash --user-group`, `visudo -cf`, `locale-gen`/`update-locale`, `dnf module reset`, plus the NodeSource `curl … \| bash -` (via the Phase-56 dispatcher) | std; no external crate. |
| `clap` | `4.6` (derive) | Add the `provision` subcommand + its flags (`--user`, `--yes`, `--dry-run`, `--report-only`, `--purge`, etc.) | Already the CLI parser. `[VERIFIED: crates.io — clap OK, 16M weekly dl]` |
| `agentlinux-core` | path | The ported pure gates the entrypoint consumes | In-repo. `[VERIFIED: rust/Cargo.toml]` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `dispatcher.rs` (Phase 56) | in-repo | Run NodeSource setup + `as_user` recipe/verify + `agentlinux adopt --all` post-provision with tee/timeout/signal escalation | Any shell-out to an external tool or a per-agent recipe. |
| `recipe_env.rs::full_child_env` (Phase 56) | in-repo | The 6 `AGENTLINUX_*` + canonical PATH/HOME/npm-prefix child env for recipe/adoption dispatch | When invoking a recipe or `agentlinux adopt --all` as the install user. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `std::process::Command` for useradd/visudo/apt/dnf | A pure-Rust user-mgmt crate (e.g. shelling avoided) | **Rejected.** These ARE the observable boundary the bats assert (`useradd` semantics, `visudo -cf` gate, apt/dnf pinning). Shelling to the exact same binaries preserves byte-identical behavior; a pure-Rust reimplementation would diverge from `/etc/passwd` conventions and drop the visudo TOCTOU belt. |
| `nix::unistd::chown` | `std::os::unix::fs::chown` (Rust 1.73+) | `std` `chown` exists and avoids nix for the ownership case — weigh at plan time. `nix` is already a dep and its `User::from_name`/`Group::from_name` name→uid lookup is still needed regardless (`ensure_dir` takes `user:group` strings). Recommend `nix` for name resolution + either for the syscall. |
| A marker-block crate | hand-port the `awk`-strip algorithm | **Hand-port.** `ensure_marker_block` (idempotency.sh:94-147) is a precise line-filter (strip lines between `# >>> tag begin >>>`/`# <<< tag end <<<`, re-emit at `--top`/`--bottom`) with byte-exact output the `.bashrc` bats grep. No crate matches; port the algorithm verbatim. |

**Installation:** No `cargo add`. Confirm the existing features cover the port:
```bash
cd rust && cargo tree -p agentlinux -i nix   # confirm signal+process+user features present
```

**Version verification:** All crates already pinned + Package-Legitimacy-cleared in Phase 56. Re-confirm none regressed:
```bash
cargo metadata --format-version 1 | jq '.packages[] | select(.name=="nix") | .version'
```

## Package Legitimacy Audit

> **No new packages this phase.** All deps were audited + pinned in Phase 56. Re-verified this session for completeness.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `nix` | crates.io | since 2014-11-11 | 11.96M/wk | github.com/nix-rust/nix | OK | Approved (already in Cargo.toml) |
| `wait-timeout` | crates.io | since 2015-09-08 | 3.70M/wk | github.com/alexcrichton/wait-timeout | OK | Approved (already in Cargo.toml) |
| `clap` | crates.io | since 2015-03-01 | 16.05M/wk | github.com/clap-rs/clap | OK | Approved (already in Cargo.toml) |

`[VERIFIED: gsd-tools query package-legitimacy check --ecosystem crates nix wait-timeout clap → all OK, no postinstall, source-backed]`

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Project Constraints (from CLAUDE.md / AGENTS.md)

- **Never `sudo npm install -g` anywhere; always `sudo -u agent -H`** — the Rust entrypoint's recipe/adoption dispatch MUST route through `as_user` semantics (the Phase-56 dispatcher already does `sudo -u <user> -H -E --` with the invoker==target short-circuit). `[VERIFIED: plugin/lib/as_user.sh:32-40; AGENTS.md Critical Rules]`
- **No wrapper shims at `/usr/local/bin/`** pointing to agent-owned binaries — the provisioner stages `agentlinux` into `~/.npm-global/bin/` via symlink, NOT `/usr/local/bin`. `[VERIFIED: plugin/provisioner/50-registry-cli.sh:124]`
- **Behavior tests in `tests/bats/` are the spec** — implementation may change freely while the suite stays green. Do not pin implementation choices as requirements.
- **Docker-only test runs are insufficient** — QEMU must be green before release; six-mode PATH (systemd/cron/locale) needs a real VM. Phase 57 runs the Docker-runnable cases; the systemd/QEMU-gated cases are Phase 59.
- **Every release tarball ships a sibling `.sha256`** — not this phase (Phase 58), but the registry-staging step must remain compatible.
- Follow the `agentlinux-installer` project skill conventions (set -euo pipefail semantics, idempotency primitives, `as_user`, distro detection, six-mode PATH contract) — the Rust port must preserve the same contracts the skill codifies.

## Architecture Patterns

### System Architecture Diagram

```
                    agentlinux provision [--user=NAME --yes --dry-run --report-only --purge]
                                          │  (runs as root, PRE-Node, on bare ubuntu/almalinux)
                                          ▼
                          ┌───────────────────────────────┐
                          │ cmd/provision.rs (orchestrator)│  reproduces agentlinux-install main()
                          │  flag parse · log tee · traps  │
                          └───────────────┬───────────────┘
                                          ▼
                    ┌─────────────────────────────────────────────┐
                    │ distro::detect  → family ∈ {debian, rhel}    │  distro_detect.sh port
                    │                   + version (22.04/9.x)      │
                    └─────────────────────┬───────────────────────┘
                                          ▼
              ┌────────────────────────────────────────────────────────┐
              │ DETECT: probe user / nodejs / npm-prefix / agents /     │  detect.sh + detect/*.sh
              │ sudoers  →  write /run/agentlinux-detect.json           │  (thin std::fs/subprocess readers)
              └─────────────────────────┬──────────────────────────────┘
                                        ▼
              ┌────────────────────────────────────────────────────────┐
              │ DECIDE (pure): reuse_gate / remediate_gate + user/node/ │  agentlinux-core gates
              │ sudoers/npm-prefix decisions → RESOLUTIONS map          │  (ALREADY PORTED)
              │  bail? → exit 65 (before any mutation)                   │
              └─────────────────────────┬──────────────────────────────┘
                                        ▼ (numeric-ordered, each idempotent)
        ┌──────────┬──────────────┬──────────────┬───────────────┬──────────────────┐
        ▼          ▼              ▼              ▼               ▼                  │
   10 user     20 sudoers     30 nodejs      40 path-wiring   50 registry-cli      │
   ensure_user visudo-gate    NodeSource     4 artefacts      cp CLI + symlink     │
   ensure_dir  0440 drop-in   curl|bash →    (profile.d,      into .npm-global/bin │
   locale      root:root      apt/dnf node   .bashrc-top,     + state/installed.d  │
   CLAUDE.md                  npmrc prefix   agentlinux.env,  + verify as_user     │
   (marker)                                  cron.d)                               │
        └──────────┴──────────────┴──────────────┴───────────────┴────────┬───────┘
                                                                          ▼
                                              agentlinux adopt --all (as install user, via dispatcher)
```
File-to-implementation mapping is in the Component Responsibilities table below; the diagram shows data flow only.

### Component Responsibilities (Bash source → Rust target)

| Bash source (`file:line`, LOC) | Rust target (recommended) | Nature |
|-------------------------------|---------------------------|--------|
| `plugin/bin/agentlinux-install` (616 LOC; flag parse, log tee, ERR/EXIT traps, `run_provisioners`, `main()` order, `run_purge`, `run_agent_adoption`) | `cmd/provision.rs` + `provision/mod.rs` | Orchestrator port. |
| `plugin/lib/idempotency.sh` (198) | `sysio.rs` — `write_file_atomic`, `ensure_line_in_file`, `ensure_marker_block`, `ensure_user`, `ensure_dir`, `visudo_validate` | **NEW systems I/O.** Byte-fidelity load-bearing. |
| `plugin/lib/distro_detect.sh` (115) | `distro.rs` — `detect_distro()` → `Family{Debian,Rhel}` + version | **NEW.** PROV-03. |
| `plugin/lib/pkg.sh` (226) | `pkg.rs` — `pkg_install`, `pkg_is_installed`, `pkg_remove`, `pkg_autoremove`, `nodesource_prereqs`, `nodesource_setup`, `nodesource_repo_paths`, `nodesource_module_reset`, `locale_ensure` | **NEW.** The apt↔dnf verb set (PROV-03). |
| `plugin/lib/as_user.sh` (54) | Reuse `dispatcher.rs` (Phase 56) — `sudo -u -H -E --` + invoker==target short-circuit; add `as_user_login` (`sudo -u -H -i --`) if adoption needs login-shell PATH | Mostly reused. |
| `plugin/provisioner/10-agent-user.sh` (143) | `provision/agent_user.rs` | ensure_user + ensure_dir + `locale_ensure` + CLAUDE.md marker block (DOC-02). |
| `plugin/provisioner/20-sudoers.sh` (71) | `provision/sudoers.rs` | visudo-gated 0440 root:root drop-in (ADR-012). |
| `plugin/provisioner/30-nodejs.sh` (174) | `provision/nodejs.rs` | NodeSource curl|bash + pkg_install node + npmrc prefix + npm-prefix remediation dispatch. |
| `plugin/provisioner/40-path-wiring.sh` (153) | `provision/path_wiring.rs` | The four six-mode artefacts. |
| `plugin/provisioner/50-registry-cli.sh` (142) | `provision/registry_cli.rs` | Stage CLI dist + catalog + symlink + state dir. (See §Registry-CLI note re: what the tarball ships.) |
| `plugin/lib/detect.sh` + `detect/*.sh` (107 + 6 files) | `provision/probe/*.rs` (thin readers) feeding the pure gates | Detection I/O. |
| `plugin/lib/reuse.sh` + `reuse/*.sh` (33 + 3) | Reuse `agentlinux-core::reuse` + `detect_gates` (ported); DELETE the Bash map | Decision layer wiring. |
| `plugin/lib/remediate.sh` + `remediate/*.sh` (299 + 4) | `agentlinux-core::detect_gates` (pure) + `provision/remediate/*.rs` (the state-overwrite I/O: chown/rebase npm prefix, overwrite sudoers, reinstall agent) | Decision pure; the mutation is I/O. |
| `plugin/lib/prompt.sh` (285) | Thin boundary — port only the non-TTY report + the bats-exercised paths | Interactive UX stays thin. |

### Pattern 1: Ordered idempotent steps dispatched on a resolved RESOLUTIONS map
**What:** `main()` collects ALL decisions up front (`remediate::collect_all_decisions` → `RESOLUTIONS[component]` ∈ {create,reuse,remediate,reuse-with-warning,bail}), flushes bails (`exit 65`) BEFORE any mutation, then each step dispatches on its pre-resolved token. `[VERIFIED: plugin/bin/agentlinux-install:579-610; each 10/20/30 step opens with `case "${RESOLUTIONS[X]:-create}" in`]`
**When to use:** Every provisioner step. The decide-then-act split is why a bailing host never sees partial mutation.
**Rust shape:** A `Resolutions` struct/map computed in `cmd/provision.rs` before the step loop; each `provision/*.rs` takes `&Resolutions` and matches its component token.

### Pattern 2: Family-branched pkg verbs (the ONE auditable apt↔dnf fork point)
**What:** Every apt-get/dpkg/dnf/rpm/locale-gen call collapses to a single verb in `pkg.sh`, branching exactly once on `AGENTLINUX_DISTRO_FAMILY`. The debian arm = the byte-for-byte Ubuntu command; the rhel arm = the EL9 equivalent. `[VERIFIED: plugin/lib/pkg.sh:30-226]`
**When to use:** Any package operation. Never inline `if family == rhel` at a call site.
**Rust shape:** `pkg.rs` with a `Family` enum and one `match` per verb — mirroring the Bash 1:1 so the AlmaLinux port (v0.3.5, already done once in Bash) is a mechanical translation.

### Pattern 3: Six-mode PATH wiring via four artefacts (additive, always runs)
**What:** PATH wiring runs UNCONDITIONALLY for both CREATE and REUSE — the artefacts are additive (marker block preserves user content; the three root-owned files are installer-owned). No RESOLUTIONS dispatch. `[VERIFIED: plugin/provisioner/40-path-wiring.sh:33-47]`
**When to use:** The path-wiring step. See §The Six-Mode PATH Matrix for the exact byte content of each file.

### Anti-Patterns to Avoid
- **Blind `echo >> file`** — forbidden; breaks INST-02 convergence. Every mutation goes through a grep-before-mutate / atomic-rename primitive. `[VERIFIED: idempotency.sh:5-9]`
- **`install -m … /dev/stdin <dest>`** — ENOENTs on uutils-coreutils (Ubuntu 26.04) when the dest exists. Use the same-dir-tmpfile + `install`/rename pattern (`write_file_atomic`). `[VERIFIED: idempotency.sh:20-62]` The Rust port must replicate: write tmpfile in the SAME directory as dest, then atomic rename.
- **Inline distro `if` at call sites** — collapse to a `pkg.rs` verb (Pattern 2).
- **`curl` in the rhel NodeSource prereqs** — EL9 has curl-minimal; installing `curl` conflicts. The rhel arm installs ONLY `ca-certificates`. `[VERIFIED: pkg.sh:104-119, Pitfall 6]`
- **Wrapper shim under `/usr/local/bin`** — the canonical self-update bug.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Marker-block idempotent edit | A regex sed-replace | Port `ensure_marker_block`'s awk line-filter verbatim | Byte-exact output the `.bashrc` bats grep; `--top` placement is load-bearing (before the skel non-interactive early-return). `[VERIFIED: 40-path-wiring.sh:92-114; idempotency.sh:94-147]` |
| Atomic file write w/ mode | `fs::write` + `set_permissions` | Same-dir tmpfile → `install`/rename (`write_file_atomic`) | Atomicity + uutils /dev/stdin bug avoidance; cross-fs rename loses atomicity. `[VERIFIED: idempotency.sh:39-62]` |
| Ensure user | raw `useradd` | `ensure_user` (id-check then `useradd --create-home --shell /bin/bash --user-group`) | Idempotent; never modifies an existing user's identity. `[VERIFIED: idempotency.sh:151-163]` |
| sudoers drop-in | write then hope | visudo `-cf` gate BEFORE install + post-install re-verify (TOCTOU belt), atomic 0440 root:root | A malformed sudoers locks out sudo host-wide. `[VERIFIED: remediate/sudoers.sh; 20-sudoers.sh:26-59]` |
| NodeSource pin | `apt install nodejs` from distro | Run the pinned `setup_22.x` script then `pkg_install nodejs` | Distro nodejs is too old; the setup script pins the repo + gpgkey (ADR-005). `[VERIFIED: pkg.sh:121-138; 30-nodejs.sh:59-111]` |
| Version classify / divergence / gates | Re-derive in the entrypoint | `agentlinux-core` (already ported) | Property + mutation tested; the whole point of the rewrite. `[VERIFIED: rust/crates/agentlinux-core/src/*]` |
| Subprocess dispatch | `Command::spawn` + manual kill | `dispatcher.rs` (Phase 56) | Tee + timeout + SIGTERM→SIGKILL + invoker==target short-circuit already pinned by unit tests. `[VERIFIED: rust/crates/agentlinux/src/dispatcher.rs]` |

**Key insight:** In this domain, the "same observable state" bar means the port must produce byte-identical file contents, modes, and owners — so hand-rolling a "cleaner" primitive that emits even a trailing-newline difference will fail the bats. Port the primitives faithfully, not idiomatically.

## The Entrypoint + Step Order

`plugin/bin/agentlinux-install` (616 LOC) is the sole entrypoint. Its `main()` sequence `[VERIFIED: :452-613]`:

1. `parse_args` — flags: `--help`/`--version` (pre-parsed before log init, :100-116), `--verbose`, `--purge`, `--remove-nodejs`, `--report-only`, `--report-format=text|json`, `--user=NAME`, `--yes`/`--no-yes` (contradiction-checked), `--dry-run` (contradicts `--yes`). Exit codes: **0** success, **1** runtime, **64** usage, **65** data/incompatible-host-state. `[VERIFIED: :46-93 usage; :196-290 parse_args]`
2. Log init: `install -m 0644 /dev/null $LOG_FILE`, then `exec > >(tee -a $LOG_FILE) 2>&1`, save tee PID, EXIT trap closes FDs + waits tee (avoids deadlock), ERR trap logs `src:line` + exit code. `[VERIFIED: :118-152]` — **Rust port:** dup stdout/stderr through a tee thread OR write directly + mirror to log; the observable is the transcript at `/var/log/agentlinux-install.log`. Bats greps the log (e.g. INST-05 "no EACCES on second run"). Preserve the log path + no-EACCES content.
3. Source order: `log.sh` → `distro_detect.sh` → `pkg.sh` → `idempotency.sh` → `as_user.sh`. `[VERIFIED: :140-165]` (Rust: all one binary; no sourcing.)
4. `main()`: `parse_args` → source `remediate.sh` (for `validate_user_name`/`user_adoptable`) → AGENTLINUX_USER env fallback → parse-time user-name validation (exit 64) → `require_root` (EUID≠0 → exit 64) → `user_adoptable` gate (refuse UID<1000 → exit 64) → `--purge` branch → optional interactive user prompt (greenfield TTY only) → `detect_distro` → `ensure_jq` → `detect::run_once` → source `reuse.sh` → `--report-only` short-circuit (emit report, exit 0) → alt-user gate → `remediate::collect_all_decisions` → `--dry-run` early-return (exit 0) → `flush_bails_or_continue` (exit 65 on any bail) → TTY per-action prompt loop → **`run_provisioners`** → `run_agent_adoption`. `[VERIFIED: :452-613]`
5. `run_provisioners`: `compgen -G "$PROV_DIR/[0-9][0-9]-*.sh" | sort` then source each in numeric order. `[VERIFIED: :313-330]` — **Rust:** a fixed ordered `[agent_user, sudoers, nodejs, path_wiring, registry_cli]` step vec (no filesystem glob).
6. `run_agent_adoption`: `as_user_login "$user" agentlinux adopt --all` (best-effort; a failure must not fail the install). `[VERIFIED: :341-346]` — reuses the Phase-56 `adopt` verb + dispatcher.

**Recommended Rust entrypoint shape:** `agentlinux provision [flags]` as a clap subcommand (add `Provision(ProvisionArgs)` to `cli.rs`'s `Command` enum; dispatch in `main.rs::dispatch`). The CLI-05 guard in `dispatch` (`guard_agent_user`) currently exits 64 for a non-install-user invoker — **`provision` must run as ROOT**, so it needs a DIFFERENT guard (`require_root`, EUID==0) rather than the agent-user guard. Add a `verb_name` arm that skips `guard_agent_user` for `provision` and instead asserts root. `[VERIFIED: main.rs:162-178 dispatch runs guard for every verb; agentlinux-install:305-310 require_root]`

## Each Provisioner Step

### 10-agent-user.sh → `provision/agent_user.rs` `[VERIFIED: plugin/provisioner/10-agent-user.sh]`
- **Dispatch** on `RESOLUTIONS[user]` ∈ {create, reuse, remediate (=reuse here), reuse-with-warning, bail}. REUSE skips useradd+locale; CLAUDE.md + path-wiring still run. (:28-55)
- **Observable output (CREATE):** (1) `ensure_user <user>` → `/home/<user>`, shell `/bin/bash`, matching user-group; (2) `ensure_dir /home/<user> 0755 <user>:<user>`; (3) `locale_ensure C.UTF-8` (writes `/etc/default/locale` on debian, `/etc/locale.conf` on rhel; both end with a `locale -a` grep gate); (4) `ensure_marker_block /home/<user>/CLAUDE.md agentlinux-doc-02 --top` with the DOC-02 body, then `chmod 0644` + `chown <user>:<user>`. (:59-141)
- **Byte-fidelity anchors the bats grep:** the DOC-02 body MUST keep the three anti-pattern strings `usr/local/bin`, `sudo npm install -g`, `second Node.js install`. `[VERIFIED: :84]`
- **Idempotency:** `ensure_user` is id-check-gated; `ensure_dir` re-asserts mode+owner; `ensure_marker_block` replaces the block (user content outside survives).
- **New I/O vs. wiring:** genuinely-new (useradd, locale files, marker-block write). Decision is wiring (RESOLUTIONS[user] from ported gate).

### 20-sudoers.sh → `provision/sudoers.rs` `[VERIFIED: plugin/provisioner/20-sudoers.sh]`
- `pkg_install sudo` if `visudo` absent (:26-29). `ensure_dir /etc/sudoers.d 0755 root:root`.
- **Dispatch** on `RESOLUTIONS[sudoers]` ∈ {reuse (no-op), remediate (overwrite, --yes-gated), create (install), reuse-with-warning, bail}. Both create+remediate route through `remediate::sudoers::install_or_overwrite` (single source). (:41-71)
- **Observable output:** `/etc/sudoers.d/agentlinux`, mode **0440 root:root**, visudo-clean, byte-stable; content = static header + `<user> ALL=(ALL) NOPASSWD: ALL`. Satisfies BHV-07 + INST-06 + REMEDIATE-03. `[VERIFIED: remediate/sudoers.sh:36-49]`
- **visudo gate:** validate the tmpfile BEFORE install AND re-verify after (TOCTOU belt). `[VERIFIED: remediate/sudoers.sh:27-28]`
- **New I/O vs. wiring:** genuinely-new (visudo-gated atomic 0440 write). Decision wiring.

### 30-nodejs.sh → `provision/nodejs.rs` — see §NodeSource Install (the chicken-and-egg crux).

### 40-path-wiring.sh → `provision/path_wiring.rs` — see §The Six-Mode PATH Matrix.

### 50-registry-cli.sh → `provision/registry_cli.rs` `[VERIFIED: plugin/provisioner/50-registry-cli.sh]`
- Stages `/opt/agentlinux/cli/<ver>/{dist,node_modules,package.json}` + `/opt/agentlinux/catalog/<ver>/` + `/opt/agentlinux/state/installed.d/` (empty — CAT-02) + symlinks `~/.npm-global/bin/agentlinux → …/dist/index.js`. (:84-126)
- Verifies the symlink is executable **as the install user** (`as_user <user> test -x $SYMLINK`). (:137-140)
- **CRITICAL Phase-57/58 note:** this step currently stages the **TypeScript CLI bundle** (dist/index.js + node_modules). Phase 57's job is the *provisioner* port, NOT the distribution channel (that's Phase 58 — musl tarball as sole channel). **Decision needed (see §Open Questions Q1):** does the Rust `provision` step (a) keep staging the TS bundle (symlink → dist/index.js) for now, matching master's observable state and letting Phase 58 swap it for the musl binary, or (b) stage the Rust binary itself? Recommendation: **(a)** — keep the TS-bundle staging observable identical this phase (the `run.sh` harness already re-points the symlink at the Rust bin under `AGENTLINUX_STAGE_RUST_CLI=1`, `[VERIFIED: tests/docker/run.sh:277-331]`), and defer the "stage the musl binary" swap to Phase 58 where DIST-01 explicitly owns it. This keeps Phase 57 a pure provisioner port and preserves per-phase rollback (GATE-05).
- **New I/O vs. wiring:** genuinely-new (cp tree + symlink + state dir). No decision dispatch (runs unconditionally, INST-02 idempotent).

## Idempotency Primitives (`idempotency.sh` → `sysio.rs`)

The six primitives, with the exact semantics the Rust port must preserve `[VERIFIED: plugin/lib/idempotency.sh]`:

| Primitive | Semantics | Rust port notes |
|-----------|-----------|-----------------|
| `write_file_atomic <mode> <dest>` (stdin body) | tmpfile in SAME dir as dest (`mktemp -p $dir .$base.XXXXXX`), `cat > tmp`, `install -m <mode> tmp dest`, RETURN-trap `rm tmp`. Avoids the uutils `/dev/stdin` ENOENT bug. (:39-62) | `std::fs::File` in dest's parent dir + `fs::rename` (atomic same-fs) + `set_permissions(mode)`. Unlink tmp on all paths (RAII / Drop). |
| `ensure_line_in_file <line> <file>` | `grep -Fxq -- <line> <file>` else `printf '%s\n' >> file`. Whole-line fixed-string match. (:71-81) | Read lines, exact-match, append if absent. Preserve the trailing `\n`. |
| `ensure_marker_block <file> <tag> [--top\|--bottom]` (stdin body) | awk-strip lines between `# >>> <tag> begin >>>`/`# <<< <tag> end <<<`, re-emit block at placement, `install -m 0644 tmp file`. Default `--bottom`; `--top` required for `.bashrc`. (:94-147) | Port the awk line-filter exactly. `--top` = block THEN filtered-existing; `--bottom` = filtered-existing THEN block. Byte-exact begin/end marker strings. |
| `ensure_user <name>` | id-check → `useradd --create-home --shell /bin/bash --user-group <name>`. No-op if exists (never modifies existing). (:151-163) | `Command::new("useradd")`; check via `nix::unistd::User::from_name`. |
| `ensure_dir <path> <mode> <user:group>` | absent → `install -d -m <mode> -o <u> -g <g>`; present → `chmod <mode>` + `chown <u>:<g>` (corrects out-of-band drift). (:168-181) | `fs::create_dir_all` + `set_permissions` + `nix chown` (resolve u/g via `User::from_name`/`Group::from_name`). Re-assert on existing. |
| `visudo_validate <file>` | `visudo -cf <file>` → non-zero fails. (:187-198) | `Command::new("visudo").args(["-cf", file])`. |

**Byte-fidelity is load-bearing:** the bats assert file **content + mode + owner** across the six modes; a trailing-newline or ordering difference fails. Port the emit order verbatim (e.g. `ensure_marker_block --top` emits `begin\n` `content\n` `end\n` THEN the filtered remainder).

## Distro Detection + Pkg Abstraction (PROV-03 parity surface)

### `distro_detect.sh` → `distro.rs` `[VERIFIED: plugin/lib/distro_detect.sh]`
- Reads `/etc/os-release` (override via `AGENTLINUX_OS_RELEASE_PATH` — a bats seam). Exports `AGENTLINUX_DISTRO_FAMILY` ∈ {debian, rhel} + `AGENTLINUX_DISTRO_VERSION`.
- **Exact-ID match** (never the similarity field): `ubuntu` + VERSION_ID ∈ {22.04, 24.04, 26.04} → debian; `almalinux` + VERSION_ID ∈ {9, 9.*} → rhel; everything else refused (Rocky/RHEL/CentOS/Fedora + AlmaLinux 8/10 stay refused). (:83-114)
- Escape hatch `AGENTLINUX_SKIP_DISTRO_CHECK=1` (dev/bats only) seeds family from ID or defaults debian. (:48-66)
- **Rust:** a `detect_distro(os_release_path) -> Result<(Family, String)>`; honor the two env seams (the `18-distro-detect.bats`/`18-detect-el9.bats` fixtures drive them — 15+7 @tests).

### `pkg.sh` → `pkg.rs` — every branch point `[VERIFIED: plugin/lib/pkg.sh]`
| Verb | debian arm | rhel arm |
|------|-----------|----------|
| `pkg_install <pkg…>` | `apt-get update` + `apt-get install -y --no-install-recommends` | `dnf install -y --setopt=install_weak_deps=False` |
| `pkg_is_installed <pkg>` | `dpkg-query -W -f='${Status}' … \| grep "install ok installed"` | `rpm -q` |
| `pkg_remove <pkg…>` | `apt-get purge -y` | `dnf remove -y` |
| `pkg_autoremove` | `apt-get autoremove -y` | `dnf autoremove -y` |
| `nodesource_prereqs` | install `curl gnupg ca-certificates apt-transport-https` (cache-refresh first) | install ONLY `ca-certificates` (NEVER curl — curl-minimal conflict; no gnupg/apt-transport-https on EL9) |
| `nodesource_setup` | `curl -fsSL https://deb.nodesource.com/setup_22.x \| bash -` | `curl -fsSL https://rpm.nodesource.com/setup_22.x \| bash -` |
| `nodesource_repo_paths` | `/etc/apt/sources.list.d/nodesource.sources` + `.list` + `/etc/apt/preferences.d/nodejs` | `/etc/yum.repos.d/nodesource-nodejs.repo` + `nodesource-nsolid.repo` |
| `nodesource_module_reset` | no-op | `dnf -y module reset nodejs \|\| true` (defuse AppStream module — Pitfall 4) |
| `locale_ensure C.UTF-8` | install `locales` if `locale-gen` absent, `locale-gen C.UTF-8`, `update-locale LANG/LC_ALL`, write `/etc/default/locale`, `locale -a` grep gate | write `/etc/locale.conf` (atomic), `locale -a` grep gate (no locale-gen; glibc-langpack provides C.UTF-8) |
- All apt commands set `DEBIAN_FRONTEND=noninteractive`. `[VERIFIED: :33,69,85,107,203]`
- **Mirror the v0.3.5 AlmaLinux Bash port:** the rhel arms already exist and are proven green — the Rust port is a mechanical 1:1 translation of each `case` arm. `[MEMORY: project_v0_3_5_almalinux — apt→dnf port done once in Bash; behavior contract held; PRs #42+#44]`
- **Bats oracle:** `18-distro-detect` (15), `18-pkg-dispatch` (20), `18-detect-el9` (7) — these unit-source the libs today; the Rust port must satisfy the same seams (see §Acceptance Oracle for how unit-sourcing bats port over).

## PROV-02 Map Consolidation

**Current state (the single remaining Bash duplication):**
- Bash: `REUSE_AGENT_CANONICAL_PATHS` (claude-code, gsd, playwright-cli) + `REUSE_GSD_SYSTEM_PATH` in `plugin/lib/reuse/agents.sh:38-53`. `[VERIFIED]`
- Rust: `main.rs::canonical_path(id)` + `GSD_SYSTEM_PATH` const — already the twin. `[VERIFIED: rust/crates/agentlinux/src/main.rs:35-49]`
- TS: `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` in `detect.ts:16-28` — retires with the TS bundle (Phase 58).

**The two external consumers of the Bash map** (the reason it wasn't deleted in Phase 56) `[VERIFIED]`:
1. `remediate.sh:286-296` — iterates `${!REUSE_AGENT_CANONICAL_PATHS[@]}` to enumerate per-agent decisions (`RESOLUTIONS[agents.$id]=$(reuse::agent_decision $id)` + gate-or-bail on remediate).
2. `prompt.sh:110-114` — iterates the same keys to render the per-agent report block.

**Recommended consolidation:** The Rust `provision` entrypoint OWNS the per-agent iteration end-to-end. The ordered flow becomes: after detection, the entrypoint iterates the Rust `canonical_path` map's known ids (claude-code, gsd, playwright-cli), calls the ported `reuse_gate`/`remediate_gate`/`agent_decision` directly (no per-id `agentlinux reuse-decision` shell-out), builds `RESOLUTIONS[agents.<id>]`, and drives the adoption. **Then delete** the Bash `REUSE_AGENT_CANONICAL_PATHS`/`REUSE_GSD_SYSTEM_PATH` map, the `reuse::agent_decision` Rust-else-bash shim + `reuse::_agent_decision_bash` fallback, and the `remediate.sh`/`prompt.sh` iterators — because with the Rust entrypoint as the sole orchestrator, no Bash consumer survives.

**Desync guard:** to prevent the Rust map drifting from any lingering Bash need, the recommended bridge (if ANY Bash still needs the id list — e.g. a bats fixture) is a `agentlinux provision --print-canonical-map` / hidden debug verb that prints the map from the single Rust source. But the target is **zero** Bash consumers: the map lives once, in `main.rs`. **Confirm at plan time** that no bats @test greps `REUSE_AGENT_CANONICAL_PATHS` directly (they don't in the current tree — the map is consumed only by the two libs above; `13-reuse.bats` drives the DECISION via `agentlinux reuse-decision` + env vars, not the map). `[VERIFIED: grep REUSE_AGENT_CANONICAL_PATHS → only reuse/agents.sh + remediate.sh + prompt.sh]`

## The Detect / Remediate / Reuse Wiring

The deciders are pure + ported; Phase 57 wires them into the provision flow. `[VERIFIED: rust/crates/agentlinux-core/src/{detect_gates,reuse}.rs; plugin/lib/{detect,reuse,remediate}.sh]`

**Detection I/O (the NEW thin readers feeding the gates):** `detect::run_once` runs 5 probes into JSON fragments merged to `/run/agentlinux-detect.json` (tmpfs). `[VERIFIED: detect.sh:45-93]`
- `detect/user.sh` (108) — user exists? home? UID.
- `detect/nodejs.sh` (208) — node version (matches `^v?22\.`?), NodeSource repo present (via `nodesource_repo_paths` gate).
- `detect/npm_prefix.sh` (143) — `.npm-global` writable by the install user? (feeds REMEDIATE-01 chown/rebase).
- `detect/agents.sh` (261) — per-agent status (healthy/broken/absent) + resolved path (feeds the reuse/remediate/presence gates).
- `detect/sudoers.sh` (81) — `/etc/sudoers.d/agentlinux` present? canonical ADR-012 line present? (feeds the sudoers decision).

**Decision (pure, ported):** `remediate::collect_all_decisions` builds `RESOLUTIONS[{user,node,npm-prefix,sudoers,agents.<id>}]` from the DETECT_* exports via the gates, gating state-overwrites behind `--yes` (`gate_or_bail`), accumulating bails. `[VERIFIED: remediate.sh:264-299]` The Rust entrypoint calls the ported gates with the probed inputs (the cache adapter `cache.rs` already reads `/run/agentlinux-detect.json` — Phase 56).

**Mutation I/O (the remediate ACTIONS — NEW):** on `remediate` tokens: `remediate::nodejs::chown_or_rebase` (npm prefix, 228 LOC — chown vs rebase strategy selector), `remediate::sudoers::install_or_overwrite` (86), `remediate::user` (37), `remediate/agents.sh` (25 — reinstall). These are the state-overwriting I/O the entrypoint runs when RESOLUTIONS says `remediate` and `--yes` gated it.

**Rust wiring shape:** `cmd/provision.rs` → probe (thin readers, `provision/probe/*.rs`) → write detect cache → call pure gates → `Resolutions` → for each remediate action, call the corresponding `provision/remediate/*.rs` I/O. Reuse `cache.rs` (Phase 56) for the detect-cache read used by adoption.

## NodeSource Install (the chicken-and-egg crux)

`30-nodejs.sh` is where the compiled-binary payoff lands: it installs Node when NO Node exists. `[VERIFIED: plugin/provisioner/30-nodejs.sh]`

**Sequence (CREATE path, :57-142):**
1. `nodesource_prereqs` — debian: curl/gnupg/ca-certificates/apt-transport-https; rhel: ca-certificates only. (installer-log visibility; the setup script re-installs its own.)
2. `nodesource_module_reset` — rhel-only `dnf -y module reset nodejs` (Pitfall 4); no-op debian.
3. **Idempotent NodeSource repo add:** gate on `nodesource_repo_paths` — if ANY family repo file present, short-circuit; else `nodesource_setup` (`curl -fsSL https://{deb,rpm}.nodesource.com/setup_22.x | bash -`). Integrity = HTTPS + `curl -f` cert-verify + the GPG-signed repo (ADR-005; no body SHA — NodeSource publishes none). The setup script `rm -f`s repo files before recreating, so a missed gate self-heals byte-clean. (:84-96)
4. `pkg_install nodejs` — apt/dnf install, repo-pinned to 22.x.
5. **Post-install verify (RT-01):** `node --version` → major must be ≥ 22, else `return 1`. (:106-110)
6. **npm prefix layout (RT-04):** `ensure_dir ~/.npm-global{,/bin,/lib} 0755 <user>:<user>` (proactively agent-owned so `npm install -g` never races root). (:120-129)
7. **`~/.npmrc` prefix line:** create-if-absent (`install -m 0644 -o <user> -g <user> /dev/null`) then `ensure_line_in_file "prefix=~/.npm-global"` + re-chown/chmod. (:134-142)
8. **npm-prefix remediation dispatch (REMEDIATE-01):** runs unconditionally after the create/reuse split — `RESOLUTIONS[npm-prefix]` ∈ {reuse, create, remediate (`chown_or_rebase`), reuse-with-warning, bail}. (:146-172)

**Rust port:** run the NodeSource `curl … | bash -` via the Phase-56 dispatcher (it already does buffered/streamed exec with timeout). The apt/dnf calls go through `pkg.rs`. **Crux constraint:** this MUST work with only the static musl binary on a bare host — no Node, no npm, no jq initially (`ensure_jq` installs jq mid-flow via `pkg_install`, :295-303). The Rust bin is self-contained (musl static), so it has no such bootstrap gap for ITSELF; it shells to curl/apt/dnf which the base image ships (or apt provides). **Confirm** curl availability on the rhel prereq path (the setup script needs curl; rhel installs ca-certificates but the base almalinux:9 image must have curl-minimal for the pipe — the Bash relies on this today, so it holds). `[VERIFIED: pkg.sh:104-138]`

## The Six-Mode PATH Matrix

`40-path-wiring.sh` writes **four artefacts**, each guaranteeing PATH/locale for specific invocation modes. `[VERIFIED: plugin/provisioner/40-path-wiring.sh]` Ordering invariant: user-owned prefixes FIRST (`.npm-global/bin`, `.local/bin`) then system — prevents path-injection.

| # | Artefact | Mode + owner | Covers | Exact content (byte-critical) |
|---|----------|--------------|--------|-------------------------------|
| 1 | `/etc/profile.d/agentlinux.sh` | 0644 root:root | interactive login (BHV-06) + `sudo -u -i` (BHV-05) | Re-source guard (`AGENTLINUX_PROFILE_SOURCED`), `export LANG/LC_ALL="${…:-C.UTF-8}"`, `export AGY_CLI_DISABLE_AUTO_UPDATE=true`, two `case ":$PATH:"` guarded prepends (.local/bin then .npm-global/bin, LIFO → .npm-global/bin ends FIRST), `export PATH`. Written via `write_file_atomic 0644`. Heredoc UNQUOTED (`${_AL_HOME}`/`${_AL_USER}` interpolate); runtime `\$PATH` escaped. (:61-90) |
| 2 | `<home>/.bashrc` marker block `agentlinux-path` `--top` | 0644 user:user | non-interactive SSH (BHV-02) + `sudo -u bash -c` | `if [ -f /etc/profile.d/agentlinux.sh ]; then . /etc/profile.d/agentlinux.sh; fi`. `--top` places it BEFORE the skel `.bashrc` non-interactive early-return (`case $- in *i*) ;; *) return;; esac`) so those modes still get PATH. Create empty user-owned file first if absent; re-chown/chmod after (marker-block leaves root-owned). Body is a QUOTED heredoc (literal). (:92-114) |
| 3 | `/etc/agentlinux.env` | 0644 root:root | systemd `User=agent` EnvironmentFile (BHV-04) | Literal `KEY=VALUE` (no `export`, no expansion — systemd/cron parse literally): `PATH=<home>/.npm-global/bin:<home>/.local/bin:/usr/local/bin:/usr/bin:/bin`, `NPM_CONFIG_PREFIX=<home>/.npm-global`, `AGENTLINUX_USER=<user>`, `AGENTLINUX_AGENT_HOME=<home>`, `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`, `AGY_CLI_DISABLE_AUTO_UPDATE=true`. The PATH line MUST be byte-identical to artefact 4's (cross-grep enforced). `AGENTLINUX_USER`/`AGENTLINUX_AGENT_HOME` are the runtime source-of-truth the CLI reads (`recipe_env.rs` reads this file, :107). (:116-133) |
| 4 | `/etc/cron.d/agentlinux` | 0644 root:root | cron (BHV-03) | Comment header (example job, do-NOT-uncomment) + `PATH=<same as artefact 3>` + `LANG`/`LC_ALL`/`AGY_CLI_DISABLE_AUTO_UPDATE`. vixie-cron does NOT expand `$PATH` → fully-expanded literal. No default jobs. (:135-151) |

Also: `ensure_dir <home>/.local{,/bin} 0755 <user>:<user>` (so the PATH prefix isn't dangling). Runs UNCONDITIONALLY (additive; no RESOLUTIONS dispatch). REUSE emits a `[REMEDIATE-02]` marker. `[VERIFIED: :33-52]`

**Rust port:** artefacts 1/3/4 via `write_file_atomic`; artefact 2 via `ensure_marker_block --top`. The interpolation (`_AL_HOME`/`_AL_USER`) is just `format!`; the escaped runtime vars stay literal in the emitted string. **For the default user `agent` the emitted bytes must be identical to master** (the RT-* + BHV-* bats grep these files across all six modes). `recipe_env.rs::canonical_path` already emits the exact PATH string — reuse it for artefacts 3/4. `[VERIFIED: recipe_env.rs:129-131]`

## Runtime State Inventory

> This is a like-for-like port, not a rename — but it touches privileged host state. Explicit inventory:

| Category | Items | Action Required |
|----------|-------|------------------|
| Stored data | `/run/agentlinux-detect.json` (tmpfs detect cache) — read by adoption; `/opt/agentlinux/state/installed.d/<id>.json` sentinels | Rust `cache.rs`/`sentinel.rs` already read/write these (Phase 56). No migration — same paths, same JSON shape. |
| Live service config | None registered by the provisioner (no default cron jobs, no systemd units shipped — `/etc/cron.d/agentlinux` ships headers only; systemd consumes `/etc/agentlinux.env` but the provisioner registers no unit). | None. |
| OS-registered state | The agent USER (`/etc/passwd`), the sudoers drop-in (`/etc/sudoers.d/agentlinux`), the NodeSource apt/dnf repo (`/etc/apt/sources.list.d/…` / `/etc/yum.repos.d/…`) | The Rust port creates these identically. `--purge` (agentlinux-install:363-450) must also port (userdel -r, rm repo files via `nodesource_repo_paths`, rm PATH artefacts + sudoers). Confirm `provision --purge` parity at plan time. |
| Secrets / env vars | None baked. `AGENTLINUX_USER`/`AGENTLINUX_AGENT_HOME` in `/etc/agentlinux.env` are identity, not secrets. | None. |
| Build artifacts | `/opt/agentlinux/cli/<ver>/` (TS bundle staged today — Phase 58 swaps to musl binary); the musl `agentlinux` bin itself | Registry-CLI step stages the TS bundle this phase (Open Q1); Phase 58 owns the musl-tarball swap. |

## Common Pitfalls

### Pitfall 1: uutils `/dev/stdin` ENOENT on re-run (Ubuntu 26.04)
**What goes wrong:** `install -m … /dev/stdin <dest>` succeeds on first run, ENOENTs on idempotent re-run when dest exists (uutils readlink-chases /dev/stdin → pipe:[N] → stat fails). **Avoid:** same-dir tmpfile + atomic rename (`write_file_atomic`). The Rust `fs::rename` is naturally immune, but keep the same-dir constraint (cross-fs rename loses atomicity). `[VERIFIED: idempotency.sh:20-38]`

### Pitfall 2: `.bashrc` block below the non-interactive early-return
**What goes wrong:** Ubuntu skel `.bashrc` early-returns for non-interactive shells; a block placed `--bottom` never runs for `ssh host 'cmd'` / `sudo -u bash -c`. **Avoid:** `--top` placement (mandatory for artefact 2). `[VERIFIED: 40-path-wiring.sh:92-98]`

### Pitfall 3: `secure_path` shadows inherited PATH under sudo
**What goes wrong:** `sudo -E` preserves env but sudoers `secure_path` overrides PATH → recipes resolve `npm` from `/usr/bin` (EACCES). **Avoid:** set PATH EXPLICITLY in the child env (not via `-E`). `recipe_env.rs::full_child_env` already does this. `[VERIFIED: recipe_env.rs:128-152]`

### Pitfall 4: AppStream nodejs module wins over NodeSource (EL9)
**What goes wrong:** the distro's `nodejs` module shadows the NodeSource repo → wrong version. **Avoid:** `dnf -y module reset nodejs` before install (rhel-only). `[VERIFIED: pkg.sh:165-178]`

### Pitfall 5: `curl` in EL9 NodeSource prereqs conflicts with curl-minimal
**What goes wrong:** `dnf install curl` on EL9 conflicts with the pre-installed curl-minimal. **Avoid:** rhel prereqs install ONLY ca-certificates. `[VERIFIED: pkg.sh:104-119]`

### Pitfall 6: PATH ordering flips reuse→remediate / injects a shim
**What goes wrong:** system prefix before user prefix lets a `/usr/local/bin` shim win → the self-update bug. **Avoid:** user-owned prefixes FIRST in every artefact. `[VERIFIED: 40-path-wiring.sh:75-88]`

### Pitfall 7: CLI-05 guard would block `provision`
**What goes wrong:** `dispatch` runs `guard_agent_user` for every verb (exit 64 if invoker ≠ install user) — but `provision` runs as ROOT. Applying the agent-user guard would reject the root invoker. **Avoid:** `provision` uses `require_root` (EUID==0), NOT `guard_agent_user`. `[VERIFIED: main.rs:162-178; agentlinux-install:305-310]`

### Pitfall 8: bats unit-source the Bash libs directly
**What goes wrong:** `18-distro-detect`/`18-pkg-dispatch`/`14-remediate`/`13-reuse` `source` the Bash lib functions and call them directly (not the binary). Deleting/porting a lib without a bin-level equivalent orphans those @tests. **Avoid:** see §Acceptance Oracle — decide per-file whether the @test exercises OBSERVABLE state (survives the port unchanged) or a Bash-internal function (needs a bin subcommand seam or the @test rewires to the bin). `[VERIFIED: test counts — 18-pkg-dispatch:20, 14-remediate:56, 13-reuse:32 unit-style]`

## Acceptance Oracle + Staging

### Bats file map (provisioner surface)
| File | @tests | Surface | Docker-runnable now? |
|------|--------|---------|----------------------|
| `10-installer.bats` | 11 | Entrypoint flags/usage/exit-codes | Yes |
| `13-reuse.bats` | 32 | reuse-decision (`agentlinux reuse-decision` + env) | Yes (already Rust via shim) |
| `14-remediate.bats` | 56 | remediate decisions + actions | Mostly — some need real host state |
| `15-detection.bats` | 25 | detect probes + report | Yes |
| `18-distro-detect.bats` | 15 | distro_detect (unit-source) | Yes |
| `18-pkg-dispatch.bats` | 20 | pkg verbs (unit-source, apt↔dnf) | Yes |
| `18-detect-el9.bats` | 7 | EL9 detection | Yes (Docker almalinux:9) |
| `20-agent-user.bats` | 14 | user creation, locale, CLAUDE.md | Yes |
| `22-agent-sudo.bats` | 7 | sudoers drop-in 0440, NOPASSWD | Yes |
| `23-install-user.bats` | 9 | alt-user (AL-50) install + INST-02-under-flag | Yes |
| `30-runtime.bats` | 5 | Node 22, npm prefix, RT-* across 6 modes | **Partial** — systemd/cron modes need systemd (→ QEMU/Phase 59) |
| `50-agents.bats` | 12 | AGT-* real installs + adoption | Partial — real recipe installs; systemd-gated cases → 59 |

**Six-mode matrix** (`tests/bats/helpers/invoke_modes.bash`): interactive (`su - agent -c`), ssh, cron (polls ≤70s), systemd_user (SKIPs loudly if systemd absent — exit 75), sudo_u, sudo_u_i. `[VERIFIED: helpers/invoke_modes.bash]` The systemd_user + cron modes are the ones Docker can't fully exercise → those assertions are **Phase 59 (QEMU)**; Docker runs interactive/ssh/sudo_u/sudo_u_i now.

### Staging strategy (extend the Phase-56 `run.sh` pattern)
- Today `run.sh:238` runs the **Bash** `agentlinux-install`. `[VERIFIED]`
- **Phase 57:** add an `AGENTLINUX_PROVISION_RUST=1` gate that instead runs `agentlinux provision` (the staged musl bin) as the provisioner, THEN runs bats. On master (flag unset) the Bash entrypoint stays authoritative (GATE-05 rollback). Mirror the fail-loud guard the CLI-symlink override uses (abort if the flag is set but the bin is absent — no false-green). `[VERIFIED: run.sh:277-331 pattern]`
- The `AGENTLINUX_STAGE_RUST_CLI=1` CLI-symlink override + `AGENTLINUX_RUST_BIN` reuse-shim export already exist — Phase 57 adds the provisioner-level equivalent.
- **Docker OOM:** the full bats suite OOMs ~test 131 in this VM `[MEMORY: reference_docker_oom]` → run targeted per-file (`bats tests/bats/30-runtime.bats`) or per-target containers.
- **For the unit-source bats (18-*, 14-*, 13-*):** these call Bash lib functions. As the libs are ported/deleted, decide per-file: (a) keep the Bash lib as a thin shim that shells to the bin for the ported logic (like `reuse/agents.sh` does today — the try-Rust-else-bash shim, `[VERIFIED: reuse/agents.sh:76-108]`), OR (b) rewrite the @test to drive the bin subcommand. Recommendation: extend the shim pattern for `distro_detect`/`pkg` during the port so `18-*` stays green without rewrites, then retire shims where the map-consolidation deletes the Bash entirely. **Confirm the shim-vs-rewrite choice per unit-source file at plan time.**

### Docker-now vs QEMU/Phase-59
- **Runnable in Docker now:** 10/13/14(most)/15/18-*/20/22/23 + the interactive/ssh/sudo_u/sudo_u_i modes of 30/50.
- **Phase 59 (real systemd/QEMU):** the systemd_user + cron modes of `30-runtime`/`50-agents`, AGT-02 self-update against the live CDN, full-matrix (22/24/26 + AlmaLinux 9 QEMU).

## State of the Art

| Old Approach | Current Approach | When | Impact |
|--------------|------------------|------|--------|
| Bash provisioner sourced as ordered `NN-*.sh` fragments | Rust `provision` subcommand with a fixed ordered step vec | This phase | Untestable Bash → property/mutation-testable Rust running PRE-Node from a static binary |
| Duplicated `CANONICAL_PATHS` in TS + Bash + Rust | Single Rust source (`main.rs`) | This phase (PROV-02) | Drift-proof; the Bash map + fallback retire |
| `install -m … /dev/stdin` | same-dir tmpfile + atomic rename | Already (uutils fix) | Ported as `write_file_atomic` |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The registry-CLI step should keep staging the **TS bundle** this phase (defer the musl-binary swap to Phase 58) | §Each Provisioner Step (50) / Open Q1 | If wrong, Phase 57 also owns DIST-01's binary staging — larger scope, blurs the phase boundary. Recommend confirming in discuss/plan. |
| A2 | No bats @test greps `REUSE_AGENT_CANONICAL_PATHS` directly (only the two libs consume it), so deleting the Bash map is safe | §PROV-02 | If a fixture greps it, deletion breaks that @test. VERIFIED via grep this session — low risk, but re-confirm at plan time. |
| A3 | The `provision` step-order + `--purge`/`--dry-run`/`--report-only` flag semantics must be ported for full `10-installer.bats` parity | §Entrypoint | If a flag path is skipped, 10-installer @tests fail. Enumerate all flag paths in the plan. |
| A4 | `almalinux:9` base image ships curl-minimal so the NodeSource `curl | bash` pipe works without installing curl | §NodeSource Install | If absent, EL9 Node install fails. The Bash relies on this today (green in v0.3.5), so low risk. |
| A5 | The tee-transcript log (`/var/log/agentlinux-install.log`) content need only preserve what bats grep (no-EACCES lines, step markers) — not byte-identical framing | §Entrypoint step 2 | If a @test asserts exact log framing, the Rust logger must match it. Audit INST-05 + log-greps at plan time. |

## Open Questions

1. **Does the registry-CLI step stage the TS bundle or the Rust binary this phase?**
   - Known: Phase 58 (DIST-01) explicitly owns the musl-tarball-as-sole-channel; the `run.sh` harness already re-points the symlink at the Rust bin under a flag.
   - Unclear: whether Phase 57 should pre-stage the musl binary or keep the TS bundle for observable-parity.
   - Recommendation: **keep TS-bundle staging** (A1) — preserves master parity + per-phase rollback; Phase 58 swaps it.
2. **Shim vs. rewrite for the unit-source bats (18-*, 14-*, 13-*) as the Bash libs port over?**
   - Recommendation: extend the try-Rust-else-bash shim for `distro_detect`/`pkg` so `18-*` stays green without rewrites; retire shims where consolidation deletes the Bash. Decide per-file at plan time.
3. **Does `provision --purge` need full parity in this phase, or can teardown lag?**
   - `--purge` is a distinct 7-step path (agentlinux-install:363-450). Recommendation: port it in the same phase (it shares `nodesource_repo_paths` + the sudoers/PATH artefact list) so `--purge`-based bats teardowns keep working; flag if it should slip to a follow-up.
4. **How faithful must the tee-transcript be?** (see A5) — audit INST-05 + any log-greps.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `cargo` + musl target | Building the Rust provisioner | ✓ (Phase 53–56 build green) | x86_64-unknown-linux-musl | — |
| `docker` | Per-file bats runs | ✓ | — | QEMU (Phase 59) for systemd/cron modes |
| `nix` crate features (signal/process/user) | chown/uid/mode in sysio | ✓ (in Cargo.toml) | 0.31 | `std::os::unix::fs::chown` for the syscall |
| curl / apt / dnf (in target images) | NodeSource setup + pkg verbs | ✓ (base images) | — | none (these ARE the boundary) |
| systemd (PID 1) | systemd_user mode assertions | ✗ in Docker | — | QEMU (Phase 59) — bats SKIPs loudly |

**Missing (no fallback in this phase):** systemd/cron real-mode assertions → deferred to Phase 59 (QEMU). Everything else present.

## Validation Architecture

> `workflow.nyquist_validation` not explicitly false → section included.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats (behavior contract, ADR-002) + `cargo test` (bin unit tests) + `cargo-mutants`/`proptest` (pure core) |
| Config file | `tests/bats/` (behavior) + `rust/` workspace |
| Quick run command | `cargo test -p agentlinux` (bin adapter/sysio units) |
| Full suite command | `bash tests/docker/run.sh ubuntu-24.04` (per-target; per-file under OOM) |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Command | Exists? |
|-----|----------|-----------|---------|---------|
| PROV-01 | user/sudoers/node/path/registry observable state, 6 modes | behavior | `bats tests/bats/{20,22,30,50,23}-*.bats` | ✅ (Docker modes) / Phase-59 (systemd/cron) |
| PROV-01 | idempotency (INST-02) | behavior | `bats tests/bats/10-installer.bats` (2nd run) | ✅ |
| PROV-01 | sysio primitives byte-fidelity | unit | `cargo test -p agentlinux sysio` | ❌ Wave 0 (new module) |
| PROV-02 | Bash map deleted, single Rust source | behavior + grep | `bats tests/bats/13-reuse.bats` + `! grep REUSE_AGENT_CANONICAL_PATHS plugin/` | ✅ (grep is new gate) |
| PROV-03 | distro detect + apt/dnf parity | behavior | `bats tests/bats/18-{distro-detect,pkg-dispatch,detect-el9}.bats` | ✅ |
| PROV-03 | reuse/remediate/bail on both families | behavior | `bats tests/bats/{13,14,15}-*.bats` (Ubuntu) + EL9 | ✅ |

### Sampling Rate
- **Per task commit:** `cargo test -p agentlinux` + `cargo clippy` + the touched bats file.
- **Per wave merge:** the wave's bats files on ubuntu-24.04 (+ almalinux-9 for PROV-03 waves), per-file under OOM.
- **Phase gate:** full provisioner-surface bats green on the Rust build (Docker modes); systemd/cron/QEMU cases recorded as Phase-59-deferred.

### Wave 0 Gaps
- [ ] `rust/crates/agentlinux/src/sysio.rs` — new module (unit tests for atomic write, marker-block, ensure_dir/user)
- [ ] `rust/crates/agentlinux/src/distro.rs` + `pkg.rs` — new modules (family branch units)
- [ ] `AGENTLINUX_PROVISION_RUST=1` gate in `tests/docker/run.sh` — the provisioner staging seam
- [ ] A `! grep REUSE_AGENT_CANONICAL_PATHS plugin/` CI gate — the PROV-02 deletion assertion

## Security Domain

> `security_enforcement` not explicitly false → included. This phase runs privileged systems I/O.

### Applicable ASVS Categories
| ASVS | Applies | Standard Control |
|------|---------|-----------------|
| V5 Input Validation | yes | User-name charset validation (`^[a-z][a-z0-9_-]*$`, reject root/system accounts UID<1000) BEFORE any mutation. `[VERIFIED: agentlinux-install:469-484]` Port `validate_user_name` + `user_adoptable`. |
| V6 Cryptography | partial | NodeSource integrity = HTTPS + `curl -f` cert-verify + GPG-signed repo (ADR-005 — no body SHA, accepted). Don't hand-roll; shell to the pinned setup script. |
| V4 Access Control | yes | `require_root` for `provision`; the sudoers drop-in is visudo-gated 0440 root:root; recipes run as the UNPRIVILEGED install user via `sudo -u` (never sudo-npm). |

### Known Threat Patterns
| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| Malformed sudoers locks out host | Denial of Service | visudo `-cf` pre-install + post-install re-verify (TOCTOU belt); atomic 0440. `[VERIFIED: remediate/sudoers.sh]` |
| curl-pipe-bash tampering | Tampering | HTTPS + cert-verify + GPG repo (ADR-005). |
| Poisoned PATH resolves attacker `agentlinux` | Elevation of Privilege | reuse shim honors only an ABSOLUTE executable `AGENTLINUX_RUST_BIN`; user-owned PATH prefixes FIRST. `[VERIFIED: reuse/agents.sh:79-87]` |
| `rm -rf $VAR` in purge | Tampering | purge targets are LITERAL absolute paths; only the charset-validated user home feeds `userdel -r`. `[VERIFIED: agentlinux-install:356-450]` |
| Tampered sentinel picks scripts to run as agent | Tampering | recipe paths derive from catalog snapshot keyed by sentinel id, NOT sentinel JSON. `[VERIFIED: agentlinux-install:379-401]` |

## Sources

### Primary (HIGH confidence)
- `plugin/bin/agentlinux-install` (entrypoint, 616 LOC) — flag parse, log tee, traps, main() order, run_provisioners, run_purge, run_agent_adoption
- `plugin/provisioner/{10,20,30,40,50}-*.sh` — the five ordered steps
- `plugin/lib/{idempotency,distro_detect,pkg,as_user,detect,reuse,remediate}.sh` + `detect/`, `remediate/`, `reuse/` subdirs — primitives + orchestration
- `rust/crates/agentlinux/src/{main,recipe_env,dispatcher,cache,sentinel,catalog,guard}.rs` + `agentlinux-core/src/{detect_gates,reuse,classify,divergence}.rs` — the ported core + adapters
- `tests/docker/run.sh` (staging pattern), `tests/docker/Dockerfile.*` (bare base images), `tests/bats/helpers/invoke_modes.bash` (six-mode matrix)
- `rust/crates/agentlinux/Cargo.toml` — the already-pinned deps
- `gsd-tools query package-legitimacy check --ecosystem crates nix wait-timeout clap` → all OK

### Secondary (MEDIUM confidence)
- `.planning/phases/56-*/56-RESEARCH.md` — house style + the Phase-56 dispatcher/RecipeEnv/adapter contract
- Memory `project_v0_3_5_almalinux` — the apt→dnf port done once in Bash (the Rust rhel-arm reference)
- Memory `reference_docker_oom` — per-file bats runs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new crates; all deps present + audited in Phase 56.
- Architecture / step-order: HIGH — every step + primitive read at `file:line`; the port is a byte-faithful translation of code whose observable output the bats already pin.
- PROV-02 consolidation: HIGH — the three Bash sites + two external consumers located + verified; only the shim-retirement sequencing is a plan-time choice.
- Pitfalls: HIGH — sourced from the existing code's own comments + the v0.3.5 AlmaLinux port.
- Registry-CLI staging (Q1) / purge scope (Q3): MEDIUM — recommendation given; confirm the phase boundary at plan time.

**Research date:** 2026-07-28
**Valid until:** 2026-08-27 (stable — in-repo source; refresh if the Bash provisioner or Rust adapters change)
