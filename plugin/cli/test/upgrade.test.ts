// plugin/cli/test/upgrade.test.ts — upgradeCmd orchestrator paths.
//
// Fixture shape mirrors install.test.ts: tmp catalog + tmp state dir, with
// two entries (one npm-backed, one script-backed) so we exercise both the
// "query npm ls for installed version" and "fall back to sentinel" branches.
//
// Dispatcher DI: upgradeCmd accepts `deps = { dispatchRecipe, queryGlobalNpm,
// queryNpmViewLatest }` — tests inject capturing/stubbing implementations so
// no sudo ever runs under `pnpm test`.

import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import type { DispatchResult, Dispatcher } from "../src/runner.js";
import type { CatalogEntry, Sentinel } from "../src/types.js";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;

const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "npm-agent",
      display_name: "Npm Agent",
      description: "npm-backed fixture with version_constraint",
      source_kind: "npm",
      npm_package_name: "npm-agent",
      pinned_version: "1.0.0",
      version_constraint: "^1.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "script-agent",
      display_name: "Script Agent",
      description: "native-installer fixture",
      source_kind: "script",
      pinned_version: "2.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-upgrade-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  for (const id of ["npm-agent", "script-agent"]) {
    await mkdir(join(CATALOG_DIR, "agents", id), { recursive: true });
    await writeFile(
      join(CATALOG_DIR, "agents", id, "install.sh"),
      "#!/usr/bin/env bash\nexit 0\n",
      { mode: 0o755 },
    );
    await writeFile(
      join(CATALOG_DIR, "agents", id, "uninstall.sh"),
      "#!/usr/bin/env bash\nexit 0\n",
      { mode: 0o755 },
    );
  }
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
  // Default the detect cache at a nonexistent path so the presence overlay reads
  // "no cache" (→ not-installed) for the report-only tests, rather than a real
  // /run/agentlinux-detect.json on a dev host. The presence describe overrides it.
  process.env.AGENTLINUX_DETECT_CACHE = join(TMP, "nonexistent-detect.json");
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete required for process.env
  delete process.env.AGENTLINUX_STATE_DIR;
  // biome-ignore lint/performance/noDelete: delete required for process.env
  delete process.env.AGENTLINUX_DETECT_CACHE;
  // biome-ignore lint/performance/noDelete: delete required for process.env
  delete process.env.AGENTLINUX_AGENT_HOME;
});

const { upgradeCmd } = await import("../src/commands/upgrade.js");
const { writeSentinel, readSentinel } = await import("../src/state/sentinel.js");

type CapturedCall = {
  entryId: string;
  version: string;
  env: Record<string, string>;
};

