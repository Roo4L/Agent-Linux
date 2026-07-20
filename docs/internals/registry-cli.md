# Registry CLI

`agentlinux` is the small TypeScript CLI shipped with the plugin. It reads
the agent catalog and dispatches install / adopt / list / remove / upgrade /
pin commands — every state-changing operation runs as the configured install
user (the `agent` user by default; see [Choosing the install
user](installer.md)), never as root. The CLI is the surface developers
actually touch; everything else (provisioner steps, recipes, sentinels, the
catalog itself) is wiring underneath.

## The problem

A fleet of agents, each with its own install command and update story,
becomes unmemorable fast. Claude Code installs via Anthropic's native
`claude.ai/install.sh`; Open GSD installs via `npm install -g @opengsd/gsd-core`
plus a multi-runtime bootstrapper; Playwright installs via
`npm install -g @playwright/cli` plus a `--skills` bootstrapper that
needs apt-layer browser deps. The naive alternative is a `README.md`
listing per-agent install commands and hoping operators copy-paste them
correctly — which immediately drifts because no one updates README in
lockstep with the install paths, and the friction of "look up the right
incantation for *this* tool" multiplies linearly with every new agent.

Operators want one verb per intent. `agentlinux install <name>`
regardless of whether the underlying recipe is npm-global, an
upstream native installer, or a future apt path; `agentlinux upgrade`
regardless of which mix of agents is installed; `agentlinux pin
<name>=<spec>` regardless of which release pinned the agent at which
version. Without a CLI, those verbs do not exist — and without those
verbs, fleet-level concerns (stickiness, three-way divergence,
"is this currently installed?", install-time invariants) have nowhere
to live.

A CLI is also where invocation discipline gets enforced. Every recipe
must run as the configured install user (not root) so the install tree
lands owned by that user; every recipe must receive the catalog's `pinned_version`
in the environment so the install version matches what AgentLinux's CI
actually exercised. That preflight is impossible to enforce in a
README; it is trivial in a CLI.

## What AgentLinux does

The CLI exposes six verbs:

- `agentlinux list` — render the catalog as a table (or JSON), with
  per-agent status: `not-installed`, `present`, `synced`,
  `override-ahead`, `override-behind`, `drift-undeclared`. `present` is the
  honest-status case: a tool the host already has but that AgentLinux has not
  recorded — it reads `present` with its detected version, never
  `not-installed`, so a brownfield host's existing tools are never
  mislabelled as absent. The hint depends on *where* the tool lives: at the
  managed (canonical) path it says "run install to manage" (adoptable); at a
  non-canonical path — e.g. Claude Code installed via npm at
  `~/.npm-global/bin/claude` instead of the native `~/.local/bin/claude` — it
  names the detected path and says "run install to migrate", because that
  install is a migration candidate, not blessed as-is. `list` also tells the
  truth when a tool self-updated behind AgentLinux's back: rather than trust
  the version it recorded at install time, it probes the *real* on-disk
  version, so an agent that ran its own updater (`codex update`, a stray
  `npm i -g`) reads `drift-undeclared` with the actual version and a
  "self-updated from `<recorded>` — run: agentlinux upgrade to reconcile"
  pointer, not a false "synced". Hides `test_only` entries unless
  `--include-test`.
- `agentlinux install <name>` — load the catalog, find the entry,
  inject `AGENTLINUX_PINNED_VERSION` and the install-user environment,
  and dispatch the entry's `install_recipe_path` (typically
  `install.sh`) as the configured install user. After success, write a sentinel
  to `/opt/agentlinux/state/installed.d/<id>.json` recording the
  installed version and source (`curated`, `latest`, or
  `pinned=<semver>`). `--version <semver>` overrides the catalog
  pin; `--force` re-runs the recipe even when the sentinel says it is
  already installed. When the detect cache reports a healthy install at a
  *non-canonical* path (the npm→native migration case for Claude Code),
  install treats it as a relocation: it uninstalls the off-path install and
  reinstalls at the canonical path — **keeping the user's current version**
  (recorded `source=override`), not forcing the catalog pin. A later
  `agentlinux upgrade --reset-all-curated` reconciles to the curated
  version only if the operator opts in.
- `agentlinux adopt [<name>] [--all]` — record a tool the host already
  has into a managed sentinel *without installing anything*. When a
  pre-existing install is healthy, at its canonical path, and within the
  catalog's compatibility window, adopt writes a `reused` sentinel so
  the agent comes under `upgrade`/`remove` management; it never
  downloads, reinstalls, or repairs. The installer runs `adopt --all`
  automatically after a successful apply, which is what turns a
  brownfield host's `present` tools into managed `reused` entries. "No
  agent installed by default" still holds — adopt only records what
  detection already found.

After a coding agent install succeeds, the CLI also makes a best-effort
cross-agent reconciliation pass for installed providers that declare a
`rewire_recipe_path`. That pass includes Antigravity in the supported coding
agent set, so hosted MCP registrations can be applied to its native config
when it is installed after the provider. A failed reconciliation is reported
without turning the already-successful agent install into a failure.
- `agentlinux remove <name>` — the symmetric inverse: dispatch the
  entry's `uninstall_recipe_path` and delete the sentinel. `--force`
  succeeds even when nothing is installed (idempotent).
