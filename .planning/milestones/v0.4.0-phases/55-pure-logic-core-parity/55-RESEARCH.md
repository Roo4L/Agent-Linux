# Phase 55: Pure-Logic Core Parity - Research

**Researched:** 2026-07-28
**Domain:** Rust port of TS pure decision logic (category derivation, pin-spec parsing, detect-gate deciders) with byte-for-byte golden-corpus parity
**Confidence:** HIGH (all findings grounded in this repo's source; no external unknowns)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None locked — CONTEXT.md marks this an "infrastructure/port phase; all choices at Claude's Discretion — like-for-like port, verdicts pinned by the TS golden corpora." The one hard, non-negotiable bar is **byte-for-byte TS parity** across the golden corpora, enforced by `GATE-01` (full bats green) and `GATE-05` (master shippable).

### Claude's Discretion
- Module layout: new pure modules `category.rs`, `pin_spec.rs`, and detect-gate deciders in `detect_gates.rs` (or folded into existing modules). *Recommended, not binding.*
- Keep the crate PURE (no `std::process`/`std::fs`/`std::env`) so the Phase-54 `cargo-mutants --package agentlinux-core` + proptest scope holds; the cache-read I/O lives in the bin/adapter, NOT the core.
- Golden corpus = the TS test tables verbatim (`category.test.ts`, the `parsePinSpec` cases in `pin.test.ts`, the detect-gate decision cases), ported as Rust `#[test]` golden modules.
- Extend Phase-54 machinery: add proptest invariants; the cargo-mutants gate naturally covers new pure modules (same `--package agentlinux-core` scope).

### Deferred Ideas (OUT OF SCOPE)
- Cache-read I/O adapter (`readCachedAgentById` / `readDetectedAgent` / `detectCachePath` / `readCacheAgents`) → **Phase 56**.
- CLI verbs + subprocess dispatcher + env-var contract (`pinCmd`, `adoptCmd`, `listCmd`, the `process.exit` shells) → **Phase 56**.
- Provisioner port + `CANONICAL_PATHS` / `GSD_SYSTEM_PATH` consolidation (delete-from-TS/bash) → **Phase 57**. **Keep the maps duplicated** (detect.ts:16,28 + bin `main.rs`:19,26-33 + bash) in Phase 55.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-01 | Six-state `classify` verdicts identical to TS across a golden corpus. **Already ported** (Phase 53 `classify.rs`). | §CORE-01/02 Re-assertion — recommends importing the 2 missing corpus rows (`decideVersion` stays out); classify.rs already covers all 7 six-state rows. |
| CORE-02 | `computeDivergence` + `resolveLatestFor` match TS incl. zero-match error path. **Already ported** (Phase 53 `divergence.rs`) + covered by 54-01 parity golden. | §CORE-01/02 Re-assertion — divergence.rs (14 `#[test]`) already covers all `resolveLatestFor` branches + both throw paths; re-assert only. |
| CORE-03 | **NEW port:** detect gates (reuse/remediate/presence), pin-spec parsing, category derivation match TS across the golden corpus. | §Standard Stack, §Architecture Patterns (3 pure ports), §The Pure/I-O Seam, §parsePinSpec Parity, §category Derivation Parity — full signatures + corpus mapping. |
| GATE-01 | Full bats suite green; no red/newly-skipped behavior test. Cross-cutting; re-asserted every phase. | §Validation Architecture — the ported surface is TS-unit-tested, not bats; parity is pinned by Rust `#[test]` golden modules. bats is unaffected (no observable behavior change). |
| GATE-05 | `master` stays shippable; parallel track; per-phase rollback. Cross-cutting. | §Architecture Patterns — additive-only (new modules under `agentlinux-core`); no TS deleted this phase; the TS remains the live implementation until Phase 56 wires the bin. |
</phase_requirements>

## Summary

Phase 55 is a **pure-function port with a golden oracle** — the lowest-risk, highest-value slice of the rewrite. Three self-contained TS deciders move to `agentlinux-core`: `deriveCategory` (65 LOC, `category.ts`), `parsePinSpec` (~23 LOC, `pin.ts:52-74`), and the three detect-gate decision cores (`isCanonicalAgentPath` + `tryReuse` + `tryRemediate` + `detectPresence`, `detect.ts:32-275`). Each has an existing TS unit-test table that becomes the byte-for-byte Rust `#[test]` golden corpus. The port pattern is already proven three times over in the crate (`classify.rs`, `divergence.rs`, `reuse.rs`): pure decider takes borrowed data + returns a value/typed-error; the bin owns every side effect. `[VERIFIED: rust/crates/agentlinux-core/src/reuse.rs, classify.rs]`

The single most important design act is **cutting the pure/I-O seam inside the detect gates.** In TS, `tryReuse`/`tryRemediate`/`detectPresence` each call `readCachedAgentById`/`readDetectedAgent`, which read `/run/agentlinux-detect.json` off disk (`detect.ts:116-159`). Phase 55 must port the *decision* — "given a `DetectedAgent` record + a `CatalogEntry` + the canonical-path map → verdict" — and leave the cache read as a Phase-56 adapter, mirroring exactly the Phase-53 split where `reuse::agent_decision` is pure and `cmd_reuse_decision` in `main.rs` reads env. `[VERIFIED: plugin/cli/src/detect.ts, rust/crates/agentlinux/src/main.rs]` There is one caveat: `tryReuse` also does a *host* `statSync` re-validation of the binary (`detect.ts:183-188`); that is I/O and stays in the adapter — the pure decision is `detectPresence`'s gate set (which the TS comment at `detect.ts:262-273` already documents as "tryReuse's gates minus its host statSync").

Two capability gaps block a clean port and must be closed in `semver_shim`: **`parsePinSpec` needs `semver.valid`** (returns the normalized version or None — `pin.ts:69`) and **the detect gates need `semver.satisfies(version, range)`** (`detect.ts:179,273`). The shim today exports `eq`/`gt`/`max_satisfying`/`parse_lenient`/`normalize_range` but **neither `valid` nor `satisfies`** `[VERIFIED: grep semver_shim.rs pub fn]`. Both are thin wrappers over machinery already present (`parse_lenient`, `VersionReq::parse` + `normalize_range`), and both MUST route through the shim so the node-semver divergence isolation holds.

**Primary recommendation:** Add `semver_shim::valid` + `semver_shim::satisfies`, then port the three deciders into `category.rs` / `pin_spec.rs` / `detect_gates.rs` as pure functions over a new `DetectedAgent` struct, porting each TS test table verbatim as the golden `#[test]` module + one proptest totality invariant each. Treat CORE-01/02 as a re-assertion: import the two missing `classify` corpus rows into `classify.rs`, confirm `divergence.rs` already covers CORE-02's branches, and add no new port for them.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| category derivation (`deriveCategory`) | Pure core (`agentlinux-core`) | — | Total function of `CatalogEntry.tags` + `source_kind` → `Category`; no I/O. |
| pin-spec parsing (`parsePinSpec`) | Pure core | — | Total function `&str → Result<PinTarget, PinSpecError>`; no I/O (semver via shim). |
| detect-gate DECISIONS (`isCanonicalAgentPath`, `tryReuse`, `tryRemediate`, `detectPresence`) | Pure core | — | Decision over a `DetectedAgent` value + `CatalogEntry` + canonical-path map → verdict; no I/O. |
| detect-cache READ (`readCachedAgentById`, `readDetectedAgent`, `detectCachePath`, `readCacheAgents`) | Adapter / bin | — | `std::fs` read of `/run/agentlinux-detect.json` — **Phase 56, OUT of scope.** |
| `tryReuse`'s binary-exists `statSync` re-validation | Adapter / bin | — | Host filesystem stat — I/O — stays in the adapter; the pure decider omits it (mirrors `detectPresence`). |
| canonical-path map (`CANONICAL_PATHS`, `GSD_SYSTEM_PATH`) | Passed in as params | Duplicated (TS + bin + bash) | Stays duplicated until Phase 57 consolidation; pure deciders receive it as arguments, never hardcode it (matches `reuse::agent_decision`). |

## Standard Stack

No new dependencies. Everything needed is already in the workspace, pinned by Phase 53/54.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `semver` (dtolnay) | `=1.0.28` (pinned, DO NOT bump) | Version parse/compare/range behind `semver_shim` ONLY | TEST-04 audit pinned this exact version; the shim reproduces THIS version's node-semver divergences. `[VERIFIED: rust/crates/agentlinux-core/Cargo.toml]` |
| `serde` + `serde` derive | `1` | Deserialize `CatalogEntry` / a new `DetectedAgent` from JSON in tests + (later) the adapter | Already a core dep; `types.rs` uses it. `[VERIFIED: Cargo.toml]` |
| `thiserror` | `1` | Typed `PinSpecError` (mirror the TS `throw new Error(...)` messages) | Already used by `divergence.rs::DivergenceError` + `semver_shim::SemverError`. `[VERIFIED: divergence.rs:18, semver_shim.rs:21]` |

### Supporting (dev-only)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `proptest` | `1.11` | Totality/determinism invariants for the new deciders (TEST-01 pattern) | Add one `proptests` submodule per new module, reusing `proptest_strategies.rs` generators. `[VERIFIED: Cargo.toml dev-deps]` |
| `cargo-mutants` | `=27.1.0` (CI) | Mutation gate over the pure crate | New modules fall under the existing `--package agentlinux-core --in-diff` gate automatically — no CI edit. `[VERIFIED: .github/workflows/test.yml:191-237]` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Extending `semver_shim` with `valid`/`satisfies` | Calling `semver::` directly in `pin_spec.rs`/`detect_gates.rs` | **Rejected.** Every version op MUST route through the shim (lib.rs contract, classify.rs:12-13, divergence.rs:14) so the node-semver divergences stay isolated in one module. Direct calls would reintroduce the exact bug TEST-04 fixed. |
| New `detect_gates.rs` module | Folding deciders into existing `reuse.rs` | `reuse.rs` is the *provisioner* reuse decision (bash `reuse::agent_decision`), a DISTINCT contract (see §Reuse Overlap). Folding would conflate two decision surfaces. Recommend a separate module. |
| A `DetectedAgent` struct | Passing `(id, status, path, version)` tuples | The TS `DetectCacheAgent` interface (detect.ts:106-111) is already a 4-field record; mirror it as a struct so the adapter (Phase 56) deserializes it directly and the signatures read cleanly. |

**Installation:** None. `cd rust && cargo build` uses the existing lockfile.

## Package Legitimacy Audit

> No external packages are added this phase. All crates (`semver`, `serde`, `thiserror`, `proptest`, `schemars`, `serde_json`) are already present in `rust/crates/agentlinux-core/Cargo.toml`, pinned, and vetted in Phases 53/54.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none added) | — | — | — | — | — | No new installs; legitimacy gate N/A |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
TS (live implementation, unchanged this phase)          RUST (agentlinux-core, additive)
──────────────────────────────────────────             ─────────────────────────────────

