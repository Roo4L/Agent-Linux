// plugin/cli/test/pin.test.ts — pinCmd + parsePinSpec unit tests.
//
// pin is a state-mutation-only verb: it updates the sentinel's source + sticky
// fields (and optionally version) to record user intent. It does NOT invoke
// install.sh — the user is asserting something about what the existing install
// means. This test file covers:
//   1. parsePinSpec — parsing <name>=<target> into a discriminated union
//   2. pinCmd state mutation — all three target types (curated/latest/semver)
//   3. pinCmd error paths — missing sentinel / unknown agent / bad spec
//   4. Integration sanity — upgrade reads the sticky flag pin writes (consumer
//      contract confirmed so a refactor in Plan 04-04's upgrade.ts that
//      accidentally ignores `sticky` trips this plan's tests too)
//
// Fixture shape mirrors install.test.ts / upgrade.test.ts: tmp catalog dir +
// tmp state dir, two visible entries (foo npm-kind, bar script-kind) plus one
// test-only entry (dummy) to exercise the test_only-doesn't-block-pin path.

import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;

const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "foo",
      display_name: "Foo",
      description: "npm-backed fixture",
      source_kind: "npm",
      npm_package_name: "foo",
      pinned_version: "1.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "bar",
      display_name: "Bar",
      description: "script-backed fixture",
      source_kind: "script",
      pinned_version: "2.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-pin-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  for (const id of ["foo", "bar"]) {
    await mkdir(join(CATALOG_DIR, "agents", id), { recursive: true });
  }
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete required for process.env
  delete process.env.AGENTLINUX_STATE_DIR;
});

const { parsePinSpec, pinCmd } = await import("../src/commands/pin.js");
const { readSentinel, writeSentinel } = await import("../src/state/sentinel.js");
const { upgradeCmd } = await import("../src/commands/upgrade.js");
import type { Sentinel } from "../src/types.js";

// Helper: pre-seed a sentinel entry. Unit-level — bypass pinCmd so we're
// testing pin's mutation on a known starting state, not chaining pinCmds.
async function installed(
  id: string,
  source: Sentinel["source"],
  sticky: boolean,
  version = "1.0.0",
): Promise<void> {
  await writeSentinel({ id, version, source, sticky, installed_at: "2026-04-19T00:00:00.000Z" });
}

// silence console captures — keeps test output clean AND lets us inspect logs
// when asserting the human-facing message for each pin target.
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

describe("parsePinSpec — all target shapes + error paths", () => {
  test("curated target", () => {
    assert.deepEqual(parsePinSpec("foo=curated"), { name: "foo", target: "curated" });
  });

  test("latest target", () => {
    assert.deepEqual(parsePinSpec("foo=latest"), { name: "foo", target: "latest" });
  });

  test("exact semver target", () => {
    assert.deepEqual(parsePinSpec("foo=2.1.7"), {
      name: "foo",
      target: "version",
      version: "2.1.7",
    });
  });

  test("pre-release semver target", () => {
    const parsed = parsePinSpec("foo=2.1.7-beta.1");
    assert.equal(parsed.target, "version");
    if (parsed.target === "version") {
      assert.equal(parsed.version, "2.1.7-beta.1");
    }
  });

  test("invalid target: throws with message listing valid targets", () => {
    assert.throws(() => parsePinSpec("foo=bogus"), /invalid target/);
    assert.throws(() => parsePinSpec("foo=bogus"), /curated.*latest.*semver/);
  });

  test("no '=': throws with usage help", () => {
    assert.throws(() => parsePinSpec("no-equals"), /<name>=<target>/);
  });

  test("empty name: throws", () => {
    assert.throws(() => parsePinSpec("=curated"), /<name>=<target>/);
  });

  test("empty target (trailing '='): throws with invalid-target message", () => {
    // Empty string is not 'curated', not 'latest', and not a valid semver.
    assert.throws(() => parsePinSpec("foo="), /invalid target/);
  });
});

