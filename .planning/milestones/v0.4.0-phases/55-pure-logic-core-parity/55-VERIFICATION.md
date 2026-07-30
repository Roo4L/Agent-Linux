---
phase: 55-pure-logic-core-parity
verified: 2026-07-28T10:20:00Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
requirements_verified: [CORE-01, CORE-02, CORE-03, GATE-01, GATE-05]
---

# Phase 55: Pure-Logic Core Parity Verification Report

**Phase Goal:** Port the remaining I/O-free decision core (category derivation, pin-spec parsing, detect-gate pure deciders) to Rust with byte-for-byte-equivalent verdicts to TS across a golden corpus; re-assert classify + divergence (already ported); fold in decideVersion. Keep agentlinux-core pure.
**Verified:** 2026-07-28T10:20:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `derive_category` matches TS `deriveCategory` byte-for-byte (ordered precedence, mcp fallback, Other floor) | ✓ VERIFIED | `TAG_PRECEDENCE` is an ORDERED `&[(&str, CategoryKey)]` slice (category.rs:30-40), byte-identical order to category.ts:44-54 (workflow/token precede devops; coding-agent before bare agent). 8 golden `#[test]` rows byte-for-byte from category.test.ts:27-72 (rtk `["token","workflow","devops"]`→Workflow; `["agent","coding-agent"]`→CodingAgent). `cargo test category` → 12 passed. `grep HashMap\|BTreeMap` → none. |
| 2 | `parse_pin_spec` matches TS `parsePinSpec` incl. the two distinct error messages | ✓ VERIFIED | Both `#[error]` strings byte-identical to pin.ts:57-59 (Usage) and pin.ts:71-73 (InvalidTarget) — pin_spec.rs:62-72. `eq<=0` collapse via `matches!(idx, None | Some(0))`. Version case keeps RAW `tgt` (`PinTarget::Version(tgt.to_string())`), matching TS `version: tgt`. Partial rejection routes through STRICT `semver_shim::valid`. 8 golden rows from pin.test.ts:117-159. `cargo test pin_spec` → 10 passed. |
| 3 | Pure detect-gate deciders match TS across adopt/list-presence corpus WITHOUT statSync/cache-read | ✓ VERIFIED | `ReuseCandidate {path, version}` is slim — no statSync/isFile (TS detect.ts:183-188 deferred to Phase 56, per Open Q2). Empty-window `""` treated as absent via `.as_deref().filter(\|w\| !w.is_empty())` (Pitfall 4). Gate order byte-for-byte with tryReuse. Remediate canonical-gated. Constants (CLAUDE/GSD canonical, GSD_SYSTEM_PATH) byte-identical to detect.ts:16-28. Goldens match adopt.test.ts:194-227 + list-presence.test.ts:92-149. `grep std::fs\|statSync\|std::env` in detect_gates.rs → none. `cargo test detect_gates` → 19 passed. |
| 4 | `classify` returns verdicts identical to TS across the full six-state corpus (CORE-01 re-assert) | ✓ VERIFIED | All 6 states covered: not-installed×2, synced, drift-undeclared, override-ahead, override-behind, pinned-override (classify.rs:136-187). `cargo test classify` → 15 passed. No logic change (re-assert only). |
| 5 | `decide_version` returns `{version, source, sticky}` identical to TS across all 5 classify.test.ts:96-121 rows | ✓ VERIFIED | Branch order byte-for-byte with classify.ts:34-50. Sticky branch INHERITS `sentinel.source.clone()` (classify.rs:91), NOT hardcoded — row 3 test asserts source "pinned" inherited. 5-row golden matches TS. `cargo test decide` → 5 passed. |
| 6 | `compute_divergence` + `resolve_latest_for` re-asserted incl. zero-match + empty-list error paths (CORE-02) | ✓ VERIFIED | `NoSatisfyingVersion` (zero-match, divergence.rs:259-270) and `NoPublishedVersions` (empty-list, 273-278) both tested against TS message substrings. `resolve_latest_for` routes through `semver_shim::max_satisfying`. `cargo test divergence` → 14 passed. No logic change. |
| 7 | Crate stays PURE; semver isolation held (GATE-01/GATE-05 substance) | ✓ VERIFIED | No production `std::process`/`std::fs`/`std::env` in any core module (the 4 hits are all inside `#[cfg(test)]` oracle/schema-drift modules). No production `semver::` outside `semver_shim` — the sole `semver::VersionReq::parse` at divergence.rs:328 is inside `#[cfg(test)] mod proptests` (line 281), the documented independent-oracle. Each new module has a proptest module → cargo-mutants/proptest gate scopes cleanly. |
| 8 | `master` untouched, additive-only under rust/, bats untouched (GATE-01/GATE-05) | ✓ VERIFIED | `git rev-parse master` = f14c092 (untouched). `git diff master...HEAD -- tests/bats` → empty. Phase-55 commits (91446bd^..HEAD) touch ONLY `rust/crates/agentlinux-core/src/*.rs` + `.planning/`. Additive, reversible per-phase. |

