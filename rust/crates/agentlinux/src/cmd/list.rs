//! cmd/list.rs — `agentlinux list` (CLI-02, ENABLE-06, AL-61/62).
//!
//! Loads the catalog
//! (hot path — `validate:false`), the sentinels, the installed-version probe, and
//! the detect-cache presence overlay; builds a `Row` per entry via the PURE
//! `classify` / `derive_category` / `presence_gate` (never re-derives); and
//! renders either the padded NAME/STATUS/CURATED/INSTALLED table (+ `--by-category`
//! `## <label>` groups, + `--descriptions`) or the `--json` `Row` array.
//!
//! # Load-bearing literals
//! The INSTALLED-column suffixes are copied byte-for-byte,
//! INCLUDING the em-dash `—` (U+2014) and `▸`-adjacent wording — bats greps them
//! with `grep -qF`. The `#[cfg(test)]` module pins the exact bytes.
//!
//! list exits 0 whenever it can produce a report, which is the normal case for a
//! read-only command. It exits 1 in exactly two situations, both "we cannot
//! answer the question you asked": the catalog will not load, and the install
//! records cannot be read. The second is deliberate — rendering every agent as
//! `not installed` because the record store was unreadable is a wrong answer
//! delivered confidently, and the operator's likely next move (re-installing what
//! is already there) is worse than being told nothing. The CLI-05 guard already
//! ran in `main::dispatch` before this body.

use crate::catalog::{self, FullCatalogEntry};
use crate::sentinel::{self, Sentinel};
use crate::{agent_home, canonical_path, host_paths};
use agentlinux_core::category::derive_category;
use agentlinux_core::classify::classify;
use agentlinux_core::detect_gates::presence_gate;
use agentlinux_core::types::{CatalogEntry as CoreCatalogEntry, Sentinel as CoreSentinel, Status};
use serde::Serialize;

use std::process::ExitCode;

use crate::cli::ListArgs;

/// The list Row — serde field names byte-identical to the TS `Row`
/// so `--json` (`serde_json::to_string_pretty`) serializes field-identically.
///
/// `status` is the kebab `Status` string via the core enum's serde rename;
/// `sentinel_status`/`decline_reason` are carried verbatim; `category_*` come from
/// the pure `derive_category`.
#[derive(Debug, Clone, Serialize)]
struct Row {
    id: String,
    display_name: String,
    status: String,
    curated: String,
    installed: String,
    sentinel_version: Option<String>,
    drifted: bool,
    description: String,
    source: String,
    reused: bool,
    present: bool,
    present_canonical: bool,
    present_adoptable: bool,
    present_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    sentinel_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    decline_reason: Option<String>,
    category: String,
    category_label: String,
    category_order: u32,
}

/// The kebab string for a `Status` (matches the core enum's serde rename → the TS
/// `Status` union string the text table + JSON carry).
pub fn status_str(s: Status) -> &'static str {
    match s {
        Status::NotInstalled => "not-installed",
        Status::Synced => "synced",
        Status::DriftUndeclared => "drift-undeclared",
        Status::OverrideAhead => "override-ahead",
        Status::OverrideBehind => "override-behind",
        Status::PinnedOverride => "pinned-override",
    }
}

