#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# tests/docker/rc-sandbox.sh — interactive local sandbox for hand-testing a
# release candidate you built yourself, without publishing anything to GitHub.
#
# Three-step workflow:
#
#   tests/docker/rc-sandbox.sh up          # 1. spin up a systemd Ubuntu container
#   tests/docker/rc-sandbox.sh install     # 2. install the RC tarball from dist/
#   tests/docker/rc-sandbox.sh shell       # 3. drop into a shell as the agent user
#
# Then, inside the shell, run whatever you like:
#   agentlinux list
#   agentlinux list --by-category
#   agentlinux install codex
#   agentlinux remove codex
#
# `down` tears the container down when you are finished.
#
# How it differs from dogfood.sh: dogfood.sh is a one-shot automated gate that
# curls a PUBLISHED release off agentlinux.org and asserts the claude self-update
# invariant. This script installs a tarball you built LOCALLY (dist/), stays up,
# and hands you an interactive prompt — it reuses dogfood.sh's Dockerfile and the
# same systemd-in-Docker recipe, but the loop is yours to drive.
#
# The install path is the REAL curl-pipe-bash installer
# (packaging/curl-installer/install.sh) pointed at the local tarball via the
# AGENTLINUX_RELEASE_BASE=file:// seam — so SHA256 verification, gzip-magic
# checks, extraction and hand-off all run exactly as they would for a user who
# ran `curl https://agentlinux.org/install.sh | sudo bash`.
#
# NOTE: openclaw and hermes-agent are per-user systemd DAEMONS. This container
# masks systemd-logind (no per-user bus), so `agentlinux install openclaw` /
# `hermes-agent` degrade to config-only or fail the daemon step. That is a
# Docker-substrate limitation (Docker can't reproduce per-user systemd), NOT an
# AgentLinux bug — those two are validated under the QEMU harness. Every other
# catalog entry (coding CLIs, MCP servers, DevOps tools, token/workflow tools)
# installs and runs normally here.
#
# Usage:
#   rc-sandbox.sh up   [ubuntu-22.04|ubuntu-24.04|ubuntu-26.04]   (default 24.04)
#   rc-sandbox.sh install [<path-to-tarball>]   (default: newest dist/agentlinux-*.tar.gz)
#   rc-sandbox.sh shell
#   rc-sandbox.sh run  <command…>    (run one command as the agent user, non-interactive)
#   rc-sandbox.sh status
#   rc-sandbox.sh down
#
# Environment:
#   AGENTLINUX_RC_CONTAINER   container name (default: agentlinux-rc)

set -euo pipefail
IFS=$'\n\t'

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly HERE
REPO_ROOT=$(cd "$HERE/../.." && pwd)
readonly REPO_ROOT
readonly CONTAINER=${AGENTLINUX_RC_CONTAINER:-agentlinux-rc}
readonly UBUNTU_DEFAULT=ubuntu-24.04

die() {
  printf 'rc-sandbox: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '6,49p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == "true" ]]
}

require_running() {
  container_running || die "container '$CONTAINER' is not running — run: $(basename "$0") up"
}

cmd_up() {
  local ubuntu=${1:-$UBUNTU_DEFAULT}
  case "$ubuntu" in
    ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04) ;;
    *) die "unsupported ubuntu version: $ubuntu (use ubuntu-22.04|24.04|26.04)" ;;
  esac

  if container_running; then
    printf 'rc-sandbox: container %s already running — reusing it (run `down` to reset)\n' "$CONTAINER"
    return 0
  fi
  # A stopped container with the same name would block `docker run --name`.
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

  local num=${ubuntu#ubuntu-}
  local img="agentlinux-rc:${ubuntu}"
  printf '== build image %s ==\n' "$img"
  docker build --build-arg "UBUNTU_VERSION=${num}" -t "$img" \
    -f "$HERE/Dockerfile.dogfood" "$REPO_ROOT" >/dev/null

  printf '== start systemd container %s ==\n' "$CONTAINER"
  docker run -d --name "$CONTAINER" \
    --privileged --cgroupns=host \
    -e container=docker \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /tmp \
    "$img" >/dev/null

  printf '== wait for systemd (up to 30s) ==\n'
  local ready=
  for _ in $(seq 1 30); do
    # `is-system-running --wait` blocks until startup *finishes* before we read
    # the state, so we never accept a transient early `degraded` while units are
    # still activating (this image ends up degraded permanently — logind masked).
    if docker exec "$CONTAINER" sh -c \
      'systemctl is-system-running --wait >/dev/null 2>&1 || true
       case "$(systemctl is-system-running 2>/dev/null || true)" in running|degraded) exit 0 ;; *) exit 1 ;; esac'; then
      ready=1
      break
    fi
    sleep 1
  done
  [[ -n "$ready" ]] || die "systemd did not reach running/degraded within 30s (check: docker logs $CONTAINER)"
  printf 'rc-sandbox: container up. Next: %s install\n' "$(basename "$0")"
}

