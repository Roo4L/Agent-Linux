# 005: System Node.js (NodeSource) over version managers (nvm/fnm/volta)

**Status:** Accepted
**Date:** 2026-04-18

## Context

Version managers (nvm, fnm, volta) install Node.js into a shell-activated prefix
and require a shell hook (`eval "$(fnm env)"`, `source ~/.nvm/nvm.sh`) to wire
PATH. That hook only fires in interactive shells. NodeSource installs Node.js
as a system package with a stable PATH entry that works in every invocation
mode.

## Decision

Install Node.js 22 LTS from the official NodeSource apt repository. Do not use
nvm, fnm, volta, or any shell-hook version manager in the AgentLinux plugin.

## Consequences

- nvm/fnm/volta shell-hook activation breaks cron, systemd, and non-interactive
  SSH — the exact invocation modes BHV-02..06 require. System Node.js sidesteps
  the entire class of invocation-mode-dependent PATH bugs.
- Node.js version upgrades follow the distro's apt upgrade cadence, not a
  per-user re-activation flow. Acceptable trade-off because AgentLinux's job is
  a correctly-owned runtime, not bleeding-edge Node features.
- The keystone ownership decision (ADR-004) attaches to the system-installed
  Node.js: the agent user's npm prefix points to their own home, but the Node.js
  binary itself is system-owned.
