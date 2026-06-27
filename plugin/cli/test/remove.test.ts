// plugin/cli/test/remove.test.ts — removeCmd happy path + sentinel guard + --force.
// Same DI-dispatcher pattern as install.test.ts: capturing mock injected via
// optional third parameter, no real sudo invocation.

import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import type { DispatchResult, Dispatcher } from "../src/runner.js";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;

const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "fake-agent",
      display_name: "Fake",
      description: "unit-test fixture",
      source_kind: "script",
      pinned_version: "1.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-remove-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  await mkdir(join(CATALOG_DIR, "agents", "fake-agent"), { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  await writeFile(
    join(CATALOG_DIR, "agents", "fake-agent", "install.sh"),
    "#!/usr/bin/env bash\nexit 0\n",
    { mode: 0o755 },
  );
  await writeFile(
    join(CATALOG_DIR, "agents", "fake-agent", "uninstall.sh"),
    "#!/usr/bin/env bash\nexit 0\n",
    { mode: 0o755 },
  );
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // delete is semantically required for process.env — assignment coerces to
  // the string "undefined" which contaminates sibling test env lookups.
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_STATE_DIR;
});

const { removeCmd } = await import("../src/commands/remove.js");
const { readSentinel, writeSentinel } = await import("../src/state/sentinel.js");

type CapturedCall = { user: string; argv: string[]; env: Record<string, string> };

function makeCap(result: DispatchResult = { exitCode: 0, stdout: "", stderr: "" }) {
  const calls: CapturedCall[] = [];
  const impl: Dispatcher = async (user, argv, opts) => {
    calls.push({ user, argv, env: { ...opts.env } });
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

describe("removeCmd — happy + missing sentinel + --force + unknown", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("happy path: dispatches uninstall.sh + deletes sentinel", async () => {
    await writeSentinel({
      id: "fake-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-04-19T00:00:00.000Z",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await removeCmd("fake-agent", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1);
    assert.equal(cap.calls[0].user, "agent");
    assert.ok(cap.calls[0].argv[1].endsWith("/fake-agent/uninstall.sh"));
    assert.equal(cap.calls[0].env.AGENTLINUX_PINNED_VERSION, "1.0.0");
    assert.equal(await readSentinel("fake-agent"), null);
    assert.match(sil.out.join("\n"), /removed/);
  });

  test("no sentinel + no --force: process.exit(1) with 'not installed' message", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await assert.rejects(() => removeCmd("fake-agent", {}, cap.impl), /__test_exit_1__/);
      assert.deepEqual(exitCodes, [1]);
      assert.match(sil.err.join("\n"), /not installed/);
      assert.equal(cap.calls.length, 0, "recipe must NOT dispatch when sentinel absent");
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("--force on not-installed: idempotent no-op (no dispatch, exit 0)", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await removeCmd("fake-agent", { force: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 0);
  });

  test("unknown agent: process.exit(64)", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(
        () => removeCmd("no-such-thing", {}, makeCap().impl),
        /__test_exit_64__/,
      );
      assert.deepEqual(exitCodes, [64]);
      assert.match(sil.err.join("\n"), /no such agent/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("uninstall.sh exit non-zero: propagates exit code + sentinel NOT deleted", async () => {
    await writeSentinel({
      id: "fake-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-04-19T00:00:00.000Z",
    });
    const cap = makeCap({ exitCode: 5, stdout: "", stderr: "kaboom" });
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(() => removeCmd("fake-agent", {}, cap.impl), /__test_exit_5__/);
      assert.deepEqual(exitCodes, [5]);
      assert.notEqual(await readSentinel("fake-agent"), null);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  // Plan 13-02: REUSE-03 remove behavior — reused entries are treated
  // IDENTICALLY to installed entries (binary still on disk -> run uninstall.sh
  // + delete sentinel). T-13-07: stale-reused (binary_path gone) skips
  // uninstall.sh and only deletes the sentinel.

  test("REUSE-03: reused entry with EXISTING binary_path runs uninstall.sh identically to installed", async () => {
    // Use the CATALOG_DIR catalog.json (known-existing file in this test tree)
    // as a binary that DOES exist on disk; the sentinel.binary_path existsSync
    // check passes -> proceeds to dispatch. Avoid __filename which is not
    // defined in ESM modules.
    const realFile = join(CATALOG_DIR, "catalog.json");
    await writeSentinel({
      id: "fake-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: realFile,
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await removeCmd("fake-agent", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "uninstall.sh dispatched identically for reused entries");
    assert.equal(await readSentinel("fake-agent"), null, "sentinel deleted");
    assert.match(sil.out.join("\n"), /removed/);
  });

  test("REUSE-03 / T-13-07: stale reused sentinel (binary_path gone) skips uninstall.sh", async () => {
    await writeSentinel({
      id: "fake-agent",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-16T00:00:00.000Z",
      status: "reused",
      binary_path: "/no/such/file/anywhere",
      detected_source: "pre-existing",
      reused_at: "2026-05-16T00:00:00.000Z",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await removeCmd("fake-agent", {}, cap.impl);
    } finally {
      sil.restore();
    }
    // No dispatch — the binary is already gone, so we just delete the sentinel.
    assert.equal(cap.calls.length, 0, "stale reused: uninstall.sh NOT dispatched");
    assert.equal(await readSentinel("fake-agent"), null, "sentinel deleted (silent cleanup)");
    assert.match(sil.out.join("\n"), /already gone/);
  });
});
