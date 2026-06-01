// plugin/cli/src/commands/upgrade.ts — `agentlinux upgrade` (CLI-06, ADR-011).
//
// Flow: loadCatalog → listSentinels → queryGlobalNpm once → build a
// DivergenceReport per entry → render (table/JSON). With no bulk flag it's
// report-only; otherwise iterate shouldReinstall() and dispatch recipes
// sequentially (sentinel writes must not race).
//
// Flag priority: --reset-all-curated wins over --respect-overrides and also
// resets sticky entries; --all-latest implies upstream resolution and skips
// sticky entries. Offline default: upstream is queried only with
// --check-upstream / --all-latest.
//
// `deps` is a DI object — tests inject stubs so no sudo/network runs.

import { statSync } from "node:fs";
import { join } from "node:path";
import { loadCatalog } from "../catalog/loader.js";
import { dispatchRecipe as realDispatchRecipe } from "../runner.js";
import type { DispatchResult, Dispatcher } from "../runner.js";
import { listSentinels, readSentinel, writeSentinel } from "../state/sentinel.js";
import type { CatalogEntry, DivergenceReport, Sentinel } from "../types.js";
import { computeDivergence } from "../upgrade/divergence.js";
import {
  queryGlobalNpm as realQueryGlobalNpm,
  queryNpmViewLatest as realQueryNpmViewLatest,
} from "../upgrade/npm_ls.js";

// validateReusedBinary — true when the sentinel is trustworthy for "is it
// already installed?". A "reused" sentinel whose binary_path has vanished has
// drifted and must be reinstalled (returns false). Non-reused and
// reused-with-warning sentinels are trusted as-is.
function validateReusedBinary(sentinel: Sentinel | null): boolean {
  if (!sentinel) return true;
  // reused-with-warning carries no binary_path (user declared manual
  // ownership) — trust it; the reconcile loop won't dispatch for it.
  if (sentinel.status === "reused-with-warning") return true;
  if (sentinel.status !== "reused" || !sentinel.binary_path) return true;
  try {
    return statSync(sentinel.binary_path).isFile();
  } catch {
    return false;
  }
}

export interface UpgradeOpts {
  resetAllCurated?: boolean;
  respectOverrides?: boolean;
  allLatest?: boolean;
  checkUpstream?: boolean;
  json?: boolean;
}

// DI seam — production defaults, replaced by tests.
export interface UpgradeDeps {
  dispatchRecipe?: (
    args: {
      entry: CatalogEntry;
      recipePath: string;
      version: string;
      catalogDir: string;
      extraEnv?: Record<string, string>;
    },
    dispatcher?: Dispatcher,
  ) => Promise<DispatchResult>;
  queryGlobalNpm?: () => Promise<Map<string, string>>;
  queryNpmViewLatest?: (entry: CatalogEntry) => Promise<string | null>;
}

function willTouchUpstream(opts: UpgradeOpts): boolean {
  return opts.checkUpstream === true || opts.allLatest === true;
}

// shouldReinstall: returns the reinstall source for this entry, or null to skip.
// Follows the flag-priority contract at the top of this file.
function shouldReinstall(report: DivergenceReport, opts: UpgradeOpts): "curated" | "latest" | null {
  // --reset-all-curated hits every diverged entry; synced entries are no-ops.
  if (opts.resetAllCurated) {
    return report.status === "synced" ? null : "curated";
  }
  // --all-latest: skip sticky entries (ADR-011). The latestVersion null-check
  // happens at dispatch time.
  if (opts.allLatest && !report.sticky) {
    return "latest";
  }
  // --respect-overrides: reinstall only 'curated'-source entries that diverged.
  if (opts.respectOverrides) {
    if (report.source === "curated" && report.status !== "synced") {
      return "curated";
    }
    return null;
  }
  // No bulk flag → report-only (null keeps this function total).
  return null;
}

function renderTable(reports: DivergenceReport[]): void {
  const header = ["ID", "STATUS", "SENTINEL", "INSTALLED", "CURATED", "LATEST", "SRC"];
  const rows = reports.map((r) => [
    r.id,
    r.status,
    r.sentinelVersion ?? "-",
    r.installedVersion ?? "-",
    r.curatedVersion,
    r.latestVersion ?? "-",
    r.source,
  ]);
  const all = [header, ...rows];
  const widths = header.map((_, i) => Math.max(...all.map((row) => row[i].length)));
  for (const row of all) {
    console.log(row.map((c, i) => c.padEnd(widths[i])).join("  "));
  }
}

