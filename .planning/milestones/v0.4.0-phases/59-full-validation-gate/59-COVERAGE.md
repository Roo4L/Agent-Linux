# Behavior Coverage Audit — Phase 59 (Full Validation Gate, GATE-03)

**Auditor:** `behavior-coverage-auditor` rubric (`.claude/agents/behavior-coverage-auditor.md`)
**Run:** 2026-07-29 · Wave 3 (59-03) · on the **Rust build** (musl `provision` default)
**Scope:** every v0.4.0 `.planning/REQUIREMENTS.md` family (RUST/TEST/CORE/VERB/PROV/DIST/GATE; ARCH/PERF = v2 deferred) **and** every legacy behavior family whose IDs live in the bats `@test` names (BHV/RT/AGT/CLI/CAT/INST/DET/REUSE/REMEDIATE/MCP/ENABLE/WIRE/OPS/EL/UX/DEVT/ASST/WORK/DOC/TST/HRN).

**Method:** extracted all `<FAMILY>-<NUMBER>` IDs from `.planning/REQUIREMENTS.md`; grepped `tests/bats/*.bats` for behavior/installer evidence and `tests/harness/*.bats` for meta-suite (HRN) evidence; located non-bats evidence (Rust unit/golden/proptest/mutation/schemars-drift tests, CI jobs, artifact checks) for families verified outside bats. Per the auditor rubric, non-bats IDs are classified **"verified elsewhere — see `<path>`"**, never silently omitted; a family that genuinely lost evidence in the port is reported **Uncovered** (a blocker), not hand-waved.

The bats suite is exercised on the **Rust build**: `tests/docker/run.sh` default provisions with the static-musl `agentlinux provision --user agent --yes` (run.sh:337) and stages the Rust `agentlinux` command via `AGENTLINUX_RUST_BIN` (run.sh:366-421), so all `tests/bats/` evidence below is evidence **on the Rust build**.

---

## Part A — v0.4.0 REQUIREMENTS.md families (25 IDs)

### RUST (Rust Foundation)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| RUST-01 | Covered | `.github/workflows/test.yml` rust job (`x86_64-unknown-linux-musl` + `ldd` "not a dynamic executable"); `run.sh` `host_build_musl` builds the same static bin | verified elsewhere — Rust CI + musl-static assertion |
| RUST-02 | Covered | `test.yml` rust job (clippy, rustfmt, `cargo test`, cargo-mutants `--in-diff`) on every PR | verified elsewhere — CI |
| RUST-03 | Covered | de-risking spike + `53-METRICS.md`; the reuse seam exercised via `AGENTLINUX_RUST_BIN` in `13-reuse.bats` on the Rust build | verified elsewhere (metrics) + bats (13-reuse) |

### TEST (Testing Bedrock)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| TEST-01 | Covered | `rust/crates/agentlinux-core/src/proptest_strategies.rs` + proptest invariants in the core crate | verified elsewhere — `cargo test` (338 pass) |
| TEST-02 | Covered | cargo-mutants on the pure-logic crate (`test.yml`; `rust/mutants.out/`) | verified elsewhere — CI mutation gate |
| TEST-03 | Covered | `rust/crates/agentlinux-core/src/schema_gen.rs:143` `schema_is_not_drifted` byte-locks `plugin/catalog/schema.json`; enforced by rust + cli-unit CI. `13-reuse.bats` #29 asserts the schemars nullable form on the Rust build (fixed Wave 1) | verified elsewhere (drift-check) + bats |
| TEST-04 | Covered | `rust/crates/agentlinux-core/src/semver_shim.rs` golden semver-parity tests (`satisfies`/`maxSatisfying`/`valid`) | verified elsewhere — `cargo test` |

### CORE (Pure-Logic Core Parity)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| CORE-01 | Covered | `rust/crates/agentlinux-core/src/classify.rs` golden-corpus unit tests (six-state classify == TS) | verified elsewhere — `cargo test` |
| CORE-02 | Covered | `rust/crates/agentlinux-core/src/divergence.rs` + `semver_shim.rs` (`computeDivergence`/`resolveLatestFor` + zero-match error path) | verified elsewhere — `cargo test` |
| CORE-03 | Covered | `detect_gates.rs` + `pin_spec.rs` + `category.rs` golden-corpus unit tests | verified elsewhere — `cargo test` |

### VERB (Registry CLI Verbs)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| VERB-01 | Covered | `tests/bats/40-registry-cli.bats` (CLI-*), `tests/bats/50-agents.bats` (AGT-*), `23-install-user.bats` — green on the staged Rust `agentlinux` | bats on the Rust build |
| VERB-02 | Covered | dispatcher/streaming behavior tests (`50-agents.bats` real installs; `sudo -u` + tee + timeout + SIGTERM→SIGKILL) | bats on the Rust build |
| VERB-03 | Covered | the six `AGENTLINUX_*` env-var contract generated from Rust; the ~25 Bash recipes run against it (`5x-catalog-*.bats` ENABLE/OPS) | bats on the Rust build |

