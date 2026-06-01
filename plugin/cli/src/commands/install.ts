// plugin/cli/src/commands/install.ts — `agentlinux install <name>` (CLI-03).
//
// Flow: loadCatalog → resolve entry (exit 64 on miss) → honor test_only →
// REUSE-03 / REMEDIATE-04 short-circuits → decideVersion → dispatchRecipe →
// writeSentinel. The optional `dispatcher` param is a DI seam for unit tests.

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
  // Consent surface for state-overwriting REMEDIATE-04. Required when stdin is
  // not a TTY; interactive sessions skip the gate. No env-var equivalent — the
  // CLI never reads AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES.
  yes?: boolean;
  // UX-01: preview the install decision (reuse|remediate|create) without
  // dispatching install.sh; exits 0. Contradicts --yes (exit 64, both orders).
  dryRun?: boolean;
}

// REUSE-03 canonical path map. MUST stay byte-identical to the bash
// REUSE_AGENT_CANONICAL_PATHS in plugin/lib/reuse/agents.sh. claude-code's
// canonical path is the native installer's ~agent/.local/bin/claude, NOT the
// npm-global variant (that's PATH-MISMATCH territory for REMEDIATE-04).
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

// REMEDIATE-04: tryRemediate return shape. `reason` discriminates the two
// trigger paths for the log line:
//   - "broken"        — detect cache reports status=broken
//   - "path-mismatch" — status=healthy but resolved path != CANONICAL_PATHS[id]
//                       (e.g. `npm install -g` landed claude at the npm-global
//                       path instead of the canonical native one)
interface RemediateHit {
  reason: "broken" | "path-mismatch";
  detected_path: string;
  canonical_path: string;
}

interface DetectCacheAgent {
  id: string;
  status: string;
  path: string;
  version: string;
}

// REUSE-03 cache reader. The AGENTLINUX_DETECT_CACHE override is install.ts-only
// — upgrade.ts and remove.ts never read the detect cache.
function detectCachePath(): string {
  return process.env.AGENTLINUX_DETECT_CACHE ?? "/run/agentlinux-detect.json";
}

// Shared detect-cache reader for tryReuse / tryRemediate. Resolves the cache
// path, parses it (accepting both the on-disk top-level `agents` shape from
// detect::run_once AND the `--report-only` `.components.agents` wrapped shape),
// and returns the detected agent for <entry> with its canonical path. Returns
// null on every condition both callers treat as "not a candidate": cache
// absent/unparseable, id has no canonical path, or the agent isn't in the cache.
function readDetectedAgent(
  entry: CatalogEntry,
): { detected: DetectCacheAgent; canonical: string } | null {
  const cachePath = detectCachePath();
  if (!existsSync(cachePath)) return null;
  const canonical = CANONICAL_PATHS[entry.id];
  if (!canonical) return null;
  let cache: { agents?: DetectCacheAgent[]; components?: { agents?: DetectCacheAgent[] } };
  try {
    cache = JSON.parse(readFileSync(cachePath, "utf8"));
  } catch {
    return null;
  }
  const agents = cache.agents ?? cache.components?.agents;
  const detected = agents?.find((a) => a.id === entry.id);
  if (!detected) return null;
  return { detected, canonical };
}

