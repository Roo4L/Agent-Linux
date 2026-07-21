// plugin/cli/test/adopt.test.ts — adoptCmd (AL-61). Records pre-existing
// reuse-eligible agents into sentinels without installing anything.
//
// Determinism note: adoptOne → tryReuse statSync()s the canonical path to
// re-validate (the cache may be stale), and CANONICAL_PATHS is hardcoded to
// /home/agent/… which a unit host may not have. So the happy-path adoption is
// asserted host-independently (adopted OR skipped, never a non-reused sentinel),
// matching install.test.ts's REUSE-03 convention. The non-adopting branches
// (out-of-window, path-mismatch, absent cache, already-managed, usage errors)
// short-circuit BEFORE the statSync and are fully deterministic.

import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;

const GSD_SYSTEM_PATH = "/home/agent/.claude/gsd-core/VERSION";

const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "claude-code",
      display_name: "Claude Code",
      description: "adopt fixture (canonical path map applies)",
      source_kind: "script",
      pinned_version: "2.1.98",
      compatibility_window: ">=2.0.0 <3.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "gsd",
      display_name: "Get Shit Done",
      description: "adopt fixture — gsd dual presence",
      source_kind: "script",
      pinned_version: "1.37.1",
      compatibility_window: ">=1.37.0 <2.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      // v0.3.6 catalog-expansion tool: NO CANONICAL_PATHS entry. Exercises the
      // generalized tryReuse path (adoptable at its managed ~/.local/bin dir),
      // which the original-three canonical gate used to exclude.
      id: "rtk",
      display_name: "Repo Tool Kit",
      description: "adopt fixture — non-canonical binary tool",
      source_kind: "binary",
      pinned_version: "0.42.4",
      compatibility_window: ">=0.42.0 <0.43.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "test-dummy",
      display_name: "Test Dummy",
      description: "test-only fixture",
      source_kind: "script",
      pinned_version: "0.0.1",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
      test_only: true,
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-adopt-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  await mkdir(CATALOG_DIR, { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_STATE_DIR;
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_DETECT_CACHE;
});

const { adoptCmd } = await import("../src/commands/adopt.js");
const { readSentinel, writeSentinel, listSentinels } = await import("../src/state/sentinel.js");

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

// Run a body with process.exit mocked to throw a typed sentinel so the test can
// assert on the exit code without killing the runner.
async function expectExit(code: number, body: () => Promise<void>) {
  const origExit = process.exit;
  const exitCodes: number[] = [];
  // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
  (process as any).exit = (c?: number) => {
    exitCodes.push(c ?? 0);
    throw new Error(`__test_exit_${c}__`);
  };
  try {
    await assert.rejects(body, new RegExp(`__test_exit_${code}__`));
    assert.deepEqual(exitCodes, [code]);
  } finally {
    process.exit = origExit;
  }
}

let cacheSeq = 0;
function stageCache(agents: Array<{ id: string; status: string; path: string; version: string }>) {
  cacheSeq += 1;
  const cachePath = join(TMP, `detect-${cacheSeq}.json`);
  writeFileSync(cachePath, JSON.stringify({ components: { agents } }));
  process.env.AGENTLINUX_DETECT_CACHE = cachePath;
}