/// Build a `Row` per catalog entry.
fn build_rows(entries: &[FullCatalogEntry], sentinels: &[Sentinel]) -> Vec<Row> {
    let home = agent_home();
    entries
        .iter()
        .map(|entry| {
            let core_entry = CoreCatalogEntry::from(entry);
            let sentinel = sentinels.iter().find(|s| s.id == entry.id);
            let sentinel_version = sentinel.map(|s| s.version.clone());
            // #6: probe the REAL on-disk version for npm entries; fall back to the
            // recorded sentinel version when unprobeable.
            let mut installed: Option<String> = if sentinel.is_some() {
                crate::probe::probe_installed_version(entry).or_else(|| sentinel_version.clone())
            } else {
                None
            };
            let core_sentinel = sentinel.map(CoreSentinel::from);
            let status = classify(&core_entry, core_sentinel.as_ref(), installed.as_deref());

            // AL-61 presence overlay: reconcile a not-installed verdict against the
            // detect cache so a present-but-unadopted agent reads "present".
            let mut present = false;
            let mut present_canonical = false;
            let mut present_adoptable = false;
            let mut present_path: Option<String> = None;
            if status == Status::NotInstalled {
                if let Some(detected) = crate::cache::read_cached_agent_by_id(&entry.id) {
                    if let Some(hit) = presence_gate(
                        &core_entry,
                        &detected,
                        host_paths(canonical_path(&entry.id), &home),
                    ) {
                        // `status` stays NotInstalled: the presence overlay is carried
                        // by the `present` flag below, which the renderer checks first.
                        present = true;
                        present_canonical = hit.canonical;
                        present_adoptable = hit.adoptable;
                        present_path = Some(hit.path.clone());
                        installed = hit.version.clone(); // may be None → "-"
                    }
                }
            }

            let reused = sentinel.and_then(|s| s.status.as_deref()) == Some("reused");
            let cat = derive_category(&core_entry);
            // The TS `status` string is "present" when the overlay fired.
            let status_text = if present {
                "present".to_string()
            } else {
                status_str(status).to_string()
            };
            Row {
                id: entry.id.clone(),
                display_name: entry.display_name.clone(),
                status: status_text,
                curated: entry.pinned_version.clone(),
                installed: installed.clone().unwrap_or_else(|| "-".to_string()),
                sentinel_version: sentinel_version.clone(),
                drifted: status == Status::DriftUndeclared,
                description: entry.description.clone(),
                source: sentinel.map_or_else(|| "-".to_string(), |s| s.source.clone()),
                reused,
                present,
                present_canonical,
                present_adoptable,
                present_path,
                sentinel_status: sentinel.and_then(|s| s.status.clone()),
                decline_reason: sentinel.and_then(|s| s.decline_reason.clone()),
                category: cat.key.as_str().to_string(),
                category_label: cat.label,
                category_order: cat.order,
            }
        })
        .collect()
}

// The INSTALLED-column suffix literals — byte-for-byte from list.ts:126-140,
// INCLUDING the em-dash `—` (U+2014). bats greps these with `grep -qF`.
const REUSED_SUFFIX: &str = " (reused — managed by agentlinux upgrade/remove)";
const BROKEN_AFTER_REMEDIATE_SUFFIX: &str = " (broken — half-uninstalled, manual recovery needed)";

fn reused_with_warning_suffix(reason: &str) -> String {
    format!(" (reused — declined remediation: {reason}; manual fix needed)")
}
fn drift_suffix(recorded: &str) -> String {
    format!(" (self-updated from {recorded} — run: agentlinux upgrade to reconcile)")
}
fn present_adopt_suffix(id: &str) -> String {
    format!(" (detected — run: agentlinux adopt {id} to manage)")
}
fn present_reconcile_suffix(id: &str) -> String {
    format!(" (detected out-of-window — run: agentlinux install {id} to manage)")
}
fn present_migrate_suffix(id: &str, path: &str) -> String {
    format!(" (detected at {path}, not the managed path — run: agentlinux install {id} to migrate)")
}

/// The INSTALLED cell for a row (base version + the status suffix). Mirrors the
/// `installed` computation in `renderTable`, in the SAME branch
/// order (broken → reused-with-warning → reused → drift → present).
fn installed_cell(r: &Row) -> String {
    match r.sentinel_status.as_deref() {
        Some("broken-after-remediate") => {
            format!("{}{}", r.installed, BROKEN_AFTER_REMEDIATE_SUFFIX)
        }
        Some("reused-with-warning") => format!(
            "{}{}",
            r.installed,
            reused_with_warning_suffix(r.decline_reason.as_deref().unwrap_or("unknown"))
        ),
        _ if r.reused => format!("{}{}", r.installed, REUSED_SUFFIX),
        _ if r.drifted && r.sentinel_version.is_some() => format!(
            "{}{}",
            r.installed,
            drift_suffix(r.sentinel_version.as_deref().unwrap_or_default())
        ),
        _ if r.present => {
            if r.present_adoptable {
                format!("{}{}", r.installed, present_adopt_suffix(&r.id))
            } else if r.present_canonical {
                format!("{}{}", r.installed, present_reconcile_suffix(&r.id))
            } else {
                format!(
                    "{}{}",
                    r.installed,
                    present_migrate_suffix(
                        &r.id,
                        r.present_path.as_deref().unwrap_or("a non-canonical path")
                    )
                )
            }
        }
        _ => r.installed.clone(),
    }
}

