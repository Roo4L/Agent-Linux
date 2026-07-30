---
phase: 58
plan: 03
subsystem: distribution / test-harness / installer-closeout
tags: [GATE-05, GATE-01, DIST-01, flag-fold, rollback-lever, no-node-prereq]
requires:
  - "58-02 (musl bin is the default staged agentlinux command; install.sh execs musl provision)"
provides:
  - "run.sh runs the Rust musl provision by DEFAULT with no override (GATE-01)"
  - "AGENTLINUX_LEGACY_TS=1 inverse rollback lever restores the Bash+TS distribution end-to-end (GATE-05)"
  - "61-no-node-prereq.bats proves the static CLI/provisioner needs no Node (DIST-01)"
affects:
  - "Phase 59 (cutover: delete plugin/cli/ + the Bash entrypoint; 4-distro QEMU release gate + AGT-02)"
tech-stack:
  added: []
  patterns:
    - "single inverse rollback flag (AGENTLINUX_LEGACY_TS) instead of two forward flags"
    - "off-login-PATH reuse-bin staging so a named agentlinux cannot shadow the canonical symlink"
    - "regime-aware bats (musl vs legacy-TS) skipping musl-only assertions under the rollback"
    - "readelf -l (no PT_INTERP) + readelf -d (no DT_NEEDED) static-link proof at the STAGED artifact"
key-files:
  created:
    - tests/bats/61-no-node-prereq.bats
  modified:
    - tests/docker/run.sh
decisions:
  - "Fold both forward flags into the default; the AGENTLINUX_STAGE_RUST_CLI relocate is NOT droppable — it becomes the default off-PATH staging (CLI-01 interactive/login modes use the real login PATH where .local/bin shadows .npm-global)"
  - "The harness stages the RUST-03 reuse bin OFF the login PATH (/opt/agentlinux/rust/agentlinux) and never touches the .npm-global symlink — the provisioner owns it per regime (musl default / TS rollback)"
  - "61-no-node-prereq is regime-aware: musl-only assertions skip loudly under AGENTLINUX_LEGACY_TS=1 (the no-Node claim is scoped to the musl artifact); assertion 3 (Node present post-provision) is regime-independent"
metrics:
  duration: ~55m
  completed: 2026-07-29
  files_changed: 2
  commits: 3
status: complete
---

# Phase 58 Plan 03: Flag-Fold + Rollback Lever + No-Node Proof (Wave 3 closeout)

Folded the two forward Rust harness flags into the DEFAULT (the bats now exercise
the static-musl bin as the shipped artifact with NO override — GATE-01), added the
single inverse `AGENTLINUX_LEGACY_TS=1` rollback lever that restores the Bash+TS
distribution end-to-end (GATE-05, fail-loud on a missing bundle), and added
`61-no-node-prereq.bats` proving the static CLI/provisioner needs no Node (DIST-01).
Full installer+registry closeout green on the Rust default on both ubuntu-24.04 and
almalinux-9; `agentlinux-core` + the TS oracle untouched.

## What Was Built

### Task 1 — flag fold + rollback lever in `run.sh` (commits `b2d0464`, `c10ec8e`)

- **Provision seam folded (`b2d0464`):** the `AGENTLINUX_PROVISION_RUST=1` gate is
  removed — run.sh now runs the musl `provision` AS the provisioner in the DEFAULT
  path (`docker exec … <bin> provision --user agent --yes`), splicing the built
  musl bin into `/opt/agentlinux-src/plugin/bin/agentlinux` so registry_cli's
  step-50 finds the artifact it stages. The fail-loud musl-bin guard is retained.
- **Inverse rollback lever `AGENTLINUX_LEGACY_TS=1` (`b2d0464`):** when set, run.sh
  execs the Bash `plugin/bin/agentlinux-install` entrypoint (which stages
  `dist/index.js` as the `agentlinux` command via the CLI-bundle splice). It
  **fails LOUD** — aborts non-zero, no bats run — if the TS bundle
  (`plugin/cli/dist/index.js`) is absent, so a rollback attempt on a musl-only tree
  can never false-green on the musl bin (T-58-07 mitigation, mirrors the retired
  :292-295/:377-379 discipline).
