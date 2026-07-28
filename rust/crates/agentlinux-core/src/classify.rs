//! Port of `plugin/cli/src/version/classify.ts` — the six-state version
//! classifier. Pure; no I/O. Every version comparison routes through
//! `semver_shim` (never `semver::` directly) so the node-semver divergences
//! stay isolated.
//!
//! Branch order is preserved verbatim from the TS source (classify.ts:15-27):
//!   1. null sentinel OR null installed          → NotInstalled
//!   2. sentinel.version != installed            → DriftUndeclared
//!   3. installed == entry.pinned_version        → Synced
//!   4. sentinel.sticky                          → PinnedOverride
//!   5. installed > pinned ? OverrideAhead : OverrideBehind

use crate::semver_shim;
use crate::types::{CatalogEntry, Sentinel, Status};

/// Classify the divergence between the catalog pin, the sentinel record, and the
/// version actually installed on disk. Mirrors the TS `classify()` verdict for
/// every row of the `classify.test.ts` golden corpus.
///
/// A malformed version string that reaches `eq`/`gt` cannot occur for the corpus
/// (all inputs are concrete versions), but if the shim errors we treat it as
/// drift — the safe non-Synced verdict — rather than panicking (T-53-01).
#[must_use]
pub fn classify(
    entry: &CatalogEntry,
    sentinel: Option<&Sentinel>,
    installed: Option<&str>,
) -> Status {
    // 1. not-installed: no sentinel record OR nothing on disk.
    let (Some(sentinel), Some(installed)) = (sentinel, installed) else {
        return Status::NotInstalled;
    };

    // 2. drift-undeclared: sentinel disagrees with what is actually on disk
    //    (someone ran `claude update` / `npm install -g` outside our CLI).
    if !semver_shim::eq(&sentinel.version, installed).unwrap_or(false) {
        return Status::DriftUndeclared;
    }

    // 3. synced: installed matches the curated pin exactly.
    if semver_shim::eq(installed, &entry.pinned_version).unwrap_or(false) {
        return Status::Synced;
    }

    // 4. pinned-override: operator pinned a non-curated version deliberately.
    if sentinel.sticky {
        return Status::PinnedOverride;
    }

    // 5. override-ahead / override-behind relative to the pin.
    if semver_shim::gt(installed, &entry.pinned_version).unwrap_or(false) {
        Status::OverrideAhead
    } else {
        Status::OverrideBehind
    }
}

#[cfg(test)]
mod tests {
    //! Golden corpus ported verbatim from `plugin/cli/test/classify.test.ts:36-93`
    //! (the six `classify()` states). The `decideVersion` suite is NOT ported —
    //! `decideVersion` is Phase 55/56 scope, not part of this spike's pure core.
    use super::*;

    fn base_entry() -> CatalogEntry {
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

    #[test]
    fn not_installed_null_sentinel_null_installed() {
        assert_eq!(classify(&base_entry(), None, None), Status::NotInstalled);
    }

    #[test]
    fn not_installed_sentinel_present_installed_null() {
        // disk was cleaned: sentinel present but installed=null
        let s = sentinel("1.0.0", "curated", false);
        assert_eq!(
            classify(&base_entry(), Some(&s), None),
            Status::NotInstalled
        );
    }

    #[test]
    fn synced_sentinel_pinned_installed_all_equal() {
        let s = sentinel("1.0.0", "curated", false);
        assert_eq!(
            classify(&base_entry(), Some(&s), Some("1.0.0")),
            Status::Synced
        );
    }

    #[test]
    fn drift_undeclared_sentinel_ne_installed() {
        let s = sentinel("0.9.0", "curated", false);
        assert_eq!(
            classify(&base_entry(), Some(&s), Some("1.0.0")),
            Status::DriftUndeclared
        );
    }

    #[test]
    fn override_ahead_installed_gt_pinned_not_sticky() {
        let s = sentinel("1.1.0", "override", false);
        assert_eq!(
            classify(&base_entry(), Some(&s), Some("1.1.0")),
            Status::OverrideAhead
        );
    }

    #[test]
    fn override_behind_installed_lt_pinned_not_sticky() {
        let s = sentinel("0.9.0", "override", false);
        assert_eq!(
            classify(&base_entry(), Some(&s), Some("0.9.0")),
            Status::OverrideBehind
        );
    }

    #[test]
    fn pinned_override_sticky_installed_ne_pinned() {
        let s = sentinel("1.1.0", "pinned", true);
        assert_eq!(
            classify(&base_entry(), Some(&s), Some("1.1.0")),
            Status::PinnedOverride
        );
    }
}
