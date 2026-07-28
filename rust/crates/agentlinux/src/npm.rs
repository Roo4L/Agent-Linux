//! npm.rs — the shell adapter around `npm ls -g --json` and
//! `npm view <pkg> versions --json`.
//!
//! Port of `plugin/cli/src/upgrade/npm_ls.ts` (`queryGlobalNpm` /
//! `queryNpmViewLatest`). Both run via the BUFFERED dispatcher path
//! (`dispatcher::as_user(..., stream=false, Some(30_000))`) — the 30-second
//! timeout (Open Q2) prevents a hung registry query from wedging `upgrade`
//! forever (T-56-13).
//!
//! # Pitfall 5 (buffered never-throw / npm ls exit 1 is valid JSON)
//! `npm ls -g --json` exits 1 when it has peer-dep warnings but STILL emits valid
//! JSON on stdout. `query_global_npm` intentionally parses the stdout REGARDLESS
//! of exit code and only fails when the JSON itself is unparseable (genuine npm
//! misbehavior, not a warning). The buffered dispatcher already honors the
//! never-throw contract (a non-zero exit is a valid `DispatchResult`).
//!
//! # T-56-12 (untrusted registry metadata)
//! `npm view`'s output is attacker-controlled registry metadata: it is parsed as
//! DATA (never eval'd) and version strings route through the pure
//! `resolve_latest_for` → `semver_shim` (total, no panic). A hostile `latest`
//! can't crash `upgrade` — a parse failure surfaces as an `Err`, which the caller
//! turns into a `latest=null` column.
//!
//! # Testability (DI seam)
//! Both exported functions accept an optional dispatcher matching the buffered
//! `as_user` signature. Unit tests inject a capturing/stubbing function so no sudo
//! invocation ever happens under `cargo test` (mirrors the TS `NpmDispatcher`).
//!
//! `#![allow(dead_code)]`: the public surface is consumed by Plan 03's `upgrade`
//! verb (`resolve_latest_for` feed + the INSTALLED column). The `#[cfg(test)]`
//! module exercises every item now; the allow only defers the "not yet wired into
//! a non-test caller" lint until the verb layer imports it.
#![allow(dead_code)]

use crate::catalog::FullCatalogEntry;
use crate::dispatcher::{self, DispatchResult};
use crate::recipe_env::resolve_install_user;
use agentlinux_core::divergence::resolve_latest_for;
use agentlinux_core::types::CatalogEntry as CoreCatalogEntry;
use serde::Deserialize;
use std::collections::BTreeMap;

/// The buffered npm-dispatch timeout (Open Q2) — 30 seconds, byte-identical to
/// npm_ls.ts:78,119 (`timeout: 30_000`).
const NPM_TIMEOUT_MS: u64 = 30_000;

/// Dispatcher signature — mirrors the buffered `as_user` shape (user, argv, env,
/// timeout_ms). Typed separately so unit tests inject a stub without spawning a
/// real subprocess (mirrors the TS `NpmDispatcher` type). Always buffered
/// (stream=false); the caller passes `NPM_TIMEOUT_MS`.
pub type NpmDispatcher =
    fn(user: &str, argv: &[String], env: &[(String, String)], timeout_ms: u64) -> DispatchResult;

/// The production dispatcher — the buffered `as_user` path with the npm timeout.
/// `stream=false` (buffered) is load-bearing: the streaming path would tee npm's
/// JSON to the console AND map a timeout to 124, whereas the buffered path
/// captures the JSON and maps a timeout to 1 (TS `execFile` parity).
fn real_dispatch(
    user: &str,
    argv: &[String],
    env: &[(String, String)],
    timeout_ms: u64,
) -> DispatchResult {
    dispatcher::as_user(user, argv, env, false, Some(timeout_ms))
}

/// Build the minimal npm env for `home` (npm_ls.ts `npmEnvFor`). Mirrors runner's
/// per-user derivation so `npm` resolves to the user's `~/.npm-global/bin`
/// (Pitfall 3 — `sudo -E` alone drops PATH to secure_path on Ubuntu).
fn npm_env_for(home: &str) -> Vec<(String, String)> {
    vec![
        (
            "PATH".to_string(),
            format!("{home}/.npm-global/bin:{home}/.local/bin:/usr/local/bin:/usr/bin:/bin"),
        ),
        ("HOME".to_string(), home.to_string()),
        (
            "NPM_CONFIG_PREFIX".to_string(),
            format!("{home}/.npm-global"),
        ),
        ("LANG".to_string(), "C.UTF-8".to_string()),
        ("LC_ALL".to_string(), "C.UTF-8".to_string()),
    ]
}

/// The `npm ls -g --json` shape we read — `{ dependencies: { <pkg>: { version } } }`.
#[derive(Debug, Deserialize)]
struct NpmLsShape {
    #[serde(default)]
    dependencies: Option<BTreeMap<String, NpmLsDep>>,
}

#[derive(Debug, Deserialize)]
struct NpmLsDep {
    #[serde(default)]
    version: Option<String>,
}

