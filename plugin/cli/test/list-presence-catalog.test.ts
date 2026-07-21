// plugin/cli/test/list-presence-catalog.test.ts — presence overlay for catalog
// tools WITHOUT a CANONICAL_PATHS entry (the v0.3.6 catalog expansion beyond the
// original three agents).
//
// detectPresence used to require CANONICAL_PATHS[id], so a manually-installed
// codex/gh/rtk/… (no sentinel, not one of the original three) read
// "not-installed" even though the host had it. The overlay now surfaces any
// detected catalog tool and decides the adopt-vs-migrate hint from the
// source_kind's managed install dir (npm → ~/.npm-global/bin, binary/script →
// ~/.local/bin). Pure cache read, so every assertion is host-independent.

import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;

// gh (binary) and codex (npm) — neither is in detect.ts CANONICAL_PATHS, so both
// exercise the generalized isManagedPath branch, not the original exact-path one.
const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "gh",
      display_name: "GitHub CLI",
      description: "binary presence fixture",
      source_kind: "binary",
      pinned_version: "2.95.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "codex",
      display_name: "Codex CLI",
      description: "npm presence fixture",
      source_kind: "npm",
      npm_package_name: "@openai/codex",
      pinned_version: "0.142.3",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-list-presence-catalog-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  await mkdir(CATALOG_DIR, { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_STATE_DIR;
  // biome-ignore lint/performance/noDelete: delete is required for process.env
  delete process.env.AGENTLINUX_DETECT_CACHE;
});

const { listCmd } = await import("../src/commands/list.js");

function captureStdout() {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) =>
    lines.push(args.map((a) => (typeof a === "string" ? a : String(a))).join(" "));
  return {
    lines,
    restore: () => {
      console.log = original;
    },
  };
}

let cacheSeq = 0;
function stageCache(agents: Array<{ id: string; status: string; path: string; version: string }>) {
  cacheSeq += 1;
  const cachePath = join(TMP, `detect-${cacheSeq}.json`);
  writeFileSync(cachePath, JSON.stringify({ components: { agents } }));
  process.env.AGENTLINUX_DETECT_CACHE = cachePath;
}

describe("listCmd — presence overlay for catalog-expansion tools (no CANONICAL_PATHS)", () => {
  beforeEach(() => {
    process.env.AGENTLINUX_DETECT_CACHE = join(TMP, "nonexistent-detect.json");
  });

  test("binary tool at its managed ~/.local/bin path → present + adopt hint", async () => {
    stageCache([
      { id: "gh", status: "healthy", path: "/home/agent/.local/bin/gh", version: "2.95.0" },
    ]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /gh\s+present\s+2\.95\.0\s+2\.95\.0/);
    assert.match(joined, /detected — run: agentlinux install gh to manage/);
  });

  test("npm tool at its managed ~/.npm-global/bin path → present + adopt hint", async () => {
    stageCache([
      {
        id: "codex",
        status: "healthy",
        path: "/home/agent/.npm-global/bin/codex",
        version: "0.142.3",
      },
    ]);
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const rows = JSON.parse(cap.lines.join("\n"));
    const codex = rows.find((r: { id: string }) => r.id === "codex");
    assert.equal(codex.status, "present");
    assert.equal(codex.present, true);
    assert.equal(codex.present_canonical, true);
    assert.equal(codex.installed, "0.142.3");
  });

  test("binary tool at a non-managed path (system /usr/bin) → present + migrate hint", async () => {
    stageCache([{ id: "gh", status: "healthy", path: "/usr/bin/gh", version: "2.95.0" }]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /gh\s+present/);
    assert.match(joined, /\/usr\/bin\/gh, not the managed path/);
    assert.match(joined, /to migrate/);
  });

  test("broken cache entry → stays not-installed", async () => {
    stageCache([
      { id: "gh", status: "broken", path: "/home/agent/.local/bin/gh", version: "2.95.0" },
    ]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    assert.match(cap.lines.join("\n"), /gh\s+not-installed/);
  });
});
