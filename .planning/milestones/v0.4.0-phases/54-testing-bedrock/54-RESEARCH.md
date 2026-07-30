# Phase 54: Testing Bedrock - Research

**Researched:** 2026-07-28
**Domain:** Rust property testing (`proptest`) · mutation testing (`cargo-mutants`) · JSON-Schema generation from Rust types (`schemars`) · node-semver→dtolnay-`semver` behavior-parity auditing — all layered on the Phase-53 pure core (`rust/crates/agentlinux-core`, 1027 LOC, 44 unit tests) before the bulk port.
**Confidence:** HIGH (schemars 1.2.2 output shape + attribute support empirically built & probed this session; crate versions confirmed via `cargo search`; every repo claim cites a file/line)

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | `proptest` property tests asserting the pure core's invariants (classify total & deterministic; `sticky ⇒ status ∈ {synced, pinned-override}`; latest-resolution output satisfies constraint or typed error) | §proptest Invariants — concrete generators (version-string / range strategies) + 4 property specs mapped to `classify`/`semver_shim`/`resolve_latest_for`. proptest 1.11.0 confirmed. |
| TEST-02 | `cargo-mutants` runs on the pure crate in CI, reports a mutation score, gated at an agreed threshold (advisory → gate) | §cargo-mutants CI Gate — exact `--package agentlinux-core` invocation, `--minimum-test-timeout`, `--in-diff` for PRs, `cargo install --locked` + `Swatinem/rust-cache` setup, GATE-05 guard shape mirroring the existing `rust` job. cargo-mutants 27.1.0 confirmed. |
| TEST-03 | Catalog JSON Schema generated from Rust catalog types via `schemars` (single SoT); CI fails if committed `schema.json` drifts from generated output | §schemars ↔ Hand-Written Schema Reconciliation (the highest-risk item) — empirical divergence table (schemars 1.2.2 built & probed), the exact derive attributes to match the field set, and Option (a) [generated SoT + drift-check + ajv reads generated file] recommended over (b). schemars 1.2.2 confirmed. |
| TEST-04 | `node-semver`→Rust `semver` behavior-parity audit doc + golden test on the catalog's ranges | §node-semver Parity Audit — the audit-doc contents + golden-test shape; the TS test corpora (`classify.test.ts`, `divergence.test.ts`) reused verbatim as the node-semver oracle (node deps uninstalled). |
| GATE-01 | Full bats green for ported surface; no regression / no newly-skipped behavior test | §CI Runtime Budget + §Validation Architecture — the pure core is not directly bats-visible this phase; the drift-check must keep the shipped ajv validation path GREEN. |
| GATE-05 | `master` stays shippable; a red mutants/test run can't block a non-Rust hotfix | §cargo-mutants CI Gate — the mutants + proptest steps sit behind the existing `rust`-job `guard` (`ready=false` when no code changed or `rust/Cargo.toml` absent), so a red Rust run never blocks a master hotfix. |
</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
No hard locks. CONTEXT.md §Implementation Decisions states: *"All implementation choices at Claude's discretion — testing/schema machinery, no user-observable behavior change."* This is an **infrastructure phase** (smart-discuss infrastructure-skip).