**Score:** 8/8 truths verified (0 present, behavior-unverified)

### Golden-Corpus Faithfulness (anti-circularity audit)

The stated risk was a golden that re-derives expected values from the Rust code, or a parity divergence. Findings:

- **Not circular.** Each Rust golden asserts the literal expected verdict documented in the TS `.test.ts` oracle (e.g. rtk→"workflow", gsd 1.36.0 out-of-window→None, claude@npm-global→path-mismatch with detected_version "2.1.98"). Spot-checked category.test.ts:27-72, pin.test.ts:117-159, adopt.test.ts:190-230, list-presence.test.ts:90-150, classify.test.ts:96-121 against the Rust rows — all match input-for-input and expected-for-expected.
- **TS oracle is live and green.** `pnpm test` in plugin/cli → **245 passed, 0 failed**, confirming the goldens were ported against a current, passing TS baseline rather than a stale snapshot.
- **No parity divergence found** in any spot-checked row.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `rust/crates/agentlinux-core/src/semver_shim.rs` | `valid` (STRICT) + `satisfies` (total) | ✓ VERIFIED | `valid` uses `Version::parse(stripped)` directly (not parse_lenient) → `"2.1"`→None, `"v1.2.3"`→Some("1.2.3"). 37 tests pass. |
| `rust/crates/agentlinux-core/src/types.rs` | DetectedAgent, tags/source_kind, CategoryKey/Category, VersionDecision | ✓ VERIFIED | All present; CategoryKey kebab-serializes; serde-default on new fields. |
| `rust/crates/agentlinux-core/src/category.rs` | `derive_category` + ordered TAG_PRECEDENCE | ✓ VERIFIED | Ordered slice, not map; 12 tests pass. |
| `rust/crates/agentlinux-core/src/pin_spec.rs` | `parse_pin_spec` + PinTarget + PinSpecError | ✓ VERIFIED | Two byte-identical error messages; raw version; 10 tests pass. |
| `rust/crates/agentlinux-core/src/detect_gates.rs` | reuse/remediate/presence + path predicates | ✓ VERIFIED | Slim ReuseCandidate (no statSync); empty-window falsy; 19 tests pass. |
| `rust/crates/agentlinux-core/src/classify.rs` | `decide_version` + VersionDecision + re-assert | ✓ VERIFIED | Source inherited; 5-row golden; 15+5 tests pass. |
| `rust/crates/agentlinux-core/src/divergence.rs` | CORE-02 re-assert (both error paths) | ✓ VERIFIED | Zero-match + empty-list typed errors; 14 tests pass. |
| `rust/crates/agentlinux-core/src/lib.rs` | module registration | ✓ VERIFIED | `pub mod category/pin_spec/detect_gates` all registered. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| pin_spec.rs | semver_shim::valid | accept/reject predicate | ✓ WIRED | `semver_shim::valid(tgt).is_some()` (pin_spec.rs:116). |
| detect_gates.rs | semver_shim::valid/satisfies | version/window ops | ✓ WIRED | reuse/remediate/presence all call the shim; no direct semver::. |
| category/pin_spec/detect_gates | types.rs | CatalogEntry.tags/source_kind, DetectedAgent, CategoryKey | ✓ WIRED | All import + use the Plan-01 shared types; crate compiles. |
| classify.rs decide_version | Sentinel.source | inherit (not hardcode) | ✓ WIRED | `sentinel.source.clone()` (classify.rs:91). |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| CORE-03 parity (category/pin/detect) | `cargo test -p agentlinux-core {category,pin_spec,detect_gates}` | 12 / 10 / 19 passed | ✓ PASS |
| CORE-01 classify + decide | `cargo test -p agentlinux-core classify` / `decide` | 15 / 5 passed | ✓ PASS |
| CORE-02 divergence | `cargo test -p agentlinux-core divergence` | 14 passed | ✓ PASS |
| Full workspace | `cargo test --workspace` | 121 passed | ✓ PASS |
| Clippy | `cargo clippy --workspace --all-targets -- -D warnings` | No issues found | ✓ PASS |
| Fmt | `cargo fmt --all --check` | clean (exit 0) | ✓ PASS |
| TS oracle (anti-circularity) | `pnpm test` (plugin/cli) | 245 passed, 0 failed | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CORE-01 | 55-03 | Six-state classify identical to TS + decideVersion 5-row golden | ✓ SATISFIED | classify.rs six states + decide_version_tests (source inherited) |
| CORE-02 | 55-03 | computeDivergence + resolveLatestFor incl. zero-match | ✓ SATISFIED | divergence.rs NoSatisfyingVersion + NoPublishedVersions tests |
| CORE-03 | 55-01/02 | Detect gates, pin-spec, category derivation match TS | ✓ SATISFIED | category/pin_spec/detect_gates goldens byte-for-byte with TS |
| GATE-01 | 55-01/02/03 | Green suite, no newly-skipped; proptest/mutation gate on pure core | ✓ SATISFIED | 121 tests green, clippy/fmt clean, bats untouched, per-module proptests, crate pure |
| GATE-05 | 55-01/02/03 | master shippable, per-phase reversible | ✓ SATISFIED | master at f14c092, phase-55 additive-only under rust/ |

