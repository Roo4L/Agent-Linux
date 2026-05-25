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
  compatibility_window?: string; // Phase 13 (REUSE-03): semver range — pre-existing install adopted via REUSE-03 when version satisfies this
  install_recipe_path: string; // e.g. 'install.sh'
  uninstall_recipe_path: string; // e.g. 'uninstall.sh'
  post_install_verify?: string;
  // Plan 14-03 (REMEDIATE-04 CAT-04): optional sibling-file pointer (relative
  // to the agent's catalog dir, e.g. 'preserve_paths.json'). When set, the
  // loader reads + normalizes the listed home-relative paths and exposes them
  // as `preserve_paths`. The runner.ts dispatcher joins them with ':' and
  // injects AGENTLINUX_PRESERVE_PATHS into install.sh + uninstall.sh env so
  // catalog uninstall.sh's _should_remove helper can skip user-data dirs
  // during REMEDIATE-04 reinstall.
  preserve_paths_file?: string;
  preserve_paths?: string[]; // normalized list — empty/undefined when no file
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
  // Phase 13 (REUSE-03): when AgentLinux ADOPTED a pre-existing healthy
  // install rather than running install.sh. Optional + defaults-to-"installed"
  // for backwards-compat with Phase 4-shipped sentinels (which have no status
  // field; readSentinel treats missing as "installed").
  //
  // Plan 14-03 (REMEDIATE-04): widened to include "broken-after-remediate" —
  // the terminal state reached when uninstall.sh succeeded but the follow-up
  // install.sh failed. list.ts renders this with the
  // ` (broken — half-uninstalled, manual recovery needed)` suffix; user must
  // intervene manually (`agentlinux remove <id>` to clean up the sentinel,
  // then a fresh `agentlinux install <id>`).
  status?: "installed" | "reused" | "broken-after-remediate";
  binary_path?: string; // canonical-path-matched binary; only set when status="reused"
  detected_source?: string; // e.g., "pre-existing"; only set when status="reused"
  reused_at?: string; // ISO-8601; only set when status="reused"
  compatibility_window_at_reuse?: string; // semver range at adoption time (audit trail); only set when status="reused"
  // Plan 14-03 (REMEDIATE-04): ISO-8601 timestamp of the most recent
  // remediation attempt. Set on BOTH the success path (status="installed",
  // record-keeping) and the half-uninstalled failure path
  // (status="broken-after-remediate", forensic trail).
  remediated_at?: string;
  // Plan 14-03 (REMEDIATE-04): short token explaining why remediation landed
  // in the broken-after-remediate state. Currently the only value is
  // "install-failed-post-uninstall"; future Remediate paths may add more.
  remediate_failure_reason?: string;
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
