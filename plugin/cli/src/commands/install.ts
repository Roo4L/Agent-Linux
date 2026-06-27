// plugin/cli/src/commands/install.ts — `agentlinux install <name>` (CLI-03).
//
// Flow: loadCatalog → resolve entry (exit 64 on miss) → honor test_only →
// REUSE-03 / REMEDIATE-04 short-circuits → decideVersion → dispatchRecipe →
// writeSentinel. The optional `dispatcher` param is a DI seam for unit tests.
//
// The REUSE-03 / REMEDIATE-04 detect-cache helpers (tryReuse, tryRemediate,
// CANONICAL_PATHS, …) live in ../detect.js so install, adopt, and list share
// one canonical-path map and one cache parser.

import { existsSync } from "node:fs";
import { join } from "node:path";
import semver from "semver";
import { loadCatalog } from "../catalog/loader.js";
import { tryRemediate, tryReuse } from "../detect.js";
import { type Dispatcher, dispatchRecipe } from "../runner.js";
import { readSentinel, writeSentinel } from "../state/sentinel.js";
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
    // AL-62: a healthy path-mismatch is the npm→native migration (e.g. claude
    // installed via npm at ~/.npm-global/bin/claude → relocate to the native
    // ~/.local/bin/claude). Preserve the user's detected version when it's in the
    // compatibility window; a broken install or an out-of-window version falls
    // back to the catalog pin. A preserved version is recorded source="override"
    // so `agentlinux upgrade --reset-all-curated` can later reconcile it to the
    // curated pin only if the operator opts in.
    const isMigration = remediateHit.reason === "path-mismatch";
    const dv = remediateHit.detected_version;
    const dvInWindow =
      !!dv && !!entry.compatibility_window && semver.satisfies(dv, entry.compatibility_window);
    const preserveVersion = isMigration && dvInWindow ? dv : null;
    const installVersion = preserveVersion ?? entry.pinned_version;
    const installSource: "curated" | "override" = preserveVersion ? "override" : "curated";
    const actionWord = isMigration
      ? "migrate npm→native (uninstall + reinstall)"
      : "uninstall + reinstall";

    // --yes is the sole consent surface (no env-var equivalent). In TTY mode
    // the gate auto-passes.
    const isTTY = process.stdin.isTTY === true;
    if (!opts.yes && !isTTY) {
      console.error(
        "Refusing to proceed — 1 component needs Remediate (run with --yes to apply, or --dry-run to preview):\n",
      );
      console.error(
        `[BAIL] component=${entry.id} reason=${remediateHit.reason} hint=run with --yes to ${isMigration ? "migrate" : "reinstall"}`,
      );
      console.error(
        "\nExit code 65 (EX_DATAERR — incompatible host state). See agentlinux install --help.",
      );
      process.exit(65); // EX_DATAERR
    }

    console.log(
      `[REMEDIATE-04] ${entry.id} component=${entry.id} reason=${remediateHit.reason} detected_path=${remediateHit.detected_path} canonical_path=${remediateHit.canonical_path} install_version=${installVersion}${preserveVersion ? " (preserving your version)" : ""} — ${actionWord}`,
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

    // Step 2: install.sh at installVersion (detected version for a migration,
    // else the pin). On failure we're half-uninstalled — write a
    // broken-after-remediate sentinel as a forensic trail + exit 1.
    const installPath = join(catalog.catalogDir, "agents", entry.id, entry.install_recipe_path);
    const installResult = await dispatchRecipe(
      {
        entry,
        recipePath: installPath,
        version: installVersion,
        catalogDir: catalog.catalogDir,
      },
      dispatcher,
    );
    if (installResult.exitCode !== 0) {
      const now = new Date().toISOString();
      await writeSentinel({
        id: entry.id,
        version: installVersion,
        source: installSource,
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

    // Step 3: success — status=installed sentinel + remediated_at trail. A
    // migration that preserved the user's version records source="override".
    const now = new Date().toISOString();
    await writeSentinel({
      id: entry.id,
      version: installVersion,
      source: installSource,
      sticky: false,
      installed_at: now,
      status: "installed",
      remediated_at: now,
    });
    console.log(
      `[REMEDIATE-04] ${entry.id}: ${isMigration ? "migrated to native" : "reinstalled"} at ${installVersion} (${installSource})`,
    );
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
