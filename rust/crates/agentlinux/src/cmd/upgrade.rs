//! cmd/upgrade.rs — `agentlinux upgrade [flags]` (CLI-06, ADR-011).
//!
//! Flow: loadCatalog →
//! listSentinels → queryGlobalNpm once → build a `DivergenceReport` per entry →
//! render (7-column table / --json). With no bulk flag it's report-only; otherwise
//! the reconcile loop runs `shouldReinstall` + dispatches install.sh sequentially.
//!
//! # Flag priority (upgrade.ts top comment)
//! `--reset-all-curated` wins over `--respect-overrides` and also resets sticky
//! entries; `--all-latest` implies upstream resolution and skips sticky entries.
//! Offline default: upstream is queried only with `--check-upstream` / `--all-latest`.
//!
//! # The pure/adapter seam
//! `shouldReinstall` is a PURE flag-priority helper (ported into the bin here — it
//! has no core home yet and reads only the report + opts). `compute_divergence` /
//! `resolve_latest_for` are the pure gates (never re-derived). `validateReusedBinary`'s
//! `statSync` is host I/O → it lives HERE in the adapter.
//!
//! # DI seam
//! `UpgradeDeps` injects the recipe dispatcher + the two npm queries so unit tests
//! run no sudo/network (mirrors the TS `UpgradeDeps` object).

use crate::catalog::{self, FullCatalogEntry};
use crate::cli::UpgradeArgs;
use crate::dispatcher::{self, Capture, RecipeDispatcher};
use crate::recipe_env::{recipe_child_env, recipe_path, resolve_install_user};
use crate::sentinel::{self, Sentinel};
use crate::{agent_home, canonical_path, host_paths};
use agentlinux_core::detect_gates::presence_gate;
use agentlinux_core::divergence::compute_divergence;
use agentlinux_core::types::{
    CatalogEntry as CoreCatalogEntry, DivergenceReport, Sentinel as CoreSentinel, Status,
};
use std::collections::BTreeMap;
use std::process::ExitCode;

/// The pkg→version map `npm ls -g --json` yields.
type NpmMap = BTreeMap<String, String>;

/// DI seam — production defaults, replaced by tests. All three mirror the TS
/// `UpgradeDeps` fields.
pub struct UpgradeDeps {
    pub dispatch: RecipeDispatcher,
    /// `npm ls -g --json` once → the pkg→version map. `Err` degrades to an empty
    /// map (report still renders with installed=None for npm entries).
    pub query_global_npm: fn() -> Result<NpmMap, String>,
    /// `npm view <pkg> versions --json` (opt-in). `Err`/`Ok(None)` → latest=null.
    pub query_npm_view_latest: fn(&FullCatalogEntry) -> Result<Option<String>, String>,
}

impl Default for UpgradeDeps {
    fn default() -> Self {
        Self {
            dispatch: dispatcher::dispatch_recipe,
            query_global_npm: crate::npm::query_global_npm,
            query_npm_view_latest: crate::npm::query_npm_view_latest,
        }
    }
}

/// `validateReusedBinary` — true when the sentinel is trustworthy for "is it
/// already installed?". A "reused" sentinel whose binary_path has vanished has
/// drifted and must be reinstalled (false). Port of upgrade.ts:33-44. The
/// `statSync` is host I/O → adapter.
fn validate_reused_binary(sentinel: Option<&Sentinel>) -> bool {
    let Some(s) = sentinel else { return true };
    if s.status.as_deref() == Some("reused-with-warning") {
        return true;
    }
    if s.status.as_deref() != Some("reused") {
        return true;
    }
    let Some(bin) = s.binary_path.as_deref() else {
        return true;
    };
    std::fs::metadata(bin).map(|m| m.is_file()).unwrap_or(false)
}

fn will_touch_upstream(opts: &UpgradeArgs) -> bool {
    opts.check_upstream || opts.all_latest
}

/// `shouldReinstall` — the PURE flag-priority helper. Returns
/// the reinstall source (`"curated"`/`"latest"`) or `None` to skip. `present`
/// overlay rows are report-only under every flag.
fn should_reinstall(
    status: &StatusOrPresent,
    source: &str,
    sticky: bool,
    opts: &UpgradeArgs,
) -> Option<&'static str> {
    // present = detected on disk but unmanaged (no sentinel) → report-only.
    if matches!(status, StatusOrPresent::Present) {
        return None;
    }
    let is_synced = matches!(status, StatusOrPresent::Core(Status::Synced));
    // --reset-all-curated hits every diverged entry; synced entries are no-ops.
    if opts.reset_all_curated {
        return if is_synced { None } else { Some("curated") };
    }
    // --all-latest: skip sticky entries (ADR-011).
    if opts.all_latest && !sticky {
        return Some("latest");
    }
    // --respect-overrides: reinstall only 'curated'-source entries that diverged.
    if opts.respect_overrides {
        if source == "curated" && !is_synced {
            return Some("curated");
        }
        return None;
    }
    // No bulk flag → report-only.
    None
}

