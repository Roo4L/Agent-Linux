//! probe.rs — the runtime "what's actually on disk" installed-version probe.
//!
//! For an npm-source entry, reads the installed package's `package.json` under
//! the agent npm prefix and returns its normalized `version` field — a plain file
//! read, no child process, no network. Non-npm kinds (binary/script/mcp) and any
//! absent/unreadable/!semver package.json return `None`, and callers fall back to
//! the sentinel version.
//!
//! Consumed by `cmd::list`, which overlays the real on-disk version onto the
//! recorded sentinel version so a self-updated agent reads as drifted.
//!
//! # Env seam
//! The npm prefix is `$NPM_CONFIG_PREFIX` when set, else the configured install
//! user's `~/.npm-global` (via `recipe_env`). Resolved lazily on each call so a
//! test that sets `NPM_CONFIG_PREFIX` still takes effect.
//!
//! # The pure/I-O seam
//! This adapter READS. The semver normalization routes through the pure
//! `agentlinux_core::semver_shim::valid` (which drops a leading `v`/whitespace and
//! rejects a non-semver value), never `semver::` directly — so the core crate
//! stays pure and this file owns only the fs read.

use crate::catalog::FullCatalogEntry;
use crate::recipe_env;
use agentlinux_core::semver_shim;
use serde::Deserialize;

/// Resolve the npm prefix lazily: `$NPM_CONFIG_PREFIX` else the install user's
/// `~/.npm-global` (the one spelling of that layout lives in `recipe_env`).
fn npm_prefix() -> String {
    match std::env::var("NPM_CONFIG_PREFIX") {
        Ok(v) if !v.is_empty() => v,
        _ => recipe_env::npm_prefix(&recipe_env::agent_home()),
    }
}

/// The `{ version }` shape we read out of the installed package.json — every other
/// field is ignored (`serde` drops unknown keys by default).
#[derive(Debug, Deserialize)]
struct PackageJson {
    version: Option<String>,
}

/// The actual on-disk version of an installed npm entry, or `None` when it can't
/// be determined cheaply — non-npm kind, no `npm_package_name`, package absent, or
/// an unreadable/!semver package.json. `None` is the "fall back to the sentinel
/// version" signal, never an error.
#[must_use]
pub fn probe_installed_version(entry: &FullCatalogEntry) -> Option<String> {
    // Only npm-source entries with a package name have a readable package.json.
    if entry.source_kind.as_deref() != Some("npm") {
        return None;
    }
    let pkg = entry.npm_package_name.as_deref()?;
    // Global npm layout: <prefix>/lib/node_modules/<pkg>/package.json. A scoped
    // name (@openai/codex) nests one extra dir; PathBuf::join splits `/` verbatim
    // so the scope + package become two path segments — exactly npm's on-disk shape.
    let pkg_json = std::path::Path::new(&npm_prefix())
        .join("lib")
        .join("node_modules")
        .join(pkg)
        .join("package.json");
    // Read + parse + normalize; any failure collapses to None .
    let body = std::fs::read_to_string(&pkg_json).ok()?;
    let parsed: PackageJson = serde_json::from_str(&body).ok()?;
    // semver.valid returns the CLEAN version or null.
    semver_shim::valid(&parsed.version?)
}

#[cfg(test)]
mod probe_tests {
    use super::*;
    use tempfile::tempdir;

    fn entry(id: &str, source_kind: &str, npm_package_name: Option<&str>) -> FullCatalogEntry {
        let mut json = serde_json::json!({
            "id": id,
            "display_name": "X",
            "description": "d",
            "source_kind": source_kind,
            "pinned_version": "1.0.0",
            "install_recipe_path": "install.sh",
            "uninstall_recipe_path": "uninstall.sh",
        });
        if let Some(n) = npm_package_name {
            json["npm_package_name"] = serde_json::json!(n);
        }
        serde_json::from_value(json).expect("fixture entry deserializes")
    }

    /// Stage `<prefix>/lib/node_modules/<pkg>/package.json` with the given body.
    fn stage_package_json(prefix: &std::path::Path, pkg: &str, body: &str) {
        let dir = prefix.join("lib").join("node_modules").join(pkg);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("package.json"), body).unwrap();
    }

    #[test]
    fn reads_installed_version_from_package_json() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let prefix = tempdir().unwrap();
        stage_package_json(
            prefix.path(),
            "@openai/codex",
            r#"{"name":"@openai/codex","version":"1.2.3"}"#,
        );
        env_scope.set("NPM_CONFIG_PREFIX", prefix.path());

        let e = entry("codex", "npm", Some("@openai/codex"));
        assert_eq!(probe_installed_version(&e).as_deref(), Some("1.2.3"));
    }

    #[test]
    fn normalizes_a_v_prefixed_version() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let prefix = tempdir().unwrap();
        stage_package_json(prefix.path(), "gsd-core", r#"{"version":"v1.37.1"}"#);
        env_scope.set("NPM_CONFIG_PREFIX", prefix.path());

        let e = entry("gsd", "npm", Some("gsd-core"));
        // semver.valid drops the leading `v`.
        assert_eq!(probe_installed_version(&e).as_deref(), Some("1.37.1"));
    }

    #[test]
    fn none_when_package_json_absent() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let prefix = tempdir().unwrap();
        env_scope.set("NPM_CONFIG_PREFIX", prefix.path());

        let e = entry("codex", "npm", Some("@openai/codex"));
        assert_eq!(probe_installed_version(&e), None);
    }

    #[test]
    fn none_for_non_npm_source_kind() {
        // A script-kind entry has no readable package.json — probe returns None
        // regardless of the prefix.
        let e = entry("claude-code", "script", None);
        assert_eq!(probe_installed_version(&e), None);
    }

    #[test]
    fn none_when_version_field_missing_or_not_semver() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let prefix = tempdir().unwrap();
        // Missing version field.
        stage_package_json(prefix.path(), "nover", r#"{"name":"nover"}"#);
        // Non-semver version string.
        stage_package_json(prefix.path(), "badver", r#"{"version":"not-a-version"}"#);
        env_scope.set("NPM_CONFIG_PREFIX", prefix.path());

        assert_eq!(
            probe_installed_version(&entry("a", "npm", Some("nover"))),
            None
        );
        assert_eq!(
            probe_installed_version(&entry("b", "npm", Some("badver"))),
            None
        );
    }
}
