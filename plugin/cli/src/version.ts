// SPDX-License-Identifier: MIT
// plugin/cli/src/version.ts — single source-of-truth for the AgentLinux release
// version, read once at module load from plugin/cli/package.json.
//
// AL-29 motivation: prior to this module the "version" string was duplicated
// across 8 sites (plugin/bin/agentlinux-install constant, three TS defaults,
// four bats test files). Bumping the release required mechanical edits in
// every site and one of those — the bash AGENTLINUX_VERSION constant —
// silently broke CAT-05 in v0.3.2-rc1 because the bats test reads the
// expected version from package.json dynamically, but the installer staged
// the catalog under the (still-0.3.0) hardcoded constant. This module
// terminates that sprawl: TS callers import VERSION; the bash entrypoint
// sed-extracts from the same package.json at install time.
//
// Layout:
//   - Production:  /opt/agentlinux/cli/<ver>/dist/index.js → ../package.json
//   - Production:  /opt/agentlinux/cli/<ver>/dist/catalog/loader.js → ../../package.json
//   - Test build:  dist-test/src/catalog/loader.js → ../../../package.json
//
// The walk-up loop accepts both layouts (and a generous spare depth for
// future dev tooling) without per-build path arithmetic. Mirrors the same
// pattern used in catalog/schema.ts §resolveSchemaPath for schema.json.

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function findPkgVersion(): string {
  let dir = dirname(fileURLToPath(import.meta.url));
  for (let depth = 0; depth < 6; depth++) {
    try {
      const text = readFileSync(resolve(dir, "package.json"), "utf8");
      const pkg = JSON.parse(text) as { version?: string };
      if (typeof pkg.version === "string" && pkg.version.length > 0) {
        return pkg.version;
      }
    } catch {
      // keep walking — package.json not present at this depth, or unreadable
    }
    dir = resolve(dir, "..");
  }
  throw new Error(
    `agentlinux: could not locate package.json within 6 levels of ${import.meta.url}`,
  );
}

export const VERSION = findPkgVersion();
