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
/// Not mutation-tested: binds the real streams and dispatcher (ADR-019 §5).
/// Every decision lives in [`remove_with`].
#[cfg_attr(test, mutants::skip)]
pub fn remove(name: &str, opts: &RemoveArgs) -> ExitCode {
    let (mut out, mut err) = (std::io::stdout(), std::io::stderr());
    remove_with(
        name,
        opts,
        dispatcher::dispatch_recipe,
        &mut crate::cmd::install::Out {
            out: &mut out,
            err: &mut err,
        },
    )
}

/// DI-seam variant — the testable core.
#[must_use]
pub fn remove_with(
    name: &str,
    opts: &RemoveArgs,
    dispatch: RecipeDispatcher,
    o: &mut crate::cmd::install::Out<'_>,
) -> ExitCode {
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, catalog::Validate::Required) {
        Ok(a) => a,
        Err(e) => {
            let _ = writeln!(o.err, "{e}");
            return ExitCode::from(1);
        }
    };

    let Some(entry) = catalog::find_entry(&agents, name, &mut std::io::stderr()) else {
        return ExitCode::from(EX_USAGE);
    };

    let sentinel = match sentinel::read_sentinel(&entry.id) {
        Ok(s) => s,
        Err(e) => {
            let _ = writeln!(
                o.err,
                "agentlinux: failed to read sentinel for {}: {e}",
                entry.id
            );
            return ExitCode::from(1);
        }
    };

    let Some(sentinel) = sentinel else {
        // Not installed. Without --force → exit 1; with --force → no-op exit 0.
        if !opts.force {
            let _ = writeln!(
                o.err,
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
                    let _ = writeln!(
                        o.err,
                        "agentlinux: failed to delete sentinel for {}: {e}",
                        entry.id
                    );
                    return ExitCode::from(1);
                }
                let _ = writeln!(o.out,
                    "{}: sentinel removed (binary at {bin} was already gone — adopted binary no longer present)",
                    entry.id
                );
                return ExitCode::SUCCESS;
            }
        }
    }

    let user = resolve_install_user();
    let recipe = recipe_path(&catalog_dir, &entry.id, &entry.uninstall_recipe_path);
    let _ = writeln!(o.out, "▸ removing {}…", entry.id);
    let env = recipe_child_env(entry, &sentinel.version, &catalog_dir, &user);
    let result = dispatch(&user, &recipe, &env, Capture::Streamed);
    if result.exit_code != 0 {
        let _ = writeln!(
            o.err,
            "{}: uninstall.sh failed (exit {})",
            entry.id, result.exit_code
        );
        crate::cmd::install::echo_stderr_if_any(o, &result.stderr);
        // Propagate the recipe exit code.
        return ExitCode::from(u8::try_from(result.exit_code).unwrap_or(1));
    }

    if let Err(e) = sentinel::delete_sentinel(&entry.id) {
        let _ = writeln!(
            o.err,
            "agentlinux: failed to delete sentinel for {}: {e}",
            entry.id
        );
        return ExitCode::from(1);
    }
    let _ = writeln!(o.out, "{}: removed", entry.id);
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

    static REMOVE_DISPATCHES: std::sync::atomic::AtomicUsize =
        std::sync::atomic::AtomicUsize::new(0);
    fn counting_dispatch(
        _u: &str,
        _p: &str,
        _e: &[(String, String)],
        _s: Capture,
    ) -> DispatchResult {
        REMOVE_DISPATCHES.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        DispatchResult {
            exit_code: 0,
            stdout: String::new(),
            stderr: String::new(),
            streamed: false,
        }
    }

    /// An ADOPTED agent whose binary has since vanished is removed by deleting
    /// the sentinel — running `uninstall.sh` against a binary that is not there
    /// is wasteful and, for a reused binary AgentLinux never installed, wrong.
    ///
    /// Three mutants survived on that shortcut: inverting the `== Some("reused")`
    /// status test and deleting the `!` on the existence check both send a
    /// managed agent down the adopted path (or vice versa), and the whole
    /// shortcut is only observable through what gets dispatched.
    #[test]
    fn an_adopted_agent_whose_binary_vanished_skips_the_uninstall_recipe() {
        use std::sync::atomic::Ordering;
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());

        let reused = |bin: &str| {
            let mut s = Sentinel::new("test-dummy".into(), "0.0.1".into(), "curated".into(), false);
            s.status = Some("reused".to_string());
            s.binary_path = Some(bin.to_string());
            s
        };

        // Adopted, binary gone → sentinel deleted, recipe NOT run.
        sentinel::write_sentinel(&reused("/nonexistent/vanished-binary")).unwrap();
        REMOVE_DISPATCHES.store(0, Ordering::SeqCst);
        let code = remove_with(
            "test-dummy",
            &RemoveArgs {
                name: "test-dummy".to_string(),
                force: false,
            },
            counting_dispatch,
            &mut crate::cmd::install::Out {
                out: &mut Vec::new(),
                err: &mut Vec::new(),
            },
        );
        assert_eq!(code, ExitCode::SUCCESS);
        assert_eq!(
            REMOVE_DISPATCHES.load(Ordering::SeqCst),
            0,
            "uninstall.sh must NOT run for a binary that is already gone"
        );
        assert!(
            sentinel::read_sentinel("test-dummy").unwrap().is_none(),
            "the sentinel must still be removed"
        );

        // Adopted, binary PRESENT → the recipe runs, because there is something
        // to uninstall.
        let bin = state.path().join("still-here");
        std::fs::write(&bin, b"#!/bin/sh\n").unwrap();
        sentinel::write_sentinel(&reused(bin.to_str().unwrap())).unwrap();
        REMOVE_DISPATCHES.store(0, Ordering::SeqCst);
        let code = remove_with(
            "test-dummy",
            &RemoveArgs {
                name: "test-dummy".to_string(),
                force: false,
            },
            counting_dispatch,
            &mut crate::cmd::install::Out {
                out: &mut Vec::new(),
                err: &mut Vec::new(),
            },
        );
        assert_eq!(code, ExitCode::SUCCESS);
        assert_eq!(
            REMOVE_DISPATCHES.load(Ordering::SeqCst),
            1,
            "a present adopted binary must still go through uninstall.sh"
        );

        // A MANAGED sentinel (not reused) always runs the recipe, even if the
        // recorded binary is gone — the shortcut is for adopted binaries only.
        let mut managed =
            Sentinel::new("test-dummy".into(), "0.0.1".into(), "curated".into(), false);
        managed.status = Some("installed".to_string());
        managed.binary_path = Some("/nonexistent/vanished-binary".to_string());
        sentinel::write_sentinel(&managed).unwrap();
        REMOVE_DISPATCHES.store(0, Ordering::SeqCst);
        let code = remove_with(
            "test-dummy",
            &RemoveArgs {
                name: "test-dummy".to_string(),
                force: false,
            },
            counting_dispatch,
            &mut crate::cmd::install::Out {
                out: &mut Vec::new(),
                err: &mut Vec::new(),
            },
        );
        assert_eq!(code, ExitCode::SUCCESS);
        assert_eq!(
            REMOVE_DISPATCHES.load(Ordering::SeqCst),
            1,
            "a managed agent is not an adopted one — the recipe still runs"
        );
    }

    /// Point the catalog/state reads at fixtures for the lifetime of
    /// `env_scope` — which restores them on drop, so a failing assertion cannot
    /// leak a fixture path into whatever test runs next.
    fn set_env(
        env_scope: &mut crate::test_support::EnvScope,
        cat: &std::path::Path,
        state: &std::path::Path,
    ) {
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat);
        env_scope.set("AGENTLINUX_STATE_DIR", state);
    }

    #[test]
    fn unknown_agent_is_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            remove_with(
                "ghost",
                &RemoveArgs {
                    name: "ghost".into(),
                    force: false
                },
                ok_dispatch,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new()
                },
            ),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn not_installed_without_force_is_1() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            remove_with(
                "test-dummy",
                &RemoveArgs {
                    name: "test-dummy".into(),
                    force: false
                },
                ok_dispatch,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new()
                },
            ),
            ExitCode::from(1)
        );
    }

    #[test]
    fn not_installed_with_force_is_0_noop() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
        assert_eq!(
            remove_with(
                "test-dummy",
                &RemoveArgs {
                    name: "test-dummy".into(),
                    force: true
                },
                ok_dispatch,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new()
                },
            ),
            ExitCode::SUCCESS
        );
    }

    #[test]
    fn installed_remove_dispatches_and_deletes_sentinel() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
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
                    force: false
                },
                ok_dispatch,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new()
                },
            ),
            ExitCode::SUCCESS
        );
        // Sentinel deleted after a successful uninstall.
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_none());
    }

    #[test]
    fn recipe_failure_propagates_and_preserves_sentinel() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(&mut env_scope, cat.path(), state.path());
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
                    force: false
                },
                fail_dispatch,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new()
                },
            ),
            ExitCode::from(5)
        );
        // Sentinel PRESERVED on a failed uninstall (deletion only after success).
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_some());
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