/// Render the padded columns for a set of rows (shared flat + grouped). Mirrors
/// `renderTable`: width = max(header, rows) per column, `padEnd`,
/// join with TWO spaces, `trimEnd` each line. Column width uses `chars().count()`
/// (Unicode scalar count) — the em-dash/▸ live only in the trimmed final column,
/// so BMP-vs-UTF16 width differences never reach an asserted byte.
fn render_table(rows: &[Row], lines: &mut Vec<String>, show_descriptions: bool) {
    let header: Vec<&str> = if show_descriptions {
        vec!["NAME", "STATUS", "CURATED", "INSTALLED", "DESCRIPTION"]
    } else {
        vec!["NAME", "STATUS", "CURATED", "INSTALLED"]
    };
    let data: Vec<Vec<String>> = rows
        .iter()
        .map(|r| {
            let base = vec![
                r.id.clone(),
                r.status.clone(),
                r.curated.clone(),
                installed_cell(r),
            ];
            if show_descriptions {
                let mut b = base;
                b.push(r.description.clone());
                b
            } else {
                base
            }
        })
        .collect();

    let ncols = header.len();
    let mut widths = vec![0usize; ncols];
    for (i, h) in header.iter().enumerate() {
        widths[i] = h.chars().count();
    }
    for row in &data {
        for (i, cell) in row.iter().enumerate() {
            widths[i] = widths[i].max(cell.chars().count());
        }
    }

    let render_row = |cells: &[String]| -> String {
        cells
            .iter()
            .enumerate()
            .map(|(i, c)| pad_end(c, widths[i]))
            .collect::<Vec<_>>()
            .join("  ")
            .trim_end()
            .to_string()
    };

    // header first, then rows.
    let header_owned: Vec<String> = header.iter().map(|s| (*s).to_string()).collect();
    lines.push(render_row(&header_owned));
    for row in &data {
        lines.push(render_row(row));
    }
}

/// `String.prototype.padEnd` — pad with spaces to `width` scalar chars (no
/// truncation when already wider).
fn pad_end(s: &str, width: usize) -> String {
    let len = s.chars().count();
    if len >= width {
        s.to_string()
    } else {
        format!("{s}{}", " ".repeat(width - len))
    }
}

/// `agentlinux list` body. Loads catalog + sentinels, builds rows, renders. Always
/// exits 0. Port of `listCmd`.
#[must_use]
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — it resolves
/// the ambient catalog dir, reads the real sentinel store and writes real
/// stdout. Everything it decides is asserted directly: [`visible_entries`],
/// [`build_rows`], [`render_by_category`] and [`render_table`].
#[cfg_attr(test, mutants::skip)]
pub fn list(opts: &ListArgs) -> ExitCode {
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, catalog::Validate::Skip) {
        Ok(a) => a,
        Err(e) => {
            crate::plog!("{e}");
            return ExitCode::from(1);
        }
    };
    // A listing that cannot read the install records must not render every agent
    // as "not installed" — that is a wrong answer presented as a confident one,
    // and the operator's next move (re-installing what is already there) is worse
    // than being told nothing.
    let sentinels = match sentinel::list_sentinels() {
        Ok(s) => s,
        Err(e) => {
            crate::plog!(
                "agentlinux: cannot read the install records ({e}) — refusing to \
                 report every agent as not-installed. Check {}.",
                sentinel::installed_dir().display()
            );
            return ExitCode::from(1);
        }
    };

    let visible = visible_entries(agents, opts.include_test);
    let rows = build_rows(&visible, &sentinels);

    if opts.json {
        // `JSON.stringify(rows, null, 2)` — 2-space pretty.
        match serde_json::to_string_pretty(&rows) {
            Ok(s) => println!("{s}"),
            Err(e) => {
                crate::plog!("agentlinux: failed to serialize list JSON: {e}");
                return ExitCode::from(1);
            }
        }
        return ExitCode::SUCCESS;
    }

    let mut lines: Vec<String> = Vec::new();
    if opts.by_category {
        render_by_category(&rows, opts.descriptions, &mut lines);
    } else {
        render_table(&rows, &mut lines, opts.descriptions);
    }
    for line in &lines {
        println!("{line}");
    }
    ExitCode::SUCCESS
}

