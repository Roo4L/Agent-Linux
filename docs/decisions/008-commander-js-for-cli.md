# 008: Commander.js for the registry CLI

**Status:** Accepted (2026-04-18) — **Superseded (v0.4.0):** the registry CLI was
reimplemented in Rust and no longer runs on Node. Commander.js is replaced by
`clap` 4 (derive). The reason a maintained parsing library was chosen over a
hand-rolled one **survives and carried over** — see the note below.
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

## Superseded (v0.4.0)

The v0.4.0 Rust rewrite replaced the TypeScript CLI with a static x86_64-musl
binary. Commander.js, `plugin/cli/`, and the Node runtime dependency for the CLI
itself are gone.

- **What replaces it.** `clap` 4 with the derive API, declared in
  `rust/crates/agentlinux/Cargo.toml` and defined in
  `rust/crates/agentlinux/src/cli.rs`. Verb handlers live under
  `rust/crates/agentlinux/src/cmd/`.
- **The reasoning held.** The choice here was "a maintained parser over a
  hand-rolled one, because five subcommands predictably grows into a
  re-implementation." That argument transferred intact; `clap` is the same bet in
  a different language, and the CLI did grow past five verbs.
- **The reversal-cost claim held for the CLI.** This ADR predicted that swapping
  frameworks would rewrite `src/` but not the bats tests. For the registry-CLI
  surface it governs, that is what happened: `tests/bats/40-registry-cli.bats`
  changed exactly one line (the `INSTALLER` path), and `15-preflight-ux.bats` /
  `23-install-user.bats` were pure re-pointing with no assertion edits.

  The claim does **not** generalise to the whole rewrite. The provisioner cutover
  did move specs — `tests/bats/14-remediate.bats:217` relaxed a locked
  `exit 64` (EX_USAGE) assertion to "non-zero" because clap rejects an unknown
  flag with exit 2, and the `--help` "Exit codes:" test was dropped. Those are
  provisioner-surface behaviors, outside what this ADR decided, but they are the
  reason the bounded-reversal claim should be read as CLI-scoped rather than as
  evidence about the rewrite at large.

Why the full rewrite, and what else was considered:
[`../research/stack-reconsideration.md`](../research/stack-reconsideration.md),
tracked as [AL-115 — v0.4.0 Rust Rewrite](https://copiedwonder.atlassian.net/browse/AL-115).
This ADR is retained as the historical record of the original choice.
