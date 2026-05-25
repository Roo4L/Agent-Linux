#!/usr/bin/env bash
# tests/docker/run.sh — build + run the Docker bats harness for one Ubuntu version.
#
# Invoked by .github/workflows/test.yml and developers locally. This is the
# single CI entrypoint for Phase 2's acceptance gate: it builds the matching
# systemd-capable Docker image, boots it, runs agentlinux-install INSIDE the
# container, then runs the bats suite INSIDE the container, and propagates the
# bats exit code. The installer side-effects that the bats suite asserts are
# therefore observed in the same container the installer ran in.
#
# Refs:
#   - 02-RESEARCH.md §Example 5 (base pattern)
#   - 02-RESEARCH.md §Pitfall 3 (systemd-in-Docker --privileged + --cgroupns=host)
#   - docs/HARNESS.md §1.1 (layout) and §1.3 (testing contract)
#   - ADR-007 (Docker fast-path + QEMU release-gate two-layer harness)
#
# Debugging escape hatch:
#   AGENTLINUX_DOCKER_KEEP_CONTAINER=1 bash tests/docker/run.sh ubuntu-24.04
# leaves the container running after the script exits so you can
# `docker exec -it $CID bash` and poke at state. The container is named
# agentlinux-test-<version> so the ID is easy to find via `docker ps`.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: tests/docker/run.sh <ubuntu-22.04|ubuntu-24.04|ubuntu-26.04>

Builds the matching Docker image, runs agentlinux-install inside, runs the
bats suite inside, and exits with the bats exit code.

Environment:
  AGENTLINUX_DOCKER_KEEP_CONTAINER=1  Skip cleanup (container kept running for
                                      interactive docker exec debugging).

Exit codes:
  0   installer + bats both green
  64  invalid or missing argument
  >0  build, installer, or bats failure (propagated)
EOF
}

UBUNTU_VERSION=${1:-}
if [[ -z $UBUNTU_VERSION ]]; then
  usage
  exit 64
fi
case "$UBUNTU_VERSION" in
  ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'tests/docker/run.sh: unsupported ubuntu version: %s\n' "$UBUNTU_VERSION" >&2
    usage
    exit 64
    ;;
esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
IMG="agentlinux-test:${UBUNTU_VERSION}"
DF="$HERE/Dockerfile.${UBUNTU_VERSION}"

if [[ ! -f $DF ]]; then
  printf 'tests/docker/run.sh: missing Dockerfile %s\n' "$DF" >&2
  exit 64
fi

# Test-secret forwarding. Append rows here in lockstep with .env.local.example
# and docs/internals/test-secrets.md.
SECRET_ALLOWLIST=(
  ANTHROPIC_API_KEY  # interactive Claude Code behavioral tests
  FOO                # test-secrets convention smoke
)

# Source .env.local if present so the allowlist sees vars set there.
# Missing file is silent — per-PR CI has none and require_secret skips yellow.
if [[ -f "$REPO_ROOT/.env.local" ]]; then
  echo "== source .env.local =="
  set -a
  # shellcheck disable=SC1091  # path is dynamic but verified to exist above
  . "$REPO_ROOT/.env.local"
  set +a
fi

# `-e VAR` (no `=value`): docker reads the value from the daemon's view of the
# caller's env, keeping the secret out of every other process's argv.
# `-e "VAR=$VAR"` would interpolate the secret into the docker CLI's argv.
DOCKER_ENV_FLAGS=(-e container=docker)
for var in "${SECRET_ALLOWLIST[@]}"; do
  if [[ -n ${!var-} ]]; then
    DOCKER_ENV_FLAGS+=(-e "$var")
  fi
done

# Fail the final line with a prominent banner so CI log scrollback surfaces
# pass/fail without hunting through docker output.
FINAL_STATUS=1
final_banner() {
  if [[ $FINAL_STATUS -eq 0 ]]; then
    echo "== PASS: agentlinux-install + bats on ${UBUNTU_VERSION} =="
  else
    echo "== FAIL: agentlinux-install + bats on ${UBUNTU_VERSION} (exit ${FINAL_STATUS}) ==" >&2
  fi
}
trap final_banner EXIT

echo "== build ${IMG} from ${DF} =="
# Build context is the repo root. Phase 4 Plan 04-06 added a multi-stage
# `cli-builder` stage to each Dockerfile that runs `pnpm install + pnpm run
# build` against `plugin/cli/`, so the build context needs to include the
# plugin/ tree. The final image is still small: only the compiled dist/ is
# copied from the builder stage (COPY --from=cli-builder) into the Ubuntu
# test image at /opt/cli-prebuilt/dist; source + node_modules stay in the
# throwaway builder layer.
docker build -t "$IMG" -f "$DF" "$REPO_ROOT"

