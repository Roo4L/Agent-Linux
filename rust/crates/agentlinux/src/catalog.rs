//! catalog.rs — the catalog loader adapter (I/O boundary).
//!
//! Port of `plugin/cli/src/catalog/loader.ts`. Reads `<catalog_dir>/catalog.json`
//! into a `Vec<FullCatalogEntry>` whose serde field names are byte-identical to
//! the TS `CatalogEntry` (`plugin/cli/src/types.ts:7-49`) so the SAME catalog.json
//! deserializes with no migration. Hydrates each entry's `preserve_paths_file`
//! sibling and — the load-bearing security control (T-56-06) — PORTS the
//! preserve_paths traversal reject (loader.ts:31-65): reject a non-`~/`-prefixed,
//! absolute, or `..`-containing path so a tampered catalog cannot escape `~` on a
//! later REMEDIATE-04 uninstall delete.
//!
//! # `validate`
//! The TS runs ajv schema validation on the mutation paths (install/upgrade/pin)
//! and skips it on the hot path (`list`/`adopt`). This port mirrors the SHAPE of
//! that seam: `validate:true` runs a required-field presence check (id +
//! pinned_version + the two recipe paths — the schema's `required` core);
//! `validate:false` takes the hot path. serde already rejects a structurally
//! malformed entry; the presence check adds the "mutation path fails fast on a
//! stale/broken snapshot" guarantee pin.ts:90 relies on.
//!
//! # Env seam
//! `AGENTLINUX_CATALOG_DIR` overrides the catalog dir (loader.ts:101) — the bats
//! seam (`40-registry-cli.bats:598`). [`resolve_catalog_dir`] honors it; the
//! default mirrors `defaultCatalogDir` (`/opt/agentlinux/catalog/<version>`).
//!
//! `#![allow(dead_code)]`: the loader's public surface is consumed by the Wave-1
//! verb adapters (`cmd/{list,pin,adopt}.rs`, this plan's Tasks 2/3) and Plan 03's
//! mutating verbs. The `#[cfg(test)]` module exercises every item now, so nothing
//! is truly unreachable — the allow only silences the "not yet wired into a
//! non-test caller" lint at the Task-1 commit boundary (mirrors the Wave-0
//! recipe_env/dispatcher scaffold pattern).
#![allow(dead_code)]

use serde::Deserialize;
use std::path::{Path, PathBuf};
use thiserror::Error;

/// The USER-FACING catalog version segment of the default catalog dir. Mirrors
/// `defaultCatalogDir` (loader.ts:17-20): normalized `$AGENTLINUX_VERSION` else
/// the bin's `CARGO_PKG_VERSION` (the CLI-01 version, 0.4.0). MUST resolve to the
/// SAME string the provisioner staged at — so it shares the one normalized source
/// (`registry_cli::agentlinux_version`) rather than duplicating the env logic.
/// This is the runtime half of the OBS-05 fix: a tag like `v0.4.0-rc1` staged at
/// `/opt/agentlinux/catalog/0.4.0/` must be found here too.
fn default_catalog_dir() -> PathBuf {
    let ver = crate::provision::registry_cli::agentlinux_version();
    PathBuf::from(format!("/opt/agentlinux/catalog/{ver}"))
}

/// Resolve the catalog dir: `$AGENTLINUX_CATALOG_DIR` (the bats seam) else the
/// default `/opt/agentlinux/catalog/<version>`. Port of loader.ts:101.
#[must_use]
pub fn resolve_catalog_dir() -> PathBuf {
    match std::env::var("AGENTLINUX_CATALOG_DIR") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => default_catalog_dir(),
    }
}

