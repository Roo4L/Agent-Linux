# Phase 55: Pure-Logic Core Parity - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning
**Mode:** Smart-discuss infrastructure-skip (like-for-like port of pure decision logic; no user-facing behavior change). Codebase scout populated below.

<domain>
## Phase Boundary

Port the REMAINING I/O-free decision core to Rust with byte-for-byte-equivalent
verdicts to the TS implementation across a golden corpus, guarded by the Phase-54
bedrock (proptest + cargo-mutants + parity golden). Deliverables:

- **CORE-01** — six-state `classify` verdicts identical to TS across a golden
  corpus. (Already ported in Phase 53 `classify.rs`; this phase RE-ASSERTS it via
  the corpus — likely no new port, just corpus coverage confirmation.)
- **CORE-02** — `computeDivergence` + `resolveLatestFor` match TS incl. the
  zero-match error path. (Already ported in Phase 53 `divergence.rs` + covered by
  the 54-01 parity golden; RE-ASSERT.)
- **CORE-03 (the NEW port)** — port to Rust with golden-corpus parity:
  1. **category derivation** (`plugin/cli/src/catalog/category.ts`, 65 LOC).
  2. **pin-spec parsing** (`parsePinSpec` in `plugin/cli/src/commands/pin.ts` —
     the PURE parser + `PinTarget` discriminated union; NOT the I/O `pinCmd`).
  3. **detect gates' pure decision cores** — `isCanonicalAgentPath` + the
     reuse/remediate/presence DECISION logic (`tryReuse` / `tryRemediate` /
     `detectPresence`), separating the pure decision (detected-state + entry →
     verdict) from the cache I/O.
- **GATE-01 / GATE-05** — full bats green for the ported surface (no regression /
  no newly-skipped); master shippable; parallel track; per-phase rollback.

OUT of scope: the cache I/O adapter (`readCachedAgentById`/`detectCachePath` — read
a JSON file), CLI verbs/dispatcher (Phase 56), the bash provisioner (Phase 57),
and deleting the duplicated CANONICAL_PATHS from TS/bash (Phase 57).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (infrastructure/port phase)
All choices at Claude's discretion — like-for-like port, verdicts pinned by the TS
golden corpora. Recommended shape below; not binding.

### Recommended
- New pure modules in `agentlinux-core`: `category.rs`, `pin_spec.rs`, and the pure
  detect-gate decisions in `detect_gates.rs` (or fold into existing modules). Keep
  the crate PURE (no std::process/fs/env) so Phase-54 cargo-mutants + proptest keep
  scoping to it — the cache-read I/O lives in the bin/adapter, NOT the core.
- **Separate pure decision from I/O in the detect gates:** `tryReuse`/`tryRemediate`/
  `detectPresence` currently call `readDetectedAgent` (cache I/O). Port the DECISION
  (given a `DetectedAgent` value + `CatalogEntry` → gate verdict) into the pure core;
  the cache read is an adapter seam consumed later (Phase 56). This mirrors the
  Phase-53 pattern (reuse::agent_decision pure; env-read in the bin).
- **Golden corpus = the TS test tables** verbatim: `category.test.ts` (160),
  `pin.test.ts` (553, the parsePinSpec cases), and the detect-gate test cases. Port
  them as Rust `#[test]` golden modules; every verdict byte-identical to TS.
- **Note the reuse overlap:** the bash provisioner's `reuse::agent_decision` (ported
  Phase 53, `reuse.rs`) is the PROVISIONER reuse decision; detect.ts's `tryReuse` is
  the CLI-side reuse gate — related but distinct (CLI uses the detect cache + version
  window). Keep both; do not conflate. CANONICAL_PATHS stays duplicated (Phase 57).
- Extend the Phase-54 machinery: add proptest invariants + the cargo-mutants gate
  naturally covers the new pure modules (same `--package agentlinux-core` scope).

</decisions>

<code_context>
## Existing Code Insights (from scout)

### Already ported (do NOT re-port; re-assert via corpus)
- `rust/crates/agentlinux-core/src/`: classify.rs, divergence.rs, reuse.rs,
  semver_shim.rs, types.rs (+ schema_gen, proptest_strategies).

### CORE-03 port targets (TS source + golden corpus)
- `plugin/cli/src/catalog/category.ts` (65) — category derivation; corpus
  `plugin/cli/test/category.test.ts` (160).
- `plugin/cli/src/commands/pin.ts` — `parsePinSpec` (line 52) + `PinTarget` union
  (line 47); PURE parser only. Corpus `plugin/cli/test/pin.test.ts` (553; the
  parse-spec cases — the pinCmd/sentinel-write cases are Phase 56 CLI).
- `plugin/cli/src/detect.ts` — pure gate deciders: `isCanonicalAgentPath` (32),
  `tryReuse` (165), `tryRemediate` (202), `detectPresence` (248). The I/O seam
  (`readDetectedAgent` (151) → `readCachedAgentById` (144) → `detectCachePath`
  (116)) is OUT of scope (adapter). `CANONICAL_PATHS` (16) + `GSD_SYSTEM_PATH` (28)
  are the duplicated maps (already in the Rust bin from Phase 53; consolidation is
  Phase 57 — keep duplicated here).

### Testing
- Phase-54 bedrock applies: new pure modules get proptest invariants + fall under
  the cargo-mutants `--package agentlinux-core` gate; parity pinned by golden.

</code_context>

<specifics>
## Specific Ideas

- This is the highest-value, most-testable slice — the pure decision core is what
  the whole rewrite exists to make testable. Byte-for-byte TS parity is the bar.
- Keep the core PURE; the cache-read I/O is a Phase-56 adapter seam, not core.
- master shippable; all on branch `worktree-stack-revisiting`.

</specifics>

<deferred>
## Deferred Ideas

- Cache-read I/O adapter (readCachedAgentById/detectCachePath) → Phase 56.
- CLI verbs + subprocess dispatcher + env-var contract → Phase 56.
- Provisioner port + CANONICAL_PATHS consolidation (delete-from-TS/bash) → Phase 57.

</deferred>