echo "== run systemd container from ${IMG} =="
# --privileged + --cgroupns=host + cgroup bind (rw) + tmpfs on /run,/tmp is the
# documented recipe for PID-1-is-systemd in a container (Pitfall 3).
#
# Two non-obvious requirements the minimum RESEARCH §Example 5 recipe lacked
# (learned by local smoke-test on cgroup-v2 Docker 29.x — Rule 3 auto-fix):
#   1. `-e container=docker`: without this env var, systemd's container
#      detection falls back to inspecting /proc/1/environ and refuses to
#      start as PID 1 ("Trying to run as user instance, but the system has
#      not been booted with systemd"). container=docker is the documented
#      escape hatch for systemd-in-container (see systemd container(7)).
#   2. `/sys/fs/cgroup:rw` (not `:ro`): systemd needs to create its own
#      slice/scope cgroups under the bind-mounted tree. A read-only mount
#      causes systemd to fail before emitting any journal output (container
#      exits 255 with zero log output — the exact symptom observed locally).
#
# Repo is bind-mounted read-only at /workspace; the installer needs to write
# under /etc and /home so it runs against a writable copy under /opt.
# --rm drops the container on stop; -d lets us wait for systemd before exec.
CID=$(docker run --rm -d \
  --privileged \
  --cgroupns=host \
  "${DOCKER_ENV_FLAGS[@]}" \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /tmp \
  -v "$REPO_ROOT":/workspace:ro \
  -w /workspace \
  "$IMG")

cleanup() {
  if [[ -n "${AGENTLINUX_DOCKER_KEEP_CONTAINER:-}" ]]; then
    echo "AGENTLINUX_DOCKER_KEEP_CONTAINER set; leaving ${CID} running" >&2
    return 0
  fi
  docker rm -f "$CID" >/dev/null 2>&1 || true
}
trap 'cleanup; final_banner' EXIT

# Wait up to 30s for systemd to reach a running state. `is-system-running --wait`
# blocks until the system is either `running` or `degraded`; we treat both as
# usable (some masked units in the Dockerfile push the state to `degraded`).
echo "== wait for systemd (up to 30s) =="
for _ in $(seq 1 30); do
  if docker exec "$CID" systemctl is-system-running --wait >/dev/null 2>&1; then
    break
  fi
  # Also accept `degraded` (expected: masked units show as failed on 22.04).
  if docker exec "$CID" sh -c 'state=$(systemctl is-system-running 2>/dev/null || true); case "$state" in running|degraded) exit 0 ;; *) exit 1 ;; esac'; then
    break
  fi
  sleep 1
done

# Copy the read-only mount into a writable /opt/agentlinux-src so the installer
# can place its own files under /etc, /home/agent without cross-mount permission
# surprises. The bind mount under /workspace is deliberately :ro — it's the
# repo root on the host, and we don't want container writes leaking back.
echo "== stage sources into container =="
docker exec "$CID" bash -c 'cp -R /workspace /opt/agentlinux-src'

# Phase 4 Plan 04-06: splice the pre-built CLI bundle from the image's
# builder stage (staged at /opt/cli-prebuilt/{dist,node_modules,package.json})
# into the staged source tree. The host's plugin/cli/dist/ and
# plugin/cli/node_modules/ are gitignored (tsc output + pnpm install output,
# not checked in), so without this splice the 50-registry-cli.sh provisioner
# would fail the "CLI dist/index.js missing" sanity check, or the CLI would
# fail at runtime with ERR_MODULE_NOT_FOUND on `import 'commander'`. The
# splice is idempotent — it runs once per container startup against a
# freshly-copied /opt/agentlinux-src.
echo "== splice pre-built CLI bundle (dist/ + node_modules/ + package.json) into staged sources =="
docker exec "$CID" bash -c '
  set -euo pipefail
  mkdir -p /opt/agentlinux-src/plugin/cli/dist
  mkdir -p /opt/agentlinux-src/plugin/cli/node_modules
  cp -R /opt/cli-prebuilt/dist/. /opt/agentlinux-src/plugin/cli/dist/
  cp -R /opt/cli-prebuilt/node_modules/. /opt/agentlinux-src/plugin/cli/node_modules/
  cp /opt/cli-prebuilt/package.json /opt/agentlinux-src/plugin/cli/package.json
'

echo "== run installer (agentlinux-install) =="
docker exec "$CID" bash /opt/agentlinux-src/plugin/bin/agentlinux-install

echo "== run bats suite (tests/bats/) =="
# cd into the staged sources so bats discovers helpers/ relatively.
set +e
docker exec "$CID" bash -c 'cd /opt/agentlinux-src && bats tests/bats/'
BATS_STATUS=$?
set -e

FINAL_STATUS=$BATS_STATUS
exit "$BATS_STATUS"