### Claude's Discretion (all of it — recommended shape below is non-binding)
- **proptest** targets the pure core's total functions (`classify`, `semver_shim::{parse_lenient,normalize_range}`, `reuse::agent_decision`, `resolve_latest_for`). Invariants over generated inputs; shrinking on failure. Generators kept catalog-realistic.
- **cargo-mutants** scoped `--package agentlinux-core`. Start advisory (report score), then set `--minimum-test-timeout` + an agreed threshold gate; a red mutants run must be gated so it can't block a master hotfix (GATE-05), same guard shape as the Phase-53 `rust` job.
- **schemars**: add `#[derive(JsonSchema)]` to the Rust catalog types (`agentlinux-core::types` — `CatalogEntry` etc.), generate `schema.json`, add a CI drift-check (`generated == committed`, else fail). The generated schema MUST still validate the real `plugin/catalog/catalog.json` and keep the ajv validator (`validate-catalog.mjs`) + pre-commit `catalog-schema-validate` hook GREEN. If exact byte-parity with the 109-LOC hand-written schema is impractical, document the reconciliation and make the DRIFT-CHECK authoritative (generated is the SoT), updating the ajv consumer to read the generated file.
- **semver parity (TEST-04)**: the live catalog uses only caret (`^2.1`) + compound comparators; `semver_shim` already handles these. This phase writes the audit DOC (every range/prerelease case) + a golden test locking `satisfies`/`maxSatisfying`/`valid` verdicts against the current catalog. Full prerelease edge-case audit stays here (TEST-04's home); do not expand catalog ranges.

### Deferred Ideas (OUT OF SCOPE)
- Full pure-core port (category derivation, detect gates, pin-spec) → **Phase 55**.
- CLI verbs + generated env-var contract → **Phase 56**.
- Provisioner port + `CANONICAL_PATHS` consolidation → **Phase 57**.
- Mutation-testing *of Bash* (no tooling exists) — permanently out of scope (REQUIREMENTS §Out of Scope).
</user_constraints>

## Summary

Phase 54 makes the testing rigor that *justified* the Rust rewrite operational on the pure `agentlinux-core` crate (classify/divergence/reuse/semver_shim/types — already built and green with 44 unit tests, verified `cargo test --all` → `44 passed` this session) before porting any more logic. Four deliverables layer machinery over the existing crate: property tests (`proptest`), a mutation gate (`cargo-mutants`), a generated catalog schema (`schemars`), and a node-semver parity audit + golden test. Nothing user-visible changes; the pure core is not directly bats-exercised this phase, so GATE-01's concern reduces to *"do not break the shipped ajv catalog-validation path"* — which the schemars work touches directly.

**The one high-risk item is TEST-03.** The catalog schema (`plugin/catalog/schema.json`, 109 LOC, hand-written draft-2020-12) is not a lint artifact — it is a **runtime dependency** loaded by `getValidator()` (`plugin/cli/src/catalog/schema.ts`) at CLI runtime, staged to `/opt/agentlinux/catalog/<ver>/schema.json` at install time, exercised by 12 `schema.test.ts` unit tests, and enforced by the `catalog-schema-validate` pre-commit hook. It has ~15 fields with `pattern`/`format`/`minLength` constraints and an `if/then` npm-requires conditional; the Rust `CatalogEntry` in `types.rs` deliberately mirrors only 5 read-by-the-core fields (`types.rs:14-30`). A botched generated schema breaks the shipped catalog validation on a fresh install. **Empirically this session I built schemars 1.2.2 and confirmed the achievable reconciliation:** it defaults to draft-2020-12, `definitions_path` already defaults to `$defs`, and `#[schemars(...)]` attributes reproduce `pattern`, `minLength`, `format: uri`, and arbitrary keywords — so a functionally-equivalent (ajv-strict-passing, catalog-validating) schema is achievable, though NOT byte-identical (optionals become a `["string","null"]` union). Recommend Option (a): make the generated schema the SoT, add a drift-check, and point all three ajv consumers at the generated file — with a `schema.test.ts` + `validate-catalog.mjs` green gate as the acceptance oracle rather than byte-parity.

The other three items are lower-risk and well-scoped by the Phase-53 groundwork: the pure crate is I/O-free by design (`lib.rs:5-7`) so `cargo-mutants --package agentlinux-core` scopes cleanly; the semver divergences are already isolated in `semver_shim.rs` with typed errors; and the TS test corpora (`classify.test.ts:36-93`, `divergence.test.ts:132-155`) already encode the node-semver expected verdicts, serving as the TEST-04 oracle without re-installing node-semver.

**Primary recommendation:** Add `proptest` (dev-dep) + `schemars` (with `derive` feature) to `agentlinux-core`; write 4 property-test modules over the existing pure fns; move `schema.json` generation into a `#[test]`-gated codegen (Option a: generated is SoT, ajv reads it, drift-check fails CI on divergence); write the TEST-04 audit doc + a golden test seeded from the TS corpora; and extend the existing gated `rust` job with a `cargo-mutants` step (advisory first, then `--minimum-test-timeout 20 --in-diff` on PRs, threshold-gated once a baseline exists) — all behind the existing `guard` so GATE-05 holds.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Property invariants over pure fns (TEST-01) | Pure-logic core (`agentlinux-core` `#[cfg(test)]`) | — | proptest exercises `classify`/`semver_shim`/`reuse`/`divergence` in isolation; no I/O to mock. |
| Mutation score + gate (TEST-02) | CI (`test.yml` `rust` job) over `agentlinux-core` | Local `cargo mutants` | Mutants only bite pure logic; the crate is separated precisely so `--package` scopes it. |
| Catalog schema generation (TEST-03) | Pure-logic core (`agentlinux-core::types` + a codegen test) | TS ajv consumers (read the generated file) | The Rust types own the shape; schema is a build artifact of them. The three ajv consumers are downstream readers. |
| Schema drift-check (TEST-03) | CI (`test.yml` `rust` job) | pre-commit (optional mirror) | `generated == committed` comparison; a Rust job step, mirroring how `cli-unit` gates. |
| node-semver parity audit + golden test (TEST-04) | Pure-logic core (`semver_shim` `#[cfg(test)]` + a Markdown audit doc) | TS corpora as oracle | The shim owns the divergence; the audit formalizes it; the TS tests are the recorded node-semver verdicts. |
| Shipped ajv catalog validation (GATE-01 keep-green) | TS (`validate-catalog.mjs`, `catalog/schema.ts`, `schema.test.ts`) — UNCHANGED behavior | — | Must stay green; the generated schema must satisfy ajv strict + validate the real catalog + pass the 12 fixture tests. |

## Standard Stack

### Core (additions this phase)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `proptest` | 1.11.0 | Property tests + shrinking on the pure core (TEST-01) | De-facto Rust property-testing crate (Hypothesis-style); mature, wide adoption `[VERIFIED: cargo search this session]` |
| `schemars` | 1.2.2 | Generate `catalog/schema.json` from `agentlinux-core::types` (TEST-03) | The standard Rust JSON-Schema generator; v1.x defaults to draft-2020-12 (matches the hand-written schema's meta-schema) `[VERIFIED: built & ran schemars 1.2.2 this session — emitted `"$schema":".../draft/2020-12/schema"`]` |

### Supporting (CI tooling, not a crate dep)
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `cargo-mutants` | 27.1.0 | Mutation gate on the pure crate (TEST-02) | Installed in CI via `cargo install --locked cargo-mutants` (cache via `Swatinem/rust-cache`); NOT a `Cargo.toml` dependency — it's a cargo subcommand binary `[VERIFIED: cargo search this session]` |

### Already-present deps (reused, no version change)
| Library | Version | Role this phase |
|---------|---------|-----------------|
| `semver` (dtolnay) | `=1.0.28` (pinned, `Cargo.toml:12`) | The parity subject (TEST-04). Pinned exactly because `semver_shim` reproduces *its* divergences — **do not bump** this phase. |
| `serde` + `serde_derive` | 1.0.229 | `#[derive(JsonSchema)]` composes with the existing `#[derive(Deserialize/Serialize)]` on `types.rs`. |
| `thiserror` | 1.0.69 | Typed errors (`SemverError`, `DivergenceError`) that TEST-01 asserts are returned (never panic). |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `proptest` | `quickcheck` | proptest has better shrinking + integrated regression persistence (`proptest-regressions/`); proptest is the modern default. No reason to deviate. |
| `cargo-mutants` | `mutagen` | `mutagen` is largely unmaintained and nightly-only; `cargo-mutants` is stable-channel, actively maintained (sourcefrog), and the REQUIREMENTS name it explicitly. |
| schemars-generated SoT (Option a) | keep hand-written schema + assert Rust-type ⊇ schema (Option b) | Option (b) avoids reshaping the ajv consumers but leaves TWO hand-maintained artifacts that drift (the exact problem TEST-03 exists to kill). Option (a) is recommended — see §TEST-03 Recommendation. |
| `#[schemars(...)]` attribute-matching | schemars `transform` closures / post-process the JSON | Attributes are declarative and travel with the type; a post-process transform is a second place to maintain. Prefer attributes; use `transform`/`extend` only for the `if/then` conditional + `$id` that attributes can't express. |

**Installation (this phase):**
```toml
# rust/crates/agentlinux-core/Cargo.toml
[dependencies]
semver = "=1.0.28"                                  # unchanged
serde = { version = "1", features = ["derive"] }    # unchanged
thiserror = "1"                                       # unchanged
schemars = { version = "1.2.2", features = ["derive"] }  # NEW (TEST-03) — non-dev: types derive JsonSchema

[dev-dependencies]
proptest = "1.11.0"                                  # NEW (TEST-01) — test-only
serde_json = "1"                                      # NEW — the codegen test serializes the schema to compare/emit
```
> `schemars` is a **non-dev** dependency because `#[derive(JsonSchema)]` on `CatalogEntry` (a public type) is part of the crate's compiled surface. If the schema codegen is confined to a `#[cfg(test)]`/`tests/` binary and the derive is feature-gated, `schemars` could be dev-only — the planner should pick; simplest is non-dev with the derive always on. `proptest` is dev-only.

**Version verification (this session):**
```
cargo 1.97.1 (c980f4866 2026-06-30)
proptest = "1.11.0"   cargo-mutants = "27.1.0"   schemars = "1.2.2"  (cargo search, this session)
schemars 1.2.2 features: default=[derive,std]; has `semver1` feature (JsonSchema for semver types)
cargo test --all → agentlinux-core: 44 passed; 0 failed  (this session)
```

## Package Legitimacy Audit

All are ecosystem-canonical Rust crates; `proptest`/`schemars` were flagged Phase-54-approved in the Phase-53 audit (`53-RESEARCH.md:104-106`) and re-confirmed via `cargo search` this session. `cargo-mutants` is a widely-used cargo subcommand (sourcefrog). No SLOP/SUS.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| proptest | crates.io | mature | high | github.com/proptest-rs/proptest | OK | Approved (dev-dep) |
| cargo-mutants | crates.io | mature | high | github.com/sourcefrog/cargo-mutants | OK | Approved (CI tool, `cargo install`) |
| schemars | crates.io | mature | high | github.com/GREsau/schemars | OK | Approved (dep) |
| serde_json | crates.io | mature (serde-team) | ~billions | github.com/serde-rs/json | OK | Approved (dev-dep) |

**Packages removed due to SLOP verdict:** none
**Packages flagged as suspicious (SUS):** none

*Note on `cargo-mutants` in CI:* pin the install for reproducibility — `cargo install --locked --version 27.1.0 cargo-mutants` — so a silent upstream bump can't change the mutation set mid-milestone.

## Architecture Patterns

### System Architecture Diagram

```
  ┌──────────────────────── agentlinux-core (PURE crate — the subject) ─────────────────────────┐
  │  types.rs (CatalogEntry, Sentinel, Status, DivergenceReport)                                 │
  │  classify.rs → semver_shim.rs (eq/gt/max_satisfying/normalize_range/parse_lenient)           │
  │  divergence.rs (compute_divergence, resolve_latest_for → typed DivergenceError)              │
  │  reuse.rs (agent_decision → Decision{Reuse,Remediate,Create})                                │
  └───────┬───────────────────────┬────────────────────────────┬─────────────────────────────┬──┘
          │ TEST-01               │ TEST-03                     │ TEST-04                      │ TEST-02
          ▼ proptest              ▼ #[derive(JsonSchema)]       ▼ golden test                  ▼ cargo-mutants
   property modules          schema codegen (test)        semver_shim parity          --package agentlinux-core
   (invariants over          emits schema.json            asserts satisfies/          injects mutants; the 44
    generated inputs;         from Rust types             maxSatisfying/valid          unit + new proptest cases
    shrinking on fail)             │                       == node-semver verdicts      must KILL them
                                   ▼                        (oracle = TS corpora)             │
                        drift-check (CI): generated == committed?  ──fail──► block PR         ▼
                                   │                                              CI `rust` job (gated by
                                   ▼  generated schema.json is the SoT             `guard`: ready=false when
              ┌──── ajv consumers READ the generated file (unchanged behavior) ───┐  no code changed / no
              │ validate-catalog.mjs (pre-commit)  ·  catalog/schema.ts getValidator│  rust/Cargo.toml → GATE-05
              │ (CLI runtime + /opt staging)  ·  schema.test.ts (12 fixture tests)  │  a red Rust run never
              └───────────────── must stay GREEN (GATE-01) ────────────────────────┘  blocks a master hotfix)
```

Primary trace (TEST-03, the risky path): the Rust `CatalogEntry` derives `JsonSchema`; a `#[test]` (or `tests/` bin) calls `schemars::schema_for!(Catalog)`, serializes it, and (a) writes `plugin/catalog/schema.json` when run with an env flag / `--write`, and (b) otherwise asserts the committed file byte-equals the freshly generated one (the drift-check). CI runs the assert form; a contributor who changes a Rust type regenerates and commits. All three ajv consumers keep reading `plugin/catalog/schema.json` (now generated) and must stay green against the real `catalog.json` + the 12 fixtures.

### Recommended Project Structure (additions only)
```
rust/crates/agentlinux-core/
├── Cargo.toml                 # + schemars dep, + [dev-dependencies] proptest, serde_json
└── src/
    ├── types.rs               # + #[derive(JsonSchema)] + #[schemars(...)] attrs on CatalogEntry & co.
    ├── classify.rs            # + #[cfg(test)] mod proptests (classify totality/determinism)
    ├── semver_shim.rs         # + #[cfg(test)] mod proptests (parse/normalize totality) + parity golden test
    ├── divergence.rs          # + #[cfg(test)] mod proptests (resolve_latest_for output-satisfies-or-typed-error)
    ├── reuse.rs               # + #[cfg(test)] mod proptests (sticky/decision invariants)
    └── schema_gen.rs (NEW)    # schemars codegen: `schema_json()` + a #[test] drift-check/emit
plugin/catalog/schema.json     # BECOMES a generated artifact (Option a) — header comment marks it generated
docs/audits/v0.4.0/            # NEW: TEST-04-node-semver-parity.md (the audit doc)
.github/workflows/test.yml     # extend the existing `rust` job: + mutants step, + schema-drift step
```
> The `docs/audits/v0.4.0/` dir already exists (`.pre-commit-config.yaml:23` references `docs/audits/v0.4.0/SEC-*`), so the TEST-04 audit doc lands beside the existing SEC audits — a consistent home. **Confidence: MEDIUM** (a discretion layout call; planner may prefer `docs/research/v0.4.0/`).

### Pattern 1: schema codegen behind a #[test] drift-check (the standard schemars-in-CI idiom)
**What:** A single function returns the pretty-printed schema JSON; one `#[test]` either *emits* it (when `UPDATE_SCHEMA=1`/`--write`) or *asserts* the committed file matches. CI runs the assert; contributors run the emit after changing a type.
**When to use:** TEST-03. This is the canonical "generated file with a CI freshness gate" pattern (same shape as `sync-codex-agents.sh --check` at `.pre-commit-config.yaml:97-102`, which the repo already uses for a generated-artifact drift-check).
**Example:**
```rust
// agentlinux-core/src/schema_gen.rs
// Source: schemars 1.2.2 API, built & probed this session.
use schemars::JsonSchema;

#[derive(JsonSchema)]
struct Catalog { version: String, agents: Vec<crate::types::CatalogEntry> }

/// The catalog schema, generated from the Rust types — the single source of truth (TEST-03).
pub fn schema_json() -> String {
    let schema = schemars::schema_for!(Catalog);
    serde_json::to_string_pretty(&schema).unwrap() + "\n"
}

#[cfg(test)]
mod tests {
    use super::*;
    const SCHEMA_PATH: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../plugin/catalog/schema.json");
    #[test]
    fn schema_is_not_drifted() {
        let generated = schema_json();
        if std::env::var("UPDATE_SCHEMA").is_ok() {
            std::fs::write(SCHEMA_PATH, &generated).unwrap();   // emit mode (dev)
            return;
        }
        let committed = std::fs::read_to_string(SCHEMA_PATH).unwrap();
        assert_eq!(committed, generated, "schema.json drifted — run UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema_is_not_drifted");
    }
}
```
> **Purity caveat:** the drift-check test reads a file (`std::fs`), which the crate forbids in *non-test* code (`lib.rs:5`). That is fine — the ban is on production logic; `#[cfg(test)]` file reads are standard. Keep `schema_json()` itself pure (no I/O); only the test touches the filesystem. Alternatively put the drift-check in a `tests/` integration file to keep `src/` fs-free.

### Pattern 2: node-semver-oracle golden test (TEST-04)
**What:** A table of `(input, node-semver-verdict)` rows — sourced from the TS test corpora — asserted against the Rust `semver_shim` outputs.
**When to use:** TEST-04. The node-semver verdicts are already recorded in `divergence.test.ts:132-155` and `classify.test.ts:36-93`; reuse them verbatim so the golden test *is* the parity proof without re-installing node-semver.
**Example:**
```rust
// agentlinux-core/src/semver_shim.rs (#[cfg(test)])
// Oracle rows lifted from plugin/cli/test/divergence.test.ts:133-151 (node semver.maxSatisfying).
#[test]
fn parity_max_satisfying_matches_node_semver() {
    let versions: Vec<String> = ["1.0.0","1.1.0","1.2.0","2.0.0","2.1.0"].iter().map(|s| s.to_string()).collect();
    // node: maxSatisfying(v,"^1.0") === "1.2.0" ; "~1.1" === "1.1.0" ; "*" === "2.1.0" ; "^9.0" === null
    assert_eq!(max_satisfying(&versions, "^1.0").unwrap(), Some("1.2.0"));
    assert_eq!(max_satisfying(&versions, "~1.1").unwrap(), Some("1.1.0"));
    assert_eq!(max_satisfying(&versions, "*").unwrap(),   Some("2.1.0"));
    assert_eq!(max_satisfying(&versions, "^9.0").unwrap(), None);
}
```

### Anti-Patterns to Avoid
- **Chasing byte-parity with the hand-written schema.** schemars 1.2.2 emits `["string","null"]` for `Option<T>` and cannot be forced to a bare `"string"` via a simple setting (the `option_add_null_type` toggle was removed in schemars 1.x — the available `SchemaSettings` fields are `definitions_path, meta_schema, transforms, inline_subschemas, contract, untagged_enum_variant_titles`, verified this session). Byte-parity would require a bespoke post-process transform to maintain forever. **Make functional equivalence (ajv-strict-passes + validates the real catalog + 12 fixtures green) the acceptance oracle, not `diff schema.json`.**
- **Adding `schemars` as a dev-dep while deriving on a public type.** `#[derive(JsonSchema)]` on `pub struct CatalogEntry` needs `schemars` in `[dependencies]`, not `[dev-dependencies]`, or the crate won't compile for downstream users. (If codegen is fully test-confined via a feature gate, dev-dep works — decide once.)
- **Running `cargo mutants` un-gated / un-timeout'd in CI.** Without `--minimum-test-timeout` a slow-to-timeout survivor hangs the job; without the existing `guard`, a red mutants run blocks unrelated master hotfixes (violates GATE-05). Both are avoidable — see §cargo-mutants CI Gate.
- **Property tests that re-assert the existing unit tests.** proptest earns its keep on *invariants* (totality, determinism, "output satisfies constraint OR typed error"), not by re-listing the 44 concrete cases. Write invariants the unit tests can't express.
- **Bumping `semver` off `=1.0.28`.** It is pinned (`Cargo.toml:12`) because `semver_shim` reproduces *that version's* divergences; a bump could silently change parity. TEST-04 audits the pinned version.
- **Editing the ajv consumers' validation *semantics*.** Repointing them at the generated file is fine (Option a); loosening `strict: true`/`strictRequired: false` (`catalog/schema.ts:96`, `validate-catalog.mjs:41`) to make a bad generated schema pass is not — that hides drift.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON-Schema emission from Rust types | a hand-written `to_json_schema()` | `schemars` `#[derive(JsonSchema)]` | Hand-emitting is exactly the two-artifacts-that-drift problem TEST-03 kills; schemars is the standard, draft-2020-12-default generator. |
| Property input generation + shrinking | bespoke random loops in `#[test]` | `proptest` strategies (`prop::collection`, `prop_oneof!`, regex strategies) | Shrinking to minimal failing input is the whole value; hand-rolled fuzzing gives unusable failure reports. |
| Mutation testing | a script that greps/edits source | `cargo-mutants` | It understands Rust AST mutation operators + test scoping; a grep-based mutator is unsound. |
| node-semver verdicts for the oracle | re-installing `node-semver` + a JS harness | the existing TS test corpora (`classify.test.ts`, `divergence.test.ts`) | The verdicts are already recorded and CI-verified on the TS side; they ARE the oracle (node deps stay uninstalled). |

**Key insight:** every item here is a "make the rewrite's rigor real" tool — the phase's entire thesis is *don't hand-roll the things Rust's ecosystem does properly*. Hand-rolling any of these reintroduces the drift/brittleness the rewrite exists to remove.

## The Highest-Risk Item — schemars ↔ Hand-Written Schema Reconciliation (TEST-03)

### The concrete divergences (schemars 1.2.2 built & probed this session)

I built a schemars 1.2.2 probe and generated a schema for a `Catalog{version, agents:[Agent{...}]}` shape mirroring the hand-written one. **Enumerated divergences vs `plugin/catalog/schema.json`:**

| Dimension | Hand-written `schema.json` | schemars 1.2.2 default output | Reproducible via attribute? | Validation impact on real catalog |
|-----------|----------------------------|-------------------------------|-----------------------------|-----------------------------------|
| `$schema` (meta-schema / draft) | `.../draft/2020-12/schema` | `.../draft/2020-12/schema` — **identical** | n/a (default) | none — same draft `[VERIFIED: probe]` |
| `$defs` location key | `$defs` | `$defs` — **identical** (schemars 1.x default `definitions_path`) | n/a (default) | none `[VERIFIED: probe]` |
| Optional field type | bare `"type":"string"` (e.g. `version_constraint`) | `"type":["string","null"]` (nullable union) | **No** simple toggle (`option_add_null_type` removed in 1.x) — needs a transform | **NONE for the real catalog**: a present string still matches `[string,null]`; an absent optional is skipped (not `required`). Byte-diff only. `[VERIFIED: probe + ajv semantics]` |
| `additionalProperties:false` | present (root + `agent`) | present — from `#[serde(deny_unknown_fields)]` | Yes — add the serde attr | none `[VERIFIED: probe]` |
| `pattern` (id, npm_package_name, recipe paths, pinned_version, secret_env, endpoint_url) | present | absent by default | **Yes** — `#[schemars(regex(pattern = r"..."))]` → emits `"pattern"` | must add attrs or a *present-but-malformed* value would pass; the real catalog is well-formed so validation still passes, but the constraint is lost `[VERIFIED: probe emitted `"pattern"`]` |
| `minLength` (display_name, description, compatibility_window) | present | absent by default | **Yes** — `#[schemars(length(min = 1))]` → `"minLength"` | as above `[VERIFIED: probe emitted `"minLength":1`]` |
| `format:"uri"` (homepage, endpoint_url) | present | absent by default | **Yes** — `#[schemars(url)]` or `#[schemars(extend("format"="uri"))]` → `"format":"uri"` | as above `[VERIFIED: probe emitted `"format":"uri"`]` |
| `enum` on `source_kind` | inline `"enum":["npm","script","binary","mcp"]` | a `$defs/SourceKind` `$ref` with the same enum | mostly — a Rust `enum SourceKind` yields the ref-form; `#[schemars(inline)]` can inline it | none (ref vs inline both validate the same); byte-diff `[VERIFIED: probe]` |
| `if/then` npm-requires conditional (`allOf[0]`) | present (`source_kind==npm ⇒ npm_package_name required`) | **absent** — schemars won't derive a cross-field conditional | **Only via** `#[schemars(extend("allOf" = ...))]` with a hand-written JSON blob, or a `transform` | **material**: without it, an npm entry missing `npm_package_name` would validate. The real catalog has all npm entries populated, so it still passes — but the constraint the schema *exists to enforce* is dropped. Must be re-added via `extend`. |
| `$id` (`https://agentlinux.org/schemas/catalog.json`) | present | absent | Via `#[schemars(extend("$id" = "..."))]` on the root, or a transform | none (informational); add via extend for parity |
| `title`/`description` (root) | `"title":"AgentLinux Catalog"` + long `description` | `"title":"Catalog"` (from the struct name) | doc-comment → `description`; rename struct or `#[schemars(title="...")]` | none; cosmetic |
| `$defs` member name | `agent` (lowercase) | `Agent` (Rust type name) | rename type or accept | none (internal ref); cosmetic |
| `default:false` on `test_only` | present | schemars emits `default` for `#[serde(default)]` fields in some modes | partial | none |
| ajv `strict:true` compatibility | authored to pass (`strictRequired:false` set for the `allOf.then`) | must be re-verified: the `["string","null"]` union + `extend`-injected `allOf` must not trip ajv strict | test it | **gating** — the acceptance oracle is `schema.test.ts` + `validate-catalog.mjs` GREEN, not a diff |

### Recommendation: Option (a) — generated schema is the SoT + drift-check + ajv reads it

**Do NOT chase byte-parity.** The `["string","null"]` union is not reachable via a `SchemaSettings` toggle in schemars 1.x (verified this session) and would need a perpetual post-process transform. Instead:

1. **Add `#[derive(JsonSchema)]` + `#[schemars(...)]` attributes** to the `agentlinux-core::types` catalog types so `pattern`/`minLength`/`format`/`enum` match the field set. **Expand `CatalogEntry`** to carry all ~15 schema fields (it currently mirrors only 5 — `types.rs:14-30`) OR model a dedicated `SchemaCatalogEntry` for codegen. *(The full-field `CatalogEntry` is Phase-55 scope per `types.rs:5-7`; the planner must decide whether TEST-03 pulls the field expansion forward or uses a codegen-only struct — flag below.)*
2. **Re-add the two constraints schemars can't derive** — the `if/then` npm-requires conditional and `$id` — via `#[schemars(extend("allOf" = json!([...])))]` / `extend("$id" = ...)` on the root/agent type.
3. **Generate `plugin/catalog/schema.json`** from those types (Pattern 1) and **commit the generated file** (mark it generated with a header comment; note the ajv consumers ignore unknown top-level comments — JSON has none, so use a `$comment` or a sibling note).
4. **Point the three ajv consumers at the generated file** — they already read `plugin/catalog/schema.json` (`validate-catalog.mjs:10`, `catalog/schema.ts:71`, `schema.test.ts` via `AGENTLINUX_CATALOG_DIR`), so if the generated file lands at that path, **no consumer code changes** and the staging-to-`/opt` path is unaffected. This is the low-friction win.
5. **CI drift-check** (Pattern 1's assert-mode test) fails if a Rust type change wasn't regenerated-and-committed.
6. **Acceptance oracle = functional, not byte:** the phase is done when (i) the drift-check passes, (ii) `validate-catalog.mjs` validates the real `catalog.json` green, (iii) all 12 `schema.test.ts` fixtures pass (including the *negative* fixtures that must still be rejected), and (iv) the pre-commit hook is green. Byte-diff against the old hand-written schema is explicitly NOT a criterion.

**Why not Option (b)** (keep hand-written + assert Rust-type ⊇ schema): it leaves two hand-maintained artifacts (`schema.json` + the Rust types) that drift — the exact failure TEST-03 targets — and a "⊇" assertion is weaker than "this IS the schema." Only choose (b) if expanding the Rust types to the full field set is judged too invasive for this phase; if so, document it and defer full-SoT to Phase 55.

### ⚠️ Ambiguity flags for the planner (TEST-03)
- **"drift" semantics.** TEST-03 says *"CI fails if the committed `schema.json` drifts from the generated output."* This is unambiguous under Option (a): `drift == (committed != generated)`, a byte comparison of the *generated* file against its committed copy (NOT against the old hand-written schema). Confirm the planner reads it this way; the drift-check compares generated-vs-committed, and the *separate* keep-green gate is ajv-validates-real-catalog.
- **Field-set scope.** The Rust `CatalogEntry` mirrors 5 fields; the schema has ~15. Generating the *full* schema requires either expanding `CatalogEntry` (Phase-55 scope creep) or a codegen-only struct. **Planner must pick.** Recommendation: a codegen-only `SchemaCatalogEntry` in `schema_gen.rs` that carries all schema fields, keeping the lean `CatalogEntry` the core actually reads untouched until Phase 55 — this contains the blast radius.
- **Negative fixtures.** `schema.test.ts` has 12 tests including ones that assert *rejection* (bad id pattern, missing npm_package_name, etc.). The generated schema MUST still reject those — which is exactly why the `pattern`/`if-then` attributes/`extend` are non-optional, not cosmetic. The planner should make "all 12 fixtures green" an explicit task gate.

## cargo-mutants CI Gate (TEST-02)

### Local invocation (scoped to the pure crate)
```bash
# From rust/ — mutate ONLY the pure crate; the bin is thin adapter code, out of scope.
cargo mutants --package agentlinux-core --minimum-test-timeout 20
```
- `--package agentlinux-core` scopes mutation injection to the pure crate (the whole reason it's a separate crate — `lib.rs:1-7`). The `agentlinux` bin is excluded.
- `--minimum-test-timeout 20` (seconds) floors the per-mutant timeout so a mutant that induces an infinite loop is killed by timeout rather than hanging the runner. The crate's suite runs in ~0.00s (44 tests, verified this session), so 20s is generous headroom; tune down if wall-clock matters.
- cargo-mutants auto-discovers the workspace; run it from `rust/`.

### CI integration — extend the existing gated `rust` job (GATE-05 preserved)
Add steps to the **existing** `rust` job in `test.yml` (which already has the `guard` at `test.yml:147-157` that sets `ready=false` when no code changed or `rust/Cargo.toml` is absent, and `timeout-minutes: 15` at `test.yml:142`). This inherits GATE-05 for free — a red mutants run behind `if: steps.guard.outputs.ready == 'true'` never fires on a non-Rust hotfix.
```yaml
      - name: Install cargo-mutants (pinned, cached)
        if: steps.guard.outputs.ready == 'true'
        run: cargo install --locked --version 27.1.0 cargo-mutants
      - name: Mutation test (pure core) — ADVISORY first, then gated
        if: steps.guard.outputs.ready == 'true'
        working-directory: rust
        run: |
          # PRs: only mutate lines the diff touches — keeps wall-clock bounded.
          cargo mutants --package agentlinux-core --minimum-test-timeout 20 --in-diff <(git diff origin/master...HEAD -- 'crates/agentlinux-core/**') \
            || echo "::warning::surviving mutants (advisory — not yet gated)"
          # Once a baseline exists, drop the `|| echo` to GATE, or add `--error-if-survived` / threshold check.
```
- **Advisory → gate ratchet (TEST-02's "agreed threshold"):** cargo-mutants exits non-zero when mutants survive. Phase-in: (1) first run advisory (`|| echo ::warning::`), record the surviving-mutant list + score; (2) fix or `#[mutants::skip]`-annotate justified survivors; (3) flip to gating by removing the `|| echo` so a surviving mutant fails the job. A numeric threshold (e.g. "≥90% caught") is enforced by parsing `cargo mutants --json` output or simply by requiring zero un-skipped survivors — the latter is simpler and stricter.
- **`--in-diff` bounds PR cost:** mutating only diff-touched lines keeps per-PR mutation runtime small (the full crate is ~750 non-test LOC; a full run is still fast given the sub-second suite, but `--in-diff` is the safe default). A **scheduled full run** (`--package agentlinux-core` without `--in-diff`) can live in `nightly-*.yml` if the planner wants a full-crate score periodically — note `.github/workflows/nightly-mutation` already exists per AGENTS.md, so the planner should check whether TEST-02 belongs there vs the per-PR `rust` job.
- **Caching:** `Swatinem/rust-cache@v2` (already in the `rust` job at `test.yml:164-167`) caches `~/.cargo` incl. the installed `cargo-mutants` binary + the target dir, so the `cargo install` is a cache-hit no-op on warm runs.

### ⚠️ Ambiguity flags for the planner (TEST-02)
- **"agreed threshold" is undefined.** REQUIREMENTS §TEST-02 and CONTEXT.md both say "an agreed threshold (advisory → gate)" without a number. **The planner/user must set it.** Recommendation: start advisory, then gate at **zero un-skipped surviving mutants** on `--in-diff` (simplest, strictest, no score-parsing). If a percentage is preferred, parse `cargo mutants --json`. Surface this as a `checkpoint:human-decide` in the plan.
- **Per-PR vs nightly.** A repo `nightly-mutation` workflow already exists (AGENTS.md §CI). Decide: does TEST-02's per-PR gate live in the `rust` job (`--in-diff`, fast) with the *full* score in nightly, or is the whole thing nightly? Recommendation: `--in-diff` gate on PRs (keeps the merge gate honest without blowing the 15-min budget) + full-crate score nightly.

## proptest Invariants (TEST-01)

dtolnay `semver` does **not** ship a proptest/arbitrary `Strategy` (confirmed — no such crate in the dep tree; `proptest-derive` exists but there's no `semver` arbitrary support). **Generators are hand-written string strategies.** proptest 1.11.0.

### Generators (strategy shapes)
```rust
// A catalog-realistic full-version string generator.
fn version_str() -> impl Strategy<Value = String> {
    (0u64..50, 0u64..50, 0u64..50).prop_map(|(a,b,c)| format!("{a}.{b}.{c}"))
}
// A version string with node-loose shapes the shim must accept (v-prefix, 2-part partial).
fn loose_version_str() -> impl Strategy<Value = String> {
    prop_oneof![
        version_str(),
        version_str().prop_map(|v| format!("v{v}")),
        (0u64..50, 0u64..50).prop_map(|(a,b)| format!("{a}.{b}")),   // partial
    ]
}
// A range the catalog uses: caret, tilde, star, or a compound (space-separated).
fn range_str() -> impl Strategy<Value = String> {
    prop_oneof![
        (0u64..10, 0u64..10).prop_map(|(a,b)| format!("^{a}.{b}")),
        (0u64..10, 0u64..10).prop_map(|(a,b)| format!("~{a}.{b}")),
        Just("*".to_string()),
        (0u64..10, 10u64..20).prop_map(|(a,b)| format!(">={a}.0.0 <{b}.0.0")),  // compound (space!)
    ]
}
```

### The four property specs (mapped to existing pure fns)
| # | Invariant | Target fn | Property shape | Why it's an invariant (not a unit test) |
|---|-----------|-----------|----------------|------------------------------------------|
| P1 | **`classify` is total & deterministic** | `classify.rs::classify` | For any generated `(entry, sentinel?, installed?)`, `classify(..)` returns a `Status` and never panics; calling it twice gives the same result. | Totality over the *input space*, not 6 hand-picked rows. The `unwrap_or(false)` fallbacks (`classify.rs:36,41,51`) mean no input can panic — proptest proves it across generated versions incl. malformed ones. |
| P2 | **`sticky ⇒ status ∈ {synced, pinned-override}`** | `classify.rs::classify` | For any generated input where `sentinel.sticky == true`, the returned `Status` is `Synced` or `PinnedOverride` (never `OverrideAhead/Behind/DriftUndeclared` for a *matching* sentinel). | This is the CONTEXT/TEST-01 named invariant. Trace: sticky is only consulted at branch 4 (`classify.rs:46`) after drift (2) and synced (3) — so a sticky sentinel that agrees with `installed` lands in `{Synced, PinnedOverride}`. Guard the generator so `sentinel.version == installed` (else branch-2 drift legitimately precedes sticky) — **the invariant holds for the non-drift subspace; encode that precondition** (`prop_assume!`). |
| P3 | **latest-resolution output satisfies the constraint OR returns a typed error** | `divergence.rs::resolve_latest_for` | For any generated `(entry with version_constraint from range_str(), published_versions)`, either `Ok(v)` where `v ∈ published_versions` AND `v` satisfies the constraint, OR `Err(DivergenceError::{NoSatisfyingVersion,NoPublishedVersions,InvalidConstraint})` — never a panic, never an `Ok` violating the range. | The exact TEST-01 wording. Re-verify the returned `v` satisfies the range via `semver_shim::max_satisfying` on `[v]` — a strong postcondition the 5 unit rows can't cover. |
| P4 | **`semver_shim` parse/normalize totality** | `semver_shim.rs::{parse_lenient, normalize_range, max_satisfying}` | (a) `normalize_range` is idempotent (`normalize(normalize(x)) == normalize(x)`) — the `#[test]` at `semver_shim.rs:161` asserts one case; proptest generalizes. (b) `parse_lenient(loose_version_str())` never panics (Ok or typed Err). (c) `max_satisfying(vs, range_str())` never panics and any returned version is `∈ vs` and satisfies the range. | Totality + idempotence over the generated input space; the crate's no-panic contract (`semver_shim.rs:16-18`, threat T-53-01) becomes machine-checked. |

**proptest hygiene:** enable regression persistence (proptest writes `proptest-regressions/` — add it to git so a discovered counterexample is replayed forever). Keep `PROPTEST_CASES` at the default (256) for CI speed; the sub-second suite absorbs it.

## node-semver Parity Audit + Golden Test (TEST-04)

### What the audit DOC must cover (`docs/audits/v0.4.0/TEST-04-node-semver-parity.md`)
The doc formalizes the empirically-probed table from `53-RESEARCH.md:246-260`, extended to every range/prerelease shape. Required sections:

| Case class | Concrete examples (from the catalog + edges) | node-semver verdict (oracle) | Rust `semver 1.0.28` behavior | Shim handling |
|------------|----------------------------------------------|------------------------------|-------------------------------|---------------|
| Caret | `^2.1` (the only live `version_constraint`, catalog.json:12); `^1.0` | satisfies 2.5.0 true / 3.0.0 false | agrees | none needed (`semver_shim.rs` passes through) |
| Compound (space) | `>=2.0.0 <3.0.0` (every `compatibility_window`, e.g. catalog.json:13) | space-separated OK | **`VersionReq::parse` ERRORS on space** | `normalize_range` space→", " (`semver_shim.rs:54`) |
| Compound (open-ended) | `>=2026.2.17` (slack-mcp, catalog.json:380); `>=0.37.0 <1.0.0` | OK | single comparator parses; compound needs comma | `normalize_range` |
| Exact pin | `pinned_version` on every entry (e.g. `2.1.98`, `0.142.3`) | valid | `Version::parse` OK for full 3-part | `parse_lenient` |
| GA-date "version" | `2026.2.17`, `2025.5.1`, `2026.2.4` (hosted-MCP pins, catalog.json:378,398,419) | valid 3-part numeric | `Version::parse` OK (numeric major.minor.patch) | `parse_lenient` — **audit MUST confirm** these YYYY.M.D pins parse as ordinary semver (they do: 3 numeric dot-parts) |
| `v`-prefix | `v1.0.0` (from `<bin> --version` output) | eq/gt strip `v` | **`Version::parse` ERRORS on `v`** | `parse_lenient` strips leading `v`/`V` (`semver_shim.rs:70-73`) |
| Partial | `2.1` | loose-coerces to `2.1.0` in ranges | **`Version::parse` ERRORS on 2-part** | `parse_lenient` coerces (`semver_shim.rs:85-101`) |
| Prerelease vs non-pre range | `^1.0` vs `1.5.0-beta` ; `>=1.0.0 <2.0.0` vs `1.5.0-beta` | false (excluded) | false — agrees | none (opt-in prerelease agrees) |
| Zero-match | `^9.0` vs 1.x/2.x list | maxSatisfying → null (throws upstream) | `max_satisfying → None` → typed `NoSatisfyingVersion` | `divergence.rs:92-110` |
| Empty list | `[]` | throws "no published versions" | typed `NoPublishedVersions` | `divergence.rs:80-84` |
| `valid()` | `valid("2.1")`, `valid("v1.0.0")` | loose | strict `Version::parse` rejects both | never `Version::parse` a partial/`v` directly — always via `parse_lenient` |

The doc must also state the **known scope boundary**: the catalog uses NO `||` (OR) ranges and NO hyphen ranges (verified `53-RESEARCH.md:243-244` + this session's `catalog.json` read) — so those node-semver features are *documented as untested/unsupported* rather than silently assumed. If a future catalog adds them, TEST-04 must extend.

### Golden test shape
- Seed the golden table from the TS corpora **verbatim** — they are the recorded node-semver verdicts and are CI-verified on the TS side:
  - `divergence.test.ts:133` versions `["1.0.0","1.1.0","1.2.0","2.0.0","2.1.0"]` with `^1.0→1.2.0`, `~1.1→1.1.0`, no-constraint→`2.1.0`, `^9.0→throw`, `[]→throw` (`divergence.test.ts:135-155`).
  - `classify.test.ts:36-93` — the six-state rows (already ported to `classify.rs` tests, so parity is transitively proven; the audit records the mapping).
- Add a **catalog-driven** golden case: load the real `catalog.json` version fields (`pinned_version`, `version_constraint`, `compatibility_window`) and assert every one `parse_lenient`s / `normalize_range`+parses without error — a regression guard that a future catalog edit can't introduce a range the shim mis-handles. (This test reads a file → keep it `#[cfg(test)]` or in `tests/`.)

**Node-semver is NOT re-installed.** The oracle is the recorded TS verdicts (node deps stay uninstalled per Phase-53 setup, `53-RESEARCH.md:643-645`). This is an accepted MEDIUM-confidence stance: the TS side ran node-semver historically; the doc should note that if a verdict is ever in doubt, a one-off `node -e "require('semver').maxSatisfying(...)"` in a throwaway container is the tiebreaker — but the phase does not require it.

## Common Pitfalls

### Pitfall 1: generated schema drops a constraint and a bad catalog entry silently validates
**What goes wrong:** schemars doesn't derive `pattern`/`format`/`minLength`/the `if-then` npm conditional by default; the generated schema is *looser* than the hand-written one. The real catalog still passes (it's well-formed), so CI is green — but the schema no longer *rejects* a malformed future entry, and the 12 `schema.test.ts` negative fixtures start failing (they assert rejection).
**Why:** default schemars output is a structural schema, not a constraint schema.
**How to avoid:** add every `#[schemars(regex(...))]`/`length(...)`/`url`/`extend(...)` attribute to match the field set; make "all 12 `schema.test.ts` fixtures green (incl. negatives)" an explicit task gate, not just "real catalog validates."
**Warning signs:** `schema.test.ts` negative-case tests flip to failing; `validate-catalog.mjs` passes a catalog that the old schema rejected.

### Pitfall 2: ajv strict mode rejects the generated schema
**What goes wrong:** the ajv consumers run `strict: true` (`validate-catalog.mjs:41`, `catalog/schema.ts:96`). An `extend`-injected `allOf`/`if-then` or the `["string","null"]` union can trip ajv strict (unknown keyword, or strict-tuple/strict-types complaints) → `ajv.compile` throws → the pre-commit hook and CLI runtime crash.
**Why:** ajv strict is pickier than the schema's own draft.
**How to avoid:** run `validate-catalog.mjs` (which compiles under the exact ajv flags) as part of the drift-check acceptance BEFORE committing the generated schema; keep the existing `strictRequired:false` (it's there for the `allOf.then` — `validate-catalog.mjs:38-41`). Don't loosen other strict flags to paper over a bad generation.
**Warning signs:** `catalog-schema-validate: ajv not installed`-adjacent stack traces, or `strict mode: ...` errors from `ajv.compile`.

### Pitfall 3: `#[derive(JsonSchema)]` on the lean `CatalogEntry` generates a 5-field schema
**What goes wrong:** deriving on the current `CatalogEntry` (`types.rs:14-30`, 5 fields) yields a schema missing `display_name`, `install_recipe_path`, `source_kind`, etc. — the ajv validator then rejects the real catalog (which has those required fields) OR (if they're optional) drops the `required` contract.
**Why:** the core's `CatalogEntry` is a deliberate *subset* (`types.rs:5-7`), full field set is Phase-55.
**How to avoid:** use a codegen-only `SchemaCatalogEntry` carrying all ~15 schema fields (contains blast radius), OR pull the field expansion forward with the planner's explicit sign-off. Do NOT ship a 5-field schema.
**Warning signs:** `validate-catalog.mjs` errors `must have required property 'display_name'` against the real catalog.

### Pitfall 4: cargo-mutants hangs or gates a non-Rust hotfix
**What goes wrong:** un-timeout'd mutants hang; or an un-gated mutants step fails a master hotfix that touches no Rust.
**Why:** missing `--minimum-test-timeout`; step not behind the `guard`.
**How to avoid:** `--minimum-test-timeout 20`; put every mutants step behind `if: steps.guard.outputs.ready == 'true'` (the existing `rust`-job guard, `test.yml:152-157`) so GATE-05 holds; `--in-diff` on PRs to bound wall-clock under the 15-min cap.
**Warning signs:** the `rust` job hits `timeout-minutes: 15`; a docs-only PR shows a red mutants check.

### Pitfall 5: proptest P2 fails on legitimate drift inputs
**What goes wrong:** the "sticky ⇒ {synced,pinned-override}" property fails because the generator produced a sticky sentinel whose `version != installed` — which correctly classifies as `DriftUndeclared` (branch 2 precedes sticky at branch 4).
**Why:** the invariant holds only for the non-drift subspace; sticky is consulted *after* the drift check (`classify.rs:34-48`).
**How to avoid:** `prop_assume!(sentinel.version == installed)` (or generate them equal) so the property scopes to where sticky is actually reached. Document the precondition in the test.
**Warning signs:** shrink output shows a sticky sentinel with mismatched sentinel/installed versions.

## Runtime State Inventory

> Refactor-adjacent (adds test/schema machinery; TEST-03 changes `schema.json` from hand-written to generated). Inventory covers the artifacts that change ownership/provenance.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — all four deliverables operate on in-memory pure-fn inputs + committed test corpora. No datastore key/collection renamed. | none |
| Live service config | None — no external service consumes the schema/tests. | none |
| OS-registered state | None — no OS-registered names change. The generated `schema.json` still stages to `/opt/agentlinux/catalog/<ver>/schema.json` at install time (`catalog/schema.ts:66`) at the SAME path — provenance changes (generated vs hand-written) but the deployed path and filename are identical, so the CLI runtime + staging are unaffected. | none — verify the generated file lands at the identical repo path so staging is transparent |
| Secrets/env vars | New **test-only** env flags: `UPDATE_SCHEMA` (regenerate the schema) and proptest's `PROPTEST_CASES`. `cargo-mutants` reads no secrets. No production env-var name added/renamed. | document `UPDATE_SCHEMA=1` in the schema_gen module + a CONTRIBUTING note |
| Build artifacts | `schema.json` becomes a **generated** artifact (was hand-written) — add a `$comment`/header marking it generated so a contributor doesn't hand-edit it. New: `proptest-regressions/` dir (commit it — replays counterexamples). `cargo install cargo-mutants` binary (CI-cached, not committed). `rust/target/mutants*/` scratch (gitignore). | mark `schema.json` generated; commit `proptest-regressions/`; gitignore `**/mutants.out*` |

**The canonical question — after every file is updated, what still has the old contract?** The three ajv consumers keep reading `plugin/catalog/schema.json` at the same path; if the generated file lands there byte-for-byte-committed, nothing downstream changes behavior. The only provenance shift is *who authors* `schema.json` (Rust codegen, not a human) — enforced by the drift-check.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (Rust) | `cargo test` (built-in) + `proptest` (property strategies) — the existing 44 unit tests are the regression floor |
| Framework (mutation) | `cargo-mutants 27.1.0` (cargo subcommand, `cargo install --locked`) |
| Framework (schema) | `schemars 1.2.2` codegen + a `#[test]` drift-check; ajv (`validate-catalog.mjs`, `schema.test.ts`) as the keep-green oracle |
| Config file | `rust/crates/agentlinux-core/Cargo.toml` (+ deps); no separate proptest/mutants config needed (flags inline) |
| Quick run command | `cd rust && cargo test -p agentlinux-core` |
| Full suite command | `cd rust && cargo test --all && cargo mutants --package agentlinux-core --minimum-test-timeout 20` + `cd plugin/cli && pnpm exec node --test dist-test/test/schema.test.js` + `node plugin/cli/scripts/validate-catalog.mjs` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | classify totality/determinism; sticky invariant; resolve-latest postcondition; shim totality | property | `cargo test -p agentlinux-core` (new `#[cfg(test)] proptest!` modules) | ❌ Wave 0 |
| TEST-02 | mutation score + gate on the pure crate | mutation | `cargo mutants --package agentlinux-core --minimum-test-timeout 20 [--in-diff ...]` | ❌ Wave 0 |
| TEST-03 | schema generated from Rust types; drift-check; real catalog + 12 fixtures green | codegen + drift + ajv | `UPDATE_SCHEMA= cargo test -p agentlinux-core schema_is_not_drifted` + `node plugin/cli/scripts/validate-catalog.mjs` + `pnpm exec node --test dist-test/test/schema.test.js` | ❌ Wave 0 (schema.test.ts EXISTS — must stay green) |
| TEST-04 | node-semver parity audit doc + golden test | doc + golden | `cargo test -p agentlinux-core parity` + review `docs/audits/v0.4.0/TEST-04-*.md` | ❌ Wave 0 |
| GATE-01 | shipped ajv catalog validation stays green; no newly-skipped bats | keep-green | `node plugin/cli/scripts/validate-catalog.mjs` green; pre-commit `catalog-schema-validate` green; CI bats matrix unaffected | ✅ (validators exist) |
| GATE-05 | red mutants/test can't block a non-Rust hotfix | process/CI | mutants + proptest steps behind `if: steps.guard.outputs.ready == 'true'` in the `rust` job | ✅ (guard exists, `test.yml:152`) |

### Sampling Rate
- **Per task commit:** `cd rust && cargo test -p agentlinux-core && cargo clippy --all-targets -- -D warnings`
- **Per wave merge:** `cargo test --all` + `cargo mutants --package agentlinux-core --in-diff` + `node validate-catalog.mjs` + `schema.test.ts` green
- **Phase gate:** CI `test.yml` green (extended `rust` job: fmt/clippy/test/musl + **mutants + schema-drift** steps) on the PR before `/gsd-verify-work`; the drift-check + all 12 schema fixtures + `validate-catalog.mjs` green.

### Wave 0 Gaps
- [ ] `agentlinux-core/Cargo.toml` — add `schemars` (dep, `features=["derive"]`) + `[dev-dependencies] proptest = "1.11.0"`, `serde_json`
- [ ] `agentlinux-core/src/schema_gen.rs` — `schema_json()` + drift-check `#[test]` + `SchemaCatalogEntry` (full field set) with `#[schemars(...)]` attrs + `extend` for `if/then` + `$id`
- [ ] `agentlinux-core/src/{classify,semver_shim,divergence,reuse}.rs` — `#[cfg(test)] proptest!` modules (P1–P4) + generators
- [ ] `agentlinux-core/src/semver_shim.rs` — TEST-04 golden test seeded from the TS corpora + catalog-driven case
- [ ] `docs/audits/v0.4.0/TEST-04-node-semver-parity.md` — the audit doc
- [ ] `.github/workflows/test.yml` — extend the `rust` job: `cargo install cargo-mutants` + mutants step (`--in-diff`, guarded) + schema-drift step
- [ ] `plugin/catalog/schema.json` — regenerate from Rust types; mark generated; verify all three ajv consumers green
- [ ] `.gitignore` — `**/mutants.out*`; **commit** `proptest-regressions/`
- [ ] (decision) proptest-regressions dir + `UPDATE_SCHEMA` doc note in CONTRIBUTING

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| cargo/rustc | all four TEST items | ✓ | 1.97.1 | — |
| `proptest` (crates.io) | TEST-01 | ✓ (reachable) | 1.11.0 | — |
| `schemars` (crates.io) | TEST-03 | ✓ (built & ran this session) | 1.2.2 | — |
| `cargo-mutants` | TEST-02 | ✓ (installable via `cargo install`) | 27.1.0 | — |
| ajv + ajv-formats (plugin/cli) | TEST-03 keep-green | ✓ | existing (pnpm) | — |
| node/pnpm | schema.test.ts + validate-catalog.mjs | ✓ | node 22 | — |
| Docker (bats) | GATE-01 (indirect) | ✓ | — | targeted per-file runs (full suite OOMs in this VM — MEMORY reference_docker_oom) |
| node-semver | TEST-04 oracle | ✗ (uninstalled by design) | — | **the TS test corpora are the recorded oracle** (accepted MEDIUM confidence; one-off `node -e` in a container is the tiebreaker if ever needed) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** node-semver stays uninstalled — TEST-04's oracle is the committed TS verdicts (`classify.test.ts`, `divergence.test.ts`).

## Project Constraints (from CLAUDE.md / AGENTS.md)

- **Behavior tests in `tests/bats/` are the spec (ADR-002).** This phase adds machinery *around* the pure core; it must not newly-skip or regress any bats test (GATE-01). The pure core isn't directly bats-visible, so the live risk is the shipped **ajv** validation path (`catalog-schema-validate` hook) — keep it green.
- **No wrapper shims at `/usr/local/bin/`.** N/A this phase (no binary staging changes), but the generated `schema.json` must land at the SAME repo path so `/opt` staging (`catalog/schema.ts:66`) is unaffected.
- **Agent-owned `$HOME`; never `sudo npm install -g`; no privilege climbing.** `cargo install cargo-mutants` runs in agent-owned `~/.cargo`; no sudo.
- **Review loop (`.claude/skills/review/`)** must run on changed files before reporting complete — new/changed file types: Rust (`schema_gen.rs`, proptest modules), YAML (`test.yml`), Markdown (TEST-04 audit doc), generated JSON (`schema.json`).
- **`master` (v0.3.6, shipped) untouched — all work on `worktree-stack-revisiting` (GATE-05).** The mutants/proptest CI steps sit behind the existing `rust`-job guard so a red Rust run can't block a non-Rust master hotfix.
- **Session tracking in Jira project AL** for the concrete deliverable (code + doc-producing session, not research-only).
- **`.planning/` hygiene gate** (`planning-hygiene` job, `test.yml:288`) — keep intermediate GSD state off master per the planning-workflow skill.
- **Docker-only runs insufficient for release (QEMU gate)** — but this phase's acceptance is Rust unit/property/mutation + ajv, plus CI bats staying green; QEMU/GATE-02 is Phase 59.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `schema.json` hand-written + `types.ts` hand-mirrored (two artifacts that drift) | `schema.json` generated from Rust `agentlinux-core::types` (single SoT) + drift-check | this phase (TEST-03) | kills the schema/type drift class; contributors regenerate, CI enforces freshness |
| Rust core covered by 44 example unit tests only | + property tests (invariants over generated inputs) + mutation gate (score + ratchet) | this phase (TEST-01/02) | the rigor that justified the rewrite becomes operational, not aspirational — later ports (55–57) land behind a live gate |
| node-semver parity known only from the Phase-53 ad-hoc probe table | formal audit doc + golden test locking every catalog range/prerelease case | this phase (TEST-04) | parity is a maintained artifact; a future catalog range that breaks the shim is caught |

**Deprecated/outdated:** the schemars 1.x `SchemaSettings::option_add_null_type` toggle no longer exists (verified this session — the field set is `definitions_path, meta_schema, transforms, inline_subschemas, contract, untagged_enum_variant_titles`); older schemars-0.8 guidance that references it does not apply.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The `["string","null"]` union on optionals doesn't break ajv-strict validation of the real catalog (present strings match; absent optionals skipped) | TEST-03 | LOW — logically sound + confirmed by ajv semantics; the drift-check acceptance runs `validate-catalog.mjs` which would catch it empirically. Verify by running the validator on the generated schema. |
| A2 | schemars `#[schemars(extend("allOf"=...))]` can re-inject the `if/then` npm conditional in a form ajv-strict accepts | TEST-03 | MEDIUM — `extend` emits arbitrary keywords (probed working for `format`); the exact `if/then` blob must be tested against ajv strict. Task gate: `validate-catalog.mjs` + negative fixtures green. |
| A3 | The catalog's GA-date pins (`2026.2.17` etc.) parse as ordinary 3-part semver via `parse_lenient` | TEST-04 | LOW — they are numeric `major.minor.patch`; `Version::parse` handles them. The catalog-driven golden case proves it. |
| A4 | The TS test corpora are a faithful node-semver oracle (node deps uninstalled) | TEST-04 | MEDIUM — the TS tests ran node-semver historically and are CI-verified; a one-off `node -e` container is the tiebreaker if a verdict is ever disputed. |
| A5 | "agreed threshold" (TEST-02) = start advisory, gate at zero un-skipped survivors on `--in-diff` | TEST-02 | MEDIUM — the number is genuinely undefined in REQUIREMENTS/CONTEXT; **planner/user must confirm** (surface as checkpoint:human-decide). |
| A6 | A codegen-only `SchemaCatalogEntry` (full field set) is preferable to expanding the lean `CatalogEntry` this phase | TEST-03 | MEDIUM — contains blast radius (full-field CatalogEntry is Phase-55 scope, `types.rs:5-7`); planner may prefer to pull the expansion forward. |
| A7 | `docs/audits/v0.4.0/` is the right home for the TEST-04 doc | Project Structure | LOW — dir exists (`.pre-commit-config.yaml:23`); `docs/research/v0.4.0/` is an alternative. |

## Open Questions

1. **TEST-03 "drift" semantics — generated-vs-committed, not vs-old-hand-written.**
   - What we know: TEST-03 says "CI fails if the committed schema.json drifts from the generated output." Under Option (a) this is `committed != freshly-generated`.
   - What's unclear: whether the phase owner also expects a *documented reconciliation* vs the old hand-written schema (byte-diff report), or just functional equivalence.
   - Recommendation: drift-check = generated-vs-committed byte compare; acceptance = ajv-validates-real-catalog + 12 fixtures green; produce a one-time reconciliation note (in the plan or a short doc) enumerating the `["string","null"]`-union + `title`/`$defs`-name cosmetic diffs so reviewers understand the intentional non-byte-parity.

2. **TEST-02 threshold + per-PR-vs-nightly placement.**
   - What we know: "agreed threshold (advisory → gate)"; a `nightly-mutation` workflow already exists (AGENTS.md §CI).
   - What's unclear: the numeric threshold; whether the gate is per-PR (`--in-diff` in the `rust` job) or nightly (full crate).
   - Recommendation: per-PR `--in-diff` gate at zero un-skipped survivors (keeps merge gate honest under the 15-min cap) + full-crate score nightly. Surface the threshold as a `checkpoint:human-decide`.

3. **schemars field-set scope (codegen struct vs expand `CatalogEntry`).**
   - What we know: `CatalogEntry` mirrors 5 fields; the schema has ~15; full field set is Phase-55 (`types.rs:5-7`).
   - Recommendation: codegen-only `SchemaCatalogEntry` this phase; defer full-field `CatalogEntry` to Phase 55. Planner confirms.

## Sources

### Primary (HIGH confidence)
- **Empirical schemars 1.2.2 probes (this session)** — built & ran; confirmed draft-2020-12 default `$schema`, `$defs` default key, `#[schemars(regex/length/url/extend)]` → `pattern`/`minLength`/`format`/arbitrary keywords, `#[serde(deny_unknown_fields)]` → `additionalProperties:false`, `Option<T>` → `["string","null"]` union, and the removed `option_add_null_type` (available `SchemaSettings`: `definitions_path, meta_schema, transforms, inline_subschemas, contract, untagged_enum_variant_titles`).
- **`cargo search` (this session)** — proptest 1.11.0, cargo-mutants 27.1.0, schemars 1.2.2; `cargo info schemars` features (incl. `semver1`, `derive`).
- **`cargo test --all` (this session)** — `agentlinux-core: 44 passed; 0 failed`; `cargo tree` (semver has no arbitrary/proptest support).
- Repo source (this session): `rust/crates/agentlinux-core/src/{types,classify,semver_shim,divergence,reuse,lib}.rs`; `rust/Cargo.toml`; `rust/crates/agentlinux-core/Cargo.toml`; `plugin/catalog/schema.json`; `plugin/catalog/catalog.json`; `plugin/cli/src/types.ts`; `plugin/cli/src/catalog/schema.ts`; `plugin/cli/scripts/validate-catalog.mjs`; `plugin/cli/test/{schema,classify,divergence}.test.ts`; `.github/workflows/test.yml`; `.pre-commit-config.yaml`.
- `.planning/phases/53-.../53-RESEARCH.md` (the semver parity table, crate approvals, CI `rust`-job shape); `.planning/REQUIREMENTS.md` (TEST/GATE text); `54-CONTEXT.md`.

### Secondary (MEDIUM confidence)
- node-semver verdicts sourced from the committed TS test corpora (node deps uninstalled — the oracle, not re-run this session).
- MEMORY reference_docker_oom (full Docker bats suite OOMs mid-run in this VM → targeted runs).

### Tertiary (LOW confidence)
- The exact `extend("allOf"=...)` JSON blob for the `if/then` npm conditional under ajv strict — needs an in-phase probe against `validate-catalog.mjs` (A2).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — proptest/schemars/cargo-mutants versions confirmed via cargo search; schemars 1.2.2 built & ran.
- TEST-03 reconciliation: HIGH on the divergence enumeration (empirically probed) + achievability of `pattern`/`format`/`minLength`; MEDIUM on the `if/then` `extend` blob passing ajv strict (A2 — needs an in-phase probe).
- TEST-01 invariants: HIGH — the four properties map directly to existing pure fns whose branch order is cited; P2's non-drift precondition is derived from `classify.rs:34-48`.
- TEST-02 gate: HIGH on the invocation + guard shape (reuses the existing `rust` job); MEDIUM on the threshold (undefined — planner decides).
- TEST-04 audit: HIGH on the Rust-side behavior (isolated in `semver_shim.rs`, ported tests green); MEDIUM on node-side exactness (TS-corpora oracle, node uninstalled).

**Research date:** 2026-07-28
**Valid until:** ~2026-08-27 (stable toolchain; re-verify crate versions + re-probe schemars output if the phase slips a month or schemars minor-bumps).