describe("pinCmd — state mutation across all three target types", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("pin <installed>=curated: clears sticky + source=curated", async () => {
    // Pre-existing sticky override; pin=curated must reset it.
    await installed("foo", "latest", true);
    const sil = silenceConsole();
    try {
      await pinCmd("foo=curated");
    } finally {
      sil.restore();
    }
    const s = await readSentinel("foo");
    assert.ok(s);
    assert.equal(s?.source, "curated");
    assert.equal(s?.sticky, false);
    assert.match(sil.out.join("\n"), /cleared/);
  });

  test("pin <installed>=latest: sets sticky=true + source=latest; version preserved", async () => {
    await installed("foo", "curated", false, "1.0.0");
    const sil = silenceConsole();
    try {
      await pinCmd("foo=latest");
    } finally {
      sil.restore();
    }
    const s = await readSentinel("foo");
    assert.ok(s);
    assert.equal(s?.source, "latest");
    assert.equal(s?.sticky, true);
    // Open Q4 resolution: pin=latest records intent — resolution happens at
    // next `upgrade --all-latest`. Until then, sentinel.version stays put.
    assert.equal(s?.version, "1.0.0");
    assert.match(sil.out.join("\n"), /latest/);
  });

  test("pin <installed>=2.1.7: sets sticky=true + source=pinned + version=2.1.7", async () => {
    await installed("foo", "curated", false, "1.0.0");
    const sil = silenceConsole();
    try {
      await pinCmd("foo=2.1.7");
    } finally {
      sil.restore();
    }
    const s = await readSentinel("foo");
    assert.ok(s);
    assert.equal(s?.source, "pinned");
    assert.equal(s?.sticky, true);
    assert.equal(s?.version, "2.1.7");
    assert.match(sil.out.join("\n"), /2\.1\.7/);
  });

  test("pin does NOT modify installed_at or id (append-only on source/sticky/version)", async () => {
    // Round-trip integrity: installed_at set by the original install should
    // survive pin mutation. pinCmd is a partial update, not a re-create.
    const original = "2026-04-19T00:00:00.000Z";
    await writeSentinel({
      id: "foo",
      version: "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: original,
    });
    const sil = silenceConsole();
    try {
      await pinCmd("foo=2.0.0");
    } finally {
      sil.restore();
    }
    const s = await readSentinel("foo");
    assert.equal(s?.installed_at, original);
    assert.equal(s?.id, "foo");
  });

  test("pin=curated on already-curated sentinel: idempotent (no-error, result identical)", async () => {
    await installed("bar", "curated", false, "2.0.0");
    const sil = silenceConsole();
    try {
      await pinCmd("bar=curated");
    } finally {
      sil.restore();
    }
    const s = await readSentinel("bar");
    assert.equal(s?.source, "curated");
    assert.equal(s?.sticky, false);
    assert.equal(s?.version, "2.0.0");
  });
});