/run/agentlinux-detect.json  ──┐
                               │ readCacheAgents()  [I/O — Phase 56 adapter]
                               ▼
     DetectCacheAgent record  ─┼──────────────────►  DetectedAgent struct (serde)
                               │                              │
CatalogEntry ──────────────────┤                     CatalogEntry (types.rs, extend tags/source_kind)
CANONICAL_PATHS / GSD_SYS_PATH ─┤ (duplicated map)            │ (map passed in as params)
                               │                              ▼
        ┌──────────────────────┼─────────────────┐   ┌──────────────────────────────┐
        ▼                      ▼                 ▼    │  PURE DECIDERS (this phase)   │
   tryReuse()           tryRemediate()   detectPresence()   isCanonicalAgentPath()   │
   → ReuseHit|null      → RemediateHit|null → PresenceHit|null                        │
        │                                          │   deriveCategory()              │
   [+ statSync host I/O — stays in adapter]        │   → Category                    │
                                                   │   parse_pin_spec()              │
   parsePinSpec()  ─────────────────────────────►  │   → Result<PinTarget, Err>      │
                                                   └──────────────┬───────────────────┘
                                                                  │ every version op
                                                                  ▼
                                                         semver_shim (ONLY caller of `semver::`)
                                                         + NEW: valid(), satisfies()
