---
phase: 57-provisioner-port-logic-consolidation
plan: 04
subsystem: infra
tags: [rust, nodejs, nodesource, npm-prefix, provisioner, apt, dnf, musl, remediate]

# Dependency graph
requires:
  - phase: 57-01
    provides: "pkg.rs NodeSource verbs (nodesource_prereqs/module_reset/repo_paths/setup, pkg_install) + sysio.rs (ensure_dir, ensure_line_in_file)"
  - phase: 57-02
    provides: "distro.rs Family (apt↔dnf fork) exposed via ProvisionCtx"
  - phase: 57-03
    provides: "cmd/provision.rs orchestrator shell + require_root + agent_user/sudoers steps + Resolutions/ProvisionCtx"
  - phase: 56
    provides: "dispatcher.rs as_user (buffered/streamed exec, sudo -u hop) for the npm module-migration shell-out"
provides:
  - "provision/nodejs.rs — the 30-nodejs.sh port: NodeSource pre-Node bootstrap + RT-01 v22 verify + RT-04 npm-prefix layout + .npmrc"
  - "provision/remediate_npm_prefix.rs — REMEDIATE-01 chown_or_rebase (strategy selector + chown/rebase mutations + module migration)"
  - "Node 22 LTS + agent-owned ~/.npm-global installed on both apt (deb.nodesource) and dnf (rpm.nodesource) paths, observably identical to the Bash provisioner"
affects: [57-05, 57-06, path-wiring, registry-cli, phase-59-qemu]

# Tech tracking
tech-stack:
  added: []  # no new crates
  patterns:
    - "Step port = dispatch on RESOLUTIONS[<component>] token, do ONLY I/O (mirrors sudoers/agent_user)"
    - "Pre-Node crux: node --version runs directly (root, on PATH post-install); the curl|bash setup + apt/dnf shelled external via Wave-0 pkg verbs"
    - "REMEDIATE-01 npm-prefix dispatch runs UNCONDITIONALLY after the create/reuse split"

key-files:
  created:
    - rust/crates/agentlinux/src/provision/nodejs.rs
    - rust/crates/agentlinux/src/provision/remediate_npm_prefix.rs
  modified:
    - rust/crates/agentlinux/src/provision/mod.rs
    - rust/crates/agentlinux/src/cmd/provision.rs

key-decisions:
  - "node --version runs directly (not via as_user) — matches root-executed 30-nodejs.sh; node is on PATH after NodeSource install"
  - "chown_recursive uses lchown + symlink_metadata (chown -RP parity) so a symlink out of the prefix never chowns a system tree"
  - "remediate_npm_prefix derives the old prefix from <install_home>/.npm-global + on-disk owner (detect-cache readers land Wave 5); observable mutation identical"

patterns-established:
  - "RT-01 version gate: parse node --version major, hard-fail (Err) if < 22 — the return-1-equivalent that aborts the provisioner loudly"
  - "Idempotent NodeSource repo-add gated on nodesource_repo_paths: any family repo file present → short-circuit (no re-fetch)"

requirements-completed: [PROV-01, PROV-03, GATE-01, GATE-05]

coverage:
  - id: D1
    description: "RT-01: Node 22 LTS installed via the NodeSource pre-Node bootstrap on ubuntu-24.04 (apt) and almalinux-9 (dnf); node --version reports v22.23.1 on both"
    requirement: "PROV-01"
    verification:
      - kind: integration
        ref: "docker: AGENTLINUX_PROVISION_RUST=1 provision --user agent --yes → node --version = v22.23.1 (ubuntu-24.04 AND almalinux-9)"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux/src/provision/nodejs.rs#rt01_gate_threshold_is_22, rt01_parses_major_from_v_prefixed_version"
        status: pass
    human_judgment: false
  - id: D2
    description: "RT-04: ~agent/.npmrc carries prefix=/home/agent/.npm-global; the prefix dirs (.npm-global{,/bin,/lib}) are agent:agent 0755; npm config get prefix (as agent) resolves under /home/agent — on both distros"
    requirement: "PROV-01"
    verification:
      - kind: integration
        ref: "docker: stat .npm-global* = agent:agent 755; cat .npmrc = prefix=/home/agent/.npm-global; npm config get prefix = /home/agent/.npm-global (both distros)"
        status: pass
      - kind: unit
        ref: "rust/crates/agentlinux/src/provision/nodejs.rs#rt04_npmrc_prefix_line_is_idempotent, rt04_prefix_paths_derive_from_install_home"
        status: pass
    human_judgment: false
  - id: D3
    description: "INST-02 idempotency: a second provision run short-circuits the NodeSource repo-add (no re-fetch) and .npmrc keeps exactly one prefix line — on both distros"
    requirement: "PROV-01"
    verification:
      - kind: integration
        ref: "docker: 2nd provision run logs 'NodeSource repo already configured (gate: nodesource_repo_paths)'; grep -c ^prefix= .npmrc = 1 (both distros)"
        status: pass
    human_judgment: false
  - id: D4
    description: "REMEDIATE-01 chown_or_rebase: strategy selector (chown under-home+salvageable, else rebase) + the chown/rebase observable mutation + best-effort module migration; chown -RP symlink safety"
    requirement: "PROV-01"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux/src/provision/remediate_npm_prefix.rs#strategy_*, chown_recursive_does_not_recurse_through_symlink, parse_manifest_*, rebase_npmrc_prefix_line_is_written_and_idempotent"
        status: pass
    human_judgment: false
  - id: D5
    description: "RT-01/RT-02/RT-04 across the six invocation modes (interactive/ssh/cron/systemd_user/sudo_u/sudo_u_i) via 30-runtime.bats on the Rust provisioner"
    requirement: "PROV-01"
    verification: []
    human_judgment: true
    rationale: "The six-mode PATH iteration depends on Wave-4 40-path-wiring (profile.d/agentlinux.env PATH prepend), NOT yet ported, plus systemd/cron which require QEMU (ADR-007). Deferred to Wave 4 (interactive/ssh/sudo_u modes) + Phase-59 QEMU (systemd_user/cron). This plan's floor (Node+prefix state) is proven directly; the bats mode-iteration cannot pass until Wave 4."

