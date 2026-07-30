# Phase 53: Rust Scaffold + De-Risking Spike - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning
**Mode:** Smart-discuss infrastructure-skip (no user-facing grey areas — like-for-like rewrite spike). Codebase scout populated below.

<domain>
## Phase Boundary

Prove the Rust rewrite is viable end-to-end at small scale, and lock in the two
cross-cutting invariants every later phase re-asserts. Concretely, this phase
delivers:

1. A cargo **workspace** that produces a single fully-static `x86_64-unknown-linux-musl`
   `agentlinux` binary (`ldd` → "not a dynamic executable"). (RUST-01)
2. CI that builds + `clippy` + `rustfmt --check` + unit-tests the Rust binary on
   every PR, added to the Docker matrix. (RUST-02)
3. A ported spike surface — `classify` + `divergence` (pure logic) + **one gnarly
   provisioner unit** — validated behind the **existing bats suite** with no
   newly-skipped tests. (RUST-03, GATE-01)
4. Recorded **agent-loop metrics** (iterations-to-green, token cost,
   cargo-timeout + crate-hallucination incidents) to calibrate the 54–59 port.
   (RUST-03)
5. The two invariants proven in practice: **GATE-01** (green full bats for the
   ported surface) and **GATE-05** (master stays shippable; parallel track on
   `worktree-stack-revisiting`; per-phase rollback).

Explicitly OUT of scope for the spike: porting the full CLI, the full provisioner,
distribution changes, or the property/mutation machinery (that is Phase 54).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (infrastructure phase)
All implementation choices are at Claude's discretion — this is a like-for-like
rewrite spike with no user-observable behavior change. The ROADMAP success
criteria + REQUIREMENTS (RUST-01/02/03, GATE-01/05) + codebase conventions guide
decisions. Recommended shape recorded below for the planner; not binding.

### Workspace layout (recommended)
- Cargo **workspace** with a pure-logic crate separated from the binary crate,
  so Phase 54's `proptest` + `cargo-mutants` can target the pure core in
  isolation: `crates/agentlinux-core` (pure, no I/O) + `crates/agentlinux` (bin;
  CLI + provisioner adapters). Keeps the "pure core" testable surface that the
  whole rewrite is justified by.
- Static musl is the release target; the dev/CI build may use the gnu target for
  speed, but the RUST-01 artifact + `ldd` assertion is musl.

### Spike provisioner unit (recommended)
- Port the **REUSE-03 reuse decision** (`plugin/lib/reuse/agents.sh`, 97 LOC) as
  the gnarly unit: it is the exact sync-pain exemplar the research doc quotes —
  it stops at 2 of 3 predicates because "semver-range satisfaction is non-trivial
  in bash," and it hand-maintains `REUSE_AGENT_CANONICAL_PATHS` that "MUST stay
  byte-identical" to `detect.ts`. Porting it to Rust (a) proves Rust does the
  semver predicate bash could not, and (b) lets the CANONICAL_PATHS map live once
  in Rust. High-signal for the thesis.
- Acceptable alternative if integration surface is too wide for a spike:
  `plugin/provisioner/30-nodejs.sh` npm-prefix reconciliation (174 LOC), per the
  research doc's other suggestion. Planner picks based on the smallest
  bats-validatable integration seam.

### bats integration (recommended)
- The ported surface must be reachable by the existing bats tests through the
  same observable interface (CLI subcommand stdout/exit or provisioner
  file/system state), so the language-agnostic spec (ADR-002) validates it
  unchanged. Prefer a seam where the Rust binary is swapped in behind the same
  invocation the bats test already makes — no bats edits beyond what a genuine
  behavior change would require (ideally zero).
- Docker note: the full bats suite OOMs mid-run in this VM; run targeted
  per-file bats containers for the ported surface and record which files were
  exercised (do not claim full-suite green from a partial run).

