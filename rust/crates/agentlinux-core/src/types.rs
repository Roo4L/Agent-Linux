//! Rust mirrors of the TS `plugin/cli/src/types.ts` shapes the pure core consumes.
//!
//! `CatalogEntry` and `Sentinel` are modelled as plain `#[derive(Deserialize)]`
//! structs (not builder-wrapped) so Phase 54's `#[derive(JsonSchema)]` bolts on
//! without reshaping (RESEARCH §Phase-54-readiness). Only the fields the ported
//! classify/divergence units actually read are mirrored — the full catalog schema
//! is Phase 55 scope.

use serde::{Deserialize, Serialize};

/// Mirror of the subset of `CatalogEntry` (`plugin/cli/src/types.ts`) that the
/// pure classify/divergence units read. Optional fields default to `None` via
/// serde so a partial JSON entry still deserializes.
#[derive(Debug, Clone, Deserialize)]
pub struct CatalogEntry {
    pub id: String,
    /// Exact semver the catalog curates (CAT-04 / ADR-011).
    pub pinned_version: String,
    /// `--all-latest` upper-bound range (e.g. `^2.1`). Absent → resolve_latest_for
    /// defaults to `*`.
    #[serde(default)]
    pub version_constraint: Option<String>,
    /// Required when `source_kind == "npm"`; used only as the human label in the
    /// zero-match error message.
    #[serde(default)]
    pub npm_package_name: Option<String>,
    /// REUSE-03 semver range (adopt a detected install whose version satisfies it).
    #[serde(default)]
    pub compatibility_window: Option<String>,
}

/// Mirror of `Sentinel` (`plugin/cli/src/types.ts`) — the install-record shape at
/// `/opt/agentlinux/state/installed.d/<id>.json`. Only the fields classify/
/// divergence read are mirrored.
#[derive(Debug, Clone, Deserialize)]
pub struct Sentinel {
    pub id: String,
    pub version: String,
    pub source: String,
    pub sticky: bool,
}

/// The six-state divergence status. Serde-renamed to the TS kebab strings so a
/// serialized `Status` is byte-identical to the TS `Status` union.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Status {
    NotInstalled,
    Synced,
    DriftUndeclared,
    OverrideAhead,
    OverrideBehind,
    PinnedOverride,
}

/// Mirror of `DivergenceReport` (`plugin/cli/src/types.ts`) — the per-agent record
/// `agentlinux upgrade` reifies. Field names mirror the TS shape (camelCase in the
/// TS JSON) via serde renames; `source: "none"` is the sentinel-less fallback.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DivergenceReport {
    pub id: String,
    pub status: Status,
    #[serde(rename = "sentinelVersion")]
    pub sentinel_version: Option<String>,
    #[serde(rename = "installedVersion")]
    pub installed_version: Option<String>,
    #[serde(rename = "curatedVersion")]
    pub curated_version: String,
    #[serde(rename = "latestVersion")]
    pub latest_version: Option<String>,
    pub source: String,
    pub sticky: bool,
}
