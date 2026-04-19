// plugin/cli/src/commands/remove.ts — STUB.
// Implementation lands in Plan 04-03 (list + install + remove wave).
// Pattern ref: 04-RESEARCH §Pattern 4 lines 631-667.
// Symmetric inverse of install: asUser dispatch uninstall.sh → deleteSentinel.
// --force makes missing-sentinel a no-op (idempotent remove).

export interface RemoveOpts {
  force?: boolean;
}

export async function removeCmd(_name: string, _opts: RemoveOpts): Promise<void> {
  throw new Error("removeCmd not yet implemented — lands in Plan 04-03");
}
