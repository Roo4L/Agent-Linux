# 003: No default agents installed in v0.3.0

**Status:** Accepted
**Date:** 2026-04-18

## Context

v0.2.0 pre-installed Claude Code, GSD, and Chrome DevTools MCP into the distro
image. That coupled the base-system install with the user's choice of agent,
made version upgrades awkward (re-image vs in-place), and conflated "agent
environment" with "specific agent tooling." The plugin model separates base
provisioning from agent selection — the interesting primitive is the
correctly-owned runtime, not any particular agent.

## Decision

v0.3.0 installs zero agents by default. The catalog ships claude-code, gsd, and
playwright as *available* entries; users opt in via `agentlinux install <name>`.
A post-install system has a ready agent user and runtime but no agent binaries.

## Consequences

- Acceptance test AGT-02 (Claude Code self-update without EACCES) requires a
  prior `agentlinux install claude-code` in the test flow; the installer itself
  is not what installs Claude Code.
- Uninstall / remove is symmetric: `agentlinux remove` cleans up what
  `agentlinux install` placed.
- Catalog entries are the opt-in contract; adding a new agent does not require
  editing the CLI source (CAT-03).
