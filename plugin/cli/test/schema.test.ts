// plugin/cli/test/schema.test.ts — CAT-03 / CAT-04 ajv validator unit tests.
//
// Test-run strategy: compiled-first via `tsc -p tsconfig.test.json` to
// dist-test/ (see package.json "test" script). Node 20 LTS on the executor
// host lacks --experimental-strip-types; the compile-first approach keeps
// the source tree homogeneous in .ts while shipping a zero-runtime-deps
// test harness.

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { getValidator } from "../src/catalog/schema.js";

const HERE = dirname(fileURLToPath(import.meta.url));

// Fixture resolution: tsc emits test .js files under dist-test/test/ but does
// NOT copy .json fixtures. Walk up from the compiled file's dir looking for a
// sibling `test/fixtures/` tree that lives in the source under plugin/cli/.
function resolveFixturesDir(): string {
  for (let depth = 0; depth <= 6; depth++) {
    const up = Array(depth).fill("..");
    const candidate = join(HERE, ...up, "test", "fixtures");
    if (existsSync(candidate)) return candidate;
    // Also try plugin/cli/test/fixtures from higher up.
    const cliSide = join(HERE, ...up, "plugin", "cli", "test", "fixtures");
    if (existsSync(cliSide)) return cliSide;
  }
  throw new Error(`cannot locate test/fixtures/ from ${HERE}`);
}
const FIXTURES = resolveFixturesDir();

// Pin the validator to the REPO's plugin/catalog/schema.json — the source of
// truth this suite exercises — rather than whatever may be staged under
// /opt/agentlinux/catalog/<ver>/ on the build host. getValidator() consults
// AGENTLINUX_CATALOG_DIR before its production default, so setting it here at
// module load (before any getValidator() call) keeps the schema tests hermetic
// regardless of an ambient AgentLinux install on the test machine.
function resolveRepoCatalogDir(): string {
  for (let depth = 0; depth <= 6; depth++) {
    const up = Array(depth).fill("..");
    const candidate = join(HERE, ...up, "catalog", "schema.json");
    if (existsSync(candidate)) return dirname(candidate);
    const pluginSide = join(HERE, ...up, "plugin", "catalog", "schema.json");
    if (existsSync(pluginSide)) return dirname(pluginSide);
  }
  throw new Error(`cannot locate plugin/catalog/schema.json from ${HERE}`);
}
process.env.AGENTLINUX_CATALOG_DIR = resolveRepoCatalogDir();

function loadFixture(name: string): unknown {
  return JSON.parse(readFileSync(join(FIXTURES, name), "utf8"));
}

const baseValidNpmEntry = {
  id: "foo",
  display_name: "Foo",
  description: "base fixture",
  source_kind: "npm" as const,
  npm_package_name: "foo",
  pinned_version: "1.2.3",
  install_recipe_path: "install.sh",
  uninstall_recipe_path: "uninstall.sh",
};

describe("ajv catalog schema (CAT-03 / CAT-04)", () => {
  test("rejects entry missing pinned_version", async () => {
    const validate = await getValidator();
    const catalog = loadFixture("catalog-missing-pin.json");
    assert.equal(validate(catalog), false);
    const errs = validate.errors ?? [];
    assert.ok(
      errs.some(
        (e) =>
          e.keyword === "required" &&
          (e.params as { missingProperty?: string }).missingProperty === "pinned_version",
      ),
      `expected missingProperty=pinned_version; got ${JSON.stringify(errs)}`,
    );
  });

  test("rejects entry with unknown source_kind (enum)", async () => {
    const validate = await getValidator();
    const catalog = loadFixture("catalog-bad-source-kind.json");
    assert.equal(validate(catalog), false);
    const errs = validate.errors ?? [];
    assert.ok(
      errs.some((e) => e.keyword === "enum"),
      `expected keyword=enum; got ${JSON.stringify(errs)}`,
    );
    const enumErr = errs.find((e) => e.keyword === "enum");
    const allowed =
      (enumErr?.params as { allowedValues?: string[] } | undefined)?.allowedValues ?? [];
    assert.ok(allowed.includes("npm") && allowed.includes("script"));
    // ENABLE-01: "binary" is now a first-class dispatchable source_kind.
    assert.ok(allowed.includes("binary"), `expected "binary" among allowed; got ${allowed}`);
  });

  test("accepts well-formed catalog with a binary entry", async () => {
    const validate = await getValidator();
    const catalog = loadFixture("catalog-binary.json");
    const ok = validate(catalog);
    assert.equal(ok, true, `unexpected errors: ${JSON.stringify(validate.errors)}`);
  });

  test("accepts well-formed catalog with mixed npm + script entries", async () => {
    const validate = await getValidator();
    const catalog = loadFixture("catalog-valid.json");
    const ok = validate(catalog);
    assert.equal(ok, true, `unexpected errors: ${JSON.stringify(validate.errors)}`);
  });

  test("allOf: source_kind=npm missing npm_package_name fails", async () => {
    const validate = await getValidator();
    const bad = {
      version: "0.3.0",
      agents: [
        {
          id: "foo",
          display_name: "Foo",
          description: "npm entry without package name",
          source_kind: "npm",
          pinned_version: "1.2.3",
          install_recipe_path: "install.sh",
          uninstall_recipe_path: "uninstall.sh",
        },
      ],
    };
    assert.equal(validate(bad), false);
    const errs = validate.errors ?? [];
    assert.ok(
      errs.some(
        (e) =>
          e.keyword === "required" &&
          (e.params as { missingProperty?: string }).missingProperty === "npm_package_name",
      ),
      `expected missingProperty=npm_package_name; got ${JSON.stringify(errs)}`,
    );
  });

  test("pinned_version pattern rejects non-semver '1.2'", async () => {
    const validate = await getValidator();
    const bad = {
      version: "0.3.0",
      agents: [{ ...baseValidNpmEntry, pinned_version: "1.2" }],
    };
    assert.equal(validate(bad), false);
    const errs = validate.errors ?? [];
    assert.ok(
      errs.some((e) => e.keyword === "pattern" && e.instancePath.endsWith("/pinned_version")),
      `expected keyword=pattern on /pinned_version; got ${JSON.stringify(errs)}`,
    );
  });

  test("pinned_version pattern accepts '1.2.3-beta.0+sha.abc'", async () => {
    const validate = await getValidator();
    const good = {
      version: "0.3.0",
      agents: [{ ...baseValidNpmEntry, pinned_version: "1.2.3-beta.0+sha.abc" }],
    };
    const ok = validate(good);
    assert.equal(ok, true, `unexpected errors: ${JSON.stringify(validate.errors)}`);
  });
});