```

Data flows: a detected-agent record (from cache, deserialized) + catalog entry + canonical map enter the pure deciders; each returns a typed verdict. The cache read and the `statSync` re-validation are the only I/O and are the Phase-56 seam.

### Recommended Project Structure
```
rust/crates/agentlinux-core/src/
├── lib.rs               # add: pub mod category; pub mod pin_spec; pub mod detect_gates;
├── category.rs          # NEW — deriveCategory port + golden #[test] (category.test.ts:27-72) + proptest
├── pin_spec.rs          # NEW — parsePinSpec port + PinTarget enum + PinSpecError + golden (pin.test.ts:117-159)
├── detect_gates.rs      # NEW — isCanonicalAgentPath/tryReuse/tryRemediate/detectPresence pure deciders + DetectedAgent + golden
├── semver_shim.rs       # EXTEND — add pub fn valid() + pub fn satisfies()
├── types.rs             # EXTEND — CatalogEntry gains tags + source_kind; add DetectedAgent, Category, CategoryKey
├── classify.rs          # RE-ASSERT — import 2 missing corpus rows (see §CORE-01/02)
├── divergence.rs        # RE-ASSERT — no change (already covers CORE-02)
└── reuse.rs             # UNCHANGED — the DISTINCT provisioner reuse decision (§Reuse Overlap)
```

### Pattern 1: Pure decider + typed error (the crate's established shape)
**What:** Function over borrowed/owned data returning a value or a `thiserror` enum; no `std::env`/`fs`/`process`.
**When to use:** Every ported decider.
**Example:**
```rust
// Source: rust/crates/agentlinux-core/src/reuse.rs:64-108 (the proven pattern)
pub fn agent_decision(
    id: &str, status: &str, detected_path: Option<&str>,
    canonical: Option<&str>, gsd_system_path: &str,
) -> Decision { /* pure branches, no I/O */ }
// The bin owns I/O — main.rs:49-68 reads env, then calls the pure fn.
```

### Pattern 2: Discriminated union → Rust enum with data
**What:** A TS discriminated union (`PinTarget`) becomes a Rust enum whose variants carry the payload; the parser returns `Result<Enum, Error>`.
**When to use:** `parsePinSpec` → `PinTarget`.
**Example:**
```rust
// Mirror of pin.ts:47-50 discriminated union
pub enum PinTarget {
    Curated,                       // { target: "curated" }
    Latest,                        // { target: "latest" }
    Version(String),               // { target: "version", version }
}
// NB: the TS PinTarget also carries `name` (spec.slice(0, eq)); keep it —
// return e.g. `struct ParsedPin { name: String, target: PinTarget }`.
```

### Pattern 3: Serde-renamed enum for byte-identical serialization
**What:** When a Rust enum must serialize to the exact TS string, use `#[serde(rename_all = "kebab-case")]` / explicit `rename`.
**When to use:** `CategoryKey` (`"coding-agent"`, `"mcp"`, …) if serialized; already done for `Status` in types.rs:46-55.
**Example:**
```rust
// Source: rust/crates/agentlinux-core/src/types.rs:46-55
#[serde(rename_all = "kebab-case")]
pub enum Status { NotInstalled, Synced, /* … */ }
```

