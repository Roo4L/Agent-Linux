//! The ONLY module that touches the dtolnay `semver` crate.
//!
//! Isolates the empirically-probed node-semver → dtolnay `semver 1.0.28`
//! divergences behind
//! typed-error functions so `classify.rs` / `divergence.rs` never see them:
//!
//!  1. dtolnay `VersionReq::parse` REQUIRES a comma between compound
//!     comparators; node-semver accepts spaces. The catalog's
//!     `compatibility_window` is space-separated (">=2.0.0 <3.0.0").
//!     `normalize_range` translates space → ", " before parse.
//!  2. dtolnay `Version::parse` is strict: it rejects a leading `v`
//!     ("v1.0.0") and partials ("2.1"). node-semver loose-parses both.
//!     `parse_lenient` strips a leading `v`/whitespace and coerces a
//!     two-component partial ("2.1" → "2.1.0") before `Version::parse`.
//!
//! Every entry point returns a typed [`SemverError`] on malformed input —
//! never `unwrap`/`expect`/`panic` on untrusted version strings.

use semver::{Version, VersionReq};
use thiserror::Error;

/// Typed error for every parse/range operation in the shim.
#[derive(Debug, Error)]
pub enum SemverError {
    /// A concrete version string (from `<bin> --version` / `npm ls`) failed to
    /// parse even after lenient normalization.
    #[error("invalid version {raw:?}: {source}")]
    Version {
        raw: String,
        #[source]
        source: semver::Error,
    },
    /// A range/constraint string failed to parse after `normalize_range`.
    #[error("invalid version range {raw:?}: {source}")]
    Range {
        raw: String,
        #[source]
        source: semver::Error,
    },
}

/// Convert a node-style space-separated compound range into the comma form
/// dtolnay `VersionReq::parse` accepts.
///
/// `">=2.0.0 <3.0.0"` → `">=2.0.0, <3.0.0"`. A single comparator (`"^2.1"`,
/// `"*"`, `"~1.1"`) has no interior whitespace and passes through unchanged.
///
/// Idempotent: an already-comma'd range (`">=2.0.0, <3.0.0"`) round-trips
/// unchanged. We split on any run of whitespace *and/or* commas, drop empty
/// tokens, then re-join with ", " — so a comma already present does not produce
/// a doubled `",,"` separator that `VersionReq::parse` would reject.
///
/// Not supported: node-semver OR-ranges (`"^1.0 || ^2.0"`) and hyphen ranges
/// (`"1.0.0 - 2.0.0"`). This tokenizer mangles them into `"^1.0, ||, ^2.0"` /
/// `"1.0.0, -, 2.0.0"`, which `VersionReq::parse` rejects. No catalog entry uses
/// either shape; if one is added, extend this function
/// (`parity_catalog_ranges_all_round_trip_the_shim` fails first).
#[must_use]
pub fn normalize_range(node_range: &str) -> String {
    node_range
        .split(|c: char| c.is_whitespace() || c == ',')
        .filter(|tok| !tok.is_empty())
        .collect::<Vec<_>>()
        .join(", ")
}

/// Lenient version parse mirroring node-semver's loose acceptance of the shapes
/// that reach classify's `eq`/`gt` from real `<bin> --version` output.
///
/// Strips surrounding whitespace and a single leading `v`/`V`, then coerces a
/// bare two-component partial (`"2.1"` → `"2.1.0"`) before `Version::parse`.
/// Anything still unparseable returns [`SemverError::Version`] (no panic).
pub fn parse_lenient(raw: &str) -> Result<Version, SemverError> {
    let trimmed = raw.trim();
    let stripped = trimmed
        .strip_prefix('v')
        .or_else(|| trimmed.strip_prefix('V'))
        .unwrap_or(trimmed);
    let coerced = coerce_partial(stripped);
    Version::parse(&coerced).map_err(|source| SemverError::Version {
        raw: raw.to_string(),
        source,
    })
}