/// The catalog entries `list` will show: `test_only` fixtures are hidden unless
/// `--include-test` asks for them.
///
/// Extracted from `list` because inside it the filter was only reachable by
/// running the whole verb against the real catalog and reading real stdout.
/// `delete !` and `replace || with &&` both survived there — one shows the
/// fixtures to every user, the other hides every REAL agent unless
/// `--include-test` is passed.
fn visible_entries(agents: Vec<FullCatalogEntry>, include_test: bool) -> Vec<FullCatalogEntry> {
    agents
        .into_iter()
        .filter(|a| include_test || !a.test_only)
        .collect()
}

/// Render the `--by-category` grouping: categories in `category_order` (ties
/// broken by key), agents within a category by id, a blank line between groups
/// and never before the first.
///
/// Extracted for the same reason as [`visible_entries`] — five mutants survived
/// in here behind `println!`: the dedup that builds the key list, both halves of
/// the order lookup, the per-group membership test, and the blank-line guard.
fn render_by_category(rows: &[Row], descriptions: bool, lines: &mut Vec<String>) {
    let mut keys: Vec<String> = Vec::new();
    for r in rows {
        if !keys.contains(&r.category) {
            keys.push(r.category.clone());
        }
    }
    keys.sort_by(|a, b| {
        let order_of = |k: &String| {
            rows.iter()
                .find(|r| &r.category == k)
                .map_or(100, |r| r.category_order)
        };
        order_of(a).cmp(&order_of(b)).then_with(|| a.cmp(b))
    });
    let mut first = true;
    for key in &keys {
        let mut group: Vec<Row> = rows
            .iter()
            .filter(|r| &r.category == key)
            .cloned()
            .collect();
        group.sort_by(|a, b| a.id.cmp(&b.id));
        if !first {
            lines.push(String::new());
        }
        first = false;
        let label = group
            .first()
            .map_or_else(|| key.clone(), |r| r.category_label.clone());
        lines.push(format!("## {label}"));
        render_table(&group, lines, descriptions);
    }
}

#[cfg(test)]
mod list_tests {
    use super::*;

    fn row(id: &str) -> Row {
        Row {
            id: id.to_string(),
            display_name: id.to_string(),
            status: "not-installed".to_string(),
            curated: "1.0.0".to_string(),
            installed: "-".to_string(),
            sentinel_version: None,
            drifted: false,
            description: "desc".to_string(),
            source: "-".to_string(),
            reused: false,
            present: false,
            present_canonical: false,
            present_adoptable: false,
            present_path: None,
            sentinel_status: None,
            decline_reason: None,
            category: "coding-agent".to_string(),
            category_label: "Coding agents".to_string(),
            category_order: 1,
        }
    }

    fn entry(id: &str, test_only: bool) -> FullCatalogEntry {
        FullCatalogEntry {
            id: id.to_string(),
            display_name: id.to_string(),
            description: "d".to_string(),
            homepage: None,
            license: None,
            source_kind: Some("script".to_string()),
            npm_package_name: None,
            requires_secret: None,
            secret_env: None,
            endpoint_url: None,
            pinned_version: "1.0.0".to_string(),
            version_constraint: None,
            compatibility_window: None,
            install_recipe_path: "install.sh".to_string(),
            uninstall_recipe_path: "uninstall.sh".to_string(),
            rewire_recipe_path: None,
            post_install_verify: None,
            preserve_paths_file: None,
            preserve_paths: None,
            tags: Vec::new(),
            test_only,
        }
    }

    fn sentinel_for(id: &str, version: &str, source: &str, status: Option<&str>) -> Sentinel {
        let mut s = Sentinel::new(
            id.to_string(),
            version.to_string(),
            source.to_string(),
            false,
        );
        s.status = status.map(str::to_string);
        s
    }