describe("pinCmd — error paths (process.exit intercepted)", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("pin on not-installed sentinel: exit 1 with 'install first' message", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(() => pinCmd("foo=curated"), /__test_exit_1__/);
      assert.deepEqual(exitCodes, [1]);
      assert.match(sil.err.join("\n"), /not installed/);
      assert.match(sil.err.join("\n"), /agentlinux install foo/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("pin on unknown agent: exit 64 with 'no such agent' message", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(() => pinCmd("unknown=curated"), /__test_exit_64__/);
      assert.deepEqual(exitCodes, [64]);
      assert.match(sil.err.join("\n"), /no such agent/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("pin with bad spec (no '='): exit 64 with usage message", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(() => pinCmd("noeq"), /__test_exit_64__/);
      assert.deepEqual(exitCodes, [64]);
      assert.match(sil.err.join("\n"), /<name>=<target>/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });

  test("pin with invalid target (bogus RHS): exit 64 with valid-targets help", async () => {
    const origExit = process.exit;
    const exitCodes: number[] = [];
    // biome-ignore lint/suspicious/noExplicitAny: test override of process.exit signature
    (process as any).exit = (code?: number) => {
      exitCodes.push(code ?? 0);
      throw new Error(`__test_exit_${code}__`);
    };
    const sil = silenceConsole();
    try {
      await assert.rejects(() => pinCmd("foo=not-a-version"), /__test_exit_64__/);
      assert.deepEqual(exitCodes, [64]);
      assert.match(sil.err.join("\n"), /invalid target/);
    } finally {
      sil.restore();
      process.exit = origExit;
    }
  });
});

describe("pin + upgrade integration sanity", () => {
  // Thin sanity checks that confirm upgrade.ts (Plan 04-04) honors the sticky
  // flag pin.ts writes. Not a replacement for upgrade.test.ts's own sticky
  // tests — a regression canary: if someone refactors upgrade.ts to ignore
  // sticky, this plan's tests trip too.

  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("after pin=latest, sentinel carries sticky=true + source=latest (upgrade input shape)", async () => {
    await installed("foo", "curated", false);
    const sil = silenceConsole();
    try {
      await pinCmd("foo=latest");
    } finally {
      sil.restore();
    }
    const s = await readSentinel("foo");
    assert.equal(s?.source, "latest");
    assert.equal(s?.sticky, true);
    // These two fields are exactly the inputs upgrade.ts reads when deciding
    // to skip under --all-latest (ADR-011 nag-avoidance).
  });

  test("upgrade --all-latest skips foo after pin=latest (end-to-end pin→upgrade)", async () => {
    await installed("foo", "curated", false, "1.0.0");
    const silPin = silenceConsole();
    try {
      await pinCmd("foo=latest");
    } finally {
      silPin.restore();
    }
    // Now run upgrade with stubbed npm-view that would return a newer version.
    // pin wrote sticky=true, so --all-latest must skip foo.
    const recipeCalls: Array<{ id: string; version: string }> = [];
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { allLatest: true },
        {
          dispatchRecipe: async (args) => {
            recipeCalls.push({ id: args.entry.id, version: args.version });
            return { exitCode: 0, stdout: "", stderr: "" };
          },
          queryGlobalNpm: async () => new Map([["foo", "1.0.0"]]),
          queryNpmViewLatest: async () => "1.5.0",
        },
      );
    } finally {
      sil.restore();
    }
    const ids = recipeCalls.map((c) => c.id);
    assert.ok(!ids.includes("foo"), "pin=latest sticky entry must be skipped by upgrade --all-latest");
    // Post-upgrade sentinel untouched.
    const s = await readSentinel("foo");
    assert.equal(s?.source, "latest");
    assert.equal(s?.sticky, true);
    assert.equal(s?.version, "1.0.0");
  });

  test("upgrade --reset-all-curated clears a pin=2.0.0 sticky override (explicit reset)", async () => {
    await installed("foo", "curated", false, "1.0.0");
    const silPin = silenceConsole();
    try {
      await pinCmd("foo=2.0.0");
    } finally {
      silPin.restore();
    }
    // Now --reset-all-curated: per ADR-011, explicit reset clears sticky.
    const recipeCalls: Array<{ id: string; version: string }> = [];
    const sil = silenceConsole();
    try {
      await upgradeCmd(
        { resetAllCurated: true },
        {
          dispatchRecipe: async (args) => {
            recipeCalls.push({ id: args.entry.id, version: args.version });
            return { exitCode: 0, stdout: "", stderr: "" };
          },
          queryGlobalNpm: async () => new Map([["foo", "2.0.0"]]),
          queryNpmViewLatest: async () => null,
        },
      );
    } finally {
      sil.restore();
    }
    const fooCall = recipeCalls.find((c) => c.id === "foo");
    assert.ok(fooCall, "reset-all-curated must reinstall the sticky entry");
    assert.equal(fooCall.version, "1.0.0", "reset to catalog pin, not the pinned-to version");
    const s = await readSentinel("foo");
    assert.equal(s?.source, "curated");
    assert.equal(s?.sticky, false);
  });
});
