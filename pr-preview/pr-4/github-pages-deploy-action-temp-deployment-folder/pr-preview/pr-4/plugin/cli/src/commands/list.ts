// plugin/cli/src/commands/list.ts — `agentlinux list` implementation (CLI-02).
// Pattern ref: 04-RESEARCH §Component Responsibilities (list) + §Pattern 6
// (Status classifier). Hot path: skips ajv validation per 04-RESEARCH Open
// Question 2 resolution — pre-commit + install/upgrade paths validate; list
// tolerates a partially-invalid catalog so it can still surface info.
//
// Installed-version detection for Phase 4: the sentinel's recorded version is
// the truth we render. Phase 5 (AGT-XX) may cross-check against
// `npm ls -g --json` for drift detection; deferred out of Phase 4 per
// Pitfall 4 (npm ls output shape) + scope.

import { loadCatalog } from "../catalog/loader.js";
import { listSentinels } from "../state/sentinel.js";
import type { CatalogEntry, Sentinel, Status } from "../types.js";
import { classify } from "../version/classify.js";

export interface ListOpts {
  json?: boolean;
  includeTest?: boolean;
}

interface Row {
  id: string;
  display_name: string;
  status: Status;
  curated: string; // entry.pinned_version
  installed: string; // sentinel?.version ?? '-'
  description: string;
  source: Sentinel["source"] | "-";
}

function buildRows(entries: CatalogEntry[], sentinels: Sentinel[]): Row[] {
  const bySentinel = new Map(sentinels.map((s) => [s.id, s]));
  return entries.map((entry) => {
    const sentinel = bySentinel.get(entry.id) ?? null;
    // Phase 4: installed = sentinel.version (no npm ls cross-check yet).
    const installed = sentinel?.version ?? null;
    const status = classify({ entry, sentinel, installed });
    return {
      id: entry.id,
      display_name: entry.display_name,
      status,
      curated: entry.pinned_version,
      installed: installed ?? "-",
      description: entry.description,
      source: sentinel?.source ?? "-",
    };
  });
}

export async function listCmd(opts: ListOpts): Promise<void> {
  // Hot path: validate:false — Open Question 2 resolution.
  const catalog = await loadCatalog({ validate: false });
  const sentinels = await listSentinels();

  const visible = catalog.agents.filter((a) => opts.includeTest || !a.test_only);
  const rows = buildRows(visible, sentinels);

  if (opts.json) {
    console.log(JSON.stringify(rows, null, 2));
    return;
  }

  // Text table: grep-friendly, no color, no box chars.
  // Columns per CONTEXT §CLI UX: NAME STATUS CURATED INSTALLED DESCRIPTION.
  const header = ["NAME", "STATUS", "CURATED", "INSTALLED", "DESCRIPTION"];
  const data = rows.map((r) => [r.id, r.status, r.curated, r.installed, r.description]);
  const all = [header, ...data];
  const widths = header.map((_, i) => Math.max(...all.map((row) => row[i].length)));
  for (const row of all) {
    console.log(row.map((c, i) => c.padEnd(widths[i])).join("  "));
  }
}
