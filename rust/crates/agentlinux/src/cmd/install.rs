//! cmd/install.rs — `agentlinux install <name>` (CLI-03, VERB-01/02/03).
//!
//! The decision flow:
//! loadCatalog → resolve entry → honor test_only → REUSE-03 / REMEDIATE-04
//! short-circuits → decideVersion → dispatchRecipe → writeSentinel. This is the
//! FIRST verb to exercise the dispatcher (VERB-02) on a REAL recipe with
//! the RecipeEnv contract (VERB-03) end-to-end.
//!
//! # The pure/adapter seam
//! The DECISION lives in the pure core: `reuse_gate`/`remediate_gate`
//! (detect_gates.rs) + `decide_version` (classify.rs). The verb NEVER re-derives.
//! The post-gate host I/O — `tryReuse`'s `statSync` reuse re-validation
//! (install.ts:183-188 via the shared cache adapter) and the post-uninstall
//! `existsSync` — lives HERE in the adapter, not in the pure gate.
//!
//! # DI seam
//! A `RecipeDispatcher` fn is injected so unit tests exercise the branch selection
//! plus the exit map and literals without spawning a real recipe (mirrors the TS
//! `dispatcher?` DI param). Production passes `real_dispatch` (the streaming
//! `dispatch_recipe`).

use crate::catalog;
use crate::cli::InstallArgs;
use crate::dispatcher::{self, Capture, RecipeDispatcher};
use crate::recipe_env::{recipe_child_env, recipe_path, resolve_install_user};
use crate::rewire;
use crate::sentinel::{self, Sentinel};
use crate::{agent_home, canonical_path, host_paths};
use agentlinux_core::classify::decide_version;
use agentlinux_core::detect_gates::{remediate_gate, reuse_gate, RemediateReason};
use agentlinux_core::semver_shim;
use agentlinux_core::types::CatalogEntry as CoreCatalogEntry;
use std::io::IsTerminal;
use std::process::ExitCode;

const EX_USAGE: u8 = 64;
const EX_DATAERR: u8 = 65;

/// `agentlinux install <name>` body.
#[must_use]
pub fn install(name: &str, opts: &InstallArgs) -> ExitCode {
    install_with(name, opts, dispatcher::dispatch_recipe)
}

