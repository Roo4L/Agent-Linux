#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// plugin/cli/src/index.ts — agentlinux CLI entrypoint (ADR-008, Commander ^12).
//
// Registers six subcommands; a preAction hook runs guardAgentUser before any
// action (blocks root + non-agent users with exit 64, CLI-05). parseAsync is
// required so rejected async-handler promises aren't silently dropped.

import { Command } from "commander";
import { adoptCmd } from "./commands/adopt.js";
import { installCmd } from "./commands/install.js";
import { listCmd } from "./commands/list.js";
import { pinCmd } from "./commands/pin.js";
import { removeCmd } from "./commands/remove.js";
import { upgradeCmd } from "./commands/upgrade.js";
import { guardAgentUser } from "./guard/user.js";
import { VERSION } from "./version.js";

const program = new Command();

program
  .name("agentlinux")
  .description("AgentLinux registry CLI — install, upgrade, remove catalog agents")
  .version(VERSION, "-V, --version");

// enablePositionalOptions() is required so the install subcommand's
// `--version <semver>` override (CLI-03) can shadow the program-level
// `-V, --version`; without it Commander intercepts `--version` and exits early.
// Side-effect: program-level options aren't recognized after a subcommand name,
// so `--json` is registered per-subcommand (list, upgrade) instead.
program.enablePositionalOptions();

// CLI-05: fail fast as a non-agent user before any subcommand runs.
program.hook("preAction", (_thisCommand, actionCommand) => {
  guardAgentUser(actionCommand.name());
});

program
  .command("list")
  .description("List catalog agents and their install status")
  .option("--include-test", "include test-only entries (hidden by default)")
  .option("--by-category", "group entries by category (coding-agent, mcp, devops, …)")
  .option("--descriptions", "show the DESCRIPTION column (hidden by default; always in --json)")
  .option("--json", "machine-readable JSON array output")
  .action(async (opts) => {
    await listCmd(opts);
  });

program
  .command("install <name>")
  .description("Install a catalog agent at its pinned_version")
  .option("--force", "re-run install.sh even if sentinel matches")
  .option("--version <semver>", "override catalog pin with a specific version")
  .option("--include-test", "allow installing test-only entries (hidden by default)")
  // Consent gate for state-overwriting REMEDIATE-04, required in non-TTY mode.
  // No env-var equivalent.
  .option("--yes", "approve state-overwriting REMEDIATE-04 (uninstall + reinstall) in non-TTY mode")
  // Preview the install decision without dispatching; contradicts --yes (exit 64).
  .option(
    "--dry-run",
    "preview the install decision (reuse|remediate|create) without dispatching install.sh; exits 0",
  )
  .action(async (name: string, opts) => {
    await installCmd(name, opts);
  });

program
  // AL-61: record pre-existing reuse-eligible agents into sentinels without
  // installing anything. <name> is optional; --all sweeps the catalog. The base
  // installer runs `agentlinux adopt --all` after a successful --yes apply.
  .command("adopt [name]")
  .description("Adopt pre-existing reuse-eligible agents into managed sentinels (no install)")
  .option("--all", "adopt every reuse-eligible catalog agent")
  .option("--include-test", "include test-only entries (hidden by default)")
  .option("--json", "machine-readable JSON array output")
  .action(async (name: string | undefined, opts) => {
    await adoptCmd(name, opts);
  });

program
  .command("remove <name>")
  .description("Uninstall a catalog agent")
  .option("--force", "succeed even if agent is not installed (idempotent no-op)")
  .action(async (name: string, opts) => {
    await removeCmd(name, opts);
  });

program
  .command("upgrade")
  .description("Reconcile installed versions against the curated catalog")
  .option("--reset-all-curated", "accept curated versions for all agents; clear overrides")
  .option("--respect-overrides", "install curated only for non-overridden agents")
  .option("--all-latest", "install npm latest for all (implies --check-upstream)")
  .option("--check-upstream", "query `npm view <pkg> version` for upstream latest (network)")
  .option("--json", "machine-readable JSON array output")
  .action(async (opts) => {
    await upgradeCmd(opts);
  });

program
  .command("pin <spec>")
  .description("Set sticky override: <name>=curated|latest|x.y.z")
  .action(async (spec: string, opts) => {
    await pinCmd(spec, opts);
  });

// Async actions require parseAsync; top-level await needs "type": "module".
await program.parseAsync(process.argv);
