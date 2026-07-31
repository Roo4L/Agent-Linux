//! rewire.rs — post-install cross-agent wiring reconcile (#4 / WIRE-02).
//!
//! A cross-agent
//! PROVIDER (rtk, a fan-out MCP server) wires itself into every coding agent
//! PRESENT AT ITS OWN INSTALL TIME. Without this reconcile, an agent installed
//! LATER stays un-wired, so the end state would depend on install order. After a
//! coding agent is installed, this re-runs each installed provider's lightweight,
//! idempotent, present-aware rewire recipe so it fans out into the new agent too.
//! Best-effort: a wiring hiccup NEVER fails the install that already succeeded.
//!
//! # DI seam
//! The dispatch goes through an injectable `RecipeDispatcher` matching the
//! buffered `dispatch_recipe` shape (a rewire runs buffered — it isn't the long
//! interactive install path). Tests inject a capturing/stubbing dispatcher so no
//! sudo invocation happens under `cargo test`.

use crate::catalog::FullCatalogEntry;
use crate::dispatcher::{self, Capture, RecipeDispatcher};
use crate::recipe_env::{full_child_env, RecipeEnv};
use crate::sentinel;
use std::collections::HashSet;

/// The coding agents that RECEIVE cross-agent wiring (rtk hooks, MCP servers).
/// Installing one of these triggers the reconcile; installing anything else (a
/// provider, a devops CLI) does not — the provider's own install.sh already
/// fanned out into whatever was present. Mirrors rewire.ts:22-28 + the target
/// sets in lib/rtk-wire.sh and lib/mcp-register.sh.
const WIREABLE_AGENTS: &[&str] = &[
    "claude-code",
    "codex",
    "antigravity-cli",
    "opencode",
    "qwen-code",
];

/// Re-run each installed provider's rewire recipe so it fans out into the
/// freshly-installed `installed_id`. Best-effort — never returns an error; a
/// wiring hiccup is logged and the install stays OK.
///
/// `user` is the resolved install user, `catalog_dir` the catalog root; the
/// providers are the installed entries (per the sentinel list) that declare a
/// `rewire_recipe_path`, excluding `installed_id` itself.
pub fn reconcile_cross_wiring(
    installed_id: &str,
    agents: &[FullCatalogEntry],
    catalog_dir: &str,
    user: &str,
) {
    reconcile_cross_wiring_with(
        installed_id,
        agents,
        catalog_dir,
        user,
        dispatcher::dispatch_recipe,
    );
}

/// DI-seam variant — the testable core.
pub fn reconcile_cross_wiring_with(
    installed_id: &str,
    agents: &[FullCatalogEntry],
    catalog_dir: &str,
    user: &str,
    dispatch: RecipeDispatcher,
) {
    // Only a freshly-installed coding agent can be a NEW wiring target.
    if !WIREABLE_AGENTS.contains(&installed_id) {
        return;
    }

    // The ids the host currently has a sentinel for.
    let installed_ids: HashSet<String> = match sentinel::list_sentinels() {
        Ok(list) => list.into_iter().map(|s| s.id).collect(),
        // A sentinel-list failure is non-fatal (best-effort) — skip the reconcile.
        Err(_) => return,
    };

    // Providers = installed entries declaring a rewire recipe, excluding the agent
    // we just installed (its own install already wired whatever was present).
    for provider in agents {
        if !installed_ids.contains(&provider.id) {
            continue;
        }
        if provider.id == installed_id {
            continue;
        }
        let Some(rewire) = provider.rewire_recipe_path.as_deref() else {
            continue;
        };
        // TRUST: provider.id + rewire_recipe_path are catalog-derived; the catalog
        // is an installer-owned, root-written artifact under /opt/agentlinux/catalog
        // and its schema constrains recipe paths — so no local traversal guard here
        // (faithful to install.ts). If the catalog ever becomes caller-influenced,
        // add a `..`/absolute reject mirroring catalog.rs preserve_paths.
        let recipe_path = std::path::Path::new(catalog_dir)
            .join("agents")
            .join(&provider.id)
            .join(rewire);
        let recipe_env = RecipeEnv {
            pinned_version: provider.pinned_version.clone(),
            catalog_dir: catalog_dir.to_string(),
            agent_home: format!("/home/{user}"),
            source_kind: provider.source_kind.clone().unwrap_or_default(),
            install_log: "/var/log/agentlinux-install.log".to_string(),
            preserve_paths: provider
                .preserve_paths
                .clone()
                .unwrap_or_default()
                .join(":"),
        };
        let env = full_child_env(recipe_env, user, &[]);
        let result = dispatch(
            user,
            &recipe_path.to_string_lossy(),
            &env,
            Capture::Buffered,
        );
        if result.exit_code == 0 {
            println!("↻ re-wired {} into {installed_id}", provider.id);
        } else {
            eprintln!(
                "↻ note: re-wiring {} into {installed_id} exited {} (install still OK; run `agentlinux install {}` to re-wire)",
                provider.id, result.exit_code, provider.id
            );
        }
    }
}

