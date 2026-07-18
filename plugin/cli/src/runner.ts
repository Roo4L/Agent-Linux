// SPDX-License-Identifier: MIT
// plugin/cli/src/runner.ts — shared recipe dispatcher for install/remove/upgrade.
// Mirrors /etc/agentlinux.env (40-path-wiring.sh) byte-for-byte so recipes
// inherit the same PATH/locale from provisioner or CLI — a drift would let
// recipes resolve npm from /usr/bin and break the no-EACCES contract.
//
// DI seam: the second parameter is the asUser impl (defaults to the real one);
// unit tests inject a capturing mock. DI over module-mocking because
// `mock.module` is undefined on the Node 20 executor host.

import { asUser } from "./state/dispatcher.js";
import type { CatalogEntry } from "./types.js";

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
  const env: Record<string, string> = {
    AGENTLINUX_PINNED_VERSION: args.version,
    AGENTLINUX_CATALOG_DIR: args.catalogDir,
    AGENTLINUX_AGENT_HOME: "/home/agent",
    AGENTLINUX_SOURCE_KIND: args.entry.source_kind,
    AGENTLINUX_INSTALL_LOG: "/var/log/agentlinux-install.log",
    AGENTLINUX_PRESERVE_PATHS: preservePaths,
    PATH: AGENT_PATH,
    HOME: "/home/agent",
    NPM_CONFIG_PREFIX: "/home/agent/.npm-global",
    LANG: "C.UTF-8",
    LC_ALL: "C.UTF-8",
    ...(args.extraEnv ?? {}),
  };

  return dispatcher("agent", ["bash", args.recipePath], { env, stream: args.stream ?? false });
}
