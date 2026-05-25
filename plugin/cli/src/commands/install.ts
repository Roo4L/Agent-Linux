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
  // Plan 14-03 (REMEDIATE-04 + T-14-12): consent surface for state-overwriting
  // REMEDIATE-04 (uninstall + reinstall a broken/path-mismatched catalog agent).
  // The CLI's --yes is INDEPENDENT of the bash entrypoint's --yes — they're
  // separate operator invocations. Required when stdin is NOT a TTY (CI,
  // cron, curl|bash); interactive sessions skip the gate. CLI never reads
  // AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES env vars (T-14-12 / T-14-01).
  yes?: boolean;
  // Plan 15-01 (UX-01 / D-15-01): preview the install decision (reuse |
  // remediate | create) without dispatching install.sh. Parallels the bash
  // entrypoint's --dry-run flag and exits 0 after emitting the per-agent
  // summary. D-15-04: --dry-run + --yes is contradictory (exit 64) in both
  // orders — the guard fires at the top of installCmd.
  dryRun?: boolean;
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

// Plan 14-03 (REMEDIATE-04): tryRemediate return shape. The reason discriminates
// between the two trigger paths so the [REMEDIATE-04] log line is precise:
//   - "broken"        — detect cache reports status=broken (binary present but
//                       --version exits non-zero, OR path doesn't resolve)
//   - "path-mismatch" — detect cache reports status=healthy BUT the resolved
//                       path differs from CANONICAL_PATHS[id] (e.g. claude
//                       installed via `npm install -g` lands at
//                       ~/.npm-global/bin/claude instead of the canonical
//                       ~/.local/bin/claude — exactly the PATH-MISMATCH case
//                       that motivates this entire feature)
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

  // Cache shape: `agents` may be at the top level (the actual on-disk shape
  // written by detect::run_once at /run/agentlinux-detect.json) OR under
  // `.components.agents` (the wrapped shape that the `--report-only` formatter
  // emits). Accept both for compatibility — matches the `(.components.agents
  // // .agents)` fallback that tests/bats/15-detection.bats uses.
  let cache: { agents?: DetectCacheAgent[]; components?: { agents?: DetectCacheAgent[] } };
  try {
    cache = JSON.parse(readFileSync(cachePath, "utf8"));
  } catch {
    return null;
  }
  const agents = cache.agents ?? cache.components?.agents;
  const detected = agents?.find((a) => a.id === entry.id);
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

// Plan 14-03 (REMEDIATE-04) pre-runner check. Mirrors tryReuse's cache-reader
// shape but with INVERSE discriminator: triggers on the "broken catalog agent"
// path OR the "PATH-MISMATCH" path (status=healthy but detected path !=
// canonical). Both signals mean "AgentLinux is in charge — uninstall + reinstall
// at the canonical location".
//
// Returns null when:
//   - cache absent (no detect:: run; greenfield install)
//   - canonical path not in CANONICAL_PATHS (test_only entry)
//   - cache parse fails (T-14-10 safe-fall-through; same shape as tryReuse)
//   - agent absent from cache (greenfield)
//   - status=absent (greenfield — nothing to remediate)
//   - status=healthy AND path === canonical (REUSE territory, not REMEDIATE)
//
// Returns RemediateHit when:
//   - status=broken (binary present but unhealthy; REMEDIATE)
//   - status=healthy AND path != canonical (PATH-MISMATCH; REMEDIATE-04)
//
// The version check (compatibility_window) is NOT applied here — REMEDIATE-04
// reinstalls at entry.pinned_version regardless of the detected version. That's
// the whole point: the broken/mis-pathed install is being replaced.
function tryRemediate(entry: CatalogEntry): RemediateHit | null {
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
  // Plan 15-01 (D-15-04 / T-15-01-06): --dry-run + --yes is contradictory
  // in BOTH orders. --dry-run NEVER mutates, --yes is a mutation gate; the
  // combination is ambiguous and must be rejected upfront with exit 64
  // EX_USAGE. Mirror the bash entrypoint's symmetric guard in parse_args.
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

  // Plan 15-01 (UX-01 / D-15-01): --dry-run early-return. Compute the same
  // tryReuse + tryRemediate decisions a real install would make, render a
  // [DRY-RUN] summary, and exit 0 WITHOUT calling dispatchRecipe or
  // writeSentinel. Mirrors the bash entrypoint's main() dry-run branch (which
  // hooks AFTER collect_all_decisions, BEFORE flush_bails_or_continue). Skips
  // the --yes consent gate by design — dry-run never mutates so consent does
  // not apply (D-15-04 rejected the combo as contradictory upstream).
  if (opts.dryRun) {
    // Compute decisions the same way the real install path does, but WITHOUT
    // applying --force / --version / existing-sentinel skip semantics — the
    // operator wants to see what *would* happen on a normal invocation.
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
    return; // exit 0; no dispatchRecipe, no writeSentinel
  }

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

  // Plan 14-03 (REMEDIATE-04 CAT-04): the REMEDIATE branch. After REUSE has had
  // its chance, check whether the detect cache reports a state that requires
  // uninstall+reinstall (broken catalog agent OR PATH-MISMATCH). Skip when:
  //   - opts.force      (--force always installs fresh at the canonical path
  //                      without consulting detect; mirrors REUSE skip semantic)
  //   - opts.version    (explicit version override = "I want this exact version",
  //                      not adoption-via-remediation)
  // Note: unlike REUSE, REMEDIATE-04 DOES fire even when a sentinel exists —
  // the existing sentinel tells us "AgentLinux thought it owned this install"
  // but the detect cache says "but it's broken/mispathed now". Remediating is
  // the right response.
  const remediateHit = !opts.force && !opts.version ? tryRemediate(entry) : null;
  if (remediateHit) {
    // T-14-12 mitigation: --yes is the SOLE consent surface. CLI never reads
    // AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES env vars (verified by bats
    // grep). In TTY mode the gate auto-passes — Phase 15 will add an
    // interactive `Proceed? [Y/n]` prompt here on top of the same predicate.
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
    // when present (so uninstall.sh knows what it's tearing down); falls back
    // to the catalog's pinned_version when no sentinel exists (e.g. brownfield
    // claude installed via npm, no AgentLinux sentinel ever written).
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

    // T-14-05 mitigation: post-uninstall verification. uninstall.sh could exit
    // 0 while leaving the binary at either the canonical path OR the detected
    // (PATH-MISMATCH) path. Check BOTH — if either still exists, we cannot
    // proceed to install (would risk double-install / corrupted state).
    if (existsSync(remediateHit.canonical_path) || existsSync(remediateHit.detected_path)) {
      console.error(
        `[REMEDIATE-04:uninstall-incomplete] ${entry.id} uninstall.sh exited 0 but binary still present (canonical=${existsSync(remediateHit.canonical_path)} detected=${existsSync(remediateHit.detected_path)})`,
      );
      process.exit(1); // runtime
    }

    // Step 2: install.sh at the catalog's pinned_version. On failure we land
    // in the half-uninstalled state (uninstall succeeded, install failed) —
    // write a broken-after-remediate sentinel as forensic trail + exit 1.
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

    // Step 3: success — write status=installed sentinel + remediated_at trail.
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
