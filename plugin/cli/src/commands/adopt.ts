// plugin/cli/src/commands/adopt.ts — `agentlinux adopt [<name>] [--all]` (AL-61).
//
// Records pre-existing, reuse-eligible agents into sentinels WITHOUT installing
// anything. For each target with no sentinel: if the detect cache reports it
// healthy at its canonical presence and within compatibility_window (tryReuse),
// write a status:"reused" sentinel. Never dispatches a recipe, never downloads,
// never remediates, needs no --yes — it only records reality the host already
// holds, so `agentlinux list` stops reporting present tools as not-installed.
//
// The base installer runs `agentlinux adopt --all` (as the agent user) after a
// successful `--yes` apply. "No agent installed by default" still holds: adopt
// fetches nothing — it only adopts what detection already found.

import { loadCatalog } from "../catalog/loader.js";
import { tryRemediate, tryReuse } from "../detect.js";
import { readSentinel, writeSentinel } from "../state/sentinel.js";
import type { CatalogEntry } from "../types.js";

export interface AdoptOpts {
  all?: boolean;
  json?: boolean;
  includeTest?: boolean;
}

type AdoptAction = "adopted" | "already-managed" | "skipped" | "migrate-available";

interface AdoptResult {
  id: string;
  action: AdoptAction;
  version?: string;
  reason?: string;
}

async function adoptOne(entry: CatalogEntry): Promise<AdoptResult> {
  // Never adopt over an existing record — a real install/remediate already owns
  // this sentinel.
  const existing = await readSentinel(entry.id);
  if (existing) {
    return { id: entry.id, action: "already-managed", version: existing.version };
  }
  const hit = tryReuse(entry);
  if (!hit) {
    // Not reuse-eligible. AL-62: distinguish a migration candidate (healthy but
    // at a non-canonical path — e.g. claude installed via npm) from a plain skip,
    // so adopt-on-install surfaces it in the transcript. adopt never migrates
    // (that uninstall+reinstall needs consent via `agentlinux install`).
    const rem = tryRemediate(entry);
    if (rem?.reason === "path-mismatch") {
      return {
        id: entry.id,
        action: "migrate-available",
        version: rem.detected_version ?? undefined,
        reason: `present at ${rem.detected_path} (non-canonical) — run \`agentlinux install ${entry.id}\` to migrate to the native install`,
      };
    }
    return {
      id: entry.id,
      action: "skipped",
      reason: "not reuse-eligible (absent, out-of-window, broken, or wrong path)",
    };
  }
  const now = new Date().toISOString();
  await writeSentinel({
    id: entry.id,
    version: hit.version,
    source: "curated",
    sticky: false,
    installed_at: now,
    status: "reused",
    binary_path: hit.binary_path,
    detected_source: hit.detected_source,
    reused_at: now,
    compatibility_window_at_reuse: entry.compatibility_window,
  });
  return { id: entry.id, action: "adopted", version: hit.version };
}

export async function adoptCmd(name: string | undefined, opts: AdoptOpts): Promise<void> {
  // Hot path like list: a partially-invalid catalog shouldn't block adopting the
  // valid entries it still describes.
  const catalog = await loadCatalog({ validate: false });

  let targets: CatalogEntry[];
  if (name) {
    const entry = catalog.agents.find((a) => a.id === name);
    if (!entry) {
      const available = catalog.agents
        .filter((a) => !a.test_only)
        .map((a) => a.id)
        .join(", ");
      console.error(`agentlinux: no such agent in catalog: ${name}`);
      console.error(`  available: ${available}`);
      process.exit(64); // EX_USAGE
    }
    if (entry.test_only && !opts.includeTest) {
      console.error(`agentlinux: ${name} is a test-only entry; pass --include-test to adopt`);
      process.exit(64);
    }
    targets = [entry];
  } else if (opts.all) {
    targets = catalog.agents.filter((a) => opts.includeTest || !a.test_only);
  } else {
    console.error("agentlinux adopt: specify an agent name or --all");
    process.exit(64); // EX_USAGE
  }

  const results: AdoptResult[] = [];
  for (const entry of targets) {
    results.push(await adoptOne(entry));
  }

  if (opts.json) {
    console.log(JSON.stringify(results, null, 2));
    return;
  }

  for (const r of results) {
    if (r.action === "adopted") {
      console.log(
        `[ADOPT] ${r.id}: adopted pre-existing install ${r.version} (status=reused — managed by agentlinux upgrade/remove)`,
      );
    } else if (r.action === "already-managed") {
      console.log(`${r.id}: already managed at ${r.version}; no-op`);
    } else if (r.action === "migrate-available") {
      console.log(`[MIGRATE] ${r.id}: ${r.reason}`);
    } else {
      console.log(`${r.id}: nothing to adopt — ${r.reason}`);
    }
  }
}