/// Coerce a bare `MAJOR.MINOR` partial to `MAJOR.MINOR.0`, and a bare `MAJOR`
/// to `MAJOR.0.0`, matching node-semver's loose coercion; a 3+-component string
/// (a full version, prerelease, or build) is left untouched.
///
/// The coercion keys purely on the dot-component COUNT and lets the downstream
/// [`Version::parse`] in [`parse_lenient`] be the sole validator: appending `.0`
/// to a non-numeric partial (`"1.beta"` → `"1.beta.0"`) still fails to parse, so a
/// separate numeric/`-`/`+` pre-guard would only ever reject inputs `parse` already
/// rejects — it changes no observable outcome. Keeping the single count switch
/// avoids that redundant, unobservable branch (and the equivalent-mutant it breeds).
fn coerce_partial(v: &str) -> String {
    match v.split('.').count() {
        1 => format!("{v}.0.0"),
        2 => format!("{v}.0"),
        _ => v.to_string(),
    }
}

/// Equality of two concrete version strings via lenient parse (node `semver.eq`).
pub fn eq(a: &str, b: &str) -> Result<bool, SemverError> {
    Ok(parse_lenient(a)? == parse_lenient(b)?)
}

/// `a > b` on two concrete version strings via lenient parse (node `semver.gt`).
pub fn gt(a: &str, b: &str) -> Result<bool, SemverError> {
    Ok(parse_lenient(a)? > parse_lenient(b)?)
}

/// Validate a concrete version string mirroring node `semver.valid`: returns the
/// NORMALIZED version string, or `None`.
///
/// STRICT on partials: node `semver.valid` accepts
/// full versions and prereleases (`"2.1.7-beta.1"`), accepts and normalizes a
/// leading `v` (`"v1.2.3"` → `"1.2.3"`), but REJECTS partials (`"2.1"` → `null`)
/// and ranges (`"^2.1"` → `null`). Pins are version points, not ranges
///
/// Unlike [`parse_lenient`], this does NOT route through [`coerce_partial`] — a
/// bare `"2.1"` must NOT be coerced to `"2.1.0"` and accepted, because the TS
/// `parsePinSpec` rejects it. We trim, strip a single leading `v`/`V` (node's one
/// loose allowance), then call `Version::parse` DIRECTLY; on success return the
/// normalized `to_string()` form, on parse error return `None`.
#[must_use]
pub fn valid(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    let stripped = trimmed
        .strip_prefix('v')
        .or_else(|| trimmed.strip_prefix('V'))
        .unwrap_or(trimmed);
    Version::parse(stripped).ok().map(|v| v.to_string())
}

/// Does `version` satisfy `node_range`? (node `semver.satisfies`, detect.ts:179,273).
///
/// TOTAL: returns a bool for any input, never `Err`, never panics.
/// The range is normalized via [`normalize_range`] so the node
/// space→comma compound-range divergence is handled; a malformed range → `false`.
/// The version is lenient-parsed via [`parse_lenient`] so a cache version like
/// `"v1.37.1"` satisfies; an unparseable version → `false`.
#[must_use]
pub fn satisfies(version: &str, node_range: &str) -> bool {
    let Ok(req) = VersionReq::parse(&normalize_range(node_range)) else {
        return false;
    };
    match parse_lenient(version) {
        Ok(v) => req.matches(&v),
        Err(_) => false,
    }
}

