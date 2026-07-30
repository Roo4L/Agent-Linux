---
phase: 55-pure-logic-core-parity
plan: 02
subsystem: infra
tags: [rust, semver, catalog, detect-gates, pin-spec, category, parity, proptest, port]

# Dependency graph
requires:
  - phase: 55-01
    provides: "semver_shim::valid/satisfies + types.rs (DetectedAgent, CatalogEntry.tags/source_kind, CategoryKey/Category)"
provides:
  - "category::derive_category — pure deriveCategory port (ordered TAG_PRECEDENCE, source_kind=mcp fallback, Other floor)"
  - "pin_spec::parse_pin_spec — pure parsePinSpec port with PinTarget enum + two-variant PinSpecError (Usage/InvalidTarget)"
  - "detect_gates — pure reuse/remediate/presence deciders + is_canonical_agent_path/is_at_managed_path helpers (no statSync, no cache read)"
affects: [56-adapter-cli-wiring, 57-canonical-map-consolidation]

# Tech tracking
tech-stack:
  added: []  # no new deps — all crates pinned by 53/54
  patterns:
    - "Pure decider + typed thiserror error (mirrors reuse.rs/divergence.rs)"
    - "Discriminated union -> Rust enum with data (PinTarget, RemediateReason)"
    - "Canonical map passed in as params (never hardcoded in a decider) — Phase-57 consolidation"
    - "Verbatim TS .test.ts table as the Rust #[test] golden module (the parity oracle) + one totality proptest per module"

key-files:
  created:
    - rust/crates/agentlinux-core/src/category.rs
    - rust/crates/agentlinux-core/src/pin_spec.rs
    - rust/crates/agentlinux-core/src/detect_gates.rs
  modified:
    - rust/crates/agentlinux-core/src/lib.rs

key-decisions:
  - "TAG_PRECEDENCE is an ORDERED slice, never a HashMap/BTreeMap — first-match-wins ordering is load-bearing (Pitfall 3)."
  - "PinTarget::Version keeps the RAW target string (matching TS `version: tgt`), semver_shim::valid used only as accept/reject predicate."
  - "The reuse gate returns a slim ReuseCandidate{path,clean-version} with NO statSync — the statSync->ReuseHit build is the Phase-56 adapter (Open Q2)."
  - "detect_gates stays DISTINCT from reuse.rs: these gates evaluate compatibility_window via satisfies; reuse::agent_decision deliberately does not."

patterns-established:
  - "Pattern: every version op routes through semver_shim (valid/satisfies) — no direct semver:: in a decider."
  - "Pattern: !!compatibility_window JS-falsiness modeled as .as_deref().filter(|w| !w.is_empty()) so empty string is absent (Pitfall 4)."

requirements-completed: [CORE-03, GATE-01, GATE-05]

coverage:
  - id: D1
    description: "derive_category matches TS deriveCategory byte-for-byte across the category.test.ts corpus (ordered precedence, mcp fallback, Other floor)"
    requirement: "CORE-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/category.rs#tests (8 golden rows from category.test.ts:27-72) + proptests (totality/determinism + first-match-wins)"
        status: pass
      - kind: unit
        ref: "cargo test -p agentlinux-core category — 12 passed"
        status: pass
    human_judgment: false
  - id: D2
    description: "parse_pin_spec matches TS parsePinSpec with the two distinct error messages (Usage vs InvalidTarget) and the eq<=0 / empty-target edge cases"
    requirement: "CORE-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/pin_spec.rs#tests (8 golden rows from pin.test.ts:117-159 incl. both error-substring asserts) + totality proptest"
        status: pass
      - kind: unit
        ref: "cargo test -p agentlinux-core pin_spec — 10 passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "pure detect-gate deciders (reuse/remediate/presence + isCanonicalAgentPath) match TS across the adopt/list-presence corpus, WITHOUT statSync/cache read"
    requirement: "CORE-03"
    verification:
      - kind: unit
        ref: "rust/crates/agentlinux-core/src/detect_gates.rs#tests (18 golden rows from adopt.test.ts + list-presence.test.ts) + totality proptest"
        status: pass
      - kind: unit
        ref: "cargo test -p agentlinux-core detect_gates — 19 passed"
        status: pass
    human_judgment: false
  - id: D4
    description: "GATE-01/GATE-05 held: workspace green (116), clippy -D warnings clean, fmt clean, master shippable; additive-only (no TS deleted)"
    requirement: "GATE-01"
    verification:
      - kind: unit
        ref: "cargo test --workspace — 116 passed; cargo clippy --workspace --all-targets -- -D warnings — clean; cargo fmt --all --check — clean"
        status: pass
    human_judgment: false