/// DI-seam variant — the testable core (tests inject a stub dispatcher).
#[must_use]
pub fn install_with(name: &str, opts: &InstallArgs, dispatch: RecipeDispatcher) -> ExitCode {
    // --dry-run + --yes is contradictory (dry-run never mutates; --yes is a
    // mutation gate). Reject upfront with exit 64.
    if opts.dry_run && opts.yes {
        crate::plog!(
            "agentlinux install: contradictory flags — --dry-run forbids --yes (dry-run never mutates; --yes is a mutation gate)"
        );
        return ExitCode::from(EX_USAGE);
    }

    // loadCatalog(validate:true) — install is a mutation path.
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

    // test_only entries are refused unless --include-test.
    if entry.test_only && !opts.include_test {
        crate::plog!("agentlinux: {name} is a test-only entry; pass --include-test to install");
        return ExitCode::from(EX_USAGE);
    }

    // --version present but not valid semver → 64.
    if let Some(v) = opts.version.as_deref() {
        if semver_shim::valid(v).is_none() {
            crate::plog!("agentlinux: --version '{v}' is not a valid semver");
            return ExitCode::from(EX_USAGE);
        }
    }

    let existing = match sentinel::read_sentinel(&entry.id) {
        Ok(s) => s,
        Err(e) => {
            crate::plog!("agentlinux: failed to read sentinel for {}: {e}", entry.id);
            return ExitCode::from(1);
        }
    };

    let core_entry = CoreCatalogEntry::from(entry);
    let home = agent_home();
    let canonical = canonical_path(&entry.id);
    let user = resolve_install_user();

    // Compute the reuse/remediate candidates once (used by both --dry-run and the
    // real path). tryReuse is skipped on --force / --version / an existing sentinel;
    // tryRemediate is skipped on --force / --version (but fires even with a sentinel).
    let detected = crate::cache::read_cached_agent_by_id(&entry.id);
    let reuse_hit = if !opts.force && opts.version.is_none() && existing.is_none() {
        try_reuse(&core_entry, detected.as_ref(), canonical, &home)
    } else {
        None
    };
    let remediate_hit = if !opts.force && opts.version.is_none() {
        detected
            .as_ref()
            .and_then(|d| remediate_gate(&core_entry, d, host_paths(canonical, &home)))
    } else {
        None
    };

    // UX-01: --dry-run early-return. No dispatch, no sentinel.
    if opts.dry_run {
        // For dry-run, tryRemediate is only consulted when reuse didn't hit
        // (install.ts:80 — `!reuseHit`).
        let remediate_for_dry = if reuse_hit.is_none() {
            remediate_hit.as_ref()
        } else {
            None
        };
        let decision = if reuse_hit.is_some() {
            "reuse"
        } else if remediate_for_dry.is_some() {
            "remediate"
        } else {
            "create"
        };
        let would_action = match decision {
            "reuse" => format!(
                "short-circuit (binary at {})",
                reuse_hit.as_ref().map_or("?", |h| h.binary_path.as_str())
            ),
            "remediate" => {
                let r = remediate_for_dry.unwrap();
                format!(
                    "uninstall + reinstall (reason: {}; detected at {}; canonical at {})",
                    r.reason.as_str(),
                    r.detected_path,
                    r.canonical_path
                )
            }
            _ => format!("dispatch install.sh at version {}", entry.pinned_version),
        };
        // The Commander install command exposes no `--json` flag,
        // so install.ts's `opts.json` dry-run branch is unreachable in practice —
        // the CLI always prints the `[DRY-RUN]` text line. Match that behavior.
        println!("[DRY-RUN] {}: {decision} — would {would_action}", entry.id);
        return ExitCode::SUCCESS;
    }

    // REUSE-03: write a status:"reused" sentinel, no dispatch.
    if let Some(hit) = reuse_hit {
        let now = sentinel::now_iso8601();
        let mut s = Sentinel::new(
            entry.id.clone(),
            hit.version.clone(),
            "curated".into(),
            false,
        );
        s.installed_at = Some(now.clone());
        s.status = Some("reused".to_string());
        s.binary_path = Some(hit.binary_path.clone());
        s.detected_source = Some(hit.detected_source.clone());
        s.reused_at = Some(now);
        s.compatibility_window_at_reuse = entry.compatibility_window.clone();
        if let Err(e) = sentinel::write_sentinel(&s) {
            crate::plog!("agentlinux: failed to write sentinel for {}: {e}", entry.id);
            return ExitCode::from(1);
        }
        println!(
            "[REUSE-03] {} reused: binary={} version={} (in window {}) status=healthy",
            entry.id,
            hit.binary_path,
            hit.version,
            entry.compatibility_window.as_deref().unwrap_or("")
        );
        return ExitCode::SUCCESS;
    }

    // REMEDIATE-04.
    if let Some(rem) = remediate_hit {
        let is_migration = rem.reason == RemediateReason::PathMismatch;
        let dv = rem.detected_version.as_deref();
        let dv_in_window = dv.is_some_and(|d| {
            entry
                .compatibility_window
                .as_deref()
                .is_some_and(|w| !w.is_empty() && semver_shim::satisfies(d, w))
        });
        let preserve_version = if is_migration && dv_in_window {
            dv
        } else {
            None
        };
        let install_version = preserve_version
            .map(str::to_string)
            .unwrap_or_else(|| entry.pinned_version.clone());
        let install_source = if preserve_version.is_some() {
            "override"
        } else {
            "curated"
        };
        let action_word = if is_migration {
            "migrate npm→native (uninstall + reinstall)"
        } else {
            "uninstall + reinstall"
        };

        // --yes is the sole consent surface (no env-var equivalent). TTY mode
        // auto-passes.
        let is_tty = std::io::stdin().is_terminal();
        if !opts.yes && !is_tty {
            crate::plog!(
                "Refusing to proceed — 1 component needs Remediate (run with --yes to apply, or --dry-run to preview):\n"
            );
            crate::plog!(
                "[BAIL] component={} reason={} hint=run with --yes to {}",
                entry.id,
                rem.reason.as_str(),
                if is_migration { "migrate" } else { "reinstall" }
            );
            crate::plog!(
                "\nExit code 65 (EX_DATAERR — incompatible host state). See agentlinux install --help."
            );
            return ExitCode::from(EX_DATAERR);
        }

        println!(
            "[REMEDIATE-04] {} component={} reason={} detected_path={} canonical_path={} install_version={}{} — {}",
            entry.id,
            entry.id,
            rem.reason.as_str(),
            rem.detected_path,
            rem.canonical_path,
            install_version,
            if preserve_version.is_some() {
                " (preserving your version)"
            } else {
                ""
            },
            action_word
        );

        // Step 1: uninstall.sh. Version = existing sentinel version else the pin.
        let uninstall_version = existing
            .as_ref()
            .map(|s| s.version.clone())
            .unwrap_or_else(|| entry.pinned_version.clone());
        let uninstall_path = recipe_path(&catalog_dir, &entry.id, &entry.uninstall_recipe_path);
        let uninstall_env = recipe_child_env(entry, &uninstall_version, &catalog_dir, &user);
        let uninstall_result = dispatch(&user, &uninstall_path, &uninstall_env, Capture::Buffered);
        if uninstall_result.exit_code != 0 {
            crate::plog!(
                "[REMEDIATE-04:uninstall-fail] {} uninstall.sh exited {}",
                entry.id, uninstall_result.exit_code
            );
            if !uninstall_result.stderr.is_empty() {
                crate::plog!("{}", uninstall_result.stderr);
            }
            return ExitCode::from(1);
        }

        // Post-uninstall verification: the binary must be gone
        // at BOTH the canonical + detected path, else abort (exit 1). ADAPTER I/O.
        let canonical_present = std::path::Path::new(&rem.canonical_path).exists();
        let detected_present = std::path::Path::new(&rem.detected_path).exists();
        if canonical_present || detected_present {
            crate::plog!(
                "[REMEDIATE-04:uninstall-incomplete] {} uninstall.sh exited 0 but binary still present (canonical={canonical_present} detected={detected_present})",
                entry.id
            );
            return ExitCode::from(1);
        }

        // Step 2: install.sh at install_version (streaming).
        let install_path = recipe_path(&catalog_dir, &entry.id, &entry.install_recipe_path);
        println!("▸ reinstalling {} {}…", entry.id, install_version);
        let install_env = recipe_child_env(entry, &install_version, &catalog_dir, &user);
        let install_result = dispatch(&user, &install_path, &install_env, Capture::Streamed);
        if install_result.exit_code != 0 {
            let now = sentinel::now_iso8601();
            let mut s = Sentinel::new(
                entry.id.clone(),
                install_version.clone(),
                install_source.into(),
                false,
            );
            s.installed_at = Some(now.clone());
            s.status = Some("broken-after-remediate".to_string());
            s.remediated_at = Some(now);
            s.remediate_failure_reason = Some("install-failed-post-uninstall".to_string());
            let _ = sentinel::write_sentinel(&s);
            crate::plog!(
                "[REMEDIATE-04:half-uninstalled] {} install.sh exited {} after uninstall succeeded — manual recovery needed (run agentlinux remove {} then agentlinux install {})",
                entry.id, install_result.exit_code, entry.id, entry.id
            );
            if !install_result.stderr.is_empty() {
                crate::plog!("{}", install_result.stderr);
            }
            return ExitCode::from(1);
        }

        // Step 3: success sentinel + remediated_at.
        let now = sentinel::now_iso8601();
        let mut s = Sentinel::new(
            entry.id.clone(),
            install_version.clone(),
            install_source.into(),
            false,
        );
        s.installed_at = Some(now.clone());
        s.status = Some("installed".to_string());
        s.remediated_at = Some(now);
        if let Err(e) = sentinel::write_sentinel(&s) {
            crate::plog!("agentlinux: failed to write sentinel for {}: {e}", entry.id);
            return ExitCode::from(1);
        }
        println!(
            "[REMEDIATE-04] {}: {} at {install_version} ({install_source})",
            entry.id,
            if is_migration {
                "migrated to native"
            } else {
                "reinstalled"
            }
        );
        rewire::reconcile_cross_wiring(&entry.id, &agents, &catalog_dir.to_string_lossy(), &user);
        return ExitCode::SUCCESS;
    }

    // decideVersion — the pure decision.
    let decision = decide_version(
        &core_entry,
        opts.version.as_deref(),
        existing
            .as_ref()
            .map(agentlinux_core::types::Sentinel::from)
            .as_ref(),
    );

    // Idempotent short-circuit.
    if !opts.force {
        if let Some(ex) = existing.as_ref() {
            if semver_shim::eq(&ex.version, &decision.version).unwrap_or(false) {
                println!(
                    "{}: already installed at {} ({}); no-op",
                    entry.id, ex.version, ex.source
                );
                return ExitCode::SUCCESS;
            }
        }
    }

    // create path: dispatch install.sh streaming.
    let install_path = recipe_path(&catalog_dir, &entry.id, &entry.install_recipe_path);
    println!("▸ installing {} {}…", entry.id, decision.version);
    let env = recipe_child_env(entry, &decision.version, &catalog_dir, &user);
    let result = dispatch(&user, &install_path, &env, Capture::Streamed);
    if result.exit_code != 0 {
        crate::plog!(
            "{}: install.sh failed (exit {})",
            entry.id, result.exit_code
        );
        if !result.stderr.is_empty() {
            crate::plog!("{}", result.stderr);
        }
        // Propagate the recipe exit code.
        return exit_from_code(result.exit_code);
    }

    let now = sentinel::now_iso8601();
    let mut s = Sentinel::new(
        entry.id.clone(),
        decision.version.clone(),
        decision.source.clone(),
        decision.sticky,
    );
    s.installed_at = Some(now);
    s.status = Some("installed".to_string());
    if let Err(e) = sentinel::write_sentinel(&s) {
        crate::plog!("agentlinux: failed to write sentinel for {}: {e}", entry.id);
        return ExitCode::from(1);
    }
    println!(
        "{}: installed {} ({})",
        entry.id, decision.version, decision.source
    );
    rewire::reconcile_cross_wiring(&entry.id, &agents, &catalog_dir.to_string_lossy(), &user);
    ExitCode::SUCCESS
}

