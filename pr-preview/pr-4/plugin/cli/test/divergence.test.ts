// plugin/cli/test/divergence.test.ts — pure-function divergence classifier
// (Plan 04-04). Three suites:
//   1. computeDivergence: all six Status states + upstream-latest threading.
//   2. resolveLatestFor: semver.maxSatisfying over version_constraint.
//   3. queryGlobalNpm defensive parse (Pitfall 4 — empty deps, exit 1, unparseable).
//
// All tests run without network access. The npm dispatcher is DI-injected
// through the second parameter of queryGlobalNpm/queryNpmViewLatest so the
// unit suite never spawns sudo.

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import type { CatalogEntry, Sentinel } from "../src/types.js";
import { computeDivergence, resolveLatestFor } from "../src/upgrade/divergence.js";
import { queryGlobalNpm, queryNpmViewLatest } from "../src/upgrade/npm_ls.js";

const E: CatalogEntry = {
  id: "foo",
  display_name: "Foo",
  description: "fixture",
  source_kind: "npm",
  npm_package_name: "foo",
  pinned_version: "1.0.0",
  install_recipe_path: "install.sh",
  uninstall_recipe_path: "uninstall.sh",
};

function sentinel(
  version: string,
  source: Sentinel["source"] = "curated",
  sticky = false,
): Sentinel {
  return {
    id: "foo",
    version,
    source,
    sticky,
    installed_at: "2026-04-19T00:00:00.000Z",
  };
}

describe("computeDivergence — all six Status states + latestVersion threading", () => {
  test("not-installed: sentinel null + installed null", () => {
    const r = computeDivergence({ entry: E, sentinel: null, installed: null });
    assert.equal(r.status, "not-installed");
    assert.equal(r.sentinelVersion, null);
    assert.equal(r.installedVersion, null);
    assert.equal(r.curatedVersion, "1.0.0");
    assert.equal(r.latestVersion, null);
    assert.equal(r.source, "none");
    assert.equal(r.sticky, false);
  });

  test("synced: sentinel + installed + pin all equal", () => {
    const r = computeDivergence({
      entry: E,
      sentinel: sentinel("1.0.0"),
      installed: "1.0.0",
    });
    assert.equal(r.status, "synced");
    assert.equal(r.sentinelVersion, "1.0.0");
    assert.equal(r.installedVersion, "1.0.0");
    assert.equal(r.source, "curated");
  });

  test("drift-undeclared: sentinel !== installed", () => {
    const r = computeDivergence({
      entry: E,
      sentinel: sentinel("1.0.0"),
      installed: "1.2.0",
    });
    assert.equal(r.status, "drift-undeclared");
    assert.equal(r.sentinelVersion, "1.0.0");
    assert.equal(r.installedVersion, "1.2.0");
  });

  test("override-behind: installed < pin, not sticky", () => {
    const r = computeDivergence({
      entry: E,
      sentinel: sentinel("0.9.0", "override", false),
      installed: "0.9.0",
    });
    assert.equal(r.status, "override-behind");
    assert.equal(r.source, "override");
    assert.equal(r.sticky, false);
  });

  test("override-ahead: installed > pin, not sticky", () => {
    const r = computeDivergence({
      entry: E,
      sentinel: sentinel("1.1.0", "override", false),
      installed: "1.1.0",
    });
    assert.equal(r.status, "override-ahead");
  });

  test("pinned-override: sticky=true + installed !== pin", () => {
    const r = computeDivergence({
      entry: E,
      sentinel: sentinel("1.1.0", "pinned", true),
      installed: "1.1.0",
    });
    assert.equal(r.status, "pinned-override");
    assert.equal(r.source, "pinned");
    assert.equal(r.sticky, true);
  });

  test("latestVersion threaded through when provided", () => {
    const r = computeDivergence({
      entry: E,
      sentinel: sentinel("1.0.0"),
      installed: "1.0.0",
      latest: "1.2.3",
    });
    assert.equal(r.latestVersion, "1.2.3");
    assert.equal(r.status, "synced", "status classifier ignores latestVersion");
  });

  test("pinned-override with upstream latest populated", () => {
    const r = computeDivergence({
      entry: E,
      sentinel: sentinel("1.1.0", "pinned", true),
      installed: "1.1.0",
      latest: "2.0.0",
    });
    assert.equal(r.status, "pinned-override");
    assert.equal(r.latestVersion, "2.0.0");
    assert.equal(r.sticky, true);
  });
});

describe("resolveLatestFor — semver.maxSatisfying over version_constraint", () => {
  const versions = ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "2.1.0"];

  test("no constraint: returns newest (2.1.0)", () => {
    assert.equal(resolveLatestFor(E, versions), "2.1.0");
  });

  test("constraint ^1.0: respects upper bound (never 2.x)", () => {
    const e: CatalogEntry = { ...E, version_constraint: "^1.0" };
    assert.equal(resolveLatestFor(e, versions), "1.2.0");
  });

  test("constraint ~1.1: respects tilde (1.1.x only)", () => {
    const e: CatalogEntry = { ...E, version_constraint: "~1.1" };
    assert.equal(resolveLatestFor(e, versions), "1.1.0");
  });

  test("constraint matches zero versions: throws with explicit message", () => {
    const e: CatalogEntry = { ...E, version_constraint: "^9.0" };
    assert.throws(() => resolveLatestFor(e, versions), /no published version.*satisfies/);
  });

  test("empty versions list: throws", () => {
    assert.throws(() => resolveLatestFor(E, []), /no published versions/);
  });
});

