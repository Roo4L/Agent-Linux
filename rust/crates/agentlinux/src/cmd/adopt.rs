//! cmd/adopt.rs — `agentlinux adopt [name] [--all]` (AL-61, AL-62).
//!
//! Records pre-existing,
//! reuse-eligible agents into `status:"reused"` sentinels WITHOUT installing
//! anything — it dispatches NO recipe, downloads nothing, remediates nothing. It
//! only records reality the host already holds so `list` stops reporting present
//! tools as not-installed.
//!
//! # The pure gate + adapter `statSync` seam
//! `tryReuse` = the PURE `reuse_gate` (detect_gates.rs) PLUS the host
//! `statSync(path).isFile()` re-validation that stays HERE in the adapter (the
//! cache may be stale — the binary could have been removed since detect ran).
//! `tryRemediate` = the PURE `remediate_gate` for the migration-candidate (AL-62)
//! detection. Neither pure gate does the stat; this adapter does it AFTER a
//! `Some` reuse verdict — so `grep metadata|is_file cmd/adopt.rs` matches here.
//!
//! # Guard
//! The CLI-05 guard runs once in `main::dispatch` (the TS preAction hook); adopt
//! does not re-guard.

use crate::catalog::{self, FullCatalogEntry};
use crate::sentinel::{self, Sentinel};
use crate::{agent_home, canonical_path, host_paths};
use agentlinux_core::detect_gates::{remediate_gate, reuse_gate};
use agentlinux_core::types::CatalogEntry as CoreCatalogEntry;
use serde::Serialize;
use std::process::ExitCode;

use crate::cli::AdoptArgs;

const EX_USAGE: u8 = 64;

/// The adopt verdict per entry — mirrors the TS `AdoptAction` union
///  + `AdoptResult`. Serialized for `--json`.
#[derive(Debug, Clone, Serialize)]
struct AdoptResult {
    id: String,
    action: String, // "adopted" | "already-managed" | "skipped" | "migrate-available"
    #[serde(skip_serializing_if = "Option::is_none")]
    version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    reason: Option<String>,
}

/// Adopt one entry — port of `adoptOne`.
fn adopt_one(entry: &FullCatalogEntry) -> AdoptResult {
    // Never adopt over an existing record — a real install/remediate owns it.
    if let Ok(Some(existing)) = sentinel::read_sentinel(&entry.id) {
        return AdoptResult {
            id: entry.id.clone(),
            action: "already-managed".to_string(),
            version: Some(existing.version),
            reason: None,
        };
    }

    let core_entry = CoreCatalogEntry::from(entry);
    let home = agent_home();
    let canonical = canonical_path(&entry.id);

    // tryReuse = the PURE reuse_gate + the host statSync re-validation HERE.
    let detected = crate::cache::read_cached_agent_by_id(&entry.id);
    let reuse_hit = detected
        .as_ref()
        .and_then(|d| reuse_gate(&core_entry, d, host_paths(canonical, &home)));
    let reuse_hit = reuse_hit.filter(|c| crate::cmd::is_regular_file(&c.path));

    let Some(hit) = reuse_hit else {
        // Not reuse-eligible. AL-62: distinguish a migration candidate (healthy at
        // a non-canonical path) from a plain skip via the PURE remediate_gate.
        let rem = detected
            .as_ref()
            .and_then(|d| remediate_gate(&core_entry, d, host_paths(canonical, &home)));
        if let Some(rem) = rem {
            // The same decision `install` makes, through the same tested
            // helper — a second copy of the comparison is a second place to get
            // it backwards.
            if crate::cmd::install::is_migration(rem.reason) {
                return AdoptResult {
                    id: entry.id.clone(),
                    action: "migrate-available".to_string(),
                    version: rem.detected_version.clone(),
                    reason: Some(format!(
                        "present at {} (non-canonical) — run `agentlinux install {}` to migrate to the native install",
                        rem.detected_path, entry.id
                    )),
                };
            }
        }
        return AdoptResult {
            id: entry.id.clone(),
            action: "skipped".to_string(),
            version: None,
            reason: Some(
                "not reuse-eligible (absent, out-of-window, broken, or wrong path)".to_string(),
            ),
        };
    };

    // Write a status:"reused" sentinel. Never dispatches a
    // recipe. `binary_path`/`detected_source` mirror the TS ReuseHit.
    let now = sentinel::now_iso8601();
    let mut s = Sentinel::new(
        entry.id.clone(),
        hit.version.clone(),
        "curated".into(),
        false,
    );
    s.installed_at = Some(now.clone());
    s.status = Some("reused".to_string());
    s.binary_path = Some(hit.path.clone());
    s.detected_source = Some("pre-existing".to_string());
    s.reused_at = Some(now);
    s.compatibility_window_at_reuse = entry.compatibility_window.clone();
    if let Err(e) = sentinel::write_sentinel(&s) {
        // A write failure is a genuine error — surface, mark skipped so the run
        // continues for --all sweeps.
        eprintln!("agentlinux: failed to write sentinel for {}: {e}", entry.id);
        return AdoptResult {
            id: entry.id.clone(),
            action: "skipped".to_string(),
            version: None,
            reason: Some(format!("sentinel write failed: {e}")),
        };
    }
    AdoptResult {
        id: entry.id.clone(),
        action: "adopted".to_string(),
        version: Some(hit.version),
        reason: None,
    }
}

