// plugin/cli/src/detect.ts — shared detect-cache reader + REUSE-03 / REMEDIATE-04
// pre-runner decision helpers, plus the REUSE-03 presence overlay for `list`.
//
// Extracted from commands/install.ts so install, adopt, and list share ONE
// canonical-path map and ONE cache parser. Drift between separate copies would
// flip reuse↔remediate↔present inconsistently across the three commands.

import { existsSync, readFileSync, statSync } from "node:fs";
import semver from "semver";
import type { CatalogEntry } from "./types.js";

// REUSE-03 canonical path map. MUST stay byte-identical to the bash
// REUSE_AGENT_CANONICAL_PATHS in plugin/lib/reuse/agents.sh. claude-code's
// canonical path is the native installer's ~agent/.local/bin/claude, NOT the
// npm-global variant (that's PATH-MISMATCH territory for REMEDIATE-04).
export const CANONICAL_PATHS: Record<string, string> = {
  "claude-code": "/home/agent/.local/bin/claude",
  gsd: "/home/agent/.npm-global/bin/gsd-core",
  "playwright-cli": "/home/agent/.npm-global/bin/playwright-cli",
};

// GSD's second canonical presence — the deployed-system VERSION file. The Open
// GSD installer writes its runtime under `~/.claude/gsd-core`; this path is the
// fallback when a package-native binary is absent. detect/agents.sh reports gsd
// at this path when the binary is absent, and it counts as canonical for REUSE.
// MUST stay byte-identical to REUSE_GSD_SYSTEM_PATH in
// plugin/lib/reuse/agents.sh.
export const GSD_SYSTEM_PATH = "/home/agent/.claude/gsd-core/VERSION";

// A detected agent is "at canonical" when its path is the catalog canonical OR,
// for gsd only, the deployed-system VERSION file (gsd's dual presence).
export function isCanonicalAgentPath(
  entry: CatalogEntry,
  path: string,
  canonical: string,
): boolean {
  return path === canonical || (entry.id === "gsd" && path === GSD_SYSTEM_PATH);
}

// Agent home base for the managed-dir heuristic. Mirrors the hardcoded home in
// CANONICAL_PATHS; overridable so unit tests can point at a fixture tree.
function agentHome(): string {
  return process.env.AGENTLINUX_AGENT_HOME ?? "/home/agent";
}

// The dir AgentLinux's own recipe installs a tool's binary into, by source_kind:
// npm globals land in the per-user npm prefix bin; prebuilt binaries and script
// installers land in ~/.local/bin. Returns null for kinds with no PATH binary
// (mcp). Used ONLY for the list presence adopt-vs-migrate hint — never gates a
// mutation, so an imperfect guess degrades to "migrate" wording, not a reinstall.
function managedBinDir(entry: CatalogEntry): string | null {
  switch (entry.source_kind) {
    case "npm":
      return `${agentHome()}/.npm-global/bin`;
    case "binary":
    case "script":
      return `${agentHome()}/.local/bin`;
    default:
      return null;
  }
}

// True when a detected binary sits in its source_kind's managed install dir —
// i.e. AgentLinux already owns the path, so list renders "adopt" not "migrate".
function isManagedPath(entry: CatalogEntry, path: string): boolean {
  const dir = managedBinDir(entry);
  return dir !== null && path.startsWith(`${dir}/`);
}

// "Is this detected binary at the path AgentLinux would manage it at?" —
// the single at-canonical predicate shared by adopt (tryReuse) and list
// (detectPresence) so the two agree on what counts as adoptable. The original
// three carry an EXACT canonical path (CANONICAL_PATHS + gsd's dual VERSION
// presence); every other catalog tool has no such entry, so its managed path is
// derived from the source_kind's install dir. Without this, a brownfield rtk/gh
// would read `present` in `list` yet be un-adoptable (dead-end) — the exact
// inconsistency this fixes.
function isAtManagedPath(entry: CatalogEntry, path: string): boolean {
  const known = CANONICAL_PATHS[entry.id];
  return known ? isCanonicalAgentPath(entry, path, known) : isManagedPath(entry, path);
}