### Anti-Patterns to Avoid
- **Calling `semver::` directly in a decider.** Route through `semver_shim` or the divergence isolation breaks (lib.rs contract). Add `valid`/`satisfies` there first.
- **Reading the cache inside the pure core.** `readCachedAgentById`/`detectCachePath` stay in the bin/adapter (Phase 56). If `std::fs` appears in `agentlinux-core`, the cargo-mutants scoping and the pure-crate invariant are both violated.
- **Hardcoding `CANONICAL_PATHS` in a decider.** Pass it in as a parameter (as `reuse::agent_decision` takes `canonical`/`gsd_system_path`). The duplicated map lives in the bin until Phase 57.
- **Porting the `statSync` into the pure `tryReuse`.** That host stat is I/O; the pure decider is the gate set *without* it (TS itself documents this split at detect.ts:262-273).
- **Porting `pinCmd`/`adoptCmd`/`listCmd` or `process.exit` shells.** Those are Phase-56 CLI verbs. Only the pure functions move now.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Version validity (`semver.valid`) | A regex for `X.Y.Z(-pre)?` | `semver_shim::valid` (new; wraps `parse_lenient` → `Option<String>`) | node-semver's `valid` normalizes + accepts prereleases, rejects partials/ranges (pin.ts:66-69). A regex will diverge. |
| Range satisfaction (`semver.satisfies`) | Manual comparator parsing | `semver_shim::satisfies` (new; wraps `normalize_range` + `VersionReq::matches`) | The space→comma compound-range divergence + lenient version parse are already solved in the shim; reuse them. |
| Detect-cache JSON shape | A new struct | Mirror `DetectCacheAgent` (detect.ts:106-111) as `DetectedAgent` | Same 4 fields (`id`, `status`, `path`, `version`); the Phase-56 adapter deserializes it directly. |
| Golden test data | Invented cases | Port the TS test tables verbatim | The TS tests ARE the oracle; inventing cases risks a parity gap the corpus wouldn't catch. |

**Key insight:** This phase's entire value is that these decisions become mutation-tested and property-tested. Hand-rolling semver breaks the isolation that makes that possible.

## Runtime State Inventory

> Not a rename/refactor/migration phase — this is an additive Rust port that changes no observable behavior and touches no stored/registered runtime state. The TS remains the live implementation until Phase 56. Categories confirmed as follows:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — the port adds Rust code; no data store keys/collections change. | none |
| Live service config | None — no service configuration references this logic. | none |
| OS-registered state | None — no scheduler/systemd/pm2 registration touched. | none |
| Secrets/env vars | The `AGENTLINUX_DETECT_CACHE` / `AGENTLINUX_AGENT_HOME` env seams stay in TS + move to the Phase-56 bin adapter, NOT the pure core. No secret renamed. | none this phase |
| Build artifacts | New crate modules compile into `agentlinux-core`; no stale artifact from a rename (nothing renamed). | `cargo build` picks them up |

**Nothing found in any category** — verified by reading `detect.ts`, `pin.ts`, `category.ts` (pure logic, no persistence) and confirming the phase is additive per CONTEXT.md §Deferred.

## Common Pitfalls

### Pitfall 1: `parsePinSpec`'s `eq <= 0` guard collapses two error branches
**What goes wrong:** Porting `spec.indexOf("=")` naively and only checking `=== -1` misses the empty-name case (`"=curated"`, `eq === 0`).
**Why it happens:** TS uses `eq <= 0` (pin.ts:56) to catch BOTH "no `=`" AND "empty name". The corpus asserts `"=curated"` throws the `<name>=<target>` usage message (pin.test.ts:151-153).
**How to avoid:** In Rust, `spec.find('=')` → guard `matches!(idx, None | Some(0))` → usage error. Then split at the index.
**Warning signs:** The `"=curated"` golden row expects the *usage* message, not the *invalid-target* message.

### Pitfall 2: The two distinct `parsePinSpec` error messages
**What goes wrong:** Using one error string for all failures.
**Why it happens:** TS throws TWO different messages: the `<name>=<target>` usage help (bad/absent `=`, pin.ts:57-59) vs the `invalid target '<tgt>'` help (unparseable RHS, pin.ts:71-73). The corpus greps for each independently (pin.test.ts:143-158): `"foo=bogus"` → `/invalid target/`; `"foo="` (empty RHS) → `/invalid target/`; `"no-equals"`/`"=curated"` → `/<name>=<target>/`.
**How to avoid:** Two `PinSpecError` variants (`Usage { spec }`, `InvalidTarget { spec, target }`) with `#[error(...)]` strings that contain the exact substrings the corpus matches (`<name>=<target>`, `invalid target`, `curated`, `latest`, `semver`).
**Warning signs:** `"foo="` (trailing `=`, empty target) must be `InvalidTarget` (empty string is not `curated`/`latest`/valid-semver), NOT `Usage` — subtle, asserted at pin.test.ts:155-158.

