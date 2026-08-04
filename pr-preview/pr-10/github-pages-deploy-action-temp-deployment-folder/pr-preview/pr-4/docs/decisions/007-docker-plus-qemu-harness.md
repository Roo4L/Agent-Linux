# 007: Docker (fast) + QEMU (release gate) test harness; Docker-only is disqualified

**Status:** Accepted
**Date:** 2026-04-18

## Context

Docker runs bats suites in ~90s per Ubuntu version and gives fast PR feedback.
But Docker containers don't reproduce systemd, locale generation, cloud-init
paths, or real UID allocation — all of which AgentLinux's installer touches. A
Docker-green-only suite has been observed to let real installer bugs (systemd
User=agent unit failures, cloud-init locale breakage) ship to QEMU / real VMs.

## Decision

Two-layer harness. Docker matrix (Ubuntu 22.04 + 24.04) runs on every PR for
fast feedback. QEMU harness boots fresh Ubuntu cloud images, runs the installer
over SSH, and runs bats — mandatory before every release. A red QEMU run blocks
the release workflow (TST-03 / TST-05).

## Consequences

- Two CI surfaces to maintain (`tests/docker/`, `tests/qemu/`) with shared bats
  assertions under `tests/bats/`.
- QEMU runs cost ~5min each; acceptable because they're nightly + release-gate,
  not per-PR.
- Docker-only would be ~40% of the signal; we treat it as fast feedback, not as
  the release gate. The `qa-engineer` subagent enforces that every requirement
  with a Docker test also has the corresponding QEMU coverage by release time.