### PROV (Provisioner)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| PROV-01 | Covered | `RT-*` (`30-runtime.bats`), `AGT-*` (`50-agents.bats`), `BHV-*` (`20-agent-user.bats`) across the six invocation modes — on the Rust `provision` (run.sh:337) | bats on the Rust build |
| PROV-02 | Covered | `scripts/check-no-bash-canonical-map.sh` (exactly-one Bash canonical def); the Rust `canonical_path` map is authoritative; `13-reuse.bats` exercises the Rust decision path | verified elsewhere (guard) + bats |
| PROV-03 | Covered | `DET-*` (`15-detection.bats`, `18-*`), `REUSE-*` (`13-reuse.bats`), `REMEDIATE-*` (`14-remediate.bats`) — Ubuntu 22/24/26 + AlmaLinux 9 | bats on the Rust build |

### DIST (Distribution)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| DIST-01 | Covered | `scripts/build-release.sh` (reproducible musl tarball + `.sha256`); `tests/bats/60-curl-installer.bats` (sha256-before-exec); `tests/bats/61-no-node-prereq.bats` (no Node prereq for the CLI/provisioner) | bats on the Rust build |
| DIST-02 | Covered | fpm/.deb deletion sweep (`packaging/deb/` gone, no `--deb`/`fpm` branch); INST-* installer bats | bats + artifact-deletion check |

### GATE (Validation Gate)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| GATE-01 | Covered | per-phase green full bats suite (cross-cutting); Wave 1 cleared the 3 carried reds → `tests/harness/run.sh` 118/118, `13-reuse` 32/32 on the Rust build | verified elsewhere (per-phase gate) + this phase Wave 1 |
| GATE-02 | Covered | Docker matrix runs Rust by default (`test.yml` bats-docker, `release.yml` gate-2/4); QEMU gate re-wired at the Rust `provision` with the provisioner-identity guard (Wave 2, `tests/qemu/boot.sh`) | verified elsewhere — CI/QEMU pipeline (green-in-CI) |
| GATE-03 | Covered | **THIS report** — `behavior-coverage-auditor` zero-Uncovered on the Rust build | this artifact |
| GATE-04 | Covered | `tests/bats/51-agt02-release-gate.bats` on the Rust chain (`claude update` zero-EACCES); live-CDN enforcing gate = `release.yml` gate-2/gate-3 | bats on the Rust build + CI live-CDN gate |
| GATE-05 | Covered | `AGENTLINUX_LEGACY_TS=1` rollback lever (run.sh:297-308) restores Bash+TS; substrate retained (`plugin/cli/` + `plugin/bin/agentlinux-install`) | verified elsewhere — rollback lever + substrate present |

### ARCH / PERF (v2 — deferred, NOT uncovered)

| ID | Status | Evidence | Notes |
|----|--------|----------|-------|
| ARCH-01 | Deferred (v2) | out of scope — ARM not in project scope (`REQUIREMENTS.md` "Out of Scope") | not a gate blocker; explicitly deferred, not uncovered |
| PERF-01 | Deferred (v2) | its own milestone once the rewrite lands (`REQUIREMENTS.md` v2) | not a gate blocker; explicitly deferred, not uncovered |

---

## Part B — Legacy behavior families (IDs in bats `@test` names)

These families carry the shipped v0.3.x contract; their IDs live in the bats `@test` names rather than in the v0.4.0 `REQUIREMENTS.md`. GATE-03 requires each retains evidence **on the Rust build** — confirmed: every family below has ≥1 `@test` in `tests/bats/`, which `run.sh` exercises on the Rust `provision`.

