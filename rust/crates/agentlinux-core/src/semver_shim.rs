//! The ONLY module that touches the dtolnay `semver` crate.
//!
//! Isolates the empirically-probed node-semver → dtolnay `semver 1.0.28`
//! divergences (RESEARCH §"node-semver → Rust semver Parity") behind
//! typed-error functions so `classify.rs` / `divergence.rs` never see them:
//!
//!   1. dtolnay `VersionReq::parse` REQUIRES a comma between compound
//!      comparators; node-semver accepts spaces. The catalog's
//!      `compatibility_window` is space-separated (">=2.0.0 <3.0.0").
//!      `normalize_range` translates space → ", " before parse.
//!   2. dtolnay `Version::parse` is strict: it rejects a leading `v`
//!      ("v1.0.0") and partials ("2.1"). node-semver loose-parses both.
//!      `parse_lenient` strips a leading `v`/whitespace and coerces a
//!      two-component partial ("2.1" → "2.1.0") before `Version::parse`.
//!
//! Every entry point returns a typed [`SemverError`] on malformed input —
//! never `unwrap`/`expect`/`panic` on untrusted version strings (threat
//! T-53-01).

use semver::{Version, VersionReq};
use thiserror::Error;

/// Typed error for every parse/range operation in the shim (threat T-53-01).
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
/// Idempotent for already-comma'd input because the split collapses the empty
/// token produced by a trailing comma is avoided (we split on whitespace only).
#[must_use]
pub fn normalize_range(node_range: &str) -> String {
    node_range.split_whitespace().collect::<Vec<_>>().join(", ")
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
/// to `MAJOR.0.0`, matching node-semver's loose coercion. Only fires when every
/// present component is purely numeric and there is no pre-release/build
/// metadata (a `-`/`+`), so real full versions and rc strings are untouched.
fn coerce_partial(v: &str) -> String {
    if v.contains('-') || v.contains('+') {
        return v.to_string();
    }
    let parts: Vec<&str> = v.split('.').collect();
    let all_numeric = parts
        .iter()
        .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()));
    if !all_numeric {
        return v.to_string();
    }
    match parts.len() {
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

    // --- normalize_range: the compound-range comma divergence (Pitfall 2) ---

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
    fn compound_range_matches_in_window_and_rejects_out() {
        // ">=2.0.0 <3.0.0" must accept 2.5.0 and reject 3.0.0 once normalized.
        let versions = vec!["2.5.0".to_string(), "3.0.0".to_string()];
        let hit = max_satisfying(&versions, ">=2.0.0 <3.0.0").unwrap();
        assert_eq!(hit, Some("2.5.0"));
    }

    // --- parse_lenient: v-prefix + partial coercion (Pitfall 1) ---

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
}
