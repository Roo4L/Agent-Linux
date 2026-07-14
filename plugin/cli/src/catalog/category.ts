// plugin/cli/src/catalog/category.ts — ENABLE-06 catalog category derivation.
//
// `agentlinux list --by-category` groups entries by a small, fixed set of categories.
// The category is DERIVED from the entry's tags (with source_kind as a fallback signal),
// NOT hardcoded per entry — so a contributor adding a catalog entry via the ENABLE-07
// template lands in the right group just by choosing a canonical category tag, with zero
// CLI edits (the CAT-03 "add an entry without touching TypeScript" contract).

import type { CatalogEntry } from "../types.js";

// The canonical category keys. A literal union (not bare string) so the precedence table
// below is compile-time checked — a typo'd key fails tsc rather than returning undefined.
export type CategoryKey =
  | "coding-agent"
  | "assistant"
  | "mcp"
  | "devops"
  | "workflow"
  | "browser"
  | "other";

export interface Category {
  key: CategoryKey;
  label: string;
  order: number; // display order when grouping
}

// The canonical categories, in display order. Keep in lockstep with the ENABLE-07
// contributor template + selection rubric (docs/CATALOG-CONTRIBUTING.md).
export const CATEGORIES: Record<CategoryKey, Category> = {
  "coding-agent": { key: "coding-agent", label: "Coding agents", order: 1 },
  assistant: { key: "assistant", label: "AI assistants", order: 2 },
  mcp: { key: "mcp", label: "MCP servers", order: 3 },
  devops: { key: "devops", label: "DevOps & security", order: 4 },
  workflow: { key: "workflow", label: "Token & workflow", order: 5 },
  browser: { key: "browser", label: "Browser & automation", order: 6 },
  other: { key: "other", label: "Other", order: 99 },
};

// Tag → category precedence (FIRST matching tag wins). Order matters: a tool tagged both
// `workflow` and `devops` (e.g. rtk) is a workflow tool first, so `workflow`/`token`
// precede `devops`. `coding-agent` beats a bare `agent` (claude-code), and `browser`
// beats `agent` (playwright-cli) so browser tooling groups on its own.
const TAG_PRECEDENCE: ReadonlyArray<readonly [string, CategoryKey]> = [
  ["coding-agent", "coding-agent"],
  ["assistant", "assistant"],
  ["mcp", "mcp"],
  ["workflow", "workflow"],
  ["token", "workflow"],
  ["devops", "devops"],
  ["browser", "browser"],
  ["automation", "browser"],
  ["agent", "coding-agent"],
];

// deriveCategory — with source_kind:"mcp" as a fallback signal, and "Other" for the
// unmatched so no entry is ever dropped from the grouped view.
export function deriveCategory(entry: CatalogEntry): Category {
  const tags = entry.tags ?? [];
  for (const [tag, key] of TAG_PRECEDENCE) {
    if (tags.includes(tag)) return CATEGORIES[key];
  }
  if (entry.source_kind === "mcp") return CATEGORIES.mcp;
  return CATEGORIES.other;
}