/// Typed catalog-load error mirroring the TS `throw new Error(...)` messages
/// (loader.ts) closely enough that a diagnostic printed to stderr is intelligible.
#[derive(Debug, Error)]
pub enum CatalogError {
    #[error("agentlinux: catalog.json not found or unreadable at {path}: {source}")]
    Read {
        path: String,
        source: std::io::Error,
    },
    #[error("agentlinux: catalog.json is not valid JSON: {0}")]
    Parse(serde_json::Error),
    #[error("agentlinux: catalog validation failed: {0}")]
    Validate(String),
    #[error("agentlinux: preserve_paths_file '{file}' for agent '{id}' not found at {path}")]
    PreservePathsMissing {
        id: String,
        file: String,
        path: String,
    },
    #[error("agentlinux: preserve_paths.json for '{id}' is not valid JSON: {source}")]
    PreservePathsParse {
        id: String,
        source: serde_json::Error,
    },
    /// The traversal-reject control (T-56-06). Message mirrors the loader.ts:33-63
    /// `throw new Error(...)` wording family (per-entry, indexed).
    #[error("{0}")]
    PreservePathsTraversal(String),
}

/// The full catalog entry the bin needs — field names byte-identical to the TS
/// `CatalogEntry` (`types.ts:7-49`) so the SAME catalog.json deserializes. The
/// pure `agentlinux-core::types::CatalogEntry` is a lean 7-field subset (Phase-55
/// contract); this is the bin-side FULL shape (RESEARCH §"What is NOT yet in
/// agentlinux-core", item 1).
///
/// Optional fields carry `#[serde(default)]` so a partial entry (e.g. the
/// `test-dummy` fixture with no `compatibility_window`) still deserializes.
///
/// `#[allow(dead_code)]`: several fields (`homepage`, `license`,
/// `install_recipe_path`, `uninstall_recipe_path`, `rewire_recipe_path`,
/// `preserve_paths`, `requires_secret`, `secret_env`, `endpoint_url`,
/// `post_install_verify`) are read by the mutating verbs in Plan 03
/// (install/remove/upgrade build recipe paths + inject preserve_paths), not by
/// Wave-1's read-only list/adopt/pin. The FULL shape is deserialized now (the
/// catalog.json field set is fixed); the allow defers the "field not yet read by
/// a non-test caller" lint until Plan 03 wires the recipe dispatch.
#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct FullCatalogEntry {
    pub id: String,
    pub display_name: String,
    pub description: String,
    #[serde(default)]
    pub homepage: Option<String>,
    #[serde(default)]
    pub license: Option<String>,
    /// `"npm" | "script" | "binary" | "mcp"` — kept a plain `Option<String>` (not
    /// an enum) so an unknown/absent kind deserializes; the gates compare it to
    /// the literals. Absent for the `test-dummy` fixture.
    #[serde(default)]
    pub source_kind: Option<String>,
    #[serde(default)]
    pub npm_package_name: Option<String>,
    #[serde(default)]
    pub requires_secret: Option<bool>,
    #[serde(default)]
    pub secret_env: Option<String>,
    #[serde(default)]
    pub endpoint_url: Option<String>,
    pub pinned_version: String,
    #[serde(default)]
    pub version_constraint: Option<String>,
    #[serde(default)]
    pub compatibility_window: Option<String>,
    pub install_recipe_path: String,
    pub uninstall_recipe_path: String,
    #[serde(default)]
    pub rewire_recipe_path: Option<String>,
    #[serde(default)]
    pub post_install_verify: Option<String>,
    /// The sibling-file pointer (e.g. `"preserve_paths.json"`). When set,
    /// [`load_catalog`] hydrates `preserve_paths` from it.
    #[serde(default)]
    pub preserve_paths_file: Option<String>,
    /// Normalized home-relative list — empty/absent when no file. Populated by the
    /// loader (never deserialized directly from catalog.json).
    #[serde(default)]
    pub preserve_paths: Option<Vec<String>>,
    #[serde(default)]
    pub tags: Vec<String>,
    /// Hide from default `list` (CAT-02). Absent → `false`.
    #[serde(default)]
    pub test_only: bool,
}

/// The top-level catalog document (`{ version, agents }`). `catalogDir` (TS) is
/// tracked by the caller, not deserialized.
#[derive(Debug, Clone, Deserialize)]
struct CatalogDoc {
    #[allow(dead_code)]
    version: String,
    agents: Vec<FullCatalogEntry>,
}

