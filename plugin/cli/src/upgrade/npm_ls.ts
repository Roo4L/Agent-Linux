// plugin/cli/src/upgrade/npm_ls.ts — shell adapter around `npm ls -g --json`
// and `npm view <pkg> versions --json`.
//
// Pattern ref: 04-RESEARCH §Pattern 7 (queryNpmViewLatest excerpt, lines
// 830-864) + §Pitfall 4 (npm ls defensive parse, lines 1201-1215).
//
// T-04-11 mitigation: asUser dispatches as an ARRAY argv via execFile —
// catalog-entry `npm_package_name` never reaches a shell; the ajv schema also
// pattern-validates the field at catalog load time, so even the array-arg
// injection surface is narrowed (no spaces, no $, no backticks).
//
// T-04-12 mitigation: queryNpmViewLatest is only called when the user opts in
// via --check-upstream or --all-latest in upgrade.ts; a 30-second timeout
// prevents a hung registry from stalling the CLI indefinitely.
//
// Pitfall 4 mitigation: `npm ls -g --json` exits 1 when it has peer-dep
// warnings but STILL emits valid JSON on stdout. We intentionally parse the
// stdout regardless of exit code and only fail when the JSON itself is
// unparseable (genuine npm misbehavior, not a warning).
//
// Testability: both exported functions accept an optional dispatcher matching
// the asUser signature. Unit tests inject a capturing/stubbing function so no
// sudo invocation ever happens under `pnpm test`.

import { resolveInstallUser } from "../runner.js";
import { asUser } from "../state/dispatcher.js";
import type { CatalogEntry } from "../types.js";
import { resolveLatestFor } from "./divergence.js";

// Build the minimal npm env for the configured install user (AL-50 AC4 /
// AL-59). Mirrors runner.ts's per-user derivation so `npm` resolves to the
// user's ~/.npm-global/bin (Pitfall 5 — sudo -E alone drops PATH to secure_path
// on Ubuntu). For the default user `agent` this is byte-identical to the old
// hardcoded /home/agent env and to the AGENT_PATH constant in runner.ts.
function npmEnvFor(home: string): Record<string, string> {
  return {
    PATH: `${home}/.npm-global/bin:${home}/.local/bin:/usr/local/bin:/usr/bin:/bin`,
    HOME: home,
    NPM_CONFIG_PREFIX: `${home}/.npm-global`,
    LANG: "C.UTF-8",
    LC_ALL: "C.UTF-8",
  };
}

// Dispatcher signature — mirrors state/dispatcher.ts asUser exactly.
// Typed separately here so unit tests can pass a stub without pulling the real
// asUser into the test module graph (which would try to resolve /usr/bin/sudo
// at load time on CI hosts that may not have sudo).
export type NpmDispatcher = (
  user: string,
  argv: string[],
  opts: { env: Record<string, string>; timeout?: number },
) => Promise<{ exitCode: number; stdout: string; stderr: string }>;

interface NpmLsShape {
  dependencies?: Record<string, { version?: string; overridden?: boolean }>;
}

/**
 * Run `sudo -u <install-user> -H -E -- npm ls -g --json --depth=0` and return a
 * Map<pkgName, version> of the configured install user's globally-installed npm
 * packages. The user is resolved via resolveInstallUser() (AL-50 AC4 / AL-59) so
 * `agentlinux upgrade` probes the right home on a `--user=NAME` host instead of
 * a hardcoded `agent` that may not exist.
 *
 * Defensive parsing per Pitfall 4:
 *   (a) missing `dependencies` key (no globals installed) → empty map
 *   (b) missing `version` field on a key → skip that entry
 *   (c) exit 1 with valid JSON (peer-dep warning) → parse anyway
 *   (d) unparseable stdout → throw with stderr context
 */
export async function queryGlobalNpm(
  dispatcher: NpmDispatcher = asUser,
): Promise<Map<string, string>> {
  const user = resolveInstallUser();
  const result = await dispatcher(user, ["npm", "ls", "-g", "--json", "--depth=0"], {
    env: npmEnvFor(`/home/${user}`),
    timeout: 30_000,
  });

  let parsed: NpmLsShape;
  try {
    parsed = JSON.parse(result.stdout) as NpmLsShape;
  } catch {
    throw new Error(
      `npm ls -g --json did not emit parseable JSON (exit ${result.exitCode})\nstderr: ${result.stderr}`,
    );
  }

  const map = new Map<string, string>();
  for (const [pkg, info] of Object.entries(parsed.dependencies ?? {})) {
    if (info?.version) map.set(pkg, info.version);
  }
  return map;
}

/**
 * Resolve the upstream-latest version for a catalog entry via
 * `npm view <pkg> versions --json`. Honors entry.version_constraint via
 * resolveLatestFor. Only called when the user opts in through
 * --check-upstream or --all-latest (offline-default per ADR-011 / T-04-12).
 *
 * Returns null for non-npm entries (source_kind !== 'npm'). Script-backed
 * agents like Claude Code's native installer don't have a single canonical
 * "latest" derivable from npm; the upgrade flow surfaces this as a
 * `latestVersion: null` column in the report.
 */
export async function queryNpmViewLatest(
  entry: CatalogEntry,
  dispatcher: NpmDispatcher = asUser,
): Promise<string | null> {
  if (entry.source_kind !== "npm" || !entry.npm_package_name) {
    return null;
  }
  const user = resolveInstallUser();
  const result = await dispatcher(
    user,
    ["npm", "view", entry.npm_package_name, "versions", "--json"],
    { env: npmEnvFor(`/home/${user}`), timeout: 30_000 },
  );
  if (result.exitCode !== 0) {
    throw new Error(
      `npm view ${entry.npm_package_name} failed (exit ${result.exitCode}): ${result.stderr}`,
    );
  }
  // `npm view <pkg> versions --json` returns either a JSON array of strings
  // (when >1 published) OR a single string (when only 1 published). Handle
  // both to stay faithful to the npm CLI contract.
  let versions: string[];
  try {
    const raw = JSON.parse(result.stdout);
    versions = Array.isArray(raw) ? raw : [String(raw)];
  } catch {
    throw new Error(
      `npm view ${entry.npm_package_name} returned unparseable JSON:\n${result.stdout}`,
    );
  }
  return resolveLatestFor(entry, versions);
}
