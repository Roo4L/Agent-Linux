//! cmd/adopt.rs — `agentlinux adopt [name] [--all]` (AL-61, AL-62).
//!
//! Byte-for-byte port of `plugin/cli/src/commands/adopt.ts`. Records pre-existing,
//! reuse-eligible agents into `status:"reused"` sentinels WITHOUT installing
//! anything — it dispatches NO recipe, downloads nothing, remediates nothing. It
//! only records reality the host already holds so `list` stops reporting present
//! tools as not-installed.
//!
//! # The pure gate + adapter `statSync` seam (RESEARCH §Cache-Read Adapter)
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
use crate::{agent_home, canonical_path, GSD_SYSTEM_PATH};
use agentlinux_core::detect_gates::{remediate_gate, reuse_gate, RemediateReason};
use agentlinux_core::types::CatalogEntry as CoreCatalogEntry;
use serde::Serialize;
use std::process::ExitCode;

use crate::cli::AdoptArgs;

const EX_USAGE: u8 = 64;

/// The adopt verdict per entry — mirrors the TS `AdoptAction` union
/// (adopt.ts:25) + `AdoptResult` (adopt.ts:27-32). Serialized for `--json`.
#[derive(Debug, Clone, Serialize)]
struct AdoptResult {
    id: String,
    action: String, // "adopted" | "already-managed" | "skipped" | "migrate-available"
    #[serde(skip_serializing_if = "Option::is_none")]
    version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    reason: Option<String>,
}

fn to_core_entry(e: &FullCatalogEntry) -> CoreCatalogEntry {
    let v = serde_json::json!({
        "id": e.id,
        "pinned_version": e.pinned_version,
        "version_constraint": e.version_constraint,
        "npm_package_name": e.npm_package_name,
        "compatibility_window": e.compatibility_window,
        "tags": e.tags,
        "source_kind": e.source_kind,
    });
    serde_json::from_value(v).expect("full→core catalog entry projection")
}

/// Adopt one entry — port of `adoptOne` (adopt.ts:34-76).
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

    let core_entry = to_core_entry(entry);
    let home = agent_home();
    let canonical = canonical_path(&entry.id);

    // tryReuse = the PURE reuse_gate + the host statSync re-validation HERE.
    let detected = crate::cache::read_cached_agent_by_id(&entry.id);
    let reuse_hit = detected
        .as_ref()
        .and_then(|d| reuse_gate(&core_entry, d, canonical, GSD_SYSTEM_PATH, &home));
    let reuse_hit = reuse_hit.filter(|c| {
        // ADAPTER statSync re-validation (detect.ts:183-188): confirm the binary
        // still exists at install time. Stale-cache safety.
        std::fs::metadata(&c.path)
            .map(|m| m.is_file())
            .unwrap_or(false)
    });

    let Some(hit) = reuse_hit else {
        // Not reuse-eligible. AL-62: distinguish a migration candidate (healthy at
        // a non-canonical path) from a plain skip via the PURE remediate_gate.
        let rem = detected
            .as_ref()
            .and_then(|d| remediate_gate(&core_entry, d, canonical, GSD_SYSTEM_PATH));
        if let Some(rem) = rem {
            if rem.reason == RemediateReason::PathMismatch {
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

    // Write a status:"reused" sentinel (adopt.ts:62-74). Never dispatches a
    // recipe. `binary_path`/`detected_source` mirror the TS ReuseHit.
    let now = now_iso8601();
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

/// `agentlinux adopt [name]` body. Port of `adoptCmd` (adopt.ts:78-130).
#[must_use]
pub fn adopt(name: Option<&str>, opts: &AdoptArgs) -> ExitCode {
    // Hot path (validate:false) — a partially-invalid catalog shouldn't block
    // adopting the valid entries.
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, false) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(1);
        }
    };

    let targets: Vec<FullCatalogEntry> = if let Some(name) = name {
        let Some(entry) = agents.iter().find(|a| a.id == name) else {
            let available = agents
                .iter()
                .filter(|a| !a.test_only)
                .map(|a| a.id.as_str())
                .collect::<Vec<_>>()
                .join(", ");
            eprintln!("agentlinux: no such agent in catalog: {name}");
            eprintln!("  available: {available}");
            return ExitCode::from(EX_USAGE);
        };
        if entry.test_only && !opts.include_test {
            eprintln!("agentlinux: {name} is a test-only entry; pass --include-test to adopt");
            return ExitCode::from(EX_USAGE);
        }
        vec![entry.clone()]
    } else if opts.all {
        agents
            .into_iter()
            .filter(|a| opts.include_test || !a.test_only)
            .collect()
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
        match r.action.as_str() {
            "adopted" => println!(
                "[ADOPT] {}: adopted pre-existing install {} (status=reused — managed by agentlinux upgrade/remove)",
                r.id,
                r.version.as_deref().unwrap_or("")
            ),
            "already-managed" => println!(
                "{}: already managed at {}; no-op",
                r.id,
                r.version.as_deref().unwrap_or("")
            ),
            "migrate-available" => println!(
                "[MIGRATE] {}: {}",
                r.id,
                r.reason.as_deref().unwrap_or("")
            ),
            _ => println!(
                "{}: nothing to adopt — {}",
                r.id,
                r.reason.as_deref().unwrap_or("")
            ),
        }
    }
    ExitCode::SUCCESS
}

