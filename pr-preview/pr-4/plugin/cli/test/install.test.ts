// plugin/cli/test/install.test.ts — installCmd idempotency + override + error paths.
// DI seam: inject a capturing dispatcher (matches runner.ts Dispatcher type)
// so no actual sudo invocation happens. Unit-test-safe under any user context.

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
  TMP = await mkdtemp(join(tmpdir(), "al-install-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  await mkdir(join(CATALOG_DIR, "agents", "fake-agent"), { recursive: true });
  await mkdir(join(CATALOG_DIR, "agents", "test-dummy"), { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  // Stub recipes — content doesn't matter because the dispatcher is mocked,
  // but paths must resolve for test integrity (no ENOENT on construction).
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
  await writeFile(
    join(CATALOG_DIR, "agents", "test-dummy", "install.sh"),
    "#!/usr/bin/env bash\nexit 0\n",
    { mode: 0o755 },
  );
  await writeFile(
    join(CATALOG_DIR, "agents", "test-dummy", "uninstall.sh"),
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

const { installCmd } = await import("../src/commands/install.js");
const { readSentinel, writeSentinel, deleteSentinel } = await import("../src/state/sentinel.js");

type CapturedCall = { user: string; argv: string[]; env: Record<string, string> };

function makeCap(result: DispatchResult = { exitCode: 0, stdout: "", stderr: "" }) {
  const calls: CapturedCall[] = [];
  const impl: Dispatcher = async (user, argv, opts) => {
    calls.push({ user, argv, env: { ...opts.env } });
    return result;
  };
  return { impl, calls };
}

// silence captures — prevent test output noise; also lets us assert messages.
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

describe("installCmd — happy path + idempotency + overrides + errors", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("fresh install: dispatches recipe + writes sentinel with curated source", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "dispatcher invoked exactly once");
    assert.equal(cap.calls[0].user, "agent");
    assert.equal(cap.calls[0].argv[0], "bash");
    assert.ok(cap.calls[0].argv[1].endsWith("/fake-agent/install.sh"));
    assert.equal(cap.calls[0].env.AGENTLINUX_PINNED_VERSION, "1.0.0");
    const s = await readSentinel("fake-agent");
    assert.ok(s);
    assert.equal(s?.version, "1.0.0");
    assert.equal(s?.source, "curated");
    assert.equal(s?.sticky, false);
  });

  test("idempotent: second install with same version is a no-op (no recipe dispatch)", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", {}, cap.impl);
      await installCmd("fake-agent", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "second call must NOT dispatch recipe");
    const joined = sil.out.join("\n");
    assert.match(joined, /already installed/);
  });

  test("--force re-runs recipe even when sentinel matches", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", {}, cap.impl);
      await installCmd("fake-agent", { force: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 2, "dispatcher invoked twice under --force");
  });

  test("--version 9.9.9: dispatches override version + sentinel source='override'", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", { version: "9.9.9" }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls[0].env.AGENTLINUX_PINNED_VERSION, "9.9.9");
    const s = await readSentinel("fake-agent");
    assert.equal(s?.version, "9.9.9");
    assert.equal(s?.source, "override");
  });

  test("--version with invalid semver: process.exit(64)", async () => {
    // Mock process.exit to throw a typed sentinel so the test can assert on
    // exit code without actually exiting the test runner process.
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
        () => installCmd("fake-agent", { version: "not-a-semver" }, makeCap().impl),
        /__test_exit_64__/,
      );
      assert.deepEqual(exitCodes, [64]);
      assert.match(sil.err.join("\n"), /not a valid semver/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("unknown agent: process.exit(64) with 'no such agent' message", async () => {
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
        () => installCmd("no-such-thing", {}, makeCap().impl),
        /__test_exit_64__/,
      );
      assert.deepEqual(exitCodes, [64]);
      assert.match(sil.err.join("\n"), /no such agent/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("test-only entry without --include-test: process.exit(64)", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(() => installCmd("test-dummy", {}, makeCap().impl), /__test_exit_64__/);
      assert.deepEqual(exitCodes, [64]);
      assert.match(sil.err.join("\n"), /test-only/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("test-only entry WITH --include-test: install proceeds", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("test-dummy", { includeTest: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1);
    const s = await readSentinel("test-dummy");
    assert.ok(s);
    assert.equal(s?.version, "0.0.1");
    await deleteSentinel("test-dummy");
  });

  test("recipe exit non-zero: propagates exit code + no sentinel write", async () => {
    const cap = makeCap({ exitCode: 7, stdout: "", stderr: "boom" });
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(() => installCmd("fake-agent", {}, cap.impl), /__test_exit_7__/);
      assert.deepEqual(exitCodes, [7]);
      assert.match(sil.err.join("\n"), /install\.sh failed/);
      assert.equal(await readSentinel("fake-agent"), null);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("canonical env: dispatcher receives PATH/HOME/CATALOG_DIR from runner.ts", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", {}, cap.impl);
    } finally {
      sil.restore();
    }
    const env = cap.calls[0].env;
    assert.equal(
      env.PATH,
      "/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin",
    );
    assert.equal(env.HOME, "/home/agent");
    assert.equal(env.AGENTLINUX_CATALOG_DIR, CATALOG_DIR);
    assert.equal(env.AGENTLINUX_SOURCE_KIND, "script");
  });

  test("sticky sentinel preserved under --force: decideVersion keeps sticky version", async () => {
    // Pre-seed a sticky sentinel at 1.2.3 (pinned source). Sticky semantics:
    // decideVersion preserves the sentinel version regardless of the catalog
    // pin. Without --force the install short-circuits (sentinel matches
    // decision 1.2.3); with --force we re-dispatch and can observe that
    // AGENTLINUX_PINNED_VERSION=1.2.3 (NOT the catalog's 1.0.0 pin).
    await writeSentinel({
      id: "fake-agent",
      version: "1.2.3",
      source: "pinned",
      sticky: true,
      installed_at: "2026-04-19T00:00:00.000Z",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", { force: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "sticky + --force dispatches recipe");
    assert.equal(
      cap.calls[0].env.AGENTLINUX_PINNED_VERSION,
      "1.2.3",
      "sticky preserved over catalog pin 1.0.0",
    );
    const s = await readSentinel("fake-agent");
    assert.equal(s?.version, "1.2.3");
    assert.equal(s?.source, "pinned");
    assert.equal(s?.sticky, true);
  });

  test("sticky sentinel without --force: idempotent short-circuit (no dispatch)", async () => {
    // Companion to the --force test above: confirms sticky + matching-version
    // is still a no-op under the normal path (same short-circuit semantics as
    // any other equal-version install).
    await writeSentinel({
      id: "fake-agent",
      version: "1.2.3",
      source: "pinned",
      sticky: true,
      installed_at: "2026-04-19T00:00:00.000Z",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 0, "sticky+matching-version must short-circuit");
    assert.match(sil.out.join("\n"), /already installed/);
  });
});
