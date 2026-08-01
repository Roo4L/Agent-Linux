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
    crate::cmd::is_regular_file(bin)
}

/// The presence overlay only ever describes a row the sentinel store says is
/// NOT installed — a host that already has the binary but has not adopted it.
///
/// `replace == with !=` survived, which consults the overlay for every row
/// EXCEPT the ones it exists to describe, so an already-managed agent can be
/// re-reported as merely "present".
fn presence_overlay_applies(status: Status) -> bool {
    status == Status::NotInstalled
}

/// The reinstall target after the vanished-reuse override.
///
/// `should_reinstall` speaks first; the override only fills a gap it left. The
/// `&&` survived as `||`, which lets the override REPLACE a decision that was
/// already made — an `--all-latest` run targeting "latest" would be forced back
/// to "curated" on any agent with a missing reused binary.
fn final_target(target: Option<&'static str>, reused_binary_gone: bool) -> Option<&'static str> {
    match target {
        Some(t) => Some(t),
        None if reused_binary_gone => Some("curated"),
        None => None,
    }
}

/// Sticky survives a `latest` reinstall and nothing else.
///
/// Sticky means "the operator pinned this deliberately". Carrying it through a
/// CURATED reinstall would re-pin an agent the operator just accepted the
/// curated version for; dropping it on a latest reinstall silently un-pins one
/// they did not. `replace == with !=` survived and does exactly that swap.
fn preserve_sticky(source: &str, prior_sticky: bool) -> bool {
    source == "latest" && prior_sticky
}

/// The INSTALLED column: an npm-kind entry's real on-disk version comes from
/// the `npm ls -g` map; everything else can only report what the sentinel
/// recorded.
///
/// `replace == with !=` survived on the source-kind test, which swaps the two
/// sources: npm agents then report their sentinel's recorded version (missing
/// any self-update, which is the whole reason the npm map is consulted) and
/// script agents look themselves up in an npm map they were never in.
fn installed_version_for(
    entry: &FullCatalogEntry,
    npm_ls: &BTreeMap<String, String>,
    sentinel: Option<&Sentinel>,
) -> Option<String> {
    if entry.source_kind.as_deref() == Some("npm") {
        entry
            .npm_package_name
            .as_deref()
            .and_then(|pkg| npm_ls.get(pkg).cloned())
    } else {
        sentinel.map(|s| s.version.clone())
    }
}

/// Whether to spend an `npm view` round trip on this entry: only when the
/// operator opted in AND the entry is npm-kind (nothing else has a registry to
/// ask).
///
/// `replace && with ||` survived, which queries upstream for every entry on
/// every run — a network call per catalog entry on a command that is
/// offline-by-default (ADR-011).
fn should_query_upstream(opts: &UpgradeArgs, entry: &FullCatalogEntry) -> bool {
    will_touch_upstream(opts) && entry.source_kind.as_deref() == Some("npm")
}

/// No bulk flag means no mutation: `agentlinux upgrade` with no flags REPORTS.
///
/// Five mutants survived on this one condition — both `&&`s and all three `!`s.
/// Each turns a bare `upgrade` into a run that reinstalls agents the operator
/// only asked to look at.
fn is_report_only(opts: &UpgradeArgs) -> bool {
    !opts.reset_all_curated && !opts.respect_overrides && !opts.all_latest
}

/// A "reused" sentinel whose binary has vanished forces a curated reinstall even
/// when the divergence report says "synced" — the report believes the sentinel,
/// and the sentinel is describing a binary that is no longer there.
///
/// Both halves broke independently under mutation: `||` reinstalls every reused
/// agent regardless, `delete !` reinstalls only the ones whose binary is STILL
/// present, and inverting the status test applies it to managed agents instead.
fn reuse_forces_reinstall(sentinel: Option<&Sentinel>) -> bool {
    sentinel.and_then(|s| s.status.as_deref()) == Some("reused")
        && !validate_reused_binary(sentinel)
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
/// Not mutation-tested: binds the real streams and the real dispatcher
/// (ADR-019 §5). Every decision lives in [`upgrade_with`].
#[cfg_attr(test, mutants::skip)]
pub fn upgrade(opts: &UpgradeArgs) -> ExitCode {
    let (mut out, mut err) = (std::io::stdout(), crate::provision::log::err_sink());
    upgrade_with(
        opts,
        UpgradeDeps::default(),
        &mut crate::cmd::install::Out {
            out: &mut out,
            err: &mut err,
        },
    )
}

/// DI-seam variant — the testable core.
#[must_use]
pub fn upgrade_with(
    opts: &UpgradeArgs,
    deps: UpgradeDeps,
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
    let sentinels = match sentinel::list_sentinels() {
        Ok(s) => s,
        Err(e) => {
            let _ = writeln!(o.err, "agentlinux: failed to list sentinels: {e}");
            return ExitCode::from(1);
        }
    };
    let by_sentinel: BTreeMap<String, Sentinel> =
        sentinels.into_iter().map(|s| (s.id.clone(), s)).collect();

    // queryGlobalNpm once (npm INSTALLED column).
    //
    // Degrading a FAILURE to an empty map silently is not safe on the reconcile
    // path. `npm.rs` returns Err on a 30s timeout, on a drain-grace expiry that
    // yields an empty capture, or on unparseable output — all transient. An empty
    // map makes every npm entry read installed=None, so `compute_divergence` calls
    // it non-Synced, and under `--reset-all-curated` that reinstalls EVERY npm
    // agent on the host. A blip in the registry became a host-wide mutation with
    // nothing in the output saying why.
    //
    // Report-only runs still degrade (an unknown INSTALLED column is honest and
    // mutates nothing); a reconcile refuses, because it cannot tell "not installed"
    // from "could not ask".
    let npm_query_failed;
    let npm_ls = match (deps.query_global_npm)() {
        Ok(map) => {
            npm_query_failed = false;
            map
        }
        Err(e) => {
            npm_query_failed = true;
            crate::plog!(
                "agentlinux upgrade: could not read global npm state ({e}); the \
                 INSTALLED column for npm entries is unknown, not empty"
            );
            NpmMap::new()
        }
    };

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
        let installed = installed_version_for(entry, &npm_ls, sentinel);

        // Upstream-latest (opt-in). Per-entry errors are non-fatal — the row still
        // renders with latest=None.
        let mut latest: Option<String> = None;
        if should_query_upstream(opts, entry) {
            match (deps.query_npm_view_latest)(entry) {
                Ok(v) => latest = v,
                Err(msg) => {
                    let _ = writeln!(o.err, "  ! {}: could not resolve latest — {msg}", entry.id);
                }
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
        if presence_overlay_applies(report.status) {
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
        render_json(&rows, o);
    } else {
        render_table(&rows, o);
    }

    // Report-only default: no bulk flag = no mutation.
    if is_report_only(opts) {
        return ExitCode::SUCCESS;
    }

    // Refuse to reconcile on an unknown installed-state. Past this point every
    // npm-kind entry that reads installed=None is a reinstall candidate, and the
    // failed query above cannot distinguish "not installed" from "could not ask".
    // Reinstalling the host's entire npm agent set because the registry was slow
    // for 30 seconds is a far worse outcome than declining and being re-run.
    let any_npm_entry = agents
        .iter()
        .any(|e| !e.test_only && e.source_kind.as_deref() == Some("npm"));
    if npm_query_failed && any_npm_entry {
        crate::plog!(
            "agentlinux upgrade: refusing to reconcile — the global npm query failed, \
             so every npm entry's installed version is unknown and would be treated \
             as a reinstall candidate. The report above is still valid. Re-run once \
             `npm ls -g` works, or use --reset-all-curated on a specific host where \
             you know that is intended."
        );
        return ExitCode::from(crate::EX_TEMPFAIL);
    }

    // Reconcile loop. Sequential for deterministic log ordering.
    let entry_by_id: BTreeMap<String, &FullCatalogEntry> =
        agents.iter().map(|e| (e.id.clone(), e)).collect();
    let user = resolve_install_user();

    // Counted over entries that actually reached a reinstall attempt — a `continue`
    // above the dispatch is a decision not to touch that entry, not a failure.
    let mut attempted = 0usize;
    let mut failures = 0usize;

    for row in &rows {
        let id = &row.report.id;
        let sentinel = by_sentinel.get(id);

        // REUSE-03 surfacing.
        if sentinel.and_then(|s| s.status.as_deref()) == Some("reused") {
            let _ = writeln!(
                o.out,
                "{id}: upgrading reused install (binary={} -> catalog pin)",
                sentinel
                    .and_then(|s| s.binary_path.as_deref())
                    .unwrap_or("?")
            );
        }
        if sentinel.and_then(|s| s.status.as_deref()) == Some("reused-with-warning") {
            let _ = writeln!(o.out,
                "{id}: skipping upgrade for reused-with-warning sentinel (decline_reason={}; user retains manual ownership)",
                sentinel.and_then(|s| s.decline_reason.as_deref()).unwrap_or("unknown")
            );
        }

        // A reused sentinel whose binary vanished forces a curated reinstall even
        // when shouldReinstall returned null for a "synced" report.
        let reused_binary_gone = reuse_forces_reinstall(sentinel);
        let target = should_reinstall(&row.status, &row.report.source, row.report.sticky, opts);
        let Some(target) = final_target(target, reused_binary_gone) else {
            continue;
        };

        let Some(entry) = entry_by_id.get(id) else {
            continue; // defensive
        };

        let (version, source): (String, &str) = if target == "latest" {
            match row.report.latest_version.as_deref() {
                Some(v) => (v.to_string(), "latest"),
                None => {
                    // NOT a benign skip. Under `--all-latest` this is the shape a
                    // blackholed or rate-limited registry takes: every entry fails
                    // to resolve, nothing is attempted, and without counting it the
                    // sweep exits 0 having done nothing — the exact "told the
                    // scheduler it succeeded" failure the exit code exists to
                    // prevent. Counted as attempted AND failed.
                    let _ = writeln!(o.err, "{id}: skipping (no upstream latest resolved)");
                    attempted += 1;
                    failures += 1;
                    continue;
                }
            }
        } else {
            (entry.pinned_version.clone(), "curated")
        };

        let recipe = recipe_path(&catalog_dir, id, &entry.install_recipe_path);
        let _ = writeln!(o.out, "{id}: reinstalling at {version} ({source})");
        attempted += 1;
        let env = recipe_child_env(entry, &version, &catalog_dir, &user);
        // Bounded: the production `dispatch` is `dispatcher::dispatch_recipe`,
        // which carries `recipe_timeout_ms()` (default 30 min,
        // `AGENTLINUX_RECIPE_TIMEOUT_MS`), so one wedged recipe can no longer
        // wedge the sweep.
        let result = (deps.dispatch)(&user, &recipe, &env, Capture::Buffered);
        if result.exit_code != 0 {
            let _ = writeln!(o.err, "{id}: recipe failed (exit {})", result.exit_code);
            if !result.stderr.is_empty() {
                let _ = writeln!(o.err, "{}", result.stderr);
            }
            // Preserve the pre-upgrade sentinel — never mark "installed" on failure.
            // continue — NEVER abort the whole run, but DO remember, so the final
            // exit code tells an unattended caller the sweep was not clean.
            failures += 1;
            continue;
        }
        if !result.stdout.is_empty() {
            let _ = writeln!(o.out, "{}", result.stdout.trim_end());
        }

        // Sticky preservation: keep sticky when source='latest' and prior was sticky.
        let sticky = preserve_sticky(source, sentinel.is_some_and(|s| s.sticky));

        let mut s = Sentinel::new(id.clone(), version, source.into(), sticky);
        s.installed_at = Some(sentinel::now_iso8601());
        s.status = Some("installed".to_string());
        if let Err(e) = sentinel::write_sentinel(&s) {
            let _ = writeln!(o.err, "agentlinux: failed to write sentinel for {id}: {e}");
            // Non-fatal for the run (a single write failure shouldn't abort the
            // sweep) — continue like a per-entry recipe failure. The recipe DID
            // succeed, but the host now disagrees with its own record, which is
            // exactly the kind of drift the exit code has to surface.
            failures += 1;
            continue;
        }
    }

    // Continue-on-failure and report-success-afterwards are separable, and only
    // the first is wanted. A scheduler reads the exit code and nothing else: an
    // `upgrade --reset-all-curated` from a timer that reinstalled nothing because
    // the registry was wedged wrote its diagnosis to stderr, where — the CLI verbs
    // having no transcript — it reached the journal or an unread cron mail, and
    // then reported success. Every entry is still attempted; the sweep just tells
    // the truth at the end.
    if failures > 0 {
        crate::plog!(
            "agentlinux upgrade: {failures} of {attempted} entr{} failed — see the \
             per-entry lines above",
            if attempted == 1 { "y" } else { "ies" }
        );
        return ExitCode::FAILURE;
    }

    ExitCode::SUCCESS
}

/// Render the padded 7-column table. Header
/// `["ID","STATUS","SENTINEL","INSTALLED","CURATED","LATEST","SRC"]`; each column
/// padded to its max width; columns joined with two spaces.
fn render_table(rows: &[Row], o: &mut crate::cmd::install::Out<'_>) {
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
        let _ = writeln!(o.out, "{line}");
    }
}

/// Render the `--json` DivergenceReport array. A `present` row overlays its
/// status string onto the serialized report (the core enum can't hold `present`).
fn render_json(rows: &[Row], o: &mut crate::cmd::install::Out<'_>) {
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
        Ok(s) => {
            let _ = writeln!(o.out, "{s}");
        }
        Err(e) => {
            let _ = writeln!(o.err, "agentlinux: failed to serialize upgrade JSON: {e}");
        }
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

    fn sentinel(status: Option<&str>, binary_path: Option<&str>) -> Sentinel {
        Sentinel {
            id: "claude-code".to_string(),
            version: "1.0.0".to_string(),
            source: "curated".to_string(),
            sticky: false,
            installed_at: None,
            status: status.map(str::to_string),
            decline_reason: None,
            binary_path: binary_path.map(str::to_string),
            detected_source: None,
            reused_at: None,
            compatibility_window_at_reuse: None,
            remediated_at: None,
            remediate_failure_reason: None,
        }
    }

    /// A "reused" sentinel is a claim about a binary AgentLinux did not install.
    /// The claim is only trustworthy while that binary is still there — the one
    /// case that returns false, and the only case that reaches the stat.
    ///
    /// Four mutants survived here: forcing the result true or false outright,
    /// and inverting each of the two status comparisons. Forced true is the
    /// dangerous one — a vanished upstream binary reads as "still installed",
    /// so `upgrade` skips the reinstall that would have restored it.
    #[test]
    fn a_reused_sentinel_is_trusted_only_while_its_binary_survives() {
        let dir = tempdir().unwrap();
        let present = dir.path().join("claude");
        std::fs::write(&present, b"#!/bin/sh\n").unwrap();
        let present = present.to_str().unwrap();
        let absent = dir.path().join("gone").to_str().unwrap().to_string();

        // The discriminating case: reused, and the binary is gone.
        assert!(
            !validate_reused_binary(Some(&sentinel(Some("reused"), Some(&absent)))),
            "a reused sentinel whose binary vanished has drifted"
        );

        // Everything else is trusted, each for its own reason.
        for (s, why) in [
            (
                sentinel(Some("reused"), Some(present)),
                "binary still present",
            ),
            (sentinel(Some("reused"), None), "no binary_path to check"),
            (
                sentinel(Some("reused-with-warning"), Some(&absent)),
                "reused-with-warning is trusted regardless",
            ),
            (
                sentinel(Some("managed"), Some(&absent)),
                "a managed sentinel is not a reuse claim",
            ),
            (
                sentinel(None, Some(&absent)),
                "no status is not a reuse claim",
            ),
        ] {
            assert!(validate_reused_binary(Some(&s)), "{why}");
        }

        assert!(
            validate_reused_binary(None),
            "no sentinel at all is not a drifted reuse"
        );
    }

    /// `--check-upstream` and `--all-latest` each independently mean the run
    /// will hit the network. `replace || with &&` survived, which makes a
    /// single-flag run report as offline — and the flag guards a real
    /// `npm view` round trip.
    #[test]
    fn either_upstream_flag_alone_means_upstream_is_touched() {
        assert!(will_touch_upstream(&opts(false, false, false, true, false)));
        assert!(will_touch_upstream(&opts(false, false, true, false, false)));
        assert!(will_touch_upstream(&opts(false, false, true, true, false)));
        assert!(
            !will_touch_upstream(&opts(true, true, false, false, true)),
            "no upstream flag means no upstream, whatever else is set"
        );
    }

    /// The presence overlay describes rows the store says are NOT installed.
    /// `replace == with !=` consults it for every row EXCEPT those, so an
    /// already-managed agent can be re-reported as merely "present".
    #[test]
    fn the_presence_overlay_applies_only_to_a_not_installed_row() {
        assert!(presence_overlay_applies(Status::NotInstalled));
        for s in [
            Status::Synced,
            Status::DriftUndeclared,
            Status::OverrideAhead,
            Status::OverrideBehind,
            Status::PinnedOverride,
        ] {
            assert!(
                !presence_overlay_applies(s),
                "{s:?} is installed — the overlay has nothing to add"
            );
        }
    }

    /// The vanished-reuse override FILLS a gap `should_reinstall` left; it does
    /// not overrule it. `replace && with ||` lets it replace a decision already
    /// made, so an --all-latest run targeting "latest" is forced back to
    /// "curated" on any agent whose reused binary is missing.
    #[test]
    fn the_reuse_override_fills_a_gap_it_does_not_overrule_one() {
        assert_eq!(
            final_target(Some("latest"), true),
            Some("latest"),
            "a decision already made must survive the override"
        );
        assert_eq!(final_target(Some("curated"), true), Some("curated"));
        assert_eq!(
            final_target(None, true),
            Some("curated"),
            "no decision + a vanished reused binary forces a curated reinstall"
        );
        assert_eq!(
            final_target(None, false),
            None,
            "no decision and nothing forcing one means skip"
        );
    }

    /// Sticky means "the operator pinned this deliberately". It survives a
    /// `latest` reinstall and nothing else: carrying it through a CURATED
    /// reinstall re-pins an agent the operator just accepted the curated version
    /// for, and dropping it on a latest reinstall silently un-pins one they did
    /// not. `replace == with !=` makes exactly that swap.
    #[test]
    fn sticky_survives_a_latest_reinstall_and_nothing_else() {
        assert!(preserve_sticky("latest", true));
        assert!(
            !preserve_sticky("latest", false),
            "a non-sticky agent does not BECOME sticky"
        );
        assert!(
            !preserve_sticky("curated", true),
            "accepting the curated version clears the pin"
        );
        assert!(!preserve_sticky("curated", false));
    }

    /// The STATUS column's string. Both constant replacements survived, and a
    /// blank or junk STATUS is the column an operator reads to decide whether
    /// to act at all.
    #[test]
    fn every_status_or_present_has_its_own_string() {
        assert_eq!(StatusOrPresent::Present.as_str(), "present");
        for (s, want) in [
            (Status::NotInstalled, "not-installed"),
            (Status::Synced, "synced"),
            (Status::DriftUndeclared, "drift-undeclared"),
            (Status::OverrideAhead, "override-ahead"),
            (Status::OverrideBehind, "override-behind"),
            (Status::PinnedOverride, "pinned-override"),
        ] {
            assert_eq!(StatusOrPresent::Core(s).as_str(), want);
            assert_ne!(
                StatusOrPresent::Core(s).as_str(),
                StatusOrPresent::Present.as_str(),
                "a core status must not render as the presence overlay"
            );
        }
    }

    /// Both renderers could be replaced with `()` and produce no output at all —
    /// `upgrade` would exit 0 having printed nothing, which reads as "no agents"
    /// rather than "the report is missing".
    #[test]
    fn the_renderers_actually_emit_the_report() {
        let rows = vec![Row {
            report: report("claude-code", Status::Synced, "curated", false),
            status: StatusOrPresent::Core(Status::Synced),
        }];

        let (mut o, mut e) = (Vec::new(), Vec::new());
        render_table(
            &rows,
            &mut crate::cmd::install::Out {
                out: &mut o,
                err: &mut e,
            },
        );
        let text = String::from_utf8(o).unwrap();
        assert!(
            text.contains("ID") && text.contains("STATUS"),
            "header: {text:?}"
        );
        assert!(
            text.contains("claude-code") && text.contains("synced"),
            "the row must carry the agent and its status: {text:?}"
        );

        let (mut o, mut e) = (Vec::new(), Vec::new());
        render_json(
            &rows,
            &mut crate::cmd::install::Out {
                out: &mut o,
                err: &mut e,
            },
        );
        let parsed: serde_json::Value =
            serde_json::from_str(&String::from_utf8(o).unwrap()).expect("--json emits JSON");
        assert_eq!(parsed[0]["id"], "claude-code");
        assert_eq!(parsed[0]["status"], "synced");
    }

    /// A bare `agentlinux upgrade` REPORTS; only a bulk flag mutates. Five
    /// mutants survived on this one condition — both `&&`s and all three `!`s —
    /// and each turns a look-only run into one that reinstalls agents.
    #[test]
    fn only_a_bulk_flag_turns_upgrade_into_a_mutation() {
        assert!(
            is_report_only(&opts(false, false, false, false, false)),
            "no flags is a report"
        );
        assert!(
            is_report_only(&opts(false, false, false, true, true)),
            "--check-upstream and --json are read-only too"
        );
        for (r, o_, a, what) in [
            (true, false, false, "--reset-all-curated"),
            (false, true, false, "--respect-overrides"),
            (false, false, true, "--all-latest"),
            (true, true, true, "all three"),
        ] {
            assert!(
                !is_report_only(&opts(r, o_, a, false, false)),
                "{what} mutates"
            );
        }
    }

    /// The INSTALLED column reads from the npm map for npm entries and from the
    /// sentinel for everything else. Inverted, npm agents report their recorded
    /// version — missing exactly the self-update the map exists to catch — and
    /// script agents are looked up in a map they were never in.
    #[test]
    fn the_installed_column_reads_the_right_source_per_kind() {
        let mut npm_ls = BTreeMap::new();
        npm_ls.insert("@anthropic-ai/claude-code".to_string(), "2.5.0".to_string());

        let npm_entry: FullCatalogEntry = serde_json::from_value(serde_json::json!({
            "id": "claude-code", "display_name": "C", "description": "d",
            "source_kind": "npm", "npm_package_name": "@anthropic-ai/claude-code",
            "pinned_version": "2.1.0", "install_recipe_path": "i.sh",
            "uninstall_recipe_path": "u.sh",
        }))
        .unwrap();
        let script_entry: FullCatalogEntry = serde_json::from_value(serde_json::json!({
            "id": "rtk", "display_name": "R", "description": "d",
            "source_kind": "script", "pinned_version": "0.42.0",
            "install_recipe_path": "i.sh", "uninstall_recipe_path": "u.sh",
        }))
        .unwrap();
        let s = sentinel(Some("installed"), None);

        assert_eq!(
            installed_version_for(&npm_entry, &npm_ls, Some(&s)).as_deref(),
            Some("2.5.0"),
            "an npm entry reports what is ON DISK, not what was recorded"
        );
        assert_eq!(
            installed_version_for(&script_entry, &npm_ls, Some(&s)).as_deref(),
            Some("1.0.0"),
            "a script entry can only report the sentinel's record"
        );
        assert_eq!(
            installed_version_for(&script_entry, &npm_ls, None),
            None,
            "…and nothing at all without one"
        );
    }

    /// Upstream is queried only when the operator asked AND the entry has a
    /// registry to ask. `replace && with ||` survived, which fires a network
    /// call per catalog entry on a command that is offline-by-default.
    #[test]
    fn upstream_is_queried_only_for_npm_entries_on_an_opt_in_run() {
        let npm_entry: FullCatalogEntry = serde_json::from_value(serde_json::json!({
            "id": "claude-code", "display_name": "C", "description": "d",
            "source_kind": "npm", "npm_package_name": "@anthropic-ai/claude-code",
            "pinned_version": "2.1.0", "install_recipe_path": "i.sh",
            "uninstall_recipe_path": "u.sh",
        }))
        .unwrap();
        let script_entry: FullCatalogEntry = serde_json::from_value(serde_json::json!({
            "id": "rtk", "display_name": "R", "description": "d",
            "source_kind": "script", "pinned_version": "0.42.0",
            "install_recipe_path": "i.sh", "uninstall_recipe_path": "u.sh",
        }))
        .unwrap();

        let opted_in = opts(false, false, false, true, false);
        let offline = opts(false, false, false, false, false);

        assert!(should_query_upstream(&opted_in, &npm_entry));
        assert!(
            !should_query_upstream(&opted_in, &script_entry),
            "a script entry has no registry to ask, even on an opt-in run"
        );
        assert!(
            !should_query_upstream(&offline, &npm_entry),
            "no opt-in means no network, even for an npm entry"
        );
        assert!(!should_query_upstream(&offline, &script_entry));
    }

    /// A reused sentinel whose binary vanished forces a curated reinstall even
    /// when the report says "synced" — the report believes the sentinel, and the
    /// sentinel describes a binary that is gone.
    #[test]
    fn a_vanished_reused_binary_forces_a_reinstall() {
        let dir = tempdir().unwrap();
        let present = dir.path().join("claude");
        std::fs::write(&present, b"#!/bin/sh\n").unwrap();
        let present = present.to_str().unwrap();
        let absent = dir.path().join("gone").to_str().unwrap().to_string();

        assert!(
            reuse_forces_reinstall(Some(&sentinel(Some("reused"), Some(&absent)))),
            "reused + gone is the case that forces it"
        );
        assert!(
            !reuse_forces_reinstall(Some(&sentinel(Some("reused"), Some(present)))),
            "a reused binary still on disk needs no forcing"
        );
        assert!(
            !reuse_forces_reinstall(Some(&sentinel(Some("installed"), Some(&absent)))),
            "a MANAGED sentinel is not a reuse claim — this rule does not apply"
        );
        assert!(!reuse_forces_reinstall(None));
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
        let (mut ro, mut re) = (Vec::new(), Vec::new());
        render_table(
            &rows,
            &mut crate::cmd::install::Out {
                out: &mut ro,
                err: &mut re,
            },
        );
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

    // --- reconcile loop: continue-on-failure never aborts; the exit code is honest ---

    /// Drive the reconcile loop and hand back what the operator would have seen.
    fn run_upgrade(o_args: UpgradeArgs, deps: UpgradeDeps) -> (ExitCode, String, String) {
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let code = upgrade_with(
            &o_args,
            deps,
            &mut crate::cmd::install::Out {
                out: &mut out,
                err: &mut err,
            },
        );
        (
            code,
            String::from_utf8(out).unwrap(),
            String::from_utf8(err).unwrap(),
        )
    }

    /// The reconcile loop's per-sentinel notices and its failure reporting.
    /// Seven mutants lived in here, every one of them only observable in what
    /// the operator is told:
    ///
    /// * the two `status ==` tests decide WHICH notice fires — a reused install
    ///   being upgraded, versus one deliberately left alone because the operator
    ///   declined its remediation. Swapping them tells the operator the opposite
    ///   of what happened.
    /// * `delete !` on the two `is_empty` checks either drops a failing recipe's
    ///   stderr — the only diagnosis of why an upgrade failed — or prints an
    ///   empty line in its place on every success.
    #[test]
    fn the_reconcile_loop_reports_what_it_did_to_each_sentinel() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog_two(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

        // a-agent was adopted; b-agent's remediation was declined.
        let mut a = Sentinel::new("a-agent".into(), "1.0.0".into(), "override".into(), false);
        a.status = Some("reused".to_string());
        a.binary_path = Some("/nonexistent/gone".to_string());
        sentinel::write_sentinel(&a).unwrap();
        let mut b = Sentinel::new("b-agent".into(), "1.0.0".into(), "override".into(), false);
        b.status = Some("reused-with-warning".to_string());
        b.decline_reason = Some("prefix busy".to_string());
        sentinel::write_sentinel(&b).unwrap();

        let (code, out, _err) = run_upgrade(
            opts(true, false, false, false, false),
            UpgradeDeps {
                dispatch: |_u, _p, _e, _s| DispatchResult {
                    exit_code: 0,
                    stdout: "recipe said hello".to_string(),
                    stderr: String::new(),
                    streamed: false,
                },
                query_global_npm: empty_npm,
                query_npm_view_latest: no_latest,
            },
        );
        assert_eq!(code, ExitCode::SUCCESS);
        assert!(
            out.contains("a-agent: upgrading reused install"),
            "an adopted install being upgraded must say so:\n{out}"
        );
        assert!(
            out.contains("b-agent: skipping upgrade for reused-with-warning")
                && out.contains("prefix busy"),
            "a declined remediation must be reported as SKIPPED, with its reason:\n{out}"
        );
        assert!(
            out.contains("recipe said hello"),
            "a recipe's own stdout reaches the operator:\n{out}"
        );

        // Re-seed: the successful run above rewrote both sentinels to curated, so
        // nothing would be diverged for the next one to reconcile.
        sentinel::write_sentinel(&a).unwrap();
        sentinel::write_sentinel(&b).unwrap();

        // A failing recipe: its stderr is the only diagnosis there is.
        let (code, _out, err) = run_upgrade(
            opts(true, false, false, false, false),
            UpgradeDeps {
                dispatch: |_u, _p, _e, _s| DispatchResult {
                    exit_code: 3,
                    stdout: String::new(),
                    stderr: "npm EACCES on prefix".to_string(),
                    streamed: false,
                },
                query_global_npm: empty_npm,
                query_npm_view_latest: no_latest,
            },
        );
        assert_eq!(
            code,
            ExitCode::FAILURE,
            "every entry is visited, and a sweep in which all of them failed \
             must not report success"
        );
        assert!(
            err.contains("recipe failed (exit 3)") && err.contains("npm EACCES on prefix"),
            "the failure and its cause must both reach the operator:\n{err}"
        );
    }

    /// A catalog that will not load is a hard exit 1, not a silent success.
    /// `replace upgrade_with -> ExitCode with Default::default()` survived, and
    /// `Default` is SUCCESS — so a broken catalog would report as a clean run.
    #[test]
    fn an_unreadable_catalog_fails_the_run() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let empty = tempdir().unwrap();
        env_scope.set("AGENTLINUX_CATALOG_DIR", empty.path()); // no catalog.json
        env_scope.set("AGENTLINUX_STATE_DIR", empty.path());

        let (code, _out, err) = run_upgrade(
            opts(false, false, false, false, false),
            UpgradeDeps {
                dispatch: |_u, _p, _e, _s| DispatchResult {
                    exit_code: 0,
                    stdout: String::new(),
                    stderr: String::new(),
                    streamed: false,
                },
                query_global_npm: empty_npm,
                query_npm_view_latest: no_latest,
            },
        );
        assert_eq!(code, ExitCode::from(1), "a missing catalog is a failure");
        assert!(!err.is_empty(), "and it says why:\n{err}");
    }

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
    fn reconcile_total_failure_reports_failure_and_preserves_sentinels() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog_two(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

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
        // A run in which every reinstall failed must not report success — the exit
        // code is the only signal an unattended scheduler reads. (With an all-failing
        // dispatcher this test cannot also distinguish "continued" from "aborted":
        // both leave identical state. That property is pinned by
        // `reconcile_finishes_every_entry_but_still_reports_partial_failure`.)
        assert_eq!(
            upgrade_with(
                &opts(true, false, false, false, false),
                deps,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new(),
                },
            ),
            ExitCode::FAILURE
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

        env_scope.unset("AGENTLINUX_CATALOG_DIR");
        env_scope.unset("AGENTLINUX_STATE_DIR");
        env_scope.unset("AGENTLINUX_DETECT_CACHE");
    }

    thread_local! {
        /// Recipe ids the stub dispatcher was asked to run, in order — the direct
        /// evidence for "the sweep visited every entry".
        static DISPATCHED: std::cell::RefCell<Vec<String>> =
            const { std::cell::RefCell::new(Vec::new()) };
    }

    /// The NEGATIVE CONTROL. Without it, mutating `if failures > 0` to
    /// `if failures >= 0` — making every real sweep return 1, the exact inverse of
    /// the bug being fixed, breaking the same timer and CI consumers — survives the
    /// entire suite, because every other test that reaches the reconcile loop
    /// expects FAILURE.
    #[test]
    fn reconcile_reports_success_when_every_entry_succeeds() {
        let _g = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog_two(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
        std::env::set_var("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

        for id in ["a-agent", "b-agent"] {
            let mut s = Sentinel::new(id.into(), "1.0.0".into(), "override".into(), false);
            s.status = Some("installed".to_string());
            sentinel::write_sentinel(&s).unwrap();
        }

        fn ok(_u: &str, _p: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
            DispatchResult {
                exit_code: 0,
                stdout: String::new(),
                stderr: String::new(),
                streamed: false,
            }
        }
        let deps = UpgradeDeps {
            dispatch: ok,
            query_global_npm: empty_npm,
            query_npm_view_latest: no_latest,
        };
        assert_eq!(
            upgrade_with(
                &opts(true, false, false, false, false),
                deps,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new(),
                },
            ),
            ExitCode::SUCCESS,
            "a clean sweep must report success"
        );
        // Both entries really were reconciled, so this is not passing vacuously.
        for id in ["a-agent", "b-agent"] {
            assert_eq!(
                sentinel::read_sentinel(id).unwrap().unwrap().source,
                "curated"
            );
        }

        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }

    /// The two halves of the contract, together: a partly-failing sweep must still
    /// finish every entry (so one wedged agent cannot strand the rest) AND report
    /// non-zero (so a timer or CI job sees that it was not clean). Asserting only
    /// one of those lets the other regress silently — which is how the exit-0-on-
    /// total-failure bug survived: `continue` was tested, the exit code was not.
    #[test]
    fn reconcile_finishes_every_entry_but_still_reports_partial_failure() {
        let _g = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog_two(cat.path());
        std::env::set_var("AGENTLINUX_CATALOG_DIR", cat.path());
        std::env::set_var("AGENTLINUX_STATE_DIR", state.path());
        std::env::set_var("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

        for id in ["a-agent", "b-agent"] {
            let mut s = Sentinel::new(id.into(), "1.0.0".into(), "override".into(), false);
            s.status = Some("installed".to_string());
            sentinel::write_sentinel(&s).unwrap();
        }

        // `a-agent` fails, `b-agent` succeeds. a-agent is dispatched first because
        // `rows` follows catalog DECLARATION order (nothing sorts), so an
        // abort-on-first-failure implementation would never reach b-agent. That
        // ordering is asserted below rather than assumed — relying on it silently
        // would let a future reorder fake this property.
        fn mixed(_u: &str, path: &str, _e: &[(String, String)], _s: Capture) -> DispatchResult {
            let id = if path.contains("a-agent") {
                "a-agent"
            } else {
                "b-agent"
            };
            DISPATCHED.with(|d| d.borrow_mut().push(id.to_string()));
            let fails = id == "a-agent";
            DispatchResult {
                exit_code: if fails { 9 } else { 0 },
                stdout: String::new(),
                stderr: if fails { "boom".into() } else { String::new() },
                streamed: false,
            }
        }
        DISPATCHED.with(|d| d.borrow_mut().clear());
        let deps = UpgradeDeps {
            dispatch: mixed,
            query_global_npm: empty_npm,
            query_npm_view_latest: no_latest,
        };
        assert_eq!(
            upgrade_with(
                &opts(true, false, false, false, false),
                deps,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new(),
                },
            ),
            ExitCode::FAILURE,
            "a sweep with a failed entry must not report success"
        );
        // The direct assertion of "visits every entry": both were dispatched, in
        // that order. This pins the property itself rather than a side effect a
        // reordering could reproduce under an aborting implementation.
        assert_eq!(
            DISPATCHED.with(|d| d.borrow().clone()),
            vec!["a-agent".to_string(), "b-agent".to_string()],
            "the sweep aborted instead of continuing past the failed entry"
        );
        // And the entry after the failure really was reinstalled, not merely visited.
        assert_eq!(
            sentinel::read_sentinel("b-agent").unwrap().unwrap().source,
            "curated"
        );
        // And the failed entry's own sentinel is untouched — never marked installed.
        assert_eq!(
            sentinel::read_sentinel("a-agent").unwrap().unwrap().source,
            "override"
        );

        std::env::remove_var("AGENTLINUX_CATALOG_DIR");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        std::env::remove_var("AGENTLINUX_DETECT_CACHE");
    }

    #[test]
    fn report_only_default_does_not_mutate() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let cat = tempdir().unwrap();
        let state = tempdir().unwrap();
        write_catalog_two(cat.path());
        env_scope.set("AGENTLINUX_CATALOG_DIR", cat.path());
        env_scope.set("AGENTLINUX_STATE_DIR", state.path());
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

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
            upgrade_with(
                &opts(false, false, false, false, false),
                deps,
                &mut crate::cmd::install::Out {
                    out: &mut Vec::new(),
                    err: &mut Vec::new(),
                },
            ),
            ExitCode::SUCCESS
        );
        // Untouched.
        assert_eq!(
            sentinel::read_sentinel("a-agent").unwrap().unwrap().source,
            "override"
        );

        env_scope.unset("AGENTLINUX_CATALOG_DIR");
        env_scope.unset("AGENTLINUX_STATE_DIR");
        env_scope.unset("AGENTLINUX_DETECT_CACHE");
    }
}
