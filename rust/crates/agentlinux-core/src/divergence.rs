//! Port of `plugin/cli/src/upgrade/divergence.ts` — the pure upgrade classifier.
//!
//! Two exports, both pure (no I/O, deterministic):
//!   - `compute_divergence` reifies the `classify` verdict plus the four version
//!     columns into a `DivergenceReport` (source "none" when the sentinel is
//!     absent).
//!   - `resolve_latest_for` picks the highest published version satisfying
//!     `entry.version_constraint` (default `*`) via `semver_shim::max_satisfying`,
//!     returning a typed `DivergenceError` on zero-match or empty input (never a
//!     panic — mirrors the TS `throw` paths, T-04-13 / T-53-01).
//!
//! Every semver operation routes through `semver_shim`; this module never calls
//! `semver::` directly.

use crate::classify::classify;
use crate::semver_shim;
use crate::types::{CatalogEntry, DivergenceReport, Sentinel};
use thiserror::Error;

/// Typed error for `resolve_latest_for`. Message shapes mirror the TS `Error`
/// strings so downstream string matching (and the ported corpus regexes) hold.
#[derive(Debug, Error)]
pub enum DivergenceError {
    /// The published-versions list was empty (defensive — a real registry should
    /// never return `[]` for a live package). Mirrors `${id}: no published
    /// versions found`.
    #[error("{id}: no published versions found")]
    NoPublishedVersions { id: String },
    /// The constraint matched zero published versions (e.g. a typo like `^9.0`
    /// against a 1.x package). Mirrors `${id}: no published version of ${pkg}
    /// satisfies constraint ${constraint}`.
    #[error("{id}: no published version of {pkg} satisfies constraint {constraint}")]
    NoSatisfyingVersion {
        id: String,
        pkg: String,
        constraint: String,
    },
    /// The constraint string itself failed to parse (surfaced from the shim).
    #[error("{id}: invalid version constraint: {source}")]
    InvalidConstraint {
        id: String,
        #[source]
        source: semver_shim::SemverError,
    },
}

/// Reify the `classify` verdict plus the four version columns into a
/// `DivergenceReport`. Mirrors `computeDivergence` (divergence.ts:35-48):
/// `source` falls back to "none" and `sticky` to `false` when the sentinel is
/// absent; `latest` threads through untouched.
#[must_use]
pub fn compute_divergence(
    entry: &CatalogEntry,
    sentinel: Option<&Sentinel>,
    installed: Option<&str>,
    latest: Option<&str>,
) -> DivergenceReport {
    let status = classify(entry, sentinel, installed);
    DivergenceReport {
        id: entry.id.clone(),
        status,
        sentinel_version: sentinel.map(|s| s.version.clone()),
        installed_version: installed.map(str::to_string),
        curated_version: entry.pinned_version.clone(),
        latest_version: latest.map(str::to_string),
        source: sentinel.map_or_else(|| "none".to_string(), |s| s.source.clone()),
        sticky: sentinel.is_some_and(|s| s.sticky),
    }
}

/// Resolve the highest published version satisfying `entry.version_constraint`.
///
/// Absent constraint → newest via `*`. Zero matches → `NoSatisfyingVersion`.
/// Empty input list → `NoPublishedVersions`. Mirrors `resolveLatestFor`
/// (divergence.ts:59-72) including both `throw` paths.
pub fn resolve_latest_for(
    entry: &CatalogEntry,
    published_versions: &[String],
) -> Result<String, DivergenceError> {
    if published_versions.is_empty() {
        return Err(DivergenceError::NoPublishedVersions {
            id: entry.id.clone(),
        });
    }
    let range = entry.version_constraint.as_deref().unwrap_or("*");
    let max = semver_shim::max_satisfying(published_versions, range).map_err(|source| {
        DivergenceError::InvalidConstraint {
            id: entry.id.clone(),
            source,
        }
    })?;
    match max {
        Some(v) => Ok(v.to_string()),
        None => {
            let pkg = entry
                .npm_package_name
                .clone()
                .unwrap_or_else(|| entry.id.clone());
            Err(DivergenceError::NoSatisfyingVersion {
                id: entry.id.clone(),
                pkg,
                // Mirrors TS `${entry.version_constraint}` — the raw constraint,
                // which is the Some(..) branch here (a None constraint is "*"
                // and cannot zero-match a non-empty list).
                constraint: entry
                    .version_constraint
                    .clone()
                    .unwrap_or_else(|| "*".to_string()),
            })
        }
    }
}

#[cfg(test)]
mod tests {
    //! Golden corpus ported verbatim from
    //! `plugin/cli/test/divergence.test.ts:42-157` — the `computeDivergence`
    //! six-state + latestVersion-threading suite and the `resolveLatestFor`
    //! table (versions at divergence.test.ts:133). The `queryGlobalNpm` /
    //! `queryNpmViewLatest` suites are NOT ported — they are impure npm-dispatcher
    //! tests (Phase 56 scope), not pure-core parity.
    use super::*;
    use crate::types::Status;

    fn e() -> CatalogEntry {
        CatalogEntry {
            id: "foo".to_string(),
            pinned_version: "1.0.0".to_string(),
            version_constraint: None,
            npm_package_name: Some("foo".to_string()),
            compatibility_window: None,
        }
    }