/// `agentlinux adopt [name]` body. Port of `adoptCmd`.
#[must_use]
pub fn adopt(name: Option<&str>, opts: &AdoptArgs) -> ExitCode {
    // Hot path (validate:false) — a partially-invalid catalog shouldn't block
    // adopting the valid entries.
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, catalog::Validate::Skip) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(1);
        }
    };

    let targets: Vec<FullCatalogEntry> = if let Some(name) = name {
        let Some(entry) = catalog::find_entry(&agents, name, &mut std::io::stderr()) else {
            return ExitCode::from(EX_USAGE);
        };
        if entry.test_only && !opts.include_test {
            eprintln!("agentlinux: {name} is a test-only entry; pass --include-test to adopt");
            return ExitCode::from(EX_USAGE);
        }
        vec![entry.clone()]
    } else if opts.all {
        adopt_all_targets(agents, opts.include_test)
    } else {
        eprintln!("agentlinux adopt: specify an agent name or --all");
        return ExitCode::from(EX_USAGE);
    };

    let results: Vec<AdoptResult> = targets.iter().map(adopt_one).collect();

    if opts.json {
        match serde_json::to_string_pretty(&results) {
            Ok(s) => println!("{s}"),
            Err(e) => {
                eprintln!("agentlinux: failed to serialize adopt JSON: {e}");
                return ExitCode::from(1);
            }
        }
        return ExitCode::SUCCESS;
    }

    for r in &results {
        println!("{}", adopt_line(r));
    }
    ExitCode::SUCCESS
}

/// The `--all` target set: every catalog agent, with `test_only` fixtures
/// excluded unless `--include-test` asks for them.
///
/// Extracted from `adopt` because inside it the filter was only reachable by
/// running the whole verb. `delete !` offers the fixtures to everyone;
/// `|| -> &&` drops every REAL agent unless --include-test is passed, so a
/// plain `adopt --all` silently adopts nothing.
fn adopt_all_targets(agents: Vec<FullCatalogEntry>, include_test: bool) -> Vec<FullCatalogEntry> {
    agents
        .into_iter()
        .filter(|a| include_test || !a.test_only)
        .collect()
}

/// The operator-facing line for one adopt result.
///
/// Extracted for the same reason: all four arms went straight to `println!`, so
/// deleting any of the three named arms silently demoted its result to the
/// catch-all "nothing to adopt" — telling an operator that an agent AgentLinux
/// just adopted was not adopted at all.
fn adopt_line(r: &AdoptResult) -> String {
    let version = r.version.as_deref().unwrap_or("");
    let reason = r.reason.as_deref().unwrap_or("");
    match r.action.as_str() {
        "adopted" => format!(
            "[ADOPT] {}: adopted pre-existing install {version} (status=reused — managed by agentlinux upgrade/remove)",
            r.id
        ),
        "already-managed" => format!("{}: already managed at {version}; no-op", r.id),
        "migrate-available" => format!("[MIGRATE] {}: {reason}", r.id),
        _ => format!("{}: nothing to adopt — {reason}", r.id),
    }
}

