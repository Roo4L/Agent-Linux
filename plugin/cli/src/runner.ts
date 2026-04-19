// plugin/cli/src/runner.ts — shared recipe dispatcher for install/remove/upgrade.
// Mirrors /etc/agentlinux.env (plugin/provisioner/40-path-wiring.sh line 146)
// byte-for-byte so recipes inherit the same PATH/locale whether triggered by
// provisioner or CLI. T-04-07 mitigation: a drift between the two would cause
// recipes to resolve npm from /usr/bin (Pitfall 5 — sudo -E is overridden by
// secure_path) and break the no-EACCES contract that AgentLinux exists for.
//
// Testability: DI seam — second parameter is the asUser implementation
// (defaults to the real one). Unit tests inject a capturing mock; production
// code uses the default. Chose DI over node:test module-mocking because
// `mock.module` is undefined on Node 20.20.1 (executor host) — DI is portable
// across both Node 20 dev and Node 22 LTS production.

import { asUser } from "./state/dispatcher.js";
import type { CatalogEntry } from "./types.js";

export interface RecipeEnv {
  AGENTLINUX_PINNED_VERSION: string;
  AGENTLINUX_CATALOG_DIR: string;
  AGENTLINUX_AGENT_HOME: string;
  AGENTLINUX_SOURCE_KIND: string;
  AGENTLINUX_INSTALL_LOG: string;
  [key: string]: string;
}

// Canonical PATH literal — MUST be byte-identical to /etc/agentlinux.env
// written by 40-path-wiring.sh (see T-04-07 / Pitfall 5 / Plan 03-01). Plan
// 04-07 bats will cross-assert this value against the on-disk env file on a
// provisioned host.
export const AGENT_PATH =
  "/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin";

export interface DispatchArgs {
  entry: CatalogEntry;
  recipePath: string; // absolute path to install.sh / uninstall.sh
  version: string; // decideVersion().version
  catalogDir: string; // Catalog.catalogDir
  extraEnv?: Record<string, string>;
}

export interface DispatchResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

// Dispatcher signature — the injection seam used by unit tests.
// Mirrors state/dispatcher.ts asUser() exactly (same (user, argv, opts) shape).
export type Dispatcher = (
  user: string,
  argv: string[],
  opts: { env: Record<string, string> },
) => Promise<DispatchResult>;

export async function dispatchRecipe(
  args: DispatchArgs,
  dispatcher: Dispatcher = asUser,
): Promise<DispatchResult> {
  const env: Record<string, string> = {
    AGENTLINUX_PINNED_VERSION: args.version,
    AGENTLINUX_CATALOG_DIR: args.catalogDir,
    AGENTLINUX_AGENT_HOME: "/home/agent",
    AGENTLINUX_SOURCE_KIND: args.entry.source_kind,
    AGENTLINUX_INSTALL_LOG: "/var/log/agentlinux-install.log",
    PATH: AGENT_PATH,
    HOME: "/home/agent",
    NPM_CONFIG_PREFIX: "/home/agent/.npm-global",
    LANG: "C.UTF-8",
    LC_ALL: "C.UTF-8",
    ...(args.extraEnv ?? {}),
  };

  return dispatcher("agent", ["bash", args.recipePath], { env });
}