/// A UTC ISO-8601 second-resolution timestamp (`YYYY-MM-DDTHH:MM:SSZ`) matching
/// the TS `new Date().toISOString()` shape the sentinel records. Computed from the
/// unix epoch without a chrono dep (the bin stays dependency-light).
fn now_iso8601() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format_epoch_utc(secs)
}

/// Format unix seconds as `YYYY-MM-DDTHH:MM:SSZ` (proleptic Gregorian, UTC).
fn format_epoch_utc(secs: u64) -> String {
    let days = secs / 86_400;
    let rem = secs % 86_400;
    let (hh, mm, ss) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    // Civil-from-days (Howard Hinnant's algorithm), epoch 1970-01-01.
    let z = days as i64 + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    format!("{year:04}-{m:02}-{d:02}T{hh:02}:{mm:02}:{ss:02}Z")
}

#[cfg(test)]
mod adopt_tests {
    use super::*;
    use std::sync::Mutex;
    use tempfile::tempdir;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

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
        let _g = ENV_LOCK.lock().unwrap();
        let cat = tempdir().unwrap();
        write_catalog(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        assert_eq!(
            adopt(None, &args(false, false, false)),
            ExitCode::from(EX_USAGE)
        );
        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
    }

    #[test]
    fn unknown_agent_exits_64() {
        let _g = ENV_LOCK.lock().unwrap();
        let cat = tempdir().unwrap();
        write_catalog(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        assert_eq!(
            adopt(Some("ghost"), &args(false, false, false)),
            ExitCode::from(EX_USAGE)
        );
        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
    }

    #[test]
    fn test_only_without_include_test_exits_64() {
        let _g = ENV_LOCK.lock().unwrap();
        let cat = tempdir().unwrap();
        write_catalog(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        assert_eq!(
            adopt(Some("test-dummy"), &args(false, false, false)),
            ExitCode::from(EX_USAGE)
        );
        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
    }

    #[test]
    fn greenfield_all_is_a_noop_exit_0() {
        let _g = ENV_LOCK.lock().unwrap();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
        std::env::set_var("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");
        // No cache → nothing adopted, no sentinel written, exit 0.
        assert_eq!(adopt(None, &args(true, false, false)), ExitCode::SUCCESS);
        assert!(sentinel::list_sentinels().unwrap().is_empty());
        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn adopts_present_in_window_agent_as_reused_sentinel() {
        let _g = ENV_LOCK.lock().unwrap();
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
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
        std::env::set_var("AGENTLINUX_DETECT_CACHE", &cache);
        std::env::set_var("AGENTLINUX_AGENT_HOME", bindir.path());

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

        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
        std::env::remove_var("AGENTLINUX_AGENT_HOME");
    }

    #[test]
    fn epoch_formatting_matches_known_timestamp() {
        // 2026-07-28T00:00:00Z = 1785196800 (sanity of the civil-from-days path).
        assert_eq!(format_epoch_utc(1_785_196_800), "2026-07-28T00:00:00Z");
        assert_eq!(format_epoch_utc(0), "1970-01-01T00:00:00Z");
    }
}