#[cfg(test)]
mod rewire_tests {
    use super::*;
    use crate::dispatcher::DispatchResult;
    use crate::sentinel::Sentinel;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tempfile::tempdir;

    fn provider(id: &str, rewire: Option<&str>) -> FullCatalogEntry {
        let mut json = serde_json::json!({
            "id": id,
            "display_name": "P",
            "description": "d",
            "source_kind": "binary",
            "pinned_version": "1.0.0",
            "install_recipe_path": "install.sh",
            "uninstall_recipe_path": "uninstall.sh",
        });
        if let Some(r) = rewire {
            json["rewire_recipe_path"] = serde_json::json!(r);
        }
        serde_json::from_value(json).unwrap()
    }

    static DISPATCH_COUNT: AtomicUsize = AtomicUsize::new(0);
    fn counting_ok(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
        DISPATCH_COUNT.fetch_add(1, Ordering::SeqCst);
        DispatchResult {
            exit_code: 0,
            stdout: String::new(),
            stderr: String::new(),
            streamed: false,
        }
    }

    // A non-wireable installed id short-circuits: no sentinel read, no dispatch.
    #[test]
    fn non_wireable_agent_is_a_noop() {
        DISPATCH_COUNT.store(0, Ordering::SeqCst);
        // rtk is a provider, not a wireable coding agent → early return.
        reconcile_cross_wiring_with("rtk", &[], "/tmp", "agent", counting_ok);
        assert_eq!(DISPATCH_COUNT.load(Ordering::SeqCst), 0);
    }

    // Happy path: installing a wireable agent (claude-code) re-runs an installed
    // provider's (rtk) rewire recipe exactly once, excluding the agent itself.
    #[test]
    fn rewires_installed_providers_into_new_agent() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let state = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());

        // rtk (provider, has a rewire recipe) + claude-code are both installed.
        sentinel::write_sentinel(&Sentinel::new(
            "rtk".into(),
            "1.0.0".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        sentinel::write_sentinel(&Sentinel::new(
            "claude-code".into(),
            "2.1.98".into(),
            "curated".into(),
            false,
        ))
        .unwrap();

        let agents = vec![
            provider("rtk", Some("rewire.sh")),
            provider("claude-code", None), // the new agent — excluded (no rewire recipe anyway)
        ];

        DISPATCH_COUNT.store(0, Ordering::SeqCst);
        reconcile_cross_wiring_with("claude-code", &agents, "/opt/cat", "agent", counting_ok);
        // Exactly rtk's rewire ran (claude-code excluded as the installed id).
        assert_eq!(DISPATCH_COUNT.load(Ordering::SeqCst), 1);

        env_scope.unset("AGENTLINUX_STATE_DIR");
    }

    // A provider that is NOT installed (no sentinel) is skipped.
    #[test]
    fn skips_uninstalled_providers() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let state = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        // Only claude-code installed; rtk is in the catalog but has no sentinel.
        sentinel::write_sentinel(&Sentinel::new(
            "claude-code".into(),
            "2.1.98".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        let agents = vec![provider("rtk", Some("rewire.sh"))];

        DISPATCH_COUNT.store(0, Ordering::SeqCst);
        reconcile_cross_wiring_with("claude-code", &agents, "/opt/cat", "agent", counting_ok);
        assert_eq!(DISPATCH_COUNT.load(Ordering::SeqCst), 0);

        env_scope.unset("AGENTLINUX_STATE_DIR");
    }

    // A non-zero rewire exit does NOT abort the sweep and does NOT invalidate
    // the provider's install.
    #[test]
    fn a_failed_rewire_leaves_the_sentinel_intact_and_keeps_going() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let state = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        sentinel::write_sentinel(&Sentinel::new(
            "rtk".into(),
            "1.0.0".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        sentinel::write_sentinel(&Sentinel::new(
            "claude-code".into(),
            "2.1.98".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        sentinel::write_sentinel(&Sentinel::new(
            "gsd".into(),
            "1.37.1".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        let agents = vec![
            provider("rtk", Some("rewire.sh")),
            provider("gsd", Some("rewire.sh")),
        ];

        fn failing(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
            DISPATCH_COUNT.fetch_add(1, Ordering::SeqCst);
            DispatchResult {
                exit_code: 3,
                stdout: String::new(),
                stderr: "rewire boom".to_string(),
                streamed: false,
            }
        }

        DISPATCH_COUNT.store(0, Ordering::SeqCst);
        reconcile_cross_wiring_with("claude-code", &agents, "/opt/cat", "agent", failing);

        // The behaviour worth defending, and what the old "no panic" version
        // discarded: the first provider failing must not stop the second…
        assert_eq!(
            DISPATCH_COUNT.load(Ordering::SeqCst),
            2,
            "a failed rewire must not abort the remaining providers"
        );
        // …and a failed rewire must not be mistaken for a failed install: the
        // provider's sentinel is left exactly as it was.
        let rtk = sentinel::read_sentinel("rtk")
            .unwrap()
            .expect("rtk sentinel");
        assert_eq!(rtk.version, "1.0.0");
        assert!(sentinel::read_sentinel("gsd").unwrap().is_some());
    }
}
