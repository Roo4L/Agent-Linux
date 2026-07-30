#!/usr/bin/env bash
# tests/docker/run-smoke.sh — run the OPS-01 operational smokes
# (tests/bats/54-catalog-npm-smoke.bats) inside a provisioned AgentLinux
# container, injecting provider credentials so each catalog tool is exercised
# in a real (minimal) scenario — not just install/version/remove.
#
# Credentials are read from the environment and forwarded to the in-container
# bats process via `docker exec -e` (the values never appear on a command
# line). Two ways to supply them:
#   - Local: drop them in an out-of-repo env file (default
#     ~/.config/agentlinux-smoke.env, KEY=value lines) — sourced here.
#   - CI: set OPENAI_API_KEY / ANTHROPIC_API_KEY / etc. as
#     job env (e.g. from GitHub Actions secrets); no file needed.
# Any credential that is absent makes its @test skip (the suite stays green
# without secrets); ccusage runs unconditionally on seeded local data.
#
# Usage: tests/docker/run-smoke.sh [ubuntu-22.04|ubuntu-24.04|ubuntu-26.04]
#   AGENTLINUX_SMOKE_ENV=/path/to/creds.env  override the creds file location.
set -euo pipefail

UBUNTU_VERSION=${1:-ubuntu-24.04}
case "$UBUNTU_VERSION" in
  ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04) ;;
  *)
    printf 'run-smoke.sh: unsupported ubuntu version: %s\n' "$UBUNTU_VERSION" >&2
    exit 64
    ;;
esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
IMG="agentlinux-test:${UBUNTU_VERSION}"
DF="$HERE/Dockerfile.${UBUNTU_VERSION}"
CREDS=${AGENTLINUX_SMOKE_ENV:-$HOME/.config/agentlinux-smoke.env}

if [[ ! -f $DF ]]; then
  printf 'run-smoke.sh: missing Dockerfile %s\n' "$DF" >&2
  exit 64
fi

# Load credentials from the out-of-repo file when present; otherwise rely on
# whatever is already in the environment (CI path). Never echoed.
if [[ -f $CREDS ]]; then
  echo "== loading credentials from ${CREDS} (values not printed) =="
  set -a
  # shellcheck disable=SC1090
  . "$CREDS"
  set +a
else
  echo "== no creds file at ${CREDS}; using ambient environment (CI mode) =="
fi

echo "== build ${IMG} =="
docker build -t "$IMG" -f "$DF" "$REPO_ROOT" >/dev/null

echo "== run systemd container =="
CID=$(docker run --rm -d --privileged --cgroupns=host -e container=docker \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp \
  -v "$REPO_ROOT":/workspace:ro -w /workspace "$IMG")
cleanup() { docker rm -f "$CID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for _ in $(seq 1 30); do
  if docker exec "$CID" sh -c 'state=$(systemctl is-system-running 2>/dev/null || true); case "$state" in running | degraded) exit 0 ;; *) exit 1 ;; esac'; then
    break
  fi
  sleep 1
done

echo "== stage sources + Rust musl provisioner =="
docker exec "$CID" bash -c 'cp -R /workspace /opt/agentlinux-src'
HOST_MUSL_BIN="$REPO_ROOT/rust/target/x86_64-unknown-linux-musl/release/agentlinux"
# Always rebuild when cargo is available: gating the build on "the binary is
# absent" means a stale binary is never refreshed, so the smoke run silently
# tests whatever was built last.
if command -v cargo >/dev/null 2>&1 || [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
  (cd "$REPO_ROOT/rust" && cargo build --release --target x86_64-unknown-linux-musl -p agentlinux)
fi
[[ -x $HOST_MUSL_BIN ]] || {
  echo "ERROR: the Rust provisioner musl bin is absent — refusing to smoke-test a missing artifact" >&2
  exit 1
}
docker exec "$CID" install -d /opt/agentlinux-src/plugin/bin
docker cp "$HOST_MUSL_BIN" "$CID:/opt/agentlinux-src/plugin/bin/agentlinux"
docker exec "$CID" chmod 0755 /opt/agentlinux-src/plugin/bin/agentlinux

echo "== run Rust provisioner (agentlinux provision) =="
docker exec "$CID" /opt/agentlinux-src/plugin/bin/agentlinux provision --user agent --yes >/dev/null

echo "== run OPS-01 smokes (credentials forwarded by name via -e) =="
set +e
# Forward only the providers the smoke actually consumes (Appendix C routing).
# Add -e DASHSCOPE_API_KEY here if/when a native-Qwen DashScope smoke is added.
docker exec \
  -e OPENAI_API_KEY -e ANTHROPIC_API_KEY -e ANTIGRAVITY_CLI_QA \
  "$CID" bash -c 'cd /opt/agentlinux-src && bats tests/bats/54-catalog-npm-smoke.bats'
RC=$?
set -e
echo "== smoke rc=${RC} =="
exit "$RC"
