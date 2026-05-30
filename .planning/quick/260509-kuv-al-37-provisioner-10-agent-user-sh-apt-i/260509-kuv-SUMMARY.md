---
phase: quick-260509-kuv
plan: 01
status: complete
quick_id: 260509-kuv
description: "AL-37: provisioner 10-agent-user.sh apt install locales fails on empty apt cache — add apt update before install"
started: "2026-05-09T15:01:03Z"
finished: "2026-05-09T15:09:00Z"
commits:
  - f12c94f
  - 86d5cbf
  - 94c4064
files_modified:
  - plugin/provisioner/10-agent-user.sh
  - plugin/provisioner/20-sudoers.sh
  - tests/docker/Dockerfile.dogfood
requirements:
  - AL-37
---

# Quick Task 260509-kuv: AL-37 — apt-get update before gated auto-installs

## What changed

Three atomic commits, three single-file edits, total +21 / -12 lines.

1. **`plugin/provisioner/10-agent-user.sh`** (commit `f12c94f`) — added
   `DEBIAN_FRONTEND=noninteractive apt-get update` inside the
   `if ! command -v locale-gen` auto-install gate, immediately before the
   existing `apt-get install -y --no-install-recommends locales` line.
   Comment block updated to cite AL-37 and reference the canonical pattern
   at `30-nodejs.sh:33`.

2. **`plugin/provisioner/20-sudoers.sh`** (commit `86d5cbf`) — same fix
   shape applied to the `if ! command -v visudo` gate at line 45. The
   `sudo` package install now runs `apt-get update` first. Comment block
   updated to keep the "Mirror the pattern used by 10-agent-user.sh"
   language accurate.

3. **`tests/docker/Dockerfile.dogfood`** (commit `94c4064`) — replaced the
   AL-37 tactical-workaround comment block (which previously instructed
   maintainers NOT to clean apt lists) with a positive-framing comment
   explaining that AL-37 is now fixed and the dogfood image intentionally
   starts with an empty apt cache as permanent regression coverage.
   Added `&& rm -rf /var/lib/apt/lists/*` to the apt-get install RUN.

## Why

Bug class introduced under AL-30 (the four-bug fix bundle): provisioner
steps that auto-install missing prerequisite packages from inside the
installer silently relied on the apt cache being warm. On a freshly
pulled Ubuntu container or a long-idle real Ubuntu host, the cache is
empty and `apt-get install` fails with `Package <name> has no installation
candidate`, aborting the installer.

The bug was masked in earlier dogfood retests because the manual setup
recipe ran `apt-get update` before installing curl, side-effecting a
populated cache that the AgentLinux installer's later `apt-get install`
rode on. AL-36's minimal-prereqs Dockerfile.dogfood surfaced AL-37 by
NOT running that pre-update — but ironically the file then carried a
tactical workaround keeping `/var/lib/apt/lists/` populated, because the
strategic fix (this AL-37 commit) hadn't landed yet.

`30-nodejs.sh:33` already had the correct pattern:
`DEBIAN_FRONTEND=noninteractive apt-get update` then
`DEBIAN_FRONTEND=noninteractive apt-get install`. AL-37 propagates that
pattern to the two remaining gated auto-install branches and removes the
tactical workaround in Dockerfile.dogfood.

## Validation

End-to-end Docker reproduction (the AL-37 acceptance scenario):

```text
docker build -t agentlinux-dogfood-al37:24.04 -f tests/docker/Dockerfile.dogfood ...
# Image starting state — verified before installer run:
#   /var/lib/apt/lists/ : 0 files (empty cache)
#   locale-gen           : ABSENT (gate will fire)
#   visudo               : ABSENT (gate will fire)

docker run -d --privileged --cgroupns=host \
  -e container=docker -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /tmp -v "$PWD":/workspace:ro \
  agentlinux-dogfood-al37:24.04
# (systemd reaches running state in ~3s)

docker exec "$CID" cp -R /workspace /opt/agentlinux-src
docker exec "$CID" bash /opt/agentlinux-src/plugin/bin/agentlinux-install
# ↳ runs the LOCAL worktree code (not the published RC)
```

Installer log assertions (full log captured at `/tmp/al37-install.log`
during validation; representative excerpts):

