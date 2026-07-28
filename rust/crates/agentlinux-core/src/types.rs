//! Rust mirrors of the TS `plugin/cli/src/types.ts` shapes the pure core consumes.
//!
//! `CatalogEntry` and `Sentinel` are modelled as plain `#[derive(Deserialize)]`
//! structs. Only the fields the ported classify/divergence units actually read
//! are mirrored — the full catalog field set is Phase 55 scope. The catalog
//! schema (TEST-03) is NOT generated from these lean types: Plan 54-02 uses a
//! dedicated codegen-only struct in `schema_gen.rs` that carries the full field
//! set, so these core types stay minimal and free of schema-derive concerns.

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
    /// Category-derivation tags (`types.ts` `tags?: string[]`). `#[serde(default)]`
    /// so a partial JSON entry with no tags still deserializes (Assumption A3);
    /// the TS reads `entry.tags ?? []`, so an absent field is the empty list.
    #[serde(default)]
    pub tags: Vec<String>,
    /// `source_kind` union (`"npm"`/`"script"`/`"binary"`/`"mcp"`) — kept as a
    /// plain `Option<String>` (NOT an enum) so an unknown/absent kind deserializes
    /// cleanly; the detect gates only compare it to those string literals.
    /// `#[serde(default)]` so an entry without it still deserializes.
    #[serde(default)]
    pub source_kind: Option<String>,
}

/// Mirror of `DetectCacheAgent` (`plugin/cli/src/detect.ts:106-111`) — the
/// detect-cache record the pure detect gates decide over. Deserialize-only so the
/// Phase-56 cache adapter reads it directly. `status`/`version` stay plain
/// `String`: the deciders compare `status` to `"healthy"`/`"broken"` and pass
/// `version` to [`crate::semver_shim::valid`], so they are not modelled as enums.
#[derive(Debug, Clone, Deserialize)]
pub struct DetectedAgent {
    pub id: String,
    pub status: String,
    pub path: String,
    pub version: String,
}

/// The canonical category keys (`plugin/cli/src/catalog/category.ts:13-20`).
/// Serde-renamed to the TS kebab strings (`"coding-agent"`, `"mcp"`, …) so a
/// serialized `CategoryKey` is byte-identical to the TS `CategoryKey` union —
/// mirrors the [`Status`] enum convention.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum CategoryKey {
    CodingAgent,
    Assistant,
    Mcp,
    Devops,
    Workflow,
    Browser,
    Other,
}

/// Mirror of `Category` (`plugin/cli/src/catalog/category.ts:22-26`) — a category
/// key with its human label and display order. The `deriveCategory` logic and the
/// `CATEGORIES` / `TAG_PRECEDENCE` tables land in Plan 02's `category.rs`; this
/// struct only defines the shared shape wave-2 compiles against.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Category {
    pub key: CategoryKey,
    pub label: String,
    pub order: u32,
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

#[cfg(test)]
mod tests {
    use super::*;

    /// `CategoryKey` must serialize to the exact TS kebab strings so a serialized
    /// key is byte-identical to the TS `CategoryKey` union (category.ts:13-20).
    #[test]
    fn category_key_serializes_to_ts_kebab_strings() {
        let cases = [
            (CategoryKey::CodingAgent, "\"coding-agent\""),
            (CategoryKey::Assistant, "\"assistant\""),
            (CategoryKey::Mcp, "\"mcp\""),
            (CategoryKey::Devops, "\"devops\""),
            (CategoryKey::Workflow, "\"workflow\""),
            (CategoryKey::Browser, "\"browser\""),
            (CategoryKey::Other, "\"other\""),
        ];
        for (key, want) in cases {
            assert_eq!(serde_json::to_string(&key).unwrap(), want);
            // round-trips back to the same variant.
            let back: CategoryKey = serde_json::from_str(want).unwrap();
            assert_eq!(back, key);
        }
    }

    /// `Category` mirrors category.ts:22-26 `{ key, label, order }`.
    #[test]
    fn category_round_trips() {
        let cat = Category {
            key: CategoryKey::CodingAgent,
            label: "Coding agents".to_string(),
            order: 1,
        };
        let json = serde_json::to_string(&cat).unwrap();
        let back: Category = serde_json::from_str(&json).unwrap();
        assert_eq!(back, cat);
    }

    /// `DetectedAgent` deserializes the 4-field `DetectCacheAgent` record
    /// (detect.ts:106-111) directly.
    #[test]
    fn detected_agent_deserializes_cache_record() {
        let json = r#"{"id":"rtk","status":"healthy","path":"/home/agent/.local/bin/rtk","version":"v1.37.1"}"#;
        let agent: DetectedAgent = serde_json::from_str(json).unwrap();
        assert_eq!(agent.id, "rtk");
        assert_eq!(agent.status, "healthy");
        assert_eq!(agent.path, "/home/agent/.local/bin/rtk");
        assert_eq!(agent.version, "v1.37.1");
    }

    /// A partial `CatalogEntry` JSON with NO `tags`/`source_kind` still
    /// deserializes — `tags` defaults to `[]`, `source_kind` to `None`
    /// (Assumption A3; TS reads `tags ?? []`).
    #[test]
    fn catalog_entry_defaults_tags_and_source_kind_when_absent() {
        let json = r#"{"id":"foo","pinned_version":"1.0.0"}"#;
        let entry: CatalogEntry = serde_json::from_str(json).unwrap();
        assert!(entry.tags.is_empty());
        assert_eq!(entry.source_kind, None);
    }

    /// When present, `tags`/`source_kind` deserialize into the new fields.
    #[test]
    fn catalog_entry_reads_tags_and_source_kind_when_present() {
        let json = r#"{"id":"rtk","pinned_version":"1.0.0","tags":["token","workflow","devops"],"source_kind":"script"}"#;
        let entry: CatalogEntry = serde_json::from_str(json).unwrap();
        assert_eq!(entry.tags, vec!["token", "workflow", "devops"]);
        assert_eq!(entry.source_kind.as_deref(), Some("script"));
    }
}
