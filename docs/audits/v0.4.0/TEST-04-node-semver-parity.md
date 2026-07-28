# TEST-04 — node-semver ⇄ Rust `semver` Behavior-Parity Audit

**Milestone:** v0.4.0 (Rust Rewrite) · **Phase:** 54 (Testing Bedrock) · **Plan:** 54-01
**Subject:** `rust/crates/agentlinux-core/src/semver_shim.rs` (the sole module that
touches the dtolnay `semver` crate) vs. node's `semver` package (`node-semver`).
**Pinned `semver` version under audit:** `=1.0.28` (`rust/crates/agentlinux-core/Cargo.toml`).
**Golden test:** `semver_shim.rs` `#[cfg(test)] mod parity` — run with
`cargo test -p agentlinux-core parity`.

---

## Why this doc exists

The TypeScript CLI resolved catalog versions with `node-semver`
(`semver.satisfies` / `semver.maxSatisfying` / `semver.valid`). The Rust rewrite
routes every version comparison through dtolnay `semver` **via `semver_shim`**,
never `semver::` directly. The two libraries are **not** drop-in equivalent:
node-semver loose-parses shapes that dtolnay `semver` strictly rejects, and node
accepts space-separated compound ranges that `VersionReq::parse` rejects.
`semver_shim` reconciles those divergences behind typed-error functions. This
audit formalizes **every range/prerelease shape the live catalog uses**, records
the node-semver verdict (the oracle), the raw dtolnay behavior, and how the shim
reconciles the gap — and states the **scope boundary** of what is deliberately
NOT supported.

## The oracle: committed TypeScript corpora (node stays uninstalled)

`node-semver` is **not re-installed** for this audit (node deps are uninstalled
by design since Phase 53). The oracle is the **committed** TS test corpora, which
ran `node-semver` historically and are CI-verified on the TS side:

- `plugin/cli/test/divergence.test.ts:132-155` — the `resolveLatestFor`
  (`semver.maxSatisfying`) verdicts over `["1.0.0","1.1.0","1.2.0","2.0.0","2.1.0"]`.
- `plugin/cli/test/classify.test.ts:36-93` — the six-state `classify` rows
  (`semver.eq` / `semver.gt`), already ported to `classify.rs` tests, so the
  parity is transitively proven.

The Rust golden test seeds its corpus verbatim from `divergence.test.ts:133`.
**Tiebreaker (documented, not required):** if a verdict is ever disputed, a
one-off `node -e "require('semver').maxSatisfying(...)"` in a throwaway container
resolves it — but the phase does not depend on running it.

---

## Case-class parity table

Every case class below is a shape the live `plugin/catalog/catalog.json` uses
(or an edge the classifier must survive). "node verdict" is the oracle; "raw
dtolnay `1.0.28`" is what the bare crate does; "shim handling" is the
reconciliation in `semver_shim.rs`.

| # | Case class | Concrete catalog example(s) | node-semver verdict (oracle) | Raw dtolnay `semver 1.0.28` | Shim handling |
|---|-----------|-----------------------------|------------------------------|-----------------------------|---------------|
| 1 | **Caret** | `^2.1` (`claude-code.version_constraint`, the only live `version_constraint`); `^1.0` | `maxSatisfying(v,"^1.0")==="1.2.0"`; excludes 2.x | `VersionReq::parse("^1.0")` OK, agrees | pass-through — `max_satisfying` (`normalize_range` leaves a single comparator unchanged) |
| 2 | **Tilde** | `~1.1` (corpus edge) | `maxSatisfying(v,"~1.1")==="1.1.0"` | `VersionReq::parse("~1.1")` OK, agrees | pass-through |
| 3 | **Star / no-constraint** | absent `version_constraint` → `*` default | newest, `"2.1.0"` | `VersionReq::parse("*")` OK, agrees | `resolve_latest_for` defaults absent constraint to `"*"` |
| 4 | **Compound (space, closed)** | `>=2.0.0 <3.0.0` (every *closed* `compatibility_window` — 20 of 26 entries, e.g. `claude-code`, `sentry-mcp`) | space-separated accepted | **`VersionReq::parse` ERRORS on the space** | `normalize_range` rewrites space → `", "` before parse (`semver_shim.rs:54`) |
| 5 | **Compound (open-ended)** | `>=2026.2.17` (`slack-mcp`, `linear-mcp`, `jira-atlassian-mcp`, `openclaw`, `hermes-agent` — the 5 single-comparator windows) | accepted | single comparator parses; no space to split | `normalize_range` (no-op for a lone comparator; splits only the closed form) |
| 6 | **Exact pin** | `pinned_version` on every entry (`2.1.98`, `0.142.3`, `1.7.0`, …) | `valid` | `Version::parse` OK for full 3-part | `parse_lenient` |
| 7 | **GA-date "version"** | `2026.2.17`, `2025.5.1`, `2026.2.4`, `2026.6.10`, `2026.6.19` (hosted-MCP + agent pins) | valid 3-part numeric | `Version::parse` OK (numeric `major.minor.patch`) | `parse_lenient` — **confirmed**: these `YYYY.M.D` pins are ordinary 3-part numeric semver (year as major), so they parse with no special-casing |
| 8 | **`v`-prefix** | `v1.0.0` (from `<bin> --version` output, not the catalog) | `eq`/`gt` strip the `v` | **`Version::parse` ERRORS on leading `v`** | `parse_lenient` strips a leading `v`/`V` (`semver_shim.rs:70-73`) |
| 9 | **Two-part partial** | `2.1` (loose `<bin> --version`) | loose-coerces to `2.1.0` | **`Version::parse` ERRORS on a 2-part string** | `parse_lenient` coerces `MAJOR.MINOR` → `MAJOR.MINOR.0` (`coerce_partial`, `semver_shim.rs:85-101`) |
| 10 | **Prerelease vs non-pre range** | `^1.0` vs `1.5.0-beta`; `>=1.0.0 <2.0.0` vs `1.5.0-beta` | excluded (`false`) | excluded (`false`) — agrees | none needed; opt-in prerelease semantics already agree |
| 11 | **Zero-match** | `^9.0` vs a 1.x/2.x list | `maxSatisfying → null` (caller `throw`s) | `max_satisfying → None` | shim returns `Ok(None)`; `divergence.rs` reifies the typed `NoSatisfyingVersion` |
| 12 | **Empty published list** | `[]` | `throw` "no published versions" | n/a (guarded before parse) | `resolve_latest_for` returns typed `NoPublishedVersions` (`divergence.rs:80-84`) |
| 13 | **`valid()` on loose input** | `valid("2.1")`, `valid("v1.0.0")` | loose-accepts | strict `Version::parse` **rejects** both | never `Version::parse` a partial/`v` directly — always via `parse_lenient` |
| 14 | **Malformed range** | `"not a range"` (adversarial) | `throw` / `null` | `VersionReq::parse` ERRORS | typed `SemverError::Range` — never a panic (T-53-01) |
| 15 | **Malformed version** | `"1.x.0"`, `"not-a-version"` (adversarial) | loose or `null` | `Version::parse` ERRORS | typed `SemverError::Version` — never a panic (T-53-01) |

