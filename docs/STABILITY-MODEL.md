# AgentLinux Stability Model

> The user-facing summary of AgentLinux's curated-combo version pinning —
> the full decision record is at [`docs/decisions/011-stability-first-version-pinning.md`](decisions/011-stability-first-version-pinning.md).

AgentLinux ships *curated combos*: every catalog agent is pinned to an exact
version that we test together end-to-end before each release. You install one
combo and everything just works. When you want to run ahead of the curated
pin, you can — and `agentlinux upgrade` + `agentlinux pin` give you a clean
way to reconcile.

## What's a curated combo

Every release bundles a catalog snapshot that AgentLinux CI has exercised
against the full Docker + QEMU matrix before the tag shipped. The snapshot
is staged on disk at `/opt/agentlinux/catalog/<version>/catalog.json` and is
the source of truth for `agentlinux install <name>`.

v0.3.0 pins:

- `claude-code` — **2.1.98** (Anthropic's native installer; self-updates via
  `claude update` into the agent-owned install tree)
- `gsd` (`get-shit-done-cc`) — **1.37.1** (npm global into the agent's
  per-user prefix)
- `playwright` — **1.59.1** (npm global + `playwright install --with-deps
  chromium`; apt-layer runs via the agent user's NOPASSWD sudo drop-in)

The release-gate test installs the full pinned combo on a clean Ubuntu host
and runs the agent bats suite before the tag can publish. A red combo cannot
ship.

## The three divergence states

`agentlinux upgrade` compares three numbers per agent:

- **installed** — what `npm ls -g --json` or the agent's native binary
  reports on disk (the sentinel at `/opt/agentlinux/state/installed.d/<id>.json`
  is cross-checked).
- **curated** — the `pinned_version` from the release's catalog snapshot.
- **upstream latest** — whatever `npm view <pkg> version` resolves (checked
  only when you pass `--check-upstream`; offline-by-default otherwise).

Outcomes:

- `synced` — installed == curated. Nothing to do.
- `override-ahead` — installed > curated. You ran the agent's own updater
  past the pin, or passed `--version` explicitly, or pinned `=latest`.
- `override-behind` — installed < curated. A new AgentLinux release rolled
  the pin forward; you have not yet upgraded.

## Worked example: "I ran `claude update`"

The canonical path. Claude Code ships with its own self-updater that writes
into the agent-owned install tree — that is the whole point of AgentLinux.
After `claude update`, the curated pin and the installed version
disagree; `agentlinux upgrade` surfaces the diff rather than silently
overwriting your choice:

```
$ claude update                               # Claude Code's own updater
✓ Claude Code 2.1.114 installed

$ agentlinux upgrade
Per-agent divergence (report-only; pass --reset-all-curated or per-agent
choice to mutate):

  claude-code  installed=2.1.114  curated=2.1.98   state=override-ahead
  gsd          installed=1.37.1   curated=1.37.1   state=synced
  playwright   installed=1.59.1   curated=1.59.1   state=synced

  Choose per-agent: [keep override] [accept curated] [accept upstream latest]
  Or apply to all: --reset-all-curated | --respect-overrides | --all-latest
```

Choosing `keep override` here marks the entry sticky, so the next release's
`agentlinux upgrade` does not re-nag. `accept curated` downgrades back to the
tested combo. Either is a defensible choice; AgentLinux just refuses to make
it for you silently.

## Escape hatch: `agentlinux pin`

```bash
agentlinux pin claude-code=latest
agentlinux pin claude-code=curated
agentlinux pin gsd=1.38.0
```

- `=latest` — follow upstream for this agent. Sticky. Skipped by
  `agentlinux upgrade --all-latest --respect-overrides`.
- `=curated` — clear the sticky override. Return to the catalog pin on the
  next release.
- `=<semver>` — hold at an exact version, even past the curated choice.
  Sticky. Useful for bisecting a regression or waiting out a broken upstream
  release.

Precedent: Homebrew's `brew pin` + `brew outdated` + `brew upgrade` loop.

## Why pin at all (the trade-off)

Without pinning, AgentLinux would be a thin wrapper around `npm install -g`.
Two problems:

1. **It provides no value over what users could do themselves.** Running
   `sudo -u agent -H npm install -g <pkg>` by hand is a one-liner. A CLI
   that only forwards the call adds no product surface.
2. **Upstream instability hits users immediately.** Claude Code, GSD, and
   Playwright publish daily-to-weekly; broken versions occasionally ship
   (a documented GSD upstream regression surfaced, then shipped, then got
   fixed over the course of a few days). A thin-wrapper AgentLinux would
   always pull the latest — which would expose users to every upstream
   regression the moment it publishes.

Pinning is the explicit contract: **we test exactly what we ship, and you
decide when to move.** Running ahead is supported (`pin =latest`); staying
behind is supported (`pin =<semver>`); reconciling is one command
(`agentlinux upgrade`). What is *not* supported is silent drift.

## Related

- [Stability-first version pinning with explicit reconciliation](decisions/011-stability-first-version-pinning.md)
  — the full decision record, including considered alternatives (private
  apt/dpkg repo, Nix-style symlink profiles, thin-wrapper baseline).
- [curl-pipe-bash primary + optional .deb distribution](decisions/006-curl-pipe-bash-plus-deb.md)
  — how the release tarball + catalog snapshot + SHA256 sidecar get to users.
- [README.md](../README.md) — the top-level install + verify story.