### Pitfall 3: `deriveCategory` precedence is first-match-wins, ORDER-SENSITIVE
**What goes wrong:** Using a `HashMap<tag, key>` loses the ordering; `workflow`/`token` MUST beat `devops`, and `coding-agent` MUST beat bare `agent`.
**Why it happens:** `TAG_PRECEDENCE` (category.ts:44-54) is an ordered array; the loop returns the FIRST tag present in `entry.tags`. rtk tagged `["token","workflow","devops"]` must resolve `workflow` (category.test.ts:46-52).
**How to avoid:** Port as an ordered `&[(&str, CategoryKey)]` slice iterated in order — NOT a map. Then the `source_kind == "mcp"` fallback, then `other`.
**Warning signs:** Any test where an entry carries multiple precedence tags (rtk, ccusage, the `["agent","coding-agent"]` codex row at category.test.ts:29).

### Pitfall 4: `detectPresence`'s `adoptable` truthiness gate on `compatibility_window`
**What goes wrong:** Treating `!!entry.compatibility_window` as merely "is Some".
**Why it happens:** TS uses `!!entry.compatibility_window` (detect.ts:271) which is falsy for BOTH `undefined` AND `""` (empty string). The comment (detect.ts:268-271) says this stays byte-for-byte with `tryReuse`'s `if (!entry.compatibility_window) return null` even if the schema's `minLength:1` is relaxed.
**How to avoid:** In Rust model `compatibility_window: Option<String>` and gate on `.as_deref().is_some_and(|w| !w.is_empty())` — treat empty string as absent, matching JS falsiness.
**Warning signs:** An entry with `compatibility_window: ""` must be NOT adoptable.

### Pitfall 5: `tryReuse` (not-canonical-gated) vs `tryRemediate` (canonical-gated) read DIFFERENT sources
**What goes wrong:** Assuming both gates use the same lookup.
**Why it happens:** `tryReuse` uses `readCachedAgentById` (no canonical-path requirement — any catalog tool at its managed path, detect.ts:171) so it can adopt a brownfield `rtk`/`gh`; `tryRemediate` uses `readDetectedAgent` (canonical-gated — only ids WITH a `CANONICAL_PATHS` entry, detect.ts:203). In the pure port, this is the difference between which predicate the decider applies (`isAtManagedPath` vs `isCanonicalAgentPath`), and whether an unknown-id entry is a candidate at all.
**How to avoid:** Port `isAtManagedPath` (detect.ts:78-81 — `CANONICAL_PATHS[id] ? isCanonicalAgentPath : isManagedPath`) and `managedBinDir`/`isManagedPath` (detect.ts:51-68) as pure helpers taking `agent_home` as a parameter (TS reads `AGENTLINUX_AGENT_HOME` — that env read stays in the adapter; the pure fn takes the resolved home string).
**Warning signs:** rtk at `~/.local/bin` is adoptable (tryReuse), but a claude-code at `/home/agent/.npm-global/bin/claude` is a remediate path-mismatch (tryRemediate). Different predicates.

### Pitfall 6: `semver.valid`/`satisfies` normalize the version before comparing
**What goes wrong:** Returning the raw version instead of the normalized one.
**Why it happens:** TS `semver.valid(detected.version)` returns the CLEAN version (drops leading `v`/whitespace, detect.ts:177,261,220). The sentinel/downstream use the clean value.
**How to avoid:** `semver_shim::valid(raw) -> Option<String>` must return `parse_lenient(raw).ok().map(|v| v.to_string())` (the normalized form), NOT the raw input.
**Warning signs:** A cache version like `"v1.37.1"` must surface as `"1.37.1"`.

## Code Examples

### `semver_shim::valid` (new — mirrors node `semver.valid`)
```rust
// Add to rust/crates/agentlinux-core/src/semver_shim.rs
// node semver.valid(x): returns the normalized version string, or null.
// pin.ts:66-69 relies on: accepts prereleases (2.1.7-beta.1), rejects
// partials (2.1) and ranges (^2.1). parse_lenient COERCES partials, so for
// `valid` we must NOT coerce — use a strict parse to reject "2.1".
#[must_use]
pub fn valid(raw: &str) -> Option<String> {
    // node semver.valid is STRICT on partials: "2.1" → null. But it DOES
    // accept a leading `v` and surrounding space. So: trim + strip v, then
    // strict Version::parse (NOT coerce_partial).
    let trimmed = raw.trim();
    let stripped = trimmed.strip_prefix('v').or_else(|| trimmed.strip_prefix('V')).unwrap_or(trimmed);
    Version::parse(stripped).ok().map(|v| v.to_string())
}
```
> **VERIFY against the TS/node-semver corpus.** `pin.test.ts` asserts `"foo=2.1.7"` → version, `"foo=2.1.7-beta.1"` → version, `"foo="`/`"foo=bogus"` → invalid. It does NOT test `"foo=2.1"` explicitly, but pin.ts:66-67 comment says partials are rejected. Confirm node `semver.valid("2.1") === null` and node `semver.valid("v1.2.3")` behavior when porting — this is the one place the shim's lenient-vs-strict boundary matters for parity. `[ASSUMED — node semver.valid partial/v-prefix semantics; verify against node-semver docs + a cross-check test]`

### `semver_shim::satisfies` (new — mirrors node `semver.satisfies`)
```rust
// node semver.satisfies(version, range): does `version` satisfy `range`?
// detect.ts:179,273: semver.satisfies(version, entry.compatibility_window)
#[must_use]
pub fn satisfies(version: &str, node_range: &str) -> bool {
    let Ok(req) = VersionReq::parse(&normalize_range(node_range)) else { return false; };
    match parse_lenient(version) {
        Ok(v) => req.matches(&v),
        Err(_) => false,
    }
}
// Reuse the existing max_satisfying test data (semver_shim.rs) to golden this.
```