# Metrics
duration: 6 min
completed: 2026-07-28
status: complete
---

# Phase 55 Plan 02: Pure-Logic Core Parity (CORE-03 substance) Summary

**Ported `deriveCategory`, `parsePinSpec`, and the pure `tryReuse`/`tryRemediate`/`detectPresence`/`isCanonicalAgentPath` deciders from TS into `agentlinux-core` with byte-for-byte golden-corpus parity — ordered tag precedence, two distinct pin-spec error messages, and the pre-statSync detect-gate cores, all routing semver through `semver_shim` and keeping the crate PURE.**

## Performance

- **Duration:** 6 min (execution wall time across the 4 commits)
- **Started:** 2026-07-28T09:03:05Z (first task commit)
- **Completed:** 2026-07-28T09:08:36Z
- **Tasks:** 3 (all TDD `type="auto"`)
- **Files modified:** 4 (3 created + `lib.rs` mod-registration)

## Accomplishments
- `category.rs` — `derive_category(&CatalogEntry) -> Category` with an ORDERED `TAG_PRECEDENCE` slice (never a map, Pitfall 3), `source_kind == "mcp"` fallback, and the `Other` floor. `category_for` carries the exact TS labels + display orders. 8 golden `#[test]` rows verbatim from `category.test.ts:27-72` + totality/determinism + precedence-monotonicity proptests.
- `pin_spec.rs` — `parse_pin_spec(&str) -> Result<ParsedPin, PinSpecError>` with a `PinTarget` enum (`Curated`/`Latest`/`Version(raw)`) and a two-variant `PinSpecError` (`Usage`/`InvalidTarget`) whose `#[error]` strings are byte-identical to `pin.ts`. `eq<=0` collapse via `matches!(idx, None | Some(0))` (Pitfall 1); empty target → `InvalidTarget` (Pitfall 2). 8 golden rows from `pin.test.ts:117-159` (incl. both error-substring asserts) + totality proptest.
- `detect_gates.rs` — the pure decision cores: `is_canonical_agent_path`, `managed_bin_dir`/`is_managed_path`/`is_at_managed_path`, and `reuse_gate -> Option<ReuseCandidate>` (slim path+clean-version, NO statSync, Open Q2), `remediate_gate -> Option<RemediateHit>` (canonical-gated, broken vs path-mismatch, Pitfall 5), `presence_gate -> Option<PresenceHit>` (mcp→None, `!!compatibility_window` falsiness, Pitfall 4). 18 golden rows from `adopt.test.ts` + `list-presence.test.ts` + a totality proptest over all deciders.
- All six research pitfalls honored and named in code + tests; the crate stays PURE (grep-clean of `semver::`/`std::fs`/`std::env`/`std::process` in all three new modules); the cache read + statSync remain the Phase-56 seam.

## Task Commits

Each task was committed atomically (TDD module = test+impl in one green commit):

1. **Task 1: Port `derive_category` with the verbatim `category.test.ts` golden corpus** — `703738f` (feat)
2. **Task 2: Port `parse_pin_spec` + `PinTarget` with the `pin.test.ts` golden corpus + 2 error messages** — `926791f` (feat)
3. **Task 3: Port the pure detect-gate deciders (reuse/remediate/presence + `isCanonicalAgentPath`)** — `89f4e47` (feat)
4. **Review fix: simplify `presence_gate` adoptable to a single window/version match** — `504ff59` (refactor, `$review` simplicity finding)

## Files Created/Modified
- `rust/crates/agentlinux-core/src/category.rs` (314 lines) — `derive_category` + `category_for` + `TAG_PRECEDENCE` + golden/proptest modules.
- `rust/crates/agentlinux-core/src/pin_spec.rs` (271 lines) — `parse_pin_spec` + `ParsedPin`/`PinTarget`/`PinSpecError` + golden/proptest modules.
- `rust/crates/agentlinux-core/src/detect_gates.rs` (707 lines) — path predicates + reuse/remediate/presence gates + `ReuseCandidate`/`RemediateHit`/`PresenceHit`/`RemediateReason` + golden/proptest modules.
- `rust/crates/agentlinux-core/src/lib.rs` — registered `pub mod category;`, `pub mod pin_spec;`, `pub mod detect_gates;`.