describe("adoptCmd — AL-61 adopt-on-install / honest reuse recording", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
    // Point at a nonexistent path (NOT delete) so the "no cache" default never
    // falls back to a real /run/agentlinux-detect.json on a dev host. stageCache
    // overrides this per-test.
    process.env.AGENTLINUX_DETECT_CACHE = join(TMP, "nonexistent-detect.json");
  });

  test("no name and no --all → exit 64 usage error", async () => {
    const sil = silenceConsole();
    try {
      await expectExit(64, () => adoptCmd(undefined, {}));
      assert.match(sil.err.join("\n"), /specify an agent name or --all/);
    } finally {
      sil.restore();
    }
  });

  test("unknown agent name → exit 64", async () => {
    const sil = silenceConsole();
    try {
      await expectExit(64, () => adoptCmd("no-such-thing", {}));
      assert.match(sil.err.join("\n"), /no such agent/);
    } finally {
      sil.restore();
    }
  });

  test("test-only entry without --include-test → exit 64", async () => {
    const sil = silenceConsole();
    try {
      await expectExit(64, () => adoptCmd("test-dummy", {}));
      assert.match(sil.err.join("\n"), /test-only/);
    } finally {
      sil.restore();
    }
  });

  test("--all with no detect cache → everything skipped, zero sentinels written", async () => {
    const sil = silenceConsole();
    try {
      await adoptCmd(undefined, { all: true });
    } finally {
      sil.restore();
    }
    assert.match(sil.out.join("\n"), /nothing to adopt/);
    assert.equal(
      (await listSentinels()).length,
      0,
      "adopt must not write a sentinel with no cache",
    );
  });

  test("out-of-window cache → skipped, no sentinel (deterministic, pre-statSync)", async () => {
    stageCache([{ id: "gsd", status: "healthy", path: GSD_SYSTEM_PATH, version: "1.36.0" }]);
    const sil = silenceConsole();
    try {
      await adoptCmd("gsd", {});
    } finally {
      sil.restore();
    }
    assert.match(sil.out.join("\n"), /nothing to adopt/);
    assert.equal(await readSentinel("gsd"), null, "out-of-window must not be adopted");
  });

  test("path-mismatch cache → migrate-available notice, no sentinel — adopt never migrates (AL-62)", async () => {
    // A healthy claude at a NON-canonical path (npm install) is a MIGRATION
    // candidate: adopt surfaces it ([MIGRATE] … run install to migrate) but must
    // NOT adopt or migrate it (no sentinel; migration needs consent via install).
    stageCache([
      {
        id: "claude-code",
        status: "healthy",
        path: "/home/agent/.npm-global/bin/claude",
        version: "2.1.98",
      },
    ]);
    const sil = silenceConsole();
    try {
      await adoptCmd("claude-code", {});
    } finally {
      sil.restore();
    }
    const out = sil.out.join("\n");
    assert.match(out, /\[MIGRATE\] claude-code/);
    assert.match(out, /migrate to the native install/);
    assert.doesNotMatch(out, /nothing to adopt/);
    assert.equal(
      await readSentinel("claude-code"),
      null,
      "adopt must not write a sentinel for a migration candidate",
    );
  });

  test("existing sentinel → already-managed, sentinel left untouched", async () => {
    await writeSentinel({
      id: "gsd",
      version: "1.37.1",
      source: "curated",
      sticky: false,
      installed_at: "2026-01-01T00:00:00.000Z",
      status: "installed",
    });
    // Even with a reuse-eligible cache present, an existing record wins.
    stageCache([{ id: "gsd", status: "healthy", path: GSD_SYSTEM_PATH, version: "1.37.1" }]);
    const sil = silenceConsole();
    try {
      await adoptCmd("gsd", {});
    } finally {
      sil.restore();
    }
    assert.match(sil.out.join("\n"), /already managed/);
    const s = await readSentinel("gsd");
    assert.equal(s?.status, "installed", "existing sentinel status must not be overwritten");
  });

  test("--json emits a structured result array", async () => {
    const sil = silenceConsole();
    try {
      await adoptCmd(undefined, { all: true, json: true });
    } finally {
      sil.restore();
    }
    const parsed = JSON.parse(sil.out.join("\n"));
    assert.ok(Array.isArray(parsed));
    assert.ok(parsed.length >= 1, "--all result array must be non-empty (catalog has agents)");
    for (const r of parsed) {
      assert.ok(typeof r.id === "string");
      assert.ok(["adopted", "already-managed", "skipped", "migrate-available"].includes(r.action));
    }
  });

  test("non-canonical catalog tool (rtk) at its managed path → adopted (generalized reuse)", async () => {
    // The keystone fix: a tool with NO CANONICAL_PATHS entry, detected healthy at
    // its source_kind's managed dir (~/.local/bin for a binary) within the
    // compatibility window, is now adoptable. Deterministic: point AGENT_HOME at
    // TMP and lay down a real binary so tryReuse's statSync re-validation passes.
    process.env.AGENTLINUX_AGENT_HOME = TMP;
    const binPath = join(TMP, ".local/bin/rtk");
    await mkdir(join(TMP, ".local/bin"), { recursive: true });
    await writeFile(binPath, "#!/usr/bin/env bash\nexit 0\n", { mode: 0o755 });
    stageCache([{ id: "rtk", status: "healthy", path: binPath, version: "0.42.4" }]);
    const sil = silenceConsole();
    try {
      await adoptCmd("rtk", {});
    } finally {
      sil.restore();
      // biome-ignore lint/performance/noDelete: delete required for process.env
      delete process.env.AGENTLINUX_AGENT_HOME;
    }
    assert.match(sil.out.join("\n"), /\[ADOPT\] rtk/);
    const s = await readSentinel("rtk");
    assert.equal(s?.status, "reused", "generalized adoption writes a reused sentinel");
    assert.equal(s?.version, "0.42.4");
    assert.equal(s?.binary_path, binPath, "reused sentinel records the detected binary path");
    assert.equal(s?.detected_source, "pre-existing");
  });

  test("non-canonical tool at a NON-managed path (system bin) → skipped, no sentinel", async () => {
    // Symmetric guard: rtk at /usr/bin/rtk is NOT at its managed ~/.local/bin, so
    // adopt declines it (list surfaces it as a present migration candidate). adopt
    // only records tools already sitting where AgentLinux would manage them.
    process.env.AGENTLINUX_AGENT_HOME = TMP;
    stageCache([{ id: "rtk", status: "healthy", path: "/usr/bin/rtk", version: "0.42.4" }]);
    const sil = silenceConsole();
    try {
      await adoptCmd("rtk", {});
    } finally {
      sil.restore();
      // biome-ignore lint/performance/noDelete: delete required for process.env
      delete process.env.AGENTLINUX_AGENT_HOME;
    }
    assert.match(sil.out.join("\n"), /nothing to adopt/);
    assert.equal(await readSentinel("rtk"), null, "non-managed path must not be adopted");
  });

  test("happy path is host-independent: gsd@system-path → adopted or skipped, never a non-reused sentinel", async () => {
    stageCache([{ id: "gsd", status: "healthy", path: GSD_SYSTEM_PATH, version: "1.37.1" }]);
    const sil = silenceConsole();
    try {
      // Must never throw or remediate. On a host where the VERSION file exists
      // (statSync passes) gsd is adopted with a reused sentinel; otherwise it is
      // skipped. Both are correct; a non-reused sentinel would be the bug.
      await adoptCmd("gsd", {});
    } finally {
      sil.restore();
    }
    const s = await readSentinel("gsd");
    if (s) {
      assert.equal(s.status, "reused", "an adopted sentinel must be status=reused");
      assert.equal(s.version, "1.37.1");
      assert.equal(s.detected_source, "pre-existing");
    } else {
      assert.match(sil.out.join("\n"), /nothing to adopt|adopted/);
    }
  });
});