- **Off-PATH reuse-bin staging (`c10ec8e`, Rule-1 fix):** the Phase-56
  `AGENTLINUX_STAGE_RUST_CLI` relocate block is FOLDED INTO THE DEFAULT, not
  dropped. The initial fold dropped it on the premise that the invoke_mode PATH
  favors `.npm-global`; that premise held only for the cron mode
  (`invoke_modes.bash:70`). CLI-01's interactive/login modes run `su - agent` /
  `sudo -i` with the REAL login PATH, where skel `~/.profile` prepends
  `~/.local/bin` ahead of `.npm-global/bin`, so the RUST-03 reuse bin at
  `.local/bin/agentlinux` SHADOWED the canonical `.npm-global` symlink and CLI-01
  (interactive) went red. Fix: stage the reuse bin OFF the login PATH (at
  `/opt/agentlinux/rust/agentlinux`) and DO NOT touch the `.npm-global` symlink —
  the provisioner owns it per regime (musl default / TS rollback). `AGENTLINUX_RUST_BIN`
  points at the off-path bin for 13-reuse's shim. Regime-agnostic.
- **Flag-docs block updated (`b2d0464`):** the two forward flags removed; the
  `AGENTLINUX_LEGACY_TS=1` entry added with its Bash+TS rollback + fail-loud
  semantics.

### Task 2 — `61-no-node-prereq.bats` (commit `ebeb037`)

The DIST-01 no-Node negative-assertion, 3 `INST-08` `@test`s mirroring the INST-05
log-grep pattern (10-installer.bats:180-216):

1. **Static-link proof (RUST-01 re-asserted at the staged artifact):** the staged
   `agentlinux` bin has no PT_INTERP program header (`readelf -l`) and no DT_NEEDED
   shared libs (`readelf -d`), corroborated by `ldd` reporting `statically linked`
   / `not a dynamic executable`. It cannot load a dynamic linker or libc at exec,
   so no Node runtime can be required (T-58-08 mitigation).
2. **No-Node-before-the-bin (runtime ordering):** the transcript shows the musl
   provisioner's own step markers `agentlinux provision: 10-agent-user` +
   `20-sudoers` BEFORE `30-nodejs` — the static bin drove two full provisioner
   steps while Node was still absent — plus a negative grep that no `node`/`npm`/
   `pnpm` command ran before the first step marker.
3. **Recipes-still-get-Node (the irreducible boundary):** `node --version` resolves
   AFTER provision (nodejs.rs installed it for the recipes); DIST-01 is scoped to
   the CLI/provisioner itself, not the recipes (50-agents.bats is the deeper proof).

Regime-aware like INST-02: under `AGENTLINUX_LEGACY_TS=1` the staged artifact is the
TS `dist/index.js` Node script, so assertions 1+2 skip loudly (the no-Node claim is
scoped to the musl artifact — never a false-red on the rollback path) while
assertion 3 (regime-independent) still runs.

## How It Was Verified

`cargo fmt --all --check` (clean), `cargo clippy -p agentlinux --all-targets -- -D
warnings` (clean), `cargo test --workspace` (338 passed: 217+121; 0 failed).

Full installer+registry closeout on the Rust build (DEFAULT artifact, **no
override**) per-file (Docker-OOM dodge) on BOTH distros:

| bats | ubuntu-24.04 | almalinux-9 |
|------|-------------|-------------|
| 61-no-node-prereq | 3/3 ✓ | 3/3 ✓ |
| 10-installer (incl. INST-02) | 11/11 ✓ | 11/11 ✓ |
| 60-curl-installer | 4/4 ✓ | 4/4 ✓ |
| 23-install-user | 9/9 ✓ | 9/9 ✓ |
| 40-registry-cli (incl. CLI-01 all modes) | 29/29 ✓ | 29/29 ✓ |
| 13-reuse | 31/32 ✓ (only #29) | 31/32 ✓ (only #29) |

- **GATE-05 rollback lever:** `AGENTLINUX_LEGACY_TS=1 10-installer` is 11/11 green on
  the restored Bash+TS distribution (the Bash entrypoint execs, `[INFO]`-prefixed
  transcript, `dist/index.js` staged). Fail-loud proof: with the TS bundle hidden,
  the run **aborts non-zero** (`ERROR: … TS bundle … absent — refusing to fall back
  to the musl bin and report false-green`), no bats run. `61-no-node-prereq` under
  the rollback regime cleanly skips assertions 1+2 and passes 3 (no false-red).
- **13-reuse #29** (`REUSE-03: schema.json declares compatibility_window field`) is
  the pre-existing red (Phase-57 `deferred-items.md`), red on BOTH builds, out of
  scope. The re-pointed REUSE-03 brownfield E2E tests (31, 32) are GREEN — REUSE-03
  is not silently skipped, confirming the off-path `AGENTLINUX_RUST_BIN` bin resolves.

## Deviations from Plan

### Auto-fixed (Rule 1 — bug in the enumerated fold)

**1. [Rule 1 — Bug] The `AGENTLINUX_STAGE_RUST_CLI` relocate is NOT droppable; fold it into the default off-PATH staging**
- **Found during:** Task 1 closeout run of `40-registry-cli` on ubuntu-24.04.
- **Issue:** The plan's Task-1 action offered "drop the flag-gated relocate that
  existed solely to un-shadow the canonical symlink under the old TS-default." The
  initial fold did exactly that, on the premise that the invoke_mode PATH favors
  `.npm-global/bin`. That premise held only for the **cron** mode
  (`invoke_modes.bash:70`); CLI-01's **interactive/login** modes use the REAL login
  PATH (`su - agent` / `sudo -i`) where skel `~/.profile` prepends `~/.local/bin`
  ahead of `.npm-global/bin`. The RUST-03 reuse bin at `.local/bin/agentlinux`
  therefore shadowed the canonical `.npm-global` symlink → CLI-01 (interactive)
  red: `observed /home/agent/.local/bin/agentlinux, expected …/.npm-global/…`.
- **Fix:** Fold the flag block's CLI-01 reconciliation into the DEFAULT: stage the
  RUST-03 reuse bin OFF the login PATH (`/opt/agentlinux/rust/agentlinux`) and DO
  NOT touch the `.npm-global` symlink (the provisioner owns it per regime). This is
  cleaner than the old flag block (which re-pointed the symlink) and is
  regime-agnostic — the off-PATH staging is identical for musl default and TS
  rollback; only the provisioner-owned canonical symlink's target differs.
- **Files modified:** `tests/docker/run.sh`
- **Commit:** `c10ec8e`

No architectural (Rule 4) deviations were needed. The plan's core instruction (fold
the flags; add the ONE inverse lever) holds — the deviation is only that the CLI-01
reconciliation had to fold into the default rather than be dropped.

## Invariants Preserved

- **GATE-01:** the bats exercise the musl bin as the DEFAULT artifact with NO
  override.
- **GATE-05:** the single `AGENTLINUX_LEGACY_TS=1` inverse lever restores the
  Bash+TS distribution end-to-end (fail-loud on a missing bundle) — a live per-phase
  rollback.
- **DIST-01:** `61-no-node-prereq.bats` proves static-link + no-Node-before-the-bin
  + recipes-still-get-Node.
- **`agentlinux-core`:** 0 files changed (pure); all of `rust/` unchanged this wave.
- **TS oracle (`plugin/cli/`) + Bash entrypoint (`plugin/bin/agentlinux-install`):**
  retained as the rollback substrate (deletion deferred to the Phase-59 cutover).
- **bats specs:** the only bats change is the new `61-no-node-prereq.bats`; the
  Wave-2 re-points (10/13/40/60) are untouched.

## Known Stubs

None. `61-no-node-prereq.bats` is a real negative assertion (readelf/ldd static
proof + transcript step-ordering grep + a negative pre-Node command grep), not a
tautology; the legacy-TS skips are regime-correct, not stubs.

## Deferred to Phase 59 (NOT closed here)

- The 4-distro Docker + QEMU release gate (release.yml gate-3, boot.sh) — CI/QEMU
  release-gate cases, not runnable per-file locally.
- AGT-02 self-update against the live Anthropic CDN (GATE-04).
- Deletion of `plugin/cli/` (TS oracle) + `plugin/bin/agentlinux-install` (the
  rollback substrate) at the cutover.
- 13-reuse #29 (schema `compatibility_window`) — pre-existing, red on both builds,
  out of this phase's scope.

## Self-Check: PASSED

- Created `58-03-SUMMARY.md` — FOUND.
- `tests/bats/61-no-node-prereq.bats` — FOUND.
- `tests/docker/run.sh` — FOUND.
- Commits `b2d0464`, `ebeb037`, `c10ec8e` — FOUND.