export async function upgradeCmd(opts: UpgradeOpts, deps: UpgradeDeps = {}): Promise<void> {
  const dispatch = deps.dispatchRecipe ?? realDispatchRecipe;
  const queryGlobalNpm = deps.queryGlobalNpm ?? realQueryGlobalNpm;
  const queryNpmViewLatest = deps.queryNpmViewLatest ?? realQueryNpmViewLatest;

  const catalog = await loadCatalog({ validate: true });
  const sentinels = await listSentinels();
  const bySentinel = new Map(sentinels.map((s) => [s.id, s]));
  const npmLs = await queryGlobalNpm();

  const reports: DivergenceReport[] = [];
  for (const entry of catalog.agents) {
    if (entry.test_only) continue; // hidden, matching list default

    const sentinel = bySentinel.get(entry.id) ?? null;
    // installed-version: npm-kind from the npm ls map, script-kind from the
    // sentinel's declared-install record.
    const installed =
      entry.source_kind === "npm" && entry.npm_package_name
        ? (npmLs.get(entry.npm_package_name) ?? null)
        : (sentinel?.version ?? null);

    // Upstream-latest (opt-in only). Per-entry errors are non-fatal — the row
    // still renders with latestVersion=null.
    let latest: string | null = null;
    if (willTouchUpstream(opts) && entry.source_kind === "npm") {
      try {
        latest = await queryNpmViewLatest(entry);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`  ! ${entry.id}: could not resolve latest — ${msg}`);
      }
    }

    reports.push(computeDivergence({ entry, sentinel, installed, latest }));
  }

  if (opts.json) {
    console.log(JSON.stringify(reports, null, 2));
  } else {
    renderTable(reports);
  }

  // Report-only default: no bulk flag = no mutation.
  const isReportOnly = !opts.resetAllCurated && !opts.respectOverrides && !opts.allLatest;
  if (isReportOnly) return;

  // Reconcile loop. Sequential for deterministic log ordering.
  const entryById = new Map(catalog.agents.map((e) => [e.id, e]));
  for (const report of reports) {
    const sentinel = bySentinel.get(report.id) ?? null;

    // REUSE-03: surface that upgrading a reused install flips ownership from
    // adopted to AgentLinux-managed.
    if (sentinel?.status === "reused") {
      console.log(
        `${report.id}: upgrading reused install (binary=${sentinel.binary_path ?? "?"} -> catalog pin)`,
      );
    }
    // reused-with-warning: surface that upgrade does NOT re-attempt the declined
    // remediation.
    if (sentinel?.status === "reused-with-warning") {
      console.log(
        `${report.id}: skipping upgrade for reused-with-warning sentinel (decline_reason=${sentinel.decline_reason ?? "unknown"}; user retains manual ownership)`,
      );
    }

    // If a reused sentinel's binary has vanished, force a curated reinstall even
    // when shouldReinstall returned null for a "synced" report.
    const reusedBinaryGone = sentinel?.status === "reused" && !validateReusedBinary(sentinel);
    let target = shouldReinstall(report, opts);
    if (reusedBinaryGone && !target) {
      target = "curated";
    }
    if (!target) continue;

    const entry = entryById.get(report.id);
    if (!entry) continue; // Defensive — should not happen since reports was built from catalog.agents.

    let version: string;
    let source: Sentinel["source"];
    if (target === "latest") {
      if (!report.latestVersion) {
        // --all-latest requested but no upstream version (script-kind or the
        // view call failed). Skip rather than guess.
        console.error(`${entry.id}: skipping (no upstream latest resolved)`);
        continue;
      }
      version = report.latestVersion;
      source = "latest";
    } else {
      version = entry.pinned_version;
      source = "curated";
    }

    const recipePath = join(catalog.catalogDir, "agents", entry.id, entry.install_recipe_path);
    console.log(`${entry.id}: reinstalling at ${version} (${source})`);
    const result = await dispatch({
      entry,
      recipePath,
      version,
      catalogDir: catalog.catalogDir,
    });
    if (result.exitCode !== 0) {
      console.error(`${entry.id}: recipe failed (exit ${result.exitCode})`);
      if (result.stderr) console.error(result.stderr);
      continue; // Preserve pre-upgrade sentinel — don't mark "installed" on failure.
    }
    if (result.stdout) console.log(result.stdout.trimEnd());

    // Sticky preservation: keep the sticky flag when source='latest' and the
    // prior sentinel was sticky. --reset-all-curated clears it.
    let sticky = false;
    if (source === "latest") {
      const prior = await readSentinel(entry.id);
      sticky = prior?.sticky ?? false;
    }

    // Post-upgrade sentinel is always status: "installed" — the REUSE-only
    // fields are cleared by omission, since we just ran install.sh.
    await writeSentinel({
      id: entry.id,
      version,
      source,
      sticky,
      installed_at: new Date().toISOString(),
      status: "installed",
    });
  }
}