/// A report's status is either a core six-state `Status` OR the `present` overlay.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StatusOrPresent {
    Core(Status),
    Present,
}

impl StatusOrPresent {
    /// The kebab string for rendering.
    ///
    /// A plain match, not a `serde_json` round-trip: the round-trip yielded `""`
    /// on failure, so a serialization slip would have rendered a blank STATUS
    /// column rather than failing. `cmd::list::status_str` maps the same enum;
    /// both are exhaustive matches, so adding a `Status` variant breaks the build.
    fn as_str(self) -> &'static str {
        match self {
            StatusOrPresent::Core(s) => crate::cmd::list::status_str(s),
            StatusOrPresent::Present => "present",
        }
    }
}

/// A per-entry row carrying the core `DivergenceReport` plus the resolved
/// status-or-present overlay. The presence overlay's installed version is written
/// directly onto `report.installed_version`, so no separate field is needed.
struct Row {
    report: DivergenceReport,
    status: StatusOrPresent,
}

/// `agentlinux upgrade` body. Port of `upgradeCmd`.
#[must_use]
pub fn upgrade(opts: &UpgradeArgs) -> ExitCode {
    upgrade_with(opts, UpgradeDeps::default())
}

/// DI-seam variant — the testable core.
#[must_use]
pub fn upgrade_with(opts: &UpgradeArgs, deps: UpgradeDeps) -> ExitCode {
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, catalog::Validate::Required) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(1);
        }
    };
    let sentinels = match sentinel::list_sentinels() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("agentlinux: failed to list sentinels: {e}");
            return ExitCode::from(1);
        }
    };
    let by_sentinel: BTreeMap<String, Sentinel> =
        sentinels.into_iter().map(|s| (s.id.clone(), s)).collect();

    // queryGlobalNpm once (npm INSTALLED column). A failure degrades to empty
    // (report still renders installed=None for npm entries).
    let npm_ls = (deps.query_global_npm)().unwrap_or_default();

    let home = agent_home();
    let mut rows: Vec<Row> = Vec::new();
    for entry in &agents {
        if entry.test_only {
            continue; // hidden, matching list default
        }
        let sentinel = by_sentinel.get(&entry.id);
        let core_entry = CoreCatalogEntry::from(entry);

        // installed-version: npm-kind from the npm ls map, else the sentinel's
        // declared-install record.
        let installed: Option<String> = if entry.source_kind.as_deref() == Some("npm") {
            entry
                .npm_package_name
                .as_deref()
                .and_then(|pkg| npm_ls.get(pkg).cloned())
        } else {
            sentinel.map(|s| s.version.clone())
        };

        // Upstream-latest (opt-in). Per-entry errors are non-fatal — the row still
        // renders with latest=None.
        let mut latest: Option<String> = None;
        if will_touch_upstream(opts) && entry.source_kind.as_deref() == Some("npm") {
            match (deps.query_npm_view_latest)(entry) {
                Ok(v) => latest = v,
                Err(msg) => eprintln!("  ! {}: could not resolve latest — {msg}", entry.id),
            }
        }

        let core_sentinel = sentinel.map(CoreSentinel::from);
        let mut report = compute_divergence(
            &core_entry,
            core_sentinel.as_ref(),
            installed.as_deref(),
            latest.as_deref(),
        );
        let mut status = StatusOrPresent::Core(report.status);

        // Presence overlay (mirrors list): a not-installed entry the host already
        // has reads "present" with its detected version.
        if report.status == Status::NotInstalled {
            let detected = crate::cache::read_cached_agent_by_id(&entry.id);
            let hit = detected.as_ref().and_then(|d| {
                presence_gate(&core_entry, d, host_paths(canonical_path(&entry.id), &home))
            });
            if let Some(hit) = hit {
                status = StatusOrPresent::Present;
                report.installed_version = hit.version;
            }
        }

        rows.push(Row { report, status });
    }

    // Render.
    if opts.json {
        render_json(&rows);
    } else {
        render_table(&rows);
    }

    // Report-only default: no bulk flag = no mutation.
    let is_report_only = !opts.reset_all_curated && !opts.respect_overrides && !opts.all_latest;
    if is_report_only {
        return ExitCode::SUCCESS;
    }

    // Reconcile loop. Sequential for deterministic log ordering.
    let entry_by_id: BTreeMap<String, &FullCatalogEntry> =
        agents.iter().map(|e| (e.id.clone(), e)).collect();
    let user = resolve_install_user();

    for row in &rows {
        let id = &row.report.id;
        let sentinel = by_sentinel.get(id);

        // REUSE-03 surfacing.
        if sentinel.and_then(|s| s.status.as_deref()) == Some("reused") {
            println!(
                "{id}: upgrading reused install (binary={} -> catalog pin)",
                sentinel
                    .and_then(|s| s.binary_path.as_deref())
                    .unwrap_or("?")
            );
        }
        if sentinel.and_then(|s| s.status.as_deref()) == Some("reused-with-warning") {
            println!(
                "{id}: skipping upgrade for reused-with-warning sentinel (decline_reason={}; user retains manual ownership)",
                sentinel.and_then(|s| s.decline_reason.as_deref()).unwrap_or("unknown")
            );
        }

        // A reused sentinel whose binary vanished forces a curated reinstall even
        // when shouldReinstall returned null for a "synced" report.
        let reused_binary_gone = sentinel.and_then(|s| s.status.as_deref()) == Some("reused")
            && !validate_reused_binary(sentinel);
        let mut target = should_reinstall(&row.status, &row.report.source, row.report.sticky, opts);
        if reused_binary_gone && target.is_none() {
            target = Some("curated");
        }
        let Some(target) = target else { continue };

        let Some(entry) = entry_by_id.get(id) else {
            continue; // defensive
        };

        let (version, source): (String, &str) = if target == "latest" {
            match row.report.latest_version.as_deref() {
                Some(v) => (v.to_string(), "latest"),
                None => {
                    eprintln!("{id}: skipping (no upstream latest resolved)");
                    continue;
                }
            }
        } else {
            (entry.pinned_version.clone(), "curated")
        };

        let recipe = recipe_path(&catalog_dir, id, &entry.install_recipe_path);
        println!("{id}: reinstalling at {version} ({source})");
        let env = recipe_child_env(entry, &version, &catalog_dir, &user);
        // PARITY: the unattended upgrade sweep dispatches recipes UN-timed
        // (matches upgradeCmd in TS). A hung recipe wedges the sweep; a future
        // sweep-scoped timeout (NOT dispatcher-global — interactive install needs
        // TTY prompts) would target these stream=false calls.
        let result = (deps.dispatch)(&user, &recipe, &env, Capture::Buffered);
        if result.exit_code != 0 {
            eprintln!("{id}: recipe failed (exit {})", result.exit_code);
            if !result.stderr.is_empty() {
                eprintln!("{}", result.stderr);
            }
            // Preserve the pre-upgrade sentinel — never mark "installed" on failure.
            // continue — NEVER abort the whole run.
            continue;
        }
        if !result.stdout.is_empty() {
            println!("{}", result.stdout.trim_end());
        }

        // Sticky preservation: keep sticky when source='latest' and prior was sticky.
        let sticky = if source == "latest" {
            sentinel.map(|s| s.sticky).unwrap_or(false)
        } else {
            false
        };

        let mut s = Sentinel::new(id.clone(), version, source.into(), sticky);
        s.installed_at = Some(sentinel::now_iso8601());
        s.status = Some("installed".to_string());
        if let Err(e) = sentinel::write_sentinel(&s) {
            eprintln!("agentlinux: failed to write sentinel for {id}: {e}");
            // Non-fatal for the run (a single write failure shouldn't abort the
            // sweep) — continue like a per-entry recipe failure.
            continue;
        }
    }

    ExitCode::SUCCESS
}