export interface ReuseHit {
  binary_path: string;
  version: string;
  detected_source: string;
}

// REMEDIATE-04: tryRemediate return shape. `reason` discriminates the two
// trigger paths for the log line:
//   - "broken"        — detect cache reports status=broken
//   - "path-mismatch" — status=healthy but resolved path != CANONICAL_PATHS[id]
//                       (e.g. `npm install -g` landed claude at the npm-global
//                       path instead of the canonical native one). This is the
//                       npm→native migration case for claude-code (AL-62).
// `detected_version` carries the user's currently-installed version for a healthy
// path-mismatch so the migration can preserve it (install native at the detected
// version, not the catalog pin); null for a broken install (no version to keep).
export interface RemediateHit {
  reason: "broken" | "path-mismatch";
  detected_path: string;
  canonical_path: string;
  detected_version: string | null;
}

export interface DetectCacheAgent {
  id: string;
  status: string;
  path: string;
  version: string;
}

// The AGENTLINUX_DETECT_CACHE override is the detect-cache test seam, shared by
// install (reuse/remediate), adopt, and list (presence). upgrade.ts and
// remove.ts never read the detect cache.
export function detectCachePath(): string {
  return process.env.AGENTLINUX_DETECT_CACHE ?? "/run/agentlinux-detect.json";
}

// Shared detect-cache reader. Resolves the cache path, parses it (accepting both
// the on-disk top-level `agents` shape from detect::run_once AND the
// `--report-only` `.components.agents` wrapped shape), and returns the detected
// agent for <entry> with its canonical path. Returns null on every condition the
// callers treat as "not a candidate": cache absent/unparseable, id has no
// canonical path, or the agent isn't in the cache.
// Low-level cache parse: resolve the path, parse it (accepting both the on-disk
// top-level `agents` shape AND the `--report-only` `.components.agents` shape),
// and return the agents array, or null when the cache is absent/unparseable.
function readCacheAgents(): DetectCacheAgent[] | null {
  const cachePath = detectCachePath();
  if (!existsSync(cachePath)) return null;
  let cache: { agents?: DetectCacheAgent[]; components?: { agents?: DetectCacheAgent[] } };
  try {
    cache = JSON.parse(readFileSync(cachePath, "utf8"));
  } catch {
    return null;
  }
  return cache.agents ?? cache.components?.agents ?? null;
}

// Cache lookup by id with NO canonical-path requirement. The list presence
// overlay uses this so every detected catalog tool is surfaced, not only the
// ones with a CANONICAL_PATHS entry.
export function readCachedAgentById(id: string): DetectCacheAgent | null {
  return readCacheAgents()?.find((a) => a.id === id) ?? null;
}

// Canonical-gated reader for REUSE-03 / REMEDIATE-04. Those decisions compare the
// detected path against a KNOWN canonical path, so an entry without one is simply
// not a reuse/remediate candidate — install behavior is unchanged for such tools.
export function readDetectedAgent(
  entry: CatalogEntry,
): { detected: DetectCacheAgent; canonical: string } | null {
  const canonical = CANONICAL_PATHS[entry.id];
  if (!canonical) return null;
  const detected = readCachedAgentById(entry.id);
  if (!detected) return null;
  return { detected, canonical };
}

