#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# product/tests/docker/dogfood.sh — one-command dogfood retest of the curl-pipe-bash
# install path. AL-36.
#
# Builds the minimal Dockerfile.dogfood image with curl + ca-certificates
# preinstalled, runs it under the systemd-in-Docker recipe, fires the real
# curl-pipe-bash against a published release, and exercises the canonical AGT-02
# self-update probe end-to-end.
#
# Usage:
#   product/tests/docker/dogfood.sh                          # ubuntu 24.04, latest stable RC
#   product/tests/docker/dogfood.sh ubuntu-22.04             # 22.04, latest
#   product/tests/docker/dogfood.sh ubuntu-26.04 v0.4.0-rc1  # 26.04, pinned RC
#   product/tests/docker/dogfood.sh -h | --help              # usage
#
# Environment overrides:
#   AGENTLINUX_KEEP_CONTAINER=1   skip teardown (interactive `docker exec`
#                                 debugging — the container ID is printed
#                                 at end-of-run for follow-up).
#   AGENTLINUX_DOGFOOD_TAG        synonym for the second arg; arg wins.
#                                 Unset = install whatever is latest.
#
# Exit codes:
#   0    install + claude install + claude update all green; no EACCES
#   64   bad/missing argument
#   >0   install, agent install, or claude update failure (propagated)
#
# Refs: AL-36; AL-30 (the four installer fixes that made this image possible).

set -euo pipefail
IFS=$'\n\t'

usage() {
  cat >&2 <<'EOF'
usage: product/tests/docker/dogfood.sh [<ubuntu-22.04|ubuntu-24.04|ubuntu-26.04>] [<vX.Y.Z[-suffix]>]

Defaults to ubuntu-24.04 and whatever release is currently latest — the path a
real user takes. Pass a tag to install a specific release instead.

Environment overrides:
  AGENTLINUX_DOGFOOD_TAG=vX.Y.Z-rcN   pin a tag without passing it as the
                                       second argument
  AGENTLINUX_KEEP_CONTAINER=1          skip teardown for interactive
                                       `docker exec` debugging. WARNING:
                                       leaves a privileged container
                                       running; do NOT set in shared CI —
                                       this is intended for dev-laptop
                                       inspection only.

The wrapper exits 0 only if every step (install, claude-code install,
claude --version pre-update, claude update, claude --version post-update)
succeeds AND the captured `claude update` transcript contains zero EACCES
or permission-denied lines. The EACCES check is the AGT-02 release-gate
invariant (see tests/bats/51-agt02-release-gate.bats) and matters because
Anthropic's updater can return exit 0 while still flagging EACCES on a
non-fatal path — that pattern would silently invalidate the dogfood
without the explicit grep.
EOF
}

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
    printf 'product/tests/docker/dogfood.sh: unsupported ubuntu version: %s\n' "$UBUNTU_VERSION" >&2
    usage
    exit 64
    ;;
esac