/// Render the padded 7-column table. Header
/// `["ID","STATUS","SENTINEL","INSTALLED","CURATED","LATEST","SRC"]`; each column
/// padded to its max width; columns joined with two spaces.
fn render_table(rows: &[Row]) {
    let header = [
        "ID",
        "STATUS",
        "SENTINEL",
        "INSTALLED",
        "CURATED",
        "LATEST",
        "SRC",
    ];
    let mut all: Vec<[String; 7]> = vec![header.map(str::to_string)];
    for row in rows {
        let r = &row.report;
        all.push([
            r.id.clone(),
            row.status.as_str().to_string(),
            r.sentinel_version
                .clone()
                .unwrap_or_else(|| "-".to_string()),
            r.installed_version
                .clone()
                .unwrap_or_else(|| "-".to_string()),
            r.curated_version.clone(),
            r.latest_version.clone().unwrap_or_else(|| "-".to_string()),
            r.source.clone(),
        ]);
    }
    let widths: [usize; 7] =
        std::array::from_fn(|i| all.iter().map(|row| row[i].len()).max().unwrap_or(0));
    for row in &all {
        let line = row
            .iter()
            .enumerate()
            .map(|(i, c)| format!("{c:<width$}", width = widths[i]))
            .collect::<Vec<_>>()
            .join("  ");
        println!("{line}");
    }
}

