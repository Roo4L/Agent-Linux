// SPDX-License-Identifier: MIT
// plugin/cli/src/types.ts — shared interfaces for the registry CLI.
// Single source of truth consumed by src/commands/*, src/state/*, src/version/*,
// src/catalog/*, and every test fixture.
// Contracts:
//   - CatalogEntry mirrors plugin/catalog/schema.json $defs/agent (ADR-011).
//   - Sentinel mirrors /opt/agentlinux/state/installed.d/<id>.json shape.
//   - Status enumerates the six divergence states in 04-RESEARCH §Pattern 6.
// Downstream plans 04-03/04/05 import from here without further exploration.

export interface CatalogEntry {
  id: string;
  display_name: string;
  description: string;
  homepage?: string;
  license?: string;
  source_kind: "npm" | "script";
  npm_package_name?: string; // required when source_kind === 'npm' (allOf clause)
  pinned_version: string; // exact semver — CAT-04 / ADR-011
  version_constraint?: string; // e.g. '^2.1' — --all-latest upper-bound
  install_recipe_path: string; // e.g. 'install.sh'
  uninstall_recipe_path: string; // e.g. 'uninstall.sh'
  post_install_verify?: string;
  tags?: string[];
  test_only?: boolean; // hide from default `list`; exercised by bats (CAT-02 test-dummy)
}

export interface Catalog {
  version: string;
  agents: CatalogEntry[];
  catalogDir: string; // absolute path resolved by loader.ts
}

export interface Sentinel {
  id: string;
  version: string;
  source: "curated" | "override" | "latest" | "pinned";
  sticky: boolean;
  installed_at: string; // ISO-8601
}

export interface VersionDecision {
  version: string;
  source: Sentinel["source"];
  sticky: boolean;
}

export type Status =
  | "not-installed"
  | "synced"
  | "override-ahead"
  | "override-behind"
  | "pinned-override"
  | "drift-undeclared";

// DivergenceReport — added in Plan 04-04 for `agentlinux upgrade`.
// Extends the Plan 04-01 Status classifier with the four inputs (sentinel,
// catalog pin, installed, optional upstream latest) reified into a single
// per-agent record. Rendered as a table row OR emitted as JSON.
//
// Fields are null-vs-string rather than "-" placeholders — presentation
// concerns live in the command layer (upgrade.ts / list.ts), not the data
// type. `source: 'none'` is the sentinel-less fallback; lifts the Sentinel
// 'source' enum to a narrowed string literal so the command layer can switch
// on it exhaustively without nullable handling.
export interface DivergenceReport {
  id: string;
  status: Status;
  sentinelVersion: string | null; // null if not installed
  installedVersion: string | null; // from npm ls / native probe
  curatedVersion: string; // entry.pinned_version
  latestVersion: string | null; // only populated when --check-upstream / --all-latest
  source: Sentinel["source"] | "none";
  sticky: boolean;
}
