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

#[cfg(test)]
mod proptests {
    //! Property tests (TEST-01) over `classify` — invariants the 44 example
    //! rows cannot express: totality, determinism, and the sticky invariant.
    //!
    //! Generators are hand-written (dtolnay `semver` ships no proptest/Arbitrary
    //! support — RESEARCH §proptest Invariants). They are catalog-realistic:
    //! full-version strings plus the loose shapes (`v`-prefix, two-part partial)
    //! `parse_lenient` is contracted to accept, so P1's totality covers the
    //! malformed inputs a real `<bin> --version` can emit.
    use super::*;
    use crate::proptest_strategies::{loose_version_str, version_str};
    use proptest::prelude::*;

    /// A `CatalogEntry` whose `pinned_version` is a generated (possibly loose)
    /// version string. The classifier reads only `id` + `pinned_version`.
    fn entry_strategy() -> impl Strategy<Value = CatalogEntry> {
        loose_version_str().prop_map(|pinned| CatalogEntry {
            id: "foo".to_string(),
            pinned_version: pinned,
            version_constraint: None,
            npm_package_name: Some("foo".to_string()),
            compatibility_window: None,
        })
    }

    /// A `Sentinel` with a generated (loose) version and an arbitrary sticky flag.
    fn sentinel_strategy() -> impl Strategy<Value = Sentinel> {
        (loose_version_str(), any::<bool>()).prop_map(|(version, sticky)| Sentinel {
            id: "foo".to_string(),
            version,
            source: "curated".to_string(),
            sticky,
        })
    }

    proptest! {
        // P1a — classify is TOTAL: for any (entry, sentinel?, installed?) — including
        // loose/malformed version strings — classify returns a Status and never
        // panics. The `unwrap_or(false)` fallbacks (classify.rs:36,41,51) guarantee
        // this; the property proves it across the generated input space (T-53-01).
        #[test]
        fn p1_classify_is_total(
            entry in entry_strategy(),
            sentinel in proptest::option::of(sentinel_strategy()),
            installed in proptest::option::of(loose_version_str()),
        ) {
            // The call itself not panicking IS the totality assertion; capture the
            // verdict so the optimizer cannot elide the call.
            let status = classify(&entry, sentinel.as_ref(), installed.as_deref());
            let _ = status;
        }

        // P1b — classify is DETERMINISTIC: two calls on identical input agree.
        #[test]
        fn p1_classify_is_deterministic(
            entry in entry_strategy(),
            sentinel in proptest::option::of(sentinel_strategy()),
            installed in proptest::option::of(loose_version_str()),
        ) {
            let a = classify(&entry, sentinel.as_ref(), installed.as_deref());
            let b = classify(&entry, sentinel.as_ref(), installed.as_deref());
            prop_assert_eq!(a, b);
        }

        // P2 — sticky ⇒ status ∈ {Synced, PinnedOverride}.
        //
        // Scoped to the NON-DRIFT subspace (Pitfall 5): sticky is only consulted
        // at branch 4, AFTER the drift check (branch 2, sentinel.version != installed)
        // and the synced check (branch 3). A sticky sentinel whose version disagrees
        // with `installed` correctly classifies as DriftUndeclared — outside the
        // invariant's scope. We generate sentinel.version == installed (both drawn
        // from a single generated version) so the property lands where sticky is
        // actually reached, and use prop_assume to skip any degenerate parse.
        #[test]
        fn p2_sticky_implies_synced_or_pinned_override(
            entry in entry_strategy(),
            shared_version in version_str(),
        ) {
            let sentinel = Sentinel {
                id: "foo".to_string(),
                version: shared_version.clone(),
                source: "pinned".to_string(),
                sticky: true,
            };
            // Non-drift precondition: sentinel.version must equal installed under
            // the shim's own equality (they are the same string, so this holds for
            // any parseable version; prop_assume guards the pathological case).
            prop_assume!(semver_shim::eq(&sentinel.version, &shared_version).unwrap_or(false));

            let status = classify(&entry, Some(&sentinel), Some(&shared_version));
            prop_assert!(
                matches!(status, Status::Synced | Status::PinnedOverride),
                "sticky non-drift sentinel yielded {:?}, expected Synced or PinnedOverride",
                status
            );
        }
    }
}
