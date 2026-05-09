// plugin/cli/src/upgrade/divergence.ts — pure-function upgrade classifier.
// Pattern ref: 04-RESEARCH §Pattern 6 lines 772-827 (six-state classify) +
// §Pattern 7 lines 830-864 (resolveLatestFor + semver.maxSatisfying).
//
// Two exports, both pure functions (no I/O, no side effects, deterministic):
//
//   computeDivergence({entry, sentinel, installed, latest?})
//     Reifies the Plan 04-01 classify() result plus the four version columns
//     (sentinel, installed, curated, optional upstream latest) into a single
//     DivergenceReport record. The upgrade command layer renders this as a
//     table row or emits it as JSON.
//
//   resolveLatestFor(entry, publishedVersions)
//     Given the npm-view versions array, picks the highest semver that
//     satisfies entry.version_constraint. Throws with an explicit message
//     when the constraint matches zero versions (T-04-13 mitigation — catches
//     typos like `^9.0` against a 1.x package before --all-latest reinstalls
//     the wrong version).
//
// Purity rationale: both functions are trivially unit-testable without
// mocking subprocess / filesystem. The impure shell adapter lives in
// sibling npm_ls.ts so divergence.ts stays a leaf module with no state.

import semver from "semver";
import type { CatalogEntry, DivergenceReport, Sentinel } from "../types.js";
import { classify } from "../version/classify.js";

export interface ComputeDivergenceInput {
  entry: CatalogEntry;
  sentinel: Sentinel | null;
  installed: string | null;
  latest?: string | null;
}

export function computeDivergence(input: ComputeDivergenceInput): DivergenceReport {
  const { entry, sentinel, installed, latest = null } = input;
  const status = classify({ entry, sentinel, installed });
  return {
    id: entry.id,
    status,
    sentinelVersion: sentinel?.version ?? null,
    installedVersion: installed,
    curatedVersion: entry.pinned_version,
    latestVersion: latest,
    source: sentinel?.source ?? "none",
    sticky: sentinel?.sticky ?? false,
  };
}

/**
 * Resolve the highest published version satisfying entry.version_constraint.
 *
 * Absent constraint → newest stable version via semver.maxSatisfying('*').
 * Present constraint → semver.maxSatisfying(versions, constraint).
 * Zero matches → throw with a descriptive Error (T-04-13 mitigation).
 * Empty input list → throw (defensive — npm view should never return [] for
 *   a real package, but guard against a misbehaving registry).
 */
export function resolveLatestFor(entry: CatalogEntry, publishedVersions: string[]): string {
  if (publishedVersions.length === 0) {
    throw new Error(`${entry.id}: no published versions found`);
  }
  const range = entry.version_constraint ?? "*";
  const max = semver.maxSatisfying(publishedVersions, range);
  if (!max) {
    const pkgLabel = entry.npm_package_name ?? entry.id;
    throw new Error(
      `${entry.id}: no published version of ${pkgLabel} satisfies constraint ${entry.version_constraint}`,
    );
  }
  return max;
}
