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
//! list ALWAYS exits 0 (a read-only report). The CLI-05 guard already ran in
//! `main::dispatch` before this body.

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
pub fn list(opts: &ListArgs) -> ExitCode {
    let catalog_dir = catalog::resolve_catalog_dir();
    let agents = match catalog::load_catalog(&catalog_dir, catalog::Validate::Skip) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(1);
        }
    };
    let sentinels = sentinel::list_sentinels().unwrap_or_default();

    let visible: Vec<FullCatalogEntry> = agents
        .into_iter()
        .filter(|a| opts.include_test || !a.test_only)
        .collect();
    let rows = build_rows(&visible, &sentinels);

    if opts.json {
        // `JSON.stringify(rows, null, 2)` — 2-space pretty.
        match serde_json::to_string_pretty(&rows) {
            Ok(s) => println!("{s}"),
            Err(e) => {
                eprintln!("agentlinux: failed to serialize list JSON: {e}");
                return ExitCode::from(1);
            }
        }
        return ExitCode::SUCCESS;
    }

    let mut lines: Vec<String> = Vec::new();
    if opts.by_category {
        // Group by category, ordered by category_order (ties by key).
        let mut keys: Vec<String> = Vec::new();
        for r in &rows {
            if !keys.contains(&r.category) {
                keys.push(r.category.clone());
            }
        }
        keys.sort_by(|a, b| {
            let oa = rows
                .iter()
                .find(|r| &r.category == a)
                .map_or(100, |r| r.category_order);
            let ob = rows
                .iter()
                .find(|r| &r.category == b)
                .map_or(100, |r| r.category_order);
            oa.cmp(&ob).then_with(|| a.cmp(b))
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
            render_table(&group, &mut lines, opts.descriptions);
        }
    } else {
        render_table(&rows, &mut lines, opts.descriptions);
    }
    for line in &lines {
        println!("{line}");
    }
    ExitCode::SUCCESS
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
