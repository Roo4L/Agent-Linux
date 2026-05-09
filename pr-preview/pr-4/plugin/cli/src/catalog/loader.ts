// plugin/cli/src/catalog/loader.ts — reads catalog.json + resolves recipe paths.
// Contracts:
//   - AGENTLINUX_CATALOG_DIR env override → test seam + production override
//   - Defaults to /opt/agentlinux/catalog/<AGENTLINUX_VERSION> (provisioner 50)
//   - validate:true (default) runs ajv and throws a formatted Error on reject;
//     hot-path `list` uses validate:false per 04-RESEARCH Open Question 2.

import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Catalog } from "../types.js";
import { formatErrors, getValidator } from "./schema.js";

function defaultCatalogDir(): string {
  const ver = process.env.AGENTLINUX_VERSION ?? "0.3.0";
  return `/opt/agentlinux/catalog/${ver}`;
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
  return { ...raw, catalogDir };
}