#[cfg(test)]
mod adopt_tests {
    use super::*;

    fn result(id: &str, action: &str) -> AdoptResult {
        AdoptResult {
            id: id.to_string(),
            action: action.to_string(),
            version: Some("2.1.0".to_string()),
            reason: Some("because".to_string()),
        }
    }

    /// Each action renders as its OWN line. Deleting any of the three named
    /// match arms survived, and each deletion demotes that result to the
    /// catch-all "nothing to adopt" — so an agent AgentLinux just adopted is
    /// reported as not adopted.
    #[test]
    fn every_adopt_action_renders_as_its_own_line() {
        let adopted = adopt_line(&result("claude-code", "adopted"));
        assert!(
            adopted.starts_with("[ADOPT] claude-code:") && adopted.contains("2.1.0"),
            "got {adopted:?}"
        );
        assert!(
            adopted.contains("status=reused"),
            "the adopt line states what management it just took on: {adopted:?}"
        );

        let managed = adopt_line(&result("gsd", "already-managed"));
        assert!(
            managed.contains("already managed") && managed.contains("no-op"),
            "got {managed:?}"
        );

        let migrate = adopt_line(&result("rtk", "migrate-available"));
        assert!(
            migrate.starts_with("[MIGRATE] rtk:") && migrate.contains("because"),
            "got {migrate:?}"
        );

        let nothing = adopt_line(&result("other", "skipped"));
        assert!(
            nothing.contains("nothing to adopt") && nothing.contains("because"),
            "got {nothing:?}"
        );

        // And the four are genuinely distinct — a deleted arm would collapse one
        // into another.
        let all = [adopted, managed, migrate, nothing];
        for (i, a) in all.iter().enumerate() {
            for b in all.iter().skip(i + 1) {
                assert_ne!(a, b, "two actions must not render identically");
            }
        }
    }

    /// `--all` adopts every real agent, and the test fixtures only when asked.
    /// `|| -> &&` survived, which drops every REAL agent unless --include-test
    /// is passed — so a plain `adopt --all` silently adopts nothing.
    #[test]
    fn adopt_all_covers_real_agents_and_fixtures_only_on_request() {
        let entry = |id: &str, test_only: bool| -> FullCatalogEntry {
            serde_json::from_value(serde_json::json!({
                "id": id, "display_name": id, "description": "d",
                "source_kind": "script", "pinned_version": "1.0.0",
                "install_recipe_path": "install.sh",
                "uninstall_recipe_path": "uninstall.sh",
                "test_only": test_only,
            }))
            .unwrap()
        };
        let catalog = || vec![entry("claude-code", false), entry("test-dummy", true)];
        let ids = |v: Vec<FullCatalogEntry>| v.into_iter().map(|e| e.id).collect::<Vec<_>>();

        assert_eq!(
            ids(adopt_all_targets(catalog(), false)),
            vec!["claude-code"],
            "a plain --all must still cover the real agents"
        );
        assert_eq!(
            ids(adopt_all_targets(catalog(), true)),
            vec!["claude-code", "test-dummy"],
            "--include-test ADDS the fixtures, it does not replace the list"
        );
    }
    use tempfile::tempdir;

