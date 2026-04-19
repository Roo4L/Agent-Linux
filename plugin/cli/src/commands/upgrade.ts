// plugin/cli/src/commands/upgrade.ts — STUB.
// Implementation lands in Plan 04-04 (upgrade + classify wave).
// Pattern ref: 04-RESEARCH §Pattern 7 lines 830-862 — three-way classifier,
// sticky-skip unless --reset-all-curated, --all-latest via npm view.

export interface UpgradeOpts {
  resetAllCurated?: boolean;
  respectOverrides?: boolean;
  allLatest?: boolean;
  checkUpstream?: boolean;
  json?: boolean;
}

export async function upgradeCmd(_opts: UpgradeOpts): Promise<void> {
  throw new Error("upgradeCmd not yet implemented — lands in Plan 04-04");
}
