// plugin/cli/src/commands/pin.ts — CLI-07 sticky-override verb per ADR-011.
//
// `agentlinux pin <name>=<target>` is a STATE-ONLY mutation. It updates
// /opt/agentlinux/state/installed.d/<id>.json to record the user's intent
// about the existing install. It does NOT shell out to install.sh — the verb
// asserts something about what the existing bits mean, not a fresh install.
//
// Three target shapes:
//   - `<name>=curated`  → clears the sticky flag; the entry returns to
//                         following the catalog's curated pin on the next
//                         `upgrade`. Equivalent to "remove pin" (cf. Homebrew
//                         `brew unpin`, but recast as a positive verb).
//   - `<name>=latest`   → sticky=true + source='latest'. Upgrade --all-latest
//                         resolves the current upstream version AT UPGRADE
//                         TIME (RESEARCH Open Q4); between pin and next
//                         upgrade, sentinel.version lags behind upstream and
//                         `list` surfaces the divergence.
//   - `<name>=<semver>` → sticky=true + source='pinned' + version=<semver>.
//                         The entry is pinned at this specific version;
//                         upgrade never touches it unless --reset-all-curated.
//
// Error policy:
//   - Malformed spec (no '=', empty name, bogus target) → exit 64 (EX_USAGE).
//   - Unknown agent (not in catalog) → exit 64.
//   - Agent not installed (no sentinel) → exit 1 with clear "install first"
//     message. v0.3.0 does not support pre-declared intent on absent
//     sentinels; Phase 5+ may allow it but not this milestone.
//
// Threat model T-04-14 mitigation: parsePinSpec validates the target ∈
// {curated, latest, exact-semver} before any sentinel mutation; semver.valid
// is used (not regex) so malformed pins like '2.1' are rejected. The user
// string flows only into sentinel fields — no shell interpolation.

import semver from "semver";
import { loadCatalog } from "../catalog/loader.js";
import { detectPresence } from "../detect.js";
import { readSentinel, writeSentinel } from "../state/sentinel.js";
import type { Sentinel } from "../types.js";

export interface PinOpts {
  json?: boolean;
}

// Discriminated union — keeps call sites exhaustive via switch(parsed.target).
// 'version' carries the parsed semver string; 'curated' / 'latest' carry only
// the agent id since their version semantics are resolution-time concerns.
export type PinTarget =
  | { name: string; target: "curated" }
  | { name: string; target: "latest" }
  | { name: string; target: "version"; version: string };

export function parsePinSpec(spec: string): PinTarget {
  const eq = spec.indexOf("=");
  // eq <= 0 catches both 'no-equals' (eq === -1) and '=curated' (eq === 0,
  // empty name). Both need the usage help pointing at <name>=<target> form.
  if (eq <= 0) {
    throw new Error(
      `agentlinux pin: expected '<name>=<target>' (got '${spec}');\n  valid targets: curated, latest, or exact semver like 2.1.7`,
    );
  }
  const name = spec.slice(0, eq);
  const tgt = spec.slice(eq + 1);

  if (tgt === "curated") return { name, target: "curated" };
  if (tgt === "latest") return { name, target: "latest" };
  // semver.valid() accepts pre-releases (2.1.7-beta.1) and rejects partials
  // (2.1) + ranges (^2.1). That's the exact surface we want — pins are
  // version points, not ranges.
  if (semver.valid(tgt)) return { name, target: "version", version: tgt };

  throw new Error(
    `agentlinux pin: invalid target '${tgt}' in '${spec}';\n  valid targets: curated, latest, or exact semver (e.g. 2.1.7)`,
  );
}

export async function pinCmd(spec: string, _opts: PinOpts = {}): Promise<void> {
  let parsed: PinTarget;
  try {
    parsed = parsePinSpec(spec);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(msg);
    process.exit(64); // EX_USAGE — matches install/remove error shape
    return; // defensive: process.exit is mocked to throw in tests
  }

  // Catalog lookup — validate=true because pin is a mutation path (same
  // Open Q2 rule install/upgrade follow). Reject malformed catalogs up front
  // so a pin doesn't land against a stale/broken snapshot.
  const catalog = await loadCatalog({ validate: true });
  const entry = catalog.agents.find((a) => a.id === parsed.name);
  if (!entry) {
    const available = catalog.agents
      .filter((a) => !a.test_only)
      .map((a) => a.id)
      .join(", ");
    console.error(`agentlinux: no such agent in catalog: ${parsed.name}`);
    console.error(`  available: ${available}`);
    process.exit(64);
    return;
  }

  // Sentinel must exist — pin is intent-about-existing-install, not a
  // pre-declaration. Without an install, 'pinned to 2.1.7' would be a lie
  // since no bits at 2.1.7 are on disk.
  const existing = await readSentinel(entry.id);
  if (!existing) {
    // A tool the host already has (detected, no sentinel) is `present`, not
    // absent — so route it to the SAME verb `list` recommends, not a blanket
    // "install". Three cases, mirroring the list hints:
    //   - adoptable (managed path AND in-window) → `adopt` records the bits with
    //     no reinstall.
    //   - present but NOT adoptable → `install` brings it under management:
    //     reinstall at the pin for an out-of-window managed-path tool, or relocate
    //     a non-managed-path tool (migrate). Advising `adopt` in either case would
    //     dead-end, since adopt refuses both — the exact trap QA flagged.
    const present = detectPresence(entry);
    if (present?.adoptable) {
      console.error(
        `agentlinux: ${entry.id} is present but not managed — run 'agentlinux adopt ${entry.id}' first, then pin`,
      );
    } else if (present?.canonical) {
      console.error(
        `agentlinux: ${entry.id} is present but out of the compatibility window — run 'agentlinux install ${entry.id}' to bring it under management, then pin`,
      );
    } else if (present) {
      console.error(
        `agentlinux: ${entry.id} is present at ${present.path} (not the managed path) — run 'agentlinux install ${entry.id}' to migrate it under management, then pin`,
      );
    } else {
      console.error(
        `agentlinux: ${entry.id} is not installed — run 'agentlinux install ${entry.id}' first`,
      );
    }
    process.exit(1);
    return;
  }

  // Compute next sentinel state. Spread over existing to preserve id +
  // installed_at (pin is a partial update — we only touch source/sticky/version).
  let next: Sentinel;
  switch (parsed.target) {
    case "curated":
      // Clear the override. Version stays at whatever is currently installed;
      // the next `upgrade` will classify and reconcile if divergent.
      next = { ...existing, source: "curated", sticky: false };
      console.log(`${entry.id}: pin cleared (source=curated, sticky=false)`);
      break;
    case "latest":
      // Record intent; version preserved until next `upgrade --all-latest`
      // resolves upstream (RESEARCH Open Q4).
      next = { ...existing, source: "latest", sticky: true };
      console.log(
        `${entry.id}: pinned to follow upstream latest (sticky=true); next 'upgrade --all-latest' resolves`,
      );
      break;
    case "version":
      // Exact-version pin. Record the user-asserted version on the sentinel.
      // Note: this does NOT re-install — the user is asserting the currently
      // installed bits ARE at parsed.version. If they lied, upgrade --list
      // will surface the drift on the next call.
      next = { ...existing, source: "pinned", sticky: true, version: parsed.version };
      console.log(`${entry.id}: pinned to ${parsed.version} (sticky=true)`);
      break;
  }

  await writeSentinel(next);
}
