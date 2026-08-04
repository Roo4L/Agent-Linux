# AgentLinux Stability Model

> The user-facing summary of AgentLinux's curated-combo version pinning —
> the full decision record is at [`decisions/011-stability-first-version-pinning.md`](decisions/011-stability-first-version-pinning.md).

AgentLinux ships *curated combos*: every catalog agent is pinned to an exact
version that we test together end-to-end before each release. You install one
combo and everything just works. When you want to run ahead of the curated
pin, you can — and `agentlinux upgrade` + `agentlinux pin` give you a clean
way to reconcile.

## What's a curated combo

Every release bundles a catalog snapshot that CI has exercised on freshly
booted VMs of every supported distribution before the tag shipped. The snapshot
is staged on disk at `/opt/agentlinux/catalog/<version>/catalog.json` and is
the source of truth for `agentlinux install <name>`.

The catalog currently pins 26 tools; `agentlinux list` is the live answer. The
three it started with:

- `claude-code` — **2.1.98** (Anthropic's native installer; self-updates via
  `claude update` into the agent-owned install tree)
- `gsd` (`@opengsd/gsd-core`) — **1.7.0** (npm global into the agent's
  per-user prefix; the package-native command is `gsd-core`)
- `playwright-cli` — **0.1.17** (npm global + agent-owned browser download;
  launch libraries are installed through the agent user's non-interactive
  sudo permission)

Before a release can publish, CI installs the entire pinned set on freshly
booted VMs of every supported distribution and runs the full behavior suite
against them. If any agent in the combo fails, the release does not ship.

## What `agentlinux upgrade` compares

For each agent, `agentlinux upgrade` lines up four numbers — the four version
columns in its table:

- **sentinel** — the version AgentLinux recorded when it last installed or
  pinned this agent. Think of it as "what AgentLinux believes is installed."
- **installed** — what is actually on disk. For npm-installed agents this is
  read live from the global npm tree, so it can disagree with the sentinel. For
  agents that ship their own installer, AgentLinux reports the recorded version
  (see the limitation below).
- **curated** — the pin from this release's catalog snapshot.
- **latest** — the newest published upstream version. Resolved only for
  npm-backed agents, and only when you pass `--check-upstream`; otherwise it
  shows `-` and no network call is made.

The STATUS column is the verdict:

- `synced` — installed matches the curated pin. Nothing to do.
- `drift-undeclared` — the sentinel and the disk disagree: something updated
  this agent outside AgentLinux. This is the state a self-updater or a stray
  `npm i -g` produces.
- `override-ahead` / `override-behind` — the sentinel and the disk agree, but
  sit above or below the curated pin. You installed with an explicit version, or
  a new release rolled the pin past you.
- `pinned-override` — you are off the curated pin on purpose, recorded with
  `agentlinux pin`. AgentLinux stops flagging it.
- `not-installed` / `present` — not installed, or installed by hand and not yet
  managed by AgentLinux (`agentlinux adopt` takes it over).

> **Known limitation.** Drift detection currently works only for npm-installed
> agents. Agents with their own installer — Claude Code among them — report the
> recorded version rather than probing disk, so a self-update is invisible to
> `agentlinux upgrade` and the row stays `synced`.

## Worked example: something updated behind AgentLinux's back

Agents update themselves — that is the point of the environment AgentLinux
provisions. When one does, the version AgentLinux recorded and the version on
disk stop agreeing, and `agentlinux upgrade` says so instead of quietly
overwriting your machine:

```
$ npm i -g @opengsd/gsd-core@1.8.0     # or the tool updated itself
$ agentlinux upgrade
ID              STATUS            SENTINEL  INSTALLED  CURATED  LATEST  SRC
claude-code     synced            2.1.98    2.1.98     2.1.98   -       curated
gsd             drift-undeclared  1.7.0     1.8.0      1.7.0    -       curated
playwright-cli  synced            0.1.17    0.1.17     0.1.17   -       curated
```

(Trimmed — the real table prints one row per catalog entry. Run it as the agent
user; AgentLinux's commands refuse to run as anyone else.)

**`agentlinux upgrade` on its own changes nothing.** With no flags it prints the
table and exits: report first, decide, then apply — the same shape as
`apt list --upgradable` before `apt upgrade`. Nothing is installed, removed, or
downgraded until you pass a flag. (`LATEST` stays `-` unless you add
`--check-upstream`, which costs a network call; `upgrade` is offline by default.)

Applying a decision is one flag:

```bash
agentlinux upgrade --reset-all-curated  # everything back to the tested combo
agentlinux upgrade --respect-overrides  # move only the agents still on curated
agentlinux upgrade --all-latest         # npm-backed agents to upstream latest
```

To keep one agent out of those sweeps, record the decision first:

```bash
agentlinux pin gsd=1.8.0                # "I meant to be on 1.8.0" -> pinned-override
agentlinux upgrade --respect-overrides  # everything else to curated, gsd left alone
```

`agentlinux pin` only writes down your intent — it never reinstalls anything.
The next `upgrade` acts on what you recorded. Note that `--reset-all-curated` is
the blunt instrument: it drags **every** agent back to the curated pin, clearing
recorded overrides as it goes.

There is no interactive prompt, by design. `agentlinux upgrade` should run the
same way in a provisioning script or a cron job as it does in your shell, and a
command that blocks on stdin cannot. So the per-agent decision moves earlier:
you record it once with `agentlinux pin`, where it is durable, greppable, and
still there at the next release — instead of re-answering it from memory on
every run.

## Escape hatch: `agentlinux pin`

```bash
agentlinux pin claude-code=latest
agentlinux pin claude-code=curated
agentlinux pin gsd=1.7.0
```

- `=latest` — hands off. AgentLinux stops moving this agent: both
  `--respect-overrides` and `--all-latest` skip it, and you take updates through
  the tool's own updater. Clear it with `=curated`.
- `=curated` — clear the sticky override. Return to the catalog pin on the
  next release.
- `=<semver>` — hold at an exact version, even past the curated choice.
  Sticky. Useful for bisecting a regression or waiting out a broken upstream
  release.

If you have used `brew pin`, this is the same idea.

## Why pin at all

Claude Code, GSD, and Playwright publish daily to weekly, and broken versions
do ship — one GSD regression landed, shipped, and got fixed inside a few days.
Anything that always installs the newest version hands you every one of those
regressions the moment it publishes, on whatever morning you happen to run it.

Pinning is the trade you get instead: **we test exactly what we ship, and you
decide when to move.** Running ahead is supported (`pin =latest`), holding
behind is supported (`pin =<semver>`), and reconciling is one flag
(`agentlinux upgrade --reset-all-curated`). What is *not* supported is silent
drift.

## Related

- [Stability-first version pinning with explicit reconciliation](decisions/011-stability-first-version-pinning.md)
  — the full decision record, including considered alternatives (private
  apt/dpkg repo, Nix-style symlink profiles, thin-wrapper baseline).
- [curl-pipe-bash primary + optional .deb distribution](decisions/006-curl-pipe-bash-plus-deb.md)
  — how the release tarball + catalog snapshot + SHA256 sidecar get to users.
- [README.md](../README.md) — the top-level install + verify story.
- [docs/VISION.md — Pillar 2: Stability](VISION.md)
  — the canonical framing this stability model implements. Pillar 2 names what the optimization target is; this doc names the mechanism (the `pinned_version` contract + the explicit reconciliation verbs).
