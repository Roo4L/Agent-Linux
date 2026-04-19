// plugin/cli/src/commands/upgrade.ts — `agentlinux upgrade` (CLI-06).
// Pattern ref: 04-RESEARCH §Pattern 7 lines 830-864 + ADR-011 stability-first.
//
// Orchestration flow:
//   1. loadCatalog(validate:true) — reject malformed catalogs up front (upgrade
//      is a mutation path; Open Q2 says validate here unlike the `list` hot path)
//   2. listSentinels() → Map<id, Sentinel>
//   3. queryGlobalNpm() once — populates installed-version for every npm entry
//   4. For each catalog entry: build DivergenceReport (with optional upstream
//      latest if --check-upstream / --all-latest). Any per-entry upstream
//      failure is logged as a warning and the row still renders with
//      latestVersion=null.
//   5. Render report (text table OR JSON).
//   6. If no bulk flag → return (report-only).
//   7. Otherwise iterate: shouldReinstall(report, opts) → 'curated' | 'latest'
//      | null. Dispatch the recipe sequentially (for-of rather than Promise.all
//      — sentinel writes must not race on the same filesystem).
//
// Flag priority (from the plan):
//   --reset-all-curated wins over --respect-overrides (explicit "reset everything")
//   --all-latest implies upstream-resolution; skips sticky entries
//   --reset-all-curated ALSO resets sticky entries (explicit override per ADR-011)
//
// Offline default (T-04-12): willTouchUpstream() returns true only when the
// user opts in through --check-upstream or --all-latest. Ordinary
// `agentlinux upgrade` never shells out to `npm view`.
//
// Testability: `deps` DI object — tests inject stubbed dispatchRecipe,
// queryGlobalNpm, queryNpmViewLatest so no sudo/network happens under
// `pnpm test`. Same pattern used in install.ts / remove.ts.

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

export interface UpgradeOpts {
  resetAllCurated?: boolean;
  respectOverrides?: boolean;
  allLatest?: boolean;
  checkUpstream?: boolean;
  json?: boolean;
}

// DI seam. Each function has a production default; tests replace them with
// capturing/stubbing impls. Matches the install.ts / remove.ts pattern.
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

// shouldReinstall: returns the reinstall SOURCE for this entry, or null to skip.
// Logic follows the flag priority contract documented at the top of this file.
function shouldReinstall(report: DivergenceReport, opts: UpgradeOpts): "curated" | "latest" | null {
  // Highest priority: --reset-all-curated hits every diverged (non-synced)
  // entry regardless of source/sticky. Synced entries are skipped so we don't
  // re-run the recipe for a no-op.
  if (opts.resetAllCurated) {
    return report.status === "synced" ? null : "curated";
  }
  // --all-latest: skip sticky entries (ADR-011 — pin semantics). For
  // non-sticky entries we need a resolved latestVersion; the caller layer
  // surfaces the "latest unknown" case and this function just commits to the
  // intent — the actual null-check happens at dispatch time.
  if (opts.allLatest && !report.sticky) {
    return "latest";
  }
  // --respect-overrides: only re-install entries whose sentinel.source is
  // 'curated' AND that are diverged from their pin. Leaves 'override',
  // 'pinned', 'latest' alone.
  if (opts.respectOverrides) {
    if (report.source === "curated" && report.status !== "synced") {
      return "curated";
    }
    return null;
  }
  // No bulk flag → report-only (caller short-circuits before reaching here,
  // but returning null keeps this function total).
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
    if (entry.test_only) continue; // match list default — hidden unless --include-test (Phase 5+)

    const sentinel = bySentinel.get(entry.id) ?? null;
    // installed-version resolution:
    //   - npm-kind: npm ls map (truth for the agent user's global namespace)
    //   - script-kind: sentinel.version (Phase 5 may add a native version
    //     probe; for Phase 4 the sentinel is the declared-install record)
    const installed =
      entry.source_kind === "npm" && entry.npm_package_name
        ? (npmLs.get(entry.npm_package_name) ?? null)
        : (sentinel?.version ?? null);

    // Upstream-latest (opt-in only): T-04-12 — offline default honored.
    // Errors are non-fatal per-entry so one dead registry call doesn't break
    // the whole upgrade run. The row still renders with latestVersion=null.
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

  // Reconcile loop. Sequential on purpose — concurrent sentinel writes on the
  // same filesystem are safe (atomic rename per agent) but we still want
  // deterministic log ordering for debugging failed upgrades.
  const entryById = new Map(catalog.agents.map((e) => [e.id, e]));
  for (const report of reports) {
    const target = shouldReinstall(report, opts);
    if (!target) continue;

    const entry = entryById.get(report.id);
    if (!entry) continue; // Defensive — should not happen since reports was built from catalog.agents.

    let version: string;
    let source: Sentinel["source"];
    if (target === "latest") {
      if (!report.latestVersion) {
        // --all-latest was requested but upstream didn't produce a version —
        // either script-kind (no npm identity) or the view call failed.
        // Skip with a diagnostic rather than guess at the right action.
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
      continue; // Preserve pre-upgrade sentinel on failure (integrity — don't
      // mark "installed at X" when X didn't actually install).
    }
    if (result.stdout) console.log(result.stdout.trimEnd());

    // Sticky preservation: when source='latest' and a prior sentinel was
    // sticky (user ran `agentlinux pin <name>=latest`), keep the sticky flag.
    // Explicit --reset-all-curated clears sticky (source='curated', sticky=false).
    let sticky = false;
    if (source === "latest") {
      const prior = await readSentinel(entry.id);
      sticky = prior?.sticky ?? false;
    }

    await writeSentinel({
      id: entry.id,
      version,
      source,
      sticky,
      installed_at: new Date().toISOString(),
    });
  }
}
