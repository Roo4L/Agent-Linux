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