readonly UBUNTU_NUM=${UBUNTU_VERSION#ubuntu-}

# The release tag to install. EMPTY BY DEFAULT — the installer then resolves
# "latest" itself, which is the path a real user takes and therefore the one
# worth dogfooding.
#
# This used to default to a pinned v0.3.2-rc2 to route around AL-31, where
# unpinned resolution 404'd on the redirect-URL parse. That is fixed
# (`resolve_version` in packaging/curl-installer/install.sh reads
# `%{redirect_url}` instead of following with -L), so the pin now only served to
# test an ancient release. Pass a tag explicitly to install a specific one.
readonly TAG=${2:-${AGENTLINUX_DOGFOOD_TAG:-}}
readonly TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$'
if [[ -n "$TAG" && ! "$TAG" =~ $TAG_REGEX ]]; then
  printf 'product/tests/docker/dogfood.sh: tag fails regex %s: %q\n' "$TAG_REGEX" "$TAG" >&2
  exit 64
fi

# SC2155 split: assign first so a cmdsub failure surfaces as non-zero
# instead of being masked by the readonly wrapper. Same pattern the
# project's bash entrypoint uses for BIN_DIR/LIB_DIR/PROV_DIR.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly HERE
REPO_ROOT=$(cd "$HERE/../../.." && pwd)
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

# Diagnostic dump on any unexpected failure (set -e abort). Runs BEFORE the
# cleanup trap removes the container, so the journal/install-log are still
# reachable. ERR fires per-failed-command under set -e.
err_dump() {
  local rc=$?
  printf '\n== FAIL DIAGNOSTIC (exit %d) ==\n' "$rc" >&2
  printf '\n--- /var/log/agentlinux-install.log (last 80 lines) ---\n' >&2
  docker exec "$CID" sh -c 'tail -n 80 /var/log/agentlinux-install.log 2>/dev/null || echo "(no install log)"' >&2 || true
  printf '\n--- systemd journal (last 80 entries) ---\n' >&2
  docker exec "$CID" journalctl --no-pager -n 80 2>/dev/null >&2 || true
  printf '\n--- claude update transcript (if captured) ---\n' >&2
  if [[ -n "${UPDATE_LOG:-}" && -f "$UPDATE_LOG" ]]; then
    cat "$UPDATE_LOG" >&2
  else
    echo "(no transcript captured — failure occurred before claude update)" >&2
  fi
}
trap err_dump ERR

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

printf '== curl-pipe-bash install (%s) ==\n' "${TAG:-latest}"
# Only pin when a tag was asked for; otherwise let the installer resolve latest.
if [[ -n "$TAG" ]]; then
  docker exec -e "AGENTLINUX_VERSION=$TAG" "$CID" \
    bash -lc 'curl -fsSL https://agentlinux.org/install.sh | bash'
else
  docker exec "$CID" \
    bash -lc 'curl -fsSL https://agentlinux.org/install.sh | bash'
fi

printf '== agentlinux install claude-code ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'agentlinux install claude-code'

printf '== claude --version (post-install) ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'claude --version'

printf '== claude update (AGT-02 release-gate self-update) ==\n'
# Capture the transcript so we can grep it for EACCES / permission-denied
# lines AFTER the update returns. The Anthropic updater is known to exit 0
# while still emitting permission-denied diagnostics on non-fatal recovery
# paths — that pattern would silently invalidate the AGT-02 invariant
# without this explicit grep. Mirrors tests/bats/51-agt02-release-gate.bats
# which tees and runs assert_no_eacces over the captured output.
UPDATE_LOG=$(mktemp -t agentlinux-dogfood-update.XXXXXX)
readonly UPDATE_LOG
docker exec "$CID" sudo -u agent -H bash -lc 'claude update' 2>&1 | tee "$UPDATE_LOG"

if grep -E -i 'EACCES|permission denied' "$UPDATE_LOG" >/dev/null; then
  printf '\nFAIL: claude update transcript contains EACCES / permission-denied lines\n' >&2
  printf '      (AGT-02 release-gate invariant violated — see %s)\n' "$UPDATE_LOG" >&2
  grep -nE -i 'EACCES|permission denied' "$UPDATE_LOG" >&2 || true
  exit 1
fi

printf '== claude --version (post-update) ==\n'
docker exec "$CID" sudo -u agent -H bash -lc 'claude --version'

printf '== claude binary location + ownership ==\n'
# Assert agent:agent ownership explicitly rather than eyeballing `ls -la`.
CLAUDE_OWNER=$(docker exec "$CID" sudo -u agent -H bash -lc 'stat -c "%U:%G" "$(command -v claude)"')
printf 'claude binary owner:group = %s\n' "$CLAUDE_OWNER"
if [[ "$CLAUDE_OWNER" != "agent:agent" ]]; then
  printf '\nFAIL: claude binary not owned by agent:agent (got: %s)\n' "$CLAUDE_OWNER" >&2
  printf '      AGT-02 invariant violated — Claude Code self-update would break.\n' >&2
  exit 1
fi
docker exec "$CID" sudo -u agent -H bash -lc 'ls -la "$(command -v claude)"'

# Clean up transcript on success — only kept when err_dump fires.
rm -f "$UPDATE_LOG"

FINAL_STATUS=0
exit 0
