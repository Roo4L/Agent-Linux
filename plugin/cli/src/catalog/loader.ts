// plugin/cli/src/catalog/loader.ts — reads catalog.json + resolves recipe paths.
// Contracts:
//   - AGENTLINUX_CATALOG_DIR env override → test seam + production override
//   - Defaults to /opt/agentlinux/catalog/<AGENTLINUX_VERSION> (provisioner 50)
//   - validate:true (default) runs ajv and throws a formatted Error on reject;
//     hot-path `list` uses validate:false per 04-RESEARCH Open Question 2.
//
// Plan 14-03 (REMEDIATE-04 CAT-04): when an agent entry carries
// preserve_paths_file (e.g. "preserve_paths.json"), the loader reads the
// sibling JSON from <catalogDir>/agents/<id>/<file>, parses + normalizes the
// listed home-relative paths, and exposes them as `entry.preserve_paths`. The
// runner.ts dispatcher then joins them with ':' and injects
// AGENTLINUX_PRESERVE_PATHS into uninstall.sh's env so its _should_remove
// helper can skip user-data dirs during REMEDIATE-04 reinstall.
//
// T-14-04 mitigation (preserve_paths.json path traversal): each entry MUST
// start with `~/` (home-relative). The loader strips the leading `~/`,
// normalizes the remainder, and REJECTS any path that contains a `..`
// component or that resolves to an absolute path. Verified by unit test with
// a `~/../../etc` fixture.

import { readFile } from "node:fs/promises";
import { join, normalize } from "node:path";
import type { Catalog, CatalogEntry } from "../types.js";
import { VERSION } from "../version.js";
import { formatErrors, getValidator } from "./schema.js";

function defaultCatalogDir(): string {
  const ver = process.env.AGENTLINUX_VERSION ?? VERSION;
  return `/opt/agentlinux/catalog/${ver}`;
}

interface PreservePathsFile {
  preserve_paths: string[];
  comment?: string;
}

// normalizePreservePath — strip leading `~/`, normalize the remainder, reject
// `..` traversal and absolute paths (T-14-04 mitigation). Returns the
// home-relative-normalized form (e.g. ".claude" or ".config/get-shit-done")
// suitable for joining with AGENTLINUX_AGENT_HOME inside uninstall.sh's
// _should_remove helper. Throws on any malformed entry — the catalog must
// fail fast rather than silently dropping a preserved path (which would
// cause user data to be deleted on REMEDIATE-04).
function normalizePreservePath(raw: string, agentId: string, idx: number): string {
  if (typeof raw !== "string" || raw.length === 0) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${agentId}' entry [${idx}]: must be a non-empty string (got ${typeof raw})`,
    );
  }
  if (!raw.startsWith("~/")) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${agentId}' entry [${idx}]: must start with '~/' (got: ${raw})`,
    );
  }
  // Strip leading `~/`, drop trailing slash (uniform shape: no trailing /).
  const stripped = raw.slice(2).replace(/\/+$/, "");
  if (stripped.length === 0) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${agentId}' entry [${idx}]: empty after stripping '~/' (got: ${raw})`,
    );
  }
  // T-14-04: reject path traversal. `path.normalize` collapses `a/../b` to `b`
  // and `../etc` to `../etc` — so we check the NORMALIZED form for any `..`
  // component or absolute-path leak.
  const normalized = normalize(stripped);
  if (normalized.startsWith("/")) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${agentId}' entry [${idx}]: absolute paths forbidden (got: ${raw}; normalized: ${normalized})`,
    );
  }
  // Reject `..` as a standalone segment OR a leading `..` after normalization
  // (the latter signals traversal that escaped the home dir). Bash `cd a/../b`
  // semantics would otherwise let a malicious catalog escape ~/.
  const segments = normalized.split("/");
  if (segments.some((s) => s === "..")) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${agentId}' entry [${idx}]: '..' traversal forbidden (got: ${raw}; normalized: ${normalized})`,
    );
  }
  return normalized;
}

async function loadPreservePaths(
  catalogDir: string,
  entry: CatalogEntry,
): Promise<string[] | undefined> {
  if (!entry.preserve_paths_file) return undefined;
  const filePath = join(catalogDir, "agents", entry.id, entry.preserve_paths_file);
  let body: string;
  try {
    body = await readFile(filePath, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      throw new Error(
        `agentlinux: preserve_paths_file '${entry.preserve_paths_file}' for agent '${entry.id}' not found at ${filePath}`,
      );
    }
    throw err;
  }
  let parsed: PreservePathsFile;
  try {
    parsed = JSON.parse(body);
  } catch (err) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${entry.id}' is not valid JSON: ${(err as Error).message}`,
    );
  }
  if (!Array.isArray(parsed.preserve_paths)) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${entry.id}' missing required 'preserve_paths' array`,
    );
  }
  return parsed.preserve_paths.map((p, i) => normalizePreservePath(p, entry.id, i));
}

export async function loadCatalog(opts: { validate?: boolean } = {}): Promise<Catalog> {
  const catalogDir = process.env.AGENTLINUX_CATALOG_DIR ?? defaultCatalogDir();
  const catalogPath = join(catalogDir, "catalog.json");
  const raw = JSON.parse(await readFile(catalogPath, "utf8")) as Omit<Catalog, "catalogDir">;

  if (opts.validate ?? true) {
    const validator = await getValidator();
    if (!validator(raw)) {
      throw new Error(`Catalog validation failed:\n${formatErrors(validator.errors)}`);
    }
  }

  // Plan 14-03: hydrate preserve_paths sibling files (T-14-04 traversal
  // rejection happens inside normalizePreservePath). Sequential await keeps
  // the error reporting deterministic — agent-ordered failure message rather
  // than the first-failing-promise race.
  for (const entry of raw.agents) {
    const preserved = await loadPreservePaths(catalogDir, entry);
    if (preserved !== undefined) {
      entry.preserve_paths = preserved;
    }
  }

  return { ...raw, catalogDir };
}
