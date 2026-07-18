// plugin/cli/test/rewire.test.ts — reconcileCrossWiring (#4 / WIRE-02).
// DI dispatcher captures which provider rewire recipes get re-run after a coding
// agent is installed, verifying order-independence without spawning anything.

import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import type { Catalog } from "../src/types.js";

let TMP: string;
let STATE_DIR: string;

const CATALOG: Catalog = {
  version: "0.3.0",
  catalogDir: "/opt/agentlinux/catalog/0.3.0",
  agents: [
    {
      id: "codex",
      display_name: "codex",
      description: ".",
      source_kind: "npm",
      npm_package_name: "@openai/codex",
      pinned_version: "0.142.3",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
    },
    {
      id: "rtk",
      display_name: "rtk",
      description: ".",
      source_kind: "binary",
      pinned_version: "0.42.4",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
      rewire_recipe_path: "rewire.sh",
    },
    {
      id: "github-mcp",
      display_name: "gh mcp",
      description: ".",
      source_kind: "mcp",
      pinned_version: "1.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
      rewire_recipe_path: "install.sh",
    },
    {
      id: "chrome-devtools-mcp",
      display_name: "chrome mcp",
      description: ".",
      source_kind: "mcp",
      pinned_version: "1.0.0",
      install_recipe_path: "install.sh",
      uninstall_recipe_path: "uninstall.sh",
      // no rewire_recipe_path — claude-only MCP, not a fan-out provider.
    },
  ],
};

const { reconcileCrossWiring } = await import("../src/rewire.js");
const { writeSentinel } = await import("../src/state/sentinel.js");

type Call = { user: string; argv: string[] };
function makeCap(result = { exitCode: 0, stdout: "", stderr: "" }) {
  const calls: Call[] = [];
  const impl = async (user: string, argv: string[]) => {
    calls.push({ user, argv });
    return result;
  };
  return { impl, calls };
}

function silence() {
  const origLog = console.log;
  const origErr = console.error;
  console.log = () => {};
  console.error = () => {};
  return () => {
    console.log = origLog;
    console.error = origErr;
  };
}

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-rewire-"));
  STATE_DIR = join(TMP, "state/installed.d");
  process.env.AGENTLINUX_STATE_DIR = STATE_DIR;
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete required to unset process.env
  delete process.env.AGENTLINUX_STATE_DIR;
});

async function seed(...ids: string[]): Promise<void> {
  for (const id of ids) {
    const entry = CATALOG.agents.find((a) => a.id === id);
    await writeSentinel({
      id,
      version: entry?.pinned_version ?? "1.0.0",
      source: "curated",
      sticky: false,
      installed_at: "2026-07-01T00:00:00.000Z",
      status: "installed",
    });
  }
}

describe("reconcileCrossWiring (#4 / WIRE-02)", () => {
  beforeEach(async () => {
    await rm(STATE_DIR, { recursive: true, force: true });
  });

  test("installing a NON-wireable id (a provider) does not reconcile", async () => {
    await seed("rtk", "github-mcp");
    const cap = makeCap();
    const restore = silence();
    try {
      await reconcileCrossWiring("rtk", CATALOG, cap.impl);
    } finally {
      restore();
    }
    assert.equal(cap.calls.length, 0, "rtk is a provider, not a wiring target");
  });

  test("installing a wireable agent re-runs each installed provider's rewire recipe", async () => {
    await seed("rtk", "github-mcp", "codex", "chrome-devtools-mcp");
    const cap = makeCap();
    const restore = silence();
    try {
      await reconcileCrossWiring("codex", CATALOG, cap.impl);
    } finally {
      restore();
    }
    // Providers = rtk (rewire.sh) + github-mcp (install.sh). NOT codex (the
    // installed id / no rewire), NOT chrome-devtools-mcp (no rewire recipe).
    assert.equal(cap.calls.length, 2);
    const recipes = cap.calls.map((c) => c.argv[1]).sort();
    assert.ok(
      recipes.some((r) => r.endsWith("/agents/rtk/rewire.sh")),
      "rtk rewire dispatched",
    );
    assert.ok(
      recipes.some((r) => r.endsWith("/agents/github-mcp/install.sh")),
      "github-mcp re-registration dispatched",
    );
    assert.ok(cap.calls.every((c) => c.user === "agent"));
  });

  test("no providers installed → no dispatch", async () => {
    await seed("codex");
    const cap = makeCap();
    const restore = silence();
    try {
      await reconcileCrossWiring("codex", CATALOG, cap.impl);
    } finally {
      restore();
    }
    assert.equal(cap.calls.length, 0);
  });

  test("a provider rewire that exits non-zero is best-effort (never throws)", async () => {
    await seed("rtk", "codex");
    const cap = makeCap({ exitCode: 1, stdout: "", stderr: "boom" });
    const restore = silence();
    try {
      await reconcileCrossWiring("codex", CATALOG, cap.impl);
    } finally {
      restore();
    }
    assert.equal(cap.calls.length, 1, "still attempted despite the failure");
  });

  test("a THROWING dispatcher is caught; the reconcile resolves and continues to the next provider", async () => {
    // Guards the try/catch arm (a dispatcher that rejects, not merely exits
    // non-zero). Two providers installed; the dispatcher throws on the first —
    // reconcile must not propagate, and must still attempt the second.
    await seed("rtk", "github-mcp", "codex");
    const calls: string[] = [];
    const throwing = async (_u: string, argv: string[]) => {
      calls.push(argv[1]);
      throw new Error("dispatch exploded");
    };
    const restore = silence();
    try {
      // Must resolve, not reject.
      await reconcileCrossWiring("codex", CATALOG, throwing);
    } finally {
      restore();
    }
    assert.equal(calls.length, 2, "both providers attempted despite the first throwing");
  });
});
