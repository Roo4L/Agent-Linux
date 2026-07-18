// plugin/cli/test/list-drift.test.ts — #6 dogfood: `list` shows the REAL on-disk
// version and flags drift when an agent self-updated past its recorded sentinel.
// Stages a fake npm prefix + a stale sentinel so the probe and the sentinel
// disagree deterministically (no network).

import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";

let TMP: string;
let CATALOG_DIR: string;
let STATE_DIR: string;
let NPM_PREFIX: string;

const CATALOG = {
  version: "0.3.0",
  agents: [
    {
      id: "codex",
      display_name: "OpenAI Codex",
      description: "npm drift fixture",
      source_kind: "npm",
      npm_package_name: "@openai/codex",
      pinned_version: "0.142.3",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-drift-"));
  CATALOG_DIR = join(TMP, "catalog");
  STATE_DIR = join(TMP, "state/installed.d");
  NPM_PREFIX = join(TMP, "npm");
  await mkdir(CATALOG_DIR, { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  // Fake the self-updated on-disk version: node_modules says 0.144.5.
  const pkgDir = join(NPM_PREFIX, "lib", "node_modules", "@openai/codex");
  await mkdir(pkgDir, { recursive: true });
  await writeFile(join(pkgDir, "package.json"), JSON.stringify({ version: "0.144.5" }));
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
  process.env.NPM_CONFIG_PREFIX = NPM_PREFIX;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete required to unset process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete required to unset process.env
  delete process.env.AGENTLINUX_STATE_DIR;
  // biome-ignore lint/performance/noDelete: delete required to unset process.env
  delete process.env.NPM_CONFIG_PREFIX;
});

const { listCmd } = await import("../src/commands/list.js");
const { writeSentinel } = await import("../src/state/sentinel.js");

function captureStdout() {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => {
    lines.push(args.map((a) => (typeof a === "string" ? a : String(a))).join(" "));
  };
  return {
    lines,
    restore: () => {
      console.log = original;
    },
  };
}

describe("listCmd — #6 drift surfaced from the on-disk probe", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
    // Sentinel recorded the install-time pin; the on-disk package.json moved on.
    await writeSentinel({
      id: "codex",
      version: "0.142.3",
      source: "curated",
      sticky: false,
      installed_at: "2026-07-01T00:00:00.000Z",
      status: "installed",
    });
  });

  test("JSON reports the probed real version + drifted=true + recorded sentinel_version", async () => {
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const rows = JSON.parse(cap.lines.join("\n"));
    const codex = rows.find((r: { id: string }) => r.id === "codex");
    assert.ok(codex, "codex row present");
    assert.equal(codex.installed, "0.144.5", "installed is the REAL on-disk version");
    assert.equal(codex.sentinel_version, "0.142.3", "recorded install-time version carried");
    assert.equal(codex.drifted, true);
    assert.equal(codex.status, "drift-undeclared");
  });

  test("text table shows the real version + the 'self-updated from …' reconcile pointer", async () => {
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(
      joined,
      /0\.144\.5 \(self-updated from 0\.142\.3 — run: agentlinux upgrade to reconcile\)/,
    );
  });

  test("no drift when the on-disk version matches the sentinel (synced)", async () => {
    // Rewrite the sentinel to match the on-disk 0.144.5 → no drift.
    await writeSentinel({
      id: "codex",
      version: "0.144.5",
      source: "override",
      sticky: false,
      installed_at: "2026-07-01T00:00:00.000Z",
      status: "installed",
    });
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const rows = JSON.parse(cap.lines.join("\n"));
    const codex = rows.find((r: { id: string }) => r.id === "codex");
    assert.equal(codex.drifted, false);
    assert.equal(codex.installed, "0.144.5");
  });

  test("text table omits the 'self-updated from' suffix when not drifted", async () => {
    // Companion to the drift text test: the suffix must NOT leak into a synced row.
    await writeSentinel({
      id: "codex",
      version: "0.144.5",
      source: "override",
      sticky: false,
      installed_at: "2026-07-01T00:00:00.000Z",
      status: "installed",
    });
    const cap = captureStdout();
    try {
      await listCmd({});
    } finally {
      cap.restore();
    }
    assert.doesNotMatch(cap.lines.join("\n"), /self-updated from/);
  });
});
