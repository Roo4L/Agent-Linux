#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# tests/docker/dogfood.sh — one-command dogfood retest of the curl-pipe-bash
# install path. AL-36.
#
# Replaces the eight-line manual recipe documented in
# .planning/quick/260503-dtx-.../260503-dtx-SUMMARY.md (Path A). Builds the
# minimal Dockerfile.dogfood image with curl + ca-certificates preinstalled,
# runs it under the systemd-in-Docker recipe, exports AGENTLINUX_VERSION
# so the AL-31 unpinned-resolution bug does not bite users of this script
# until it lands on a published RC, fires the curl-pipe-bash, and exercises
# the canonical AGT-02 self-update probe end-to-end.
#
# Usage:
#   tests/docker/dogfood.sh                          # ubuntu 24.04, latest stable RC
#   tests/docker/dogfood.sh ubuntu-22.04             # 22.04, latest
#   tests/docker/dogfood.sh ubuntu-26.04 v0.3.2-rc2  # 26.04, pinned RC
#   tests/docker/dogfood.sh -h | --help              # usage
#
# Environment overrides:
#   AGENTLINUX_KEEP_CONTAINER=1   skip teardown (interactive `docker exec`
#                                 debugging — the container ID is printed
#                                 at end-of-run for follow-up).
#   AGENTLINUX_DOGFOOD_TAG        synonym for the second arg; arg wins.
#
# Exit codes:
#   0    install + claude install + claude update all green; no EACCES
#   64   bad/missing argument
#   >0   install, agent install, or claude update failure (propagated)
#
# Refs: AL-36; AL-30 (the four installer fixes that made this image possible);
#       AL-31 (unpinned-resolution; this wrapper sets AGENTLINUX_VERSION to
#       sidestep it on retests against pre-AL-31 RCs).

set -euo pipefail
IFS=$'\n\t'

usage() {
  cat >&2 <<'EOF'
usage: tests/docker/dogfood.sh [<ubuntu-22.04|ubuntu-24.04|ubuntu-26.04>] [<vX.Y.Z[-suffix]>]

Defaults to ubuntu-24.04 and the most recent stable AgentLinux release.
Pin a specific RC via the second argument to test it.
EOF
}

# Argument parsing.
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

UBUNTU_VERSION=${1:-ubuntu-24.04}
case "$UBUNTU_VERSION" in
  ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04) ;;
  *)
    printf 'tests/docker/dogfood.sh: unsupported ubuntu version: %s\n' "$UBUNTU_VERSION" >&2
    usage
    exit 64
    ;;
esac

# Strip the `ubuntu-` prefix for the docker image build-arg.
readonly UBUNTU_NUM=${UBUNTU_VERSION#ubuntu-}

# Pinned RC tag. AL-31 documents that unpinned curl-bash currently 404s
# on the redirect-URL parse path; this wrapper exports a default tag so the
# dogfood test passes against pre-AL-31 RCs without the user having to
# remember the workaround. Override via second argument or AGENTLINUX_DOGFOOD_TAG.
readonly TAG=${2:-${AGENTLINUX_DOGFOOD_TAG:-v0.3.2-rc2}}
readonly TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$'
if [[ ! "$TAG" =~ $TAG_REGEX ]]; then
  printf 'tests/docker/dogfood.sh: tag fails regex %s: %q\n' "$TAG_REGEX" "$TAG" >&2
  exit 64
fi

# SC2155 split: assign first so a cmdsub failure surfaces as non-zero
# instead of being masked by the readonly wrapper. Same pattern the
# project's bash entrypoint uses for BIN_DIR/LIB_DIR/PROV_DIR.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly HERE
REPO_ROOT=$(cd "$HERE/../.." && pwd)
readonly REPO_ROOT
readonly IMG="agentlinux-dogfood:${UBUNTU_VERSION}"

FINAL_STATUS=1
final_banner() {
  if [[ $FINAL_STATUS -eq 0 ]]; then
    printf '\n== PASS: dogfood (%s, %s) ==\n' "$UBUNTU_VERSION" "$TAG"
  else
    printf '\n== FAIL: dogfood (%s, %s) — exit %d ==\n' \
      "$UBUNTU_VERSION" "$TAG" "$FINAL_STATUS" >&2
  fi
}
trap final_banner EXIT

printf '== build %s (UBUNTU_VERSION=%s) ==\n' "$IMG" "$UBUNTU_NUM"
docker build \
  --build-arg "UBUNTU_VERSION=${UBUNTU_NUM}" \
  -t "$IMG" \
  -f "$HERE/Dockerfile.dogfood" \
  "$REPO_ROOT" >/dev/null

printf '== run systemd container ==\n'
CID=$(docker run --rm -d \
  --privileged \
  --cgroupns=host \
  -e container=docker \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /tmp \
  "$IMG")
readonly CID

cleanup() {
  if [[ -n "${AGENTLINUX_KEEP_CONTAINER:-}" ]]; then
    printf 'AGENTLINUX_KEEP_CONTAINER set; leaving %s running for inspection\n' "$CID" >&2
    return 0
  fi
  docker rm -f "$CID" >/dev/null 2>&1 || true
}
trap 'cleanup; final_banner' EXIT

printf '== wait for systemd (up to 30s) ==\n'
for _ in $(seq 1 30); do
  if docker exec "$CID" systemctl is-system-running --wait >/dev/null 2>&1; then
    break
  fi
  if docker exec "$CID" sh -c \
    'state=$(systemctl is-system-running 2>/dev/null || true); case "$state" in running|degraded) exit 0 ;; *) exit 1 ;; esac'; then
    break
  fi
  sleep 1
done

printf '== curl-pipe-bash install (AGENTLINUX_VERSION=%s) ==\n' "$TAG"
# Pipe the env var explicitly into the docker exec so the inner bash inherits
# it. `-e VAR=value` adds it to the exec environment; the sub-bash invoked by
# `sh -lc` then sees it and exports onward to install.sh.
docker exec -e "AGENTLINUX_VERSION=$TAG" "$CID" \
  bash -lc 'curl -fsSL https://agentlinux.org/install.sh | bash'

printf '== agentlinux install claude-code ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'agentlinux install claude-code'

printf '== claude --version (post-install) ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'claude --version'

printf '== claude update (AGT-02 release-gate self-update) ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'claude update'

printf '== claude --version (post-update) ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'claude --version'

printf '== claude binary location + ownership ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'ls -la $(command -v claude)'

FINAL_STATUS=0
exit 0
