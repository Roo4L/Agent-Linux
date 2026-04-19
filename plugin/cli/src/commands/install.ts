// plugin/cli/src/commands/install.ts — STUB.
// Implementation lands in Plan 04-03 (list + install + remove wave).
// Pattern ref: 04-RESEARCH §Pattern 3 lines 555-628.
// Happy path: loadCatalog → decideVersion → asUser dispatch install.sh →
// writeSentinel. --version and --force flags supported.

export interface InstallOpts {
  force?: boolean;
  version?: string;
  json?: boolean;
}

export async function installCmd(_name: string, _opts: InstallOpts): Promise<void> {
  throw new Error("installCmd not yet implemented — lands in Plan 04-03");
}
