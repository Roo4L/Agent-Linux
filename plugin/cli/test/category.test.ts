// plugin/cli/test/category.test.ts — ENABLE-06 category derivation + grouped list output.
// The pure deriveCategory() is tested directly; the grouped `--by-category` render is
// tested via the same AGENTLINUX_CATALOG_DIR env seam as list.test.ts.

import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, describe, test } from "node:test";
import { deriveCategory } from "../src/catalog/category.js";
import type { CatalogEntry } from "../src/types.js";

function entry(id: string, tags: string[], source_kind = "npm"): CatalogEntry {
  return {
    id,
    display_name: id,
    description: `${id}-fixture`,
    // biome-ignore lint/suspicious/noExplicitAny: minimal fixture cast for the source_kind union
    source_kind: source_kind as any,
    pinned_version: "1.0.0",
    install_recipe_path: "install.sh",
    uninstall_recipe_path: "uninstall.sh",
    tags,
  } as CatalogEntry;
}

describe("deriveCategory — tag precedence", () => {
  test("coding-agent tag wins over a bare agent tag", () => {
    assert.equal(deriveCategory(entry("codex", ["agent", "coding-agent"])).key, "coding-agent");
    // claude-code has only a bare `agent` tag → still a coding agent.
    assert.equal(deriveCategory(entry("claude-code", ["agent", "anthropic"])).key, "coding-agent");
  });

  test("assistant tag → AI assistants", () => {
    const c = deriveCategory(entry("openclaw", ["assistant", "daemon"], "script"));
    assert.equal(c.key, "assistant");
    assert.equal(c.label, "AI assistants");
  });

  test("mcp via tag OR source_kind fallback", () => {
    assert.equal(deriveCategory(entry("context7", ["mcp", "docs"], "mcp")).key, "mcp");
    // source_kind=mcp catches an entry whose tags omit "mcp".
    assert.equal(deriveCategory(entry("bare-mcp", ["docs"], "mcp")).key, "mcp");
  });

  test("workflow/token precede devops (rtk is a token tool, not devops)", () => {
    assert.equal(
      deriveCategory(entry("rtk", ["token", "workflow", "devops"], "binary")).key,
      "workflow",
    );
    assert.equal(deriveCategory(entry("ccusage", ["workflow", "cost", "token"])).key, "workflow");
  });

  test("devops when no workflow/token tag", () => {
    assert.equal(deriveCategory(entry("gh", ["devops", "git", "github"], "binary")).key, "devops");
    assert.equal(
      deriveCategory(entry("trivy", ["devops", "security", "scanner"], "binary")).key,
      "devops",
    );
  });

  test("browser/automation → Browser & automation, beating a bare agent tag", () => {
    assert.equal(
      deriveCategory(entry("playwright-cli", ["browser", "automation", "agent-skill"])).key,
      "browser",
    );
  });

  test("unmatched tags fall to Other, never dropped", () => {
    assert.equal(deriveCategory(entry("mystery", ["unknowable"])).key, "other");
    assert.equal(deriveCategory(entry("no-tags", [])).key, "other");
  });
});

// Grouped render smoke test — three entries across three categories.
let TMP: string;
let CATALOG_DIR: string;

const CATALOG = {
  version: "0.3.0",
  agents: [
    entry("zeta-mcp", ["mcp", "docs"], "mcp"),
    entry("alpha-agent", ["agent", "coding-agent"], "npm"),
    entry("mid-ops", ["devops", "git"], "binary"),
  ],
};

before(async () => {
  TMP = await mkdtemp(join(tmpdir(), "al-cat-"));
  CATALOG_DIR = join(TMP, "catalog");
  await mkdir(CATALOG_DIR, { recursive: true });
  await writeFile(join(CATALOG_DIR, "catalog.json"), JSON.stringify(CATALOG));
  process.env.AGENTLINUX_CATALOG_DIR = CATALOG_DIR;
  process.env.AGENTLINUX_STATE_DIR = join(TMP, "state/installed.d");
});

after(async () => {
  await rm(TMP, { recursive: true, force: true });
  // biome-ignore lint/performance/noDelete: delete is semantically required for process.env
  delete process.env.AGENTLINUX_CATALOG_DIR;
  // biome-ignore lint/performance/noDelete: delete is semantically required for process.env
  delete process.env.AGENTLINUX_STATE_DIR;
});

const { listCmd } = await import("../src/commands/list.js");

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

describe("listCmd --by-category (ENABLE-06)", () => {
  test("groups under category headers in display order", async () => {
    const cap = captureStdout();
    try {
      await listCmd({ byCategory: true });
    } finally {
      cap.restore();
    }
    const joined = cap.lines.join("\n");
    assert.match(joined, /## Coding agents/);
    assert.match(joined, /## MCP servers/);
    assert.match(joined, /## DevOps & security/);
    // Display order: Coding agents (1) before MCP servers (3) before DevOps (4).
    const ci = joined.indexOf("## Coding agents");
    const mi = joined.indexOf("## MCP servers");
    const di = joined.indexOf("## DevOps & security");
    assert.ok(ci < mi && mi < di, "categories render in canonical display order");
    // Each entry appears under its group.
    assert.match(joined, /alpha-agent/);
    assert.match(joined, /zeta-mcp/);
    assert.match(joined, /mid-ops/);
  });

  test("JSON output carries the derived category verbatim", async () => {
    const cap = captureStdout();
    try {
      await listCmd({ json: true });
    } finally {
      cap.restore();
    }
    const parsed = JSON.parse(cap.lines.join("\n"));
    const byId = new Map(parsed.map((r: { id: string }) => [r.id, r]));
    assert.equal((byId.get("alpha-agent") as { category: string }).category, "coding-agent");
    assert.equal((byId.get("zeta-mcp") as { category: string }).category, "mcp");
    assert.equal(
      (byId.get("mid-ops") as { category_label: string }).category_label,
      "DevOps & security",
    );
  });
});
