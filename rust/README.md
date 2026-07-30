# The AgentLinux Rust workspace

A map for finding your way around. For *what a component does and why*, see
[`docs/internals/`](../docs/internals/) — in particular
[`installer.md`](../docs/internals/installer.md) and
[`registry-cli.md`](../docs/internals/registry-cli.md).

## The one thing to know first

Three kinds of code, three different places:

- **`agentlinux-core`** decides. Given some facts, what *should* happen?
- **`agentlinux`** (the bin) finds out the facts and makes things happen — every
  file read, subprocess, and env lookup lives here.
- **`plugin/catalog/agents/<name>/`** installs one specific tool. These are
  **Bash, on purpose**, and they are not in this workspace.

The core is a separate crate because `cargo-mutants` and `proptest` are scoped
to it (`--package agentlinux-core`). That only works if it stays free of
`std::process`, `std::fs`, and `std::env` — a function whose answer could differ
on two machines given the same arguments belongs in the bin.

## Where do I start?

| I want to understand… | Start here | Then |
|---|---|---|
| **the installer**, end to end | `packaging/curl-installer/install.sh` — downloads the tarball, verifies its `.sha256`, then `exec`s `agentlinux provision` | `src/cmd/provision.rs`, then `src/provision/` |
| **what the CLI accepts** | `src/cli.rs` — every verb and flag in one file | — |
| **one verb's behavior** | `src/cmd/<verb>.rs` | the core module it calls (table below) |
| **how a version decision is made** | `agentlinux-core/src/classify.rs` | called from `cmd/upgrade.rs` and `cmd/list.rs` |
| **what installs `claude-code`** | `plugin/catalog/agents/claude-code/install.sh` + `uninstall.sh` | its pinned entry in `plugin/catalog/catalog.json` |
| **how a recipe gets invoked** | `src/dispatcher.rs` | `src/recipe_env.rs` — the env contract recipes read |

## The provisioner

`cmd/provision.rs` is the orchestrator. It runs these in order, each a `run()`
in its own module under `src/provision/`:

```
agent_user → sudoers → nodejs → path_wiring → registry_cli
```

Around that sequence: `wizard.rs` handles the interactive prompts (and is
skipped when stdin is not a TTY, which is how the curl-pipe path works),
`remediate.rs` and `remediate_npm_prefix.rs` fix brownfield hosts, and
`probe.rs` / `log.rs` are helpers.

## Verb → core module

Each verb is an adapter: read through the file adapters, call the pure logic,
print. This is the mapping the module names do not currently make obvious.

| Verb | Pure logic it calls |
|---|---|
| `list` | `category`, `classify`, `detect_gates`, `semver_shim` |
| `install` | `classify`, `detect_gates`, `semver_shim` |
| `upgrade` | `divergence`, `detect_gates` |
| `pin` | `pin_spec`, `detect_gates` |
| `adopt` | `detect_gates` |
| `remove` | none — it is pure I/O |

## The bin's other modules, by what they talk to

- **Files** — `catalog.rs` (catalog.json), `sentinel.rs` (per-agent install
  records under `/opt/agentlinux/state/installed.d/`), `cache.rs` (detect cache)
- **Subprocesses** — `dispatcher.rs` (runs the recipes), `npm.rs`
  (`npm ls -g`, `npm view`), `probe.rs` (what is actually on disk)
- **The host** — `detect.rs` (scans, writes the cache), `distro.rs` (Ubuntu vs
  AlmaLinux family), `pkg.rs` (apt↔dnf neutral verbs), `sysio.rs` (the
  grep-before-mutate idempotency primitives)
- **Contracts** — `recipe_env.rs` (the typed source of the recipe env vars),
  `guard.rs` (refuses to run as the wrong user), `rewire.rs` (cross-agent wiring
  after install)

## Running things

```bash
cd rust
cargo test --all                          # what CI runs
cargo test -p agentlinux-core parity      # the node-semver parity goldens
cargo clippy --all-targets -- -D warnings
cargo fmt --all -- --check
```

Behavior tests are bats, not cargo, and run against an *installed* AgentLinux
inside a container:

```bash
./tests/docker/run.sh ubuntu-24.04        # from the repo root
```

## Two things that will confuse you

**Most files carry a large `#[cfg(test)]` block**, so a file's line count
overstates its production code considerably.

**Many doc comments cite a TypeScript file** — `upgrade.ts:103-119`,
`detect.ts:16`. That is a porting trail from the rewrite, not a live reference.
Those files are gone.

Counterexample seeds under `proptest-regressions/` are **committed on purpose**:
a failure found once must replay on every future run.