/// Highest version in `versions` satisfying `node_range` (node
/// `semver.maxSatisfying`). `node_range` is normalized before parse. Versions
/// that fail lenient parse are skipped (mirrors node ignoring invalid entries).
/// Returns `Ok(None)` when nothing matches (the caller reifies the typed
/// zero-match error), `Err` only when the range itself is malformed.
pub fn max_satisfying<'a>(
    versions: &'a [String],
    node_range: &str,
) -> Result<Option<&'a str>, SemverError> {
    let req =
        VersionReq::parse(&normalize_range(node_range)).map_err(|source| SemverError::Range {
            raw: node_range.to_string(),
            source,
        })?;
    let mut best: Option<(&'a str, Version)> = None;
    for raw in versions {
        let Ok(parsed) = parse_lenient(raw) else {
            continue;
        };
        if req.matches(&parsed) {
            match &best {
                Some((_, cur)) if *cur >= parsed => {}
                _ => best = Some((raw.as_str(), parsed)),
            }
        }
    }
    Ok(best.map(|(raw, _)| raw))
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- normalize_range: the compound-range comma divergence ---

    #[test]
    fn normalize_range_inserts_commas_for_compound() {
        assert_eq!(normalize_range(">=2.0.0 <3.0.0"), ">=2.0.0, <3.0.0");
    }

    #[test]
    fn normalize_range_passes_single_comparators_through() {
        assert_eq!(normalize_range("^2.1"), "^2.1");
        assert_eq!(normalize_range("*"), "*");
        assert_eq!(normalize_range("~1.1"), "~1.1");
    }

    #[test]
    fn normalize_range_is_idempotent_on_comma_form() {
        // Feeding an already-normalized range back through must NOT produce a
        // doubled ",," separator (which VersionReq::parse rejects).
        let once = normalize_range(">=2.0.0 <3.0.0");
        assert_eq!(once, ">=2.0.0, <3.0.0");
        assert_eq!(normalize_range(&once), ">=2.0.0, <3.0.0");
        // And the comma-form range still parses + matches after a round-trip.
        let versions = vec!["2.5.0".to_string(), "3.0.0".to_string()];
        assert_eq!(max_satisfying(&versions, &once).unwrap(), Some("2.5.0"));
    }

    #[test]
    fn compound_range_matches_in_window_and_rejects_out() {
        // ">=2.0.0 <3.0.0" must accept 2.5.0 and reject 3.0.0 once normalized.
        let versions = vec!["2.5.0".to_string(), "3.0.0".to_string()];
        let hit = max_satisfying(&versions, ">=2.0.0 <3.0.0").unwrap();
        assert_eq!(hit, Some("2.5.0"));
    }

    // --- parse_lenient: v-prefix + partial coercion ---

    #[test]
    fn parse_lenient_strips_v_prefix() {
        assert_eq!(
            parse_lenient("v1.0.0").unwrap(),
            parse_lenient("1.0.0").unwrap()
        );
    }

    #[test]
    fn parse_lenient_coerces_two_component_partial() {
        assert_eq!(
            parse_lenient("2.1").unwrap(),
            parse_lenient("2.1.0").unwrap()
        );
    }

    #[test]
    fn parse_lenient_accepts_full_version() {
        assert_eq!(parse_lenient("2.1.0").unwrap(), Version::new(2, 1, 0));
    }

    #[test]
    fn parse_lenient_malformed_returns_err_no_panic() {
        assert!(parse_lenient("not-a-version").is_err());
        assert!(matches!(
            parse_lenient("1.x.0"),
            Err(SemverError::Version { .. })
        ));
    }

    #[test]
    fn parse_lenient_coerces_bare_major_partial() {
        // A single-component partial "2" coerces to "2.0.0" (the `1 =>` match arm
        // in coerce_partial); without that arm "2" would fail Version::parse.
        assert_eq!(parse_lenient("2").unwrap(), Version::new(2, 0, 0));
        assert_eq!(parse_lenient("2").unwrap(), parse_lenient("2.0.0").unwrap());
    }

    #[test]
    fn parse_lenient_leaves_prerelease_and_build_uncoerced() {
        // Coercion counts dot-separated components, so a 3-component string is
        // already whole and passes through untouched — prerelease and build
        // metadata ride along inside that third component.
        assert_eq!(
            parse_lenient("1.2.3-rc1").unwrap(),
            Version::parse("1.2.3-rc1").unwrap()
        );
        // "1.beta" IS coerced (2 components → "1.beta.0") — coerce_partial counts
        // components, it does not check that they are numeric. The rejection comes
        // one step later, from `Version::parse`, which refuses a non-numeric minor.
        // Same observable answer, different mechanism than a coercion-set guard.
        assert!(parse_lenient("1.beta").is_err());
    }

    #[test]
    fn gt_is_strict_not_ge() {
        // Strictly-greater: equal versions are NOT gt (guards `>` vs `>=`).
        assert!(!gt("1.2.3", "1.2.3").unwrap());
        assert!(gt("2.0.0", "1.9.9").unwrap());
        assert!(!gt("1.0.0", "2.0.0").unwrap());
    }

    // --- max_satisfying: the divergence.test.ts corpus divergences ---

    #[test]
    fn max_satisfying_caret_respects_upper_bound() {
        let versions: Vec<String> = ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "2.1.0"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(max_satisfying(&versions, "^1.0").unwrap(), Some("1.2.0"));
    }

    #[test]
    fn max_satisfying_tilde_respects_bound() {
        let versions: Vec<String> = ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "2.1.0"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(max_satisfying(&versions, "~1.1").unwrap(), Some("1.1.0"));
    }

    #[test]
    fn max_satisfying_star_returns_newest() {
        let versions: Vec<String> = ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "2.1.0"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(max_satisfying(&versions, "*").unwrap(), Some("2.1.0"));
    }

    #[test]
    fn max_satisfying_picks_max_not_last_when_unsorted() {
        // The input is DESCENDING, so "keep current if it's >= the candidate" and
        // "always take the latest seen" diverge: the true max (1.2.0) comes FIRST,
        // and a later-but-smaller match (1.0.0) must NOT displace it. Guards the
        // `*cur >= parsed` selection against an always-replace mutation.
        let versions: Vec<String> = ["1.2.0", "1.1.0", "1.0.0"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(max_satisfying(&versions, "^1.0").unwrap(), Some("1.2.0"));
    }

    #[test]
    fn max_satisfying_zero_match_returns_none() {
        let versions: Vec<String> = ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "2.1.0"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(max_satisfying(&versions, "^9.0").unwrap(), None);
    }

    #[test]
    fn max_satisfying_malformed_range_returns_err() {
        let versions = vec!["1.0.0".to_string()];
        assert!(matches!(
            max_satisfying(&versions, "not a range"),
            Err(SemverError::Range { .. })
        ));
    }

    // --- eq / gt ---

    #[test]
    fn eq_and_gt_on_concrete_versions() {
        assert!(eq("1.0.0", "1.0.0").unwrap());
        assert!(!eq("1.0.0", "1.1.0").unwrap());
        assert!(gt("1.1.0", "1.0.0").unwrap());
        assert!(!gt("1.0.0", "1.1.0").unwrap());
    }

    #[test]
    fn eq_handles_v_prefix_parity() {
        // node semver.eq("v1.0.0","1.0.0") === true
        assert!(eq("v1.0.0", "1.0.0").unwrap());
    }

    // --- valid: STRICT node semver.valid parity ---
    //
    // node `semver.valid(x)` returns the NORMALIZED version string or null:
    //  - accepts full versions + prereleases,
    //  - accepts a leading `v` (normalizing it away),
    //  - REJECTS partials ("2.1") and ranges ("^2.1") — pins are version
    //  points, not ranges.
    // The shim's `valid` must therefore NOT reuse parse_lenient's partial
    // coercion, which would wrongly accept "2.1".

    #[test]
    fn valid_accepts_full_version_returns_normalized() {
        // valid("2.1.7") → Some("2.1.7")
        assert_eq!(valid("2.1.7"), Some("2.1.7".to_string()));
    }

    #[test]
    fn valid_accepts_prerelease() {
        // valid("2.1.7-beta.1") → Some("2.1.7-beta.1") (prereleases accepted)
        assert_eq!(valid("2.1.7-beta.1"), Some("2.1.7-beta.1".to_string()));
    }

    #[test]
    fn valid_strips_and_normalizes_v_prefix() {
        // A1 cross-check row: valid("v1.2.3") → Some("1.2.3") (leading v stripped,
        // the NORMALIZED form is returned, not the input).
        assert_eq!(valid("v1.2.3"), Some("1.2.3".to_string()));
    }

    #[test]
    fn valid_rejects_two_component_partial() {
        // A1 cross-check row: valid("2.1") → None. This is the strict subtlety —
        // it must NOT coerce "2.1" → "2.1.0" the way parse_lenient does. node
        // semver.valid("2.1") === null.
        assert_eq!(valid("2.1"), None);
    }

    #[test]
    fn valid_rejects_range_and_garbage_and_empty() {
        // valid("^2.1") → None (a range, not a version point)
        assert_eq!(valid("^2.1"), None);
        // valid("bogus") → None
        assert_eq!(valid("bogus"), None);
        // valid("") → None
        assert_eq!(valid(""), None);
    }

    // --- satisfies: total node semver.satisfies parity ---

    #[test]
    fn satisfies_compound_range_in_and_out_of_window() {
        // satisfies("2.5.0", ">=2.0.0 <3.0.0") → true (compound via normalize_range)
        assert!(satisfies("2.5.0", ">=2.0.0 <3.0.0"));
        // satisfies("3.0.0", ">=2.0.0 <3.0.0") → false
        assert!(!satisfies("3.0.0", ">=2.0.0 <3.0.0"));
    }

    #[test]
    fn satisfies_lenient_parses_version_v_prefix() {
        // satisfies("v1.37.1", ">=1.37.0 <2.0.0") → true (version lenient-parsed)
        assert!(satisfies("v1.37.1", ">=1.37.0 <2.0.0"));
    }

    #[test]
    fn satisfies_malformed_inputs_return_false_never_panic() {
        // satisfies("x", "^1") → false (version unparseable)
        assert!(!satisfies("x", "^1"));
        // satisfies("1.0.0", "not a range") → false (range unparseable, no panic)
        assert!(!satisfies("1.0.0", "not a range"));
    }
}

#[cfg(test)]
mod parity {
    //! TEST-04 — node-semver ⇄ dtolnay `semver 1.0.28` behavior-parity golden
    //! tests. Every fn name contains `parity` so `cargo test -p agentlinux-core
    //! parity` selects exactly this module.
    //!
    //! The oracle is the COMMITTED TypeScript corpora (node deps stay
    //! uninstalled by design): the `maxSatisfying` verdicts are recorded verbatim
    //! from the pre-cutover TypeScript suite. Every comparison routes
    //! through `semver_shim` (never `semver::` directly) so parity stays isolated.
    use super::*;

    /// The `divergence.test.ts:133` version list, reused verbatim as the oracle.
    fn corpus_versions() -> Vec<String> {
        ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "2.1.0"]
            .iter()
            .map(|s| (*s).to_string())
            .collect()
    }

    // --- Corpus case: max_satisfying verdicts == recorded node-semver verdicts ---

    #[test]
    fn parity_corpus_max_satisfying_matches_node_semver() {
        let v = corpus_versions();
        // node semver.maxSatisfying(v, "^1.0") === "1.2.0" (caret upper bound)
        assert_eq!(max_satisfying(&v, "^1.0").unwrap(), Some("1.2.0"));
        // node semver.maxSatisfying(v, "~1.1") === "1.1.0" (tilde bound)
        assert_eq!(max_satisfying(&v, "~1.1").unwrap(), Some("1.1.0"));
        // no-constraint (resolveLatestFor default "*") === "2.1.0" (newest)
        assert_eq!(max_satisfying(&v, "*").unwrap(), Some("2.1.0"));
        // node semver.maxSatisfying(v, "^9.0") === null (zero-match)
        assert_eq!(max_satisfying(&v, "^9.0").unwrap(), None);
    }

    // --- valid/satisfies case: A1 STRICT-valid + satisfies parity ---

    #[test]
    fn parity_valid_strict_rejects_partials_accepts_prerelease() {
        // The A1 cross-check the pin.test.ts corpus does NOT exercise — added
        // here as the parity oracle boundary. node semver.valid semantics:
        //  semver.valid("2.1.7") === "2.1.7"
        //  semver.valid("2.1.7-beta.1") === "2.1.7-beta.1"
        //  semver.valid("v1.2.3") === "1.2.3" (normalized)
        //  semver.valid("2.1") === null (partial REJECTED)
        //  semver.valid("^2.1") === null (range REJECTED)
        assert_eq!(valid("2.1.7"), Some("2.1.7".to_string()));
        assert_eq!(valid("2.1.7-beta.1"), Some("2.1.7-beta.1".to_string()));
        assert_eq!(valid("v1.2.3"), Some("1.2.3".to_string()));
        assert_eq!(valid("2.1"), None);
        assert_eq!(valid("^2.1"), None);
    }

    #[test]
    fn parity_satisfies_matches_node_semver_over_window() {
        // node semver.satisfies(version, compatibility_window) verdicts.
        //  satisfies("2.5.0", ">=2.0.0 <3.0.0") === true
        //  satisfies("3.0.0", ">=2.0.0 <3.0.0") === false
        //  satisfies("v1.37.1", ">=1.37.0 <2.0.0") === true (lenient version)
        assert!(satisfies("2.5.0", ">=2.0.0 <3.0.0"));
        assert!(!satisfies("3.0.0", ">=2.0.0 <3.0.0"));
        assert!(satisfies("v1.37.1", ">=1.37.0 <2.0.0"));
    }

    // --- Loose-shape case: parse_lenient parity with node-semver's loose accept ---

    #[test]
    fn parity_loose_shapes_parse_like_node_semver() {
        // node semver.eq("v1.0.0","1.0.0") === true (v-prefix stripped)
        assert_eq!(
            parse_lenient("v1.0.0").unwrap(),
            parse_lenient("1.0.0").unwrap()
        );
        // node coerces "2.1" → "2.1.0" in range/version context
        assert_eq!(
            parse_lenient("2.1").unwrap(),
            parse_lenient("2.1.0").unwrap()
        );
        // GA-date "pins" are ordinary 3-part numeric semver — parse without error.
        for ga in ["2026.2.17", "2025.5.1", "2026.2.4"] {
            let parsed = parse_lenient(ga)
                .unwrap_or_else(|e| panic!("GA-date pin {ga:?} failed to parse: {e}"));
            // sanity: the major component is the year (>= 2025).
            assert!(parsed.major >= 2025, "GA-date {ga} parsed as {parsed}");
        }
    }

    // --- Catalog-driven case: every LIVE catalog range/pin round-trips the shim ---

    /// Reads the real `plugin/catalog/catalog.json` (CARGO_MANIFEST_DIR-relative)
    /// and asserts every `pinned_version` `parse_lenient`-parses and every
    /// `version_constraint` / `compatibility_window` `normalize_range`-then-parses.
    /// A future catalog edit introducing a range shape the shim mis-handles fails
    /// HERE — this is the regression guard TEST-04 exists to provide.
    #[test]
    fn parity_catalog_ranges_all_round_trip_the_shim() {
        use semver::VersionReq;

        const CATALOG_PATH: &str = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../plugin/catalog/catalog.json"
        );
        let raw = std::fs::read_to_string(CATALOG_PATH)
            .unwrap_or_else(|e| panic!("cannot read catalog at {CATALOG_PATH}: {e}"));
        let catalog: serde_json::Value =
            serde_json::from_str(&raw).expect("catalog.json is valid JSON");
        let agents = catalog["agents"]
            .as_array()
            .expect("catalog.json has an `agents` array");
        assert!(!agents.is_empty(), "catalog has at least one agent");

        for agent in agents {
            let id = agent["id"].as_str().unwrap_or("<no-id>");

            // pinned_version: must parse via the lenient version parser.
            if let Some(pin) = agent["pinned_version"].as_str() {
                parse_lenient(pin).unwrap_or_else(|e| {
                    panic!("[{id}] pinned_version {pin:?} failed parse_lenient: {e}")
                });
            }

            // version_constraint + compatibility_window: normalize_range then
            // VersionReq::parse must succeed (the shim's range-handling contract).
            for (field, name) in [
                (&agent["version_constraint"], "version_constraint"),
                (&agent["compatibility_window"], "compatibility_window"),
            ] {
                if let Some(range) = field.as_str() {
                    let normalized = normalize_range(range);
                    VersionReq::parse(&normalized).unwrap_or_else(|e| {
                        panic!(
                            "[{id}] {name} {range:?} → normalize_range {normalized:?} \
                             failed VersionReq::parse: {e} — a range shape the shim \
                             does not handle; extend semver_shim + TEST-04"
                        )
                    });
                }
            }
        }
    }
}