cmd_install() {
  require_running

  local tarball=${1:-}
  if [[ -z "$tarball" ]]; then
    # newest by mtime
    tarball=$(ls -1t "$REPO_ROOT"/dist/agentlinux-*.tar.gz 2>/dev/null | head -1 || true)
  fi
  [[ -n "$tarball" && -f "$tarball" ]] \
    || die "no RC tarball found — build one first, e.g.:
    SKIP_DEB=1 scripts/build-release.sh v0.3.6-rc1 --no-deb
  (then re-run: $(basename "$0") install)"
  [[ -f "${tarball}.sha256" ]] \
    || die "missing sidecar ${tarball}.sha256 (rebuild via scripts/build-release.sh)"

  local base tag
  base=$(basename "$tarball")          # agentlinux-v0.3.6-rc1.tar.gz
  tag=${base#agentlinux-}
  tag=${tag%.tar.gz}                    # v0.3.6-rc1
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] \
    || die "tarball name '$base' does not encode a vX.Y.Z[-suffix] tag"

  # A second `install` re-runs the installer over an existing tree — that is the
  # rerun/converge path (INST-02), NOT a fresh install. Say so, so a re-test
  # after a code change is not mistaken for a clean-slate result.
  if docker exec "$CONTAINER" test -d /opt/agentlinux 2>/dev/null; then
    printf 'rc-sandbox: NOTE — AgentLinux already present; this re-runs the installer\n'
    printf '           (exercises the rerun/converge path, not a fresh install).\n'
    printf '           For a clean fresh-install test: %s down && %s up\n' \
      "$(basename "$0")" "$(basename "$0")"
  fi

  printf '== stage %s into container (%s) ==\n' "$base" "$tag"
  docker exec "$CONTAINER" mkdir -p "/opt/rc/${tag}"
  docker cp "$tarball" "$CONTAINER:/opt/rc/${tag}/"
  docker cp "${tarball}.sha256" "$CONTAINER:/opt/rc/${tag}/"

  printf '== run the real curl-pipe-bash installer against the local tarball ==\n'
  # Pipe the actual installer over stdin — this is byte-for-byte the code path a
  # user hits with `curl … | sudo bash`, except the release base is a local
  # file:// dir instead of GitHub. AGENTLINUX_VERSION short-circuits the network
  # version-resolution; AGENTLINUX_RELEASE_BASE points at the staged tarball.
  docker exec -i \
    -e "AGENTLINUX_VERSION=${tag}" \
    -e "AGENTLINUX_RELEASE_BASE=file:///opt/rc" \
    "$CONTAINER" bash < "$REPO_ROOT/packaging/curl-installer/install.sh"

  printf '\n== installed — sanity check ==\n'
  docker exec "$CONTAINER" sudo -u agent -H bash -lc \
    'agentlinux --version; echo; agentlinux list | head -n 8; echo "…"'
  # Assert (not just display): a working install must enumerate ≥1 catalog entry.
  # A broken-but-on-PATH agentlinux yields 0 here — fail loudly rather than hand
  # the user a container that looks ready but is not.
  local count
  count=$(docker exec "$CONTAINER" sudo -u agent -H bash -lc \
    'agentlinux list --json 2>/dev/null | grep -c "\"id\""' || true)
  [[ "$count" =~ ^[0-9]+$ && "$count" -ge 1 ]] \
    || die "sanity check failed: agentlinux enumerated '${count:-0}' catalog entries (expected ≥1) — install looks broken"
  printf 'catalog entries: %s — OK\n' "$count"
  printf '\nrc-sandbox: ready. Next: %s shell   (or: %s run "agentlinux list")\n' \
    "$(basename "$0")" "$(basename "$0")"
}

cmd_shell() {
  require_running
  printf 'rc-sandbox: entering %s as the agent user (Ctrl-D to exit)\n' "$CONTAINER"
  docker exec -it "$CONTAINER" sudo -iu agent
}

cmd_run() {
  require_running
  [[ $# -ge 1 ]] || die "run: needs a command, e.g. run 'agentlinux list --by-category'"
  docker exec "$CONTAINER" sudo -u agent -H bash -lc "$*"
}

cmd_status() {
  if container_running; then
    printf 'rc-sandbox: %s is running\n' "$CONTAINER"
    docker exec "$CONTAINER" sudo -u agent -H bash -lc \
      'command -v agentlinux >/dev/null && agentlinux --version || echo "AgentLinux not installed yet (run: install)"'
  else
    printf 'rc-sandbox: %s is not running (run: up)\n' "$CONTAINER"
  fi
}

cmd_down() {
  # Check existence first so a real docker error (daemon down, permission) is
  # NOT swallowed and misreported as "nothing to remove".
  if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    printf 'rc-sandbox: nothing to remove (%s not present)\n' "$CONTAINER"
    return 0
  fi
  docker rm -f "$CONTAINER" >/dev/null
  printf 'rc-sandbox: removed %s\n' "$CONTAINER"
}

main() {
  command -v docker >/dev/null 2>&1 || die "docker not found on PATH"
  local sub=${1:-}
  [[ $# -gt 0 ]] && shift || true
  case "$sub" in
    up) cmd_up "$@" ;;
    install) cmd_install "$@" ;;
    shell) cmd_shell ;;
    run) cmd_run "$@" ;;
    status) cmd_status ;;
    down) cmd_down ;;
    -h | --help | help | '') usage ;;
    *) die "unknown subcommand: $sub (try: $(basename "$0") --help)" ;;
  esac
}

main "$@"
