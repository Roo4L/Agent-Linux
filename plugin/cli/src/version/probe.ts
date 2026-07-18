// plugin/cli/src/version/probe.ts — runtime "what's actually on disk" version probe.
//
// #6 (dogfood): `list` reported the SENTINEL version (recorded at install time),
// so an agent that self-updated out of band (`codex update`, a stray
// `npm i -g …`) still read "synced" at the stale pin while `codex --version`
// disagreed. Probing the real installed version lets classify() surface
// drift-undeclared and lets the INSTALLED column show the truth.
//
// Scope: npm-source entries, read cheaply from the installed package.json under
// the agent npm prefix — a plain file read, no child process, no network. Other
// source_kinds (binary/script/mcp) return null → callers fall back to the
// sentinel version (unchanged behavior). The prefix is the canonical
// NPM_CONFIG_PREFIX (byte-identical to runner.ts AGENT_PATH's prefix),
// overridable via the same env var so unit tests can point at a fixture tree.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import semver from "semver";
import type { CatalogEntry } from "../types.js";

const DEFAULT_NPM_PREFIX = "/home/agent/.npm-global";

// Resolve the prefix lazily on each call so a test that sets NPM_CONFIG_PREFIX
// after import still takes effect (mirrors sentinel.ts / detect.ts seams).
export function npmPrefix(): string {
  return process.env.NPM_CONFIG_PREFIX ?? DEFAULT_NPM_PREFIX;
}

// The actual on-disk version of an installed entry, or null when it can't be
// determined cheaply — non-npm kind, package absent, or an unreadable/!semver
// package.json. Null is the "fall back to the sentinel version" signal, never an
// error: probing is a best-effort truth overlay, and a missing package.json for
// an entry with a sentinel just means we can't improve on the recorded value.
export function probeInstalledVersion(entry: CatalogEntry): string | null {
  if (entry.source_kind !== "npm" || !entry.npm_package_name) return null;
  // Global npm layout: <prefix>/lib/node_modules/<pkg>/package.json. A scoped
  // name (@openai/codex) nests one extra dir; join() splits on '/' verbatim, so
  // the scope and package become two path segments — exactly npm's on-disk shape.
  const pkgJson = join(npmPrefix(), "lib", "node_modules", entry.npm_package_name, "package.json");
  try {
    const version = (JSON.parse(readFileSync(pkgJson, "utf8")) as { version?: unknown }).version;
    return typeof version === "string" ? semver.valid(version) : null;
  } catch {
    return null;
  }
}
