// plugin/cli/src/version/classify.ts — pure-function divergence classifier.
// Pattern ref: 04-RESEARCH §Pattern 6 (lines 776-827).
// No I/O; no side effects; trivially unit-testable.
// Six-state Status is the authoritative contract consumed by list + upgrade.

import semver from "semver";
import type { CatalogEntry, Sentinel, Status, VersionDecision } from "../types.js";

export interface ClassifyInput {
  entry: CatalogEntry;
  sentinel: Sentinel | null;
  installed: string | null; // `npm ls -g --json` version OR native `<bin> --version`
}

export function classify({ entry, sentinel, installed }: ClassifyInput): Status {
  if (!sentinel || !installed) return "not-installed";

  // drift-undeclared: someone ran `claude update` or `npm install -g` outside
  // our CLI. Sentinel disagrees with what's actually on disk.
  if (!semver.eq(sentinel.version, installed)) return "drift-undeclared";

  if (semver.eq(installed, entry.pinned_version)) return "synced";

  if (sentinel.sticky) return "pinned-override";

  return semver.gt(installed, entry.pinned_version) ? "override-ahead" : "override-behind";
}

// decideVersion: which version does the CLI ask the recipe to install?
// Used by install + upgrade. Returns {version, source, sticky}.
//   - versionOverride (--version flag) always wins → source='override', sticky=false
//   - sticky sentinel preserved → source inherits, sticky=true
//   - otherwise default to catalog pin → source='curated', sticky=false
export function decideVersion(
  entry: CatalogEntry,
  versionOverride: string | undefined,
  existingSentinel: Sentinel | null,
): VersionDecision {
  if (versionOverride) {
    return { version: versionOverride, source: "override", sticky: false };
  }
  if (existingSentinel?.sticky) {
    return {
      version: existingSentinel.version,
      source: existingSentinel.source,
      sticky: true,
    };
  }
  return { version: entry.pinned_version, source: "curated", sticky: false };
}
