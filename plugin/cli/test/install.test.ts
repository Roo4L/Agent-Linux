// plugin/cli/test/install.test.ts — installCmd idempotency + override + error paths.
// DI seam: inject a capturing dispatcher (matches runner.ts Dispatcher type)
// so no actual sudo invocation happens. Unit-test-safe under any user context.

import assert from "node:assert/strict";
import { chmodSync, writeFileSync } from "node:fs";
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
      id: "claude-code",
      display_name: "Claude Code",
      description: "REUSE-03 fixture (real catalog id; canonical path map applies)",
      source_kind: "script",
      pinned_version: "2.1.98",
      compatibility_window: ">=2.0.0 <3.0.0",
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
  await mkdir(join(CATALOG_DIR, "agents", "claude-code"), { recursive: true });
  await mkdir(join(CATALOG_DIR, "agents", "test-dummy"), { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  await writeFile(
    join(CATALOG_DIR, "agents", "claude-code", "install.sh"),
    "#!/usr/bin/env bash\nexit 0\n",
    { mode: 0o755 },
  );
  await writeFile(
    join(CATALOG_DIR, "agents", "claude-code", "uninstall.sh"),
    "#!/usr/bin/env bash\nexit 0\n",
    { mode: 0o755 },
  );
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

// Plan 13-02: REUSE-03 pre-runner check. Mocks /run/agentlinux-detect.json via
// AGENTLINUX_DETECT_CACHE env override + creates a fake binary at the canonical
// path under a writable tmp tree, then asserts installCmd writes a status:
// "reused" sentinel WITHOUT invoking dispatchRecipe.
describe("installCmd — REUSE-03 pre-runner check (Plan 13-02)", () => {
  // We can't override the CANONICAL_PATHS map (hardcoded as /home/agent/...),
  // so the tests build a detect-cache that names the production canonical path
  // /home/agent/.local/bin/claude. Most CI environments don't have an
  // /home/agent/ binary, so the statSync re-validation step (T-13-07) would
  // normally cause tryReuse to return null. The fixture creates a real file at
  // a TMP path AND seeds the detect-cache with that same path — but the cache
  // path doesn't equal CANONICAL_PATHS[id], so REUSE shorts to null. SOLUTION:
  // exercise the path-mismatch branch (cache path != canonical) to verify
  // tryReuse returns null in that case, and verify the cache-absent and
  // version-out-of-window branches. The happy-path REUSE branch is exercised
  // by the bats brownfield E2E smoke @test in Task 3 where /home/agent/ is
  // populated.

  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  after(() => {
    // biome-ignore lint/performance/noDelete: delete required for process.env
    delete process.env.AGENTLINUX_DETECT_CACHE;
  });

  test("REUSE-03: no detect cache file -> normal install path (no REUSE)", async () => {
    process.env.AGENTLINUX_DETECT_CACHE = join(TMP, "nonexistent-detect.json");
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", {}, cap.impl);
    } finally {
      sil.restore();
    }
    // Normal install path runs.
    assert.equal(cap.calls.length, 1, "dispatchRecipe invoked because cache is absent");
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed");
  });

  test("REUSE-03: cache present but path-mismatch -> normal install path", async () => {
    const cachePath = join(TMP, "detect-mismatch.json");
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [
            {
              id: "claude-code",
              status: "healthy",
              // PATH-MISMATCH: ~/.npm-global vs canonical ~/.local/bin
              path: "/home/agent/.npm-global/bin/claude",
              version: "2.1.98",
            },
          ],
        },
      }),
    );
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "path-mismatch must fall through to install");
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed");
  });

  test("REUSE-03: cache present but version out-of-window -> normal install path", async () => {
    const cachePath = join(TMP, "detect-oow.json");
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [
            {
              id: "claude-code",
              status: "healthy",
              path: "/home/agent/.local/bin/claude",
              // OUT-OF-WINDOW: 1.5.0 does not satisfy >=2.0.0 <3.0.0
              version: "1.5.0",
            },
          ],
        },
      }),
    );
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "version-oow must fall through to install");
  });

  test("REUSE-03: --force bypasses the REUSE pre-runner check", async () => {
    // Even if the cache says REUSE, --force ALWAYS runs the recipe.
    const cachePath = join(TMP, "detect-force.json");
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [
            {
              id: "claude-code",
              status: "healthy",
              path: "/home/agent/.local/bin/claude",
              version: "2.1.98",
            },
          ],
        },
      }),
    );
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { force: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "--force always dispatches");
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed", "force install writes installed, not reused");
  });

  test("REUSE-03: --version bypasses the REUSE pre-runner check", async () => {
    const cachePath = join(TMP, "detect-vbypass.json");
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [
            {
              id: "claude-code",
              status: "healthy",
              path: "/home/agent/.local/bin/claude",
              version: "2.1.98",
            },
          ],
        },
      }),
    );
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { version: "2.0.5" }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "--version always dispatches");
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed");
    assert.equal(s?.source, "override");
  });

  test("REUSE-03: existing sentinel suppresses the REUSE pre-runner check (don't override)", async () => {
    // Pre-seed an existing sentinel — installCmd must NOT clobber an existing
    // record with a status:"reused" overwrite.
    await writeSentinel({
      id: "claude-code",
      version: "2.1.98",
      source: "curated",
      sticky: false,
      installed_at: "2026-05-01T00:00:00.000Z",
      status: "installed",
    });
    const cachePath = join(TMP, "detect-existing.json");
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [
            {
              id: "claude-code",
              status: "healthy",
              path: "/home/agent/.local/bin/claude",
              version: "2.1.98",
            },
          ],
        },
      }),
    );
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", {}, cap.impl);
    } finally {
      sil.restore();
    }
    // Same version + no force = idempotent short-circuit; sentinel stays
    // status:"installed", REUSE branch never runs.
    assert.equal(cap.calls.length, 0, "idempotent short-circuit prevented dispatch");
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed", "existing sentinel preserved (not flipped to reused)");
  });

  test("REUSE-03: AGENTLINUX_DETECT_CACHE env override is honored (install.ts-only seam)", async () => {
    // Production reads /run/agentlinux-detect.json; tests use the env override.
    // The seam exists for install.ts only; upgrade/remove tests below assert
    // those commands do NOT read the cache.
    const cachePath = join(TMP, "detect-explicit.json");
    writeFileSync(cachePath, "{not valid JSON}");
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      // Malformed cache parses to null in tryReuse, falls through to install.
      // (T-13-05 mitigation — parse failures are safe.)
      await installCmd("claude-code", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "malformed cache falls through safely");
    // Use chmodSync to silence the unused-import warning if biome lints it;
    // also documents intent.
    chmodSync(cachePath, 0o600);
  });
});
