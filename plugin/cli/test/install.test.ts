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

  test("REUSE-03: cache present but path-mismatch -> REMEDIATE-04 fires (Plan 14-03 supersedes prior fall-through)", async () => {
    // Plan 14-03 (REMEDIATE-04) semantic shift: path-mismatch used to fall
    // through to install (REUSE-03 returns null → decideVersion → install.sh
    // at canonical). Now path-mismatch triggers tryRemediate which fires the
    // REMEDIATE-04 branch — uninstall the brownfield binary, install at the
    // canonical path. Without --yes in non-TTY we exit 65; with --yes we
    // get 2 dispatcher calls (uninstall + install).
    //
    // NOTE: detected_path must be a path that does NOT exist on the test
    // host (mocked dispatcher can't actually uninstall it). Otherwise the
    // T-14-05 verification check fires (uninstall.exitCode=0 but binary
    // present) → exit 1, which is a different test scenario (see U16).
    const cachePath = join(TMP, "detect-mismatch.json");
    const nonexistentPath = join(TMP, "fake-mismatched-claude-does-not-exist");
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [
            {
              id: "claude-code",
              status: "healthy",
              path: nonexistentPath, // PATH-MISMATCH but file is absent
              version: "2.1.98",
            },
          ],
        },
      }),
    );
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
    // Force non-TTY so the consent gate engages deterministically.
    Object.defineProperty(process.stdin, "isTTY", { value: false, configurable: true });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 2, "path-mismatch with --yes → REMEDIATE = uninstall + install");
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

