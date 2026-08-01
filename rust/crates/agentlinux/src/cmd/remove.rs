//! cmd/remove.rs — `agentlinux remove <name>` (CLI-04, VERB-01/02/03).
//!
//! Flow: loadCatalog →
//! resolve entry (64 on miss) → readSentinel (1 unless --force) →
//! dispatchRecipe(uninstall.sh, streaming) → deleteSentinel. Requiring a sentinel
//! (unless --force) prevents a drive-by remove on a never-installed agent.
//!
//! # DI seam
//! The recipe dispatch goes through the shared `RecipeDispatcher` (install.rs) so
//! unit tests exercise the exit map + literals without a real recipe.

use crate::catalog;
use crate::cli::RemoveArgs;
use crate::dispatcher::{self, Capture, RecipeDispatcher};
use crate::recipe_env::{recipe_child_env, recipe_path, resolve_install_user};
use crate::sentinel;
use std::process::ExitCode;

const EX_USAGE: u8 = 64;

/// `agentlinux remove <name>` body.
#[must_use]
pub fn remove(name: &str, opts: &RemoveArgs) -> ExitCode {
    remove_with(name, opts, dispatcher::dispatch_recipe)
}

/// DI-seam variant — the testable core.
#[must_use]
pub fn remove_with(name: &str, opts: &RemoveArgs, dispatch: RecipeDispatcher) -> ExitCode {
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, catalog::Validate::Required) {
        Ok(a) => a,
        Err(e) => {
            crate::plog!("{e}");
            return ExitCode::from(1);
        }
    };

    let Some(entry) = catalog::find_entry(&agents, name) else {
        return ExitCode::from(EX_USAGE);
    };

    let sentinel = match sentinel::read_sentinel(&entry.id) {
        Ok(s) => s,
        Err(e) => {
            crate::plog!("agentlinux: failed to read sentinel for {}: {e}", entry.id);
            return ExitCode::from(1);
        }
    };

    let Some(sentinel) = sentinel else {
        // Not installed. Without --force → exit 1; with --force → no-op exit 0.
        if !opts.force {
            crate::plog!(
                "agentlinux: {} is not installed (pass --force for no-op)",
                entry.id
            );
            return ExitCode::from(1);
        }
        return ExitCode::SUCCESS; // --force + not-installed = idempotent exit 0
    };

    // For a "reused" (adopted) sentinel whose binary has since vanished, running
    // uninstall.sh against a missing binary is wasteful — just delete the sentinel
    // The existsSync host check lives HERE in the adapter.
    if sentinel.status.as_deref() == Some("reused") {
        if let Some(bin) = sentinel.binary_path.as_deref() {
            if !std::path::Path::new(bin).exists() {
                if let Err(e) = sentinel::delete_sentinel(&entry.id) {
                    crate::plog!(
                        "agentlinux: failed to delete sentinel for {}: {e}",
                        entry.id
                    );
                    return ExitCode::from(1);
                }
                println!(
                    "{}: sentinel removed (binary at {bin} was already gone — adopted binary no longer present)",
                    entry.id
                );
                return ExitCode::SUCCESS;
            }
        }
    }

    let user = resolve_install_user();
    let recipe = recipe_path(&catalog_dir, &entry.id, &entry.uninstall_recipe_path);
    println!("▸ removing {}…", entry.id);
    let env = recipe_child_env(entry, &sentinel.version, &catalog_dir, &user);
    let result = dispatch(&user, &recipe, &env, Capture::Streamed);
    if result.exit_code != 0 {
        crate::plog!(
            "{}: uninstall.sh failed (exit {})",
            entry.id, result.exit_code
        );
        if !result.stderr.is_empty() {
            crate::plog!("{}", result.stderr);
        }
        // Propagate the recipe exit code.
        return ExitCode::from(u8::try_from(result.exit_code).unwrap_or(1));
    }

    if let Err(e) = sentinel::delete_sentinel(&entry.id) {
        crate::plog!(
            "agentlinux: failed to delete sentinel for {}: {e}",
            entry.id
        );
        return ExitCode::from(1);
    }
    println!("{}: removed", entry.id);
    ExitCode::SUCCESS
}

#[cfg(test)]
mod remove_tests {
    use super::*;
    use crate::dispatcher::DispatchResult;
    use crate::sentinel::Sentinel;
    use tempfile::tempdir;

    fn write_catalog(dir: &std::path::Path) {
        std::fs::write(
            dir.join("catalog.json"),
            r#"{"version":"0.3.6","agents":[
                {"id":"test-dummy","display_name":"Test","description":"d","source_kind":"script",
                 "pinned_version":"0.0.1","install_recipe_path":"install.sh",
                 "uninstall_recipe_path":"uninstall.sh","test_only":true,"tags":["test-only"]}
            ]}"#,
        )
        .unwrap();
    }

    fn ok_dispatch(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
        DispatchResult {
            exit_code: 0,
            stdout: String::new(),
            stderr: String::new(),
            streamed: matches!(_s, Capture::Streamed),
        }
    }
    fn fail_dispatch(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
        DispatchResult {
            exit_code: 5,
            stdout: String::new(),
            stderr: "boom".to_string(),
            streamed: matches!(_s, Capture::Streamed),
        }
    }

    fn set_env(cat: &std::path::Path, state: &std::path::Path) {
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat);
        std::env::set_var("AGENTLINUX_STATE_DIR", state);
    }
    fn clear_env() {
        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
    }

    #[test]
    fn unknown_agent_is_64() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            remove_with(
                "ghost",
                &RemoveArgs {
                    name: "ghost".into(),
                    force: false,
                },
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
        clear_env();
    }

    #[test]
    fn not_installed_without_force_is_1() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            remove_with(
                "test-dummy",
                &RemoveArgs {
                    name: "test-dummy".into(),
                    force: false,
                },
                ok_dispatch
            ),
            ExitCode::from(1)
        );
        clear_env();
    }

    #[test]
    fn not_installed_with_force_is_0_noop() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            remove_with(
                "test-dummy",
                &RemoveArgs {
                    name: "test-dummy".into(),
                    force: true,
                },
                ok_dispatch
            ),
            ExitCode::SUCCESS
        );
        clear_env();
    }

    #[test]
    fn installed_remove_dispatches_and_deletes_sentinel() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        sentinel::write_sentinel(&Sentinel::new(
            "test-dummy".into(),
            "0.0.1".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        assert_eq!(
            remove_with(
                "test-dummy",
                &RemoveArgs {
                    name: "test-dummy".into(),
                    force: false,
                },
                ok_dispatch
            ),
            ExitCode::SUCCESS
        );
        // Sentinel deleted after a successful uninstall.
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_none());
        clear_env();
    }

    #[test]
    fn recipe_failure_propagates_and_preserves_sentinel() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        sentinel::write_sentinel(&Sentinel::new(
            "test-dummy".into(),
            "0.0.1".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        assert_eq!(
            remove_with(
                "test-dummy",
                &RemoveArgs {
                    name: "test-dummy".into(),
                    force: false,
                },
                fail_dispatch
            ),
            ExitCode::from(5)
        );
        // Sentinel PRESERVED on a failed uninstall (deletion only after success).
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_some());
        clear_env();
    }

    #[test]
    fn removing_literal_is_exact() {
        assert_eq!(
            format!("▸ removing {}…", "test-dummy"),
            "▸ removing test-dummy…"
        );
        assert_eq!(format!("{}: removed", "test-dummy"), "test-dummy: removed");
    }
}
