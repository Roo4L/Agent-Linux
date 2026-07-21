// plugin/cli/test/list-presence.test.ts — listCmd presence overlay (AL-61).
//
// classify() returns "not-installed" whenever no sentinel exists; the overlay in
// list.ts reconciles against the detect cache so a present-but-unadopted agent
// reads "present" instead of absent. detectPresence is a PURE cache read (no
// host statSync), so every assertion here is host-independent and deterministic.
// Kept in its own file (own catalog fixture) so the shared CATALOG consts in
// list.test.ts stay untouched.

import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;

const GSD_SYSTEM_PATH = "/home/agent/.claude/gsd-core/VERSION";

const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "gsd",
      display_name: "Get Shit Done",
      description: "presence fixture",
      source_kind: "script",
      pinned_version: "1.37.1",
      compatibility_window: ">=1.37.0 <2.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-list-presence-"));
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
const { writeSentinel } = await import("../src/state/sentinel.js");

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

describe("listCmd — AL-61 presence overlay", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
    // Point at a nonexistent path (NOT delete) so the "no cache" default never
    // falls back to a real /run/agentlinux-detect.json on a dev host. stageCache
    // overrides this per-test.
    process.env.AGENTLINUX_DETECT_CACHE = join(TMP, "nonexistent-detect.json");
  });

  test("no sentinel + cache healthy at canonical → status 'present' with version + hint", async () => {
    stageCache([{ id: "gsd", status: "healthy", path: GSD_SYSTEM_PATH, version: "1.37.1" }]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /gsd\s+present\s+1\.37\.1\s+1\.37\.1/);
    assert.match(joined, /detected — run: agentlinux adopt gsd to manage/);
    assert.doesNotMatch(joined, /not-installed/);
  });

  test("present overlay surfaces in --json (present:true, status present)", async () => {
    stageCache([{ id: "gsd", status: "healthy", path: GSD_SYSTEM_PATH, version: "1.37.1" }]);
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const rows = JSON.parse(cap.lines.join("\n"));
    const gsd = rows.find((r: { id: string }) => r.id === "gsd");
    assert.ok(gsd);
    assert.equal(gsd.status, "present");
    assert.equal(gsd.present, true);
    assert.equal(gsd.installed, "1.37.1");
  });

  test("cache status=broken → NOT present (stays not-installed)", async () => {
    stageCache([{ id: "gsd", status: "broken", path: GSD_SYSTEM_PATH, version: "1.37.1" }]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /gsd\s+not-installed/);
    assert.doesNotMatch(joined, /to manage/);
  });

  test("cache healthy at NON-canonical path → present (migration candidate, not not-installed) (AL-62)", async () => {
    stageCache([
      { id: "gsd", status: "healthy", path: "/home/agent/.npm-global/bin/gsd", version: "1.37.1" },
    ]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /gsd\s+present/);
    // Non-canonical → migrate hint with the detected path, NOT the "manage" hint.
    assert.match(joined, /\/home\/agent\/\.npm-global\/bin\/gsd, not the managed path/);
    assert.match(joined, /to migrate/);
    assert.doesNotMatch(joined, /not-installed/);
  });

  test("no detect cache → not-installed (overlay no-op)", async () => {
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    assert.match(cap.lines.join("\n"), /gsd\s+not-installed/);
  });

  test("an existing sentinel wins over the presence overlay (reused, not present)", async () => {
    await writeSentinel({
      id: "gsd",
      version: "1.37.1",
      source: "curated",
      sticky: false,
      installed_at: "2026-01-01T00:00:00.000Z",
      status: "reused",
      binary_path: GSD_SYSTEM_PATH,
    });
    stageCache([{ id: "gsd", status: "healthy", path: GSD_SYSTEM_PATH, version: "1.37.1" }]);
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.doesNotMatch(joined, /\bpresent\b/);
    assert.match(joined, /reused — managed by agentlinux upgrade\/remove/);
  });
});
