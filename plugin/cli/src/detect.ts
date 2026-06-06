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
  gsd: "/home/agent/.npm-global/bin/get-shit-done-cc",
  "playwright-cli": "/home/agent/.npm-global/bin/playwright-cli",
};

// GSD's second canonical presence — the deployed-system VERSION file. `npm
// install -g get-shit-done-cc` leaves a bootstrapper binary at CANONICAL_PATHS,
// but the upstream `npx get-shit-done-cc` install path deploys the GSD system
// (gsd-* skills + this VERSION file) WITHOUT a persistent binary. detect/agents.sh
// reports gsd at this path when the binary is absent, and it counts as canonical
// for REUSE. MUST stay byte-identical to REUSE_GSD_SYSTEM_PATH in
// plugin/lib/reuse/agents.sh.
export const GSD_SYSTEM_PATH = "/home/agent/.claude/get-shit-done/VERSION";

// A detected agent is "at canonical" when its path is the catalog canonical OR,
// for gsd only, the deployed-system VERSION file (gsd's dual presence).
export function isCanonicalAgentPath(
  entry: CatalogEntry,
  path: string,
  canonical: string,
): boolean {
  return path === canonical || (entry.id === "gsd" && path === GSD_SYSTEM_PATH);
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
//                       path instead of the canonical native one)
export interface RemediateHit {
  reason: "broken" | "path-mismatch";
  detected_path: string;
  canonical_path: string;
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
export function readDetectedAgent(
  entry: CatalogEntry,
): { detected: DetectCacheAgent; canonical: string } | null {
  const cachePath = detectCachePath();
  if (!existsSync(cachePath)) return null;
  const canonical = CANONICAL_PATHS[entry.id];
  if (!canonical) return null;
  let cache: { agents?: DetectCacheAgent[]; components?: { agents?: DetectCacheAgent[] } };
  try {
    cache = JSON.parse(readFileSync(cachePath, "utf8"));
  } catch {
    return null;
  }
  const agents = cache.agents ?? cache.components?.agents;
  const detected = agents?.find((a) => a.id === entry.id);
  if (!detected) return null;
  return { detected, canonical };
}

// REUSE-03 pre-runner check: read the detect cache + semver-check the catalog's
// compatibility_window against the detected version. Returns a ReuseHit on full
// match, null on any non-REUSE condition (absent agent, path-mismatch,
// version-out-of-window, missing cache, etc.).
export function tryReuse(entry: CatalogEntry): ReuseHit | null {
  if (!entry.compatibility_window) return null;
  const hit = readDetectedAgent(entry);
  if (!hit) return null;
  const { detected, canonical } = hit;
  if (detected.status !== "healthy") return null;
  if (!isCanonicalAgentPath(entry, detected.path, canonical)) return null;
  if (!semver.valid(detected.version)) return null;
  if (!semver.satisfies(detected.version, entry.compatibility_window)) return null;

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
    version: detected.version,
    detected_source: "pre-existing",
  };
}

// REMEDIATE-04 pre-runner check. Shares readDetectedAgent with tryReuse but
// applies the inverse discriminator: returns a RemediateHit when status=broken
// OR status=healthy with a non-canonical path (PATH-MISMATCH); null otherwise
// (cache absent, parse fails, greenfield, or REUSE territory). No
// compatibility_window check — REMEDIATE-04 reinstalls at pinned_version
// regardless of detected version, since the bad install is being replaced.
export function tryRemediate(entry: CatalogEntry): RemediateHit | null {
  const hit = readDetectedAgent(entry);
  if (!hit) return null;
  const { detected, canonical } = hit;
  if (detected.status === "broken") {
    return { reason: "broken", detected_path: detected.path, canonical_path: canonical };
  }
  if (detected.status === "healthy" && !isCanonicalAgentPath(entry, detected.path, canonical)) {
    return { reason: "path-mismatch", detected_path: detected.path, canonical_path: canonical };
  }
  return null;
}

// Presence overlay for `agentlinux list` (honest-status, AL-61). Reuses the same
// detect cache: an agent with no sentinel but reported healthy at its canonical
// presence is physically PRESENT (and adoptable), not "not-installed". Pure
// cache read — no host stat — so the status is host-independent in unit tests
// and matches exactly what `agentlinux adopt` / `install` would reuse. After a
// successful `--yes` install the installer adopts these into sentinels, so this
// overlay covers the window before adoption (and manual post-provision installs)
// while the detect cache is fresh.
export interface PresenceHit {
  version: string | null;
  path: string;
}

export function detectPresence(entry: CatalogEntry): PresenceHit | null {
  const hit = readDetectedAgent(entry);
  if (!hit) return null;
  const { detected, canonical } = hit;
  if (detected.status !== "healthy") return null;
  if (!isCanonicalAgentPath(entry, detected.path, canonical)) return null;
  return {
    version: semver.valid(detected.version) ? detected.version : null,
    path: detected.path,
  };
}
