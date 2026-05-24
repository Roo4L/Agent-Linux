# 008: Commander.js for the registry CLI

**Status:** Accepted
**Date:** 2026-04-18

## Context

The `agentlinux` CLI needs argument parsing, subcommand dispatch, help
generation, and JSON output. Options considered: Commander.js (mature, wide
adoption, minimal surface), yargs (more features, heavier API), oclif (Salesforce
framework, heavy for a ~5-command CLI), hand-rolled (tempting for five
subcommands but predictably turns into a re-implementation of Commander).

## Decision

Use Commander.js `^12.x` for the v0.3.0 registry CLI. Entry point at
`plugin/cli/src/index.ts`; subcommand handlers under `plugin/cli/src/commands/`.
No other CLI framework.

## Consequences

- `plugin/cli/package.json` pins `commander` as a runtime dependency; the release
  tarball bundles via `esbuild` so end users don't install Commander separately.
- `node-engineer` review subagent enforces Commander idioms (use `.command()`
  chains, not positional-arg parsing; use `.action()` handlers, not
  `process.argv` inspection).
- Swapping CLI frameworks later would require rewriting `src/` but not the
  bats tests (behavior-contract framing, ADR-002), so the cost of reversal is
  bounded.
