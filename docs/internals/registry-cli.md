# Registry CLI

`agentlinux` is the small TypeScript CLI shipped with the plugin. It reads
the agent catalog and dispatches install / list / remove / upgrade / pin
commands — every state-changing operation runs as the agent user, never
as root. The CLI is the surface developers actually touch; everything
else (provisioner steps, recipes, sentinels, the catalog itself) is
wiring underneath.

## The problem

A fleet of agents, each with its own install command and update story,
becomes unmemorable fast. Claude Code installs via Anthropic's native
`claude.ai/install.sh`; GSD installs via `npm install -g get-shit-done-cc`
plus a `--global --claude` bootstrapper; Playwright installs via
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
must run as the `agent` user (not root) so the install tree lands
agent-owned; every recipe must receive the catalog's `pinned_version`
in the environment so the install version matches what AgentLinux's CI
actually exercised. That preflight is impossible to enforce in a
README; it is trivial in a CLI.

## What AgentLinux does

The CLI exposes five verbs:

- `agentlinux list` — render the catalog as a table (or JSON), with
  per-agent status: `not installed`, `synced`, `override-ahead`,
  `override-behind`. Hides `test_only` entries unless `--include-test`
  is passed.
- `agentlinux install <name>` — load the catalog, find the entry,
  inject `AGENTLINUX_PINNED_VERSION` and the agent-user environment,
  and dispatch the entry's `install_recipe_path` (typically
  `install.sh`) as the `agent` user. After success, write a sentinel
  to `/opt/agentlinux/state/installed.d/<id>.json` recording the
  installed version and source (`curated`, `latest`, or
  `pinned=<semver>`). `--version <semver>` overrides the catalog
  pin; `--force` re-runs the recipe even when the sentinel says it is
  already installed.
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
running as root or as any user other than `agent`. The catalog snapshot
shipped with the release is staged on disk at
`/opt/agentlinux/catalog/<version>/catalog.json` and validated against
`schema.json` (JSON Schema 2020-12, ajv) before any state-changing
operation runs. Recipes are dispatched via a thin runner that exports
the agent's PATH / NPM_CONFIG_PREFIX / HOME / `AGENTLINUX_PINNED_VERSION`
and shells into the per-agent `install.sh` — the recipe itself is
plain bash, easy to read and easy for the catalog auditor to review.

## Worked example

```
$ agentlinux list
NAME           STATUS         CURATED   INSTALLED  DESCRIPTION
claude-code    not installed  2.1.98    -          Anthropic's agentic CLI ...
gsd            not installed  1.37.1    -          GSD workflow CLI for Claude Code ...
playwright-cli not installed  0.1.11    -          Microsoft's token-efficient ...

$ agentlinux install gsd
gsd: installing get-shit-done-cc@1.37.1
gsd: install complete (resolves at /home/agent/.npm-global/bin/get-shit-done-cc;
     banner matches pin; skill set wired into /home/agent/.claude/skills/gsd-*)

$ agentlinux upgrade
  claude-code     not installed
  gsd             installed=1.37.1  curated=1.37.1  state=synced
  playwright-cli  not installed
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
state-changing operation runs as the agent user with the catalog's
`pinned_version` in the environment.**

## Related

- [Catalog](catalog.md) — the schema-validated registry the CLI reads.
- [Agent user](agent-user.md) — every install runs as this user; the
  CLI's `preAction` guard refuses to dispatch under any other.
- [Claude Code](claude-code.md) — the canonical install case; the
  self-update-without-sudo invariant is its release-gate test.
- [GSD](gsd.md) — npm-global recipe with a bundled bootstrapper.
- [Playwright](playwright.md) — npm-global plus a `--skills`
  bootstrapper plus apt-layer browser deps.
