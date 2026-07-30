# Phase 59: Full Validation Gate - Research

**Researched:** 2026-07-29
**Domain:** CI/CD validation gating — proving a like-for-like Rust rewrite behavior-preserving at full-matrix scale; wiring Docker/QEMU/release pipelines to gate on the Rust build; coverage audit; the canonical AGT-02 self-update acceptance test.
**Confidence:** HIGH (every claim grounded in a `file:line` read this session; this is a gate phase with no new dependencies — no external package research needed)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **GATE-02** — the complete bats contract passes on the Rust build across the Docker matrix (Ubuntu 22.04/24.04/26.04 + AlmaLinux 9) **AND** the QEMU release gate.
- **GATE-03** — every requirement ID / behavior family (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC) retains behavior or harness evidence on the Rust build; `behavior-coverage-auditor` reports zero uncovered.
- **GATE-04** — the canonical acceptance test: agent `claude` self-update WITHOUT sudo, zero EACCES, on the Rust build against the live Anthropic CDN. THE test the whole project exists to pass.
- **GATE-01 / GATE-05** — whole-matrix confirms no behavior-contract regression / no newly-skipped vs. the TS/Bash baseline; master shippable at gate close — the Rust track is READY to become master, with the pre-cutover TS/Bash build RETAINED as the rollback.

### The dev-runnable vs. CI/QEMU-only split (the key structural decision)
This dev VM OOMs on the FULL Docker bats suite ([[reference-docker-oom]] — ~test 131) and cannot run QEMU or the live-CDN release gate directly. The phase MUST split:
- **Dev-runnable (the in-phase floor):** per-file bats across the 4 distros (Docker, `tests/docker/run.sh <target> <file>`), the `behavior-coverage-auditor` (GATE-03), a targeted AGT-02 self-update where network allows.
- **CI/QEMU-triggered (wired + documented, run by the pipeline):** the full Docker matrix (`test.yml`), nightly-qemu (`nightly-qemu.yml` + `tests/qemu/boot.sh`), and the `release.yml` 4-gate pipeline incl. the live-CDN AGT-02 gate. Phase 59 WIRES these to gate on the Rust build and documents them as pipeline-triggered — it does NOT fake a local full-matrix pass.

### Claude's Discretion (validation-gate phase)
Parity pinned by the full bats contract on the Rust build + the coverage audit + the live AGT-02 acceptance. Recommended shape below; not binding.

### Deferred Ideas (OUT OF SCOPE — the post-milestone cutover)
- The final cutover: merge the Rust track to master; delete `plugin/cli/` (TS) + the Bash entrypoint (`plugin/bin/agentlinux-install`) + the retained Bash reuse map/shim/iterators. GATE-05 explicitly KEEPS them as the rollback. On a green gate the Rust track is DECLARED ready; the master-merge + TS/Bash deletion is the post-milestone cutover.
- The canonical product renumber (v0.4.0 is the milestone label; the shipped product version is 0.3.6) — a separate release decision.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GATE-02 | Complete bats contract green on the Rust build across the Docker matrix (22.04/24.04/26.04 + AlmaLinux 9) AND the QEMU release gate. | §CI Gate Map (`test.yml`/`nightly-qemu.yml`/`release.yml` already default to the Rust musl provisioner via `run.sh`), §The Full-Matrix Reality, §Wave Sequencing |
| GATE-03 | Every requirement family (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC + v0.4.0 RUST/TEST/CORE/VERB/PROV/DIST/GATE) retains evidence on the Rust build; `behavior-coverage-auditor` reports zero uncovered. | §GATE-03 Coverage Audit (family→evidence map; auditor invocation) |
| GATE-04 | AGT-02 `claude update` self-update, zero EACCES, on the Rust build against the live Anthropic CDN. | §GATE-04 Keystone (`51-agt02-release-gate.bats` map; Rust-provisioner path; dev-runnable vs. release.yml live-CDN gate) |
| GATE-01 | Whole-matrix confirms no behavior-contract regression / no newly-skipped vs. the TS/Bash baseline. | §The Carried Reds (resolve so the gate is genuinely green), §Coverage Audit |
| GATE-05 | master shippable; Rust track ready to become master; TS/Bash retained as rollback (`AGENTLINUX_LEGACY_TS=1`). | §The Cutover Boundary (Phase 59 declares ready, does NOT delete), §The Rollback Lever |
</phase_requirements>

## Summary

Phase 59 is a **validation gate**, not feature code. The heavy lifting was already done by Phase 58: `tests/docker/run.sh:297-338` makes the **static-musl Rust `provision` binary the DEFAULT provisioner with no flag** — the no-flag run builds the host musl bin (`host_build_musl`), stages it root-owned at `/usr/local/lib/agentlinux/provision/agentlinux`, and invokes `agentlinux provision --user agent --yes` AS the provisioner; the staged Rust `agentlinux` command is exercised via the reuse seam (`AGENTLINUX_RUST_BIN`, run.sh:366-385). Both `test.yml`'s `bats-docker` matrix (test.yml:288-339) and `release.yml`'s `gate-2-docker`/`gate-4-pinned-combo` (release.yml:127-151, 246-255) call `bash tests/docker/run.sh <target>` with no override, so **the Docker matrix already runs the Rust build** — GATE-02's Docker half is largely wired. The `AGENTLINUX_LEGACY_TS=1` inverse lever (run.sh:297-308) restores the Bash+TS build for GATE-05 rollback.

The one **wiring gap** is QEMU: `tests/qemu/boot.sh:523,531` still runs `bash plugin/bin/agentlinux-install` — the **Bash entrypoint**, i.e. the legacy TS provisioner path — NOT the Rust `provision`. `nightly-qemu.yml` and `release.yml`'s `gate-3-qemu` both drive `boot.sh`, so the QEMU release gate currently exercises the OLD path. This is the single most important GATE-02 item: **`boot.sh` must be re-pointed at the Rust musl `provision`** (mirroring the `run.sh:309-338` default), or the QEMU gate is a false GATE-02 green (it proves the Bash provisioner, not the Rust one). This is the phase's #1 risk.

