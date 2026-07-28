# Requirements: AgentLinux — v0.4.0 Rust Rewrite

**Defined:** 2026-07-27
**Core Value:** An agent can be dropped into any supported Linux system and *just work* — provisioned without permission fights. The rewrite must preserve that value **exactly** (zero observable change) while moving the implementation to a tested Rust binary.

**Prime directive:** the ~11k-LOC bats behavior suite is the language-agnostic executable spec (ADR-002) and the acceptance oracle. **No requirement below is "Complete" until the full bats suite is green on the Rust build.** Nothing user-visible changes.

## v1 Requirements

Requirements for the v0.4.0 milestone. Each maps to a roadmap phase.

### Rust Foundation (RUST)

- [x] **RUST-01**: `cargo build --release --target x86_64-unknown-linux-musl` produces a single fully-static `agentlinux` binary with no dynamic libc dependency (verified by `ldd` reporting "not a dynamic executable").
- [x] **RUST-02**: CI builds, `clippy`-lints, `rustfmt`-checks, and unit-tests the Rust binary on every PR; the Rust job is added to the Docker matrix and TS jobs retire per-area as code ports over.
- [x] **RUST-03**: A de-risking spike ports `classify` + `divergence` + one gnarly provisioner unit (e.g. `detect/nodejs.sh` or npm-prefix reconciliation) to Rust behind the existing bats tests, and records measured agent-loop metrics (iterations-to-green, token cost, cargo-timeout + crate-hallucination incidents) to calibrate the remaining port.

### Testing Bedrock (TEST)

- [x] **TEST-01**: The pure-logic core has `proptest` property tests asserting its invariants (e.g. classify is total & deterministic; `sticky ⇒ status ∈ {synced, pinned-override}`; latest-resolution output always satisfies the constraint or returns a typed error).
- [ ] **TEST-02**: `cargo-mutants` runs on the pure-logic crate in CI and reports a mutation score; the score is gated at an agreed threshold (advisory → gate) — the practice that motivated the rewrite is operational, not aspirational.
- [ ] **TEST-03**: The catalog JSON Schema is generated from the Rust catalog types via `schemars` (single source of truth); CI fails if the committed `schema.json` drifts from the generated output.
- [x] **TEST-04**: A `node-semver` → Rust `semver` behavior-parity audit documents every range/prerelease case the catalog uses, backed by a golden test asserting identical `satisfies`/`maxSatisfying`/`valid` verdicts on the current catalog's version fields.

### Pure-Logic Core Parity (CORE)

- [ ] **CORE-01**: Six-state version classification returns verdicts identical to the TS `classify` across a golden corpus of `(sentinel, installed, pinned, sticky)` inputs.
- [ ] **CORE-02**: `computeDivergence` + `resolveLatestFor` (semver `maxSatisfying`) match TS outputs across the golden corpus, including the zero-match error path.
- [ ] **CORE-03**: Detect gates (reuse/remediate/presence), pin-spec parsing, and category derivation match TS outputs across the golden corpus.

### Registry CLI Verbs (VERB)

- [ ] **VERB-01**: `list / install / remove / upgrade / pin / adopt` produce contract-equivalent stdout + exit codes to the TS CLI — verified green by the existing `CLI-*` and `50-agents`/list/upgrade/pin bats tests.
- [ ] **VERB-02**: The subprocess dispatcher runs recipes as the target user (`sudo -u`), streams output (tee), enforces a timeout, and escalates SIGTERM→SIGKILL — verified by the dispatcher/streaming behavior tests.
- [ ] **VERB-03**: The recipe env-var contract (the six `AGENTLINUX_*` names) is generated from a single typed Rust source, and the ~25 unchanged Bash recipes run correctly against it (a rename cannot silently desync CLI and recipes).

### Provisioner (PROV)