/// The `preserve_paths.json` sibling shape (loader.ts:22-25).
#[derive(Debug, Deserialize)]
struct PreservePathsFile {
    preserve_paths: Vec<String>,
    #[allow(dead_code)]
    comment: Option<String>,
}

/// Normalize + traversal-reject a single preserve path (loader.ts:31-65).
///
/// Strip a leading `~/`, drop a trailing slash, then reject an absolute or
/// `..`-containing normalized form. Returns the home-relative normalized string,
/// or a [`CatalogError::PreservePathsTraversal`] carrying the TS-shaped message.
/// This is the T-56-06 security control — a silently-dropped bad path would
/// delete user data on REMEDIATE-04, so it fails fast.
fn normalize_preserve_path(raw: &str, agent_id: &str, idx: usize) -> Result<String, CatalogError> {
    if raw.is_empty() {
        return Err(CatalogError::PreservePathsTraversal(format!(
            "agentlinux: preserve_paths.json for '{agent_id}' entry [{idx}]: must be a non-empty string"
        )));
    }
    if !raw.starts_with("~/") {
        return Err(CatalogError::PreservePathsTraversal(format!(
            "agentlinux: preserve_paths.json for '{agent_id}' entry [{idx}]: must start with '~/' (got: {raw})"
        )));
    }
    // Strip leading `~/`, drop trailing slashes (uniform shape) — mirrors
    // `raw.slice(2).replace(/\/+$/, "")`.
    let stripped = raw[2..].trim_end_matches('/');
    if stripped.is_empty() {
        return Err(CatalogError::PreservePathsTraversal(format!(
            "agentlinux: preserve_paths.json for '{agent_id}' entry [{idx}]: empty after stripping '~/' (got: {raw})"
        )));
    }
    let normalized = normalize_path(stripped);
    // Reject an absolute-path leak (normalized starts with `/`).
    if normalized.starts_with('/') {
        return Err(CatalogError::PreservePathsTraversal(format!(
            "agentlinux: preserve_paths.json for '{agent_id}' entry [{idx}]: absolute paths forbidden (got: {raw}; normalized: {normalized})"
        )));
    }
    // Reject any `..` segment — a malicious catalog could otherwise escape ~/.
    if normalized.split('/').any(|s| s == "..") {
        return Err(CatalogError::PreservePathsTraversal(format!(
            "agentlinux: preserve_paths.json for '{agent_id}' entry [{idx}]: '..' traversal forbidden (got: {raw}; normalized: {normalized})"
        )));
    }
    Ok(normalized)
}

/// Collapse `.`/`a/../b` the way Node's `path.normalize` does for a RELATIVE
/// POSIX path, PRESERVING leading `..` segments (so `../x` stays `../x` and is
/// then rejected). Does NOT resolve symlinks or touch the filesystem — this is a
/// pure lexical normalization matching the TS `normalize()` semantics the
/// traversal check relies on.
fn normalize_path(input: &str) -> String {
    let mut out: Vec<&str> = Vec::new();
    let absolute = input.starts_with('/');
    for seg in input.split('/') {
        match seg {
            "" | "." => {} // skip empty (collapsed slash) + current-dir segments
            ".." => {
                // Pop a real segment; otherwise keep the `..` (leading, or after
                // another `..`) so an escape attempt survives to the reject below.
                if matches!(out.last(), Some(&last) if last != "..") {
                    out.pop();
                } else if !absolute {
                    out.push("..");
                }
                // For an absolute path a leading `..` is dropped (Node behavior),
                // but preserve_paths are `~/`-relative so this branch is unused.
            }
            other => out.push(other),
        }
    }
    let joined = out.join("/");
    if absolute {
        format!("/{joined}")
    } else if joined.is_empty() {
        // Node normalize("") === "." ; an all-collapsing relative path → ".".
        ".".to_string()
    } else {
        joined
    }
}