    fn write_catalog(dir: &std::path::Path) {
        // A claude-code entry (canonical /home/agent/.local/bin/claude) + test-dummy.
        std::fs::write(
            dir.join("catalog.json"),
            r#"{"version":"0.3.6","agents":[
                {"id":"claude-code","display_name":"Claude Code","description":"d","source_kind":"script",
                 "pinned_version":"2.1.98","compatibility_window":">=2.0.0 <3.0.0",
                 "install_recipe_path":"install.sh","uninstall_recipe_path":"uninstall.sh","tags":["agent"]},
                {"id":"test-dummy","display_name":"Test","description":"d","source_kind":"script",
                 "pinned_version":"0.0.1","install_recipe_path":"install.sh",
                 "uninstall_recipe_path":"uninstall.sh","test_only":true,"tags":["test-only"]}
            ]}"#,
        )
        .unwrap();
    }

    fn args(all: bool, include_test: bool, json: bool) -> AdoptArgs {
        AdoptArgs {
            name: None,
            all,
            include_test,
            json,
        }
    }

    #[test]
    fn no_name_no_all_exits_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        write_catalog(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        assert_eq!(
            adopt(None, &args(false, false, false)),
            ExitCode::from(EX_USAGE)
        );
        env_scope.unset("AGENTLINUX_CATALOG_DIR");
    }

    #[test]
    fn unknown_agent_exits_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        write_catalog(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        assert_eq!(
            adopt(Some("ghost"), &args(false, false, false)),
            ExitCode::from(EX_USAGE)
        );
        env_scope.unset("AGENTLINUX_CATALOG_DIR");
    }

    #[test]
    fn test_only_without_include_test_exits_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        write_catalog(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        assert_eq!(
            adopt(Some("test-dummy"), &args(false, false, false)),
            ExitCode::from(EX_USAGE)
        );
        env_scope.unset("AGENTLINUX_CATALOG_DIR");
    }

    #[test]
    fn greenfield_all_is_a_noop_exit_0() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");
        // No cache → nothing adopted, no sentinel written, exit 0.
        assert_eq!(adopt(None, &args(true, false, false)), ExitCode::SUCCESS);
        assert!(sentinel::list_sentinels().unwrap().is_empty());
        env_scope.unset("AGENTLINUX_CATALOG_DIR");
        env_scope.unset("AGENTLINUX_STATE_DIR");
        env_scope.unset("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn adopts_present_in_window_agent_as_reused_sentinel() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        let bindir = tempdir().unwrap();
        write_catalog(cat.path());
        // Stage a stand-in binary at the canonical claude path — but the canonical
        // path is hardcoded (/home/agent/.local/bin/claude) which we can't write in
        // the sandbox. Instead, drive adopt_one against a cache whose path is a REAL
        // file we own, and a catalog entry WITHOUT a canonical map entry so the
        // is_at_managed_path heuristic (source_kind managed dir) governs. Use a
        // fresh id `rtk` (binary kind, no canonical entry) at its managed .local/bin.
        let managed_bin = bindir.path().join(".local").join("bin");
        std::fs::create_dir_all(&managed_bin).unwrap();
        let bin = managed_bin.join("rtk");
        std::fs::write(&bin, "#!/bin/sh\n").unwrap();
        let cache = cat.path().join("detect.json");
        std::fs::write(
            &cache,
            format!(
                r#"{{"agents":[{{"id":"rtk","status":"healthy","path":"{}","version":"0.42.4"}}]}}"#,
                bin.display()
            ),
        )
        .unwrap();
        std::fs::write(
            cat.path().join("catalog.json"),
            r#"{"version":"0.3.6","agents":[
                {"id":"rtk","display_name":"RTK","description":"d","source_kind":"binary",
                 "pinned_version":"0.42.4","compatibility_window":">=0.42.0 <0.43.0",
                 "install_recipe_path":"install.sh","uninstall_recipe_path":"uninstall.sh","tags":["token"]}
            ]}"#,
        )
        .unwrap();
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        env_scope.set("AGENTLINUX_DETECT_CACHE", &cache);
        env_scope.set("AGENTLINUX_AGENT_HOME", bindir.path());

        assert_eq!(
            adopt(Some("rtk"), &args(false, false, false)),
            ExitCode::SUCCESS
        );
        let s = sentinel::read_sentinel("rtk").unwrap().unwrap();
        assert_eq!(s.status.as_deref(), Some("reused"));
        assert_eq!(s.version, "0.42.4");
        assert_eq!(
            s.binary_path.as_deref(),
            Some(bin.display().to_string().as_str())
        );

        env_scope.unset("AGENTLINUX_CATALOG_DIR");
        env_scope.unset("AGENTLINUX_STATE_DIR");
        env_scope.unset("AGENTLINUX_DETECT_CACHE");
        env_scope.unset("AGENTLINUX_AGENT_HOME");
    }

    // The epoch formatter itself is `agentlinux_core::time::format_epoch_utc`,
    // covered there against leap days, the century rule and an independent
    // inverse. Two assertions from this call site added nothing it does not.
}
