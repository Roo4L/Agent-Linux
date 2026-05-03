#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// plugin/cli/src/index.ts — agentlinux CLI entrypoint.
// Pattern ref: 04-RESEARCH §Pattern 2 lines 474-548 + ADR-008 (Commander ^12).
//
// Flow:
//   1. Commander registers five subcommands (list, install, remove, upgrade, pin)
//   2. preAction hook fires guardAgentUser(<cmd>) BEFORE any action runs —
//      blocks root + any non-agent user with exit 64 (CLI-05)
//   3. parseAsync awaits async action handlers (Pitfall 3: .parse() silently
//      drops rejected promises; .parseAsync() awaits them)
//
// Every subcommand handler is a STUB in Wave 1 — real implementations land in
// Plans 04-03 (list/install/remove), 04-04 (upgrade), 04-05 (pin).

import { Command } from "commander";
import { installCmd } from "./commands/install.js";
import { listCmd } from "./commands/list.js";
import { pinCmd } from "./commands/pin.js";
import { removeCmd } from "./commands/remove.js";
import { upgradeCmd } from "./commands/upgrade.js";
import { guardAgentUser } from "./guard/user.js";

const program = new Command();

program
  .name("agentlinux")
  .description("AgentLinux registry CLI — install, upgrade, remove catalog agents")
  .version("0.3.2", "-V, --version");

// Commander's `.enablePositionalOptions()` is REQUIRED so the install
// subcommand's `--version <semver>` override (CLI-03) can shadow the
// program-level `-V, --version` flag when placed AFTER the subcommand
// name (`agentlinux install --version 1.2.3 foo`). Without it, Commander's
// global option-parser intercepts `--version` first, emits "0.3.0" and
// exits before the install action ever fires. Plan 04-07 Rule 1 auto-fix.
//
// Side-effect of positional options: an option registered at program level
// (e.g. a shared `--json`) is NOT recognized when placed AFTER a subcommand
// name. So `--json` is registered on each subcommand that actually supports
// machine-readable output (list, upgrade) rather than once at the program
// level.
program.enablePositionalOptions();

// CLI-05: fail fast when invoked as a non-agent user BEFORE any subcommand runs.
// preAction hook fires after parsing but before the action handler. Commander
// v12 supports .hook('preAction', fn) (see Commander README).
program.hook("preAction", (_thisCommand, actionCommand) => {
  guardAgentUser(actionCommand.name());
});

program
  .command("list")
  .description("List catalog agents and their install status")
  .option("--include-test", "include test-only entries (hidden by default)")
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
  .action(async (name: string, opts) => {
    await installCmd(name, opts);
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
  .description("Reconcile installed versions against the curated catalog (CLI-06)")
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
  .description("Set sticky override: <name>=curated|latest|x.y.z (CLI-07)")
  .action(async (spec: string, opts) => {
    await pinCmd(spec, opts);
  });

// Async actions REQUIRE parseAsync (Pitfall 3). Top-level await requires
// "type": "module" + NodeNext module resolution (both set in package.json +
// tsconfig.json).
await program.parseAsync(process.argv);