/// Read the `preserve_paths_file` sibling for `entry` and normalize its paths.
/// Returns `None` when the entry has no `preserve_paths_file`. Port of
/// `loadPreservePaths` (loader.ts:67-98).
fn load_preserve_paths(
    catalog_dir: &Path,
    entry: &FullCatalogEntry,
) -> Result<Option<Vec<String>>, CatalogError> {
    let Some(file) = entry.preserve_paths_file.as_deref() else {
        return Ok(None);
    };
    let path = catalog_dir.join("agents").join(&entry.id).join(file);
    let body = match std::fs::read_to_string(&path) {
        Ok(b) => b,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Err(CatalogError::PreservePathsMissing {
                id: entry.id.clone(),
                file: file.to_string(),
                path: path.display().to_string(),
            });
        }
        Err(e) => {
            return Err(CatalogError::Read {
                path: path.display().to_string(),
                source: e,
            });
        }
    };
    let parsed: PreservePathsFile =
        serde_json::from_str(&body).map_err(|source| CatalogError::PreservePathsParse {
            id: entry.id.clone(),
            source,
        })?;
    let normalized = parsed
        .preserve_paths
        .iter()
        .enumerate()
        .map(|(i, p)| normalize_preserve_path(p, &entry.id, i))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Some(normalized))
}

/// Minimal required-field presence check (the ajv `required` core) run on the
/// mutation paths (`validate:true`). serde already rejects a structurally
/// malformed entry; this adds the "reject a stale/broken snapshot up front"
/// guarantee (loader.ts:105-110). Mirrors the schema's required id +
/// pinned_version + install/uninstall recipe paths.
fn validate_entries(agents: &[FullCatalogEntry]) -> Result<(), CatalogError> {
    for (i, e) in agents.iter().enumerate() {
        let missing = if e.id.is_empty() {
            Some("id")
        } else if e.pinned_version.is_empty() {
            Some("pinned_version")
        } else if e.install_recipe_path.is_empty() {
            Some("install_recipe_path")
        } else if e.uninstall_recipe_path.is_empty() {
            Some("uninstall_recipe_path")
        } else {
            None
        };
        if let Some(field) = missing {
            return Err(CatalogError::Validate(format!(
                "agent [{i}] ('{}') missing required '{field}'",
                e.id
            )));
        }
    }
    Ok(())
}

/// Load `<catalog_dir>/catalog.json` into a `Vec<FullCatalogEntry>`, hydrating
/// each entry's preserve_paths. Port of `loadCatalog` (loader.ts:100-122).
///
/// `validate:true` runs the required-field presence check (mutation paths);
/// `validate:false` takes the hot path (`list`/`adopt`). preserve_paths
/// hydration runs on BOTH paths (a traversal-reject is a hard error regardless),
/// mirroring the TS sequential-await hydration loop.
pub fn load_catalog(
    catalog_dir: &Path,
    validate: bool,
) -> Result<Vec<FullCatalogEntry>, CatalogError> {
    let catalog_path = catalog_dir.join("catalog.json");
    let raw = std::fs::read_to_string(&catalog_path).map_err(|source| CatalogError::Read {
        path: catalog_path.display().to_string(),
        source,
    })?;
    let doc: CatalogDoc = serde_json::from_str(&raw).map_err(CatalogError::Parse)?;
    let mut agents = doc.agents;

    if validate {
        validate_entries(&agents)?;
    }

    // Hydrate preserve_paths siblings (sequential — deterministic, agent-ordered
    // error reporting, mirroring loader.ts:113-119).
    for entry in &mut agents {
        if let Some(paths) = load_preserve_paths(catalog_dir, entry)? {
            entry.preserve_paths = Some(paths);
        }
    }

    Ok(agents)
}