function makeCap(result: DispatchResult = { exitCode: 0, stdout: "", stderr: "" }) {
  const calls: CapturedCall[] = [];
  const impl: Dispatcher = async (user, argv, opts) => {
    // Capture which recipe was invoked by its path component + the pinned
    // version threaded through env. This mirrors install.test.ts's shape.
    const recipePath = argv[1] ?? "";
    const match = recipePath.match(/\/agents\/([^/]+)\//);
    calls.push({
      entryId: match?.[1] ?? "unknown",
      version: opts.env.AGENTLINUX_PINNED_VERSION ?? "",
      env: { ...opts.env },
    });
    void user;
    return result;
  };
  return { impl, calls };
}

function silenceConsole() {
  const out: string[] = [];
  const err: string[] = [];
  const origLog = console.log;
  const origErr = console.error;
  console.log = (...a: unknown[]) => out.push(a.map(String).join(" "));
  console.error = (...a: unknown[]) => err.push(a.map(String).join(" "));
  return {
    out,
    err,
    restore: () => {
      console.log = origLog;
      console.error = origErr;
    },
  };
}

// Dispatcher for upgrade's DI that shadows dispatchRecipe.
type RecipeDispatcher = (
  args: {
    entry: CatalogEntry;
    recipePath: string;
    version: string;
    catalogDir: string;
    extraEnv?: Record<string, string>;
  },
  dispatcher?: Dispatcher,
) => Promise<DispatchResult>;

function makeRecipeCap(result: DispatchResult = { exitCode: 0, stdout: "", stderr: "" }): {
  impl: RecipeDispatcher;
  calls: CapturedCall[];
} {
  const calls: CapturedCall[] = [];
  const impl: RecipeDispatcher = async (args) => {
    calls.push({
      entryId: args.entry.id,
      version: args.version,
      env: { AGENTLINUX_PINNED_VERSION: args.version },
    });
    return result;
  };
  return { impl, calls };
}

describe("upgradeCmd — report-only (no bulk flag)", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("no flags + empty state: prints table, no dispatch", async () => {
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map<string, string>();
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        {},
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    assert.equal(recipe.calls.length, 0, "no dispatch on report-only path");
    const joined = sil.out.join("\n");
    assert.match(joined, /ID\s+STATUS/, "header printed");
    assert.match(joined, /npm-agent\s+not-installed/);
    assert.match(joined, /script-agent\s+not-installed/);
  });

  test("--json output: emits DivergenceReport array", async () => {
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map<string, string>();
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { json: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    assert.equal(recipe.calls.length, 0);
    const parsed = JSON.parse(sil.out.join("\n"));
    assert.equal(Array.isArray(parsed), true);
    assert.equal(parsed.length, 2);
    const ids = parsed.map((r: { id: string }) => r.id).sort();
    assert.deepEqual(ids, ["npm-agent", "script-agent"]);
  });

  test("offline default: no upstream call without --check-upstream or --all-latest", async () => {
    let viewCalls = 0;
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map<string, string>();
    const viewStub = async () => {
      viewCalls++;
      return null;
    };
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        {},
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    assert.equal(viewCalls, 0, "npm view must NOT be called by default");
  });

  test("--check-upstream: queryNpmViewLatest called once per npm entry only", async () => {
    let viewCalls = 0;
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map<string, string>();
    const viewStub = async (entry: CatalogEntry) => {
      viewCalls++;
      void entry;
      return "1.2.0";
    };
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { checkUpstream: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    // Only npm-agent is source_kind:npm. queryNpmViewLatest is the seam that
    // itself returns null for non-npm entries (see npm_ls.ts), but the
    // upgrade layer short-circuits before even calling it for script entries
    // to avoid spending the 30-second timeout budget on a guaranteed-null.
    assert.equal(viewCalls, 1, "only npm-kind entries trigger upstream call");
    assert.equal(recipe.calls.length, 0, "report-only path — no dispatch");
  });
});

describe("upgradeCmd — bulk flag reconcile", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("--reset-all-curated: drifted entry reinstalled at catalog pin", async () => {
    await writeSentinel({
      id: "npm-agent",
      version: "0.9.0",
      source: "override",
      sticky: false,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    // Reflect the sentinel as what npm ls sees so classify -> override-behind
    // rather than drift-undeclared (which would also trigger reset, but
    // override-behind is the clearer contract).
    const npmLsStub = async () => new Map([["npm-agent", "0.9.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    // Only diverged entries re-dispatched; script-agent is not-installed so
    // also counts as diverged and also gets re-installed at its pin.
    const byId = new Map(recipe.calls.map((c) => [c.entryId, c]));
    assert.ok(byId.has("npm-agent"));
    assert.equal(byId.get("npm-agent")?.version, "1.0.0", "reset at catalog pin");
    const s = await readSentinel("npm-agent");
    assert.equal(s?.version, "1.0.0");
    assert.equal(s?.source, "curated");
    assert.equal(s?.sticky, false);
  });

  test("--respect-overrides: drifted 'override' sentinel SKIPPED, 'curated' drifted RE-INSTALLED", async () => {
    // npm-agent: source='override', drifted — must NOT be touched.
    await writeSentinel({
      id: "npm-agent",
      version: "0.9.0",
      source: "override",
      sticky: false,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    // script-agent: source='curated', drifted — must BE reinstalled.
    await writeSentinel({
      id: "script-agent",
      version: "1.5.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "0.9.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { respectOverrides: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    const ids = recipe.calls.map((c) => c.entryId);
    assert.ok(!ids.includes("npm-agent"), "override sentinel must be skipped");
    assert.ok(ids.includes("script-agent"), "drifted curated must be reinstalled");
    const s = await readSentinel("script-agent");
    assert.equal(s?.version, "2.0.0", "reinstalled at catalog pin");
    // npm-agent sentinel must remain untouched.
    const npm = await readSentinel("npm-agent");
    assert.equal(npm?.version, "0.9.0");
    assert.equal(npm?.source, "override");
  });

  test("--all-latest: resolves upstream + respects version_constraint via maxSatisfying", async () => {
    await writeSentinel({
      id: "npm-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "1.0.0"]]);
    // Stub queryNpmViewLatest returns the npm_ls.ts-resolved value. Since
    // upgrade.ts passes entry through, the real maxSatisfying logic is
    // exercised in the npm_ls unit suite — here we just return what that
    // logic would compute given constraint ^1.0 and versions including 2.0.0.
    const viewStub = async (entry: CatalogEntry): Promise<string | null> => {
      if (entry.id === "npm-agent") return "1.1.0"; // maxSatisfying('^1.0', [..,1.1.0,2.0.0])
      return null;
    };
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { allLatest: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    const byId = new Map(recipe.calls.map((c) => [c.entryId, c]));
    assert.equal(byId.get("npm-agent")?.version, "1.1.0");
    const s = await readSentinel("npm-agent");
    assert.equal(s?.version, "1.1.0");
    assert.equal(s?.source, "latest");
    // script-agent is source_kind:script — queryNpmViewLatest returns null,
    // upgrade.ts skips it with a diagnostic (no upstream).
    const script = await readSentinel("script-agent");
    // Never installed + no latestVersion resolved → no re-dispatch, no sentinel
    assert.equal(script, null);
  });

  test("--all-latest: pinned (sticky=true) entry SKIPPED", async () => {
    await writeSentinel({
      id: "npm-agent",
      version: "1.2.3",
      source: "pinned",
      sticky: true,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "1.2.3"]]);
    const viewStub = async () => "1.1.0";
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { allLatest: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    const ids = recipe.calls.map((c) => c.entryId);
    assert.ok(!ids.includes("npm-agent"), "sticky entry must be skipped by --all-latest");
    const s = await readSentinel("npm-agent");
    assert.equal(s?.version, "1.2.3", "sticky sentinel preserved");
    assert.equal(s?.sticky, true);
    assert.equal(s?.source, "pinned");
  });

  test("--reset-all-curated: sticky entry IS reset (explicit override)", async () => {
    await writeSentinel({
      id: "npm-agent",
      version: "1.2.3",
      source: "pinned",
      sticky: true,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "1.2.3"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    const byId = new Map(recipe.calls.map((c) => [c.entryId, c]));
    assert.ok(byId.has("npm-agent"), "sticky entry reset under --reset-all-curated");
    assert.equal(byId.get("npm-agent")?.version, "1.0.0");
    const s = await readSentinel("npm-agent");
    assert.equal(s?.source, "curated");
    assert.equal(s?.sticky, false, "sticky cleared on explicit reset");
  });

  test("recipe exit non-zero: continues loop + logs error + does NOT write sentinel", async () => {
    await writeSentinel({
      id: "npm-agent",
      version: "0.9.0",
      source: "override",
      sticky: false,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    const recipe = makeRecipeCap({ exitCode: 7, stdout: "", stderr: "boom" });
    const npmLsStub = async () => new Map([["npm-agent", "0.9.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    // Dispatcher was invoked, error logged, sentinel not updated.
    assert.match(sil.err.join("\n"), /recipe failed/);
    const s = await readSentinel("npm-agent");
    assert.equal(s?.version, "0.9.0", "sentinel unchanged on recipe failure");
    assert.equal(s?.source, "override");
  });

  test("--check-upstream error: non-fatal; continues rendering other rows", async () => {
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map<string, string>();
    const viewStub = async (entry: CatalogEntry): Promise<string | null> => {
      throw new Error(`${entry.id}: upstream registry down`);
    };
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { checkUpstream: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    // Error was logged per-entry; no uncaught rejection.
    assert.match(sil.err.join("\n"), /could not resolve latest/);
    const joined = sil.out.join("\n");
    assert.match(joined, /npm-agent/, "row still printed despite upstream error");
    assert.match(joined, /script-agent/);
  });
});

// Plan 13-02: REUSE-03 upgrade behavior — reused entries are treated
// IDENTICALLY to installed entries; post-upgrade sentinel flips status:
// "reused" -> "installed" and clears REUSE-only fields. T-13-07: stale-reused
// detection (binary_path missing) forces reinstall.
describe("upgradeCmd — REUSE-03 reused-entry handling (Plan 13-02)", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("REUSE-03: reused sentinel under --reset-all-curated flips to status=installed + clears REUSE-only fields", async () => {
    // Pre-seed a reused sentinel for npm-agent at the catalog pin (1.0.0).
    // Reset-all-curated forces a reinstall against the catalog pin; the
    // post-upgrade sentinel must be status:"installed" with all REUSE-only
    // fields cleared.
    await writeSentinel({
      id: "npm-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: "/home/agent/.npm-global/bin/npm-agent",
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
      compatibility_window_at_reuse: ">=1.0.0 <2.0.0",
    });
    const recipe = makeRecipeCap();
    // Reflect the pin as what npm ls sees so report.status == 'synced' —
    // shouldReinstall(synced, reset-all-curated) returns null, but T-13-07's
    // stale-binary-gone override does not apply here (binary path doesn't
    // exist in CI, BUT the sentinel is the in-memory one — let's verify the
    // stale-binary fallback triggers a reinstall).
    const npmLsStub = async () => new Map([["npm-agent", "1.0.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    // The reused binary path /home/agent/.npm-global/bin/npm-agent does not
    // exist in the test sandbox -> validateReusedBinary returns false ->
    // forced reinstall regardless of synced status.
    const byId = new Map(recipe.calls.map((c) => [c.entryId, c]));
    assert.ok(byId.has("npm-agent"), "stale reused binary forces reinstall");
    const s = await readSentinel("npm-agent");
    assert.equal(s?.status, "installed", "status flips to installed");
    assert.equal(s?.binary_path, undefined, "binary_path cleared post-upgrade");
    assert.equal(s?.detected_source, undefined, "detected_source cleared");
    assert.equal(s?.reused_at, undefined, "reused_at cleared");
    assert.equal(s?.compatibility_window_at_reuse, undefined, "compatibility_window cleared");
  });

  test("REUSE-03 / T-13-07: stale reused sentinel (binary_path gone) forces reinstall even on 'synced' report", async () => {
    // npm-agent at 1.0.0 reused + npm ls reports 1.0.0 + no upgrade flag would
    // normally trigger a re-dispatch — synced reports are skipped. But the
    // binary_path is missing on disk so validateReusedBinary returns false;
    // the reconcile loop overrides the null target to "curated".
    await writeSentinel({
      id: "npm-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: "/no/such/file/anywhere",
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "1.0.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    const byId = new Map(recipe.calls.map((c) => [c.entryId, c]));
    assert.ok(byId.has("npm-agent"), "stale binary triggers reinstall");
  });

  test("REUSE-03: reused-flip log line surfaces during upgrade (visibility)", async () => {
    await writeSentinel({
      id: "npm-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: "/home/agent/.npm-global/bin/npm-agent",
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "0.9.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    const joined = sil.out.join("\n");
    assert.match(joined, /upgrading reused install/);
  });
});

// Plan 15-01 (T-15-01-05): upgrade.ts treats sentinel.status="reused-with-
// warning" IDENTICALLY to "reused" — both are "already installed; honor
// user's manual ownership of this component". Without this, a subsequent
// `agentlinux upgrade` would re-attempt the remediation the user just
// declined, defeating the whole prompt-loop UX.
describe("upgradeCmd — reused-with-warning handling (Plan 15-01 T-15-01-05)", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("U11 (T-15-01-05): reused-with-warning sentinel is treated identically to reused (no upgrade dispatch in default report-only mode)", async () => {
    // Pre-seed a reused-with-warning sentinel. The upgrade default path is
    // report-only — no flag means no mutation. Assert zero dispatches.
    await writeSentinel({
      id: "npm-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-25T00:00:00.000Z",
      status: "reused-with-warning",
      decline_reason: "chown-declined",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "1.0.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        {},
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    assert.equal(
      recipe.calls.length,
      0,
      "report-only mode never dispatches; reused-with-warning preserved",
    );
    // Sentinel preserved with both fields.
    const s = await readSentinel("npm-agent");
    assert.equal(s?.status, "reused-with-warning");
    assert.equal(s?.decline_reason, "chown-declined");
  });
});

describe("upgradeCmd — flag priority", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("--reset-all-curated wins over --respect-overrides", async () => {
    await writeSentinel({
      id: "npm-agent",
      version: "0.9.0",
      source: "override",
      sticky: false,
      installed_at: "2026-04-18T00:00:00.000Z",
    });
    const recipe = makeRecipeCap();
    const npmLsStub = async () => new Map([["npm-agent", "0.9.0"]]);
    const viewStub = async () => null;
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true, respectOverrides: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: npmLsStub,
          queryNpmViewLatest: viewStub,
        },
      );
    } finally {
      sil.restore();
    }
    // override sentinel WAS reset (reset-all-curated semantics).
    const byId = new Map(recipe.calls.map((c) => [c.entryId, c]));
    assert.ok(byId.has("npm-agent"), "reset-all-curated overrides respect-overrides");
  });
});

describe("upgradeCmd — presence overlay (detected-but-unmanaged brownfield tools)", () => {
  // A tool the host already has but that AgentLinux has not recorded must read
  // `present` in `upgrade` too — not `not-installed`, which contradicts `list`.
  // Pure cache read (detectPresence): no on-disk stat, so host-independent.
  let seq = 0;
  function stageCache(
    agents: Array<{ id: string; status: string; path: string; version: string }>,
  ) {
    seq += 1;
    const cachePath = join(TMP, `upg-detect-${seq}.json`);
    writeFileSync(cachePath, JSON.stringify({ components: { agents } }));
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
  }

  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
    // Managed-dir heuristic resolves against AGENTLINUX_AGENT_HOME; point it at
    // TMP so ~/.local/bin/<id> is a stable managed path in the cache fixtures.
    process.env.AGENTLINUX_AGENT_HOME = TMP;
    process.env.AGENTLINUX_DETECT_CACHE = join(TMP, "nonexistent-detect.json");
  });

  test("detected script tool at its managed path → present + detected version (not not-installed)", async () => {
    stageCache([
      {
        id: "script-agent",
        status: "healthy",
        path: `${TMP}/.local/bin/script-agent`,
        version: "1.9.0",
      },
    ]);
    const recipe = makeRecipeCap();
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { json: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: async () => new Map<string, string>(),
          queryNpmViewLatest: async () => null,
        },
      );
    } finally {
      sil.restore();
    }
    const rows = JSON.parse(sil.out.join("\n"));
    const row = rows.find((r: { id: string }) => r.id === "script-agent");
    assert.equal(row.status, "present", "brownfield tool reads present, not not-installed");
    assert.equal(row.installedVersion, "1.9.0", "present row carries the detected version");
  });

  test("present rows are report-only: --reset-all-curated does NOT reinstall them", async () => {
    stageCache([
      {
        id: "script-agent",
        status: "healthy",
        path: `${TMP}/.local/bin/script-agent`,
        version: "1.9.0",
      },
    ]);
    const recipe = makeRecipeCap();
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: recipe.impl,
          queryGlobalNpm: async () => new Map<string, string>(),
          queryNpmViewLatest: async () => null,
        },
      );
    } finally {
      sil.restore();
    }
    assert.ok(
      !recipe.calls.some((c) => c.entryId === "script-agent"),
      "a present (unmanaged) tool must not be reinstalled by a bulk flag — adopt is the path",
    );
    assert.equal(
      await readSentinel("script-agent"),
      null,
      "no sentinel written for a present tool by upgrade",
    );
  });
});
