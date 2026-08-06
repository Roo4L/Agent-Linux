//! catalog.rs — the catalog loader adapter (I/O boundary).
//!
//! Reads `<catalog_dir>/catalog.json`
//! into a `Vec<FullCatalogEntry>` whose serde field names are byte-identical to
//! the field names catalog.json already uses, so the SAME catalog.json
//! deserializes with no migration. Hydrates each entry's `preserve_paths_file`
//! sibling and — the load-bearing security control — PORTS the
//! preserve_paths traversal reject: reject a non-`~/`-prefixed,
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
//! `AGENTLINUX_CATALOG_DIR` overrides the catalog dir — the bats
//! seam (`40-registry-cli.bats:598`). [`resolve_catalog_dir`] honors it; the
//! default mirrors `defaultCatalogDir` (`/opt/agentlinux/catalog/<version>`).

use serde::Deserialize;
use std::path::{Path, PathBuf};
use thiserror::Error;

/// The USER-FACING catalog version segment of the default catalog dir. Mirrors
/// `defaultCatalogDir`: normalized `$AGENTLINUX_VERSION` else
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
///  closely enough that a diagnostic printed to stderr is intelligible.
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
    /// The traversal-reject control. Message mirrors the loader.ts:33-63
    /// `throw new Error(...)` wording family (per-entry, indexed).
    #[error("{0}")]
    PreservePathsTraversal(String),
}

/// The full catalog entry the bin needs — field names byte-identical to the TS
/// `CatalogEntry` (`types.ts:7-49`) so the SAME catalog.json deserializes. The
/// pure `agentlinux-core::types::CatalogEntry` is a lean 7-field subset (the
/// contract); this is the bin-side FULL shape ("What is NOT yet in
/// agentlinux-core", item 1).
///
/// Optional fields carry `#[serde(default)]` so a partial entry (e.g. the
/// `test-dummy` fixture with no `compatibility_window`) still deserializes.
///
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

/// Find the entry `name` names, or print the standard not-found diagnostic and
/// return `None`.
///
/// Every verb that takes an agent name resolves it through here, so the wording
/// and the `available:` list cannot drift between verbs — `remove` used to omit
/// the `available:` line purely because it had its own copy of this lookup.
///
/// The `test_only` gate is deliberately NOT part of this: `install`/`adopt`
/// refuse a test-only entry without `--include-test`, while `remove`/`pin` must
/// accept one (you have to be able to remove what you installed). That is a real
/// per-verb difference, so it stays at the call sites that have it.
#[must_use]
///
/// The not-found diagnostic goes to `err` rather than straight to stderr: those
/// two lines are an acceptance contract the bats suite greps, and a verb that
/// prints them through its own sink can assert them.
pub fn find_entry<'a>(
    agents: &'a [FullCatalogEntry],
    name: &str,
    err: &mut dyn std::io::Write,
) -> Option<&'a FullCatalogEntry> {
    if let Some(entry) = agents.iter().find(|a| a.id == name) {
        return Some(entry);
    }
    let available = agents
        .iter()
        .filter(|a| !a.test_only)
        .map(|a| a.id.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    let _ = writeln!(err, "agentlinux: no such agent in catalog: {name}");
    let _ = writeln!(err, "  available: {available}");
    None
}

/// Project a loaded catalog entry down to the lean shape the pure core decides
/// over (`classify` / `derive_category` / the detect gates read exactly these
/// seven fields).
///
/// A plain struct literal, deliberately: adding a field to the core type makes
/// THIS impl a compile error, which is the whole point. An earlier version did
/// the same projection through a `serde_json` round-trip in six separate
/// modules — that turned a rename into a runtime `.expect()` panic in
/// production instead of a build failure, and cost a heap allocation per entry
/// per render.
impl From<&FullCatalogEntry> for agentlinux_core::types::CatalogEntry {
    fn from(e: &FullCatalogEntry) -> Self {
        Self {
            id: e.id.clone(),
            pinned_version: e.pinned_version.clone(),
            version_constraint: e.version_constraint.clone(),
            npm_package_name: e.npm_package_name.clone(),
            compatibility_window: e.compatibility_window.clone(),
            tags: e.tags.clone(),
            source_kind: e.source_kind.clone(),
        }
    }
}

/// The top-level catalog document (`{ version, agents }`).
#[derive(Debug, Clone, Deserialize)]
struct CatalogDoc {
    #[allow(dead_code)]
    version: String,
    agents: Vec<FullCatalogEntry>,
}

/// The `preserve_paths.json` sibling shape.
#[derive(Debug, Deserialize)]
struct PreservePathsFile {
    preserve_paths: Vec<String>,
    #[allow(dead_code)]
    comment: Option<String>,
}