    fn sentinel(version: &str, source: &str, sticky: bool) -> Sentinel {
        Sentinel {
            id: "foo".to_string(),
            version: version.to_string(),
            source: source.to_string(),
            sticky,
        }
    }

    fn versions() -> Vec<String> {
        ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "2.1.0"]
            .iter()
            .map(|s| s.to_string())
            .collect()
    }

    // --- computeDivergence: six states + latestVersion threading ---

    #[test]
    fn not_installed_sentinel_null_installed_null() {
        let r = compute_divergence(&e(), None, None, None);
        assert_eq!(r.status, Status::NotInstalled);
        assert_eq!(r.sentinel_version, None);
        assert_eq!(r.installed_version, None);
        assert_eq!(r.curated_version, "1.0.0");
        assert_eq!(r.latest_version, None);
        assert_eq!(r.source, "none");
        assert!(!r.sticky);
    }

    #[test]
    fn synced_sentinel_installed_pin_all_equal() {
        let s = sentinel("1.0.0", "curated", false);
        let r = compute_divergence(&e(), Some(&s), Some("1.0.0"), None);
        assert_eq!(r.status, Status::Synced);
        assert_eq!(r.sentinel_version.as_deref(), Some("1.0.0"));
        assert_eq!(r.installed_version.as_deref(), Some("1.0.0"));
        assert_eq!(r.source, "curated");
    }

    #[test]
    fn drift_undeclared_sentinel_ne_installed() {
        let s = sentinel("1.0.0", "curated", false);
        let r = compute_divergence(&e(), Some(&s), Some("1.2.0"), None);
        assert_eq!(r.status, Status::DriftUndeclared);
        assert_eq!(r.sentinel_version.as_deref(), Some("1.0.0"));
        assert_eq!(r.installed_version.as_deref(), Some("1.2.0"));
    }

    #[test]
    fn override_behind_installed_lt_pin_not_sticky() {
        let s = sentinel("0.9.0", "override", false);
        let r = compute_divergence(&e(), Some(&s), Some("0.9.0"), None);
        assert_eq!(r.status, Status::OverrideBehind);
        assert_eq!(r.source, "override");
        assert!(!r.sticky);
    }

    #[test]
    fn override_ahead_installed_gt_pin_not_sticky() {
        let s = sentinel("1.1.0", "override", false);
        let r = compute_divergence(&e(), Some(&s), Some("1.1.0"), None);
        assert_eq!(r.status, Status::OverrideAhead);
    }

    #[test]
    fn pinned_override_sticky_installed_ne_pin() {
        let s = sentinel("1.1.0", "pinned", true);
        let r = compute_divergence(&e(), Some(&s), Some("1.1.0"), None);
        assert_eq!(r.status, Status::PinnedOverride);
        assert_eq!(r.source, "pinned");
        assert!(r.sticky);
    }

    #[test]
    fn latest_version_threaded_when_provided() {
        let s = sentinel("1.0.0", "curated", false);
        let r = compute_divergence(&e(), Some(&s), Some("1.0.0"), Some("1.2.3"));
        assert_eq!(r.latest_version.as_deref(), Some("1.2.3"));
        // status classifier ignores latestVersion
        assert_eq!(r.status, Status::Synced);
    }

    #[test]
    fn pinned_override_with_upstream_latest_populated() {
        let s = sentinel("1.1.0", "pinned", true);
        let r = compute_divergence(&e(), Some(&s), Some("1.1.0"), Some("2.0.0"));
        assert_eq!(r.status, Status::PinnedOverride);
        assert_eq!(r.latest_version.as_deref(), Some("2.0.0"));
        assert!(r.sticky);
    }

    // --- resolveLatestFor: maxSatisfying over version_constraint ---

    #[test]
    fn no_constraint_returns_newest() {
        assert_eq!(resolve_latest_for(&e(), &versions()).unwrap(), "2.1.0");
    }

    #[test]
    fn constraint_caret_1_0_respects_upper_bound() {
        let mut entry = e();
        entry.version_constraint = Some("^1.0".to_string());
        assert_eq!(resolve_latest_for(&entry, &versions()).unwrap(), "1.2.0");
    }

    #[test]
    fn constraint_tilde_1_1_respects_tilde() {
        let mut entry = e();
        entry.version_constraint = Some("~1.1".to_string());
        assert_eq!(resolve_latest_for(&entry, &versions()).unwrap(), "1.1.0");
    }

    #[test]
    fn constraint_zero_match_returns_err() {
        let mut entry = e();
        entry.version_constraint = Some("^9.0".to_string());
        let err = resolve_latest_for(&entry, &versions()).unwrap_err();
        // TS asserts /no published version.*satisfies/
        let msg = err.to_string();
        assert!(
            msg.contains("no published version") && msg.contains("satisfies"),
            "unexpected message: {msg}"
        );
        assert!(matches!(err, DivergenceError::NoSatisfyingVersion { .. }));
    }

    #[test]
    fn empty_versions_list_returns_err() {
        let err = resolve_latest_for(&e(), &[]).unwrap_err();
        // TS asserts /no published versions/
        assert!(err.to_string().contains("no published versions"));
        assert!(matches!(err, DivergenceError::NoPublishedVersions { .. }));
    }
}