// REUSE-03 pre-runner check: read the detect cache + semver-check the catalog's
// compatibility_window against the detected version. Returns a ReuseHit on full
// match, null on any non-REUSE condition (absent agent, path-mismatch,
// version-out-of-window, missing cache, etc.).
function tryReuse(entry: CatalogEntry): ReuseHit | null {
  if (!entry.compatibility_window) return null;
  const hit = readDetectedAgent(entry);
  if (!hit) return null;
  const { detected, canonical } = hit;
  if (detected.status !== "healthy") return null;
  if (detected.path !== canonical) return null;
  if (!semver.valid(detected.version)) return null;
  if (!semver.satisfies(detected.version, entry.compatibility_window)) return null;

  // Re-validate the binary actually exists at install time — the cache may be
  // stale (binary removed by an unrelated process since detect::run_once).
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

// REMEDIATE-04 pre-runner check. Shares readDetectedAgent with tryReuse but
// applies the inverse discriminator: returns a RemediateHit when status=broken
// OR status=healthy with a non-canonical path (PATH-MISMATCH); null otherwise
// (cache absent, parse fails, greenfield, or REUSE territory). No
// compatibility_window check — REMEDIATE-04 reinstalls at pinned_version
// regardless of detected version, since the bad install is being replaced.
function tryRemediate(entry: CatalogEntry): RemediateHit | null {
  const hit = readDetectedAgent(entry);
  if (!hit) return null;
  const { detected, canonical } = hit;
  if (detected.status === "broken") {
    return { reason: "broken", detected_path: detected.path, canonical_path: canonical };
  }
  if (detected.status === "healthy" && detected.path !== canonical) {
    return { reason: "path-mismatch", detected_path: detected.path, canonical_path: canonical };
  }
  return null;
}

export async function installCmd(
  name: string,
  opts: InstallOpts,
  dispatcher?: Dispatcher,
): Promise<void> {
  // --dry-run + --yes is contradictory (dry-run never mutates; --yes is a
  // mutation gate). Reject upfront with exit 64; mirrors the bash entrypoint.
  if (opts.dryRun && opts.yes) {
    console.error(
      "agentlinux install: contradictory flags — --dry-run forbids --yes (dry-run never mutates; --yes is a mutation gate)",
    );
    process.exit(64); // EX_USAGE
  }

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

  // test_only entries are refused unless --include-test.
  if (entry.test_only && !opts.includeTest) {
    console.error(`agentlinux: ${name} is a test-only entry; pass --include-test to install`);
    process.exit(64);
  }

  if (opts.version !== undefined && !semver.valid(opts.version)) {
    console.error(`agentlinux: --version '${opts.version}' is not a valid semver`);
    process.exit(64);
  }

  const existing = await readSentinel(entry.id);

  // UX-01: --dry-run early-return. Compute the same reuse/remediate decisions a
  // real install would make, render a summary, and exit 0 without dispatching
  // or writing a sentinel.
  if (opts.dryRun) {
    const reuseHit = !opts.force && !opts.version && !existing ? tryReuse(entry) : null;
    const remediateHit = !opts.force && !opts.version && !reuseHit ? tryRemediate(entry) : null;
    const decision: "reuse" | "remediate" | "create" = reuseHit
      ? "reuse"
      : remediateHit
        ? "remediate"
        : "create";
    const wouldAction =
      decision === "reuse"
        ? `short-circuit (binary at ${reuseHit?.binary_path ?? "?"})`
        : decision === "remediate"
          ? `uninstall + reinstall (reason: ${remediateHit?.reason ?? "?"}; detected at ${remediateHit?.detected_path ?? "?"}; canonical at ${remediateHit?.canonical_path ?? "?"})`
          : `dispatch install.sh at version ${entry.pinned_version}`;
    const summary = {
      id: entry.id,
      decision,
      detected_path: remediateHit?.detected_path ?? reuseHit?.binary_path ?? null,
      canonical_path: remediateHit?.canonical_path ?? null,
      pinned_version: entry.pinned_version,
      would_action: wouldAction,
    };
    if (opts.json) {
      console.log(JSON.stringify(summary, null, 2));
    } else {
      console.log(`[DRY-RUN] ${entry.id}: ${decision} — would ${wouldAction}`);
    }
    return;
  }

  // REUSE-03: when the detect cache reports a healthy install at the canonical
  // path whose version satisfies compatibility_window, skip dispatchRecipe and
  // write a status: "reused" sentinel. Skipped on --force, --version, or an
  // existing sentinel (don't adopt over an explicit/recorded install).
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

  // REMEDIATE-04: after REUSE, check whether the detect cache reports a state
  // that needs uninstall+reinstall (broken or PATH-MISMATCH). Skipped on
  // --force / --version. Unlike REUSE, this fires even when a sentinel exists —
  // a recorded install that's now broken/mispathed still needs remediating.
  const remediateHit = !opts.force && !opts.version ? tryRemediate(entry) : null;
  if (remediateHit) {
    // --yes is the sole consent surface (no env-var equivalent). In TTY mode
    // the gate auto-passes.
    const isTTY = process.stdin.isTTY === true;
    if (!opts.yes && !isTTY) {
      console.error(
        "Refusing to proceed — 1 component needs Remediate (run with --yes to apply, or --dry-run to preview):\n",
      );
      console.error(
        `[BAIL] component=${entry.id} reason=${remediateHit.reason} hint=run with --yes to reinstall`,
      );
      console.error(
        "\nExit code 65 (EX_DATAERR — incompatible host state). See agentlinux install --help.",
      );
      process.exit(65); // EX_DATAERR
    }

    console.log(
      `[REMEDIATE-04] ${entry.id} component=${entry.id} reason=${remediateHit.reason} detected_path=${remediateHit.detected_path} canonical_path=${remediateHit.canonical_path} — uninstall + reinstall`,
    );

    // Step 1: uninstall.sh. Version env carries the existing-sentinel version
    // when present, else the catalog's pinned_version (brownfield: no sentinel).
    const uninstallPath = join(catalog.catalogDir, "agents", entry.id, entry.uninstall_recipe_path);
    const uninstallResult = await dispatchRecipe(
      {
        entry,
        recipePath: uninstallPath,
        version: existing?.version ?? entry.pinned_version,
        catalogDir: catalog.catalogDir,
      },
      dispatcher,
    );
    if (uninstallResult.exitCode !== 0) {
      console.error(
        `[REMEDIATE-04:uninstall-fail] ${entry.id} uninstall.sh exited ${uninstallResult.exitCode}`,
      );
      if (uninstallResult.stderr) console.error(uninstallResult.stderr);
      process.exit(1); // runtime
    }

    // Post-uninstall verification: uninstall.sh could exit 0 while leaving the
    // binary at the canonical OR detected path. If either remains, abort rather
    // than risk a double-install.
    if (existsSync(remediateHit.canonical_path) || existsSync(remediateHit.detected_path)) {
      console.error(
        `[REMEDIATE-04:uninstall-incomplete] ${entry.id} uninstall.sh exited 0 but binary still present (canonical=${existsSync(remediateHit.canonical_path)} detected=${existsSync(remediateHit.detected_path)})`,
      );
      process.exit(1); // runtime
    }

    // Step 2: install.sh at pinned_version. On failure we're half-uninstalled —
    // write a broken-after-remediate sentinel as a forensic trail + exit 1.
    const installPath = join(catalog.catalogDir, "agents", entry.id, entry.install_recipe_path);
    const installResult = await dispatchRecipe(
      {
        entry,
        recipePath: installPath,
        version: entry.pinned_version,
        catalogDir: catalog.catalogDir,
      },
      dispatcher,
    );
    if (installResult.exitCode !== 0) {
      const now = new Date().toISOString();
      await writeSentinel({
        id: entry.id,
        version: entry.pinned_version,
        source: "curated",
        sticky: false,
        installed_at: now,
        status: "broken-after-remediate",
        remediated_at: now,
        remediate_failure_reason: "install-failed-post-uninstall",
      });
      console.error(
        `[REMEDIATE-04:half-uninstalled] ${entry.id} install.sh exited ${installResult.exitCode} after uninstall succeeded — manual recovery needed (run agentlinux remove ${entry.id} then agentlinux install ${entry.id})`,
      );
      if (installResult.stderr) console.error(installResult.stderr);
      process.exit(1); // runtime
    }
    if (installResult.stdout) console.log(installResult.stdout.trimEnd());

    // Step 3: success — status=installed sentinel + remediated_at trail.
    const now = new Date().toISOString();
    await writeSentinel({
      id: entry.id,
      version: entry.pinned_version,
      source: "curated",
      sticky: false,
      installed_at: now,
      status: "installed",
      remediated_at: now,
    });
    console.log(`[REMEDIATE-04] ${entry.id}: reinstalled at ${entry.pinned_version}`);
    return;
  }

  const decision = decideVersion(entry, opts.version, existing);

  // Idempotent short-circuit: same version + no --force → "already installed".
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
