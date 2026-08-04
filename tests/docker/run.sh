#!/usr/bin/env bash
# tests/docker/run.sh — build + run the Docker bats harness for one target.
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
# agentlinux-test-<target> so the ID is easy to find via `docker ps`.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: tests/docker/run.sh <ubuntu-22.04|ubuntu-24.04|ubuntu-26.04|almalinux-9> [bats-file]

Builds the matching Docker image, runs agentlinux-install inside, runs the
bats suite inside, and exits with the bats exit code.

Arguments:
  <target>    the distro image to build + boot (required).
  [bats-file] OPTIONAL: a single bats file to run instead of the whole
              tests/bats/ directory (dodges the Docker OOM the full suite hits
              in some VMs). Accepts a bare basename with or without the .bats
              suffix, e.g. `40-registry-cli` or `40-registry-cli.bats`.

Environment:
  AGENTLINUX_DOCKER_KEEP_CONTAINER=1  Skip cleanup (container kept running for
                                      interactive docker exec debugging).

  The run stages the static-musl Rust `agentlinux` bin and runs `provision` AS
  the provisioner (the sole distribution path); the bats exercise Rust with no
  flag. If the musl bin cannot be built/staged the run ABORTS non-zero — it
  NEVER silently false-greens on a missing artifact.

Exit codes:
  0   installer + bats both green
  64  invalid or missing argument
  >0  build, installer, or bats failure (propagated)
EOF
}

TARGET=${1:-}
if [[ -z $TARGET ]]; then
  usage
  exit 64
fi
case "$TARGET" in
  ubuntu-22.04 | ubuntu-24.04 | ubuntu-26.04 | almalinux-9) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'tests/docker/run.sh: unsupported target: %s\n' "$TARGET" >&2
    usage
    exit 64
    ;;
esac

