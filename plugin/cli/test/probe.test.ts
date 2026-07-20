// plugin/cli/test/probe.test.ts — probeInstalledVersion (#6 dogfood).
// Stages a fake npm prefix (NPM_CONFIG_PREFIX) with node_modules/<pkg>/package.json
// so the probe reads a real on-disk version deterministically, no network.

import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, describe, test } from "node:test";
import type { CatalogEntry } from "../src/types.js";

let TMP: string;

const { probeInstalledVersion } = await import("../src/version/probe.js");

function npmEntry(id: string, pkg: string): CatalogEntry {
  return {
    id,
    display_name: id,
    description: ".",
    source_kind: "npm",
    npm_package_name: pkg,
    pinned_version: "1.0.0",
    install_recipe_path: "install.sh",
    uninstall_recipe_path: "uninstall.sh",
  };
}

async function stagePkg(pkg: string, version: string): Promise<void> {
  const dir = join(TMP, "lib", "node_modules", pkg);
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, "package.json"), JSON.stringify({ name: pkg, version }));
}

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-probe-"));
  process.env.NPM_CONFIG_PREFIX = TMP;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete required to unset process.env
  delete process.env.NPM_CONFIG_PREFIX;
});

describe("probeInstalledVersion (#6)", () => {
  test("reads the installed package.json version for a scoped npm entry", async () => {
    await stagePkg("@openai/codex", "0.144.5");
    assert.equal(probeInstalledVersion(npmEntry("codex", "@openai/codex")), "0.144.5");
  });

  test("resolves an unscoped npm package name too", async () => {
    await stagePkg("ccusage", "2.3.4");
    assert.equal(probeInstalledVersion(npmEntry("ccusage", "ccusage")), "2.3.4");
  });

  test("returns null when the package is absent (caller falls back to the sentinel)", () => {
    assert.equal(probeInstalledVersion(npmEntry("nope", "@scope/nope")), null);
  });

  test("returns null for a non-npm source_kind", () => {
    const binary: CatalogEntry = {
      id: "rtk",
      display_name: "rtk",
      description: ".",
      source_kind: "binary",
      pinned_version: "1.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    };
    assert.equal(probeInstalledVersion(binary), null);
  });

  test("returns null for an npm entry missing npm_package_name", () => {
    const e = npmEntry("x", "x");
    // biome-ignore lint/performance/noDelete: exercise the missing-field guard
    delete (e as { npm_package_name?: string }).npm_package_name;
    assert.equal(probeInstalledVersion(e), null);
  });

  test("normalizes the version via semver.valid (drops a leading v)", async () => {
    await stagePkg("weird", "v3.2.1");
    assert.equal(probeInstalledVersion(npmEntry("weird", "weird")), "3.2.1");
  });

  test("returns null on an unparseable package.json", async () => {
    const dir = join(TMP, "lib", "node_modules", "broken");
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, "package.json"), "{not json");
    assert.equal(probeInstalledVersion(npmEntry("broken", "broken")), null);
  });
});