# Metrics
duration: 9min
completed: 2026-07-28
status: complete
---

# Phase 57 Plan 04: NodeSource Pre-Node Bootstrap (Node 22 + npm prefix) Summary

**`provision/nodejs.rs` installs Node 22 LTS from a bare, Node-less host via the NodeSource curl|bash + apt/dnf bootstrap, writes the agent-owned `~/.npm-global` prefix + `.npmrc`, and ports the REMEDIATE-01 chown/rebase — observably identical to `30-nodejs.sh` on both deb.nodesource and rpm.nodesource.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-07-28T20:34:05Z
- **Completed:** 2026-07-28T20:43:00Z
- **Tasks:** 1 (auto)
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments
- **The pre-Node crux holds:** the static musl bin installs Node when NO Node exists — `nodesource_prereqs → nodesource_module_reset → idempotent repo-add → pkg_install nodejs`, with the `curl … setup_22.x | bash -` + apt/dnf shelled EXTERNAL via the Wave-0 pkg verbs. Verified live on both distros (`node=v22.23.1`).
- **RT-01 verify:** `node --version` parsed to major, hard-fails (`Err`) if < 22 — the `return 1`-equivalent that aborts the provisioner loudly.
- **RT-04 npm-prefix layout:** `~/.npm-global{,/bin,/lib}` created `agent:agent 0755`, `~/.npmrc` = `prefix=/home/agent/.npm-global`, `npm config get prefix` (as agent) resolves under `/home/agent` — byte-identical to the Bash.
- **REMEDIATE-01** `chown_or_rebase` ported: the chown-vs-rebase strategy selector (chown only when under-home + trivially-salvageable; else rebase + best-effort module migration via the Phase-56 dispatcher; old prefix never deleted).
- **Idempotency (INST-02):** a second provision run short-circuits the repo-add ("already configured") and leaves exactly one `.npmrc` prefix line.

## Task Commits

1. **Task 1: port 30-nodejs.sh (NodeSource bootstrap + RT-01/RT-04 + REMEDIATE-01)** - `344914b` (feat)
2. **Review fix: chown_recursive symlink safety (chown -RP parity)** - `c3de9f7` (fix)

## Files Created/Modified
- `rust/crates/agentlinux/src/provision/nodejs.rs` (created) - the 30-nodejs.sh port: CREATE-path bootstrap, RT-01 verify, RT-04 npm-prefix + .npmrc, the unconditional npm-prefix REMEDIATE-01 dispatch.
- `rust/crates/agentlinux/src/provision/remediate_npm_prefix.rs` (created) - the remediate/nodejs.sh `chown_or_rebase` port: strategy selector, chown/rebase mutations, `npm ls -g` manifest parse + migration.
- `rust/crates/agentlinux/src/provision/mod.rs` (modified) - `pub mod nodejs; pub mod remediate_npm_prefix;`.
- `rust/crates/agentlinux/src/cmd/provision.rs` (modified) - wired `provision::nodejs::run(&ctx)` as step 30, replacing the Wave-3 not-yet-wired marker.