### Agent-loop metrics (recommended)
- Record to a phase artifact (e.g. `53-METRICS.md`): iterations-to-green per
  ported unit, wall-clock + token cost where observable, and any
  cargo-compile-timeout or crate-hallucination incidents. This is a first-class
  deliverable (RUST-03), not a side note — it is the evidence that calibrates
  the go/no-go for the bulk port.

</decisions>

<code_context>
## Existing Code Insights (from scout)

### Port surface — pure logic (spike ports classify + divergence)
- `plugin/cli/src/version/classify.ts` — 50 LOC, six-state version classifier;
  golden corpus in `plugin/cli/test/classify.test.ts`.
- `plugin/cli/src/upgrade/divergence.ts` — 72 LOC, `computeDivergence` +
  `resolveLatestFor` (semver `maxSatisfying`, zero-match error path); golden
  corpus in `plugin/cli/test/divergence.test.ts` (~10 KB, richest).
- `plugin/cli/src/catalog/category.ts` — 65 LOC (Phase 55 scope; noted for
  workspace layout).
- These are DI-tested pure functions — portable to Rust with the TS test tables
  reused as the parity golden corpus.

### Port surface — provisioner (spike ports one unit)
- `plugin/lib/reuse/agents.sh` — 97 LOC; REUSE-03 decision; carries
  `REUSE_AGENT_CANONICAL_PATHS` (line 31) + `REUSE_GSD_SYSTEM_PATH` (line 41),
  both duplicated from `plugin/cli/src/detect.ts`. Consumed by `prompt.sh` +
  `remediate.sh`.
- `plugin/provisioner/30-nodejs.sh` (174) and `plugin/lib/idempotency.sh` (198)
  are the other branch-dense candidates.

### The env-var recipe boundary (survives the rewrite — do NOT port recipes)
- `plugin/cli/src/runner.ts` hands recipes six untyped strings:
  `AGENTLINUX_PINNED_VERSION`, `_CATALOG_DIR`, `_AGENT_HOME`, `_SOURCE_KIND`,
  `_INSTALL_LOG`, `_PRESERVE_PATHS`. The ~25 `install.sh` recipes stay Bash; the
  Rust binary must emit this exact contract. (Contract-gen is Phase 56; the spike
  only needs to know the boundary exists.)

### Acceptance oracle
- `tests/bats/*.bats` — 41 files, 10,638 LOC. ADR-002: asserts observable system
  state, language-agnostic. This is the safety net; nothing is "done" until it is
  green on the Rust build for the ported surface.

### Integration points
- New code connects at: (a) the `agentlinux` binary entrypoint the CLI bats tests
  invoke, and (b) the provisioner sourcing/dispatch path the RT-*/AGT-* bats tests
  drive. The spike wires the smallest seam that keeps the relevant bats green.
- Toolchain is already bootstrapped this session: rustc/cargo 1.97.1, musl target
  + `musl-gcc`, clippy, rustfmt; static musl hello-world verified `ldd`-static.

</code_context>

<specifics>
## Specific Ideas

- The bats suite is a language-agnostic executable spec (ADR-002) — the spike's
  job is to prove a Rust build satisfies it for a real ported slice, not to add
  new behavior. Zero behavior-contract regression; zero newly-skipped tests.
- The spike's metrics are the milestone's decision input: if Rust's agent-loop
  cost (crate hallucination, cargo timeouts, iterations-to-green) is materially
  worse than estimated, that is a finding to surface, not to bury.
- Keep `master` (v0.3.6, shipped) untouched: all work on `worktree-stack-revisiting`.

</specifics>

<deferred>
## Deferred Ideas

- Property tests (`proptest`) + mutation gate (`cargo-mutants`) + `schemars`
  schema-gen + node-semver parity audit → Phase 54 (Testing Bedrock).
- Full pure-core port (category derivation, detect gates, pin-spec) → Phase 55.
- CLI verbs + generated env-var contract → Phase 56.
- Full provisioner port + CANONICAL_PATHS consolidation delete-from-Bash → Phase 57.
- musl tarball as sole channel + drop fpm .deb → Phase 58.

</deferred>