    /// `build_rows` is where a catalog entry and its sentinel become the row the
    /// table and the JSON both render. Five mutants survived in it: the whole
    /// function replaced by an empty vec, and four `==` comparisons inverted —
    /// the sentinel lookup, the presence-overlay gate, the reuse flag and the
    /// drift flag.
    ///
    /// Inverting the sentinel lookup is the worst of them: every row then reads
    /// SOME OTHER agent's sentinel, so versions, sources and reuse state are
    /// attributed to the wrong tool throughout the list.
    #[test]
    fn a_row_carries_its_own_sentinel_and_its_own_flags() {
        let mut env_scope = crate::test_support::EnvScope::new();
        // No detect cache → the presence overlay cannot fire, so these
        // assertions are about the sentinel path alone.
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");
        env_scope.set("AGENTLINUX_AGENT_HOME", "/home/agent");

        let entries = vec![entry("claude-code", false), entry("gsd", false)];
        // Deliberately in the OPPOSITE order to the entries, and with different
        // versions, so a mismatched lookup is visible rather than coincidental.
        let sentinels = vec![
            sentinel_for("gsd", "1.7.0", "override", Some("reused")),
            sentinel_for("claude-code", "1.0.0", "curated", Some("installed")),
        ];

        let rows = build_rows(&entries, &sentinels);
        assert_eq!(rows.len(), 2, "one row per visible entry");
        let by_id = |id: &str| rows.iter().find(|r| r.id == id).expect("row present");

        let claude = by_id("claude-code");
        assert_eq!(
            claude.sentinel_version.as_deref(),
            Some("1.0.0"),
            "each row must read ITS OWN sentinel, not the other one's"
        );
        assert_eq!(claude.source, "curated");
        assert!(!claude.reused, "status=installed is not a reuse");

        let gsd = by_id("gsd");
        assert_eq!(gsd.sentinel_version.as_deref(), Some("1.7.0"));
        assert_eq!(gsd.source, "override");
        assert!(gsd.reused, "status=reused sets the reuse flag");

        // An entry with NO sentinel is not-installed: no version, no source, and
        // the presence overlay left it alone because the cache is absent.
        let rows = build_rows(&[entry("rtk", false)], &sentinels);
        let rtk = &rows[0];
        assert_eq!(rtk.sentinel_version, None);
        assert_eq!(rtk.source, "-");
        assert_eq!(rtk.installed, "-");
        assert!(!rtk.present, "no cache entry means no presence overlay");
        assert!(!rtk.reused);
    }

    fn npm_entry(id: &str, pkg: &str, pinned: &str) -> FullCatalogEntry {
        let mut e = entry(id, false);
        e.source_kind = Some("npm".to_string());
        e.npm_package_name = Some(pkg.to_string());
        e.pinned_version = pinned.to_string();
        e
    }

    /// The drift flag says "the binary on disk is not the version we recorded".
    /// `replace == with != in build_rows` survived on it, which inverts the
    /// column: every synced agent renders as self-updated and every genuinely
    /// drifted one renders as clean — and drift is what tells an operator to run
    /// `agentlinux upgrade`.
    #[test]
    fn a_row_is_drifted_only_when_disk_disagrees_with_the_sentinel() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let home = tempfile::tempdir().unwrap();
        env_scope.set("AGENTLINUX_AGENT_HOME", home.path());
        env_scope.set("AGENTLINUX_DETECT_CACHE", "/nonexistent/detect.json");