Three **carried reds** must be resolved so the gate is genuinely green (all three are known + root-caused this session): (1) `13-reuse.bats` #29 asserts `compatibility_window.type == "string"` but schemars emits `["string","null"]` from `Option<String>` — the schema is the TEST-03 SoT, so the **test expectation is stale, not the schema**; (2) HRN-05 fails because `.planning/research/SUMMARY.md` is stripped from this branch by the planning-hygiene gate; (3) HRN-06 fails because `.claude/agents/security-engineer.md` lacks a `0440|sudoers` mention. HRN-05/06 live in `tests/harness/` (a Phase-1 meta-suite run by `tests/harness/run.sh`), NOT the Docker/QEMU behavior matrix, so they do not gate GATE-02 — but they must still be resolved (fix or documented xfail) for a truly-green gate.

**Primary recommendation:** 3 waves — (W1) **resolve the carried reds** (fix `13-reuse` #29 expectation to accept the schemars nullable form; fix HRN-06 rubric; resolve HRN-05 by restoring the byte-match source OR converting to a repo-relative check); (W2) **wire the QEMU gate to the Rust `provision`** in `boot.sh` (the only real GATE-02 wiring gap) + confirm `test.yml`/`release.yml` Docker gates run Rust (already do); (W3) **coverage audit (GATE-03) + AGT-02 keystone validation (GATE-04) + declare-ready (GATE-05)** — run `behavior-coverage-auditor`, run `51-agt02-release-gate.bats` on the Rust provisioner + a real `claude update` where the CDN is reachable, and record the declaration that the Rust track is master-ready with the TS/Bash rollback retained.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Run the full bats matrix (Docker) | CI (`test.yml` bats-docker) + `tests/docker/run.sh` | Dev (per-file `run.sh <t> <file>` floor) | The matrix job calls run.sh; run.sh:309-338 already defaults to the Rust `provision` |
| Run the full bats matrix (QEMU) | CI (`nightly-qemu.yml` + `release.yml` gate-3) + `tests/qemu/boot.sh` | — | boot.sh:531 still runs the BASH entrypoint — the wiring gap Phase 59 closes |
| Release-gate the 4-gate pipeline | CI (`release.yml`) | — | gate-1 precommit → gate-2 docker → gate-3 qemu → gate-4 pinned-combo → build → publish |
| Coverage audit (GATE-03) | `behavior-coverage-auditor` subagent (dev-runnable) | REQUIREMENTS.md ↔ bats grep | Cross-checks every family has bats/harness evidence; emits covered/uncovered/partial |
| AGT-02 self-update acceptance (GATE-04) | `51-agt02-release-gate.bats` on the Rust provisioner | Live Anthropic CDN (release.yml gate-3 QEMU + gate-2 Docker) | Runs a REAL `claude update`; asserts exit-0 + zero EACCES + version monotonicity |
| Declare Rust master-ready (GATE-05) | Phase-59 artifact (declaration) | `AGENTLINUX_LEGACY_TS=1` rollback lever | Declaration only — the actual TS/Bash deletion is the POST-milestone cutover |

## CI Gate Map — does CI gate on the Rust build? (GATE-02 core)

### `tests/docker/run.sh` — the single Docker entrypoint (already Rust by default)

`run.sh:277-338` is the decisive artifact. Phase 58 (Wave 2) made the musl bin the shipped + staged artifact, and run.sh's DEFAULT (no-flag) path now:
1. `host_build_musl` (run.sh:256-275) — builds/refreshes the static-musl `agentlinux` on the host via `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux` (incremental; near-noop when unchanged). **[VERIFIED: tests/docker/run.sh:256-275]**
2. Fail-loud guard (run.sh:312-315): if the musl bin is absent, ABORT non-zero — never false-green on a missing artifact. **[VERIFIED: tests/docker/run.sh:312-315]**
3. Stages the bin root-owned at `/usr/local/lib/agentlinux/provision/agentlinux` (run.sh:319-321) + splices it into `/opt/agentlinux-src/plugin/bin/agentlinux` for the 50-registry-cli staging step (run.sh:331-333). **[VERIFIED: tests/docker/run.sh:319-333]**
4. Invokes the Rust provisioner as root: `agentlinux provision --user agent --yes` (run.sh:337). **[VERIFIED: tests/docker/run.sh:337]**
5. Additionally stages the Rust `agentlinux` off the login PATH at `/opt/agentlinux/rust/agentlinux` and exports `AGENTLINUX_RUST_BIN` (run.sh:366-385, 418-421) so `13-reuse.bats` exercises the REAL Rust reuse-decision path, not the Bash fallback. **[VERIFIED: tests/docker/run.sh:366-421]**

The `AGENTLINUX_LEGACY_TS=1` inverse lever (run.sh:297-308) restores the Bash+TS distribution end-to-end for GATE-05 rollback, with its own fail-loud guard (aborts if `dist/index.js` is absent rather than false-greening on the musl bin). **[VERIFIED: tests/docker/run.sh:297-308]**

### `test.yml` — the per-PR Docker matrix (Rust, wired)

- `bats-docker` job (test.yml:288-339): matrix = `[ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, almalinux-9]`, `fail-fast: false`, runs `bash tests/docker/run.sh ${{ matrix.target }}` (test.yml:337-339) — **no override, so it exercises the Rust `provision` by default.** GATE-02's Docker half is wired here. **[VERIFIED: .github/workflows/test.yml:288-339]**
- The `rust` job (test.yml:139-257) is the gated Rust unit/lint/mutation/musl-build job (clippy, rustfmt, `cargo test`, cargo-mutants `--in-diff`, static-musl `ldd` assertion). It does NOT run bats — it is the RUST-02 per-PR gate. The per-distro in-container musl bats run is the `bats-docker` job above. **[VERIFIED: .github/workflows/test.yml:130-257]**
- **Note (not a gap, but worth a Wave-2 assertion):** the `changes` filter (test.yml:56-64) gates the expensive *steps* on whether `plugin/**|packaging/**|tests/**|scripts/**|rust/**|.github/**` changed. A `.planning/`-only or docs-only PR skips the bats run (reports green in seconds). For Phase 59's own PR (which touches `tests/`, `rust/`, `.github/`), the full matrix runs.

### `nightly-qemu.yml` + `tests/qemu/boot.sh` — THE WIRING GAP (Bash path, must fix)

- `nightly-qemu.yml:115-124` runs `bash tests/qemu/boot.sh ${{ matrix.target }}` on matrix `['22.04','24.04','26.04','almalinux-9']`, nightly + workflow_dispatch. **[VERIFIED: .github/workflows/nightly-qemu.yml:30-124]**
- `boot.sh:523,531` runs `bash plugin/bin/agentlinux-install` INSIDE the guest — the **Bash entrypoint** (the legacy TS-provisioner path via the CLI-bundle splice), NOT the Rust `provision`. **[VERIFIED: tests/qemu/boot.sh:523,531]**
- **This means the QEMU gate currently proves the Bash provisioner, not the Rust one.** Phase 59 MUST re-point `boot.sh` at the Rust musl `provision` — the same swap `run.sh:309-338` already made for Docker: build/stage the musl bin, invoke `agentlinux provision --user agent --yes` as root, with the `AGENTLINUX_LEGACY_TS=1` rollback branch. This is the single most important GATE-02 wiring task. Without it, a green QEMU gate is a **false GATE-02** (the #1 risk).
- The mechanics differ from Docker (no host bind-mount + `docker cp`; the guest gets sources via the cloud-init/ssh path in boot.sh). The musl bin must be built on the runner and transferred into the guest (scp over the boot.sh ssh-forward), OR built inside the guest. The planner should map `boot.sh`'s source-staging path (around :523) precisely before wiring — `boot.sh` is 25.9K and only the install-invocation region was scanned this session (LOW-confidence on the exact transfer mechanism; HIGH-confidence that :531 runs the Bash path).

### `release.yml` — the 4-gate release pipeline

Gate sequence enforced by `needs:` (release.yml:43-348):
- **gate-1-precommit** (release.yml:71-119): pre-commit + CLI unit tests (TS). Unchanged — this is lint/schema/TS-unit, not the behavior matrix. **[VERIFIED: release.yml:71-119]**
- **gate-2-docker** (release.yml:127-151): `bash tests/docker/run.sh <target>` × 4 distros — **Rust by default** (same run.sh). Includes `51-*.bats` (AGT-02) inside Docker. **[VERIFIED: release.yml:127-151]**
- **gate-3-qemu** (release.yml:157-238): `bash tests/qemu/boot.sh <target>` × 4 distros with `/dev/kvm` — **currently Bash path (the boot.sh gap above).** Includes `51-*.bats` (AGT-02) inside QEMU against the live CDN. **[VERIFIED: release.yml:157-238]**
- **gate-4-pinned-combo** (release.yml:246-255): `bash tests/docker/run.sh ubuntu-24.04` with the pinned catalog combo — Rust by default. **[VERIFIED: release.yml:246-255]**
- **build** (release.yml:267-306): `scripts/build-release.sh <tag>` — reproducible musl tarball + `.sha256` + catalog snapshot (Phase 58 already cargo-driven). **[VERIFIED: release.yml:267-306]**
- **publish** (release.yml:317-348): `softprops/action-gh-release@v2.6.2`, tag-push only.

**Net:** Docker gates (gate-2, gate-4) + `test.yml` bats-docker already run Rust. QEMU gates (gate-3, nightly-qemu) run the Bash path and must be re-wired. The release build is already musl. gate-1 (precommit/TS-unit) is fine to leave TS-based until the cutover — it validates the parity oracle, which GATE-05 retains.

## The Full-Matrix Reality — what runs WHERE, and the dev floor

| Layer | Where it runs | What it proves | Dev-runnable here? |
|-------|---------------|----------------|--------------------|
| Per-file bats × 4 distros (Docker) | `tests/docker/run.sh <target> <file>` | One bats file on the Rust `provision` per distro | **YES** — the OOM-dodge floor ([[reference-docker-oom]]); run.sh's 2nd positional selects one file (run.sh:86-99) |
| Full bats suite × 4 distros (Docker) | `test.yml` bats-docker / `release.yml` gate-2 | The complete contract on the Rust build (GATE-02 Docker half) | **NO** — OOMs ~test 131 in this VM; green-in-CI is the deliverable |
| Full bats suite × 4 distros (QEMU) | `nightly-qemu.yml` / `release.yml` gate-3 | systemd/cron/ssh + SELinux + cloud-init on real VMs (GATE-02 QEMU half) | **NO** — no KVM/QEMU here; wired + pipeline-gated is the deliverable |
| AGT-02 live-CDN self-update | `51-*.bats` inside Docker (gate-2) + QEMU (gate-3) | Zero-EACCES `claude update` against the live Anthropic CDN (GATE-04) | **PARTIAL** — a targeted `claude update` runs where the CDN is reachable (probed reachable this session); the enforcing gate is CI |
| Coverage audit (GATE-03) | `behavior-coverage-auditor` subagent | Every family has bats/harness evidence | **YES** — pure grep/Read; no distro needed |

**How the phase asserts GATE-02 without faking a local full-matrix pass:** the in-phase deliverable is (a) the carried reds resolved + verified per-file on the Rust build across the 4 distros (dev-runnable floor), (b) the QEMU gate re-wired to Rust (the code change), (c) the coverage audit green, and (d) a documented statement that the FULL matrix (Docker + QEMU + live-CDN) is GREEN-IN-CI (or is the pipeline gate). The full matrix pass is proven by the CI run on the phase's PR (Docker) + the nightly/release QEMU run — NOT by a local full-suite invocation (which would OOM and be meaningless anyway).

## GATE-03 Coverage Audit

### How `behavior-coverage-auditor` runs
- Subagent at `.claude/agents/behavior-coverage-auditor.md` (tools: Read, Grep, Glob, Bash). It is the TST-07 gate. **[VERIFIED: .claude/agents/behavior-coverage-auditor.md:1-89]**
- Rubric: extract all `<FAMILY>-<NUMBER>` IDs from `.planning/REQUIREMENTS.md`; for each, grep `tests/bats/` (behavior/installer) or the designated harness/artifact evidence (harness/docs/ops); report Covered / Uncovered / Partial with file paths; emit a `TST-07 gate: RED|GREEN` line. **[VERIFIED: behavior-coverage-auditor.md:18-77]**
- **Invocation for Phase 59:** spawn it as a subagent (it runs read-only grep/Read). It is dev-runnable with no distro. Feed it the full `.planning/REQUIREMENTS.md` (v0.4.0 families) AND note the GATE-03 requirement that the LEGACY families (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC) also retain evidence — those IDs live in the bats `@test` names, not in the v0.4.0 REQUIREMENTS.md.

### Family → evidence map on the Rust build

**v0.4.0 REQUIREMENTS.md families** (25 IDs; source: `.planning/REQUIREMENTS.md`):

| Family | IDs | Evidence on the Rust build |
|--------|-----|----------------------------|
| RUST | 01-03 | `test.yml` rust job (musl `ldd`, clippy, cargo test); 53-METRICS.md **[VERIFIED: test.yml:238-257]** |
| TEST | 01-04 | proptest + cargo-mutants (`test.yml:187-237`) + schemars drift (`schema_gen.rs:143`) + semver parity golden **[VERIFIED: schema_gen.rs:143-158]** |
| CORE | 01-03 | golden-corpus rust unit tests (`classify.rs`, `detect_gates.rs`, `category.rs`, `pin_spec.rs`) |
| VERB | 01-03 | `CLI-*`/`40-registry-cli.bats`/`50-agents.bats` green on the staged Rust `agentlinux` |
| PROV | 01-03 | `RT-*`/`AGT-*`/`DET-*`/`REUSE-*`/`REMEDIATE-*` bats on the Rust `provision` (run.sh:337) |
| DIST | 01-02 | `INST-*`/`60-curl-installer.bats`/`61-no-node-prereq.bats`; fpm/.deb deletion sweep |
| GATE | 01-05 | 01/05 cross-cutting (per-phase green + rollback); 02/03/04 = THIS phase |
| ARCH/PERF | 01 / 01 | ARCH-01 = v2 out-of-scope; PERF-01 = agent-loop metrics (53-METRICS.md) |

**Legacy families** (from the shipped v0.3.x contract — IDs present in bats `@test` names; counts this session): EL (42), UX (33), DET (33), REUSE (31), REMEDIATE (30), AGT (27), INST (25), MCP (21), BHV (21), ENABLE (19), CLI (16), WIRE (11), OPS (9), CAT (6), RT (5), DEVT (5), DOC (4), WORK (3), TST (1). 42 bats files, 369 `@test`s total. **[VERIFIED: grep over tests/bats/*.bats]**

- **HRN / TST / DOC evidence lives outside `tests/bats/`:** HRN-* in `tests/harness/*.bats` (run by `tests/harness/run.sh`, a Phase-1 meta-suite); DOC-* verified by artifact checks; TST-* partly in harness scaffolding. The auditor must classify these as "verified elsewhere — see `tests/harness/...`", NOT uncovered. **[VERIFIED: tests/harness/ layout]**
- **GATE-03 pass condition:** the auditor's final line is `TST-07 gate: GREEN` with zero Uncovered. Any Uncovered → add a test or document the elsewhere-evidence before gate close. Expect the audit to be green already (the rewrite was per-phase-gated); its job here is to CONFIRM no family lost evidence in the port.

## GATE-04 — the keystone (`51-agt02-release-gate.bats`)

### What the test does
`tests/bats/51-agt02-release-gate.bats:53-98` — the canonical acceptance test. **[VERIFIED: 51-agt02-release-gate.bats:1-98]**
1. `setup_file` (51:29-47): re-runs the installer if `/home/agent/.npm-global/bin/agentlinux` symlink is absent, then `agentlinux install --force claude-code` as the agent user to pin claude-code.
2. The `@test` (51:53): records `before_version`, runs `timeout 120s sudo -u agent -H bash --login -c 'claude update'` capturing a transcript, then asserts:
   - `assert_exit_zero` — update exited 0 (51:72).
   - `assert_no_eacces` on the transcript — **zero EACCES / "permission denied" lines** (the permission invariant the whole project exists to prove) (51:75).
   - version monotonicity: post-update `claude --version` ≥ pinned (51:78-94).

### How it runs on the RUST-provisioned build
- The file is invoked by `run.sh` (Docker) and `boot.sh` (QEMU) as part of the full suite. On the DEFAULT (no-flag) run.sh path, the **Rust musl `provision`** set up the agent user + NodeSource Node + PATH wiring (run.sh:337), then `setup_file` runs `agentlinux install --force claude-code` against the **staged Rust `agentlinux` command**, then `claude update` self-updates. So the whole chain — provisioner + CLI + self-update — is the Rust build. **[VERIFIED: run.sh:309-338 default path]**
- **Caveat (planner must verify):** `51:26` derives `PKG_VERSION` from `plugin/cli/package.json` (a TS artifact) and `51:38` re-runs `plugin/bin/agentlinux-install` (the Bash entrypoint) if the symlink is missing. On the Rust default path the symlink is created by the Rust `provision`, so the fallback re-install (51:37-39) should NOT fire in the normal full-suite ordering (40-*.bats tears down before 51-*.bats, but run.sh re-provisions once at the top). If a per-FILE `bats 51-*.bats` run is used for a targeted check, the fallback WOULD run the Bash entrypoint — so the **targeted AGT-02 dev check must run the full-suite ordering OR set `AGENTLINUX_RUST_BIN` + pre-stage the Rust provisioner**, else it silently validates the Bash path. Flag: the `package.json`/`agentlinux-install` references in 51-*.bats are TS/Bash couplings that survive until the cutover; they do not break the Rust default run but they are a false-green trap on isolated invocation.

### Dev-runnable vs. CI
- **Dev-runnable (floor):** a targeted `claude update` where the CDN is reachable. Probed this session: the Google CDN (Claude Code's update source, `storage.googleapis.com`) responds (HTTP), `claude` is installed at `/home/agent/.npm-global/bin/claude`, `cargo`+`docker` present. So a real `claude update` — and a Docker per-file `run.sh <target> 51-agt02-release-gate` on the Rust provisioner — is runnable here (subject to the file-ordering caveat above). **[VERIFIED: network probe + `command -v` this session]**
- **CI (enforcing gate):** `release.yml` gate-2 (Docker) + gate-3 (QEMU) run `51-*.bats` against the live Anthropic CDN with `ANTHROPIC_API_KEY` forwarded (nightly-qemu.yml:117-123 + docs/internals/test-secrets.md). The QEMU-EL9 AGT-02 zero-EACCES green is already recorded (release.yml:137-142, 162-167 — nightly-qemu almalinux-9 run 28391444242, 2026-06-29) — but that was on the BASH provisioner. Re-running it on the Rust `provision` (after the boot.sh re-wire) is the true GATE-04 QEMU proof.

## The Carried Reds — resolve so the gate is genuinely green (GATE-01)

### Red 1 — `13-reuse.bats` #29: `compatibility_window` type mismatch
- **The test** (13-reuse.bats:547-553, #29 counted): asserts `.["$defs"].agent.properties.compatibility_window.type == "string"`. **[VERIFIED: tests/bats/13-reuse.bats:547-553]**
- **The schema** (`plugin/catalog/schema.json`): `compatibility_window.type` is `["string","null"]` with `minLength:1`. **[VERIFIED: `jq` on plugin/catalog/schema.json]**
- **Root cause:** `schema.json` is GENERATED from schemars (`rust/crates/agentlinux-core/src/schema_gen.rs:79` — `compatibility_window: Option<String>`), and `Option<String>` canonically serializes to `type: ["string","null"]`. The generated form is byte-locked by the `schema_is_not_drifted` drift-check (schema_gen.rs:143-158), which the `rust` + `cli-unit` CI jobs enforce. **[VERIFIED: schema_gen.rs:79, 143-158]**
- **The fix (schema is the SoT — fix the TEST):** update 13-reuse.bats:552-553 to accept the nullable form, e.g. `jq -e '(.["$defs"].agent.properties.compatibility_window.type | if type=="array" then any(.[]; .=="string") else .=="string" end)'` or assert `.type == ["string","null"]` directly. Do NOT change the schema/schemars type: changing `Option<String>` → `String` would make the field REQUIRED (breaking test_only entries that omit it, and 13-reuse.bats:521-543 which asserts test_only entries MUST NOT carry it), and would fail the drift-check. **[CONFIDENCE: HIGH — the schema is TEST-03-locked; the test expectation predates the schemars generation (Phase-54-02 origin) and is stale.]**
- Note: 13-reuse.bats:534-543 (non-test entries carry the field; test_only entries don't) already work with the nullable schema — only the bare `type == "string"` assertion at :552 is wrong.

### Red 2 — HRN-05: `.planning/research/SUMMARY.md` byte-match
- **The test** (tests/harness/40-adrs-and-research.bats:87-88): `diff -q .planning/research/SUMMARY.md docs/research/v0.3.0/SUMMARY.md`. **[VERIFIED: 40-adrs-and-research.bats:87-88]**
- **Root cause:** `.planning/research/SUMMARY.md` does NOT exist on this branch — `.planning/research/` is absent. `docs/research/v0.3.0/SUMMARY.md` exists (27.2K). The planning-workflow skill strips intermediate `.planning/` state before merge; the byte-match test's left-hand source was a `.planning/`-tree file that this feature branch does not carry. **[VERIFIED: `ls` — .planning/research/ absent, docs/research/v0.3.0/SUMMARY.md present]**
- **The fix (recommended — convert the invariant):** the `docs/research/v0.3.0/SUMMARY.md` IS the durable artifact (it lives in `docs/`, which survives merge). The `.planning/research/SUMMARY.md` byte-match source is intermediate state that no longer exists. Recommend: change HRN-05:87-88 to a self-consistent check on the durable `docs/` copy (existence + content sanity), dropping the `.planning/`-tree dependency — the test currently encodes a "docs mirror the planning source" invariant that the planning-hygiene gate (which removes `.planning/research/`) has made structurally impossible on a merged branch. **[CONFIDENCE: MEDIUM — the exact desired invariant is a maintainer call; the planner should confirm whether to (a) restore the `.planning/research/SUMMARY.md` source, or (b) re-scope the test to `docs/`. Option (b) aligns with the planning-workflow skill.]** Alternatively, if HRN-05 is deemed out-of-scope for a Rust-rewrite gate, document it as a legitimate xfail (a pre-existing harness-hygiene red unrelated to the port, per 58 deferred-items.md:13-18) — but a "genuinely green gate" argues for fixing it.

### Red 3 — HRN-06: `security-engineer.md` sudoers-0440 rubric
- **The test** (tests/harness/50-agents-and-skills.bats:70-72): `grep -qEi "0440|sudoers" .claude/agents/security-engineer.md`. **[VERIFIED: 50-agents-and-skills.bats:70-72]**
- **Root cause:** `.claude/agents/security-engineer.md` contains NO `0440` or `sudoers` mention (grep empty this session). The rubric drifted from the test's expectation. **[VERIFIED: grep -niE "0440|sudoers" empty]**
- **The fix (fix the DOC):** add a sudoers-mode-0440 review checklist line to `.claude/agents/security-engineer.md` (the sudoers drop-in is `0440 root:root NOPASSWD`, per PROV/ADR-012 — a real review concern the reviewer role SHOULD cover). This is a 1-line rubric addition; low-risk, and makes the reviewer role actually cover the sudoers surface the rewrite touches. **[CONFIDENCE: HIGH — the fix is a doc addition; the invariant is legitimate.]**

### Where these reds gate
- Red 1 (13-reuse) is in the **Docker/QEMU behavior matrix** (`tests/bats/`) — it DOES gate GATE-02. Must fix.
- Reds 2+3 (HRN-05/06) are in `tests/harness/` — run by `tests/harness/run.sh`, which is NOT wired into `test.yml`/`release.yml`/`nightly-qemu.yml` (only `70-planning-clean-gate.bats` runs in CI, test.yml:352-353). So HRN-05/06 do NOT block the GATE-02 matrix — but GATE-03's "HRN retains harness evidence" and a "genuinely green gate" both argue for fixing them (or documenting the xfail). **[VERIFIED: grep for `tests/harness` in .github/workflows/ — only 70-planning-clean-gate.bats]**

## The Cutover Boundary — Phase 59 declares, it does NOT delete (GATE-05)

- Phase 59 does **NOT** perform the final cutover. `plugin/cli/` (TS source), `plugin/bin/agentlinux-install` (Bash entrypoint), and the retained Bash reuse map/shim/iterators (`plugin/lib/reuse/agents.sh` + `remediate.sh`/`prompt.sh` iterators) are KEPT as the GATE-05 rollback. **[VERIFIED: CONTEXT.md:31-36, 119-124; ROADMAP.md:161; REQUIREMENTS.md:40 PROV-02 note — "Bash iterators + shim are retired at the Phase-59 ENTRYPOINT cutover"]**
- **Reconciliation note for the planner:** REQUIREMENTS.md:40 (PROV-02) says the Bash iterators/shim "are retired at the Phase-59 entrypoint cutover" — but CONTEXT.md (deferred) + ROADMAP.md GATE-05 say the cutover (TS/Bash deletion) is the POST-milestone step, NOT Phase 59. Resolve in favor of CONTEXT/ROADMAP: **Phase 59 DECLARES the Rust track master-ready; the master-merge + TS/Bash deletion is the post-milestone cutover** once the maintainer green-lights it. The "Phase-59 entrypoint cutover" phrasing in PROV-02 refers to the eventual entrypoint swap that Phase 59 makes POSSIBLE (by proving the gate green), not to a deletion inside Phase 59's scope. **[CONFIDENCE: HIGH on the boundary; the planner should NOT plan any TS/Bash deletion tasks — only the declaration + the `AGENTLINUX_LEGACY_TS=1` rollback-retained assertion.]**
- **How master-shippable is asserted:** the `AGENTLINUX_LEGACY_TS=1` lever (run.sh:297-308) restores the Bash+TS build with one env var; `master` still carries the shippable Bash+TS distribution; the Rust track is additive + revertible. GATE-05 is satisfied by demonstrating the lever works (a per-file `AGENTLINUX_LEGACY_TS=1 run.sh <target> <file>` green) + the declaration that the Rust track is ready.

## Common Pitfalls

### Pitfall 1: A CI gate silently running the OLD TS/Bash path = false GATE-02 green
**What goes wrong:** the QEMU gate (`boot.sh:531`) runs `plugin/bin/agentlinux-install` (Bash), so a green QEMU release/nightly proves the BASH provisioner, not the Rust one. Declaring GATE-02 met on that green is a false pass.
**How to avoid:** re-point `boot.sh` at the Rust `provision` (mirror run.sh:309-338) as a Wave-2 task; grep the CI logs for `agentlinux provision` (Rust) vs `agentlinux-install` (Bash) as a verification step. Also add an assertion (a bats or a boot.sh echo) that the running provisioner IS the musl bin.

### Pitfall 2: The AGT-02 file's TS/Bash couplings false-green an ISOLATED run
**What goes wrong:** `51-*.bats` reads `plugin/cli/package.json` (TS) and re-runs `plugin/bin/agentlinux-install` (Bash) in `setup_file` if the symlink is missing. A per-file `bats 51-*.bats` (or `run.sh <t> 51-agt02-release-gate` without the full-suite pre-provision) would validate the Bash path, not Rust.
**How to avoid:** run the AGT-02 dev check via the FULL-suite ordering (where run.sh pre-provisions with Rust) OR pre-stage the Rust `provision` + `AGENTLINUX_RUST_BIN` before the isolated file. Verify the running `agentlinux` is the musl bin during the check.

### Pitfall 3: "Fixing" the schema instead of the stale test (Red 1)
**What goes wrong:** changing `compatibility_window: Option<String>` → `String` to match the bats `type=="string"` assertion makes the field required, breaks test_only entries + 13-reuse.bats:521-543, and fails the schemars drift-check.
**How to avoid:** the schema is the TEST-03 SoT — fix the bats expectation (:552) to accept `["string","null"]`. Never hand-edit `schema.json`.

### Pitfall 4: Treating HRN-05/06 as GATE-02 blockers (or ignoring them entirely)
**What goes wrong:** either blocking the Docker/QEMU matrix on harness meta-tests that don't run there (wasted effort), or shipping a "green gate" that still has 2 reds in `tests/harness/run.sh`.
**How to avoid:** know that HRN-05/06 gate `tests/harness/run.sh` (not the behavior matrix); fix them (Red 2 = re-scope to `docs/`; Red 3 = 1-line rubric add) OR document as explicit xfails per 58 deferred-items.md — but resolve them so the gate is genuinely green.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Run one bats file per distro on the Rust build | A new local harness | `tests/docker/run.sh <target> <file>` (2nd positional, run.sh:86-99) | Already builds/stages the musl bin + exports AGENTLINUX_RUST_BIN; OOM-safe |
| Coverage cross-check | A grep script | `behavior-coverage-auditor` subagent | It IS the TST-07 gate; emits the canonical covered/uncovered/partial report |
| Rust-vs-Bash provisioner toggle | A new flag | The existing `AGENTLINUX_LEGACY_TS=1` lever (run.sh:297) | Phase-58 already wired the default=Rust / rollback=Bash+TS split, both fail-loud |
| Schema regeneration | Hand-editing schema.json | `UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema` | The drift-check enforces byte-equality; hand-edits fail CI |

## Risks + Wave Sequencing

### Top risks (ranked)
1. **[#1] The QEMU gate silently runs the Bash path (false GATE-02).** `boot.sh:531` = `agentlinux-install` (Bash). If Phase 59 declares GATE-02 met on the current QEMU green, it proves the wrong provisioner. **Mitigation:** re-wire boot.sh to the Rust `provision` (Wave 2) + a log/assert that the musl bin ran.
2. **The live-CDN AGT-02 is un-runnable at full fidelity in-dev.** The enforcing zero-EACCES gate needs CI (Docker + QEMU against the live Anthropic CDN). **Mitigation:** the dev floor is a targeted `claude update` (CDN probed reachable) + the Docker per-file run; the QEMU + release live-CDN gate is documented as the pipeline gate, re-proven on the Rust path after the boot.sh re-wire.
3. **The carried reds mask a truly-green gate.** Red 1 (13-reuse) gates the behavior matrix; Reds 2/3 gate the harness meta-suite. **Mitigation:** Wave 1 resolves all three (Red 1 fix is HIGH-confidence; Red 2 needs a maintainer call on the invariant; Red 3 is a 1-line doc add).
4. **AGT-02 file's TS/Bash couplings (Pitfall 2)** false-green an isolated dev check. **Mitigation:** full-suite ordering or pre-stage Rust + verify the musl bin.
5. **boot.sh source-transfer mechanics unknown (LOW-confidence).** The exact musl-bin-into-guest path (scp vs in-guest build) was not fully mapped this session. **Mitigation:** the planner reads boot.sh's source-staging region (~:480-531) before wiring; the swap pattern is known (run.sh:309-338), only the transport differs.

### Recommended wave breakdown (3 waves — small, gate-shaped)
- **Wave 1 — Resolve the carried reds (GATE-01 truly green).** Fix 13-reuse.bats:552 to accept `["string","null"]` (verify per-file on the Rust build across the 4 distros via `run.sh <t> 13-reuse`); fix HRN-06 (`security-engineer.md` sudoers-0440 rubric line); resolve HRN-05 (re-scope to `docs/` OR restore source OR document xfail — maintainer call). Independent, dev-runnable, no distro coupling.
- **Wave 2 — Wire the CI gates on the Rust build (GATE-02).** Re-point `tests/qemu/boot.sh` at the Rust musl `provision` (mirror run.sh:309-338, incl. the `AGENTLINUX_LEGACY_TS=1` branch); confirm (assert, don't assume) `test.yml` bats-docker + `release.yml` gate-2/gate-4 run Rust by default (they do — add a verification note/grep); add a "which provisioner ran" assertion so a future regression to the Bash path is caught. Depends on Wave 1 (the suite must be red-free before the matrix is meaningful).
- **Wave 3 — Coverage audit + AGT-02 keystone + declare-ready (GATE-03/04/05).** Run `behavior-coverage-auditor`, emit the coverage report, confirm zero Uncovered (legacy HRN/DOC/TST classified as verified-elsewhere); validate AGT-02 (`51-*.bats` on the Rust provisioner via full-suite ordering + a real `claude update` where CDN reachable); record the GATE-05 declaration (Rust track master-ready; TS/Bash rollback retained; `AGENTLINUX_LEGACY_TS=1` lever demonstrated). The full-matrix Docker+QEMU+live-CDN pass is the CI/nightly/release pipeline gate — documented, not faked locally.

**Wave count recommendation: 3.**

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| cargo (Rust toolchain) | host_build_musl (run.sh:263) | ✓ | (rust-toolchain.toml pinned) | — |
| docker | Docker per-file bats floor | ✓ | present | — |
| Anthropic/Google CDN (storage.googleapis.com) | AGT-02 `claude update` dev check | ✓ | HTTP reachable | — |
| claude (Claude Code) | AGT-02 self-update | ✓ | /home/agent/.npm-global/bin/claude | — |
| QEMU / /dev/kvm | Full QEMU matrix (GATE-02 QEMU half) | ✗ | — | CI-only (nightly-qemu / release gate-3) — documented, not faked |
| Full Docker bats suite (all tests one run) | GATE-02 Docker half | ✗ (OOMs ~test 131) | — | Per-file floor in-dev; full matrix is CI (test.yml / release gate-2) |

**Missing with no in-dev fallback (pipeline-gated, documented):** the full QEMU matrix + the live-CDN AGT-02 QEMU gate. These genuinely require the CI/release environment — the in-phase deliverable is that they are WIRED (boot.sh re-pointed at Rust) + green-in-CI, not that they run in this dev VM.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core (behavior contract) + `cargo test` (Rust units) |
| Config | `tests/docker/run.sh` (Docker entrypoint), `tests/qemu/boot.sh` (QEMU entrypoint), `tests/harness/run.sh` (Phase-1 meta-suite) |
| Quick run (dev floor) | `bash tests/docker/run.sh ubuntu-24.04 13-reuse` (one file, one distro, Rust default) |
| Full suite (CI) | `bash tests/docker/run.sh <target>` × 4 (test.yml/release gate-2); `bash tests/qemu/boot.sh <target>` × 4 (nightly/release gate-3) |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Command | Exists? |
|-----|----------|-----------|---------|---------|
| GATE-02 | Full contract green on Rust, Docker+QEMU | integration | `run.sh <t>` ×4 (CI) + `boot.sh <t>` ×4 (CI, after re-wire) | ✅ Docker / ⚠️ QEMU needs re-wire |
| GATE-03 | Zero uncovered families | audit | `behavior-coverage-auditor` subagent | ✅ auditor exists |
| GATE-04 | AGT-02 zero-EACCES on Rust vs live CDN | integration | `run.sh <t> 51-agt02-release-gate` + release gate-2/3 | ✅ test exists; ⚠️ QEMU on Rust after re-wire |
| GATE-01 | No regression / no newly-skipped | integration | full suite green; carried reds fixed | ⚠️ 3 carried reds (Wave 0/1) |

### Wave 0 Gaps
- [ ] `tests/bats/13-reuse.bats:552` — accept `["string","null"]` (Red 1) — covers GATE-01
- [ ] `tests/harness/50-agents-and-skills.bats:70` source — `.claude/agents/security-engineer.md` sudoers-0440 rubric (Red 3)
- [ ] `tests/harness/40-adrs-and-research.bats:87` — HRN-05 re-scope/restore/xfail (Red 2 — maintainer call)
- [ ] `tests/qemu/boot.sh:531` — re-point at the Rust `provision` (GATE-02 QEMU wiring)

*(No new test framework install needed — bats + cargo already present.)*

## Security Domain

> `security_enforcement` not explicitly false — included. Phase 59 writes no new runtime code (gate/wiring/test-fix only), so the security surface is narrow.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | no | No new input surface (gate phase) |
| V6 Cryptography | yes (existing) | sha256-before-exec in the curl-installer (unchanged; DIST-01) |
| V14 Config | yes | least-privilege CI token (`permissions: contents: read`, test.yml:24); publish escalates to `contents: write` only in the publish job (release.yml:322) |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| CI secret leak (ANTHROPIC_API_KEY to bats) | Info Disclosure | step-level env only (nightly-qemu.yml:117-123); gitleaks full-history gate (test.yml:265-286) |
| False-green gate (Bash path masquerades as Rust) | Tampering (integrity of the acceptance claim) | assert the running provisioner IS the musl bin; grep CI logs for `agentlinux provision` |
| sudoers drop-in mode drift | Elevation of Privilege | HRN-06 rubric (Red 3 fix) makes the reviewer role cover `0440 root:root NOPASSWD` |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | HRN-05's intended invariant is best re-scoped to the durable `docs/` copy (vs. restoring the stripped `.planning/research/SUMMARY.md`) | Carried Reds — Red 2 | Wrong fix direction; a maintainer may prefer restoring the source — flagged as a maintainer call |
| A2 | `boot.sh` transfers the musl bin into the guest via the existing ssh-forward (not an in-guest cargo build) | CI Gate Map — QEMU | If in-guest build is required, Wave 2 needs a Rust toolchain in the guest cloud-init — larger change |
| A3 | GATE-03 auditor will report GREEN with legacy HRN/DOC/TST classified as verified-elsewhere | Coverage Audit | If a family genuinely lost evidence in the port, Wave 3 must add a test before gate close |

## Open Questions

1. **HRN-05 fix direction (restore `.planning/research/SUMMARY.md` vs. re-scope to `docs/`).**
   - Known: the `.planning/` source is stripped by planning-hygiene; the `docs/` copy is durable.
   - Unclear: which invariant the maintainer wants preserved.
   - Recommendation: re-scope to `docs/` (aligns with planning-workflow skill) OR document as a pre-existing xfail; confirm with the maintainer in discuss/plan.
2. **boot.sh musl-bin transport into the QEMU guest.**
   - Known: the swap PATTERN is run.sh:309-338; boot.sh:531 runs the Bash path today.
   - Unclear: exact source-staging mechanism in boot.sh (~:480-531 not fully read this session).
   - Recommendation: the planner reads that region before writing the wiring task.
3. **Does GATE-59 include a "provisioner identity" assertion in the suite?**
   - Recommendation: add a small assertion (bats or boot.sh/run.sh echo) that the running `agentlinux` is the musl bin, so a future regression to the Bash path is caught mechanically (defends Risk #1).

## Sources

### Primary (HIGH confidence — read this session, file:line)
- `tests/docker/run.sh:256-428` — the Rust-default provisioner seam + LEGACY_TS lever + AGENTLINUX_RUST_BIN staging
- `.github/workflows/test.yml:130-356` — rust job, bats-docker matrix, changes filter, planning-hygiene
- `.github/workflows/release.yml:43-348` — 4-gate pipeline
- `.github/workflows/nightly-qemu.yml:30-137` — QEMU matrix
- `tests/qemu/boot.sh:481-531` — the Bash-entrypoint install (the wiring gap)
- `tests/bats/51-agt02-release-gate.bats:1-98` — the AGT-02 keystone
- `tests/bats/13-reuse.bats:521-556` — the compatibility_window tests (Red 1)
- `rust/crates/agentlinux-core/src/schema_gen.rs:79,143-158` + `types.rs:30` — schemars Option<String> + drift-check
- `plugin/catalog/schema.json` (`jq`) — `compatibility_window.type == ["string","null"]`
- `tests/harness/40-adrs-and-research.bats:73-98` + `50-agents-and-skills.bats:60-72` — HRN-05/06
- `.claude/agents/behavior-coverage-auditor.md:1-89` — the GATE-03 auditor
- `.planning/REQUIREMENTS.md:40-114` — GATE/PROV-02 traceability
- `.planning/ROADMAP.md:150-177` — Phase 59 success criteria + cutover boundary
- `.planning/phases/58-.../deferred-items.md:1-25` — HRN-05/06 pre-existing reds

### Secondary (this-session probes)
- Network: `storage.googleapis.com` HTTP-reachable; `claude`/`cargo`/`docker` present (dev AGT-02 floor runnable)
- grep over `tests/bats/*.bats` — 42 files, 369 @tests, legacy family counts

## Metadata

**Confidence breakdown:**
- CI gate map (Docker already Rust; QEMU is the gap): HIGH — direct file:line reads
- Carried reds root causes: HIGH (Red 1, Red 3), MEDIUM (Red 2 fix direction — maintainer call)
- boot.sh transport mechanics: LOW — region not fully read; pattern known
- Cutover boundary (declare-not-delete): HIGH — CONTEXT + ROADMAP + PROV-02 note reconciled

**Research date:** 2026-07-29
**Valid until:** ~2026-08-28 (stable — internal CI/test files; no external dependency drift)