describe("queryGlobalNpm — defensive parse (Pitfall 4)", () => {
  test("missing dependencies key: returns empty map", async () => {
    const stub = async () => ({ exitCode: 0, stdout: '{"name":"root"}', stderr: "" });
    const m = await queryGlobalNpm(stub);
    assert.equal(m.size, 0);
  });

  test("empty dependencies object: returns empty map", async () => {
    const stub = async () => ({
      exitCode: 0,
      stdout: '{"dependencies":{}}',
      stderr: "",
    });
    const m = await queryGlobalNpm(stub);
    assert.equal(m.size, 0);
  });

  test("well-formed dependencies: maps pkg→version", async () => {
    const stub = async () => ({
      exitCode: 0,
      stdout:
        '{"dependencies":{"foo":{"version":"1.2.3"},"bar":{"version":"4.5.6","overridden":false}}}',
      stderr: "",
    });
    const m = await queryGlobalNpm(stub);
    assert.equal(m.get("foo"), "1.2.3");
    assert.equal(m.get("bar"), "4.5.6");
    assert.equal(m.size, 2);
  });

  test("exit 1 with valid JSON (peer-dep warning): still parses", async () => {
    const stub = async () => ({
      exitCode: 1,
      stdout: '{"dependencies":{"foo":{"version":"1.0.0"}}}',
      stderr: "peer-dep warning",
    });
    const m = await queryGlobalNpm(stub);
    assert.equal(m.get("foo"), "1.0.0");
    assert.equal(m.size, 1);
  });

  test("entry with no version field: skipped from map", async () => {
    const stub = async () => ({
      exitCode: 0,
      stdout: '{"dependencies":{"foo":{"version":"1.0.0"},"bar":{}}}',
      stderr: "",
    });
    const m = await queryGlobalNpm(stub);
    assert.equal(m.get("foo"), "1.0.0");
    assert.equal(m.has("bar"), false);
  });

  test("unparseable stdout: throws with context", async () => {
    const stub = async () => ({ exitCode: 0, stdout: "not json", stderr: "parse boom" });
    await assert.rejects(queryGlobalNpm(stub), /parseable JSON/);
  });

  test("argv shape: npm ls -g --json --depth=0", async () => {
    let captured: string[] = [];
    const stub = async (_user: string, argv: string[], _opts: { env: Record<string, string> }) => {
      captured = argv;
      return { exitCode: 0, stdout: '{"dependencies":{}}', stderr: "" };
    };
    await queryGlobalNpm(stub);
    assert.deepEqual(captured, ["npm", "ls", "-g", "--json", "--depth=0"]);
  });
});

describe("queryNpmViewLatest — upstream version resolution", () => {
  test("non-npm source_kind (script): returns null without dispatching", async () => {
    let called = false;
    const stub = async () => {
      called = true;
      return { exitCode: 0, stdout: "[]", stderr: "" };
    };
    const scriptEntry: CatalogEntry = { ...E, source_kind: "script", npm_package_name: undefined };
    const v = await queryNpmViewLatest(scriptEntry, stub);
    assert.equal(v, null);
    assert.equal(called, false, "dispatcher must not be invoked for non-npm entries");
  });

  test("npm entry: dispatches `npm view <pkg> versions --json` + maxSatisfying", async () => {
    let captured: string[] = [];
    const stub = async (_user: string, argv: string[], _opts: { env: Record<string, string> }) => {
      captured = argv;
      return {
        exitCode: 0,
        stdout: '["1.0.0","1.1.0","1.2.0","2.0.0"]',
        stderr: "",
      };
    };
    const e: CatalogEntry = { ...E, version_constraint: "^1.0" };
    const v = await queryNpmViewLatest(e, stub);
    assert.equal(v, "1.2.0");
    assert.deepEqual(captured, ["npm", "view", "foo", "versions", "--json"]);
  });

  test("npm entry without constraint: returns newest", async () => {
    const stub = async () => ({
      exitCode: 0,
      stdout: '["1.0.0","1.1.0","2.0.0"]',
      stderr: "",
    });
    const v = await queryNpmViewLatest(E, stub);
    assert.equal(v, "2.0.0");
  });

  test("npm view exits non-zero: throws with stderr", async () => {
    const stub = async () => ({
      exitCode: 1,
      stdout: "",
      stderr: "E404 not found",
    });
    await assert.rejects(queryNpmViewLatest(E, stub), /npm view foo.*failed.*E404/s);
  });

  test("npm view returns single string (package with 1 version): coerced to array", async () => {
    // `npm view <pkg> versions --json` on a package with a single published
    // version emits a bare JSON string rather than a one-element array. Guard
    // confirms the array-or-scalar branch in queryNpmViewLatest.
    const stub = async () => ({ exitCode: 0, stdout: '"1.0.0"', stderr: "" });
    const v = await queryNpmViewLatest(E, stub);
    assert.equal(v, "1.0.0");
  });

  test("npm view returns unparseable JSON: throws with context", async () => {
    const stub = async () => ({ exitCode: 0, stdout: "not json at all", stderr: "" });
    await assert.rejects(queryNpmViewLatest(E, stub), /returned unparseable JSON/);
  });
});