        // A real global-npm layout so probe_installed_version reads a version
        // off disk rather than falling back to the sentinel's own record.
        let pkg_dir = home
            .path()
            .join(".npm-global/lib/node_modules/@anthropic-ai/claude-code");
        std::fs::create_dir_all(&pkg_dir).unwrap();
        let write_version = |v: &str| {
            std::fs::write(
                pkg_dir.join("package.json"),
                format!(r#"{{"name":"@anthropic-ai/claude-code","version":"{v}"}}"#),
            )
            .unwrap();
        };

        let entries = vec![npm_entry(
            "claude-code",
            "@anthropic-ai/claude-code",
            "1.0.0",
        )];
        let sentinels = vec![sentinel_for(
            "claude-code",
            "1.0.0",
            "curated",
            Some("installed"),
        )];

        // On disk == recorded → not drifted.
        write_version("1.0.0");
        let rows = build_rows(&entries, &sentinels);
        assert_eq!(rows[0].installed, "1.0.0");
        assert!(!rows[0].drifted, "matching versions are not drift");

        // On disk ahead of the record → drifted, and the row reports what is
        // actually installed, not what was recorded.
        write_version("2.5.0");
        let rows = build_rows(&entries, &sentinels);
        assert_eq!(
            rows[0].installed, "2.5.0",
            "the row shows the on-disk version"
        );
        assert_eq!(rows[0].sentinel_version.as_deref(), Some("1.0.0"));
        assert!(
            rows[0].drifted,
            "a self-updated binary must render as drift so upgrade is offered"
        );
    }