```text
[INFO]  10-agent-user: starting
[INFO]  created user agent (home /home/agent, shell /bin/bash)
[WARN]  locale-gen not found; installing 'locales' package
Get:1 http://archive.ubuntu.com/ubuntu noble InRelease [256 kB]
... (full apt-get update transcript) ...
Setting up locales (2.39-0ubuntu8.7) ...
Generating locales (this might take a while)...
Generation complete.
[INFO]  locale C.UTF-8 enforced (LANG + LC_ALL in /etc/default/locale)
[INFO]  10-agent-user: done
[INFO]  20-sudoers: starting
[WARN]  visudo not found; installing 'sudo' package
Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease
... (apt-get update fast-path with populated cache from step 1) ...
Setting up sudo (1.9.15p5-3ubuntu5.24.04.2) ...
[INFO]  wrote /etc/sudoers.d/agentlinux (mode 0440 root:root — ADR-012)
[INFO]  20-sudoers: done
[INFO]  30-nodejs: done
[INFO]  40-path-wiring: done (four artefacts written)
```

AL-37 acceptance assertions (mechanical grep over the captured log):

| Assertion | Result |
|---|---|
| Zero "no installation candidate" matches in installer log | **0 / pass** |
| `apt-get update` ran (Get:/Hit: lines after each WARN) | 66 matches / pass |
| `Setting up locales` reached | present / pass |
| `locale C.UTF-8 enforced` reached | present / pass |
| `Setting up sudo` reached | present / pass |
| `wrote /etc/sudoers.d/agentlinux` reached | present / pass |
| 10/20/30/40 provisioners all show "done" | 4/4 / pass |

The trailing `50-registry-cli.sh` step did fail in the local validation
run with `CLI dist/index.js missing at /opt/agentlinux-src/plugin/cli/dist`,
but that is unrelated to AL-37 — it is the gitignored CLI bundle (output
of `pnpm build`). The Phase 4 `Dockerfile.ubuntu-XX.04` matrix images
splice a pre-built CLI bundle into the staged source tree before invoking
the installer (see `tests/docker/run.sh:161-169`); AL-37's local validation
intentionally bypassed that step because it was specifically reproducing
the AL-37 bug scenario, not the full bats matrix. The published curl-
pipe-bash flow ships the pre-built CLI in the release tarball and is
unaffected.

## Static gates

- `bash -n` clean on both edited provisioner shell scripts
- `shellcheck plugin/provisioner/10-agent-user.sh plugin/provisioner/20-sudoers.sh` clean
- `docker build` of `Dockerfile.dogfood` succeeds against ubuntu:24.04
- Diff stat: 3 files changed, 21 insertions(+), 12 deletions(-)

## Pitfalls navigated

- **Strict-mode propagation preserved.** No `|| true` on the new
  apt-get update lines — a real apt failure (network outage, GPG expiry,
  broken sources) surfaces as an installer ERR-trap with src:line
  attribution. Silencing it would mask exactly the bug class AL-37 is
  fixing.

- **Sourced-fragment contract preserved.** Both provisioners are sourced
  by `plugin/bin/agentlinux-install` and inherit `set -euo pipefail` from
  the entrypoint; their file headers explicitly forbid setting strict-
  mode flags themselves. Edit footprint is one statement insertion per
  file — no header changes.

- **Gate placement preserved.** The new `apt-get update` lives INSIDE
  the `if ! command -v <X>; then` block, not before it. On hosts where
  the prereq is already installed (steady state for re-runs and non-slim
  images), neither the update nor the install runs — the gate's no-op
  property is intact. `30-nodejs.sh` runs `apt-get update`
  unconditionally because nodejs is always installed by the AgentLinux
  installer; locales/sudo are only auto-installed when missing.

- **Dockerfile.dogfood scope.** Only the dogfood image cleans
  `/var/lib/apt/lists/`. The heavier `Dockerfile.ubuntu-{22,24,26}.04`
  bats CI images keep the cache populated because the bats setup steps
  rely on it for reasons unrelated to AL-37.

## Refs

- AL-37 (this fix)
- AL-30 (introduced the auto-install pattern this exposes — four-bug fix
  bundle that landed the `command -v` gates without the matching
  `apt-get update`)
- AL-36 (added `tests/docker/Dockerfile.dogfood` and surfaced AL-37 in
  the first dogfood retest with a clean substrate)
- ADR-012 (agent-user passwordless sudo — the broader context for
  20-sudoers.sh)
