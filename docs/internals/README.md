# AgentLinux Internals

AgentLinux provisions a dedicated `agent` user with a correctly-owned Node.js
runtime so agent tools — Claude Code, GSD, Playwright — self-update without
EACCES, recursive shims, or `sudo` fights. One curl-pipe-bash command on a
clean Ubuntu host turns it into an environment where autonomous coding agents
just work. Each doc in this directory explains what one AgentLinux surface
does and why — the value vs the naive approach you'd otherwise reach for.

## Components

The four foundational layers (everything below the agent catalog):

- [Installer](installer.md) — the curl-pipe-bash entrypoint that downloads,
  verifies, and executes the AgentLinux release tarball.
- [Agent user](agent-user.md) — the dedicated `agent` user with a per-user
  npm prefix that makes self-update Just Work.
- [Sudo drop-in](sudo-drop-in.md) — the `/etc/sudoers.d/agentlinux` NOPASSWD
  grant that lets autonomous agents reach into the host without stalling on
  password prompts.
- [Node.js runtime](nodejs-runtime.md) — system Node.js LTS plus a per-user
  npm prefix and PATH wired across every invocation mode.

The agent catalog and registry CLI:

- [Claude Code](claude-code.md) — Anthropic's coding agent, installed via the
  upstream native installer into the agent's own tree.
- [GSD](gsd.md) — `get-shit-done-cc`, the planning workflow CLI, installed
  via npm into the agent's per-user prefix.
- [Playwright](playwright.md) — browser automation with chromium, installed
  via npm and `playwright install --with-deps`.
- [Registry CLI](registry-cli.md) — the `agentlinux` command that drives
  install / remove / upgrade / pin against the catalog.
- [Catalog](catalog.md) — the curated, version-pinned manifest of available
  agents, snapshotted alongside each release tarball.

## Audience

These docs are written for the project owner first and future contributors
second. They are deliberately product-perspective rather than line-by-line
implementation notes — the goal is a 60-second answer to "what does
AgentLinux do for surface X." The same prose is intended to be excerpt-friendly
source material for blog posts, marketing emails, and the agentlinux.org
landing page; if a paragraph reads cleanly out of context, that is on purpose.

---

See also: [../README.md](../README.md) (top-level install + verify story) and
[../HARNESS.md](../HARNESS.md) (authoritative project harness spec).
