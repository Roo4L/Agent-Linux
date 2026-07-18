// plugin/cli/src/commands/list.ts — `agentlinux list` implementation (CLI-02).
// Hot path: skips ajv validation (install/upgrade validate) so a partially
// invalid catalog can still be listed. Installed version = the REAL on-disk
// version (probeInstalledVersion) for npm entries, falling back to the sentinel's
// recorded version otherwise — so an out-of-band self-update reads as drift, not
// a stale "synced" (#6 dogfood).

import { deriveCategory } from "../catalog/category.js";
import { loadCatalog } from "../catalog/loader.js";
import { detectPresence } from "../detect.js";
import { listSentinels } from "../state/sentinel.js";
import type { CatalogEntry, Sentinel, Status } from "../types.js";
import { classify } from "../version/classify.js";
import { probeInstalledVersion } from "../version/probe.js";

export interface ListOpts {
  json?: boolean;
  includeTest?: boolean;
  byCategory?: boolean;
  // Off by default: descriptions are long and blow out the table width. Opt in
  // with `--descriptions` for the human table; `--json` always carries them.
  descriptions?: boolean;
}

interface Row {
  id: string;
  display_name: string;
  status: Status;
  curated: string; // entry.pinned_version
  installed: string; // probed real version ?? sentinel?.version ?? '-'
  // #6: the version the sentinel RECORDED at install time. Carried so the text
  // renderer can show "<real> (self-updated from <recorded>)" on drift, and JSON
  // consumers can compare recorded-vs-actual. Null when not installed.
  sentinel_version: string | null;
  // #6: true when the probed on-disk version differs from the recorded sentinel
  // version (i.e. classify() returned drift-undeclared for an out-of-band update).
  drifted: boolean;
  description: string;
  source: Sentinel["source"] | "-";
  // REUSE-03: a "reused" sentinel means AgentLinux manages the adopted binary
  // (upgrade/remove act on it). The text renderer discloses this via a suffix
  // on the INSTALLED column.
  reused: boolean;
  // AL-61/AL-62: no sentinel, but the detect cache reports the agent healthy —
  // physically present, just not adopted. present_canonical distinguishes the
  // hint: at the managed path → "run install to manage" (adopt); at a
  // non-canonical path (e.g. claude via npm) → "run install to migrate" (AL-62).
  present: boolean;
  present_canonical: boolean;
  present_path: string | null;
  // Text renderer appends a distinct suffix per status; JSON carries it verbatim.
  sentinel_status?: "installed" | "reused" | "broken-after-remediate" | "reused-with-warning";
  // Carried to JSON verbatim; set only when sentinel_status === "reused-with-warning".
  decline_reason?: string;
  // ENABLE-06: derived category (key + label + display order). In JSON always; text uses it
  // for --by-category. category_order is carried so the grouped renderer sorts without
  // re-importing the category table (keeps list a pure consumer of deriveCategory).
  category: string;
  category_label: string;
  category_order: number;
}

function buildRows(entries: CatalogEntry[], sentinels: Sentinel[]): Row[] {
  const bySentinel = new Map(sentinels.map((s) => [s.id, s]));
  return entries.map((entry) => {
    const sentinel = bySentinel.get(entry.id) ?? null;
    // #6: probe the REAL on-disk version (npm entries) so an out-of-band
    // self-update surfaces as drift instead of a stale "synced". Fall back to the
    // recorded sentinel version when unprobeable (non-npm kind, package absent).
    const sentinelVersion = sentinel?.version ?? null;
    let installed = sentinel ? (probeInstalledVersion(entry) ?? sentinelVersion) : null;
    let status = classify({ entry, sentinel, installed });
    // AL-61 presence overlay: classify() returns "not-installed" whenever no
    // sentinel exists, even for tools the host already has. Reconcile against the
    // detect cache so a present-but-unadopted agent reads "present" with its
    // detected version instead of being reported absent.
    let present = false;
    let presentCanonical = false;
    let presentPath: string | null = null;
    if (status === "not-installed") {
      const hit = detectPresence(entry);
      if (hit) {
        status = "present";
        present = true;
        presentCanonical = hit.canonical;
        presentPath = hit.path;
        installed = hit.version; // may be null → renders "-"
      }
    }
    const reused = sentinel?.status === "reused";
    const category = deriveCategory(entry);
    return {
      id: entry.id,
      display_name: entry.display_name,
      status,
      curated: entry.pinned_version,
      installed: installed ?? "-",
      sentinel_version: sentinelVersion,
      // drift-undeclared is exactly "probed real version ≠ recorded sentinel".
      drifted: status === "drift-undeclared",
      description: entry.description,
      source: sentinel?.source ?? "-",
      reused,
      present,
      present_canonical: presentCanonical,
      present_path: presentPath,
      sentinel_status: sentinel?.status,
      decline_reason: sentinel?.decline_reason,
      category: category.key,
      category_label: category.label,
      category_order: category.order,
    };
  });
}