- `agentlinux upgrade` — compare three numbers per agent (installed
  per the sentinel, curated per the catalog, optionally upstream
  per `npm view <pkg> version`) and surface the divergence. Default
  is report-only and offline; opt-in flags
  (`--reset-all-curated`, `--respect-overrides`, `--all-latest`,
  `--check-upstream`) drive bulk reconciliation.
- `agentlinux pin <name>=<curated|latest|x.y.z>` — set sticky
  overrides per [STABILITY-MODEL.md](../STABILITY-MODEL.md).
  `=curated` clears the sticky bit; `=latest` follows upstream
  forever; `=<semver>` holds at an exact version.

Every command starts with the same preflight. A Commander `preAction`
hook calls `guardAgentUser`, which exits with code 64 if the CLI is
running as any user other than the **configured install user**. That user
is not a hardcoded `agent` constant: `guardAgentUser` resolves it from
`AGENTLINUX_USER` — the environment variable first, then the
`AGENTLINUX_USER=` line in the root-owned `/etc/agentlinux.env` written by
the installer — defaulting to `agent` when neither is set. So on a host
installed with `--user=claude`, the guard answers to `claude`; on a default
host it answers to `agent`. A malformed value (one that fails the POSIX
username charset) falls back to `agent` as defense-in-depth.

The catalog snapshot shipped with the release is staged on disk at
`/opt/agentlinux/catalog/<version>/catalog.json` and validated against
`schema.json` (JSON Schema 2020-12, ajv) before any state-changing
operation runs. Recipes are dispatched via a thin runner (`dispatchRecipe`)
that runs the per-agent `install.sh` / `uninstall.sh` **as the configured
install user** — `dispatcher(user, …)`, not a hardcoded `agent` — with the
env block (`PATH` / `NPM_CONFIG_PREFIX` / `HOME` / `AGENTLINUX_AGENT_HOME` /
`AGENTLINUX_PINNED_VERSION`) derived from that user's home (`/home/<user>`).
For the default user the produced PATH string is byte-identical to the
`/etc/agentlinux.env` line the installer wrote, so the recipe environment
matches the provisioner exactly. This is what closes the alt-user
hollow-install gap: a `--user=claude` host dispatches catalog ops under
`claude` (`sudo -u claude …`), so a system that has no `agent` user at all
does not fail every install/remove/upgrade with `sudo: unknown user: agent`.
The recipe itself stays plain bash, easy to read and easy for the catalog
auditor to review.

## Worked example

```
# Brownfield host that already had Claude Code + GSD before AgentLinux.
# The installer's adopt-on-install step already ran; both read as managed.
$ agentlinux list
NAME           STATUS         CURATED   INSTALLED  DESCRIPTION
claude-code    synced         2.1.98    2.1.98 (reused — managed by agentlinux ...
gsd            synced         1.7.0     1.7.0 (reused — managed by agentlinux ...
playwright-cli not-installed  0.1.17    -          Microsoft's token-efficient ...

# A tool the host has but that AgentLinux has not recorded yet reads `present`,
# not `not-installed` — and adopt records it (no download, no reinstall):
$ agentlinux list
claude-code    present        2.1.98    2.1.98 (detected — run: agentlinux install claude-code ...
$ agentlinux adopt claude-code
[ADOPT] claude-code: adopted pre-existing install 2.1.98 (status=reused — managed by agentlinux upgrade/remove)

$ agentlinux upgrade
  claude-code     installed=2.1.98  curated=2.1.98  state=synced
  gsd             installed=1.7.0  curated=1.7.0  state=synced
  playwright-cli  not-installed
```

One stable verb surface (`list`, `install`, `upgrade`) regardless of
whether the underlying recipe is an Anthropic native installer, an
npm-global, or an `@playwright/cli`-style npm-plus-bootstrap.

## Value vs the naive approach

Without a CLI, the naive paths are "remember each agent's install
command" and "manage the fleet by hand." Two problems:

1. **Per-agent commands drift.** README install instructions go stale
   the moment an agent's install path changes — a new bootstrapper
   step appears, an apt dep is added, a pinned version moves. Operators
   copy old commands from a stale README and end up with half-installed
   agents (binary on PATH but skills missing, sentinel written but
   bootstrapper skipped, etc.). The CLI binds the install path to the
   catalog so the verb stays stable while the recipe evolves
   underneath.
2. **No place to land cross-cutting concerns.** Sticky pin overrides,
   three-way divergence between installed / curated / upstream
   ([STABILITY-MODEL.md](../STABILITY-MODEL.md)), install-time
   invariants ("must run as agent user", "must inject pinned_version",
   "recipe-failure must keep the prior sentinel intact"), and "is
   this currently installed?" status are properties of the *fleet*,
   not of individual agents. The CLI is where they live; without
   one, every recipe re-implements the same preflight, badly.

**One stable verb surface for an evolving agent set — the CLI keeps
the contract honest while the recipes move underneath, and every
state-changing operation runs as the configured install user with the
catalog's `pinned_version` in the environment.**

## Related

- [Catalog](catalog.md) — the schema-validated registry the CLI reads.
- [Agent user](agent-user.md) — every install runs as this user; the
  CLI's `preAction` guard refuses to dispatch under any other.
- [Claude Code](claude-code.md) — the canonical install case; the
  self-update-without-sudo invariant is its release-gate test.
- [GSD](gsd.md) — npm-global recipe with a bundled bootstrapper.
- [Playwright](playwright.md) — npm-global plus a `--skills`
  bootstrapper plus apt-layer browser deps.