- [ ] **PROV-01**: Provisioning (agent-user creation, sudoers drop-in, NodeSource Node, PATH/env wiring to `/etc/agentlinux.env`, registry-CLI staging) leaves the system in the same observable state as the Bash provisioner — verified by the `RT-*` / `AGT-*` bats across all six invocation modes (interactive login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u`, `sudo -u -i`).
- [ ] **PROV-02**: Detection / remediation / reuse / idempotency logic is consolidated into the Rust binary; the duplicated `CANONICAL_PATHS` / `GSD_SYSTEM_PATH` maps are deleted from Bash (single source of truth in Rust).
- [ ] **PROV-03**: Distro detection and the aware-install reuse/remediate/bail paths behave identically to today on Ubuntu 22.04/24.04/26.04 **and** AlmaLinux 9 (`DET-*` / `REUSE-*` / `REMEDIATE-*` bats green).

### Distribution (DIST)

- [ ] **DIST-01**: `scripts/build-release.sh` produces a reproducible x86_64 musl static tarball + `.sha256`; the curl-installer fetches, verifies the sha256, and installs it — with **no Node prerequisite for the CLI/provisioner itself** (the chicken-and-egg is gone). This is the **sole** distribution channel.
- [ ] **DIST-02**: The legacy optional fpm `.deb` path is **removed** — `packaging/deb/`, the `build-release.sh` `--deb`/`fpm` branch, and the `.deb` postinst bridge are deleted (the `.deb` was optional and unused; the curl-installer tarball is authoritative). ADR-006 ("curl-pipe-bash-plus-deb") is flagged for an update to reflect the tarball-only channel. Per-arch packaging + arch-detecting installer remain deferred while ARM is out of scope.

### Validation Gate (GATE)

- [x] **GATE-01**: Every phase ships behind a **green full bats suite** — no phase merges with a red or newly-skipped behavior test (validation is per-phase, first-class). *Cross-cutting invariant — folded into every phase's success criteria; anchored (traceability) to Phase 53 where it is first established.*
- [ ] **GATE-02**: The complete bats behavior contract passes on the Rust build across the Docker matrix (Ubuntu 22.04/24.04/26.04 + AlmaLinux 9) **and** the QEMU release gate.
- [ ] **GATE-03**: Every existing requirement ID / behavior family (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC) retains behavior or harness evidence on the Rust build (`behavior-coverage-auditor` reports zero uncovered).
- [ ] **GATE-04**: The canonical acceptance test — agent `claude` self-update without sudo, zero EACCES — passes on the Rust build against the live Anthropic CDN.
- [x] **GATE-05**: `master` stays shippable throughout — the rewrite lands on a parallel track with a per-phase rollback path; a broken Rust phase never blocks a hotfix release from `master`. *Cross-cutting invariant — folded into every phase's success criteria; anchored (traceability) to Phase 53 where it is first established.*

## v2 Requirements

Deferred — acknowledged but not in this milestone's roadmap.

### Multi-Arch (ARCH)

- **ARCH-01**: aarch64 (ARM64) musl static build + per-arch release tarballs + arch-detecting curl-installer. Gated on ARM entering project scope (currently permanently out of scope).

### Performance / Indexing (PERF)

- **PERF-01**: A persistent, invalidated version index so `agentlinux list` is always-fresh against out-of-band updates without re-probing every entry each run. Naturally enabled by the compiled binary; scoped as its own milestone once the rewrite lands.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Rewriting the ~25 per-agent `install.sh` recipes in Rust | They are irreducible npm/apt/curl glue and the catalog's extension point (CAT-03); they stay Bash behind the generated env-var contract. |
| Any change to observable behavior / new features | This is a like-for-like reimplementation; the bats contract must stay green unchanged. Feature work happens in later milestones. |
| ARM / multi-arch packaging | Deferred to ARCH-01 (v2) — ARM is currently out of project scope; a single x86_64 tarball ships today. |
| Mutation-testing *of Bash* | No tooling exists; the point is to move logic *out* of Bash into Rust where cargo-mutants applies. |
| Go or bundled-JS-binary alternatives | Decided against in `docs/research/v0.3.0/stack-reconsideration.md` (2026-07-27). |
| Full v0.3.x/v0.4.0 numbering reconciliation | The legacy "v0.4.0" rename here is minimal (free the tag); the full renumber remains its own planned pass. |

## Traceability

Each v1 requirement maps to exactly one phase. **GATE-01 and GATE-05 are cross-cutting invariants** re-asserted in *every* phase's success criteria; for coverage they are anchored to Phase 53 (where they are first established), so each requirement still maps to exactly one home phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RUST-01 | Phase 53 | Complete |
| RUST-02 | Phase 53 | Complete |
| RUST-03 | Phase 53 | Complete |
| TEST-01 | Phase 54 | Complete |
| TEST-02 | Phase 54 | Pending |
| TEST-03 | Phase 54 | Pending |
| TEST-04 | Phase 54 | Complete |
| CORE-01 | Phase 55 | Pending |
| CORE-02 | Phase 55 | Pending |
| CORE-03 | Phase 55 | Pending |
| VERB-01 | Phase 56 | Pending |
| VERB-02 | Phase 56 | Pending |
| VERB-03 | Phase 56 | Pending |
| PROV-01 | Phase 57 | Pending |
| PROV-02 | Phase 57 | Pending |
| PROV-03 | Phase 57 | Pending |
| DIST-01 | Phase 58 | Pending |
| DIST-02 | Phase 58 | Pending |
| GATE-01 | Phase 53 (cross-cutting — every phase) | Complete |
| GATE-02 | Phase 59 | Pending |
| GATE-03 | Phase 59 | Pending |
| GATE-04 | Phase 59 | Pending |
| GATE-05 | Phase 53 (cross-cutting — every phase) | Complete |

**Coverage:**

- v1 requirements: 23 total
- Mapped to phases: 23 (100%) ✓
- Unmapped: 0 ✓
- Phases: 7 (Phase 53–59); GATE-01 + GATE-05 additionally re-asserted in every phase's success criteria

---
*Requirements defined: 2026-07-27*
*Last updated: 2026-07-27 — roadmap created; all 23 v1 requirements mapped to phases 53–59 (v0.4.0 Rust Rewrite), 0 orphans.*