| Family | Tests | Status | Evidence file(s) |
|--------|-------|--------|------------------|
| BHV (agent-user behavior, 6 invocation modes) | 21 | Covered | `20-agent-user.bats`, `22-agent-sudo.bats`, `52-agt02-brownfield-gate.bats` |
| RT (runtime) | 5 | Covered | `30-runtime.bats` |
| AGT (agent installability) | 27 | Covered | `50-agents.bats`, `51-agt02-release-gate.bats`, `51-cc-no-autoupdate.bats`, `53-catalog-npm-cluster.bats`, `55-catalog-autoupdate.bats`, `73-phase51-gsd-codex.bats` |
| CLI (registry CLI) | 16 | Covered | `40-registry-cli.bats` |
| CAT (catalog) | 6 | Covered | `10-installer.bats`, `40-registry-cli.bats` |
| INST (installer/curl) | 25 | Covered | `10-installer.bats`, `22-agent-sudo.bats`, `23-install-user.bats`, `40-registry-cli.bats`, `60-curl-installer.bats`, `61-no-node-prereq.bats` |
| DET (distro detection) | 33 | Covered | `15-detection.bats`, `18-detect-el9.bats`, `18-distro-detect.bats`, `18-pkg-dispatch.bats`, `74-catalog-brownfield-detection.bats` |
| REUSE (aware-install reuse) | 31 | Covered | `13-reuse.bats` |
| REMEDIATE (aware-install remediate) | 30 | Covered | `14-remediate.bats` |
| MCP (mcp catalog entries) | 21 | Covered | `59-catalog-mcp.bats`, `60-catalog-github-mcp.bats`, `61-catalog-sentry-mcp.bats`, `62-catalog-firecrawl-mcp.bats`, `63-catalog-slack-mcp.bats`, `64-catalog-linear-mcp.bats`, `65-catalog-jira-atlassian-mcp.bats`, `71-phase51-hosted-mcp.bats` |
| ENABLE (catalog enablement) | 19 | Covered | `53-`/`55-`/`57-`/`59-`/`66-`/`67-`/`68-`/`69-catalog-*.bats` |
| WIRE (cross-wiring) | 11 | Covered | `56-catalog-skill-wiring.bats`, `70-catalog-cross-wire.bats` |
| OPS (operational smoke) | 9 | Covered | `54-catalog-npm-smoke.bats`, `55-catalog-autoupdate.bats`, `57-catalog-binary.bats`, `72-phase51-prerequisites.bats` |
| EL (EL9 / distro dispatch) | 42 | Covered | `18-detect-el9.bats`, `18-distro-detect.bats`, `18-pkg-dispatch.bats` |
| UX (preflight/remediate UX) | 33 | Covered | `14-remediate.bats`, `15-preflight-ux.bats` |
| DEVT (devtools catalog) | 5 | Covered | `58-catalog-devtools.bats` |
| ASST (assistant catalog) | 5 | Covered | `67-catalog-openclaw.bats`, `68-catalog-hermes-agent.bats` |
| WORK (workflow) | 3 | Covered | `53-catalog-npm-cluster.bats`, `57-catalog-binary.bats`, `66-catalog-spec-kit.bats` |
| DOC (doc/artifact checks) | 4 | Covered | `10-installer.bats` (`DOC-*` @tests) — **verified in bats**, not "elsewhere" |
| TST (test/secrets scaffolding) | 1 (@test) + 5 refs | Covered / verified elsewhere | `00-secrets-smoke.bats` (TST-01 @test); TST-03..08 referenced across `tests/harness/run.sh` + bats headers; **TST-07 = this auditor** |

### HRN (harness meta-suite — verified elsewhere: `tests/harness/`, NOT `tests/bats/`)

Per the auditor rubric, HRN-* are harness/meta requirements: their evidence lives in `tests/harness/*.bats` (run by `tests/harness/run.sh`, the Phase-1 meta-suite), **not** in the behavior matrix. Classified **"verified elsewhere — see `tests/harness/`"**, NOT uncovered.

| ID | Status | Evidence |
|----|--------|----------|
| HRN-01..09 | Covered | verified elsewhere — `tests/harness/{00-layout,10-claude-md,20-precommit,30-workflows,40-adrs-and-research,50-agents-and-skills,60-mutation-scaffolding,70-planning-clean-gate}.bats`; `tests/harness/run.sh` reports **118/118 green** (Wave 1: HRN-05 restore + HRN-06 sudoers-0440 rubric resolved) |

---

## Summary

- **v0.4.0 families (RUST/TEST/CORE/VERB/PROV/DIST/GATE):** 20/20 in-scope IDs **Covered** (bats on the Rust build + Rust golden/proptest/mutation/drift tests + CI). ARCH-01 / PERF-01 = **Deferred (v2)**, explicitly out of scope — not uncovered.
- **Legacy families (BHV/RT/AGT/CLI/CAT/INST/DET/REUSE/REMEDIATE/MCP/ENABLE/WIRE/OPS/EL/UX/DEVT/ASST/WORK/DOC/TST):** all **Covered** by `tests/bats/*.bats` exercised on the Rust `provision` (42 files, 452 @tests).
- **HRN (harness meta-suite):** **Covered — verified elsewhere** (`tests/harness/` 118/118 green); correctly NOT forced into `tests/bats/`.
- **Rust unit floor:** `cargo test --workspace` = **338 passed, 0 failed** (217 + 121 across suites) — the golden/proptest/parity evidence backing CORE/TEST/DIST.

**Covered:** all in-scope families (v0.4.0 + legacy + HRN-verified-elsewhere).
**Uncovered:** 0 — no behavior family lost evidence in the Rust port.
**Deferred (v2, not a blocker):** ARCH-01, PERF-01.

The Rust rewrite was per-phase-gated (each of Phases 53–58 shipped behind a green suite), so this audit CONFIRMS — rather than discovers — that no family regressed. Every legacy behavior family still resolves to a live `@test` on the Rust build; every non-bats family (RUST/TEST/CORE Rust-unit, HRN harness, DOC/TST artifact) resolves to a named durable evidence path.

TST-07 gate: GREEN
