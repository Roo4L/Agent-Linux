# 009: Snap is structurally disqualified as a distribution mechanism

**Status:** Accepted
**Date:** 2026-04-18

## Context

Snap packages run confined by default (AppArmor + cgroup restrictions), cannot
write outside the snap's own writable tree without explicit plug declarations,
and cannot run setuid helpers or modify `/etc/sudoers.d/`. AgentLinux's
installer intentionally provisions a new system user, writes a sudoers
drop-in, and manipulates PATH in system-wide shell profiles — all of which Snap's
confinement model forbids. Classic-confinement Snap exists but requires Canonical
store review and is broadly unavailable outside Ubuntu.

## Decision

AgentLinux will not ship as a Snap. Ever. No Snap channel, no snapd integration,
no classic-confinement appeal. Distribution is `curl-pipe-bash` primary + optional
`.deb` only (ADR-006).

## Consequences

- Snap installation path is not tested, documented, or supported.
- `snap install agentlinux` returning "not found" is the correct user
  experience.
- If the user base ever demands Snap, we would revisit as a v1.x decision with
  a fundamentally different installer shape — not a tweak to the current one.