#[cfg(test)]
mod proptests {
    //! Property test P4 (TEST-01) — `semver_shim` parse/normalize/max_satisfying
    //! totality + idempotence. The crate's no-panic contract
    //! becomes machine-checked over the generated loose-input space, not just the
    //! handful of example rows.
    use super::*;
    use crate::proptest_strategies::{loose_version_str, range_str, version_str};
    use proptest::prelude::*;

    proptest! {
        // P4a — normalize_range is IDEMPOTENT: normalizing an already-normalized
        // range is a fixpoint. Generalizes the single #[test] fixpoint case above.
        #[test]
        fn p4_normalize_range_idempotent(range in range_str()) {
            let once = normalize_range(&range);
            let twice = normalize_range(&once);
            prop_assert_eq!(once, twice);
        }

        // P4a' — idempotence must hold for ARBITRARY strings too, not only the
        // catalog-realistic range shapes (normalize_range is a total string fn).
        #[test]
        fn p4_normalize_range_idempotent_arbitrary(range in ".*") {
            let once = normalize_range(&range);
            let twice = normalize_range(&once);
            prop_assert_eq!(once, twice);
        }

        // P4b — parse_lenient never PANICS on loose inputs: Ok or a typed Err.
        // The match arms are the assertion; reaching either without unwinding
        // proves totality.
        #[test]
        fn p4_parse_lenient_total_on_loose(v in loose_version_str()) {
            match parse_lenient(&v) {
                Ok(_) => {}
                Err(SemverError::Version { .. }) => {}
                Err(other) => prop_assert!(
                    false,
                    "parse_lenient returned an unexpected error variant: {:?}",
                    other
                ),
            }
        }

        // P4b' — parse_lenient never panics on ARBITRARY (adversarial) strings.
        #[test]
        fn p4_parse_lenient_total_on_arbitrary(v in ".*") {
            let _ = parse_lenient(&v);
        }

        // P4d — valid never PANICS on loose inputs: Some(normalized) or None.
        // And any Some(_) it returns is itself a strictly-valid version (feeding
        // valid's own output back in is a fixpoint: idempotent normalization).
        #[test]
        fn p4_valid_total_and_idempotent_on_loose(v in loose_version_str()) {
            // Some(normalized) → idempotent (feeding valid's output back in is a
            // fixpoint); None is legal (partial/range/garbage). Reaching either
            // arm without unwinding is the totality proof.
            if let Some(normalized) = valid(&v) {
                prop_assert_eq!(valid(&normalized), Some(normalized));
            }
        }

        // P4d' — valid never panics on ARBITRARY (adversarial) strings.
        #[test]
        fn p4_valid_total_on_arbitrary(v in ".*") {
            let _ = valid(&v);
        }

        // P4e — satisfies is TOTAL: any (version, range) yields a bool, never
        // panics (malformed range/version → false). Threat.
        #[test]
        fn p4_satisfies_total_on_loose(
            v in loose_version_str(),
            range in range_str(),
        ) {
            let _: bool = satisfies(&v, &range);
        }

        // P4e' — satisfies never panics on ARBITRARY (adversarial) inputs.
        #[test]
        fn p4_satisfies_total_on_arbitrary(v in ".*", range in ".*") {
            let _: bool = satisfies(&v, &range);
        }

        // P4c — max_satisfying never panics, and any returned version is a member
        // of the input list AND actually satisfies the range (output soundness).
        #[test]
        fn p4_max_satisfying_total_and_sound(
            versions in proptest::collection::vec(version_str(), 0..8),
            range in range_str(),
        ) {
            match max_satisfying(&versions, &range) {
                Ok(Some(best)) => {
                    // membership: the winner is one of the inputs.
                    prop_assert!(
                        versions.iter().any(|v| v == best),
                        "max_satisfying returned {:?} not in {:?}",
                        best,
                        versions
                    );
                    // soundness: the winner satisfies the range — verified
                    // INDEPENDENTLY of max_satisfying via dtolnay
                    // VersionReq::matches directly, NOT by re-calling the
                    // function under test. A broken selection/filter loop that
                    // returns an out-of-range winner cannot mask a non-match
                    // here (a circular single-element re-check would).
                    let req = VersionReq::parse(&normalize_range(&range))
                        .expect("range parsed once already by max_satisfying");
                    let winner = parse_lenient(best)
                        .expect("winner came from the parsed, matched input set");
                    prop_assert!(
                        req.matches(&winner),
                        "max_satisfying winner {:?} does not satisfy range {:?}",
                        best, range
                    );
                }
                Ok(None) => {} // legal: nothing matched.
                Err(SemverError::Range { .. }) => {} // legal: malformed range.
                Err(other) => prop_assert!(
                    false,
                    "max_satisfying returned an unexpected error variant: {:?}",
                    other
                ),
            }
        }
    }
}
