// plugin/cli/test/loader.test.ts — Plan 14-03 preserve_paths loader tests.
//
// Covers:
//   - U1: loadCatalog reads each agent's preserve_paths.json and populates
//         CatalogEntry.preserve_paths.
//   - U2: Agent without preserve_paths.json → preserve_paths is undefined.
//   - U3: T-14-04 — `~/../../etc` causes loadCatalog to throw.
//   - U4: T-14-04 — absolute path `/etc/sudoers` rejected.
//   - U5: Valid `~/.claude/`, `~/.config/claude/` entries normalize correctly
//         (trailing slash stripped, leading `~/` stripped).
//   - Loader throws on malformed JSON.
//   - Loader throws when preserve_paths_file is declared but file is missing.
//
// Uses AGENTLINUX_CATALOG_DIR env override to stage a tmp dir. Schema
// validation is intentionally skipped here (validate:false) so the loader
// tests focus on preserve_paths plumbing rather than catalog schema concerns.

import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";

let TMP: string;
let CATALOG_DIR: string;

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-loader-"));
  CATALOG_DIR = join(TMP, "catalog");
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
});

// Dynamic import so the env var is set before module body resolves defaults.
const { loadCatalog } = await import("../src/catalog/loader.js");

interface Agent {
  id: string;
  display_name: string;
  description: string;
  source_kind: "script" | "npm";
  pinned_version: string;
  install_recipe_path: string;
  uninstall_recipe_path: string;
  preserve_paths_file?: string;
  npm_package_name?: string;
}

async function writeCatalog(agents: Agent[]): Promise<void> {
  await mkdir(CATALOG_DIR, { recursive: true });
  for (const a of agents) {
    await mkdir(join(CATALOG_DIR, "agents", a.id), { recursive: true });
  }
  await writeFile(
    join(CATALOG_DIR, "catalog.json"),
    JSON.stringify({ version: "0.3.4", agents }, null, 2),
  );
}

async function writePreservePaths(agentId: string, body: unknown): Promise<void> {
  const path = join(CATALOG_DIR, "agents", agentId, "preserve_paths.json");
  await writeFile(path, typeof body === "string" ? body : JSON.stringify(body, null, 2));
}

describe("loader — preserve_paths.json (Plan 14-03)", () => {
  beforeEach(async () => {
    await rm(CATALOG_DIR, { recursive: true, force: true });
  });

  test("U1: loadCatalog reads each agent's preserve_paths.json and populates entry.preserve_paths", async () => {
    await writeCatalog([
      {
        id: "claude-code",
        display_name: "Claude Code",
        description: "preserve-test fixture",
        source_kind: "script",
        pinned_version: "2.1.98",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
      {
        id: "gsd",
        display_name: "GSD",
        description: "preserve-test fixture",
        source_kind: "npm",
        npm_package_name: "get-shit-done-cc",
        pinned_version: "1.37.1",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    await writePreservePaths("claude-code", {
      preserve_paths: ["~/.claude/", "~/.config/claude/"],
    });
    await writePreservePaths("gsd", {
      preserve_paths: ["~/.gsd/", "~/.config/get-shit-done/"],
    });

    const catalog = await loadCatalog({ validate: false });
    const claude = catalog.agents.find((a) => a.id === "claude-code");
    const gsd = catalog.agents.find((a) => a.id === "gsd");
    assert.ok(claude);
    assert.ok(gsd);
    assert.deepEqual(claude.preserve_paths, [".claude", ".config/claude"]);
    assert.deepEqual(gsd.preserve_paths, [".gsd", ".config/get-shit-done"]);
  });

  test("U2: Agent with NO preserve_paths_file → preserve_paths is undefined", async () => {
    await writeCatalog([
      {
        id: "no-preserve",
        display_name: "No Preserve",
        description: "no preserves",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
      },
    ]);
    const catalog = await loadCatalog({ validate: false });
    const entry = catalog.agents[0];
    assert.equal(entry.preserve_paths, undefined);
    assert.equal(entry.preserve_paths_file, undefined);
  });

  test("U3: T-14-04 — `~/../../etc` causes loadCatalog to throw", async () => {
    await writeCatalog([
      {
        id: "evil",
        display_name: "Evil",
        description: "traversal fixture",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    await writePreservePaths("evil", {
      preserve_paths: ["~/../../etc"],
    });
    await assert.rejects(
      () => loadCatalog({ validate: false }),
      /traversal forbidden|forbidden|\.\./i,
    );
  });

  test("U4: T-14-04 — absolute path `/etc/sudoers` is rejected (must start with ~/)", async () => {
    await writeCatalog([
      {
        id: "evil-abs",
        display_name: "Evil Abs",
        description: "absolute fixture",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    await writePreservePaths("evil-abs", {
      preserve_paths: ["/etc/sudoers"],
    });
    await assert.rejects(() => loadCatalog({ validate: false }), /must start with '~\/'/);
  });

  test("U5: Valid `~/.claude/` and `~/.config/claude/` entries normalize (strip leading ~/ and trailing /)", async () => {
    await writeCatalog([
      {
        id: "normalize-test",
        display_name: "Normalize Test",
        description: "normalization fixture",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    await writePreservePaths("normalize-test", {
      preserve_paths: ["~/.claude/", "~/.config/claude/", "~/.cache/foo"],
    });
    const catalog = await loadCatalog({ validate: false });
    const entry = catalog.agents[0];
    assert.deepEqual(entry.preserve_paths, [".claude", ".config/claude", ".cache/foo"]);
  });

  test("loader throws when preserve_paths.json is invalid JSON", async () => {
    await writeCatalog([
      {
        id: "bad-json",
        display_name: "Bad JSON",
        description: "bad-json fixture",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    await writePreservePaths("bad-json", "{not valid json");
    await assert.rejects(() => loadCatalog({ validate: false }), /not valid JSON|JSON/);
  });

  test("loader throws when preserve_paths_file is declared but file missing", async () => {
    await writeCatalog([
      {
        id: "missing-file",
        display_name: "Missing",
        description: "missing-file fixture",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    // No preserve_paths.json written.
    await assert.rejects(() => loadCatalog({ validate: false }), /not found|ENOENT/);
  });

  test("loader throws when preserve_paths field is missing or not an array", async () => {
    await writeCatalog([
      {
        id: "shape-bad",
        display_name: "Shape Bad",
        description: "shape fixture",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    await writePreservePaths("shape-bad", { not_preserve_paths: ["~/.foo"] });
    await assert.rejects(
      () => loadCatalog({ validate: false }),
      /missing required 'preserve_paths'/,
    );
  });

  test("T-14-04 — empty entry (just '~/') is rejected", async () => {
    await writeCatalog([
      {
        id: "empty-entry",
        display_name: "Empty",
        description: "empty entry fixture",
        source_kind: "script",
        pinned_version: "1.0.0",
        install_recipe_path: "install.sh",
        uninstall_recipe_path: "uninstall.sh",
        preserve_paths_file: "preserve_paths.json",
      },
    ]);
    await writePreservePaths("empty-entry", {
      preserve_paths: ["~/"],
    });
    await assert.rejects(() => loadCatalog({ validate: false }), /empty after stripping/);
  });
});