// Render the padded columns for a set of rows (shared by the flat + grouped views). The
// INSTALLED-column suffixes are binding wording — bats greps the literal strings.
// DESCRIPTION column is opt-in (showDescriptions); see ListOpts.descriptions for why.
function renderTable(rows: Row[], lines: string[], showDescriptions: boolean): void {
  const REUSED_SUFFIX = " (reused — managed by agentlinux upgrade/remove)";
  const BROKEN_AFTER_REMEDIATE_SUFFIX = " (broken — half-uninstalled, manual recovery needed)";
  const reusedWithWarningSuffix = (reason: string) =>
    ` (reused — declined remediation: ${reason}; manual fix needed)`;
  // #6: on drift, the INSTALLED column shows the real version + where it diverged
  // from the recorded pin and how to reconcile.
  const driftSuffix = (recorded: string) =>
    ` (self-updated from ${recorded} — run: agentlinux upgrade to reconcile)`;
  const presentManageSuffix = (id: string) =>
    ` (detected — run: agentlinux install ${id} to manage)`;
  const presentMigrateSuffix = (id: string, path: string) =>
    ` (detected at ${path}, not the managed path — run: agentlinux install ${id} to migrate)`;
  const header = showDescriptions
    ? ["NAME", "STATUS", "CURATED", "INSTALLED", "DESCRIPTION"]
    : ["NAME", "STATUS", "CURATED", "INSTALLED"];
  const data = rows.map((r) => {
    let installed = r.installed;
    if (r.sentinel_status === "broken-after-remediate") {
      installed = `${r.installed}${BROKEN_AFTER_REMEDIATE_SUFFIX}`;
    } else if (r.sentinel_status === "reused-with-warning") {
      installed = `${r.installed}${reusedWithWarningSuffix(r.decline_reason ?? "unknown")}`;
    } else if (r.reused) {
      installed = `${r.installed}${REUSED_SUFFIX}`;
    } else if (r.drifted && r.sentinel_version) {
      installed = `${r.installed}${driftSuffix(r.sentinel_version)}`;
    } else if (r.present) {
      installed = r.present_canonical
        ? `${r.installed}${presentManageSuffix(r.id)}`
        : `${r.installed}${presentMigrateSuffix(r.id, r.present_path ?? "a non-canonical path")}`;
    }
    const base = [r.id, r.status, r.curated, installed];
    return showDescriptions ? [...base, r.description] : base;
  });
  const all = [header, ...data];
  const widths = header.map((_, i) => Math.max(...all.map((row) => row[i].length)));
  // trimEnd so the final column carries no trailing pad (esp. without DESCRIPTION,
  // where INSTALLED becomes the last column).
  for (const row of all) {
    lines.push(
      row
        .map((c, i) => c.padEnd(widths[i]))
        .join("  ")
        .trimEnd(),
    );
  }
}

export async function listCmd(opts: ListOpts): Promise<void> {
  // Hot path: skip validation.
  const catalog = await loadCatalog({ validate: false });
  const sentinels = await listSentinels();

  const visible = catalog.agents.filter((a) => opts.includeTest || !a.test_only);
  const rows = buildRows(visible, sentinels);

  if (opts.json) {
    console.log(JSON.stringify(rows, null, 2));
    return;
  }

  // ENABLE-06: `--by-category` renders the same columns grouped under a category header
  // (`## <label>`), categories in their canonical display order, entries sorted by id
  // within each. The flat default (no flag) is UNCHANGED — the first line is still the
  // NAME/STATUS/… header — so existing grep-the-table tooling keeps working.
  const lines: string[] = [];
  if (opts.byCategory) {
    const groups = new Map<string, Row[]>();
    for (const r of rows) {
      const g = groups.get(r.category) ?? [];
      g.push(r);
      groups.set(r.category, g);
    }
    // Sort groups by the category's display order (carried on each row), ties by key.
    const keys = [...groups.keys()].sort((a, b) => {
      const oa = groups.get(a)?.[0]?.category_order ?? 100;
      const ob = groups.get(b)?.[0]?.category_order ?? 100;
      return oa - ob || a.localeCompare(b);
    });
    let first = true;
    for (const key of keys) {
      const g =
        groups
          .get(key)
          ?.slice()
          .sort((a, b) => a.id.localeCompare(b.id)) ?? [];
      if (!first) lines.push("");
      first = false;
      lines.push(`## ${g[0]?.category_label ?? key}`);
      renderTable(g, lines, opts.descriptions ?? false);
    }
  } else {
    renderTable(rows, lines, opts.descriptions ?? false);
  }
  for (const line of lines) console.log(line);
}
