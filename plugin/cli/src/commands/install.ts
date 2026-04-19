// plugin/cli/src/commands/install.ts — `agentlinux install <name>` (CLI-03).
// Pattern ref: 04-RESEARCH §Pattern 3 lines 555-628.
//
// Flow:
//   1. loadCatalog(validate:true) — ajv rejects malformed catalogs up front
//   2. Resolve entry by string equality; process.exit(64) on miss (EX_USAGE)
//   3. Honor test_only unless --include-test (RESEARCH §Pattern 11)
//   4. Validate opts.version semver if provided
//   5. decideVersion(entry, --version, existing sentinel) → {version, source, sticky}
//   6. Idempotent short-circuit: same version + !force → log and return
//   7. dispatchRecipe(install.sh) via runner.ts — env-injected, sudo -u agent
//   8. writeSentinel on success; atomic rename guarantees no partial state
//
// Testability: accepts optional `dispatcher` parameter (DI seam — same as
// runner.ts). Default dispatches through the real runner; tests inject
// capturing mocks to assert call shape + idempotency + override paths.

import { join } from "node:path";
import semver from "semver";
import { loadCatalog } from "../catalog/loader.js";
import { type Dispatcher, dispatchRecipe } from "../runner.js";
import { readSentinel, writeSentinel } from "../state/sentinel.js";
import { decideVersion } from "../version/classify.js";

export interface InstallOpts {
  force?: boolean;
  version?: string;
  json?: boolean;
  includeTest?: boolean;
}

export async function installCmd(
  name: string,
  opts: InstallOpts,
  dispatcher?: Dispatcher,
): Promise<void> {
  const catalog = await loadCatalog({ validate: true });
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

  // test_only: hidden from default `list` and refused by default `install`.
  // --include-test opts in for bats integration + developer-debug flows.
  if (entry.test_only && !opts.includeTest) {
    console.error(`agentlinux: ${name} is a test-only entry; pass --include-test to install`);
    process.exit(64);
  }

  if (opts.version !== undefined && !semver.valid(opts.version)) {
    console.error(`agentlinux: --version '${opts.version}' is not a valid semver`);
    process.exit(64);
  }

  const existing = await readSentinel(entry.id);
  const decision = decideVersion(entry, opts.version, existing);

  // Idempotent short-circuit: sentinel-version === decision-version and no
  // --force → log "already installed" and return 0. T-04-08 mitigation:
  // second invocation produces byte-stable result.
  if (!opts.force && existing && semver.eq(existing.version, decision.version)) {
    console.log(
      `${entry.id}: already installed at ${existing.version} (${existing.source}); no-op`,
    );
    return;
  }

  const recipePath = join(catalog.catalogDir, "agents", entry.id, entry.install_recipe_path);
  const result = await dispatchRecipe(
    {
      entry,
      recipePath,
      version: decision.version,
      catalogDir: catalog.catalogDir,
    },
    dispatcher,
  );

  if (result.exitCode !== 0) {
    console.error(`${entry.id}: install.sh failed (exit ${result.exitCode})`);
    if (result.stderr) console.error(result.stderr);
    process.exit(result.exitCode);
  }
  if (result.stdout) console.log(result.stdout.trimEnd());

  await writeSentinel({
    id: entry.id,
    version: decision.version,
    source: decision.source,
    sticky: decision.sticky,
    installed_at: new Date().toISOString(),
  });

  console.log(`${entry.id}: installed ${decision.version} (${decision.source})`);
}