## TS Corpus → Rust Golden Evidence (per-module)

| Module | TS oracle | Rust golden rows | Result |
|---|---|---|---|
| `category` | `category.test.ts:27-72` (7 `describe` blocks / 8 assertion groups: coding-agent>agent, assistant+label, mcp via tag/source_kind, workflow/token>devops×2, devops×2, browser/automation, Other×2) | 8 `#[test]` (all rows) + `category_for` label/order table + 2 proptests | 12 passed |
| `pin_spec` | `pin.test.ts:117-159` (curated, latest, exact semver, prerelease, `foo=bogus`→invalid, `no-equals`→usage, `=curated`→usage, `foo=`→invalid) | 8 `#[test]` (all rows, both error substrings) + 2 totality proptests | 10 passed |
| `detect_gates` | `adopt.test.ts:194-336` + `list-presence.test.ts:92-183` (gsd@system in/out of window, rtk managed/non-managed, empty-window, broken; claude npm path-mismatch, broken hit, healthy-canonical none, no-canonical none, gsd-canonical none; presence healthy-canonical adoptable, broken none, non-canonical present, empty-window not-adoptable, mcp none) | 18 `#[test]` (all deterministic pre-statSync rows) + 1 totality proptest | 19 passed |

## Decisions Made
- Reused the `semver_shim::valid`/`satisfies` already added in Plan 01 — no shim changes needed this plan (they were pre-existing per the wave-1 unblocker), so all semver routes cleanly through the shim.
- Kept `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` duplicated and passed as params (mirrors `reuse::agent_decision`) — consolidation deferred to Phase 57 as specified.
- `presence_gate` adoptable expressed as a single `(version, window)` match after the `$review` simplicity pass (behavior identical to the TS `version != null && satisfies(...)`).

## Deviations from Plan

None - plan executed exactly as written. (One additive `$review` refactor commit `504ff59` — a simplicity-lens cleanup of `presence_gate`, behavior-preserving, not a plan deviation.)

## Issues Encountered
None. All three golden corpora passed on first green; rustfmt reshaped a few long assertion lines (auto-applied), clippy was clean throughout.

## Review

Ran the project `$review` loop on the three new Rust modules + `lib.rs`. The dispatch table has no Rust surface reviewer (predates the Rust rewrite), so the language-neutral trait lenses applied: `reliability`, `security`, `simplicity`, `readability`, `testability`, `ai-deslop`. Host native subagent dispatch was unavailable in this executor context, so the role rubrics were applied directly (a **limited pass** per the skill's fallback clause). Findings: one simplicity finding (redundant `is_some()` in `presence_gate` adoptable) — **fixed** in `504ff59`. Security/reliability: clean — pure functions, total semver via the shim (T-55-03/04/05 mitigations in place, proven by totality proptests), the one `.expect()` in `pin_spec` is provably unreachable behind the `matches!(None | Some(0))` guard. No deferred items.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CORE-03 substance complete: `derive_category`, `parse_pin_spec`, and the three detect-gate deciders are ported, golden-corpus-verified, and property-tested (mutation-testable under the existing `--package agentlinux-core` gate).
- Phase 56 can now wire the cache-read adapter (`readCachedAgentById`/`readDetectedAgent`/`detectCachePath`) + the `statSync` re-validation around these pure deciders, and the CLI verbs (`pinCmd`/`adoptCmd`/`listCmd`) consume `parse_pin_spec` + the gates.
- GATE-05 held: additive-only on `worktree-stack-revisiting`; no TS deleted; master stays shippable. GATE-01 unaffected (no observable behavior change; bats untouched).

## Self-Check: PASSED
- Files exist on disk: `category.rs`, `pin_spec.rs`, `detect_gates.rs`, `lib.rs` — all FOUND.
- Commits present: `703738f`, `926791f`, `89f4e47`, `504ff59` — all FOUND in `git log`.
- `cargo test --workspace` — 116 passed; `cargo clippy --workspace --all-targets -- -D warnings` — clean; `cargo fmt --all --check` — clean.
- Grep-clean: no `semver::` / `std::fs` / `std::env` / `std::process` in the three new modules (code lines).

---
*Phase: 55-pure-logic-core-parity*
*Completed: 2026-07-28*