## Decisions Made
- `node --version` runs directly (a plain `Command`, not `as_user`) — the Bash `30-nodejs.sh` runs it as root with node on PATH after the NodeSource install; mirroring that keeps the RT-01 verify like-for-like.
- `chown_recursive` uses `lchown` + `symlink_metadata` to match `chown -R`'s default `-P` (no dereference) — a symlink under the prefix pointing at a system tree must never cause that tree to be chowned (found in self-review).
- `remediate_npm_prefix` derives the old prefix from `<install_home>/.npm-global` + the on-disk owner rather than the `DETECT_NPM_PREFIX_PATH` cache exports (which have no Rust home until Wave 5). The observable mutation is identical; Wave 5 swaps the derivation without touching the mutation body.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] chown_recursive followed symlinks (chown -RP parity)**
- **Found during:** Task 1 self-review of the REMEDIATE-01 port
- **Issue:** `chown_recursive` used `path.is_dir()` + `chown`, which dereferences symlinks — the Bash `chown -R` defaults to `-P` (lchown the link, do not recurse through a symlinked dir). A symlink under the npm prefix pointing at a system tree could cause that tree to be chowned to the install user (an ownership/privilege hole).
- **Fix:** Switched to `std::os::unix::fs::lchown` + `symlink_metadata` so a symlink is chowned as the link and treated as a leaf; added a test proving the walk does not descend through a symlink.
- **Files modified:** rust/crates/agentlinux/src/provision/remediate_npm_prefix.rs
- **Verification:** `chown_recursive_does_not_recurse_through_symlink` passes; workspace green.
- **Committed in:** `c3de9f7`

### Port derivation deviation (documented, not a fix)
- `remediate_npm_prefix.rs` derives the old prefix path from ctx (`<install_home>/.npm-global`) + on-disk owner instead of the detect-cache exports the Bash reads. Those detect READERS land with the Wave-5 detect→decide wiring; the token is `Create` in the Wave-3 seed so the remediate path is not exercised live yet. Noted in the file header + commit body.

---

**Total deviations:** 1 auto-fixed (1 Rule-1 bug) + 1 documented port-derivation deviation.
**Impact on plan:** The symlink fix is a genuine security-correctness improvement over a naive port; no scope creep. The derivation deviation is bounded and Wave-5-resolved.

## Issues Encountered
- **30-runtime.bats mode-iteration is not GREEN on the Rust provisioner yet (expected).** RT-01/RT-02/RT-04 iterate `INVOKE_MODES`; the `interactive`/`ssh`/`sudo_u`/`sudo_u_i` modes resolve `node`/`cowsay` via `/etc/profile.d/agentlinux.sh` written by Wave-4 `40-path-wiring.sh` (NOT yet ported), and `ssh`/`systemd_user`/`cron` additionally need sshd-keys/QEMU. The bats tests that DON'T depend on PATH-wiring — RT-02 no-EACCES re-install and RT-03 byte-clean uninstall (both use `sudo -u agent -H bash --login -c 'npm install -g …'` directly) — PASS on ubuntu-24.04, proving Node+npm+the agent-owned prefix work. The plan's true floor (RT-01 Node 22 + RT-04 prefix state) was proven by DIRECT container probes on BOTH distros (see coverage D1-D3). This is the plan's explicit scoping: the six-mode PATH cases are Wave-4 (interactive/ssh/sudo) + Phase-59 QEMU (systemd_user/cron), NOT claimed green from Docker.

## Verification Evidence

Live Docker runs (NodeSource is a live network fetch; the sandbox has network):

**ubuntu-24.04 (deb.nodesource.com / apt):**
- `node --version` → `v22.23.1`; `30-nodejs: Node.js v22 installed (RT-01 — v22 LTS)`
- `.npmrc` = `prefix=/home/agent/.npm-global`; `.npm-global{,/bin,/lib}` = `agent:agent 755`; `npm config get prefix` (as agent) = `/home/agent/.npm-global`
- 2nd run: `NodeSource repo already configured (gate: nodesource_repo_paths)`; `.npmrc` prefix line count = 1

**almalinux-9 (rpm.nodesource.com / dnf):**
- ca-certificates-only prereqs (Pitfall 5 — never curl); AppStream module reset ran; rpm NodeSource repo added; `dnf install nodejs` → `v22.23.1`
- `.npmrc` = `prefix=/home/agent/.npm-global`; `.npm-global{,/bin,/lib}` = `agent:agent 755`; `npm config get prefix` = `/home/agent/.npm-global`
- 2nd run: `NodeSource repo already configured`

**Rust workspace:** `cargo test --workspace` = 308 green (187 bin + 121 core); `cargo clippy -p agentlinux --all-targets -- -D warnings` clean; `cargo fmt --all --check` clean. Only `rust/` changed (Bash provisioner untouched — GATE-05); the pure `agentlinux-core` untouched.

## Self-Check: PASSED

## Next Phase Readiness
- Node 22 + the agent-owned `~/.npm-global` prefix are established. Wave 4 (`path_wiring.rs`, porting `40-path-wiring.sh`) writes the profile.d/agentlinux.env PATH artefacts whose PATH line must be byte-identical to the `~/.npm-global/bin` prefix this step created — after which the 30-runtime six-mode RT-01/RT-02/RT-04 will go green on the Rust provisioner (interactive/ssh/sudo modes in Docker; systemd_user/cron in Phase-59 QEMU).
- No blockers. The `remediate_npm_prefix` detect-cache derivation is the one Wave-5 follow-up (swap ctx derivation for the detect exports).

---
*Phase: 57-provisioner-port-logic-consolidation*
*Completed: 2026-07-28*