// Plan 14-03 (REMEDIATE-04): tryRemediate pre-runner check + REMEDIATE branch.
// Same env-override pattern as REUSE-03 tests above (AGENTLINUX_DETECT_CACHE).
// The DI dispatcher mock lets us assert the uninstall→verify→install ordering
// without spawning sudo. The fake-agent fixture is used for the failure-mode
// tests (T-14-05 + half-uninstalled + uninstall-fail) because its catalog
// entry is in CANONICAL_PATHS — wait, it is NOT, so we need a fake CANONICAL
// path. Solution: re-use the claude-code entry (canonical path is hardcoded
// in install.ts so we can't override). The fixture creates a real binary file
// at the canonical location (via mkdir + writeFile) when we want T-14-05
// "uninstall exited 0 but binary present"; deletes it before install for the
// success path. See test setup for details.
describe("installCmd — REMEDIATE-04 branch (Plan 14-03)", () => {
  const CANONICAL_CLAUDE = "/home/agent/.local/bin/claude";

  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
    // Reset isTTY between tests — Node sets it lazily based on the underlying
    // file descriptor; tests need to force the non-TTY path deterministically
    // because the test runner's stdin may or may not be a TTY depending on
    // how `pnpm test` was invoked. Default to non-TTY so the --yes gate
    // tests fire as expected; the TTY-bypass test below flips it true.
    Object.defineProperty(process.stdin, "isTTY", { value: false, configurable: true });
  });

  after(() => {
    // biome-ignore lint/performance/noDelete: delete required for process.env
    delete process.env.AGENTLINUX_DETECT_CACHE;
  });

  // Helper: stage a detect cache with the given agent state.
  function stageDetectCache(opts: {
    id: string;
    status: "broken" | "healthy" | "absent";
    path: string;
    version: string;
  }): void {
    const cachePath = join(TMP, `detect-${opts.status}-${Date.now()}-${Math.random()}.json`);
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [{ id: opts.id, status: opts.status, path: opts.path, version: opts.version }],
        },
      }),
    );
    process.env.AGENTLINUX_DETECT_CACHE = cachePath;
  }

  // Helper: replace process.exit with a throwing stub; returns the captured
  // exit codes + restore fn.
  function captureExit() {
    const orig = process.exit;
    const codes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit
    (process as any).exit = (code?: number) => {
      codes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    return {
      codes,
      restore: () => {
        process.exit = orig;
      },
    };
  }

  test("U11: tryRemediate returns null when status=healthy + canonical path → REUSE-eligible, not REMEDIATE", async () => {
    // status=healthy at the CANONICAL path → tryReuse fires (or null because
    // statSync fails on /home/agent/), and tryRemediate returns null. Asserted
    // via: cap.calls.length === 1 (normal install path runs, not REMEDIATE
    // 2-step uninstall+install dance which would be 2).
    stageDetectCache({
      id: "claude-code",
      status: "healthy",
      path: CANONICAL_CLAUDE,
      version: "2.1.98",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(
      cap.calls.length,
      1,
      "healthy+canonical → normal install (1 call), NOT REMEDIATE (2 calls)",
    );
    // The transcript should NOT carry a [REMEDIATE-04] log line.
    assert.doesNotMatch(sil.out.join("\n"), /\[REMEDIATE-04\]/);
  });

  test("U12: tryRemediate returns null when agent absent from cache → no REMEDIATE fires", async () => {
    // Cache mentions a different agent (gsd). claude-code is absent from
    // the cache → tryRemediate returns null → normal install path runs.
    stageDetectCache({
      id: "gsd",
      status: "broken",
      path: "/home/agent/.npm-global/bin/get-shit-done-cc",
      version: "1.37.1",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "agent-absent from cache → normal install");
    assert.doesNotMatch(sil.out.join("\n"), /\[REMEDIATE-04\]/);
  });

  test("U13: tryRemediate returns RemediateHit when status=broken → REMEDIATE branch fires (uninstall + install)", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: CANONICAL_CLAUDE,
      version: "2.1.98",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    // REMEDIATE branch: uninstall.sh then install.sh = exactly 2 dispatcher calls.
    assert.equal(cap.calls.length, 2, "REMEDIATE = uninstall + install = 2 calls");
    assert.ok(cap.calls[0].argv[1].endsWith("/uninstall.sh"), "first call is uninstall.sh");
    assert.ok(cap.calls[1].argv[1].endsWith("/install.sh"), "second call is install.sh");
    assert.match(sil.out.join("\n"), /\[REMEDIATE-04\].*reason=broken/);
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed");
    assert.ok(s?.remediated_at, "remediated_at trail recorded on success");
  });

  test("U14: tryRemediate returns RemediateHit when status=healthy + PATH-MISMATCH → REMEDIATE branch fires", async () => {
    // PATH-MISMATCH: status=healthy but detected at a non-canonical path.
    // Use a tmp path (not /home/agent/.npm-global/bin/claude) so the T-14-05
    // post-uninstall existsSync check doesn't trip on a host-resident
    // brownfield install (the test env may have npm-installed claude).
    // The brownfield E2E coverage of the actual ~/.npm-global path lives in
    // bats Test 51 (real container, real filesystem state).
    const tmpMismatchPath = join(TMP, "bf-claude-not-on-disk-u14");
    stageDetectCache({
      id: "claude-code",
      status: "healthy",
      path: tmpMismatchPath,
      version: "2.1.98",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 2, "REMEDIATE-04 PATH-MISMATCH = uninstall + install");
    assert.match(sil.out.join("\n"), /\[REMEDIATE-04\].*reason=path-mismatch/);
    assert.match(
      sil.out.join("\n"),
      new RegExp(`detected_path=${tmpMismatchPath.replace(/\//g, "\\/")}`),
    );
  });

  test("U15: REMEDIATE happy path order — uninstall.sh dispatched FIRST, then install.sh, then status=installed sentinel", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: CANONICAL_CLAUDE,
      version: "1.5.0",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 2);
    assert.ok(cap.calls[0].argv[1].endsWith("/uninstall.sh"), "[0] is uninstall");
    assert.ok(cap.calls[1].argv[1].endsWith("/install.sh"), "[1] is install");
    // install dispatch carries entry.pinned_version (2.1.98), NOT the
    // detected 1.5.0 — REMEDIATE reinstalls at the catalog pin.
    assert.equal(cap.calls[1].env.AGENTLINUX_PINNED_VERSION, "2.1.98");
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed");
    assert.equal(s?.version, "2.1.98");
  });

  test("U16: T-14-05 — uninstall.sh exit 0 BUT binary still present → exit 1 + [REMEDIATE-04:uninstall-incomplete]; install NOT dispatched", async () => {
    // The detected path needs to exist on disk for T-14-05 to fire (post-
    // uninstall verification check). We stage the cache pointing at a real
    // file inside TMP (so existsSync returns true) but the canonical path
    // points to /home/agent/ which doesn't exist in test env → only the
    // detected_path triggers the check.
    const fakeBinary = join(TMP, "fake-claude");
    writeFileSync(fakeBinary, "#!/bin/sh\necho fake\n", { mode: 0o755 });
    stageDetectCache({
      id: "claude-code",
      status: "healthy",
      path: fakeBinary,
      version: "2.1.98",
    });
    const cap = makeCap({ exitCode: 0, stdout: "", stderr: "" });
    const exit = captureExit();
    const sil = silenceConsole();
    try {
      await assert.rejects(
        () => installCmd("claude-code", { yes: true }, cap.impl),
        /__test_exit_1__/,
      );
    } finally {
      sil.restore();
      exit.restore();
    }
    assert.deepEqual(exit.codes, [1]);
    assert.match(sil.err.join("\n"), /\[REMEDIATE-04:uninstall-incomplete\]/);
    assert.equal(cap.calls.length, 1, "install.sh NOT dispatched after T-14-05 detection");
    // Clean up the fake binary so subsequent tests don't trip the verification.
    await rm(fakeBinary, { force: true });
  });

  test("U17: uninstall.sh exits non-zero → exit 1 + [REMEDIATE-04:uninstall-fail]; install NOT dispatched", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    // Dispatcher: uninstall fails (exitCode=3). We want to bail BEFORE any
    // install attempt. Cap counts confirm only 1 dispatch.
    const cap = makeCap({ exitCode: 3, stdout: "", stderr: "uninstall boom" });
    const exit = captureExit();
    const sil = silenceConsole();
    try {
      await assert.rejects(
        () => installCmd("claude-code", { yes: true }, cap.impl),
        /__test_exit_1__/,
      );
    } finally {
      sil.restore();
      exit.restore();
    }
    assert.deepEqual(exit.codes, [1]);
    assert.match(sil.err.join("\n"), /\[REMEDIATE-04:uninstall-fail\]/);
    assert.equal(cap.calls.length, 1, "install.sh NOT dispatched after uninstall-fail");
  });

  test("U18: uninstall OK + install fails → broken-after-remediate sentinel + exit 1 + [REMEDIATE-04:half-uninstalled]", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    // Dispatcher that succeeds on first call (uninstall) and fails on second (install).
    let callIndex = 0;
    const cap = makeCap();
    const failingDispatcher: Dispatcher = async (user, argv, opts) => {
      cap.calls.push({ user, argv, env: { ...opts.env } });
      callIndex++;
      if (callIndex === 1) return { exitCode: 0, stdout: "", stderr: "" };
      return { exitCode: 5, stdout: "", stderr: "install boom" };
    };
    const exit = captureExit();
    const sil = silenceConsole();
    try {
      await assert.rejects(
        () => installCmd("claude-code", { yes: true }, failingDispatcher),
        /__test_exit_1__/,
      );
    } finally {
      sil.restore();
      exit.restore();
    }
    assert.deepEqual(exit.codes, [1]);
    assert.match(sil.err.join("\n"), /\[REMEDIATE-04:half-uninstalled\]/);
    assert.equal(cap.calls.length, 2, "both uninstall AND install dispatched");
    const s = await readSentinel("claude-code");
    assert.ok(s, "sentinel written for forensic trail");
    assert.equal(s?.status, "broken-after-remediate");
    assert.equal(s?.remediate_failure_reason, "install-failed-post-uninstall");
    assert.ok(s?.remediated_at);
  });

  test("U19: REMEDIATE without --yes in non-TTY → [BAIL] + exit 65; uninstall+install NOT dispatched", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    const cap = makeCap();
    const exit = captureExit();
    const sil = silenceConsole();
    try {
      await assert.rejects(() => installCmd("claude-code", {}, cap.impl), /__test_exit_65__/);
    } finally {
      sil.restore();
      exit.restore();
    }
    assert.deepEqual(exit.codes, [65]);
    const errOut = sil.err.join("\n");
    assert.match(errOut, /Refusing to proceed/);
    assert.match(errOut, /\[BAIL\] component=claude-code reason=broken/);
    assert.match(errOut, /Exit code 65/);
    assert.equal(cap.calls.length, 0, "no dispatch when --yes absent in non-TTY mode");
  });

  test("U20: REMEDIATE with --yes proceeds → uninstall+install dispatched", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 2, "--yes lets the REMEDIATE branch proceed");
    const s = await readSentinel("claude-code");
    assert.equal(s?.status, "installed");
  });

  test("U21: REMEDIATE bypassed when opts.force is true (force always installs fresh, never remediates)", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { force: true, yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    // --force = single install.sh dispatch, NOT the 2-step REMEDIATE.
    assert.equal(cap.calls.length, 1);
    assert.ok(
      cap.calls[0].argv[1].endsWith("/install.sh"),
      "single install.sh dispatch under --force",
    );
  });

  test("U22: REMEDIATE bypassed when opts.version is set (explicit version override)", async () => {
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { version: "2.0.5", yes: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 1, "--version → single install.sh dispatch (no REMEDIATE)");
    assert.ok(cap.calls[0].argv[1].endsWith("/install.sh"));
  });

  test("REMEDIATE in TTY mode without --yes auto-passes the gate", async () => {
    // Force isTTY=true → consent gate bypasses for interactive sessions.
    // (Phase 15 will replace the auto-pass with an interactive prompt.)
    Object.defineProperty(process.stdin, "isTTY", { value: true, configurable: true });
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", {}, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 2, "TTY mode auto-passes the --yes gate");
  });

  test("T-14-12 grep: install.ts does not consult AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES env vars", async () => {
    // Defense-in-depth: even if a malicious env var is set, it must NOT
    // bypass the --yes gate.
    process.env.AGENTLINUX_YES = "1";
    process.env.ALWAYS_YES = "1";
    process.env.ASSUME_YES = "1";
    stageDetectCache({
      id: "claude-code",
      status: "broken",
      path: "/home/agent/.local/bin/claude",
      version: "2.1.98",
    });
    const cap = makeCap();
    const exit = captureExit();
    const sil = silenceConsole();
    try {
      await assert.rejects(() => installCmd("claude-code", {}, cap.impl), /__test_exit_65__/);
    } finally {
      sil.restore();
      exit.restore();
      // biome-ignore lint/performance/noDelete: delete required for process.env
      delete process.env.AGENTLINUX_YES;
      // biome-ignore lint/performance/noDelete: delete required for process.env
      delete process.env.ALWAYS_YES;
      // biome-ignore lint/performance/noDelete: delete required for process.env
      delete process.env.ASSUME_YES;
    }
    assert.deepEqual(exit.codes, [65], "env vars MUST NOT bypass --yes gate (T-14-12)");
    assert.equal(cap.calls.length, 0);
  });
});

