// plugin/cli/src/commands/pin.ts — STUB.
// Implementation lands in Plan 04-05 (pin + sticky-override wave — CLI-07).
// Parses `<name>=curated|latest|x.y.z`; mutates the sentinel's sticky + version.

export interface PinOpts {
  json?: boolean;
}

export async function pinCmd(_spec: string, _opts: PinOpts): Promise<void> {
  throw new Error("pinCmd not yet implemented — lands in Plan 04-05");
}
