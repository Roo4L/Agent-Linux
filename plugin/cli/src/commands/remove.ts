// plugin/cli/src/commands/remove.ts — `agentlinux remove <name>` (CLI-04).
//
// Flow: loadCatalog → resolve entry (exit 64 on miss) → readSentinel (exit 1
// unless --force) → dispatchRecipe(uninstall.sh) → deleteSentinel. Requiring a
// sentinel (unless --force) prevents a drive-by remove on a never-installed
// agent. The optional `dispatcher` param is a DI seam for unit tests.

import { existsSync } from "node:fs";
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

  // For a "reused" (adopted) sentinel whose binary has since vanished, running
  // uninstall.sh against a missing binary is wasteful and may fail noisily.
  // Just delete the sentinel — the user's intent (stop tracking) is met.
  if (sentinel.status === "reused" && sentinel.binary_path && !existsSync(sentinel.binary_path)) {
    await deleteSentinel(entry.id);
    console.log(
      `${entry.id}: sentinel removed (binary at ${sentinel.binary_path} was already gone — adopted binary no longer present)`,
    );
    return;
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