/// Normalize + traversal-reject a single preserve path.
///
/// Strip a leading `~/`, drop a trailing slash, then reject an absolute or
/// `..`-containing normalized form. Returns the home-relative normalized string,
/// or a [`CatalogError::PreservePathsTraversal`] carrying the TS-shaped message.
/// This is a security control — a silently-dropped bad path would
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
/// `loadPreservePaths`.
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
/// guarantee. Mirrors the schema's required id +
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
/// each entry's preserve_paths. Port of `loadCatalog`.
///
/// `validate:true` runs the required-field presence check (mutation paths);
/// `validate:false` takes the hot path (`list`/`adopt`). preserve_paths
/// hydration runs on BOTH paths (a traversal-reject is a hard error regardless),
/// mirroring the TS sequential-await hydration loop.
/// Whether `load_catalog` runs the required-field presence check.
///
/// An enum rather than a `bool` because the two call sites mean different
/// things by it: a MUTATION path must fail fast on a stale or truncated catalog
/// snapshot before it starts changing the host, while a REPORT path would rather
/// render what it can. `load_catalog(dir, true)` said neither.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Validate {
    /// Mutation path (install/remove/upgrade/pin) — check required fields first.
    Required,
    /// Read-only path (list/adopt/detect) — skip the check; serde already
    /// rejects a structurally malformed entry.
    Skip,
}