/// Run `npm ls -g --json --depth=0` as the configured install user and return a
/// `BTreeMap<pkg, version>` of its globally-installed npm packages. Port of
/// `queryGlobalNpm` (npm_ls.ts:72-95).
///
/// Defensive parsing per Pitfall 5:
///   (a) missing `dependencies` key (no globals) → empty map,
///   (b) missing `version` on a key → skip that entry,
///   (c) exit 1 with valid JSON (peer-dep warning) → parse anyway,
///   (d) unparseable stdout → `Err` with stderr context.
pub fn query_global_npm_with(
    dispatcher: NpmDispatcher,
) -> Result<BTreeMap<String, String>, String> {
    let user = resolve_install_user();
    let argv: Vec<String> = ["npm", "ls", "-g", "--json", "--depth=0"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let result = dispatcher(
        &user,
        &argv,
        &npm_env_for(&format!("/home/{user}")),
        NPM_TIMEOUT_MS,
    );

    // Parse the stdout REGARDLESS of exit code (Pitfall 5 — npm ls exits 1 on a
    // peer-dep warning but still emits valid JSON).
    let parsed: NpmLsShape = serde_json::from_str(&result.stdout).map_err(|_| {
        format!(
            "npm ls -g --json did not emit parseable JSON (exit {})\nstderr: {}",
            result.exit_code, result.stderr
        )
    })?;

    let mut map = BTreeMap::new();
    for (pkg, info) in parsed.dependencies.unwrap_or_default() {
        if let Some(v) = info.version {
            map.insert(pkg, v);
        }
    }
    Ok(map)
}

/// Production entry point — the real buffered dispatcher.
pub fn query_global_npm() -> Result<BTreeMap<String, String>, String> {
    query_global_npm_with(real_dispatch)
}

/// Resolve the upstream-latest version for a catalog entry via
/// `npm view <pkg> versions --json`, honoring `entry.version_constraint` through
/// `resolve_latest_for`. Only called when the user opts in via `--check-upstream`
/// / `--all-latest` (offline-default per ADR-011 / T-04-12). Port of
/// `queryNpmViewLatest` (npm_ls.ts:108-139).
///
/// `None` for non-npm entries (no single canonical "latest"). `Err` on a non-zero
/// `npm view` exit or unparseable/zero-match JSON — the upgrade caller turns any
/// `Err` into a `latestVersion: null` column.
pub fn query_npm_view_latest_with(
    entry: &FullCatalogEntry,
    dispatcher: NpmDispatcher,
) -> Result<Option<String>, String> {
    if entry.source_kind.as_deref() != Some("npm") {
        return Ok(None);
    }
    let Some(pkg) = entry.npm_package_name.as_deref() else {
        return Ok(None);
    };
    let user = resolve_install_user();
    let argv: Vec<String> = ["npm", "view", pkg, "versions", "--json"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let result = dispatcher(
        &user,
        &argv,
        &npm_env_for(&format!("/home/{user}")),
        NPM_TIMEOUT_MS,
    );
    if result.exit_code != 0 {
        return Err(format!(
            "npm view {pkg} failed (exit {}): {}",
            result.exit_code, result.stderr
        ));
    }
    // `npm view <pkg> versions --json` returns a JSON array of strings (>1
    // published) OR a single string (only 1 published). Handle both to stay
    // faithful to the npm CLI contract (npm_ls.ts:126-137).
    let raw: serde_json::Value = serde_json::from_str(&result.stdout).map_err(|_| {
        format!(
            "npm view {pkg} returned unparseable JSON:\n{}",
            result.stdout
        )
    })?;
    let versions: Vec<String> = match raw {
        serde_json::Value::Array(items) => items
            .into_iter()
            .map(|v| match v {
                serde_json::Value::String(s) => s,
                other => other.to_string(),
            })
            .collect(),
        serde_json::Value::String(s) => vec![s],
        other => vec![other.to_string()],
    };
    let core: CoreCatalogEntry = to_core_entry(entry);
    resolve_latest_for(&core, &versions)
        .map(Some)
        .map_err(|e| e.to_string())
}

/// Production entry point — the real buffered dispatcher.
pub fn query_npm_view_latest(entry: &FullCatalogEntry) -> Result<Option<String>, String> {
    query_npm_view_latest_with(entry, real_dispatch)
}

/// Project a `FullCatalogEntry` to the pure core `CatalogEntry` (via serde, so
/// field semantics stay in lockstep) — shared with the verb adapters.
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

#[cfg(test)]
mod npm_tests {
    use super::*;

    fn ok_result(stdout: &str, exit_code: i32) -> DispatchResult {
        DispatchResult {
            exit_code,
            stdout: stdout.to_string(),
            stderr: String::new(),
            streamed: false,
        }
    }

    fn entry_npm(id: &str, pkg: &str, constraint: Option<&str>) -> FullCatalogEntry {
        let mut json = serde_json::json!({
            "id": id,
            "display_name": "X",
            "description": "d",
            "source_kind": "npm",
            "npm_package_name": pkg,
            "pinned_version": "1.0.0",
            "install_recipe_path": "install.sh",
            "uninstall_recipe_path": "uninstall.sh",
        });
        if let Some(c) = constraint {
            json["version_constraint"] = serde_json::json!(c);
        }
        serde_json::from_value(json).unwrap()
    }

    // Pitfall 5: npm ls exits 1 (peer-dep warning) but still emits valid JSON —
    // query_global_npm parses it anyway and returns a non-empty map.
    #[test]
    fn query_global_npm_parses_json_on_nonzero_exit() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            ok_result(
                r#"{"dependencies":{"@openai/codex":{"version":"1.2.3"},"gsd-core":{"version":"1.37.1"}}}"#,
                1, // non-zero: peer-dep warning
            )
        }
        let map = query_global_npm_with(stub).unwrap();
        assert_eq!(map.get("@openai/codex").map(String::as_str), Some("1.2.3"));
        assert_eq!(map.get("gsd-core").map(String::as_str), Some("1.37.1"));
        assert_eq!(map.len(), 2, "parsed version list must be non-empty");
    }

    // Missing `dependencies` (no globals) → empty map, not an error.
    #[test]
    fn query_global_npm_empty_dependencies_is_empty_map() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            ok_result(r#"{"name":"root","version":"1.0.0"}"#, 0)
        }
        assert!(query_global_npm_with(stub).unwrap().is_empty());
    }

    // Unparseable stdout → Err with stderr context.
    #[test]
    fn query_global_npm_unparseable_is_err() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            DispatchResult {
                exit_code: 1,
                stdout: "not json at all".to_string(),
                stderr: "boom".to_string(),
                streamed: false,
            }
        }
        let err = query_global_npm_with(stub).unwrap_err();
        assert!(err.contains("did not emit parseable JSON"), "got: {err}");
    }

    // The buffered timeout is passed as 30_000 (Open Q2) — assert the call-site
    // timeout via a capturing stub.
    #[test]
    fn query_global_npm_passes_30s_buffered_timeout() {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEEN: AtomicU64 = AtomicU64::new(0);
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], t: u64) -> DispatchResult {
            SEEN.store(t, Ordering::SeqCst);
            ok_result(r#"{"dependencies":{}}"#, 0)
        }
        let _ = query_global_npm_with(stub).unwrap();
        assert_eq!(
            SEEN.load(Ordering::SeqCst),
            30_000,
            "npm buffered timeout must be 30_000"
        );
        assert_eq!(NPM_TIMEOUT_MS, 30_000);
    }

    // query_npm_view_latest: a JSON array feeds resolve_latest_for (no constraint
    // → newest).
    #[test]
    fn query_npm_view_latest_array_resolves_newest() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            ok_result(r#"["1.0.0","1.1.0","1.2.0","2.0.0"]"#, 0)
        }
        let e = entry_npm("codex", "@openai/codex", None);
        assert_eq!(
            query_npm_view_latest_with(&e, stub).unwrap().as_deref(),
            Some("2.0.0")
        );
    }

    // A single published version comes back as a bare string, not an array.
    #[test]
    fn query_npm_view_latest_single_string() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            ok_result(r#""3.1.4""#, 0)
        }
        let e = entry_npm("codex", "@openai/codex", None);
        assert_eq!(
            query_npm_view_latest_with(&e, stub).unwrap().as_deref(),
            Some("3.1.4")
        );
    }

    // version_constraint respected via resolve_latest_for.
    #[test]
    fn query_npm_view_latest_honors_constraint() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            ok_result(r#"["1.0.0","1.1.0","1.2.0","2.0.0"]"#, 0)
        }
        let e = entry_npm("codex", "@openai/codex", Some("^1.0"));
        assert_eq!(
            query_npm_view_latest_with(&e, stub).unwrap().as_deref(),
            Some("1.2.0")
        );
    }

    // Non-npm entry → Ok(None) (script-kind has no canonical npm latest).
    #[test]
    fn query_npm_view_latest_non_npm_is_none() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            panic!("dispatcher must not run for a non-npm entry")
        }
        let mut e = entry_npm("claude-code", "unused", None);
        e.source_kind = Some("script".to_string());
        assert_eq!(query_npm_view_latest_with(&e, stub).unwrap(), None);
    }

    // A non-zero `npm view` exit → Err (the caller turns it into latest=null).
    #[test]
    fn query_npm_view_latest_nonzero_exit_is_err() {
        fn stub(_u: &str, _a: &[String], _e: &[(String, String)], _t: u64) -> DispatchResult {
            DispatchResult {
                exit_code: 1,
                stdout: String::new(),
                stderr: "E404".to_string(),
                streamed: false,
            }
        }
        let e = entry_npm("codex", "@openai/codex", None);
        let err = query_npm_view_latest_with(&e, stub).unwrap_err();
        assert!(err.contains("failed (exit 1)"), "got: {err}");
    }
}
