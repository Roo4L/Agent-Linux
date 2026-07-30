# Phase 59: Full Validation Gate - Context

**Gathered:** 2026-07-29
**Status:** Ready for research
**Mode:** Smart-discuss validation-gate phase (the FINAL phase of v0.4.0). Not new
feature code — it PROVES the rewrite is complete + behavior-preserving at full matrix
scale, wires CI to gate on the Rust build, audits coverage, and validates the canonical
acceptance test. Codebase scout below.

<domain>
## Phase Boundary

Prove the rewrite is complete and behavior-preserving at full scale — the entire bats
behavior contract green on the Rust build across every supported distro on Docker AND
QEMU, every behavior family still covered, and the canonical self-update-without-sudo
acceptance test green against the live Anthropic CDN — so v0.4.0 can ship as a
like-for-like reimplementation with zero observable change.

- **GATE-02** — the complete bats contract passes on the Rust build across the Docker
  matrix (Ubuntu 22.04/24.04/26.04 + AlmaLinux 9) AND the QEMU release gate.
- **GATE-03** — every requirement ID / behavior family (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC)
  retains behavior or harness evidence on the Rust build; `behavior-coverage-auditor`
  reports zero uncovered.
- **GATE-04** — the canonical acceptance test: agent `claude` self-update WITHOUT sudo,
  zero EACCES, on the Rust build against the live Anthropic CDN. (This is THE test the
  whole project exists to pass — [[project-motivation]].)
- **GATE-01 / GATE-05** — whole-matrix confirms no behavior-contract regression / no
  newly-skipped vs. the TS/Bash baseline; master shippable at gate close — the Rust track
  is READY to become master, with the pre-cutover TS/Bash build retained as the rollback.

### What this phase does NOT do
It does NOT perform the final cutover (delete `plugin/cli/` TS + the Bash entrypoint +
the retained Bash reuse map). GATE-05 explicitly keeps them as the rollback path. On a
green gate, the Rust track is DECLARED ready; the actual master-merge + TS/Bash deletion
is the post-milestone cutover (or the milestone-complete step) — the researcher/planner
to confirm the boundary.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (validation-gate phase)
Parity pinned by the full bats contract on the Rust build + the coverage audit + the
live AGT-02 acceptance. Recommended shape below; not binding.

### Dev-runnable vs. CI/QEMU-only (the key structural question)
This dev VM OOMs on the FULL Docker bats suite (memory [[reference-docker-oom]]) and
cannot run QEMU or the live-CDN release gate directly. So the phase must SPLIT:
- **Dev-runnable (the in-phase floor):** per-file bats across the 4 distros (Docker),
  the `behavior-coverage-auditor` (GATE-03), a targeted AGT-02 self-update on the Rust
  build where network allows.
- **CI/QEMU-triggered (wired + documented, run by the pipeline):** the full Docker
  matrix (test.yml), nightly-qemu (`nightly-qemu.yml` + `tests/qemu/boot.sh`), and the
  release.yml 4-gate pipeline incl. the live-CDN AGT-02 gate. Phase 59 WIRES these to
  run/gate on the Rust build (Phase 58 made Rust the default artifact, so much may
  already flow) and documents them as pipeline-triggered — it does not fake a local
  full-matrix pass.

### Recommended (researcher + planner to finalize)
- Confirm `test.yml` (Docker matrix), `nightly-qemu.yml`, and `release.yml` build + gate
  on the RUST build (the musl provisioner is now the default; verify the CI actually
  exercises it, not a stale TS path). Wire any gap.
- Run `behavior-coverage-auditor` for GATE-03 — every requirement family has bats/harness
  evidence on the Rust build; emit the coverage report; fill any gap.
- Validate GATE-04 (AGT-02 self-update, zero EACCES) on the Rust build — via
  `51-agt02-release-gate.bats` on the Rust provisioner + a real `claude update` where the
  CDN is reachable.
- RESOLVE the carried pre-existing reds so the gate is truly green: the 13-reuse #29
  schema `compatibility_window` type mismatch (Phase-54 origin, red on both builds) +
  HRN-05/HRN-06 (harness meta-tests). These are the only known non-environment reds.

### The irreducible boundary
The QEMU + live-CDN gates genuinely require the CI/release environment — the in-phase
deliverable is that they are WIRED + green-in-CI (or documented as the pipeline gate),
not that they run in this dev VM.

</decisions>

<code_context>
## Existing Code Insights (from scout)

### Validation harnesses
- `tests/qemu/boot.sh` (25.9K) + `cloud-init/` + `cloud-images.txt` — the QEMU
  release-gate harness (fresh cloud images; the memory records a prior EL9-QEMU green run).
- `.github/workflows/`: `test.yml` (16.5K — the Docker matrix + the gated Rust job),
  `nightly-qemu.yml` (5.5K), `nightly-mutation.yml`, `release.yml` (15.5K — the 4-gate
  release pipeline incl. AGT-02 self-update against the live CDN).
- `tests/bats/` — 42 bats files (the full behavior contract).
- `tests/bats/51-agt02-release-gate.bats` — the AGT-02 canonical release gate (claude
  self-update, zero EACCES).

### Coverage
- `behavior-coverage-auditor` (`.claude/agents/behavior-coverage-auditor.md`) — the GATE-03
  auditor: cross-checks every requirement ID/family in REQUIREMENTS.md has bats/harness
  evidence. Runnable now.

### Known pre-existing reds to resolve (so the gate is genuinely green)
- `13-reuse.bats` #29 — schema `compatibility_window` type (`["string","null"]` vs the
  test's `"string"`; Phase-54-02 origin; red on BOTH the Rust and Bash builds).
- `HRN-05` / `HRN-06` (harness meta-tests) — noted in Phase-57/58 `deferred-items.md`.

</code_context>

<specifics>
## Specific Ideas

- FINAL phase — the milestone-closing gate. On green, gsd-autonomous proceeds to the
  milestone audit → complete → cleanup.
- Much of the gate is CI/QEMU/live-CDN — the in-phase floor is the dev-runnable subset +
  the CI wiring; the full matrix + QEMU + live-CDN are pipeline-gated (documented, not faked).
- GATE-04 (AGT-02 self-update, zero EACCES) is THE motivating acceptance test — treat it
  as the keystone.
- master shippable; branch `worktree-stack-revisiting`; the Rust track becomes
  merge-ready but the TS/Bash rollback substrate is RETAINED (GATE-05) — no cutover deletion.

</specifics>

<deferred>
## Deferred Ideas

- The final cutover (merge the Rust track to master; delete `plugin/cli/` TS + the Bash
  entrypoint + the retained Bash reuse map) — the POST-milestone step, once the gate is
  green and the maintainer green-lights the master-merge. Not this phase.
- The canonical product renumber (v0.4.0 is the milestone label; the shipped product
  version is 0.3.6) — deferred per the memory; a separate release decision.

</deferred>