No orphaned requirements: all 5 phase-55 req IDs from PLAN frontmatter map to REQUIREMENTS.md and are verified.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | none | — | No TODO/FIXME/XXX/placeholder in phase-55 modules; no stubs; no hollow data. The `.expect("guard rejected None")` in pin_spec.rs:97 is provably unreachable behind the `matches!(None \| Some(0))` guard. |

### Human Verification Required

None. All truths are verifiable programmatically via the golden corpora + the live TS oracle; no runtime/visual/external-service behavior is involved (pure decision logic).

### Gaps Summary

No gaps. Every phase-55 must-have is verified against the actual codebase:

- All 8 observable truths VERIFIED with re-run evidence (not SUMMARY trust).
- CORE-03 parity spot-checks confirm the Rust goldens encode live TS verdicts (not circular re-derivation): category TAG_PRECEDENCE is an ordered slice; both pin_spec error messages are byte-identical to pin.ts with raw-version storage and STRICT valid; detect_gates return a slim statSync-free ReuseCandidate and treat empty-string compatibility_window as falsy.
- CORE-01 decide_version inherits sentinel.source (row 3 → "pinned", not hardcoded); classify six-state corpus fully mirrored.
- CORE-02 both error paths (zero-match + empty-list) covered.
- GATE-01/GATE-05: 121 workspace tests green, clippy `-D warnings` clean, fmt clean, crate pure (test-only semver::/std::fs confined to `#[cfg(test)]`), bats untouched, master at f14c092, additive-only.
- The TS oracle suite is itself green (245/0), closing the anti-circularity risk.

---

_Verified: 2026-07-28T10:20:00Z_
_Verifier: Claude (gsd-verifier)_
