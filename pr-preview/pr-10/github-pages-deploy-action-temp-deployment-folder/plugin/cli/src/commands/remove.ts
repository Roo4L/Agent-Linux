// plugin/cli/src/commands/remove.ts — `agentlinux remove <name>` (CLI-04).
// Pattern ref: 04-RESEARCH §Pattern 4 lines 631-668.
//
// Flow:
//   1. loadCatalog(validate:true) — reject malformed catalogs
//   2. Resolve entry by id; process.exit(64) on miss
//   3. readSentinel → if null: exit 1 unless --force (idempotent no-op)
//   4. dispatchRecipe(uninstall.sh) via runner.ts
//   5. deleteSentinel — idempotent (ENOENT-safe)
//
// T-04-09 mitigation: sentinel MUST exist unless --force — prevents
// "remove any catalog entry" drive-by on a never-installed agent.
//
// Testability: accepts optional `dispatcher` DI seam (same shape as
// installCmd). Default routes through the real runner; tests inject a
// capturing mock.

import { join } from "node:path";
import { loadCatalog } from "../catalog/loader.js";
import { type Dispatcher, dispatchRecipe } from "../runner.js";
import { deleteSentinel, readSentinel } from "../state/sentinel.js";

export interface RemoveOpts {
  force?: boolean;
}

export async function removeCmd(
  name: string,
  opts: RemoveOpts,
  dispatcher?: Dispatcher,
): Promise<void> {
  const catalog = await loadCatalog({ validate: true });
  const entry = catalog.agents.find((a) => a.id === name);

  if (!entry) {
    console.error(`agentlinux: no such agent in catalog: ${name}`);
    process.exit(64);
  }

  const sentinel = await readSentinel(entry.id);
  if (!sentinel) {
    if (!opts.force) {
      console.error(`agentlinux: ${entry.id} is not installed (pass --force for no-op)`);
      process.exit(1);
    }
    return; // --force + not-installed = idempotent exit 0
  }

  const recipePath = join(catalog.catalogDir, "agents", entry.id, entry.uninstall_recipe_path);
  const result = await dispatchRecipe(
    {
      entry,
      recipePath,
      version: sentinel.version,
      catalogDir: catalog.catalogDir,
    },
    dispatcher,
  );

  if (result.exitCode !== 0) {
    console.error(`${entry.id}: uninstall.sh failed (exit ${result.exitCode})`);
    if (result.stderr) console.error(result.stderr);
    process.exit(result.exitCode);
  }
  if (result.stdout) console.log(result.stdout.trimEnd());

  await deleteSentinel(entry.id);
  console.log(`${entry.id}: removed`);
}
