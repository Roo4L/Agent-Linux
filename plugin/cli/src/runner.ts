// SPDX-License-Identifier: MIT
// plugin/cli/src/runner.ts — shared recipe dispatcher for install/remove/upgrade.
// Mirrors /etc/agentlinux.env (40-path-wiring.sh) byte-for-byte so recipes
// inherit the same PATH/locale from provisioner or CLI — a drift would let
// recipes resolve npm from /usr/bin and break the no-EACCES contract.
//
// DI seam: the second parameter is the asUser impl (defaults to the real one);
// unit tests inject a capturing mock. DI over module-mocking because
// `mock.module` is undefined on the Node 20 executor host.

import { readFileSync } from "node:fs";
import { asUser } from "./state/dispatcher.js";
import type { CatalogEntry } from "./types.js";

// POSIX-portable username charset — MUST mirror remediate::validate_user_name's
// `^[a-z][a-z0-9_-]*$` (plugin/lib/remediate.sh). Used as belt-and-suspenders
// re-validation when reading the configured install user (the file is
// root-owned and the installer already validated the name, but a malformed
// read must never flow into a `sudo -u` argument).
const INSTALL_USER_RE = /^[a-z][a-z0-9_-]*$/;
const DEFAULT_INSTALL_USER = "agent";
const AGENTLINUX_ENV_FILE = "/etc/agentlinux.env";

// resolveInstallUser — the install user catalog ops run as (AL-50 AC4). Source
// precedence: process.env.AGENTLINUX_USER > the AGENTLINUX_USER= line in
// /etc/agentlinux.env (root-owned, written by 40-path-wiring.sh) > `agent`. A
// value that fails the POSIX charset (malformed env / tampered read) falls back
// to `agent` — defense-in-depth for BOTH the guard check and the dispatch user
// (T-AL50-06).
export function resolveInstallUser(): string {
  let raw = process.env.AGENTLINUX_USER;
  if (raw === undefined || raw === "") {
    try {
      const txt = readFileSync(AGENTLINUX_ENV_FILE, "utf8");
      const m = txt.match(/^AGENTLINUX_USER=(.*)$/m);
      if (m) raw = m[1].trim();
    } catch {
      // Absent/unreadable env file (dev host, pre-AL-50 install) → default.
    }
  }
  if (raw !== undefined && INSTALL_USER_RE.test(raw)) return raw;
  return DEFAULT_INSTALL_USER;
}

export interface RecipeEnv {
  AGENTLINUX_PINNED_VERSION: string;
  AGENTLINUX_CATALOG_DIR: string;
  AGENTLINUX_AGENT_HOME: string;
  AGENTLINUX_SOURCE_KIND: string;
  AGENTLINUX_INSTALL_LOG: string;
  // Colon-separated home-relative paths that uninstall.sh's _should_remove
  // helper must preserve; empty string when the entry has no preserve_paths.
  // Set for both install.sh and uninstall.sh (symmetric contract).
  AGENTLINUX_PRESERVE_PATHS: string;
  [key: string]: string;
}

// Canonical PATH literal — MUST be byte-identical to /etc/agentlinux.env
// written by 40-path-wiring.sh (bats cross-asserts this on a provisioned host).
export const AGENT_PATH =
  "/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin";

export interface DispatchArgs {
  entry: CatalogEntry;
  recipePath: string; // absolute path to install.sh / uninstall.sh
  version: string; // decideVersion().version
  catalogDir: string; // Catalog.catalogDir
  extraEnv?: Record<string, string>;
  // #2 (dogfood): stream the recipe's stdout/stderr live (install/remove, the
  // long interactive paths). Buffered when unset — the DI test dispatchers and
  // reconcile/rewire callers never stream.
  stream?: boolean;
}

export interface DispatchResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  // Set by the streaming dispatcher when output was already teed to the console;
  // command layers key off it to skip re-printing the captured stdout.
  streamed?: boolean;
}

// Dispatcher signature — the test injection seam; mirrors asUser()'s shape.
export type Dispatcher = (
  user: string,
  argv: string[],
  opts: { env: Record<string, string>; stream?: boolean },
) => Promise<DispatchResult>;

export async function dispatchRecipe(
  args: DispatchArgs,
  dispatcher: Dispatcher = asUser,
): Promise<DispatchResult> {
  // Colon-separated home-relative paths (already normalized by loader.ts).
  // Empty string when no preserve_paths_file is configured; always set so the
  // var is present in both install.sh and uninstall.sh.
  const preservePaths = (args.entry.preserve_paths ?? []).join(":");
  // Resolve the configured install user + its home (AL-50 AC4 / AL-59). For the
  // default user `agent`, `home` is /home/agent and the PATH built below is
  // byte-identical to the AGENT_PATH constant (and /etc/agentlinux.env).
  const user = resolveInstallUser();
  const home = `/home/${user}`;
  const path = `${home}/.npm-global/bin:${home}/.local/bin:/usr/local/bin:/usr/bin:/bin`;
  const env: Record<string, string> = {
    AGENTLINUX_PINNED_VERSION: args.version,
    AGENTLINUX_CATALOG_DIR: args.catalogDir,
    AGENTLINUX_AGENT_HOME: home,
    AGENTLINUX_SOURCE_KIND: args.entry.source_kind,
    AGENTLINUX_INSTALL_LOG: "/var/log/agentlinux-install.log",
    AGENTLINUX_PRESERVE_PATHS: preservePaths,
    PATH: path,
    HOME: home,
    NPM_CONFIG_PREFIX: `${home}/.npm-global`,
    LANG: "C.UTF-8",
    LC_ALL: "C.UTF-8",
    ...(args.extraEnv ?? {}),
  };

  return dispatcher("agent", ["bash", args.recipePath], { env, stream: args.stream ?? false });
}
