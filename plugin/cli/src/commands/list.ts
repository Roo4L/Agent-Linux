// plugin/cli/src/commands/list.ts — STUB.
// Implementation lands in Plan 04-03 (list + install + remove wave).
// Reads catalog (validate:false per 04-RESEARCH Open Question 2 for hot-path
// perf) + all sentinels under installed.d/; formats text/JSON table.

export interface ListOpts {
  json?: boolean;
  includeTest?: boolean;
}

export async function listCmd(_opts: ListOpts): Promise<void> {
  throw new Error("listCmd not yet implemented — lands in Plan 04-03");
}