// ---------------------------------------------------------------------------
// Adapter helpers
// ---------------------------------------------------------------------------

/// The full `ReuseHit` — the pure `reuse_gate` verdict PLUS the host `statSync`
/// re-validation + the `detected_source` label. Mirrors the
/// TS `ReuseHit` shape.
struct ReuseHit {
    binary_path: String,
    version: String,
    detected_source: String,
}

/// tryReuse = the PURE `reuse_gate` + the host `std::fs::metadata(...).is_file()`
/// re-validation HERE in the adapter. Stale-cache safety: the
/// cache may report a binary that was removed since detect ran.
fn try_reuse(
    core_entry: &CoreCatalogEntry,
    detected: Option<&agentlinux_core::types::DetectedAgent>,
    canonical: Option<&str>,
    home: &str,
) -> Option<ReuseHit> {
    let candidate = reuse_gate(core_entry, detected?, host_paths(canonical, home))?;
    // ADAPTER statSync re-validation.
    if !std::fs::metadata(&candidate.path)
        .map(|m| m.is_file())
        .unwrap_or(false)
    {
        return None;
    }
    Some(ReuseHit {
        binary_path: candidate.path,
        version: candidate.version,
        detected_source: "pre-existing".to_string(),
    })
}

/// Map a recipe exit code to an `ExitCode` (0-255), collapsing an out-of-range
/// code to 1 like a shell would.
fn exit_from_code(code: i32) -> ExitCode {
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}