// REUSE-03 pre-runner check: read the detect cache + semver-check the catalog's
// compatibility_window against the detected version. Returns a ReuseHit on full
// match, null on any non-REUSE condition (absent agent, path-mismatch,
// version-out-of-window, missing cache, etc.).
export function tryReuse(entry: CatalogEntry): ReuseHit | null {
  if (!entry.compatibility_window) return null;
  // Not canonical-gated: any catalog tool detected at its managed path is a
  // reuse candidate (isAtManagedPath keeps the original three on their exact
  // canonical paths). This is what lets `adopt` record a brownfield rtk/gh that
  // `list` already surfaces as `present`, closing the dead-end.
  const detected = readCachedAgentById(entry.id);
  if (!detected) return null;
  if (detected.status !== "healthy") return null;
  if (!isAtManagedPath(entry, detected.path)) return null;
  // Forward the semver-NORMALIZED version (drops a leading `v`/whitespace the
  // cache may carry) so the sentinel + any downstream install use a clean value.
  const version = semver.valid(detected.version);
  if (!version) return null;
  if (!semver.satisfies(version, entry.compatibility_window)) return null;

  // Re-validate the binary actually exists at install time — the cache may be
  // stale (binary removed by an unrelated process since detect::run_once).
  try {
    const st = statSync(detected.path);
    if (!st.isFile()) return null;
  } catch {
    return null;
  }
  return {
    binary_path: detected.path,
    version,
    detected_source: "pre-existing",
  };
}

// REMEDIATE-04 pre-runner check. Shares readDetectedAgent with tryReuse but
// applies the inverse discriminator: returns a RemediateHit when status=broken
// OR status=healthy with a non-canonical path (PATH-MISMATCH); null otherwise
// (cache absent, parse fails, greenfield, or REUSE territory). A broken install
// has no version to preserve → reinstall at the pin; a healthy path-mismatch
// (the npm→native migration) carries detected_version so install can keep it.
export function tryRemediate(entry: CatalogEntry): RemediateHit | null {
  const hit = readDetectedAgent(entry);
  if (!hit) return null;
  const { detected, canonical } = hit;
  if (detected.status === "broken") {
    return {
      reason: "broken",
      detected_path: detected.path,
      canonical_path: canonical,
      detected_version: null,
    };
  }
  if (detected.status === "healthy" && !isCanonicalAgentPath(entry, detected.path, canonical)) {
    return {
      reason: "path-mismatch",
      detected_path: detected.path,
      canonical_path: canonical,
      // Normalized (semver.valid returns the clean version or null).
      detected_version: semver.valid(detected.version),
    };
  }
  return null;
}

// Presence overlay for `agentlinux list` (honest-status, AL-61 + AL-62). Reuses
// the detect cache: an agent with no sentinel but reported healthy is physically
// PRESENT, not "not-installed". `canonical` distinguishes the two cases list
// renders differently:
//   - canonical=true  → at the managed path; adoptable ("run adopt to manage").
//                       adopt records it into a reused sentinel with no reinstall
//                       (adopt-on-install already does this on the greenfield
//                       apply; this covers the pre-adoption window and now every
//                       catalog tool, not just the original three).
//   - canonical=false → present at a non-canonical path (e.g. claude installed via
//                       npm at ~/.npm-global/bin/claude); a MIGRATION candidate,
//                       not blessed — list points at `agentlinux install` to
//                       migrate to the native build (AL-62).
// Pure cache read — no host stat — so the status is host-independent in tests.
export interface PresenceHit {
  version: string | null;
  path: string;
  canonical: boolean;
}

export function detectPresence(entry: CatalogEntry): PresenceHit | null {
  // MCP entries have no PATH binary — "presence" for them means a client-config
  // registration, which the bash probe does not report and this overlay does not
  // detect (deferred follow-up). Guard explicitly so a stray mcp cache entry is
  // never mislabeled as a present-but-migrate binary.
  if (entry.source_kind === "mcp") return null;
  const detected = readCachedAgentById(entry.id);
  if (!detected || detected.status !== "healthy") return null;
  // Same at-canonical predicate adopt uses (isAtManagedPath): the original three
  // by exact canonical path, every other catalog tool by its managed install
  // dir. Keeps list's adopt-vs-migrate hint in lockstep with what `adopt` will do.
  const canonical = isAtManagedPath(entry, detected.path);
  return {
    // Normalized (semver.valid returns the clean version or null).
    version: semver.valid(detected.version),
    path: detected.path,
    canonical,
  };
}
