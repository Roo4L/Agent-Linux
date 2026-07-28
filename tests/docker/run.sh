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
  AGENTLINUX_STAGE_RUST_CLI=1         Re-point the `agentlinux` command symlink
                                      (~agent/.npm-global/bin/agentlinux) at the
                                      staged Rust musl bin AFTER the installer
                                      runs, so the CLI bats exercise the Rust
                                      binary instead of the TS bundle (Phase 56
                                      GATE-01/GATE-05 parallel track). When set
                                      but the Rust bin failed to build/stage, the
                                      run ABORTS (never false-green on TS).

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
  ANTHROPIC_API_KEY # interactive Claude Code behavioral tests
  FOO               # test-secrets convention smoke
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

# Phase 53 (RUST-03 / GATE-01): stage the static-musl `agentlinux` Rust binary
# into the container at an AGENT-OWNED path (NOT a /usr/local shim — that's the
# self-update anti-pattern) so 13-reuse.bats exercises the REAL Rust
# reuse-decision path, not just the bash fallback. The shim
# (plugin/lib/reuse/agents.sh) still falls back to in-shell logic if the binary
# is missing, so a build failure here is non-fatal — it just means the bats
# suite runs the fallback (exactly as master did).
#
# Real per-distro in-container staging lands in Phase 56/57; this host-build +
# copy is the spike's CI proof that the Rust path is green.
RUST_BIN_IN_CONTAINER=/home/agent/.local/bin/agentlinux
RUST_BIN_STAGED=""
echo "== stage Rust agentlinux binary (RUST-03 / GATE-01) =="
HOST_MUSL_BIN="$REPO_ROOT/rust/target/x86_64-unknown-linux-musl/release/agentlinux"
if [[ ! -x $HOST_MUSL_BIN ]]; then
  echo "-- prebuilt musl binary absent; building on host --"
  if command -v cargo >/dev/null 2>&1 || [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091  # optional, path checked
    [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
    (cd "$REPO_ROOT/rust" \
      && cargo build --release --target x86_64-unknown-linux-musl -p agentlinux) \
      || echo "-- WARN: host musl build failed; bats will use the bash fallback --"
  else
    echo "-- WARN: cargo unavailable; bats will use the bash fallback --"
  fi
fi
if [[ -x $HOST_MUSL_BIN ]]; then
  docker exec "$CID" install -d -o agent -g agent /home/agent/.local/bin
  docker cp "$HOST_MUSL_BIN" "$CID:$RUST_BIN_IN_CONTAINER"
  docker exec "$CID" chown agent:agent "$RUST_BIN_IN_CONTAINER"
  docker exec "$CID" chmod +x "$RUST_BIN_IN_CONTAINER"
  RUST_BIN_STAGED=$RUST_BIN_IN_CONTAINER
  echo "-- staged $RUST_BIN_IN_CONTAINER (Rust reuse path active) --"
else
  echo "-- Rust binary not staged; bats will exercise the bash fallback --"
fi

# Phase 56 (GATE-01/GATE-05): flag-gated Rust-CLI symlink override. When
# AGENTLINUX_STAGE_RUST_CLI=1, re-point the `agentlinux` command symlink that the
# provisioner (50-registry-cli.sh:124) set to the TS bundle
# (~agent/.npm-global/bin/agentlinux -> dist/index.js) so it instead points at
# the staged Rust musl bin. This makes the CLI bats (40-registry-cli, etc.)
# exercise the Rust binary AS the `agentlinux` command, not the TS bundle —
# WITHOUT touching plugin/provisioner/50-registry-cli.sh (the provisioner keeps
# symlinking the TS bundle until Phase 57/58). This is a TEST-HARNESS override.
#
# Fail-loud (exit-127 guard / T-56-05): if the override is REQUESTED but the
# Rust bin failed to build/stage, ABORT rather than leave a dangling symlink
# (exit 127 on every agentlinux invocation) or silently keep the TS bundle and
# report a false-green "Rust pass". On master (flag unset) this whole block is
# skipped and the existing non-fatal TS path is preserved.
#
# CLI-01 interactive-mode reconciliation (Phase 56 Wave 3 / GATE-01): the RUST-03
# reuse-path staging above places the Rust bin at ~agent/.local/bin/agentlinux.
# That path is FIRST on the agent's interactive login PATH (Ubuntu's skel
# ~/.profile prepends ~/.local/bin ahead of /etc/profile.d/agentlinux.sh's
# .npm-global/bin), so a bin literally named `agentlinux` there SHADOWS the
# canonical ~agent/.npm-global/bin/agentlinux symlink. On master (TS) nothing is
# staged at .local/bin, so CLI-01's `command -v agentlinux` resolves the
# .npm-global/bin symlink as the contract requires; under the flag it would
# otherwise resolve .local/bin — a HARNESS-staging artifact, NOT a CLI behavior
# change. Fix: when the CLI override is active, RELOCATE the staged bin OFF the
# agent PATH (to /opt/agentlinux/rust/agentlinux, an absolute path the reuse
# shim's AGENTLINUX_RUST_BIN accepts verbatim), drop the front-of-PATH
# .local/bin/agentlinux copy, and point the .npm-global/bin symlink at the
# relocated bin. `command -v agentlinux` then resolves the canonical
# .npm-global/bin symlink (byte-identical to master's TS resolution) while the
# CLI + reuse shim both exercise the Rust bin. The default (flag-unset)
# .local/bin staging for 13-reuse.bats is UNTOUCHED.
CLI_SYMLINK=/home/agent/.npm-global/bin/agentlinux
RUST_BIN_OFFPATH=/opt/agentlinux/rust/agentlinux
if [[ -n ${AGENTLINUX_STAGE_RUST_CLI:-} ]]; then
  if [[ -z $RUST_BIN_STAGED ]]; then
    echo "ERROR: Rust CLI staging requested (AGENTLINUX_STAGE_RUST_CLI=1) but the musl bin is absent — refusing to run bats against the TS bundle and report false-green" >&2
    exit 1
  fi
  echo "== relocate Rust bin off the agent PATH + override CLI symlink (AGENTLINUX_STAGE_RUST_CLI) =="
  # Relocate the staged bin off-PATH so it cannot shadow the canonical symlink
  # by name. cp (not mv) then rm the .local/bin copy so the RUST-03 stage's
  # ownership/mode are preserved on the relocated copy.
  docker exec "$CID" install -d -o agent -g agent /opt/agentlinux/rust
  docker exec "$CID" cp "$RUST_BIN_STAGED" "$RUST_BIN_OFFPATH"
  docker exec "$CID" chown agent:agent "$RUST_BIN_OFFPATH"
  docker exec "$CID" chmod +x "$RUST_BIN_OFFPATH"
  # Drop the front-of-PATH .local/bin/agentlinux copy that would otherwise win
  # `command -v agentlinux` in interactive/login modes.
  docker exec "$CID" rm -f "$RUST_BIN_STAGED"
  RUST_BIN_STAGED=$RUST_BIN_OFFPATH
  docker exec "$CID" ln -sfn "$RUST_BIN_STAGED" "$CLI_SYMLINK"
  docker exec "$CID" chown -h agent:agent "$CLI_SYMLINK"
  echo "-- $CLI_SYMLINK now -> $RUST_BIN_STAGED (off-PATH; CLI bats exercise the Rust bin without shadowing the canonical symlink) --"
fi

echo "== run bats suite (${BATS_TARGET_PATH}) =="
# cd into the staged sources so bats discovers helpers/ relatively. When the
# Rust binary was staged, export AGENTLINUX_RUST_BIN so the reuse shim resolves
# the absolute path (its security-L1 guard rejects a bare relative name).
BATS_ENV=()
if [[ -n $RUST_BIN_STAGED ]]; then
  BATS_ENV=(env "AGENTLINUX_RUST_BIN=$RUST_BIN_STAGED")
fi
set +e
docker exec "$CID" bash -c 'cd /opt/agentlinux-src && '"${BATS_ENV[*]:+${BATS_ENV[*]} }"'bats '"$BATS_TARGET_PATH"
BATS_STATUS=$?
set -e

FINAL_STATUS=$BATS_STATUS
exit "$BATS_STATUS"
