//! cmd/pin.rs — `agentlinux pin <spec>` (CLI-07, ADR-011).
//!
//! Byte-for-byte port of `plugin/cli/src/commands/pin.ts`. A STATE-ONLY sentinel
//! mutation — it NEVER dispatches a recipe. Parses the spec via the PURE
//! `parse_pin_spec` (pin_spec.rs), looks the agent up in the catalog, reads its
//! sentinel, and writes the pin target / sticky flag, printing the exact literal.
//!
//! # Guard (CLI-05)
//! The invoker guard runs ONCE in `main::dispatch` (mirroring the TS `preAction`
//! hook, index.ts:34-36) before this body — so pin does NOT re-guard. This matches
//! the TS, where `guardAgentUser` is a preAction hook, not a per-command call.
//!
//! # Exit map
//! - malformed spec → 64 (print `PinSpecError` message to stderr; the strings are
//!   ALREADY ported into `PinSpecError` — pin.ts:82 prints `err.message`).
//! - unknown agent → 64.
//! - not installed → 1 (route the present-hint sentences to STDERR via the pure
//!   `presence_gate`).

use crate::catalog::{self, FullCatalogEntry};
use crate::sentinel;
use crate::{agent_home, canonical_path, GSD_SYSTEM_PATH};
use agentlinux_core::detect_gates::presence_gate;
use agentlinux_core::pin_spec::{parse_pin_spec, PinTarget};
use agentlinux_core::types::CatalogEntry as CoreCatalogEntry;
use std::process::ExitCode;

const EX_USAGE: u8 = 64;

/// Project a `FullCatalogEntry` to the pure core `CatalogEntry` (via serde so
/// field semantics stay in lockstep). Shared shape with list.rs's projection.
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

/// `agentlinux pin <spec>` body. Port of `pinCmd` (pin.ts:76-168).
#[must_use]
pub fn pin(spec: &str) -> ExitCode {
    // 1. Parse the spec (PURE). On error, print the message + exit 64 — the
    //    message strings are byte-identical to the TS `throw new Error(...)`.
    let parsed = match parse_pin_spec(spec) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(EX_USAGE);
        }
    };

    // 2. Catalog lookup (validate:true — pin is a mutation path, pin.ts:90).
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, true) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(1);
        }
    };
    let Some(entry) = agents.iter().find(|a| a.id == parsed.name) else {
        let available = agents
            .iter()
            .filter(|a| !a.test_only)
            .map(|a| a.id.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        eprintln!("agentlinux: no such agent in catalog: {}", parsed.name);
        eprintln!("  available: {available}");
        return ExitCode::from(EX_USAGE);
    };

    // 3. Sentinel must exist — pin is intent-about-existing-install, not a
    //    pre-declaration.
    let existing = match sentinel::read_sentinel(&entry.id) {
        Ok(Some(s)) => s,
        Ok(None) => return pin_not_installed(entry),
        Err(e) => {
            eprintln!("agentlinux: failed to read sentinel for {}: {e}", entry.id);
            return ExitCode::from(1);
        }
    };

    // 4. Compute the next sentinel state (partial update: preserve id +
    //    installed_at + all other fields; only source/sticky/version mutate).
    let mut next = existing;
    match parsed.target {
        PinTarget::Curated => {
            next.source = "curated".to_string();
            next.sticky = false;
            println!("{}: pin cleared (source=curated, sticky=false)", entry.id);
        }
        PinTarget::Latest => {
            next.source = "latest".to_string();
            next.sticky = true;
            println!(
                "{}: pinned to follow upstream latest (sticky=true); next 'upgrade --all-latest' resolves",
                entry.id
            );
        }
        PinTarget::Version(version) => {
            next.source = "pinned".to_string();
            next.sticky = true;
            next.version = version.clone();
            println!("{}: pinned to {version} (sticky=true)", entry.id);
        }
    }

    if let Err(e) = sentinel::write_sentinel(&next) {
        eprintln!("agentlinux: failed to write sentinel for {}: {e}", entry.id);
        return ExitCode::from(1);
    }
    ExitCode::SUCCESS
}