#[cfg(test)]
mod catalog_tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn write_catalog(dir: &Path, body: &str) {
        fs::write(dir.join("catalog.json"), body).unwrap();
    }

    #[test]
    fn loads_the_real_shape_and_defaults_optional_fields() {
        let dir = tempdir().unwrap();
        write_catalog(
            dir.path(),
            r#"{"version":"0.3.6","agents":[
                {"id":"test-dummy","display_name":"Test","description":"d",
                 "pinned_version":"0.0.1","install_recipe_path":"install.sh",
                 "uninstall_recipe_path":"uninstall.sh","test_only":true,"tags":["test-only"]}
            ]}"#,
        );
        let agents = load_catalog(dir.path(), false).unwrap();
        assert_eq!(agents.len(), 1);
        let e = &agents[0];
        assert_eq!(e.id, "test-dummy");
        assert!(e.test_only);
        assert_eq!(e.source_kind, None);
        assert_eq!(e.compatibility_window, None);
        assert!(e.preserve_paths.is_none());
    }

    #[test]
    fn validate_true_rejects_missing_required_field() {
        let dir = tempdir().unwrap();
        // pinned_version present but install_recipe_path empty → validation fails.
        write_catalog(
            dir.path(),
            r#"{"version":"0.3.6","agents":[
                {"id":"x","display_name":"X","description":"d","pinned_version":"1.0.0",
                 "install_recipe_path":"","uninstall_recipe_path":"uninstall.sh"}
            ]}"#,
        );
        let err = load_catalog(dir.path(), true).unwrap_err();
        assert!(matches!(err, CatalogError::Validate(_)), "got {err:?}");
        // The same catalog loads on the hot path (validate:false).
        assert!(load_catalog(dir.path(), false).is_ok());
    }

    // T-56-06: preserve_paths traversal reject — the two malicious rows.

    #[test]
    fn preserve_paths_reject_absolute() {
        // normalize("/etc/passwd" stripped from "~//etc/passwd") → absolute leak.
        let err = normalize_preserve_path("~//etc/passwd", "evil", 0).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("absolute paths forbidden"), "got: {msg}");
    }

    #[test]
    fn preserve_paths_reject_dotdot_traversal() {
        let err = normalize_preserve_path("~/../../root/.ssh", "evil", 1).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("'..' traversal forbidden"), "got: {msg}");
    }

    #[test]
    fn preserve_paths_must_start_with_tilde_slash() {
        let err = normalize_preserve_path(".config/x", "evil", 0).unwrap_err();
        assert!(err.to_string().contains("must start with '~/'"));
    }

    #[test]
    fn preserve_paths_accepts_and_normalizes_a_safe_path() {
        // `~/.config/./app/` → `.config/app` (collapsed `.` + trailing slash).
        assert_eq!(
            normalize_preserve_path("~/.config/./app/", "good", 0).unwrap(),
            ".config/app"
        );
    }

    #[test]
    fn hydrates_preserve_paths_sibling_and_rejects_a_bad_one() {
        let dir = tempdir().unwrap();
        write_catalog(
            dir.path(),
            r#"{"version":"0.3.6","agents":[
                {"id":"claude-code","display_name":"C","description":"d","source_kind":"script",
                 "pinned_version":"2.1.98","install_recipe_path":"install.sh",
                 "uninstall_recipe_path":"uninstall.sh","preserve_paths_file":"preserve_paths.json"}
            ]}"#,
        );
        let agent_dir = dir.path().join("agents").join("claude-code");
        fs::create_dir_all(&agent_dir).unwrap();

        // A safe sibling hydrates.
        fs::write(
            agent_dir.join("preserve_paths.json"),
            r#"{"preserve_paths":["~/.claude/","~/.config/claude"]}"#,
        )
        .unwrap();
        let agents = load_catalog(dir.path(), false).unwrap();
        assert_eq!(
            agents[0].preserve_paths.as_deref(),
            Some(&[".claude".to_string(), ".config/claude".to_string()][..])
        );

        // A malicious sibling fails the whole load (fail-fast).
        fs::write(
            agent_dir.join("preserve_paths.json"),
            r#"{"preserve_paths":["~/../../etc"]}"#,
        )
        .unwrap();
        let err = load_catalog(dir.path(), false).unwrap_err();
        assert!(
            matches!(err, CatalogError::PreservePathsTraversal(_)),
            "got {err:?}"
        );
    }

    #[test]
    fn resolve_catalog_dir_honors_env_seam() {
        std::env::set_var("AGENTLINUX_CATALOG_DIR", "/tmp/fixture-catalog");
        assert_eq!(resolve_catalog_dir(), PathBuf::from("/tmp/fixture-catalog"));
        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
    }
}
