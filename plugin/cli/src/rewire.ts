// plugin/cli/src/rewire.ts — post-install cross-agent wiring reconcile (#4 / WIRE-02).
//
// A cross-agent PROVIDER (rtk, a fan-out MCP server) wires itself into every
// coding agent PRESENT AT ITS OWN INSTALL TIME. Without this, an agent installed
// LATER stays un-wired — so the end state would depend on install order. This
// reconcile closes that gap: after a coding agent is installed, re-run each
// installed provider's lightweight rewire recipe so it fans out into the new
// agent too. The rewire recipes are idempotent + present-aware (they only touch
// agents on PATH) and cheap (no re-download), and this pass is best-effort — a
// wiring hiccup never fails the install that already succeeded.

import { join } from "node:path";
import { type Dispatcher, dispatchRecipe } from "./runner.js";
import { listSentinels } from "./state/sentinel.js";
import type { Catalog, CatalogEntry } from "./types.js";

// The coding agents that RECEIVE cross-agent wiring (rtk hooks, MCP servers).
// Installing one of these triggers the reconcile; installing anything else (a
// provider, a devops CLI) does not — the provider's own install.sh already
// fanned out into whatever was present. Mirrors the target sets in
// lib/rtk-wire.sh and lib/mcp-register.sh.
const WIREABLE_AGENTS = new Set(["claude-code", "codex", "gemini-cli", "opencode", "qwen-code"]);

export async function reconcileCrossWiring(
  installedId: string,
  catalog: Catalog,
  dispatcher?: Dispatcher,
): Promise<void> {
  // Only a freshly-installed coding agent can be a NEW wiring target.
  if (!WIREABLE_AGENTS.has(installedId)) return;

  const sentinels = await listSentinels();
  const byId = new Map(catalog.agents.map((a) => [a.id, a]));
  // Providers = installed entries that declare a rewire recipe, excluding the
  // agent we just installed (it isn't a provider; and its own install already
  // wired whatever providers were present before it).
  const providers = sentinels
    .map((s) => byId.get(s.id))
    .filter((e): e is CatalogEntry => !!e && !!e.rewire_recipe_path && e.id !== installedId);

  for (const provider of providers) {
    // rewire_recipe_path stays optional on CatalogEntry even after the filter;
    // narrow it here for the join().
    const rewire = provider.rewire_recipe_path;
    if (!rewire) continue;
    const recipePath = join(catalog.catalogDir, "agents", provider.id, rewire);
    // Best-effort: dispatchRecipe honors a "never throw" contract, but this runs
    // AFTER the sentinel is written for a SUCCEEDED install — so we still guard
    // against a future/throwing DI dispatcher, lest an exception here make an
    // install that already landed look like a failure.
    try {
      const result = await dispatchRecipe(
        {
          entry: provider,
          recipePath,
          version: provider.pinned_version,
          catalogDir: catalog.catalogDir,
        },
        dispatcher,
      );
      if (result.exitCode === 0) {
        console.log(`↻ re-wired ${provider.id} into ${installedId}`);
      } else {
        console.error(
          `↻ note: re-wiring ${provider.id} into ${installedId} exited ${result.exitCode} (install still OK; run \`agentlinux install ${provider.id}\` to re-wire)`,
        );
      }
    } catch (err) {
      console.error(
        `↻ note: re-wiring ${provider.id} into ${installedId} failed (${(err as Error).message}); install still OK`,
      );
    }
  }
}
