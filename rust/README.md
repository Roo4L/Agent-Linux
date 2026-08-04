# The AgentLinux Rust workspace

A map for finding your way around. For *what a component does and why*, see
[`docs/internals/`](../docs/internals/) — in particular
[`installer.md`](../docs/internals/installer.md) and
[`registry-cli.md`](../docs/internals/registry-cli.md).

**Paths below are relative to this file** (the `rust/` directory), except the
few that start `packaging/`, `plugin/`, `tests/`, or `docs/` — those are from
the repo root. Note there is no `rust/src/`; both crates live under
`crates/`.

## The one thing to know first

Three kinds of code, three different places:

- **`crates/agentlinux-core`** decides. Given some facts, what *should* happen?
- **`crates/agentlinux`** (the bin) finds out the facts and makes things happen —
  every file read, subprocess, and env lookup lives here.
- **`plugin/catalog/agents/<name>/`** installs one specific tool. These are
  **Bash, on purpose**, and they are not in this workspace.

The core is a separate crate because `cargo-mutants` and `proptest` are scoped
to it (`--package agentlinux-core`). That only works if its production code
stays free of `std::process`, `std::fs`, and `std::env` — a function whose
answer could differ on two machines given the same arguments belongs in the bin.
(Two `#[cfg(test)]` blocks do read files; the ban is on shipped code.)

## Where do I start?

| I want to understand… | Start here | Then |
|---|---|---|
| **the entry point** | `crates/agentlinux/src/main.rs` — the verb dispatch table, the root-vs-agent-user guard split, and the canonical per-agent path map | `crates/agentlinux/src/cli.rs` |
| **the installer**, end to end | `packaging/curl-installer/install.sh` — downloads the tarball, verifies its `.sha256`, then `exec`s `agentlinux provision --user … --yes` | `crates/agentlinux/src/cmd/provision.rs`, then `crates/agentlinux/src/provision/` |
| **what the CLI accepts** | `crates/agentlinux/src/cli.rs` — every verb and flag | — |
| **one verb's behavior** | `crates/agentlinux/src/cmd/<verb>.rs` | the core module it calls (table below) |
| **how a version decision is made** | `crates/agentlinux-core/src/classify.rs` | called from `cmd/list.rs` and `cmd/install.rs`; `cmd/upgrade.rs` reaches it indirectly through `core/divergence.rs` |
| **what installs `claude-code`** | `plugin/catalog/agents/claude-code/install.sh` + `uninstall.sh` | its pinned entry in `plugin/catalog/catalog.json` — not Rust, by design |
| **how a recipe gets invoked** | `crates/agentlinux/src/dispatcher.rs` | `crates/agentlinux/src/recipe_env.rs` — the env contract recipes read |

## The provisioner

`cmd/provision.rs` is the orchestrator. Its `run_steps` runs five steps in a
fixed order, each a `run()` in its own module under
`crates/agentlinux/src/provision/`:

```
agent_user → sudoers → nodejs → path_wiring → registry_cli
```

That sequence is not the whole path. `--purge`, `--report-only`, and `--dry-run`
each return before it; host detection and agent adoption run after it. Ahead of
it, `wizard.rs` handles interactive prompts and `remediate.rs` /
`remediate_npm_prefix.rs` fix brownfield hosts.

**Consent is three-way, not two.** For a state-overwriting remediation:
`--yes` proceeds, a TTY prompts, and **neither bails** with exit 65 and zero
mutation. The curl-pipe path works because the installer passes `--yes` (and
`--user`), not merely because stdin is a pipe.

## Verb → core module

Each verb is an adapter: read through the file adapters, call the pure logic,
print. This is the mapping the module names do not make obvious.

| Verb | Pure logic it calls |
|---|---|
| `list` | `category`, `classify`, `detect_gates`, `semver_shim` |
| `install` | `classify`, `detect_gates`, `semver_shim` |
| `upgrade` | `divergence`, `detect_gates` |
| `pin` | `pin_spec`, `detect_gates` |
| `adopt` | `detect_gates` |
| `provision` | `reuse` |
| `remove` | none — it is pure I/O |

## The bin's other modules, by what they talk to

- **Files** — `catalog.rs` (catalog.json), `sentinel.rs` (per-agent install
  records, default `/opt/agentlinux/state/installed.d/`, overridable via
  `AGENTLINUX_STATE_DIR` — which is what the bats tests use), `cache.rs` (detect
  cache), `probe.rs` (the installed version, read from `package.json`)
- **Subprocesses** — `dispatcher.rs` (runs the recipes), `npm.rs`
  (`npm ls -g`, `npm view`)
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

**If you edit a catalog type and `cargo test --all` fails somewhere unrelated:**
`core/schema_gen.rs` asserts `plugin/catalog/schema.json` matches the schema
generated from the Rust types. Regenerate with
`UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema`.

## Things that will mislead you

**Doc comments claiming code is unimplemented.** `cmd/provision.rs`'s header
says only `agent_user` is wired and the other four steps are "LOUD not-yet-wired
markers"; `main.rs` says `install`/`remove`/`upgrade` "remain loud
EX_SOFTWARE(70) not-implemented stubs". All eight are fully wired. These are the
most dangerous stale comments in the tree — trust the code.

**Doc comments citing TypeScript files** — `upgrade.ts:103-119`, `detect.ts:16-28`.
A porting trail from the rewrite; those files are gone. At least one goes
further and describes a CI job that no longer exists.

**Line counts.** 44 of 45 files carry a `#[cfg(test)]` block, and about 39% of
the workspace is inside one. Several files are over 70% test.

**Two files named `probe.rs`** with unrelated jobs: `src/probe.rs` reads an
installed version from disk; `src/provision/probe.rs` reads host state.
`detect.rs` also defines a private `classify` unrelated to `core::classify`.

**`proptest-regressions/`** is deliberately not gitignored, so a counterexample
found once replays forever. It currently holds no seeds — every property passes.