    /// The AL-61 presence overlay reconciles a not-installed verdict against the
    /// detect cache, so a present-but-unadopted agent reads "present" instead of
    /// "not-installed". `replace == with != in build_rows` survived on the gate
    /// that enters it: inverted, the overlay is consulted for agents that ARE
    /// installed and skipped for the ones it exists to describe.
    #[test]
    fn the_presence_overlay_fires_only_for_a_not_installed_row() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempfile::tempdir().unwrap();
        let cache = dir.path().join("detect.json");
        std::fs::write(
            &cache,
            r#"{"agents":[{"id":"claude-code","status":"healthy",
                 "path":"/home/agent/.local/bin/claude","version":"2.1.0"}]}"#,
        )
        .unwrap();
        env_scope.set("AGENTLINUX_DETECT_CACHE", &cache);
        env_scope.set("AGENTLINUX_AGENT_HOME", "/home/agent");

        // No sentinel → NotInstalled → the overlay is allowed to fire.
        let rows = build_rows(&[entry("claude-code", false)], &[]);
        assert!(
            rows[0].present,
            "a cached, unadopted agent must read as present"
        );
        assert_eq!(rows[0].status, "present");
        assert_eq!(
            rows[0].present_path.as_deref(),
            Some("/home/agent/.local/bin/claude")
        );

        // With a sentinel the row is installed, and the overlay must NOT fire —
        // an adopted agent is not "detected".
        let sentinels = vec![sentinel_for(
            "claude-code",
            "2.1.0",
            "curated",
            Some("installed"),
        )];
        let rows = build_rows(&[entry("claude-code", false)], &sentinels);
        assert!(
            !rows[0].present,
            "an already-managed agent must not be re-reported as merely present"
        );
        assert_ne!(rows[0].status, "present");
    }

    /// `test_only` fixtures are hidden by default and shown on --include-test.
    /// `delete !` and `replace || with &&` both survived: one offers the test
    /// fixtures to every user, the other hides every REAL agent unless
    /// --include-test is passed.
    #[test]
    fn test_only_entries_are_hidden_unless_asked_for() {
        let catalog = || vec![entry("claude-code", false), entry("test-dummy", true)];

        let ids = |v: Vec<FullCatalogEntry>| v.into_iter().map(|e| e.id).collect::<Vec<_>>();
        assert_eq!(
            ids(visible_entries(catalog(), false)),
            vec!["claude-code"],
            "the default list must not offer test fixtures"
        );
        assert_eq!(
            ids(visible_entries(catalog(), true)),
            vec!["claude-code", "test-dummy"],
            "--include-test adds them WITHOUT dropping the real ones"
        );
    }

    /// `--by-category` orders groups by `category_order`, agents inside a group
    /// by id, and separates groups with exactly one blank line — never one
    /// before the first group.
    ///
    /// Five mutants survived in here while it lived inside `list` behind
    /// `println!`: the key dedup, both halves of the order lookup, the group
    /// membership test, and the blank-line guard.
    #[test]
    fn by_category_orders_groups_and_separates_them_exactly_once() {
        let mk = |id: &str, cat: &str, label: &str, order: u32| {
            let mut r = row(id);
            r.category = cat.to_string();
            r.category_label = label.to_string();
            r.category_order = order;
            r
        };
        // Deliberately out of order, and with two members in the later group so
        // the within-group sort is observable.
        let rows = vec![
            mk("zebra", "mcp", "MCP servers", 2),
            mk("alpha", "coding-agent", "Coding agents", 1),
            mk("beta", "mcp", "MCP servers", 2),
        ];

        let mut lines = Vec::new();
        render_by_category(&rows, false, &mut lines);

        let headers: Vec<&String> = lines.iter().filter(|l| l.starts_with("## ")).collect();
        assert_eq!(
            headers,
            vec!["## Coding agents", "## MCP servers"],
            "groups run in category_order, not first-seen order"
        );

        // Each category appears exactly once — the dedup that builds the key
        // list is what guarantees it.
        assert_eq!(
            lines
                .iter()
                .filter(|l| l.as_str() == "## MCP servers")
                .count(),
            1,
            "a category with two members must still print one header"
        );

        assert!(
            !lines.is_empty() && !lines[0].is_empty(),
            "no blank line before the FIRST group"
        );
        assert_eq!(
            lines.iter().filter(|l| l.is_empty()).count(),
            1,
            "exactly one blank line between two groups"
        );

        // Within the group, ids sort — beta before zebra despite input order.
        let joined = lines.join("\n");
        assert!(
            joined.find("beta").unwrap() < joined.find("zebra").unwrap(),
            "agents inside a category sort by id, got:\n{joined}"
        );
    }

    /// The INSTALLED cell is a priority chain, and the ORDER is the contract:
    /// broken-after-remediate beats reused-with-warning beats reused beats drift
    /// beats present. Deleting either of the first two match arms survived —
    /// each silently demotes a row to the next suffix down, so a
    /// half-uninstalled agent needing manual recovery renders as an ordinary
    /// reuse, and an operator is told nothing is wrong.
    #[test]
    fn the_installed_cell_branch_order_is_the_contract() {
        // Every flag below is set at once, so each case can only be produced by
        // its OWN arm winning — not by being the last one standing.
        let loaded = |status: Option<&str>| {
            let mut r = row("claude-code");
            r.installed = "2.1.0".to_string();
            r.sentinel_status = status.map(str::to_string);
            r.decline_reason = Some("npm prefix busy".to_string());
            r.reused = true;
            r.drifted = true;
            r.sentinel_version = Some("2.0.0".to_string());
            r.present = true;
            r.present_adoptable = true;
            r
        };

        assert_eq!(
            installed_cell(&loaded(Some("broken-after-remediate"))),
            format!("2.1.0{BROKEN_AFTER_REMEDIATE_SUFFIX}"),
            "broken-after-remediate outranks every other signal"
        );
        assert_eq!(
            installed_cell(&loaded(Some("reused-with-warning"))),
            format!("2.1.0{}", reused_with_warning_suffix("npm prefix busy")),
            "reused-with-warning outranks plain reuse, and carries the reason"
        );
        assert_eq!(
            installed_cell(&loaded(None)),
            format!("2.1.0{REUSED_SUFFIX}"),
            "with neither status set, plain reuse wins over drift and present"
        );

        // Drift is only reportable when there is a recorded version to name.
        let mut d = row("gsd");
        d.installed = "1.8.0".to_string();
        d.drifted = true;
        d.sentinel_version = Some("1.7.0".to_string());
        assert_eq!(
            installed_cell(&d),
            format!("1.8.0{}", drift_suffix("1.7.0")),
            "drift names the version AgentLinux recorded"
        );
        d.sentinel_version = None;
        assert_eq!(
            installed_cell(&d),
            "1.8.0",
            "drift with no recorded version has nothing to report — the `&&` in \
             that guard is what stops it printing `self-updated from `"
        );
    }

    /// The three generated suffixes are byte-exact acceptance contracts: the
    /// bats suite greps them with `grep -qF`. Each could be replaced wholesale
    /// with an empty or junk string and nothing noticed.
    #[test]
    fn the_generated_suffixes_are_byte_exact() {
        assert_eq!(
            reused_with_warning_suffix("EACCES on prefix"),
            " (reused — declined remediation: EACCES on prefix; manual fix needed)"
        );
        assert_eq!(
            drift_suffix("1.2.3"),
            " (self-updated from 1.2.3 — run: agentlinux upgrade to reconcile)"
        );
        assert_eq!(
            present_reconcile_suffix("rtk"),
            " (detected out-of-window — run: agentlinux install rtk to manage)"
        );
        // The em-dash is load-bearing in all three, as it is in REUSED_SUFFIX.
        for suffix in [
            reused_with_warning_suffix("x"),
            drift_suffix("x"),
            present_reconcile_suffix("x"),
        ] {
            assert!(suffix.contains('\u{2014}'), "{suffix:?} lost its em-dash");
        }
    }

    /// Every `Status` renders as the kebab string the JSON and the text table
    /// both carry. Replacing the whole function with "" or junk survived.
    #[test]
    fn every_status_has_its_kebab_string() {
        for (s, want) in [
            (Status::NotInstalled, "not-installed"),
            (Status::Synced, "synced"),
            (Status::DriftUndeclared, "drift-undeclared"),
            (Status::OverrideAhead, "override-ahead"),
            (Status::OverrideBehind, "override-behind"),
            (Status::PinnedOverride, "pinned-override"),
        ] {
            assert_eq!(status_str(s), want);
        }
    }

    #[test]
    fn reused_suffix_carries_the_literal_em_dash() {
        // U+2014 em-dash is a load-bearing byte.
        assert!(REUSED_SUFFIX.contains('\u{2014}'));
        assert_eq!(
            REUSED_SUFFIX,
            " (reused — managed by agentlinux upgrade/remove)"
        );
        let mut r = row("gsd");
        r.reused = true;
        r.installed = "1.7.0".to_string();
        assert_eq!(
            installed_cell(&r),
            "1.7.0 (reused — managed by agentlinux upgrade/remove)"
        );
    }

    #[test]
    fn present_adopt_and_migrate_suffixes_match_ts_bytes() {
        // AL-61 manage hint.
        let mut r = row("gsd");
        r.present = true;
        r.present_canonical = true;
        r.present_adoptable = true;
        r.installed = "-".to_string();
        assert_eq!(
            installed_cell(&r),
            "- (detected — run: agentlinux adopt gsd to manage)"
        );
        // AL-62 migrate hint — names the detected path.
        let mut m = row("claude-code");
        m.present = true;
        m.present_canonical = false;
        m.present_adoptable = false;
        m.present_path = Some("/home/agent/.npm-global/bin/claude".to_string());
        m.installed = "-".to_string();
        let cell = installed_cell(&m);
        assert!(cell.contains("to migrate"), "{cell}");
        assert!(
            cell.contains("/home/agent/.npm-global/bin/claude"),
            "{cell}"
        );
    }

    #[test]
    fn padded_table_golden() {
        // A tiny two-row golden: widths from header + rows, two-space join,
        // trimEnd (INSTALLED is the last column → no trailing pad).
        let mut rows = vec![row("claude-code"), row("gsd")];
        rows[0].status = "synced".to_string();
        rows[0].installed = "2.1.98".to_string();
        rows[1].installed = "-".to_string();
        let mut lines = Vec::new();
        render_table(&rows, &mut lines, false);
        assert_eq!(lines[0], "NAME         STATUS         CURATED  INSTALLED");
        assert_eq!(lines[1], "claude-code  synced         1.0.0    2.1.98");
        // Last column trimmed → no trailing spaces on the "-" row.
        assert_eq!(lines[2], "gsd          not-installed  1.0.0    -");
    }

    #[test]
    fn json_row_serializes_expected_fields() {
        let r = row("gsd");
        let json = serde_json::to_string(&r).unwrap();
        // Field-name parity spot check (serde renames are exact).
        assert!(json.contains("\"sentinel_version\":null"));
        assert!(json.contains("\"present_canonical\":false"));
        assert!(json.contains("\"category_label\":\"Coding agents\""));
        // None sentinel_status is skipped (matches TS undefined omission).
        assert!(!json.contains("sentinel_status"));
    }
}