### `deriveCategory` port (ordered slice, first-match-wins)
```rust
// Source: plugin/cli/src/catalog/category.ts:44-65
const TAG_PRECEDENCE: &[(&str, CategoryKey)] = &[
    ("coding-agent", CategoryKey::CodingAgent),
    ("assistant",    CategoryKey::Assistant),
    ("mcp",          CategoryKey::Mcp),
    ("workflow",     CategoryKey::Workflow),
    ("token",        CategoryKey::Workflow),
    ("devops",       CategoryKey::Devops),
    ("browser",      CategoryKey::Browser),
    ("automation",   CategoryKey::Browser),
    ("agent",        CategoryKey::CodingAgent),
];
pub fn derive_category(entry: &CatalogEntry) -> Category {
    for (tag, key) in TAG_PRECEDENCE {
        if entry.tags.iter().any(|t| t == tag) { return category_for(*key); }
    }
    if entry.source_kind.as_deref() == Some("mcp") { return category_for(CategoryKey::Mcp); }
    category_for(CategoryKey::Other)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Decision logic embedded in bash + TS, untestable by mutation | Pure Rust core, cargo-mutants + proptest | Phase 53/54 (v0.4.0) | This phase extends that core to category/pin/detect-gate decisions. |
| `semver_shim` exports `eq`/`gt`/`max_satisfying` only | Add `valid`/`satisfies` | This phase | Unblocks the pin + detect-gate ports without breaking node-semver isolation. |

**Deprecated/outdated:** Nothing removed this phase — the TS stays live until Phase 56 wires the Rust bin.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | node `semver.valid("2.1") === null` (rejects two-part partials) and `semver.valid("v1.2.3")` normalizes — so `semver_shim::valid` must be STRICT (not `parse_lenient`'s coercion). | Code Examples / Pitfall 6 | If node coerces here, `valid` would wrongly reject a pin the TS accepts (or vice versa). **Mitigation:** add a cross-check golden row per node-semver behavior; the corpus (pin.test.ts) only exercises full + prerelease + bogus, so add explicit `"2.1"` and `"v1.2.3"` rows when porting. |
| A2 | The detect-gate deciders have NO existing bats coverage — parity is pinned only by the TS unit tests (`adopt.test.ts`, `list-presence.test.ts`, `list-drift.test.ts`, `pin.test.ts`). | Validation Architecture | If bats DOES exercise these gates, GATE-01 gives extra parity coverage; if not, the Rust `#[test]` golden IS the oracle. Verified no `list/drift/adopt/presence` bats files exist (`ls tests/bats/` → none). Low risk. |
| A3 | `CatalogEntry` in `types.rs` must gain `tags: Vec<String>` and `source_kind: Option<String>` for the category + detect-gate ports (currently absent — types.rs:15-31 has only id/pinned_version/version_constraint/npm_package_name/compatibility_window). | Standard Stack / Structure | Straightforward serde extension; the risk is only forgetting `#[serde(default)]` on `tags` so partial JSON still deserializes (types.rs convention). |

## Open Questions

