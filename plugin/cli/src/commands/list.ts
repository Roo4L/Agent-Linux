// plugin/cli/src/commands/list.ts — `agentlinux list` implementation (CLI-02).
// Hot path: skips ajv validation (install/upgrade validate) so a partially
// invalid catalog can still be listed. Installed version = the sentinel's
// recorded version; no npm ls cross-check.

import { loadCatalog } from "../catalog/loader.js";
import { detectPresence } from "../detect.js";
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
  // REUSE-03: a "reused" sentinel means AgentLinux manages the adopted binary
  // (upgrade/remove act on it). The text renderer discloses this via a suffix
  // on the INSTALLED column.
  reused: boolean;
  // AL-61: no sentinel, but the detect cache reports the agent healthy at its
  // canonical presence — physically present, just not adopted. The text renderer
  // appends a "run install to manage" hint; JSON carries the flag verbatim.
  present: boolean;
  // Text renderer appends a distinct suffix per status; JSON carries it verbatim.
  sentinel_status?: "installed" | "reused" | "broken-after-remediate" | "reused-with-warning";
  // Carried to JSON verbatim; set only when sentinel_status === "reused-with-warning".
  decline_reason?: string;
}

function buildRows(entries: CatalogEntry[], sentinels: Sentinel[]): Row[] {
  const bySentinel = new Map(sentinels.map((s) => [s.id, s]));
  return entries.map((entry) => {
    const sentinel = bySentinel.get(entry.id) ?? null;
    let installed = sentinel?.version ?? null;
    let status = classify({ entry, sentinel, installed });
    // AL-61 presence overlay: classify() returns "not-installed" whenever no
    // sentinel exists, even for tools the host already has. Reconcile against the
    // detect cache so a present-but-unadopted agent reads "present" with its
    // detected version instead of being reported absent.
    let present = false;
    if (status === "not-installed") {
      const hit = detectPresence(entry);
      if (hit) {
        status = "present";
        present = true;
        installed = hit.version; // may be null → renders "-"
      }
    }
    const reused = sentinel?.status === "reused";
    return {
      id: entry.id,
      display_name: entry.display_name,
      status,
      curated: entry.pinned_version,
      installed: installed ?? "-",
      description: entry.description,
      source: sentinel?.source ?? "-",
      reused,
      present,
      sentinel_status: sentinel?.status,
      decline_reason: sentinel?.decline_reason,
    };
  });
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

  // Text table: grep-friendly, no color. Columns: NAME STATUS CURATED INSTALLED
  // DESCRIPTION. The INSTALLED-column suffixes below are binding wording — bats
  // greps the literal strings. Precedence: broken-after-remediate >
  // reused-with-warning > reused > present (present only fires with no sentinel,
  // so it never collides with the sentinel_status suffixes).
  const REUSED_SUFFIX = " (reused — managed by agentlinux upgrade/remove)";
  const BROKEN_AFTER_REMEDIATE_SUFFIX = " (broken — half-uninstalled, manual recovery needed)";
  const reusedWithWarningSuffix = (reason: string) =>
    ` (reused — declined remediation: ${reason}; manual fix needed)`;
  const presentSuffix = (id: string) => ` (detected — run: agentlinux install ${id} to manage)`;
  const header = ["NAME", "STATUS", "CURATED", "INSTALLED", "DESCRIPTION"];
  const data = rows.map((r) => {
    let installed = r.installed;
    if (r.sentinel_status === "broken-after-remediate") {
      installed = `${r.installed}${BROKEN_AFTER_REMEDIATE_SUFFIX}`;
    } else if (r.sentinel_status === "reused-with-warning") {
      installed = `${r.installed}${reusedWithWarningSuffix(r.decline_reason ?? "unknown")}`;
    } else if (r.reused) {
      installed = `${r.installed}${REUSED_SUFFIX}`;
    } else if (r.present) {
      installed = `${r.installed}${presentSuffix(r.id)}`;
    }
    return [r.id, r.status, r.curated, installed, r.description];
  });
  const all = [header, ...data];
  const widths = header.map((_, i) => Math.max(...all.map((row) => row[i].length)));
  for (const row of all) {
    console.log(row.map((c, i) => c.padEnd(widths[i])).join("  "));
  }
}