### How each row is proven

- **Rows 1-3, 11:** golden corpus test
  `parity_corpus_max_satisfying_matches_node_semver` (verdicts lifted from
  `divergence.test.ts:135-151`).
- **Rows 4-7:** golden catalog-driven test
  `parity_catalog_ranges_all_round_trip_the_shim` — reads the real
  `catalog.json` and asserts every `pinned_version` / `version_constraint` /
  `compatibility_window` round-trips the shim. Row 7's GA-date pins are covered
  both here and by `parity_loose_shapes_parse_like_node_semver`.
- **Rows 8-9, 13:** golden loose-shape test
  `parity_loose_shapes_parse_like_node_semver` + the `parse_lenient` unit tests.
- **Rows 10, 14-15:** the existing `semver_shim` unit tests
  (`parse_lenient_malformed_returns_err_no_panic`,
  `max_satisfying_malformed_range_returns_err`) plus the P4 totality property
  (`proptests::p4_*`), which machine-checks the no-panic contract across the
  generated loose-input space.

---

## Known scope boundary (deliberately untested / unsupported)

The live catalog uses **no** OR-ranges and **no** hyphen ranges. Those two
node-semver range features are therefore **documented as untested and
unsupported** rather than silently assumed to work:

- **OR ranges** — `^1.0 || ^2.0` (node-semver union syntax). `normalize_range`
  splits on whitespace/commas and rejoins with `", "`, which would turn
  `^1.0 || ^2.0` into `^1.0, ||, ^2.0` — **not** a valid `VersionReq`. The shim
  does **not** handle OR ranges. No catalog entry uses one.
- **Hyphen ranges** — `1.0.0 - 2.0.0` (node-semver inclusive-range sugar).
  `normalize_range` would produce `1.0.0, -, 2.0.0`, again invalid. The shim does
  **not** handle hyphen ranges. No catalog entry uses one.

**If a future catalog adds an OR-range or a hyphen-range**, the catalog-driven
golden test (`parity_catalog_ranges_all_round_trip_the_shim`) **fails** at that
entry — that is the intended guard. The fix is to extend `semver_shim`
(`normalize_range` → emit the comma/union form dtolnay accepts, or split the
range into multiple `VersionReq`s) **and** extend this TEST-04 doc + golden test
with the new case class. Do not loosen the golden test to make a new shape pass
silently.

---

## Reconciliation summary

`semver_shim` reconciles exactly two node-semver → dtolnay `1.0.28` divergences,
both isolated behind typed-error functions so `classify.rs` / `divergence.rs`
never see raw `semver` behavior:

1. **Compound-range separator** — node accepts spaces between comparators;
   dtolnay requires commas. `normalize_range` translates space → `", "`
   (idempotently — machine-checked by `p4_normalize_range_idempotent`).
2. **Loose version acceptance** — node loose-parses `v`-prefix and two-part
   partials; dtolnay `Version::parse` is strict. `parse_lenient` strips a leading
   `v`/`V` and coerces `MAJOR.MINOR` → `MAJOR.MINOR.0` before parsing.

Everything else (caret/tilde/star semantics, prerelease exclusion, ordering)
**agrees** between the two libraries for the shapes the catalog uses, so the shim
passes those through unchanged. The `semver = "=1.0.28"` pin is load-bearing:
this parity was audited against that exact version, and a bump could silently
shift behavior — **do not bump `semver` without re-running this audit.**