1. **How much CORE-01/02 "re-assert" is actually required?** (flagged per the additional-context ask)
   - What we know: `classify.rs` already ports all SEVEN six-state rows from `classify.test.ts:36-93` (its test module at classify.rs:84-142 covers not-installed×2, synced, drift, override-ahead, override-behind, pinned-override). `divergence.rs` has 14 `#[test]`s covering `compute_divergence` (six states + latest threading) and `resolve_latest_for` (highest-match, constraint, no-match throw, empty throw). The TS `divergence.test.ts` has the same `resolveLatestFor` branches (lines 132-156) + `computeDivergence` six states (line 42). `[VERIFIED: classify.rs:58-143, divergence.rs test count, divergence.test.ts grep]`
   - What's unclear: `classify.test.ts` also tests `decideVersion` (5 rows, lines 96-121) which classify.rs explicitly did NOT port (classify.rs:61-62 "decideVersion is Phase 55/56 scope"). Is `decideVersion` part of CORE-01, or a Phase-56 CLI concern?
   - Recommendation: **CORE-01/02 need essentially ZERO new port** — both are covered. The only gap is `decideVersion`. Given it's a pure function (`decideVersion(entry, override?, sentinel?) → {version, source, sticky}`, classify.test.ts:96-121) with an existing golden table, **fold `decideVersion` into this phase's CORE-03/CORE-01 scope** (it's pure, testable, and its corpus exists) rather than pushing it to Phase 56 where it'd be entangled with I/O. Flag for the planner: this is a ~15-LOC pure add that closes the classify.test.ts corpus completely. Treat CORE-01/02 otherwise as a documentation re-assertion (point the success criteria at the existing test modules).

2. **Does the pure `tryReuse` return the `ReuseHit` shape, or a boolean "eligible" verdict?**
   - What we know: TS `tryReuse` returns `ReuseHit | null` (binary_path, version, detected_source) AFTER the host `statSync` (detect.ts:189-193). The pure part is everything BEFORE the stat.
   - Recommendation: Port a pure `reuse_gate_decision(entry, detected: &DetectedAgent, canonical_map, agent_home) -> Option<ReuseCandidate>` returning the normalized version + path (no stat); the adapter does the `statSync` and constructs the final `ReuseHit`. This mirrors `detectPresence` exactly (which is `tryReuse`-minus-stat, per detect.ts:262). Consider making `detectPresence` the canonical pure decider and expressing `tryReuse`'s pure part in terms of it.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rust toolchain | Building the crate | ✓ | 1.97.1 (workspace rust-version) | — |
| `cargo-mutants` | CI mutation gate (not local dev) | CI-provisioned | =27.1.0 | Nightly full-crate advisory job |
| node + pnpm | Running the TS golden oracle (`pnpm test`) to confirm corpus values | ✓ (assumed; TS tests already exist and pass) | — | Read the assertion literals directly from the `.test.ts` files (done in this research) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none blocking — the golden corpus values are read directly from the committed TS test files, so re-running `pnpm test` is confirmatory, not required.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Rust built-in `#[test]` + `proptest` 1.11 (unit/property); node:test for the TS oracle |
| Config file | `rust/crates/agentlinux-core/Cargo.toml` (dev-deps); no separate config |
| Quick run command | `cd rust && cargo test --package agentlinux-core` |
| Full suite command | `cd rust && cargo test --workspace` then `./tests/docker/run.sh ubuntu-24.04` (bats, unchanged) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CORE-03 | `deriveCategory` parity (7 precedence rows) | unit (golden) | `cargo test -p agentlinux-core category` | ❌ Wave 0 — port from category.test.ts:27-72 |
| CORE-03 | `parsePinSpec` parity (all shapes + 2 error msgs) | unit (golden) | `cargo test -p agentlinux-core pin_spec` | ❌ Wave 0 — port from pin.test.ts:117-159 |
| CORE-03 | detect-gate deciders (reuse/remediate/presence) parity | unit (golden) | `cargo test -p agentlinux-core detect_gates` | ❌ Wave 0 — port from adopt/list-presence/list-drift test tables |
| CORE-03 | `semver_shim::valid` + `satisfies` behavior | unit | `cargo test -p agentlinux-core semver_shim` | ❌ Wave 0 — add golden + cross-check A1 |
| CORE-01 | `classify` six-state (re-assert) | unit (golden) | `cargo test -p agentlinux-core classify` | ✅ classify.rs:84-142 (add 2 missing rows if `decideVersion` folded in) |
| CORE-02 | `computeDivergence`/`resolveLatestFor` (re-assert) | unit (golden) | `cargo test -p agentlinux-core divergence` | ✅ divergence.rs (14 tests) |
| CORE-03 | totality/determinism invariants | property | `cargo test -p agentlinux-core proptests` | ❌ Wave 0 — one proptest per new module |
| GATE-01 | Full bats green (no regression) | bats | `./tests/docker/run.sh ubuntu-24.04` | ✅ unchanged (additive port, no observable behavior change) |

### Sampling Rate
- **Per task commit:** `cd rust && cargo test --package agentlinux-core` (fast; the whole pure crate)
- **Per wave merge:** `cd rust && cargo test --workspace && cargo clippy --workspace -- -D warnings`
- **Phase gate:** full bats suite green (`GATE-01`) + `cargo-mutants --package agentlinux-core --in-diff` catches surviving mutants on the new modules.

### Wave 0 Gaps
- [ ] `category.rs` golden `#[test]` module — port category.test.ts:27-72 (7 assertions) → covers CORE-03
- [ ] `pin_spec.rs` golden `#[test]` module — port pin.test.ts:117-159 (8 parse cases incl. both error messages) → covers CORE-03
- [ ] `detect_gates.rs` golden `#[test]` module — port the decision cases from adopt.test.ts / list-presence.test.ts / list-drift.test.ts (the pre-statSync, deterministic branches) → covers CORE-03
- [ ] `semver_shim.rs` — `valid` + `satisfies` fns + golden rows (incl. A1 cross-check: `"2.1"`, `"v1.2.3"`) → covers CORE-03
- [ ] one `proptests` submodule per new module (totality: `parse_pin_spec` never panics; `derive_category` total & deterministic; `satisfies` total)
- [ ] (if planner folds it in) `decideVersion` port + golden (classify.test.ts:96-121) → closes CORE-01 corpus

### Proptest Invariants Worth Asserting
- **`parse_pin_spec` totality:** for any `&str`, returns `Ok(_)` or a `PinSpecError` — never panics (mirrors reuse.rs:266-289 totality proptest). `[VERIFIED: pattern in reuse.rs]`
- **`derive_category` totality + determinism:** any `CatalogEntry` yields exactly one `Category` (never dropped — the `other` fallback guarantees this, category.ts:64) and two calls agree.
- **`satisfies` totality:** any `(version, range)` returns a bool, never panics (malformed range/version → `false`).
- **`derive_category` precedence monotonicity (optional):** if a higher-precedence tag is present, the result is that category regardless of lower tags — the property form of Pitfall 3.

## Reuse Overlap Clarity (per additional-context Q5)

`reuse::agent_decision` (Phase 53, `reuse.rs`) and `tryReuse` (this phase, `detect.ts:165`) are **DISTINCT** and must both exist:

| | `reuse::agent_decision` (reuse.rs) | `tryReuse` / detect gates (detect.ts) |
|---|---|---|
| Origin | bash `plugin/lib/reuse/agents.sh::reuse::agent_decision` (the PROVISIONER) | TS `detect.ts` (the CLI-side reuse/adopt gate) |
| Output | `Decision::{Reuse,Remediate,Create}` (a 3-way dispatch token) | `ReuseHit`/`RemediateHit`/`PresenceHit` (rich structs) or `null` |
| Semver | **Does NOT evaluate semver** (bash stops at predicate 2; version-in-window layered on by the CLI, reuse.rs:5-8) | **Evaluates `compatibility_window`** via `semver.satisfies` (detect.ts:179) — the layered-on predicate 3 |
| Path predicate | exact `canonical` path match (+ gsd system path) | `isAtManagedPath` — canonical for the original 3, else source_kind managed dir (generalizes to rtk/gh) |
| Consumer | `remediate.sh` provisioner dispatch | `adopt`/`list`/`pin`/`install` CLI verbs |

**Conclusion:** Phase 55 ports `tryReuse`/`tryRemediate`/`detectPresence` **separately** into `detect_gates.rs`. Do NOT re-port or conflate with `reuse.rs`. The two share the same *conceptual* canonical-path map but apply different predicates and (crucially) `tryReuse` evaluates the semver window that `reuse::agent_decision` deliberately omits. The `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` duplication across detect.ts:16,28 + main.rs:19,26-33 + bash **stays** until Phase 57 (PROV-02). `[VERIFIED: reuse.rs:1-8, detect.ts:165-224]`

## Sources

### Primary (HIGH confidence) — this repo
- `plugin/cli/src/catalog/category.ts` (65 LOC) + `test/category.test.ts` (160) — category derivation + golden corpus
- `plugin/cli/src/commands/pin.ts:47-74` — `PinTarget` union + `parsePinSpec` + error/exit contract; `test/pin.test.ts:117-159` — the parse-spec golden cases (the pinCmd/sentinel cases at 161-553 are Phase 56)
- `plugin/cli/src/detect.ts:32-275` — `isCanonicalAgentPath`, `tryReuse`, `tryRemediate`, `detectPresence` (pure) + `readCachedAgentById`/`readDetectedAgent`/`detectCachePath`/`readCacheAgents` (I/O, out of scope); tests: `test/adopt.test.ts`, `list-presence.test.ts`, `list-drift.test.ts`
- `rust/crates/agentlinux-core/src/{lib,reuse,classify,divergence,types,semver_shim,proptest_strategies}.rs` — established port conventions + existing CORE-01/02 coverage
- `rust/crates/agentlinux/src/main.rs:14-84` — the proven pure/adapter split (env-read in bin, decision in core)
- `.github/workflows/test.yml:191-237` + `nightly-mutation.yml:45-80` — cargo-mutants `--package agentlinux-core` gate (new modules auto-covered)
- `.planning/REQUIREMENTS.md` (CORE-01/02/03, GATE-01/05), `.planning/phases/55-.../55-CONTEXT.md`

### Secondary (MEDIUM confidence)
- `AGENTS.md` / `CLAUDE.md` — behavior-tests-are-spec, pure-core discipline, master-shippable, review loop

### Tertiary (LOW confidence)
- node-semver `valid`/`satisfies` partial/`v`-prefix semantics (A1) — inferred from pin.ts comments; **cross-check when porting.**

## Project Constraints (from CLAUDE.md / AGENTS.md)

- **Behavior tests in `tests/bats/` are the spec.** Implementation may change freely while the suite stays green. This phase's Rust `#[test]` goldens are the parity oracle for the pure logic; bats is unaffected (no observable behavior change).
- **Keep `agentlinux-core` PURE** — no `std::process`/`std::fs`/`std::env` (lib.rs contract) so cargo-mutants + proptest scope holds.
- **Every version op routes through `semver_shim`** — never call `semver::` directly (isolates node-semver divergences, TEST-04).
- **`master` stays shippable** (GATE-05); additive-only this phase; parallel track on `worktree-stack-revisiting`.
- **Run the `$review` loop** on changed files (Rust reviewer role) before declaring complete.
- **No new external packages** without the legitimacy gate — none added here.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new deps; everything pinned in existing Cargo.toml.
- Architecture (pure/I-O seam, module layout): HIGH — mirrors the three existing ports (reuse/classify/divergence) exactly; TS itself documents the seam (detect.ts:262-273).
- Pitfalls: HIGH — read directly from TS source line-by-line and the golden test assertions.
- semver `valid`/`satisfies` node-parity (A1): MEDIUM — behavior inferred from TS comments; needs a cross-check golden row when porting.
- CORE-01/02 re-assert scope: HIGH — confirmed existing Rust test coverage; the one open item (`decideVersion`) is flagged with a recommendation.

**Research date:** 2026-07-28
**Valid until:** 2026-08-27 (stable — repo-internal port; only drift risk is TS source changing under it, which the branch isolates)
