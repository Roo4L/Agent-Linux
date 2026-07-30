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

/// `remediate::user_adoptable` port (`plugin/lib/remediate.sh:109-126`). The
/// runtime adoption-safety gate: if the name does NOT exist, returns `true` (it
/// will be created fresh / a purge no-op is idempotent). If it DOES exist,
/// returns `true` only when its UID >= 1000 (a regular login account); an
/// EXISTING system account (UID < 1000) returns `false` so the caller refuses to
/// grant it NOPASSWD sudo + overwrite its home (H-1), and — on the purge path —
/// so `userdel -r` can never remove a system/daemon account. Reads the passwd DB
/// — NOT pure; call it at runtime (after require_root), never during DECIDE.
#[must_use]
pub fn user_adoptable(name: &str) -> bool {
    match nix::unistd::User::from_name(name) {
        // Non-existent (or lookup error) → safe to create / idempotent purge.
        Ok(None) | Err(_) => true,
        // Exists: adoptable only when it is a regular login (UID >= 1000).
        Ok(Some(u)) => u.uid.as_raw() >= 1000,
    }
}

/// The REUSE-01 compatibility state of an existing install user. The Bash
/// `reuse::user_decision` checks five predicates; the irreconcilable one this
/// provisioner surfaces is the SHELL (a wrong-shell existing user cannot be
/// adopted — no chsh handler), which bails. Present + a bash login shell → Reuse
/// (re-attach path wiring / [REMEDIATE-02]); absent → Create.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserState {
    /// No such user — fresh CREATE (useradd).
    Absent,
    /// Exists with a bash login shell — REUSE.
    Conforming,
    /// Exists but with a non-bash shell — irreconcilable, BAIL.
    WrongShell,
}

/// Probe an existing install user's shell compatibility (REUSE-01 predicate 2).
/// Absent → `Absent`; shell ∈ {`/bin/bash`, `/usr/bin/bash`} → `Conforming`; any
/// other shell → `WrongShell`. Reads the passwd DB. I/O.
#[must_use]
pub fn user_state(user: &str) -> UserState {
    match nix::unistd::User::from_name(user) {
        Ok(Some(u)) => {
            let shell = u.shell.to_string_lossy();
            if shell == "/bin/bash" || shell == "/usr/bin/bash" {
                UserState::Conforming
            } else {
                UserState::WrongShell
            }
        }
        _ => UserState::Absent,
    }
}

/// The on-host state of `/etc/sudoers.d/agentlinux`, feeding the REMEDIATE-03
/// decision. Mirrors the Bash `DETECT_SUDOERS_PRESENT` / `DETECT_SUDOERS_NOPASSWD_OK`
/// exports (`detect/sudoers.sh`): the canonical file carries the exact
/// `<user> ALL=(ALL) NOPASSWD: ALL` line (ADR-012); a present-but-drifted file
/// (e.g. a narrow package-scoped NOPASSWD) lacks it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SudoersState {
    /// No drop-in — fresh CREATE.
    Absent,
    /// Present with the canonical ADR-012 NOPASSWD line — REUSE (no-op).
    Canonical,
    /// Present but WITHOUT the canonical line — a state-overwriting REMEDIATE.
    Drifted,
}

/// Probe `/etc/sudoers.d/agentlinux`. Absent file → `Absent`; a file containing
/// the exact canonical `<user> ALL=(ALL) NOPASSWD: ALL` line → `Canonical`; a
/// present file lacking it → `Drifted`. I/O — call at runtime (post require_root),
/// never during a pure test.
#[must_use]
pub fn sudoers_state(user: &str) -> SudoersState {
    match std::fs::read_to_string("/etc/sudoers.d/agentlinux") {
        Err(_) => SudoersState::Absent,
        Ok(content) => {
            let canonical = format!("{user} ALL=(ALL) NOPASSWD: ALL");
            if content.lines().any(|l| l.trim() == canonical) {
                SudoersState::Canonical
            } else {
                SudoersState::Drifted
            }
        }
    }
}

/// The on-host state of the install user's npm-global prefix, feeding the
/// REMEDIATE-01 decision. Mirrors `reuse::npm_prefix_decision`: absent → create;
/// present-and-owned-by-the-install-user → reuse; present-but-wrong-owner → a
/// state-overwriting remediate (chown or rebase, chosen by the ACT `strategy_for`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NpmPrefixState {
    /// `<home>/.npm-global` does not exist — fresh CREATE (30-nodejs makes it).
    Absent,
    /// Exists and is owned by the install user — REUSE.
    OwnedByUser,
    /// Exists but owned by someone else (e.g. root) — brownfield REMEDIATE.
    WrongOwner,
}

/// The EFFECTIVE npm prefix for the install user: the `prefix=<path>` line in
/// `<home>/.npmrc` if present, else the canonical `<home>/.npm-global`. Mirrors the
/// Bash `DETECT_NPM_PREFIX_PATH` — a brownfield host may point npm at a foreign
/// prefix (e.g. a root-owned `/usr/local/...`) via `.npmrc`, which the REMEDIATE-01
/// rebase arm migrates away from.
#[must_use]
pub fn effective_npm_prefix(home: &str) -> String {
    let default = format!("{home}/.npm-global");
    match std::fs::read_to_string(format!("{home}/.npmrc")) {
        Ok(content) => content
            .lines()
            .filter_map(|l| l.split_once('='))
            .find(|(k, _)| k.trim() == "prefix")
            .map(|(_, v)| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or(default),
        Err(_) => default,
    }
}

/// Probe the install user's EFFECTIVE npm prefix ownership + location. Absent →
/// `Absent` (30-nodejs creates the canonical one); present, owned by the install
/// user AND under home → `OwnedByUser` (Reuse); present but wrong-owner OR off-home
/// → `WrongOwner` (a REMEDIATE-01 chown-or-rebase, strategy chosen by the ACT).
/// Uses `symlink_metadata` (no deref) + the passwd DB. I/O.
#[must_use]
pub fn npm_prefix_state(user: &str, home: &str) -> NpmPrefixState {
    use std::os::unix::fs::MetadataExt;
    let prefix = effective_npm_prefix(home);
    let md = match std::fs::symlink_metadata(&prefix) {
        Err(_) => return NpmPrefixState::Absent,
        Ok(md) => md,
    };
    let under_home = prefix.starts_with(&format!("{home}/"));
    let owned =
        matches!(nix::unistd::User::from_name(user), Ok(Some(u)) if u.uid.as_raw() == md.uid());
    if owned && under_home {
        NpmPrefixState::OwnedByUser
    } else {
        NpmPrefixState::WrongOwner
    }
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

    #[test]
    fn user_adoptable_refuses_existing_system_account() {
        // root is UID 0 (< 1000) and always exists → refuse (H-1). This is the
        // literal case run_purge must NOT feed to `userdel -r`.
        assert!(!user_adoptable("root"));
        // daemon is a UID<1000 system account present on every Linux host.
        assert!(!user_adoptable("daemon"));
    }

    #[test]
    fn user_adoptable_allows_nonexistent_and_regular_login() {
        // A non-existent name is fine: create-fresh / idempotent purge no-op.
        assert!(user_adoptable("nonexistent-user-xyz-9042"));
        // The build/CI account running this test is a regular login (UID>=1000);
        // resolve its own name and confirm it is adoptable.
        let self_uid = nix::unistd::Uid::current();
        if self_uid.as_raw() >= 1000 {
            if let Ok(Some(me)) = nix::unistd::User::from_uid(self_uid) {
                assert!(user_adoptable(&me.name));
            }
        }
    }
}
