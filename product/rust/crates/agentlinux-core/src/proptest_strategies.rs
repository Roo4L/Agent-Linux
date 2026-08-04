//! Shared proptest strategy generators for the pure core's property tests
//! (TEST-01). Test-only (`#[cfg(test)]` at the crate root), so nothing here
//! ships in the compiled crate.
//!
//! dtolnay `semver` ships no `proptest`/`Arbitrary` `Strategy`, so these are
//! hand-written string strategies. They are
//! deliberately *catalog-realistic*: a full-version generator, a loose-version
//! generator that adds the `v`-prefix + two-part partial shapes `parse_lenient`
//! is contracted to accept (so totality properties exercise the exact loose
//! inputs a real `<bin> --version` emits), and a range generator covering the
//! caret / tilde / star / space-separated-compound shapes the live catalog uses
//! (`^2.1`, `>=2.0.0 <3.0.0`, …).

use proptest::prelude::*;

/// A catalog-realistic full-version string, e.g. `"12.3.45"`. Components are
/// bounded so the generated space stays small enough for the default 256 cases
/// while still crossing the interesting ordering boundaries.
pub fn version_str() -> impl Strategy<Value = String> {
    (0u64..50, 0u64..50, 0u64..50).prop_map(|(a, b, c)| format!("{a}.{b}.{c}"))
}

/// A version string that MAY carry a prerelease tag or build metadata —
/// `"1.2.3"`, `"1.2.3-rc.1"`, `"1.2.3-alpha"`, `"1.2.3+build.5"`.
///
/// Prerelease ordering is node-semver's #1 divergence source and the reason the
/// shim exists, yet [`version_str`] alone can never cross it: a list of plain
/// `X.Y.Z` versions never exercises "a prerelease is LESS than its release", nor
/// "a range without a prerelease does not match a prerelease". Anything
/// selecting a maximum from a candidate list should generate from HERE.
pub fn prerelease_version_str() -> impl Strategy<Value = String> {
    prop_oneof![
        // Plain releases stay well represented — the common case.
        3 => version_str(),
        2 => (version_str(), prop_oneof![
            Just("alpha"),
            Just("beta"),
            Just("rc.1"),
            Just("rc.2"),
            Just("0"),
            Just("1"),
        ])
        .prop_map(|(v, tag)| format!("{v}-{tag}")),
        1 => version_str().prop_map(|v| format!("{v}+build.5")),
    ]
}

/// A version string with the node-loose shapes the shim must accept: a full
/// version, a `v`-prefixed version (`"v1.2.3"`), or a two-part partial
/// (`"2.1"` → coerced to `"2.1.0"`). Feeds P1/P4 totality — every branch of
/// `parse_lenient`'s lenient acceptance is represented.
pub fn loose_version_str() -> impl Strategy<Value = String> {
    prop_oneof![
        version_str(),
        version_str().prop_map(|v| format!("v{v}")),
        (0u64..50, 0u64..50).prop_map(|(a, b)| format!("{a}.{b}")),
    ]
}

/// A range string drawn from the shapes the live catalog uses: caret, tilde,
/// star, or a space-separated compound (`>=X.0.0 <Y.0.0`). The compound uses a
/// space (not a comma) on purpose — that is exactly the node-semver divergence
/// `normalize_range` reconciles, so P4/P3 exercise the shim's translation path.
pub fn range_str() -> impl Strategy<Value = String> {
    prop_oneof![
        (0u64..10, 0u64..10).prop_map(|(a, b)| format!("^{a}.{b}")),
        (0u64..10, 0u64..10).prop_map(|(a, b)| format!("~{a}.{b}")),
        Just("*".to_string()),
        (0u64..10, 10u64..20).prop_map(|(a, b)| format!(">={a}.0.0 <{b}.0.0")),
    ]
}
