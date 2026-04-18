# 004: Per-user npm prefix as the keystone ownership decision

**Status:** Accepted
**Date:** 2026-04-18

## Context

The primary bug class AgentLinux eliminates is permission failures on `npm
install -g` — EACCES when the npm global prefix lives under a root-owned path
(`/usr` or `/usr/local`). Every downstream workaround (wrapper shims, `sudo npm`,
recursive shim chains) stems from that one misalignment between Node.js ownership
and the user that runs the agent.

## Decision

The installer configures the agent user with an npm global prefix under their
own home (`~/.npm-global` or equivalent) and wires PATH so the prefix's `bin/` is
on PATH in every invocation mode (interactive shell, non-interactive SSH, cron,
systemd, sudo -u). `npm config get prefix` for the agent user must never return
`/usr`, `/usr/local`, or any root-owned path (RT-04).

## Consequences

- `sudo npm install -g` is banned everywhere in installer and catalog code; the
  `security-engineer` review subagent flags it.
- PATH wiring must belt-and-braces across all six invocation modes
  (BHV-01..BHV-06); missing one mode breaks cron / systemd agents silently.
- Uninstall must unwire the prefix and remove the installed binaries without
  touching system-owned files.
