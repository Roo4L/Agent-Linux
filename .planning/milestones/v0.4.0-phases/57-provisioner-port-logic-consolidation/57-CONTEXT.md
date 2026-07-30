# Phase 57: Provisioner Port + Logic Consolidation - Context

**Gathered:** 2026-07-28
**Status:** Ready for research
**Mode:** Smart-discuss infrastructure-skip (like-for-like provisioner port; identical observable system state — no user-facing change). Codebase scout below.

<domain>
## Phase Boundary

Port the ~pre-Node provisioner (agent-user creation, sudoers drop-in, NodeSource
Node, PATH/env wiring to `/etc/agentlinux.env`, registry-CLI staging) + wire the
ALREADY-PORTED pure decision core (detect/remediate/reuse/idempotency/classify/
divergence) into the Rust binary, consolidating the duplicated Bash maps into a
single Rust source of truth — so provisioning leaves **identical observable system
state** across all six invocation modes on both distro families.

- **PROV-01** — provisioning (agent-user, sudoers, NodeSource Node, PATH/env
  wiring, registry-CLI staging) leaves the same observable state as the Bash
  provisioner; `RT-*` / `AGT-*` bats green across all six invocation modes
  (interactive login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u`,
  `sudo -u -i`).
- **PROV-02** — detect/remediate/reuse/idempotency consolidated into the Rust
  binary; the duplicated `CANONICAL_PATHS` / `GSD_SYSTEM_PATH` maps are DELETED
  from Bash (single source of truth in Rust).
- **PROV-03** — distro detection + the aware-install reuse/remediate/bail paths
  behave identically on Ubuntu 22.04/24.04/26.04 **and** AlmaLinux 9;
  `DET-*` / `REUSE-*` / `REMEDIATE-*` bats green.
- **GATE-01 / GATE-05** — full bats green for the provisioner surface (no
  regression / no newly-skipped); master shippable; parallel track; per-phase
  rollback (a broken provisioner phase never blocks a master hotfix).

Also resolves the Phase-56-deferred **INST-02-under-flag** item (the pure-installer
test perturbed only by the flag's post-install symlink override).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (infrastructure/port phase)
Like-for-like provisioner port; parity pinned by the bats behavior suite (ADR-002)
+ identical observable system state. Recommended shape below; not binding.

### The crux: this phase runs PRE-Node
The whole motivation for a compiled binary (memory [[project-rust-rewrite-v0-4-0]],
[[project-motivation]]): the provisioner must run BEFORE Node exists (TS can't cross
the Node chicken-and-egg). The static x86_64-musl `agentlinux` bin (no runtime deps)
runs first, provisions the agent user + Node, then stages itself. This is the payoff
of the whole rewrite.

### What is ALREADY done (do NOT re-port — reuse)
- **Pure deciders** in `agentlinux-core` (Phases 53–55): classify, compute_divergence,
  resolve_latest_for, the detect gates (reuse/remediate/presence), derive_category,
  parse_pin_spec, decide_version, semver_shim.
- **Bin adapters** (Phase 56): guard (CLI-05 geteuid), catalog, sentinel (atomic),
  cache, probe, npm, rewire; the dispatcher (sudo -u/tee/timeout/SIGTERM→SIGKILL);
  RecipeEnv (the 6-var contract).
So Phase 57 ADDS the systems-side I/O (user/sudoers/Node/PATH) + a provisioner
entrypoint that ORCHESTRATES the pure core + these adapters, and DELETES the Bash
decision duplication.

### Recommended shape (researcher + planner to finalize)
- The `agentlinux` bin grows a `provision` entrypoint (or subcommand) that runs the
  ordered steps the Bash provisioner runs today: ensure agent user → sudoers drop-in
  → NodeSource Node → PATH/env wiring (`/etc/agentlinux.env` + profile.d + .bashrc +
  cron.d, the six-mode matrix) → stage the registry CLI. Each step idempotent.
- Port `plugin/lib/idempotency.sh` primitives (ensure_marker_block, ensure_line,
  atomic file install with mode/owner) as Rust helpers — these are the load-bearing
  "same observable state" primitives.
- Consolidate `CANONICAL_PATHS` / `GSD_SYSTEM_PATH` (duplicated in `plugin/lib/prompt.sh`,
  `remediate.sh`, `reuse/agents.sh`) into ONE Rust source; the Bash copies are deleted.
  The TS-side copies were already absorbed into agentlinux-core in Phase 55/56 — confirm
  the Rust map matches and is the single truth both Bash (via generated output) and the
  bin consume.
- Distro detection (`distro_detect.sh`: apt/dnf, Ubuntu 22/24/26 + AlmaLinux 9) →
  Rust; the pkg abstraction (`pkg.sh`: apt-get vs dnf) → Rust. This is the AlmaLinux
  parity surface (PROV-03).

### The irreducible boundary (survives the rewrite — do NOT port)
The ~25 per-agent `install.sh`/`uninstall.sh` recipes stay Bash (Phase 56 contract).
The NodeSource setup script + apt/dnf themselves stay external (shelled to via the
dispatcher / a buffered exec). Any genuinely interactive TTY prompt (`prompt.sh`)
stays a thin boundary.

</decisions>

<code_context>
## Existing Code Insights (from scout)

### Port targets (Bash → Rust, ~2,050 LOC bash + entrypoint)
- `plugin/provisioner/` (683 LOC, ordered steps): 10-agent-user.sh (143),
  20-sudoers.sh (71 — ALREADY has a Rust-adjacent shape from Phase 5.1),
  30-nodejs.sh (174 — NodeSource), 40-path-wiring.sh (153 — the six-mode matrix),
  50-registry-cli.sh (142 — stages the CLI; Phase 56's run.sh already overrides its
  symlink for bats).
- `plugin/lib/` (~1,371 LOC): as_user.sh (54), detect.sh (107), distro_detect.sh
  (115), idempotency.sh (198 — the parity primitives), log.sh (54), pkg.sh (226 —
  apt/dnf), prompt.sh (285 — TTY UX), remediate.sh (299), reuse.sh (33) + detect/
  remediate/ reuse/ subdirs.
- The `plugin/bin/agentlinux-install` entrypoint dispatches the provisioner steps
  (research to map: flag parse, log tee, ERR/EXIT traps, run_provisioners order).

### Duplicated maps to consolidate (PROV-02)
`CANONICAL_PATHS` / `GSD_SYSTEM_PATH` live in `plugin/lib/prompt.sh`,
`plugin/lib/remediate.sh`, `plugin/lib/reuse/agents.sh` (Bash) — the TS copies were
already folded into agentlinux-core. Rust becomes the single source; Bash copies deleted.

### Acceptance oracle
- bats: `RT-*` (30-runtime), `AGT-*` (50-agents), `DET-*`/`REUSE-*`/`REMEDIATE-*`
  (detection/aware-install), `INST-*` (10-installer, 23-install-user), across the
  six-mode matrix (`tests/bats/helpers/invoke_modes.bash`) on Ubuntu 22/24/26 +
  AlmaLinux 9. Docker OOM → per-file runs; stage the Rust bin (Phase 56 run.sh pattern).
- The Phase-53 `agents.sh` try-Rust-else-bash reuse shim already exercises the reuse
  path on the Rust build — extend the pattern to the full provisioner.
- Phase-54 machinery (proptest/mutants) covers any NEW pure helper landed here.

</code_context>

<specifics>
## Specific Ideas

- LARGEST phase of the milestone. The systems I/O (useradd, sudoers, NodeSource, PATH
  files) is the genuinely new surface; the decision layer is mostly WIRING the ported
  core. Split waves so a systems-step failure surfaces before the decision-wiring depends
  on it.
- "Same observable state" means the bats assertions on file contents/modes/owners/PATH
  across six modes — NOT identical internal structure.
- AlmaLinux 9 (dnf/EL9) is the parity multiplier — every step must branch apt vs dnf
  faithfully; the memory [[project-v0-3-5-almalinux]] records the apt→dnf port already
  done once in Bash (a reference for the Rust branch).
- master shippable; all on branch `worktree-stack-revisiting`; recipes stay Bash;
  per-phase rollback (GATE-05) — a red provisioner phase must never block a master hotfix.

</specifics>

<deferred>
## Deferred Ideas

- musl tarball as sole channel + drop fpm .deb → Phase 58.
- Full-matrix bats (Docker 22/24/26 + AlmaLinux 9) + QEMU release gate + AGT-02
  self-update against the live CDN → Phase 59.

</deferred>
