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
      compatibility_window: ">=2.95.0 <3.0.0",
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
      compatibility_window: ">=0.142.0 <0.143.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "github-mcp",
      display_name: "GitHub MCP",
      description: "mcp fixture — no PATH binary",
      source_kind: "mcp",
      endpoint_url: "https://api.githubcopilot.com/mcp/",
      pinned_version: "1.5.0",
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
    assert.match(joined, /detected — run: agentlinux adopt gh to manage/);
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
    assert.equal(codex.present_adoptable, true, "in-window managed-path tool is adoptable");
    assert.equal(codex.installed, "0.142.3");
  });

  test("managed-path tool OUT of compatibility window → present but NOT adoptable → install-to-manage (QA F-QA-02)", async () => {
    // Regression guard: gh at its managed path but at 3.5.0 (outside >=2.95.0
    // <3.0.0). adopt/tryReuse would refuse (out-of-window), so `list` must NOT
    // recommend `adopt` — it points at `install` to reconcile at the pin. This is
    // the dead-end the fuller QA pass caught after the install->adopt hint change.
    stageCache([
      { id: "gh", status: "healthy", path: "/home/agent/.local/bin/gh", version: "3.5.0" },
    ]);
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const rows = JSON.parse(cap.lines.join("\n"));
    const gh = rows.find((r: { id: string }) => r.id === "gh");
    assert.equal(gh.status, "present");
    assert.equal(gh.present_canonical, true, "still at the managed path");
    assert.equal(gh.present_adoptable, false, "out-of-window → not adoptable");
  });

  test("out-of-window managed-path tool renders the install-to-manage hint, not adopt", async () => {
    stageCache([
      { id: "gh", status: "healthy", path: "/home/agent/.local/bin/gh", version: "3.5.0" },
    ]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /detected out-of-window — run: agentlinux install gh to manage/);
    assert.doesNotMatch(joined, /agentlinux adopt gh/);
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

  test("npm tool at a non-managed path → present + migrate hint", async () => {
    // Guards managedBinDir's npm case: a codex resolved outside ~/.npm-global/bin
    // must read migrate, not adopt.
    stageCache([{ id: "codex", status: "healthy", path: "/usr/bin/codex", version: "0.142.3" }]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /codex\s+present/);
    assert.match(joined, /\/usr\/bin\/codex, not the managed path/);
    assert.match(joined, /to migrate/);
  });

  test("mcp entry in cache → NOT surfaced as present (no PATH binary)", async () => {
    // Even a healthy cache entry for an mcp id must not render as a present
    // binary — MCP presence is a client-config registration, out of scope here.
    stageCache([
      { id: "github-mcp", status: "healthy", path: "/home/agent/.local/bin/x", version: "1.5.0" },
    ]);
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const rows = JSON.parse(cap.lines.join("\n"));
    const mcp = rows.find((r: { id: string }) => r.id === "github-mcp");
    assert.equal(mcp.status, "not-installed");
    assert.equal(mcp.present, false);
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