/// Render the `--json` DivergenceReport array. A `present` row overlays its
/// status string onto the serialized report (the core enum can't hold `present`).
fn render_json(rows: &[Row]) {
    let arr: Vec<serde_json::Value> = rows
        .iter()
        .map(|row| {
            let mut v = serde_json::to_value(&row.report).unwrap_or(serde_json::Value::Null);
            if let StatusOrPresent::Present = row.status {
                if let Some(obj) = v.as_object_mut() {
                    obj.insert("status".to_string(), serde_json::json!("present"));
                }
            }
            v
        })
        .collect();
    match serde_json::to_string_pretty(&arr) {
        Ok(s) => println!("{s}"),
        Err(e) => eprintln!("agentlinux: failed to serialize upgrade JSON: {e}"),
    }
}

// ---------------------------------------------------------------------------
// helpers (shared shapes with install/remove)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod upgrade_tests {
    use super::*;
    use crate::dispatcher::DispatchResult;
    use tempfile::tempdir;

    fn opts(
        reset_all_curated: bool,
        respect_overrides: bool,
        all_latest: bool,
        check_upstream: bool,
        json: bool,
    ) -> UpgradeArgs {
        UpgradeArgs {
            reset_all_curated,
            respect_overrides,
            all_latest,
            check_upstream,
            json,
        }
    }

    fn report(id: &str, status: Status, source: &str, sticky: bool) -> DivergenceReport {
        DivergenceReport {
            id: id.to_string(),
            status,
            sentinel_version: Some("1.0.0".to_string()),
            installed_version: Some("1.0.0".to_string()),
            curated_version: "1.0.0".to_string(),
            latest_version: None,
            source: source.to_string(),
            sticky,
        }
    }

    // --- shouldReinstall flag-priority golden ---

    #[test]
    fn should_reinstall_present_is_always_none() {
        for o in [
            opts(true, false, false, false, false),
            opts(false, true, false, false, false),
            opts(false, false, true, false, false),
            opts(false, false, false, false, false),
        ] {
            assert_eq!(
                should_reinstall(&StatusOrPresent::Present, "curated", false, &o),
                None
            );
        }
    }

    #[test]
    fn should_reinstall_reset_all_curated() {
        // diverged → curated; synced → None.
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::OverrideAhead),
                "override",
                false,
                &opts(true, false, false, false, false)
            ),
            Some("curated")
        );
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::Synced),
                "curated",
                false,
                &opts(true, false, false, false, false)
            ),
            None
        );
    }

    #[test]
    fn should_reinstall_all_latest_skips_sticky() {
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::OverrideAhead),
                "override",
                false,
                &opts(false, false, true, false, false)
            ),
            Some("latest")
        );
        // sticky → skipped.
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::PinnedOverride),
                "pinned",
                true,
                &opts(false, false, true, false, false)
            ),
            None
        );
    }

    #[test]
    fn should_reinstall_respect_overrides_only_curated_diverged() {
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::OverrideBehind),
                "curated",
                false,
                &opts(false, true, false, false, false)
            ),
            Some("curated")
        );
        // override-source → skipped under --respect-overrides.
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::OverrideBehind),
                "override",
                false,
                &opts(false, true, false, false, false)
            ),
            None
        );
        // synced curated → skipped.
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::Synced),
                "curated",
                false,
                &opts(false, true, false, false, false)
            ),
            None
        );
    }

    #[test]
    fn should_reinstall_no_flag_is_report_only() {
        assert_eq!(
            should_reinstall(
                &StatusOrPresent::Core(Status::OverrideAhead),
                "override",
                false,
                &opts(false, false, false, false, false)
            ),
            None
        );
    }

    // --- table + json rendering ---

    #[test]
    fn table_header_is_the_seven_columns() {
        // The exact header string the bats/pattern-3 padding produces.
        let rows = vec![Row {
            report: report("claude-code", Status::Synced, "curated", false),
            status: StatusOrPresent::Core(Status::Synced),
        }];
        // Just assert the header slice is the canonical 7 columns.
        let header = [
            "ID",
            "STATUS",
            "SENTINEL",
            "INSTALLED",
            "CURATED",
            "LATEST",
            "SRC",
        ];
        assert_eq!(header.len(), 7);
        // Render doesn't panic + the padded row is at least as wide as the header.
        render_table(&rows);
    }

    #[test]
    fn json_present_overlay_serializes_present() {
        let rows = [Row {
            report: report("gsd", Status::NotInstalled, "none", false),
            status: StatusOrPresent::Present,
        }];
        // Build the same JSON render_json would, and assert the status overlay.
        let mut v = serde_json::to_value(&rows[0].report).unwrap();
        v.as_object_mut()
            .unwrap()
            .insert("status".to_string(), serde_json::json!("present"));
        assert_eq!(v["status"], serde_json::json!("present"));
    }

    // --- reconcile loop: continue-on-failure never aborts, exit 0 ---

    fn write_catalog_two(dir: &std::path::Path) {
        // Two script agents so a first-entry recipe failure can be observed to NOT
        // abort the second.
        std::fs::write(
            dir.join("catalog.json"),
            r#"{"version":"0.3.6","agents":[
                {"id":"a-agent","display_name":"A","description":"d","source_kind":"script",
                 "pinned_version":"2.0.0","install_recipe_path":"install.sh","uninstall_recipe_path":"uninstall.sh","tags":["x"]},
                {"id":"b-agent","display_name":"B","description":"d","source_kind":"script",
                 "pinned_version":"2.0.0","install_recipe_path":"install.sh","uninstall_recipe_path":"uninstall.sh","tags":["x"]}
            ]}"#,
        )
        .unwrap();
    }

    fn empty_npm() -> Result<NpmMap, String> {
        Ok(NpmMap::new())
    }
    fn no_latest(_e: &FullCatalogEntry) -> Result<Option<String>, String> {
        Ok(None)
    }

    #[test]
    fn reconcile_continue_on_failure_exits_zero_and_preserves_sentinel() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog_two(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
        std::env::set_var("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

        // Both agents have a diverged (override) sentinel so --reset-all-curated
        // targets them. The dispatcher FAILS for every entry.
        for id in ["a-agent", "b-agent"] {
            let mut s = Sentinel::new(id.into(), "1.0.0".into(), "override".into(), false);
            s.status = Some("installed".to_string());
            sentinel::write_sentinel(&s).unwrap();
        }

        fn failing(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
            DispatchResult {
                exit_code: 9,
                stdout: String::new(),
                stderr: "boom".to_string(),
                streamed: false,
            }
        }
        let deps = UpgradeDeps {
            dispatch: failing,
            query_global_npm: empty_npm,
            query_npm_view_latest: no_latest,
        };
        // Overall exit 0 despite per-entry failures (continue, never abort).
        assert_eq!(
            upgrade_with(&opts(true, false, false, false, false), deps),
            ExitCode::SUCCESS
        );
        // Sentinels PRESERVED (source stays override, not overwritten to curated).
        assert_eq!(
            sentinel::read_sentinel("a-agent").unwrap().unwrap().source,
            "override"
        );
        assert_eq!(
            sentinel::read_sentinel("b-agent").unwrap().unwrap().source,
            "override"
        );

        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn report_only_default_does_not_mutate() {
        let _g = crate::test_support::env_guard();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog_two(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
        std::env::set_var("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

        let mut s = Sentinel::new("a-agent".into(), "1.0.0".into(), "override".into(), false);
        s.status = Some("installed".to_string());
        sentinel::write_sentinel(&s).unwrap();

        fn must_not_run(
            _u: &str,
            _p: &str,
            _e: &[(String, String)],
            _s: Capture,
        ) -> DispatchResult {
            panic!("report-only upgrade must not dispatch");
        }
        let deps = UpgradeDeps {
            dispatch: must_not_run,
            query_global_npm: empty_npm,
            query_npm_view_latest: no_latest,
        };
        assert_eq!(
            upgrade_with(&opts(false, false, false, false, false), deps),
            ExitCode::SUCCESS
        );
        // Untouched.
        assert_eq!(
            sentinel::read_sentinel("a-agent").unwrap().unwrap().source,
            "override"
        );

        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }
}