/// The not-installed branch (pin.ts:107-137): route the present-hint sentences to
/// STDERR via the pure `presence_gate`, then exit 1.
fn pin_not_installed(entry: &FullCatalogEntry) -> ExitCode {
    let core_entry = to_core_entry(entry);
    let home = agent_home();
    let present = crate::cache::read_cached_agent_by_id(&entry.id).and_then(|detected| {
        presence_gate(
            &core_entry,
            &detected,
            canonical_path(&entry.id),
            GSD_SYSTEM_PATH,
            &home,
        )
    });
    match present {
        Some(hit) if hit.adoptable => {
            eprintln!(
                "agentlinux: {} is present but not managed — run 'agentlinux adopt {}' first, then pin",
                entry.id, entry.id
            );
        }
        Some(hit) if hit.canonical => {
            eprintln!(
                "agentlinux: {} is present but out of the compatibility window — run 'agentlinux install {}' to bring it under management, then pin",
                entry.id, entry.id
            );
        }
        Some(hit) => {
            eprintln!(
                "agentlinux: {} is present at {} (not the managed path) — run 'agentlinux install {}' to migrate it under management, then pin",
                entry.id, hit.path, entry.id
            );
        }
        None => {
            eprintln!(
                "agentlinux: {} is not installed — run 'agentlinux install {}' first",
                entry.id, entry.id
            );
        }
    }
    ExitCode::from(1)
}

#[cfg(test)]
mod pin_tests {
    use super::*;
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

    #[test]
    fn malformed_spec_exits_64_with_ported_message() {
        // No `=` → PinSpecError::Usage. The message is byte-identical to the TS.
        assert_eq!(pin("garbage"), ExitCode::from(EX_USAGE));
        // Confirm the ported message text matches the TS throw string.
        let err = parse_pin_spec("garbage").unwrap_err();
        assert!(err.to_string().contains("expected '<name>=<target>'"));
    }

    #[test]
    fn latest_then_curated_round_trip_mutates_sentinel_only() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());

        // Seed an installed sentinel.
        let mut s = Sentinel::new("test-dummy".into(), "0.0.1".into(), "curated".into(), false);
        s.installed_at = Some("2026-07-28T00:00:00Z".into());
        sentinel::write_sentinel(&s).unwrap();

        // pin=latest → sticky=true, source=latest, version preserved.
        assert_eq!(pin("test-dummy=latest"), ExitCode::SUCCESS);
        let after = sentinel::read_sentinel("test-dummy").unwrap().unwrap();
        assert!(after.sticky);
        assert_eq!(after.source, "latest");
        assert_eq!(after.version, "0.0.1");
        assert_eq!(after.installed_at.as_deref(), Some("2026-07-28T00:00:00Z"));

        // pin=curated → clears sticky.
        assert_eq!(pin("test-dummy=curated"), ExitCode::SUCCESS);
        let after = sentinel::read_sentinel("test-dummy").unwrap().unwrap();
        assert!(!after.sticky);
        assert_eq!(after.source, "curated");

        // pin=<semver> → source=pinned, version updated.
        assert_eq!(pin("test-dummy=1.2.3"), ExitCode::SUCCESS);
        let after = sentinel::read_sentinel("test-dummy").unwrap().unwrap();
        assert!(after.sticky);
        assert_eq!(after.source, "pinned");
        assert_eq!(after.version, "1.2.3");

        env_scope.unset("AGENTLINUX_CATALOG_DIR");
        env_scope.unset("AGENTLINUX_STATE_DIR");
    }

    #[test]
    fn unknown_agent_exits_64() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        write_catalog(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        assert_eq!(pin("nonexistent=latest"), ExitCode::from(EX_USAGE));
        env_scope.unset("AGENTLINUX_CATALOG_DIR");
    }

    #[test]
    fn not_installed_exits_1() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");
        // Known agent, but no sentinel and no detect cache → exit 1.
        assert_eq!(pin("test-dummy=latest"), ExitCode::from(1));
        env_scope.unset("AGENTLINUX_CATALOG_DIR");
        env_scope.unset("AGENTLINUX_STATE_DIR");
        env_scope.unset("AGENTLINUX_DETECT_CACHE");
    }
}
