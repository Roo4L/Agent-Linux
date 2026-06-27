// SPDX-License-Identifier: MIT
// plugin/cli/src/types.ts — shared interfaces for the registry CLI.
//   - CatalogEntry mirrors plugin/catalog/schema.json $defs/agent (ADR-011).
//   - Sentinel mirrors /opt/agentlinux/state/installed.d/<id>.json shape.
//   - Status enumerates the six divergence states.

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
  compatibility_window?: string; // REUSE-03 semver range: adopt a detected install whose version satisfies this
  install_recipe_path: string; // e.g. 'install.sh'
  uninstall_recipe_path: string; // e.g. 'uninstall.sh'
  post_install_verify?: string;
  // CAT-04: optional sibling-file pointer (e.g. 'preserve_paths.json'). When
  // set, the loader normalizes the listed paths into `preserve_paths`, which
  // the runner injects as AGENTLINUX_PRESERVE_PATHS for uninstall.sh.
  preserve_paths_file?: string;
  preserve_paths?: string[]; // normalized list — empty/undefined when no file
  tags?: string[];
  test_only?: boolean; // hide from default `list` (CAT-02)
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
  // Install-record status. Defaults to "installed" when absent (Phase 4
  // sentinels had no status field). Other states:
  //   - "reused"                 — REUSE-03 adopted a pre-existing healthy install
  //   - "broken-after-remediate" — uninstall.sh succeeded but install.sh failed;
  //                                needs manual recovery (remove + reinstall)
  //   - "reused-with-warning"    — operator declined a REMEDIATE; component left
  //                                as-is, `decline_reason` records the choice.
  //                                upgrade.ts treats it like "reused".
  status?: "installed" | "reused" | "broken-after-remediate" | "reused-with-warning";
  // Which remediation the operator declined; set only when
  // status="reused-with-warning". Tokens mirror plugin/lib/prompt.sh and name
  // the fix to apply manually:
  //   chown-declined            — REMEDIATE-01 npm-prefix chown/rebase
  //   sudoers-drift-declined    — REMEDIATE-03 sudoers drift overwrite
  //   reinstall-broken-declined — REMEDIATE-04 catalog-agent uninstall+reinstall
  decline_reason?: "chown-declined" | "sudoers-drift-declined" | "reinstall-broken-declined";
  binary_path?: string; // canonical-path-matched binary; only set when status="reused"
  detected_source?: string; // e.g., "pre-existing"; only set when status="reused"
  reused_at?: string; // ISO-8601; only set when status="reused"
  compatibility_window_at_reuse?: string; // semver range at adoption (audit trail); only set when status="reused"
  // ISO-8601 of the most recent remediation attempt; set on both the success
  // path and the broken-after-remediate failure path.
  remediated_at?: string;
  // Why remediation landed in broken-after-remediate (currently only
  // "install-failed-post-uninstall").
  remediate_failure_reason?: string;
}

export interface VersionDecision {
  version: string;
  source: Sentinel["source"];
  sticky: boolean;
}

export type Status =
  | "not-installed"
  // AL-61: physically present at its canonical presence but not adopted into a
  // sentinel — `list` overlays this over "not-installed" so a tool the host
  // already has is never reported as absent. Run `agentlinux install <id>` (or
  // `adopt`) to manage it.
  | "present"
  | "synced"
  | "override-ahead"
  | "override-behind"
  | "pinned-override"
  | "drift-undeclared";

// DivergenceReport — per-agent record for `agentlinux upgrade`, reifying the
// four inputs (sentinel, catalog pin, installed, optional upstream latest)
// behind the Status classifier. Fields are null-vs-string (the command layer
// handles presentation); `source: 'none'` is the sentinel-less fallback.
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
