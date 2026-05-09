// plugin/cli/test/classify.test.ts — pure-function classifier + decideVersion.
// Covers all six Status states (not-installed / synced / drift-undeclared /
// override-ahead / override-behind / pinned-override) plus three
// decideVersion branches (override wins / sticky preserved / curated default).

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import type { CatalogEntry, Sentinel } from "../src/types.js";
import { classify, decideVersion } from "../src/version/classify.js";

const baseEntry: CatalogEntry = {
  id: "foo",
  display_name: "Foo",
  description: "base fixture",
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

describe("classify() — six-state divergence", () => {
  test("not-installed: null sentinel + null installed", () => {
    assert.equal(classify({ entry: baseEntry, sentinel: null, installed: null }), "not-installed");
  });

  test("not-installed: sentinel present but installed=null (disk was cleaned)", () => {
    assert.equal(
      classify({ entry: baseEntry, sentinel: sentinel("1.0.0"), installed: null }),
      "not-installed",
    );
  });

  test("synced: sentinel=pinned=installed", () => {
    assert.equal(
      classify({ entry: baseEntry, sentinel: sentinel("1.0.0"), installed: "1.0.0" }),
      "synced",
    );
  });

  test("drift-undeclared: sentinel !== installed", () => {
    assert.equal(
      classify({ entry: baseEntry, sentinel: sentinel("0.9.0"), installed: "1.0.0" }),
      "drift-undeclared",
    );
  });

  test("override-ahead: installed > pinned, not sticky", () => {
    assert.equal(
      classify({
        entry: baseEntry,
        sentinel: sentinel("1.1.0", "override", false),
        installed: "1.1.0",
      }),
      "override-ahead",
    );
  });

  test("override-behind: installed < pinned, not sticky", () => {
    assert.equal(
      classify({
        entry: baseEntry,
        sentinel: sentinel("0.9.0", "override", false),
        installed: "0.9.0",
      }),
      "override-behind",
    );
  });

  test("pinned-override: sticky=true + installed !== pinned", () => {
    assert.equal(
      classify({
        entry: baseEntry,
        sentinel: sentinel("1.1.0", "pinned", true),
        installed: "1.1.0",
      }),
      "pinned-override",
    );
  });
});

describe("decideVersion() — three branches", () => {
  test("override flag wins regardless of sentinel", () => {
    const d = decideVersion(baseEntry, "2.0.0", null);
    assert.deepEqual(d, { version: "2.0.0", source: "override", sticky: false });
  });

  test("override flag wins even with sticky sentinel", () => {
    const d = decideVersion(baseEntry, "2.0.0", sentinel("1.1.0", "pinned", true));
    assert.deepEqual(d, { version: "2.0.0", source: "override", sticky: false });
  });

  test("sticky sentinel preserved when no override", () => {
    const d = decideVersion(baseEntry, undefined, sentinel("1.1.0", "pinned", true));
    assert.deepEqual(d, { version: "1.1.0", source: "pinned", sticky: true });
  });

  test("default curated: no override + non-sticky sentinel → pinned_version", () => {
    const d = decideVersion(baseEntry, undefined, sentinel("0.9.0", "curated", false));
    assert.deepEqual(d, { version: "1.0.0", source: "curated", sticky: false });
  });

  test("default curated: no override + no sentinel → pinned_version", () => {
    const d = decideVersion(baseEntry, undefined, null);
    assert.deepEqual(d, { version: "1.0.0", source: "curated", sticky: false });
  });
});
