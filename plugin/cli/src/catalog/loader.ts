// plugin/cli/src/catalog/loader.ts — reads catalog.json + resolves recipe paths.
//   - AGENTLINUX_CATALOG_DIR env override → test seam + production override
//   - Defaults to /opt/agentlinux/catalog/<AGENTLINUX_VERSION>
//   - validate:true (default) runs ajv; hot-path `list` uses validate:false.
//
// CAT-04: when an entry carries preserve_paths_file, the loader reads the
// sibling JSON, normalizes the listed home-relative paths, and exposes them as
// `entry.preserve_paths` (the runner injects them into AGENTLINUX_PRESERVE_PATHS
// so uninstall.sh can skip user-data dirs during REMEDIATE-04 reinstall).

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

// normalizePreservePath — strip leading `~/`, normalize, reject `..` traversal
// and absolute paths. Returns the home-relative-normalized form. Throws on any
// malformed entry: a silently-dropped preserve path would delete user data on
// REMEDIATE-04, so the catalog must fail fast.
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
  // Strip leading `~/`, drop trailing slash (uniform shape).
  const stripped = raw.slice(2).replace(/\/+$/, "");
  if (stripped.length === 0) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${agentId}' entry [${idx}]: empty after stripping '~/' (got: ${raw})`,
    );
  }
  // Reject path traversal: normalize collapses `a/../b` to `b`, so check the
  // normalized form for any `..` component or absolute-path leak.
  const normalized = normalize(stripped);
  if (normalized.startsWith("/")) {
    throw new Error(
      `agentlinux: preserve_paths.json for '${agentId}' entry [${idx}]: absolute paths forbidden (got: ${raw}; normalized: ${normalized})`,
    );
  }
  // Reject any `..` segment — a malicious catalog could otherwise escape ~/.
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

  // Hydrate preserve_paths sibling files. Sequential await keeps error
  // reporting deterministic (agent-ordered, not first-failing-promise race).
  for (const entry of raw.agents) {
    const preserved = await loadPreservePaths(catalogDir, entry);
    if (preserved !== undefined) {
      entry.preserve_paths = preserved;
    }
  }

  return { ...raw, catalogDir };
}