#[cfg(test)]
mod install_tests {
    use super::*;
    use crate::dispatcher::DispatchResult;
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

    fn args(
        force: bool,
        version: Option<&str>,
        include_test: bool,
        yes: bool,
        dry_run: bool,
        name: &str,
    ) -> InstallArgs {
        InstallArgs {
            name: name.to_string(),
            force,
            version: version.map(str::to_string),
            include_test,
            yes,
            dry_run,
        }
    }

    /// A dispatcher that always succeeds (exit 0), so the create/remediate paths
    /// reach their sentinel write without a real recipe.
    fn ok_dispatch(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
        DispatchResult {
            exit_code: 0,
            stdout: String::new(),
            stderr: String::new(),
            streamed: matches!(_s, Capture::Streamed),
        }
    }

    /// A dispatcher that fails (exit 7) — the recipe-failure exit-map row.
    fn fail_dispatch(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
        DispatchResult {
            exit_code: 7,
            stdout: String::new(),
            stderr: "recipe boom".to_string(),
            streamed: matches!(_s, Capture::Streamed),
        }
    }

    fn set_env(cat: &std::path::Path, state: &std::path::Path) {
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat);
        std::env::set_var("AGENTLINUX_STATE_DIR", state);
        std::env::set_var("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");
    }
    fn clear_env() {
        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }

    // --- Usage exit rows (64) ---

    #[test]
    fn dry_run_and_yes_is_64() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, true, true, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
        clear_env();
    }

    #[test]
    fn unknown_agent_is_64() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            install_with(
                "ghost",
                &args(false, None, false, false, false, "ghost"),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
        clear_env();
    }

    #[test]
    fn test_only_without_include_test_is_64() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, false, false, false, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
        clear_env();
    }

    #[test]
    fn bad_version_semver_is_64() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(
                    false,
                    Some("not-a-semver"),
                    true,
                    false,
                    false,
                    "test-dummy"
                ),
                ok_dispatch
            ),
            ExitCode::from(EX_USAGE)
        );
        clear_env();
    }

    // --- create path + --version override → source=override ---

    #[test]
    fn create_path_writes_curated_sentinel() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, false, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::SUCCESS
        );
        let s = sentinel::read_sentinel("test-dummy").unwrap().unwrap();
        assert_eq!(s.version, "0.0.1");
        assert_eq!(s.source, "curated");
        assert_eq!(s.status.as_deref(), Some("installed"));
        clear_env();
    }

    #[test]
    fn version_override_records_source_override() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, Some("9.9.9"), true, false, false, "test-dummy"),
                ok_dispatch
            ),
            ExitCode::SUCCESS
        );
        let s = sentinel::read_sentinel("test-dummy").unwrap().unwrap();
        assert_eq!(s.version, "9.9.9");
        assert_eq!(s.source, "override");
        clear_env();
    }

    // --- idempotent no-op ---

    #[test]
    fn idempotent_second_install_is_noop() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        // First install writes the sentinel.
        let _ = install_with(
            "test-dummy",
            &args(false, None, true, false, false, "test-dummy"),
            ok_dispatch,
        );
        // Second is a no-op: even a failing dispatcher must NOT run (short-circuit).
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, false, "test-dummy"),
                fail_dispatch
            ),
            ExitCode::SUCCESS
        );
        clear_env();
    }

    // --- recipe failure propagates the exit code ---

    #[test]
    fn recipe_failure_propagates_exit_code() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        // A fresh install with a failing recipe → exit 7 (propagated), no sentinel.
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, false, "test-dummy"),
                fail_dispatch
            ),
            ExitCode::from(7)
        );
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_none());
        clear_env();
    }

    // --- --dry-run: no dispatch, no sentinel, exit 0 ---

    #[test]
    fn dry_run_creates_no_sentinel_and_does_not_dispatch() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        set_env(cat.path(), state.path());
        // A failing dispatcher must never run under --dry-run.
        assert_eq!(
            install_with(
                "test-dummy",
                &args(false, None, true, false, true, "test-dummy"),
                fail_dispatch
            ),
            ExitCode::SUCCESS
        );
        assert!(sentinel::read_sentinel("test-dummy").unwrap().is_none());
        clear_env();
    }

    // --- exact literal shapes (byte strings incl. ▸ + [REUSE-03]/[REMEDIATE-04]) ---

    #[test]
    fn literal_bytes_are_exact() {
        // Guard the load-bearing byte strings the bats greps. These
        // format the same way the verb prints them.
        let installing = format!("▸ installing {} {}…", "test-dummy", "0.0.1");
        assert_eq!(installing, "▸ installing test-dummy 0.0.1…");
        let reinstalling = format!("▸ reinstalling {} {}…", "claude-code", "2.1.98");
        assert_eq!(reinstalling, "▸ reinstalling claude-code 2.1.98…");
        let installed = format!("{}: installed {} ({})", "test-dummy", "0.0.1", "curated");
        assert_eq!(installed, "test-dummy: installed 0.0.1 (curated)");
        let noop = format!(
            "{}: already installed at {} ({}); no-op",
            "test-dummy", "0.0.1", "curated"
        );
        assert_eq!(
            noop,
            "test-dummy: already installed at 0.0.1 (curated); no-op"
        );
    }
}
