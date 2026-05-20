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

import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import semver from "semver";
import { loadCatalog } from "../catalog/loader.js";
import { type Dispatcher, dispatchRecipe } from "../runner.js";
import { readSentinel, writeSentinel } from "../state/sentinel.js";
import type { CatalogEntry } from "../types.js";
import { decideVersion } from "../version/classify.js";

export interface InstallOpts {
  force?: boolean;
  version?: string;
  json?: boolean;
  includeTest?: boolean;
}

// REUSE-03 canonical path map (Plan 13-02). MUST stay byte-identical to the
// bash REUSE_AGENT_CANONICAL_PATHS in plugin/lib/reuse/agents.sh. Drift
// surfaces immediately in the brownfield E2E smoke @test (REUSE-03 path-match
// fails -> emits remediate instead of reuse).
//
// claude-code's canonical path is ~agent/.local/bin/claude (the native
// installer's default), NOT ~agent/.npm-global/bin/claude — the latter is
// PATH-MISMATCH territory handled by Phase 14 REMEDIATE-04.
const CANONICAL_PATHS: Record<string, string> = {
  "claude-code": "/home/agent/.local/bin/claude",
  gsd: "/home/agent/.npm-global/bin/get-shit-done-cc",
  "playwright-cli": "/home/agent/.npm-global/bin/playwright-cli",
};

interface ReuseHit {
  binary_path: string;
  version: string;
  detected_source: string;
}

interface DetectCacheAgent {
  id: string;
  status: string;
  path: string;
  version: string;
}

// REUSE-03 cache reader. AGENTLINUX_DETECT_CACHE env override is install.ts-
// ONLY (T-13-05 mitigation; upgrade.ts + remove.ts do not read the detect
// cache — they only re-validate via existsSync(sentinel.binary_path)).
function detectCachePath(): string {
  return process.env.AGENTLINUX_DETECT_CACHE ?? "/run/agentlinux-detect.json";
}

// REUSE-03 pre-runner check: parse /run/agentlinux-detect.json + semver-check
// the catalog's compatibility_window against the detected version. Returns a
// ReuseHit on full match, null on any non-REUSE condition (absent agent,
// path-mismatch, version-out-of-window, missing cache, etc.).
//
// T-13-07 mitigation: re-validate the binary actually exists at install time
// via statSync (cache may be stale; user may have uninstalled between
// detect:: run and CLI invocation).
function tryReuse(entry: CatalogEntry): ReuseHit | null {
  const cachePath = detectCachePath();
  if (!existsSync(cachePath)) return null;
  if (!entry.compatibility_window) return null;
  const canonical = CANONICAL_PATHS[entry.id];
  if (!canonical) return null;

  let cache: { components?: { agents?: DetectCacheAgent[] } };
  try {
    cache = JSON.parse(readFileSync(cachePath, "utf8"));
  } catch {
    return null;
  }
  const detected = cache.components?.agents?.find((a) => a.id === entry.id);
  if (!detected) return null;
  if (detected.status !== "healthy") return null;
  if (detected.path !== canonical) return null;
  if (!semver.valid(detected.version)) return null;
  if (!semver.satisfies(detected.version, entry.compatibility_window)) return null;

  // T-13-07 mitigation: re-validate the binary actually exists at install time.
  // The cache is overwritten on every agentlinux-install run, but the binary
  // itself could have been removed by an unrelated process between detect::
  // run_once and the CLI install.ts invocation.
  try {
    const st = statSync(detected.path);
    if (!st.isFile()) return null;
  } catch {
    return null;
  }
  return {
    binary_path: detected.path,
    version: detected.version,
    detected_source: "pre-existing",
  };
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

  // REUSE-03 pre-runner check (Plan 13-02). Phase 12 cache at the path resolved
  // by detectCachePath() is populated by the bash entrypoint's detect::run_once.
  // When the detected state is { status: "healthy", path: canonical, version
  // satisfies compatibility_window }, skip dispatchRecipe entirely and write a
  // status: "reused" sentinel.
  //
  // Skip the REUSE check when:
  //   - opts.force          (force always installs fresh)
  //   - opts.version        (explicit version override means "I want this exact
  //                          version", not adoption)
  //   - existing sentinel   (don't override an existing installed/reused record)
  const reuseHit = !opts.force && !opts.version && !existing ? tryReuse(entry) : null;
  if (reuseHit) {
    const now = new Date().toISOString();
    await writeSentinel({
      id: entry.id,
      version: reuseHit.version,
      source: "curated",
      sticky: false,
      installed_at: now,
      status: "reused",
      binary_path: reuseHit.binary_path,
      detected_source: reuseHit.detected_source,
      reused_at: now,
      compatibility_window_at_reuse: entry.compatibility_window,
    });
    console.log(
      `[REUSE-03] ${entry.id} reused: binary=${reuseHit.binary_path} version=${reuseHit.version} (in window ${entry.compatibility_window}) status=healthy`,
    );
    return;
  }

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
    status: "installed",
  });

  console.log(`${entry.id}: installed ${decision.version} (${decision.source})`);
}
