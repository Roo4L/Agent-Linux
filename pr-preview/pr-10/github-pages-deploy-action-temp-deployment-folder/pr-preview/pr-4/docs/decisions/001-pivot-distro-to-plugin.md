# 001: Pivot from custom distro to installable Ubuntu plugin (v0.2.0 → v0.3.0)

**Status:** Accepted
**Date:** 2026-04-18

## Context

v0.2.0 aimed to ship a custom Debian-12 QCOW2 distro with agent tooling pre-baked
as `.deb` packages. Phases 1–4 shipped (Packer image build, Node.js, Chrome,
Claude Code / GSD / MCP fpm packaging) but the distro-as-product shape forces
users to migrate their OS to try AgentLinux — a high-friction path that narrows
reach. An installable extension on top of the user's existing distro delivers
the same agent-user-provisioning value with a fraction of the friction and rides
on top of the existing packaging / update ecosystem.

## Decision

Retire the custom-distro path. Build AgentLinux as an installable plugin for
existing Ubuntu systems (22.04 + 24.04 LTS), starting with v0.3.0.

## Consequences

- Installer shape, distribution mechanism (curl-pipe-bash + optional .deb), and
  registry format become the v0.3.0 questions; Packer / QEMU image build / local
  apt repo / OpenNebula contextualization become N/A.
- Provisioner-script lessons from v0.2.0 (Node.js install patterns, agent-user
  ownership, correct-path wiring) carry forward directly into the plugin.
- Legacy `packer/` directory stays in-tree as read-only reference; final archive
  sweep is deferred to v0.3.1.