pub fn load_catalog(
    catalog_dir: &Path,
    validate: Validate,
) -> Result<Vec<FullCatalogEntry>, CatalogError> {
    let catalog_path = catalog_dir.join("catalog.json");
    let raw = std::fs::read_to_string(&catalog_path).map_err(|source| CatalogError::Read {
        path: catalog_path.display().to_string(),
        source,
    })?;
    let doc: CatalogDoc = serde_json::from_str(&raw).map_err(CatalogError::Parse)?;
    let mut agents = doc.agents;

    if validate == Validate::Required {
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
        let agents = load_catalog(dir.path(), Validate::Skip).unwrap();
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
        let err = load_catalog(dir.path(), Validate::Required).unwrap_err();
        assert!(matches!(err, CatalogError::Validate(_)), "got {err:?}");
        // The same catalog loads on the hot path (validate:false).
        assert!(load_catalog(dir.path(), Validate::Skip).is_ok());
    }

    // preserve_paths traversal reject — the two malicious rows.

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
        let agents = load_catalog(dir.path(), Validate::Skip).unwrap();
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
        let err = load_catalog(dir.path(), Validate::Skip).unwrap_err();
        assert!(
            matches!(err, CatalogError::PreservePathsTraversal(_)),
            "got {err:?}"
        );
    }

    /// A preserve-paths sibling the entry DECLARES but that is not there gets
    /// its own diagnostic naming the entry and the file. Every other read error
    /// is a plain read failure carrying the OS error.
    ///
    /// Three mutants survived on that one match guard — forcing it true, false,
    /// and inverting the `==`. Each collapses the two diagnoses into one, so a
    /// permission or I/O fault is reported as "you forgot to ship this file",
    /// or a genuinely absent file is reported as an unexplained read error.
    #[test]
    fn a_missing_preserve_paths_sibling_is_diagnosed_apart_from_a_read_fault() {
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

        // Declared, absent → PreservePathsMissing, and it names both the entry
        // and the file so the operator knows what to ship.
        let err = load_catalog(dir.path(), Validate::Skip).unwrap_err();
        match &err {
            CatalogError::PreservePathsMissing { id, file, .. } => {
                assert_eq!(id, "claude-code");
                assert_eq!(file, "preserve_paths.json");
            }
            other => panic!("an absent sibling must be PreservePathsMissing, got {other:?}"),
        }

        // Present but unreadable as a file — a directory stands in for any
        // non-NotFound fault, and unlike a chmod it behaves the same for root,
        // which is how the Docker suite runs.
        fs::create_dir(agent_dir.join("preserve_paths.json")).unwrap();
        let err = load_catalog(dir.path(), Validate::Skip).unwrap_err();
        assert!(
            matches!(err, CatalogError::Read { .. }),
            "a non-NotFound fault must stay a read error, got {err:?}"
        );
    }

    /// The `available:` line is what an operator reads after a typo, and it must
    /// list the agents they can actually install — `delete !` survived, which
    /// inverts the filter into listing ONLY the hidden test fixtures.
    #[test]
    fn the_available_list_names_real_agents_and_hides_test_only_ones() {
        let dir = tempdir().unwrap();
        write_catalog(
            dir.path(),
            r#"{"version":"0.3.6","agents":[
                {"id":"claude-code","display_name":"C","description":"d","source_kind":"script",
                 "pinned_version":"2.1.98","install_recipe_path":"install.sh",
                 "uninstall_recipe_path":"uninstall.sh"},
                {"id":"test-dummy","display_name":"T","description":"d","source_kind":"script",
                 "pinned_version":"0.0.1","install_recipe_path":"install.sh",
                 "uninstall_recipe_path":"uninstall.sh","test_only":true}
            ]}"#,
        );
        let agents = load_catalog(dir.path(), Validate::Skip).unwrap();

        let mut err = Vec::new();
        assert!(
            find_entry(&agents, "nosuch", &mut err).is_none(),
            "an unknown id must not resolve"
        );
        let msg = String::from_utf8(err).unwrap();
        assert!(
            msg.contains("available: claude-code"),
            "the installable agent must be listed, got {msg:?}"
        );
        assert!(
            !msg.contains("test-dummy"),
            "a test_only agent must NOT be offered, got {msg:?}"
        );

        // And a test_only entry is still FINDABLE by name — remove/pin must be
        // able to reach what install refused to offer.
        let mut sink = Vec::new();
        assert!(
            find_entry(&agents, "test-dummy", &mut sink).is_some(),
            "hidden from the list is not the same as unreachable by name"
        );
    }

    #[test]
    fn resolve_catalog_dir_honors_env_seam() {
        // Under the env lock: five cmd/* modules point this same variable at a
        // TempDir while holding it, and cargo runs them as threads in ONE
        // process — an unlocked write here could repoint the catalog dir out
        // from under a test that is mid-`load_catalog`.
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_CATALOG_DIR", "/tmp/fixture-catalog");
        assert_eq!(resolve_catalog_dir(), PathBuf::from("/tmp/fixture-catalog"));

        // An EMPTY seam is not a directory. `replace match guard !v.is_empty()
        // with true` survived: with it, `AGENTLINUX_CATALOG_DIR=` resolves the
        // catalog to `PathBuf::from("")` — a relative lookup in the process's
        // cwd — instead of falling back to the staged /opt directory.
        env_scope.set("AGENTLINUX_CATALOG_DIR", "");
        assert_eq!(
            resolve_catalog_dir(),
            default_catalog_dir(),
            "an EMPTY seam must fall back to the default catalog dir"
        );

        env_scope.unset("AGENTLINUX_CATALOG_DIR");
        assert_eq!(
            resolve_catalog_dir(),
            default_catalog_dir(),
            "an unset seam must fall back to the default catalog dir"
        );
    }

    /// The default catalog dir is the OBS-05 contract: it must be the SAME
    /// string the provisioner staged at, which means the normalized version —
    /// a tag like `v0.4.0-rc1` staged at `/opt/agentlinux/catalog/0.4.0/` has to
    /// be found here too. `replace default_catalog_dir -> PathBuf with
    /// Default::default()` survived, and an empty path means every catalog
    /// lookup silently misses.
    #[test]
    fn the_default_catalog_dir_carries_the_normalized_version() {
        let mut env_scope = crate::test_support::EnvScope::new();

        env_scope.set("AGENTLINUX_VERSION", "v9.9.9-rc1");
        assert_eq!(
            default_catalog_dir(),
            PathBuf::from("/opt/agentlinux/catalog/9.9.9"),
            "the tag's `v` prefix and `-rc1` suffix must be normalized away, \
             so runtime looks where the provisioner staged"
        );

        // No env override: the compiled CLI-01 version, never an empty segment.
        env_scope.unset("AGENTLINUX_VERSION");
        assert_eq!(
            default_catalog_dir(),
            PathBuf::from(format!(
                "/opt/agentlinux/catalog/{}",
                env!("CARGO_PKG_VERSION")
            ))
        );
    }

    /// The SHIPPED catalog must load, and must satisfy the constraints
    /// `plugin/catalog/schema.json` encodes.
    ///
    /// This is the repo's only end-to-end check on the real `catalog.json`. The
    /// schemars drift-test in `agentlinux-core` compares committed schema bytes
    /// to generated bytes and never opens the catalog; the `jq` pre-commit hook
    /// checks required-field presence only. Without this test, a catalog entry
    /// with an unknown `source_kind`, a non-semver pin, or an `npm` entry missing
    /// its package name reaches a release unchallenged.
    #[test]
    fn shipped_catalog_satisfies_its_schema() {
        // CARGO_MANIFEST_DIR is rust/crates/agentlinux.
        let catalog_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../plugin/catalog");

        // Deserialization enforces the required fields and the preserve_paths
        // traversal reject; `validate: true` is the mutation-path setting.
        let entries =
            load_catalog(&catalog_dir, Validate::Required).expect("shipped catalog.json loads");
        assert!(!entries.is_empty(), "shipped catalog declares no agents");

        // The constraints serde cannot express, mirroring schema.json's enum,
        // pattern and allOf/if-then clauses.
        const SOURCE_KINDS: &[&str] = &["npm", "script", "binary", "mcp"];
        for e in &entries {
            let kind = e.source_kind.as_deref().unwrap_or_else(|| {
                panic!("{}: source_kind is required", e.id);
            });
            assert!(
                SOURCE_KINDS.contains(&kind),
                "{}: source_kind '{kind}' is not one of {SOURCE_KINDS:?}",
                e.id
            );
            assert!(
                agentlinux_core::semver_shim::valid(&e.pinned_version).is_some(),
                "{}: pinned_version '{}' is not valid semver",
                e.id,
                e.pinned_version
            );
            if kind == "npm" {
                assert!(
                    e.npm_package_name.is_some(),
                    "{}: source_kind=npm requires npm_package_name",
                    e.id
                );
            }
            if let Some(url) = e.endpoint_url.as_deref() {
                assert!(
                    url.starts_with("https://"),
                    "{}: endpoint_url must be https (got {url})",
                    e.id
                );
            }
        }
    }
}