# Optional second positional: a single bats file to run (Docker OOM dodge —
# MEMORY: the full suite OOMs ~test 131 in this VM). Normalize to a bare
# basename with a .bats suffix so both `40-registry-cli` and
# `40-registry-cli.bats` resolve to tests/bats/40-registry-cli.bats. Absent →
# whole-directory run (today's default, unchanged on master).
BATS_FILE=${2:-}
BATS_TARGET_PATH="tests/bats/"
if [[ -n $BATS_FILE ]]; then
  # Strip any leading path + trailing .bats, then re-add the suffix so a stray
  # `tests/bats/40-registry-cli.bats` arg still works.
  BATS_FILE=${BATS_FILE##*/}
  BATS_FILE=${BATS_FILE%.bats}
  BATS_TARGET_PATH="tests/bats/${BATS_FILE}.bats"
fi

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
IMG="agentlinux-test:${TARGET}"
DF="$HERE/Dockerfile.${TARGET}"

if [[ ! -f $DF ]]; then
  printf 'tests/docker/run.sh: missing Dockerfile %s\n' "$DF" >&2
  exit 64
fi

# Test-secret forwarding. Append rows here in lockstep with .env.local.example
# and docs/internals/test-secrets.md.
SECRET_ALLOWLIST=(
  ANTHROPIC_API_KEY  # interactive Claude Code tests; opencode + qwen-code smokes
  OPENAI_API_KEY     # codex smoke (OpenAI-only)
  ANTIGRAVITY_CLI_QA # antigravity-cli smoke
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
    echo "== PASS: agentlinux-install + bats on ${TARGET} =="
  else
    echo "== FAIL: agentlinux-install + bats on ${TARGET} (exit ${FINAL_STATUS}) ==" >&2
  fi
}
trap final_banner EXIT

echo "== build ${IMG} from ${DF} =="
# Build context is the repo root (the Dockerfile stages the systemd test image).
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
#   3. `--tmpfs /tmp:exec` (not the default `--tmpfs /tmp`): Docker mounts a
#      bare tmpfs `noexec`, but the PATH-stub bats harnesses (18-pkg-dispatch,
#      18-detect-el9) write executable stubs under BATS_TEST_TMPDIR
#      (= /tmp/bats-run-*). On a noexec /tmp those stubs cannot execve: bash
#      falls through to the REAL dnf/rpm/curl (exit 0, empty capture -> grep
#      fails) or dies 126 (apt-get on EL9) -> false RED. `:exec` restores the
#      normal-outside-Docker default. SHARED across all rows (the same noexec
#      /tmp silently broke the Debian arm of those files too); do NOT branch
#      it per-target. exec-on-/tmp does not perturb the systemd-in-Docker boot.
#
# Repo is bind-mounted read-only at /workspace; the installer needs to write
# under /etc and /home so it runs against a writable copy under /opt.
# --rm drops the container on stop; -d lets us wait for systemd before exec.
CID=$(docker run --rm -d \
  --privileged \
  --cgroupns=host \
  "${DOCKER_ENV_FLAGS[@]}" \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /tmp:exec \
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

HOST_MUSL_BIN="$REPO_ROOT/rust/target/x86_64-unknown-linux-musl/release/agentlinux"
RUST_PROVISION_BIN_IN_CONTAINER=/usr/local/lib/agentlinux/provision/agentlinux

# host_build_musl — ensure the static-musl `agentlinux` bin exists on the host
# (build it if absent). Shared by the Phase-57 provisioner seam below and the
# Phase-53 RUST-03 reuse staging further down. Non-fatal by itself: callers that
# REQUIRE the bin (the provisioner seam) assert `-x $HOST_MUSL_BIN` afterward and
# fail loud; callers that treat it as optional (the reuse staging) fall back.
host_build_musl() {
  # When cargo is available, ALWAYS (re)build — cargo's incremental compilation
  # makes this a near-noop when nothing changed, and it correctly refreshes a
  # STALE binary after a source edit. The previous `[[ -x ]] && return 0` early
  # return silently staged a stale bin across waves (a false green/red risk on
  # the acceptance oracle). Fall back to an existing prebuilt bin only when cargo
  # is absent (the CI prebuilt-stage path).
  #
  # A FAILED build is fatal here, not a warning. The only downstream guard is
  # `[[ -x $HOST_MUSL_BIN ]]` — existence, not freshness — so with a warm
  # rust/target a compile error left yesterday's binary in place, staged it, ran
  # all 242 tests against code that does not compile, and printed PASS.
  if command -v cargo >/dev/null 2>&1 || [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091  # optional, path checked
    [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
    echo "-- building/refreshing host musl binary (cargo incremental) --"
    if ! (cd "$REPO_ROOT/rust" \
      && cargo build --release --target x86_64-unknown-linux-musl -p agentlinux); then
      echo "ERROR: host musl build FAILED — refusing to run bats against a possibly stale binary" >&2
      exit 1
    fi
  elif [[ -x $HOST_MUSL_BIN ]]; then
    echo "-- cargo unavailable; using existing prebuilt musl binary --"
  else
    echo "-- WARN: cargo unavailable and no prebuilt musl binary --"
  fi
}

# Phase 58 (DIST-01 / GATE-01 / GATE-05): the Rust musl `provision` seam is now
# the DEFAULT provisioner. Wave 2 made the static-musl bin the shipped + staged
# `agentlinux` artifact (registry_cli.rs stages the bin, install.sh execs the
# musl `provision`), so run.sh runs the Rust `provision` AS the provisioner (as
# ROOT — the container exec is root by default; the Rust `provision` uses
# require_root, NOT the CLI-05 guard_agent_user) with NO override. The forward
# AGENTLINUX_PROVISION_RUST flag is folded into this default path — the bats now
# exercise Rust with no flag (GATE-01's intent for this phase).
#
# Fail-loud (no false-green / T-58-07): if the musl bin cannot be built/staged,
# ABORT non-zero rather than silently running bats against a missing artifact.
echo "== run Rust provisioner (agentlinux provision) [default] =="
host_build_musl
if [[ ! -x $HOST_MUSL_BIN ]]; then
  echo "ERROR: the Rust provisioner musl bin is absent — refusing to run bats against a missing artifact and report false-green" >&2
  exit 1
fi
# Stage the provisioner bin at a ROOT-owned path (it runs as root via
# require_root — NOT the agent-owned reuse path). Kept distinct from the
# RUST-03 reuse staging so the two seams never collide.
docker exec "$CID" install -d /usr/local/lib/agentlinux/provision
docker cp "$HOST_MUSL_BIN" "$CID:$RUST_PROVISION_BIN_IN_CONTAINER"
docker exec "$CID" chmod +x "$RUST_PROVISION_BIN_IN_CONTAINER"
# The Rust provisioner's 50-registry-cli step STAGES the shipped musl bin from
# $AGENTLINUX_SRC_ROOT/bin/agentlinux (the tarball payload layout,
# plugin/bin/agentlinux). Splice the built musl bin into the staged src root so
# the provisioner finds the artifact it stages; without it the sanity-check dies
# "release tarball malformed?".
docker exec "$CID" install -d /opt/agentlinux-src/plugin/bin
docker cp "$HOST_MUSL_BIN" "$CID:/opt/agentlinux-src/plugin/bin/agentlinux"
docker exec "$CID" chmod 0755 /opt/agentlinux-src/plugin/bin/agentlinux
# Invoke the `provision` verb as ROOT. The install user defaults to `agent`
# (the AGENTLINUX_USER contract resolve_install_user() honors); pass it
# explicitly.
docker exec "$CID" "$RUST_PROVISION_BIN_IN_CONTAINER" provision --user agent --yes


# Seed the BHV-02 SSH keypair + start sshd BEFORE bats. The 20-agent-user /
# 50-agents suites generate this in their own `setup()`, but 30-runtime.bats does
# NOT — so a PER-FILE `30-runtime` run has no /root/.ssh/id_ed25519 +
# ~agent/.ssh/authorized_keys, the `ssh` invocation mode fails to connect, and the
# INVOKE_MODES loop aborts at `ssh` BEFORE it reaches `sudo_u`/`sudo_u_i` (masking
# those Docker-runnable modes). Seeding here (idempotent — the bats set()s guard on
# key presence) lets the six-mode iteration REACH sudo_u/sudo_u_i on a per-file run.
# This is a TEST-HARNESS seed (mirrors 20-agent-user.bats:29-34); the bats specs are
# untouched. ssh/systemd_user/cron modes themselves are the Phase-59 QEMU gate — a
# green here on the privileged systemd container is a bonus, not a QEMU substitute.
echo "== seed BHV-02 ssh keypair + sshd (idempotent; unblocks the six-mode iteration) =="
docker exec "$CID" bash -c '
  set -e
  # Two INDEPENDENT guards, deliberately. Nesting the authorized_keys install
  # inside the keypair check made "the keypair exists" stand in for "the agent
  # can be reached over ssh" — and at this point in the run the agent user does
  # NOT exist yet (bats provisions it), so `id agent` fails, authorized_keys is
  # skipped, and the keypair is left behind. Every later guard then sees the key
  # present and short-circuits, including 20-agent-user.bats setup(). The result
  # was BHV-02 failing with `Permission denied (publickey,password)` on a host
  # that was otherwise provisioned correctly.
  if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    install -d -m 0700 -o root -g root /root/.ssh
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 -q
  fi
  if id agent >/dev/null 2>&1 && [[ ! -f /home/agent/.ssh/authorized_keys ]]; then
    install -d -m 0700 -o agent -g agent /home/agent/.ssh
    install -m 0600 -o agent -g agent \
      /root/.ssh/id_ed25519.pub /home/agent/.ssh/authorized_keys
  fi
  # Best-effort sshd start (family unit: ssh on Debian, sshd on EL9). Silent on a
  # non-systemd container — the ssh-mode tests then diagnose the connection error.
  systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null || true
' || echo "-- ssh keypair/sshd seed reported a problem (ssh-mode tests will diagnose) --"

echo "== run bats suite (${BATS_TARGET_PATH}) =="
# cd into the staged sources so bats discovers helpers/ relatively.
set +e
docker exec "$CID" bash -c 'cd /opt/agentlinux-src && bats '"$BATS_TARGET_PATH"
BATS_STATUS=$?
set -e

FINAL_STATUS=$BATS_STATUS
exit "$BATS_STATUS"
