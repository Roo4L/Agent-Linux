//! cache.rs — the detect-cache read adapter.
//!
//! The detect-cache reader. Resolves the cache path
//! (`$AGENTLINUX_DETECT_CACHE` else `/run/agentlinux-detect.json`), parses it
//! (accepting BOTH the on-disk top-level `.agents` shape from `detect::run_once`
//! AND the `--report-only` `.components.agents` wrapped shape), and hands records
//! to the already-ported pure gates (`reuse_gate`/`remediate_gate`/`presence_gate`
//! in `agentlinux_core::detect_gates`).
//!
//! # The pure/I-O seam
//! This adapter READS. The DECISION lives in the pure gates. The host `statSync`
//! re-validation that `tryReuse` does AFTER its pure gate passes
//! stays in the CALLING VERB's adapter (`cmd/adopt.rs`), NOT here and NOT in the
//! pure gate — mirroring Cache-Read Adapter. So `grep metadata|is_file`
//! over this file finds nothing.
//!
//! Records deserialize into `agentlinux_core::types::DetectedAgent` (the 4-field
//! `DetectCacheAgent`, already ported: id/status/path/version).
//!
//! # Env seam
//! `AGENTLINUX_DETECT_CACHE` is the bats seam
//! (`40-registry-cli.bats:183`). [`detect_cache_path`] honors it. `None` is
//! returned on absent/unparseable cache (the callers treat that as "no
//! candidate"), never an error.

use agentlinux_core::types::DetectedAgent;
use serde::Deserialize;
use std::path::PathBuf;

const DEFAULT_CACHE_PATH: &str = "/run/agentlinux-detect.json";

/// The two accepted cache shapes: top-level `.agents` OR `.components.agents`.
/// Both fields are optional; the reader prefers `.agents`, falling back to
/// `.components.agents` (mirrors `cache.agents ?? cache.components?.agents`,
/// detect.ts:138).
#[derive(Debug, Deserialize)]
struct CacheDoc {
    #[serde(default)]
    agents: Option<Vec<DetectedAgent>>,
    #[serde(default)]
    components: Option<Components>,
}

#[derive(Debug, Deserialize)]
struct Components {
    #[serde(default)]
    agents: Option<Vec<DetectedAgent>>,
}

/// Resolve the detect-cache path: `$AGENTLINUX_DETECT_CACHE` (bats seam) else
/// `/run/agentlinux-detect.json`. Port of `detectCachePath`.
#[must_use]
pub fn detect_cache_path() -> PathBuf {
    match std::env::var("AGENTLINUX_DETECT_CACHE") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(DEFAULT_CACHE_PATH),
    }
}

/// Read + parse the detect cache into the agents list, or `None` on
/// absent/unparseable. Accepts BOTH `.agents` and `.components.agents` shapes.
/// Port of `readCacheAgents`.
#[must_use]
pub fn read_cache_agents() -> Option<Vec<DetectedAgent>> {
    let path = detect_cache_path();
    // existsSync guard: absent cache → None (not an error).
    let body = std::fs::read_to_string(&path).ok()?;
    // Unparseable → None (mirrors the TS try/catch returning null).
    let doc: CacheDoc = serde_json::from_str(&body).ok()?;
    doc.agents.or_else(|| doc.components.and_then(|c| c.agents))
}

/// Find a cached agent by id — NO canonical requirement, because the list
/// presence overlay surfaces every detected catalog tool, not only the three
/// with a canonical path. Callers that DO need the canonical gate (install's
/// reuse/remediate decisions) pair this with `canonical_path(id)` themselves.
#[must_use]
pub fn read_cached_agent_by_id(id: &str) -> Option<DetectedAgent> {
    read_cache_agents()?.into_iter().find(|a| a.id == id)
}

#[cfg(test)]
mod cache_tests {
    use super::*;
    use tempfile::tempdir;

    /// Point the detect-cache read at a fixture holding `body`. The returned
    /// TempDir must stay alive for the duration of the test.
    fn with_cache(env_scope: &mut crate::test_support::EnvScope, body: &str) -> tempfile::TempDir {
        let dir = tempdir().unwrap();
        let path = dir.path().join("detect.json");
        std::fs::write(&path, body).unwrap();
        env_scope.set("AGENTLINUX_DETECT_CACHE", &path);
        dir
    }

    /// `AGENTLINUX_DETECT_CACHE` is the bats seam, but an EMPTY value is not a
    /// path — it must fall back, not resolve to `PathBuf::from("")`.
    /// `replace match guard !v.is_empty() with true` survived: with it, an empty
    /// or blanked-out seam silently redirects every cache read and write to the
    /// current working directory instead of `/run`.
    #[test]
    fn an_empty_cache_seam_falls_back_instead_of_resolving_to_nothing() {
        let mut env_scope = crate::test_support::EnvScope::new();

        env_scope.set("AGENTLINUX_DETECT_CACHE", "/tmp/somewhere-else.json");
        assert_eq!(
            detect_cache_path(),
            std::path::PathBuf::from("/tmp/somewhere-else.json"),
            "a non-empty seam must be honoured"
        );

        env_scope.set("AGENTLINUX_DETECT_CACHE", "");
        assert_eq!(
            detect_cache_path(),
            std::path::PathBuf::from(DEFAULT_CACHE_PATH),
            "an EMPTY seam must fall back to the default, not to an empty path"
        );

        env_scope.unset("AGENTLINUX_DETECT_CACHE");
        assert_eq!(
            detect_cache_path(),
            std::path::PathBuf::from(DEFAULT_CACHE_PATH),
            "an unset seam must fall back to the default"
        );
    }

    #[test]
    fn parses_top_level_agents_shape() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let _dir = with_cache(
            &mut env_scope,
            r#"{"agents":[{"id":"rtk","status":"healthy","path":"/home/agent/.local/bin/rtk","version":"0.42.4"}]}"#,
        );
        let agents = read_cache_agents().unwrap();
        assert_eq!(agents.len(), 1);
        assert_eq!(agents[0].id, "rtk");
    }

    #[test]
    fn parses_components_agents_wrapped_shape() {
        let mut env_scope = crate::test_support::EnvScope::new();
        // This is the exact shape the bats tests write (40-registry-cli.bats:180).
        let _dir = with_cache(
            &mut env_scope,
            r#"{"components":{"agents":[{"id":"gsd","status":"healthy","path":"/home/agent/.claude/gsd-core/VERSION","version":"1.37.1"}]}}"#,
        );
        let hit = read_cached_agent_by_id("gsd").unwrap();
        assert_eq!(hit.id, "gsd");
        assert_eq!(hit.path, "/home/agent/.claude/gsd-core/VERSION");
    }

    #[test]
    fn detect_cache_path_honors_env_override() {
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/tmp/custom-detect.json");
        assert_eq!(
            detect_cache_path(),
            PathBuf::from("/tmp/custom-detect.json")
        );
        env_scope.unset("AGENTLINUX_DETECT_CACHE");
        // Default when unset.
        assert_eq!(detect_cache_path(), PathBuf::from(DEFAULT_CACHE_PATH));
    }

    #[test]
    fn null_on_absent_cache() {
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect-xyz.json");
        assert!(read_cache_agents().is_none());
        assert!(read_cached_agent_by_id("gsd").is_none());
    }

    #[test]
    fn null_on_unparseable_cache() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let _dir = with_cache(&mut env_scope, "{not valid json");
        assert!(read_cache_agents().is_none());
    }
}
