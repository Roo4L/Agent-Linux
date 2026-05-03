---
quick_id: 260503-dtx
description: Cut v0.3.2-rc1 release candidate (bump versions, push tag, document Docker dogfood test)
status: complete
date: 2026-05-03
jira: AL-18
related: [AL-21, AL-29]
pr: 16
tag: v0.3.2-rc1
release_run: https://github.com/Roo4L/Agent-Linux/actions/runs/25277326389
---

# Quick Task 260503-dtx: v0.3.2-rc1 Release Candidate — Summary

## What landed

| Step | Result |
|------|--------|
| Bumped `plugin/cli/package.json` 0.3.0 → 0.3.2 | done — commit `0a78aef` on `release/v0.3.2-rc1-bump` |
| Bumped `plugin/catalog/catalog.json` 0.3.0 → 0.3.2 | done — same commit |
| Opened release PR | done — [#16](https://github.com/Roo4L/Agent-Linux/pull/16) |
| Built `dist/agentlinux-v0.3.2-rc1.tar.gz` (+ `.sha256`, `+ catalog-v0.3.2-rc1.json`) locally | done — sha256 round-trip `OK` |
| Discovered version-string sprawl in plugin source + bats — first CI run on PR #16 failed `CAT-05` because the staged catalog path is computed from `plugin/cli/package.json.version` (0.3.2) but the installer's `AGENTLINUX_VERSION` constant + bats test paths/assertions were still pinned to 0.3.0. Fixed in commit `90f6227` (8 files, +14/-14). | done |
| PR #16 rebased on master after PR #15 merged during CI | done |
| PR #16 merged via rebase → master at `49b8c22` | done — merged 2026-05-03T10:59:07Z |
| Tag `v0.3.2-rc1` pushed (annotated, points at `49b8c22`) | done — `0af0444` |
| `release.yml` triggered (run [25277326389](https://github.com/Roo4L/Agent-Linux/actions/runs/25277326389)) | **in flight** — gate-1 → gate-2 docker → gate-3 qemu → gate-4 pinned-combo → build → publish (~25-40 min total) |
| Reviewers green (bash-engineer, node-engineer, qa-engineer) | done — sweep is mechanical; cosmetic comment-bump deferred to AL-29 |
| Jira: AL-21 → In Review (PR linked); AL-29 sub-task filed for version-string SoT consolidation | done |

## Why this RC took two commits

`scripts/build-release.sh` enforces a three-way version lock between the
tag, `package.json`, and `catalog.json` — but the **runtime** version was
ALSO hardcoded in four other places that the build-release lock didn't
catch:

- `plugin/bin/agentlinux-install` — `readonly AGENTLINUX_VERSION="..."`
  (controls the `/opt/agentlinux/catalog/<ver>/` staging path)
- `plugin/cli/src/index.ts` — Commander's `.version("...")` reply
- `plugin/cli/src/catalog/loader.ts` — `defaultCatalogDir()` fallback
- `plugin/cli/src/catalog/schema.ts` — `resolveSchemaPath()` fallback

Plus four bats test files that hardcoded `/opt/agentlinux/catalog/0.3.0/...`
in path assertions and version-string checks. The previous v0.3.1 release
slipped past this by being a metadata-only tag rename (so release.yml
never built it). v0.3.2-rc1 is the first RC since the public flip that
goes through the full release pipeline, which surfaced the sprawl.

**Follow-up worth a Jira ticket:** consolidate version-string sources so
that exactly one file is the SoT (e.g., have `plugin/bin/agentlinux-install`
read the version from `plugin/cli/package.json` at install time, and have
the bats CAT-05 pattern — read package.json — replicated across all
version-aware tests).

## Tagging step (after PR #16 merges)

Run on a freshly-pulled master:

```bash
git checkout master
git pull --ff-only origin master

# Sanity: master should now contain the bump commit.
node -e 'console.log(require("./plugin/cli/package.json").version)'   # 0.3.2
jq -r .version plugin/catalog/catalog.json                            # 0.3.2

git tag -a v0.3.2-rc1 -m "v0.3.2-rc1 — RC for AL-18 dogfood retest

Patch on top of v0.3.1 carrying the master-merged follow-ups since
the first dogfood failure: PR #7 (three dogfood-discovered installer-
path bugs), PR #5 (Ubuntu 26.04), PR #11 (Node 24 actions), PR #13
(review-reminder Stop hook + ADR-010 refinement, AL-23), PR #14
(workspace-cleanup skill), PR #4/#9/#10 (CI/website-deploy fixes).

Refs: AL-18"

git push origin v0.3.2-rc1
```

That tag push triggers `.github/workflows/release.yml`:
gate-1-precommit → gate-2-docker × {22.04, 24.04, 26.04} → gate-3-qemu →
gate-4-pinned-combo → build → publish (softprops/action-gh-release@v2.6.2).

Track the run with:

```bash
gh run watch --exit-status \
  "$(gh run list --workflow=release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
```

When `publish` lands, the RC tarball + sidecar will be at:

- https://github.com/Roo4L/Agent-Linux/releases/download/v0.3.2-rc1/agentlinux-v0.3.2-rc1.tar.gz
- https://github.com/Roo4L/Agent-Linux/releases/download/v0.3.2-rc1/agentlinux-v0.3.2-rc1.tar.gz.sha256

---

## Docker dogfood test (Ubuntu)

Two test paths. **Path A** is the production-realistic flow — what an end-user
running `curl … | sudo bash` will actually experience. **Path B** runs the
behavior-contract bats suite against the same RC tarball without going through
the public download URL; useful as a pre-publish smoke or when iterating offline.

### Prerequisites (one-time, on your host)

```bash
# Docker engine (any reasonably recent version with cgroup v2 support).
docker version

# A repo checkout pinned to the RC tag, used for Path B (and as the build
# context for Path A's test image).
git fetch --tags origin
git checkout v0.3.2-rc1   # works after the tag is pushed
```

### Path A — curl-pipe-bash dogfood (production-realistic)

This boots a clean systemd-capable Ubuntu container, downloads the published
RC tarball over HTTPS via the curl-installer, runs `agentlinux-install`, and
exercises the canonical Claude Code self-update assertion (AGT-02 — the
exact bug class AgentLinux exists to eliminate).

Repeat the block once per Ubuntu version — `22.04`, `24.04`, and `26.04`.
Bash variable substitution makes it copy-paste-once:

```bash
UBUNTU=ubuntu-24.04   # or ubuntu-22.04 / ubuntu-26.04
RC=v0.3.2-rc1
IMG=agentlinux-test:${UBUNTU}

# Build the systemd-capable test image once. The Dockerfile already includes
# every dependency the installer needs; no plugin source is baked in — the
# container fetches the RC tarball from GitHub at runtime.
docker build -t "$IMG" -f tests/docker/Dockerfile.${UBUNTU} .

# Boot the container as PID-1=systemd. (Same recipe tests/docker/run.sh uses.)
CID=$(docker run --rm -d \
  --privileged --cgroupns=host \
  -e container=docker \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /tmp \
  "$IMG")

# Wait for systemd to settle.
docker exec "$CID" systemctl is-system-running --wait >/dev/null 2>&1 \
  || docker exec "$CID" sh -c 'systemctl is-system-running | grep -qE "running|degraded"'

# Run the curl-pipe-bash installer pinned to the RC tag.
docker exec -e AGENTLINUX_VERSION="$RC" "$CID" bash -c '
  apt-get update -qq && apt-get install -qq -y curl ca-certificates >/dev/null
  curl -fsSL https://agentlinux.org/install.sh | bash
'

# Verify the install (these are the BHV-XX / RT-XX / AGT-XX behaviors).
docker exec "$CID" id agent
docker exec "$CID" sudo -u agent -H bash -lc 'node --version && which agentlinux'
docker exec "$CID" sudo -u agent -H bash -lc 'agentlinux list'
docker exec "$CID" sudo -u agent -H bash -lc 'agentlinux doctor'

# Canonical self-update probe (AGT-02). This is the bug class AgentLinux
# was built to eliminate — it MUST succeed without recursive-shim or EACCES.
docker exec "$CID" sudo -u agent -H bash -lc '
  agentlinux install claude-code &&
  claude --version &&
  claude doctor &&
  printf "AGT-02 self-update probe: OK\n"
'

# Tear down.
docker rm -f "$CID"
```

If any step fails, capture the failure with:

```bash
docker logs "$CID" > /tmp/agentlinux-${UBUNTU}-${RC}.log 2>&1
docker exec "$CID" journalctl -b --no-pager > /tmp/agentlinux-${UBUNTU}-${RC}.journal
```

…and attach both files when you log the regression on AL-18.

> **Override knobs** (rarely needed):
> - `AGENTLINUX_VERSION=v0.3.2-rc1` — pin to a specific RC (used above).
> - `AGENTLINUX_ORG=Roo4L` — point at a fork.
> - `AGENTLINUX_RELEASE_BASE=https://example.invalid/some/path` — override the
>   release base URL entirely (test seam — not for production use).

### Path B — local tarball + bats contract suite

This skips the public download path entirely. It builds the test image from
the *current checkout's* sources, runs the installer inside the container,
then runs the full `tests/bats/` behavior-contract suite — BHV-XX, RT-XX,
AGT-XX, CLI-XX, CAT-XX, INST-XX. Use this to validate the RC against the
spec without waiting for the GitHub Release to publish.

```bash
# Smallest possible smoke (fastest feedback — Ubuntu 24.04).
./tests/docker/run.sh ubuntu-24.04

# Full Docker matrix (mirror what release.yml gate-2-docker runs).
./tests/docker/run.sh ubuntu-22.04
./tests/docker/run.sh ubuntu-24.04
./tests/docker/run.sh ubuntu-26.04
```

A green run ends with:

```
== PASS: agentlinux-install + bats on ubuntu-24.04 ==
```

If you need to poke around after a failure, set `AGENTLINUX_DOCKER_KEEP_CONTAINER=1`:

```bash
AGENTLINUX_DOCKER_KEEP_CONTAINER=1 ./tests/docker/run.sh ubuntu-24.04
docker ps                                 # find the agentlinux-test-* container
docker exec -it <CID> bash                # interactive shell inside the failed env
```

### Decision tree — which path to run when

| Situation | Path |
|-----------|------|
| RC tag pushed but `release.yml` still running | B (sources match the RC because you checked out the tag) |
| `release.yml` finished, RC published | **A then B** — A validates the public download path, B reconfirms the bats contract |
| Something failed in A; want to bisect curl-installer vs installer logic | B (rules out the download/sha256/extract layer) |
| Something failed in B; want to confirm against the public artifact | A (rules out a checkout-vs-tarball drift) |

---

## Acceptance criteria for "RC ready to flip to v0.3.2 final"

1. `release.yml` for `v0.3.2-rc1` ends green (all four gates + build + publish).
2. Path A passes on Ubuntu 22.04 + 24.04 + 26.04.
3. Path B passes on Ubuntu 22.04 + 24.04 + 26.04.
4. The AGT-02 self-update probe (Path A's `claude --version && claude doctor`) succeeds —
   this is the dogfood bug that drove this whole task (AL-18).

If 1-4 all green, cut `v0.3.2` final by re-tagging master (no version-bump
needed — package.json + catalog.json already report `0.3.2`):

```bash
git tag -a v0.3.2 -m "v0.3.2 — first dogfooded GA after AL-18 retest"
git push origin v0.3.2
```

---

## Artifacts

- PLAN: `.planning/quick/260503-dtx-cut-v0-3-2-rc1-release-candidate-bump-ve/260503-dtx-PLAN.md`
- This SUMMARY: same dir, `260503-dtx-SUMMARY.md`
- Local build (built and verified during this task):
  - `dist/agentlinux-v0.3.2-rc1.tar.gz`
  - `dist/agentlinux-v0.3.2-rc1.tar.gz.sha256` (round-trip `OK`)
  - `dist/catalog-v0.3.2-rc1.json`
- Release branch: `release/v0.3.2-rc1-bump` → PR [#16](https://github.com/Roo4L/Agent-Linux/pull/16)

## Open follow-ups

- Discard the dangling `release/v0.4.1-rc1-bump` branch — superseded by the
  patch-level v0.3.2 line. Safe to `git push origin --delete release/v0.4.1-rc1-bump`
  once the tag lands.
- After the dogfood is green, log the AL-18 retest result in Jira and either
  close AL-18 or convert remaining gaps into linked tickets.
