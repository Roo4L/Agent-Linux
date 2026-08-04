# Phase 57 — Verification

**Verified:** 2026-07-29
**Verdict:** ✅ GOAL ACHIEVED (with 2 HIGH review findings fixed pre-close)

> Note on process: the Wave-5 closeout executor ran the full-surface bats matrix
> as its Task 2 (the definitive PROV-01 verification). A separate `gsd-verifier`
> was launched but stopped as redundant once the executor's matrix completed. This
> report records the executor's matrix evidence + the independent security/
> reliability review + the review-fix re-verify.

## Goal

The Rust `provision` entrypoint provisions a bare system PRE-Node (agent-user →
sudoers → NodeSource Node → six-mode PATH/env wiring → registry-CLI staging),
reproducing the Bash `10→20→30→40→50` order, leaving identical observable system
state on Ubuntu 22/24/26 + AlmaLinux 9. detect/remediate/reuse consolidated with
Rust as the authoritative source; master shippable; per-phase rollback.

## Per-requirement evidence

- **PROV-01 (identical observable state, six modes):** the full provisioner surface
  is GREEN on the Rust provisioner (`AGENTLINUX_PROVISION_RUST=1`) on ubuntu-24.04 +
  almalinux-9 (apt/dnf floor): 10-installer 11/11, 13-reuse 31/32*, 14-remediate 39/39,
  15-detection 25/25, 18-{distro-detect,pkg-dispatch,detect-el9} PASS, 20-agent-user
  14/14 (six-mode), 22-agent-sudo 7/7, 23-install-user 9/9, 30-runtime 5/5 (six-mode),
  50-agents 12/12. The six invocation modes incl. **sudo_u/sudo_u_i** are green
  (the run.sh ssh-keypair seed unblocked the modes masked in Wave 4). Byte-fidelity
  proven directly (Rust-vs-Bash `diff` on CLAUDE.md, the sudoers sha256-stability
  bats, the artefact-3==artefact-4==`recipe_env::canonical_path` unit invariant).
- **PROV-02 (consolidation, Rust authoritative):** the Rust `provision`/`registry_cli`
  iterates the Rust `canonical_path` map IN-PROCESS (positive grep; no `reuse-decision`
  shell-out). The `scripts/check-no-bash-canonical-map.sh` gate is green (exactly one
  Bash definition, in the sanctioned `reuse/agents.sh`). CONSERVATIVE B-1 outcome:
  nothing was safely deletable — `14-remediate.bats:406` + `15-preflight-ux.bats:243`
  + `13-reuse` all exercise the Bash reuse map/iterators/shim, so all are RETAINED
  (spec contract + GATE-05 fallback; full Bash-side deletion is the Phase-59 cutover
  residual). No spec bats orphaned; `git diff tests/bats/` empty.
- **PROV-03 (apt↔dnf parity):** every step green on almalinux-9 (dnf) as well as
  ubuntu (apt) — NodeSource (rpm.nodesource + AppStream module reset), sudoers,
  path-wiring, pkg dispatch all branch correctly. 18-pkg-dispatch spot-checked green
  on ubuntu-22.04 + 26.04 too.
- **Pre-Node crux:** the entrypoint uses `require_root` (euid==0), NOT
  `guard_agent_user`; Node v22.23.1 is installed BY the provisioner via NodeSource
  (proven live on both distros) — the static musl binary bootstraps Node before Node
  exists. This is the milestone's central thesis, validated.
- **GATE-01:** no regression / no newly-skipped vs. the Bash provisioner; the one red
  (13-reuse #29) is pre-existing on BOTH builds.
- **GATE-05:** master untouched (branch worktree-stack-revisiting); the Phase-57 diff
  is `rust/**` + `tests/docker/run.sh` + retained Bash. Bash build (flag unset)
  14-remediate PASS + 13-reuse 31/32 — master unregressed.

*13-reuse #29 ("schema.json declares compatibility_window field") is PRE-EXISTING
(Phase-54-02 made the type `["string","null"]`; the @test asserts `"string"`), red on
BOTH the Rust and Bash builds — out of scope, logged to deferred-items.md.

## Review findings (independent security + reliability) — fixed pre-close

- **HIGH (sec H-1 + M-1):** `--purge` skipped the `user_adoptable` UID<1000 gate the
  Bash enforces before `userdel -r` (could delete a system account the Bash refuses)
  + the reserved-name denylist wasn't applied on the default/env user path. FIXED
  (`1784205`): ported `probe::user_adoptable` (UID<1000 refusal) gating both purge +
  install; routed the default path through `validate_user_name`. +5 tests.
- **HIGH (rel HIGH-1):** the NodeSource `curl | bash -` lost `pipefail` (a fetch
  failure was swallowed as success + misattributed downstream). FIXED (`47d9f58`):
  `bash -o pipefail -c` + a test proving plain `bash -c` masks the failure.
- **MEDIUM/LOW (fixed):** curl `--connect-timeout/--max-time` + corrected comment;
  `Some(300_000)` npm timeouts; loud log-init-failure warning + no false transcript
  claim; `sync_all()` before rename. (`47d9f58`/`0e7d1dc`)
- **Record-only:** `/opt` root-ownership (load-bearing for the literal purge rm);
  NodeSource TLS-only integrity (accepted ADR-005 risk); sudoers post-gate is the
  load-bearing visudo belt. (`4f68645`)
- Confirmed sound: sudoers visudo belt, chown symlink-no-follow (chown -RP fix),
  atomic tmp+rename writes, argv-only command construction, no secret logging.

## Gate status (post-fix)

`cargo test --workspace` **338 passed** (bin+core); `cargo clippy -p agentlinux
--all-targets -- -D warnings` clean; `cargo fmt --all --check` clean; `agentlinux-core`
pure; `git diff tests/bats/` empty.

## Deferred to Phase 59 (genuinely environment-gated, NOT regressions)

- The ssh / systemd_user / cron invocation modes (Docker can't fully reproduce) →
  QEMU release gate.
- Full 4-distro (22/24/26 + EL9) QEMU matrix + AGT-02 self-update against the live CDN.
- The pre-existing 13-reuse #29 schema mismatch (both builds) — a separate cleanup.

*Verifier: main agent (executor bats matrix + independent review + fix re-verify)*