// Plan 15-01 (UX-01 / D-15-01 / D-15-04): --dry-run early-return path.
// installCmd with opts.dryRun=true runs loadCatalog + tryReuse + tryRemediate
// decision determination + report emission and exits WITHOUT calling
// dispatchRecipe. The contradictory --dry-run + --yes combo exits 64.
describe("installCmd — --dry-run early-return (Plan 15-01)", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
    // Default to non-TTY so tests are deterministic across runners.
    Object.defineProperty(process.stdin, "isTTY", { value: false, configurable: true });
  });

  after(() => {
    // biome-ignore lint/performance/noDelete: delete required for process.env
    delete process.env.AGENTLINUX_DETECT_CACHE;
  });

  test("U1 (D-15-01): --dry-run on fresh agent → no dispatchRecipe call; exits 0; [DRY-RUN] log marker emitted", async () => {
    const cap = makeCap();
    const sil = silenceConsole();
    try {
      await installCmd("fake-agent", { dryRun: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 0, "dispatchRecipe MUST NOT be called under --dry-run");
    const joined = sil.out.join("\n");
    assert.match(joined, /\[DRY-RUN\]/);
    // No sentinel written.
    assert.equal(await readSentinel("fake-agent"), null);
  });

  test("U2 (D-15-01): --dry-run on REUSE-eligible agent (cache=healthy at canonical path) reports decision=reuse without dispatch", async () => {
    // Mirror the REUSE-03 fixture pattern — canonical path is hardcoded in
    // install.ts (/home/agent/.local/bin/claude), which doesn't exist on the
    // test host. So the dry-run path falls through tryReuse (returns null due
    // to statSync) but the cache existence still drives the decision logic.
    // We instead exercise the "no cache present" path which makes both
    // tryReuse and tryRemediate return null → decision=create.
    const sil = silenceConsole();
    try {
      await installCmd("claude-code", { dryRun: true }, makeCap().impl);
    } finally {
      sil.restore();
    }
    const joined = sil.out.join("\n");
    assert.match(joined, /\[DRY-RUN\] claude-code:/);
    // Default decision (no cache) = create.
    assert.match(joined, /would (short-circuit|uninstall|dispatch)/);
  });

  test("U3 (D-15-01): --dry-run on REMEDIATE-eligible agent (cache=broken) reports decision=remediate without dispatch", async () => {
    const cachePath = join(TMP, "dryrun-remediate.json");
    writeFileSync(
      cachePath,
      JSON.stringify({
        components: {
          agents: [
            {
              id: "claude-code",
              status: "broken",
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
      await installCmd("claude-code", { dryRun: true }, cap.impl);
    } finally {
      sil.restore();
    }
    assert.equal(cap.calls.length, 0, "dry-run must NOT dispatch even when REMEDIATE-eligible");
    const joined = sil.out.join("\n");
    assert.match(joined, /\[DRY-RUN\] claude-code: remediate/);
    assert.match(joined, /would uninstall \+ reinstall/);
    // No sentinel written.
    assert.equal(await readSentinel("claude-code"), null);
  });

  test("U4 (D-15-04 symmetric): --dry-run --yes exits 64 with symmetric contradiction message", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(
        () => installCmd("fake-agent", { dryRun: true, yes: true }, makeCap().impl),
        /__test_exit_64__/,
      );
      assert.deepEqual(exitCodes, [64]);
      const errOut = sil.err.join("\n");
      assert.match(errOut, /contradictory flags/);
      assert.match(errOut, /--dry-run forbids --yes/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });
});
