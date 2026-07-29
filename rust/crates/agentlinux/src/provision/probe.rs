//! provision/probe.rs — the DETECT-phase host readers that feed the pure gates.
//!
//! The Bash entrypoint runs `detect::run_once` (populating `DETECT_*` exports +
//! `/run/agentlinux-detect.json`) and `remediate::collect_all_decisions` then
//! consults `reuse::*_decision` over those exports to build `RESOLUTIONS[…]`
//! (remediate.sh:234-299). This module is the Rust analogue: thin readers that
//! answer "what is actually on this host" so `cmd/provision.rs` can call the
//! ALREADY-PORTED pure gates (`agentlinux_core::reuse::agent_decision` +
//! `detect_gates::*`) and assemble the `Resolutions` map.
//!
//! # The pure/I-O seam
//! Every reader here does I/O (fs / passwd DB / cache read). The DECISION stays
//! in the pure `agentlinux-core` gates — this module NEVER re-implements the
//! reuse/remediate logic, it only gathers inputs. Per-agent detect status comes
//! from the Phase-56 detect-cache adapter (`crate::cache`); absent cache → every
//! agent reads `absent` (→ Create), which is the fresh-install path the
//! provisioner runs on a clean host.
//!
//! # PROV-02 (57-06)
//! `cmd/provision.rs` iterates the Rust `canonical_path` map (main.rs) IN-PROCESS
//! and calls these readers + the pure gate per id — there is NO
//! `agentlinux reuse-decision` shell-out. The Rust map is the single authoritative
//! per-agent enumerator; the Bash `reuse/agents.sh` map is retained only as the
//! 13-reuse spec-contract shim + GATE-05 rollback fallback (plan-check B-1).

use crate::cache;
use agentlinux_core::types::DetectedAgent;

/// A per-agent detect reading — status + resolved path — sourced from the detect
/// cache. Absent from the cache → `absent` with an empty path (the fresh-install
/// default the Bash `${!var:-absent}` / `${!path_var:-}` produce).
#[derive(Debug, Clone)]
pub struct AgentProbe {
    pub status: String,
    pub path: String,
}

/// Read the detect status + path for a catalog id from the Phase-56 detect cache.
/// Absent cache or absent id → `status="absent"`, `path=""` — which
/// `agent_decision` maps to `Create` (the clean-host path).
#[must_use]
pub fn probe_agent(id: &str) -> AgentProbe {
    match cache::read_cached_agent_by_id(id) {
        Some(DetectedAgent { status, path, .. }) => AgentProbe { status, path },
        None => AgentProbe {
            status: "absent".to_string(),
            path: String::new(),
        },
    }
}

/// Whether a system user exists (passwd DB). Mirrors the Bash `id <user>` probe
/// that `reuse::user_decision` keys on. A lookup error is treated as "does not
/// exist" (a fresh host has no such user) — the conservative Create default.
#[must_use]
pub fn user_exists(name: &str) -> bool {
    matches!(nix::unistd::User::from_name(name), Ok(Some(_)))
}

#[cfg(test)]
mod probe_tests {
    use super::*;

    #[test]
    fn probe_agent_absent_when_no_cache() {
        let _g = crate::test_support::env_guard();
        std::env::set_var("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect-probe.json");
        let p = probe_agent("claude-code");
        assert_eq!(p.status, "absent");
        assert!(p.path.is_empty());
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn probe_agent_reads_cache_status_and_path() {
        let _g = crate::test_support::env_guard();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("detect.json");
        std::fs::write(
            &path,
            r#"{"agents":[{"id":"gsd","status":"healthy","path":"/home/agent/.claude/gsd-core/VERSION","version":"1.37.1"}]}"#,
        )
        .unwrap();
        std::env::set_var("AGENTLINUX_DETECT_CACHE", &path);

        let p = probe_agent("gsd");
        assert_eq!(p.status, "healthy");
        assert_eq!(p.path, "/home/agent/.claude/gsd-core/VERSION");

        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn user_exists_true_for_root_false_for_bogus() {
        assert!(user_exists("root"));
        assert!(!user_exists("nonexistent-user-xyz-9042"));
    }
}
