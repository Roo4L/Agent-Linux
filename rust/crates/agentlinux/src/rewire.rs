//! rewire.rs — post-install cross-agent wiring reconcile (#4 / WIRE-02).
//!
//! Port of `plugin/cli/src/rewire.ts` (`reconcileCrossWiring`). A cross-agent
//! PROVIDER (rtk, a fan-out MCP server) wires itself into every coding agent
//! PRESENT AT ITS OWN INSTALL TIME. Without this reconcile, an agent installed
//! LATER stays un-wired, so the end state would depend on install order. After a
//! coding agent is installed, this re-runs each installed provider's lightweight,
//! idempotent, present-aware rewire recipe so it fans out into the new agent too.
//! Best-effort: a wiring hiccup NEVER fails the install that already succeeded.
//!
//! # DI seam
//! The dispatch goes through an injectable `RewireDispatcher` matching the
//! buffered `dispatch_recipe` shape (a rewire runs buffered — it isn't the long
//! interactive install path). Tests inject a capturing/stubbing dispatcher so no
//! sudo invocation happens under `cargo test`.
//!
//! `#![allow(dead_code)]`: `reconcile_cross_wiring` is consumed by Plan 03's
//! `install` verb after a successful recipe. The `#[cfg(test)]` module exercises
//! it now; the allow only defers the "not yet wired into a non-test caller" lint
//! until the verb layer imports it.
#![allow(dead_code)]

use crate::catalog::FullCatalogEntry;
use crate::dispatcher::{self, DispatchResult};
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

/// Dispatcher signature for a rewire recipe — mirrors `dispatch_recipe`
/// (user, recipe_path, env, stream). Typed so tests inject a stub without a real
/// subprocess. A rewire always dispatches buffered (`stream=false`).
pub type RewireDispatcher =
    fn(user: &str, recipe_path: &str, env: &[(String, String)], stream: bool) -> DispatchResult;

/// The production dispatcher — the real buffered `dispatch_recipe`.
fn real_dispatch(
    user: &str,
    recipe_path: &str,
    env: &[(String, String)],
    stream: bool,
) -> DispatchResult {
    dispatcher::dispatch_recipe(user, recipe_path, env, stream)
}

/// Re-run each installed provider's rewire recipe so it fans out into the
/// freshly-installed `installed_id`. Port of `reconcileCrossWiring`
/// (rewire.ts:30-81). Best-effort — never returns an error; a wiring hiccup is
/// logged and the install stays OK.
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
    reconcile_cross_wiring_with(installed_id, agents, catalog_dir, user, real_dispatch);
}

/// DI-seam variant — the testable core.
pub fn reconcile_cross_wiring_with(
    installed_id: &str,
    agents: &[FullCatalogEntry],
    catalog_dir: &str,
    user: &str,
    dispatch: RewireDispatcher,
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
        let result = dispatch(user, &recipe_path.to_string_lossy(), &env, false);
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
    fn counting_ok(_u: &str, _p: &str, _e: &[(String, String)], _s: bool) -> DispatchResult {
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
        let _g = crate::test_support::env_guard();
        let state = tempdir().unwrap();
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());

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

        std::env::remove_var("AGENTLINUX_STATE_DIR");
    }

    // A provider that is NOT installed (no sentinel) is skipped.
    #[test]
    fn skips_uninstalled_providers() {
        let _g = crate::test_support::env_guard();
        let state = tempdir().unwrap();
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
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

        std::env::remove_var("AGENTLINUX_STATE_DIR");
    }

    // A non-zero rewire exit does NOT panic or propagate — best-effort.
    #[test]
    fn failed_rewire_is_best_effort_no_panic() {
        let _g = crate::test_support::env_guard();
        let state = tempdir().unwrap();
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
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
        let agents = vec![provider("rtk", Some("rewire.sh"))];

        fn failing(_u: &str, _p: &str, _e: &[(String, String)], _s: bool) -> DispatchResult {
            DispatchResult {
                exit_code: 3,
                stdout: String::new(),
                stderr: "rewire boom".to_string(),
                streamed: false,
            }
        }
        // Must simply return (the assertion is "no panic").
        reconcile_cross_wiring_with("claude-code", &agents, "/opt/cat", "agent", failing);

        std::env::remove_var("AGENTLINUX_STATE_DIR");
    }
}
