#!/usr/bin/env bash
# tests/qemu/boot.sh — Phase 6 Plan 06-03. QEMU release-gate harness.
#
# End-to-end: download + SHA256-verify Ubuntu cloud image → generate per-run
# ed25519 keypair under mktemp 0700 → render cloud-init seed ISO (user-data +
# meta-data templates from tests/qemu/cloud-init/) → boot QEMU backgrounded
# with `-enable-kvm -snapshot=on` → wait on in-guest `cloud-init status --wait`
# over ssh → scp plugin tarball + tests tarball into the guest → run the
# installer over ssh → run bats tests/bats/ over ssh → collect serial.log
# artifact on failure → `poweroff` + reap QEMU pid → cleanup RUN_DIR via
# EXIT trap.
#
# References:
#   .planning/phases/06-distribution-release-pipeline/06-RESEARCH.md Pattern 4
#   .claude/skills/qemu-harness/SKILL.md §"Target boot flow"
#   docs/decisions/007-docker-plus-qemu-harness.md (ADR-007)
#
# Pitfalls mitigated inline:
#   Pitfall 4  — /dev/kvm fail-fast (silent TCG fallback exceeds CI timeout).
#   Pitfall 10 — SHA256 verify on EVERY cache hit (never trust cached image).
#   T-06-06    — per-run SSH keypair in mktemp 0700, destroyed by EXIT trap.
#
# Usage:
#   tests/qemu/boot.sh <22.04|24.04>
#   tests/qemu/boot.sh ubuntu-22.04            # ubuntu- prefix accepted
#   tests/qemu/boot.sh --help
#
# Environment (all optional):
#   AGENTLINUX_QEMU_CACHE   cache dir for cloud images
#                           (default: $HOME/.cache/agentlinux/qemu)
#   AGENTLINUX_QEMU_TIMEOUT seconds to wait for cloud-init (default: 300)
#   AGENTLINUX_QEMU_MEM     QEMU -m value (default: 2048)
#   AGENTLINUX_QEMU_SMP     QEMU -smp value (default: 2)
#   AGENTLINUX_QEMU_PORT    host port to forward to guest:22 (default: 2222)
#
# Exit codes:
#   0   full run passed (installer + bats both green inside guest)
#   1   runtime failure (cloud-init timeout, bats red, etc.)
#   64  usage error (missing arg, unsupported version, bad flags)
#
# Invoked by:
#   .github/workflows/nightly-qemu.yml matrix job (after KVM udev step).
#   docs/HARNESS.md §1.3 documents local invocation.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Argument parsing.
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
usage: tests/qemu/boot.sh <22.04|24.04>

Runs the AgentLinux QEMU release-gate harness against a fresh Ubuntu cloud
image. Exits 0 on a fully green run (cloud-init seed → installer → bats),
exits 1 on any in-guest failure, exits 64 on bad usage.

Options:
  -h, --help    print this message and exit 0

Environment:
  AGENTLINUX_QEMU_CACHE   cloud-image cache dir ($HOME/.cache/agentlinux/qemu)
  AGENTLINUX_QEMU_TIMEOUT cloud-init wait timeout in seconds (default 300)
  AGENTLINUX_QEMU_MEM     QEMU -m value (default 2048)
  AGENTLINUX_QEMU_SMP     QEMU -smp value (default 2)
  AGENTLINUX_QEMU_PORT    host port forwarded to guest:22 (default 2222)

Examples:
  tests/qemu/boot.sh 22.04
  tests/qemu/boot.sh ubuntu-24.04
  AGENTLINUX_QEMU_CACHE=/tmp/qemu tests/qemu/boot.sh 24.04

Invariants:
  - /dev/kvm MUST be readable+writable (Pitfall 4 — TCG fallback refused).
  - Cloud image SHA256 is re-verified on EVERY cache hit (Pitfall 10).
  - Per-run ssh keypair lives under mktemp 0700 and is destroyed on exit.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  '')
    usage >&2
    exit 64
    ;;
esac

UBUNTU_ARG=$1
# Accept both `22.04` and `ubuntu-22.04` (strip optional `ubuntu-` prefix).
UBUNTU_VERSION=${UBUNTU_ARG#ubuntu-}

# ---------------------------------------------------------------------------
# 1. Locate the cloud-images.txt manifest + resolve URLs for this version.
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGES_MANIFEST="${SCRIPT_DIR}/cloud-images.txt"
if [[ ! -f "$IMAGES_MANIFEST" ]]; then
  printf 'ERROR: cloud-images manifest not found at %s\n' "$IMAGES_MANIFEST" >&2
  exit 1
fi

# Match the leading version field; version dots are escaped in the grep literal.
MANIFEST_LINE=$(grep -E "^${UBUNTU_VERSION//./\\.}[[:space:]]" "$IMAGES_MANIFEST" || true)
if [[ -z "$MANIFEST_LINE" ]]; then
  printf 'ERROR: unsupported Ubuntu version %q (must appear in %s)\n' \
    "$UBUNTU_ARG" "$IMAGES_MANIFEST" >&2
  exit 64
fi
# shellcheck disable=SC2034  # _UV echoed back out of the split for clarity
read -r _UV IMG_URL SHASUMS_URL <<<"$MANIFEST_LINE"

case "$UBUNTU_VERSION" in
  22.04) RELEASE=jammy ;;
  24.04) RELEASE=noble ;;
  *)
    printf 'ERROR: unsupported Ubuntu version %q (no release codename mapping)\n' \
      "$UBUNTU_ARG" >&2
    exit 64
    ;;
esac

# ---------------------------------------------------------------------------
# 2. Fail-fast on /dev/kvm (Pitfall 4).
#    TCG fallback is 20-30x slower and silently blows past the 30-45min CI
#    timeout. Refuse with a loud diagnostic that names the workflow step
#    responsible for KVM access so a failed run self-diagnoses.
# ---------------------------------------------------------------------------
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  cat >&2 <<EOF
ERROR: /dev/kvm is not readable+writable — refusing to run.
       TCG fallback is 20-30x slower than KVM and will exceed the CI timeout.
       On an ubuntu-24.04 GitHub Actions runner, the "Enable /dev/kvm access"
       step in .github/workflows/nightly-qemu.yml must install the udev rule
       before this script runs. Locally, ensure the invoking user is in the
       kvm group and /dev/kvm is mode 0660 (or 0666).
EOF
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Required host tools.
# ---------------------------------------------------------------------------
for tool in qemu-system-x86_64 qemu-img cloud-localds ssh scp ssh-keygen \
  curl sha256sum jq tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'ERROR: required tool %q not found on PATH\n' "$tool" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 4. Cache dir + image paths.
# ---------------------------------------------------------------------------
CACHE=${AGENTLINUX_QEMU_CACHE:-"$HOME/.cache/agentlinux/qemu"}
mkdir -p "$CACHE"
IMG_NAME="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
IMG="${CACHE}/${IMG_NAME}"
SHASUMS="${CACHE}/${RELEASE}-SHA256SUMS"

# Download the cloud image on cold cache; the SHA manifest is refetched on
# EVERY run (Pitfall 10: never trust cached bytes without re-verification).
if [[ ! -f "$IMG" ]]; then
  printf 'fetching %s\n' "$IMG_URL"
  curl -fsSL -o "$IMG" "$IMG_URL"
else
  printf 'using cached image %s\n' "$IMG"
fi

printf 'refreshing SHA256SUMS manifest from %s\n' "$SHASUMS_URL"
curl -fsSL -o "$SHASUMS" "$SHASUMS_URL"

# `sha256sum --ignore-missing --check` only validates the rows whose filenames
# are present in $CACHE — the upstream SHA256SUMS lists many variants; we only
# cache the amd64 server cloudimg.
if ! (cd "$CACHE" && sha256sum --ignore-missing --check "${RELEASE}-SHA256SUMS"); then
  cat >&2 <<EOF
ERROR: cloud image SHA256 mismatch for ${IMG_NAME} — refusing to boot.
       The cached image does not match the upstream manifest. This is either
       a tampered cache or a mid-download corruption. Force a re-download:
         rm -f "${IMG}"
EOF
  exit 1
fi

# ---------------------------------------------------------------------------
# 5. Per-run state dir: ed25519 keypair + rendered seed + serial log.
#    mktemp -d returns mode 0700 already; we belt-and-suspenders with chmod.
#    EXIT trap destroys the whole dir (keypair + logs + seed.iso), including
#    on Ctrl-C or error path.
# ---------------------------------------------------------------------------
RUN_DIR=$(mktemp -d -t agentlinux-qemu.XXXXXX)
chmod 0700 "$RUN_DIR"

QEMU_PID=""
# shellcheck disable=SC2317  # body is invoked via `trap` — shellcheck can't see it
cleanup() {
  local rc=$?
  if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill -TERM "$QEMU_PID" 2>/dev/null || true
    # Brief grace period; then KILL if still running.
    for _ in 1 2 3 4 5; do
      kill -0 "$QEMU_PID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -rf "$RUN_DIR"
  return "$rc"
}
trap cleanup EXIT INT TERM

ssh-keygen -q -t ed25519 -N '' -f "${RUN_DIR}/id_ed25519" -C agentlinux-qemu

# ---------------------------------------------------------------------------
# 6. Render cloud-init seed ISO from the committed templates (Task 1).
# ---------------------------------------------------------------------------
PUBKEY=$(<"${RUN_DIR}/id_ed25519.pub")
INSTANCE_ID="agentlinux-ci-${RELEASE}-$(date +%s)"

# sed delimiter is | because the pubkey never contains | but does contain /.
# PUBKEY is a single-line ssh-ed25519 payload; no escaping of sed metachars
# is necessary (ssh-keygen output is alphanumerics + ` ` + `+/=` base64).
sed "s|__AGENTLINUX_QEMU_PUBKEY__|${PUBKEY}|" \
  "${SCRIPT_DIR}/cloud-init/user-data" >"${RUN_DIR}/user-data"
sed "s|__AGENTLINUX_QEMU_INSTANCE_ID__|${INSTANCE_ID}|" \
  "${SCRIPT_DIR}/cloud-init/meta-data" >"${RUN_DIR}/meta-data"

cloud-localds "${RUN_DIR}/seed.iso" \
  "${RUN_DIR}/user-data" "${RUN_DIR}/meta-data"

# ---------------------------------------------------------------------------
# 7. Boot QEMU backgrounded.
#    `snapshot=on` on the main drive — writes go to a hidden overlay, the
#    cached image is never mutated (Pitfall 10 defense-in-depth).
# ---------------------------------------------------------------------------
QEMU_MEM=${AGENTLINUX_QEMU_MEM:-2048}
QEMU_SMP=${AGENTLINUX_QEMU_SMP:-2}
QEMU_PORT=${AGENTLINUX_QEMU_PORT:-2222}

printf 'booting QEMU (Ubuntu %s / %s; mem=%s smp=%s port=%s)\n' \
  "$UBUNTU_VERSION" "$RELEASE" "$QEMU_MEM" "$QEMU_SMP" "$QEMU_PORT"

## Build a writable qcow2 overlay backed by the cached cloud image.
## `-drive ...,snapshot=on` would also work in theory, but QEMU 8.2+ is
## strict about read-only backing semantics and reports "Block node is
## read-only" on some host filesystems. An explicit overlay is portable
## across QEMU versions and keeps the cached backing file untouched
## (Pitfall 10 defense-in-depth, plus reproducible cache hits).
qemu-img create -q -f qcow2 -F qcow2 -b "${IMG}" "${RUN_DIR}/disk.qcow2"

qemu-system-x86_64 \
  -cpu host -enable-kvm \
  -m "$QEMU_MEM" -smp "$QEMU_SMP" \
  -drive "file=${RUN_DIR}/disk.qcow2,if=virtio,format=qcow2" \
  -drive "file=${RUN_DIR}/seed.iso,format=raw,readonly=on" \
  -netdev "user,id=n0,hostfwd=tcp::${QEMU_PORT}-:22" \
  -device virtio-net,netdev=n0 \
  -nographic -serial "file:${RUN_DIR}/serial.log" \
  -display none \
  &
QEMU_PID=$!

# ---------------------------------------------------------------------------
# 8. Wait for cloud-init to finish.
#    `cloud-init status --wait` blocks inside the guest until ALL user-data
#    steps (including `packages:` apt installs) complete — more reliable than
#    polling port 22, which can be open before bats/jq are installed.
# ---------------------------------------------------------------------------
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=5
  -i "${RUN_DIR}/id_ed25519"
  -p "$QEMU_PORT"
)
SCP_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=5
  -i "${RUN_DIR}/id_ed25519"
  -P "$QEMU_PORT"
)
TIMEOUT=${AGENTLINUX_QEMU_TIMEOUT:-300}
DEADLINE=$((SECONDS + TIMEOUT))

printf 'waiting up to %ds for in-guest cloud-init status --wait\n' "$TIMEOUT"
CLOUD_INIT_OK=0
while ((SECONDS < DEADLINE)); do
  if ssh "${SSH_OPTS[@]}" root@localhost 'cloud-init status --wait' \
    >/dev/null 2>&1; then
    printf 'cloud-init: done\n'
    CLOUD_INIT_OK=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    printf 'ERROR: QEMU process exited before cloud-init finished\n' >&2
    cat "${RUN_DIR}/serial.log" >&2 || true
    exit 1
  fi
  sleep 5
done
if ((CLOUD_INIT_OK == 0)); then
  printf 'ERROR: cloud-init did not finish within %ds\n' "$TIMEOUT" >&2
  tail -n 200 "${RUN_DIR}/serial.log" >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 9. Build the plugin tarball via Plan 06-01's build-release.sh.
#    The three-way version lock (tag == plugin/cli/package.json.version ==
#    plugin/catalog/catalog.json.version) is sacred — do NOT invent a
#    v0.0.0-qemu tag; use the current repo version so the lock passes.
#    SKIP_DEB=1 because fpm is optional and the QEMU harness only needs the
#    .tar.gz (the .deb path is validated in release.yml, not here).
# ---------------------------------------------------------------------------
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
VERSION=$(jq -r .version "${REPO_ROOT}/plugin/cli/package.json")
TAG="v${VERSION}"
printf 'building release tarball for tag=%s via scripts/build-release.sh\n' "$TAG"
SKIP_DEB=1 bash "${REPO_ROOT}/scripts/build-release.sh" "$TAG" --no-deb

TARBALL="${REPO_ROOT}/dist/agentlinux-${TAG}.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
  printf 'ERROR: expected tarball not found at %s\n' "$TARBALL" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 10. scp both tarballs into the guest.
#     The release tarball contains ONLY plugin/ (06-01 locked decision); the
#     bats suite lives under tests/bats/ and is shipped as a second tarball
#     so the in-guest bats run has the tests next to the installed plugin.
# ---------------------------------------------------------------------------
TESTS_TAR="${RUN_DIR}/tests.tar.gz"
tar --create --gzip --file="$TESTS_TAR" -C "$REPO_ROOT" \
  tests/bats \
  node_modules/bats 2>/dev/null || tar --create --gzip --file="$TESTS_TAR" \
  -C "$REPO_ROOT" tests/bats

printf 'scp-ing release tarball + tests into the guest\n'
scp "${SCP_OPTS[@]}" "$TARBALL" "root@localhost:/tmp/"
scp "${SCP_OPTS[@]}" "$TESTS_TAR" "root@localhost:/tmp/tests.tar.gz"

# ---------------------------------------------------------------------------
# 11. Install AgentLinux in-guest (over SSH).
#     `ssh ... bash -s -- "$TAG"` sends the remote script over stdin so we
#     never have to quote-escape the script body through two shells. The
#     positional arg "$TAG" becomes $1 inside the remote script.
# ---------------------------------------------------------------------------
printf 'running plugin/bin/agentlinux-install inside the guest\n'
ssh "${SSH_OPTS[@]}" root@localhost bash -s -- "$TAG" <<'REMOTE_INSTALL'
set -euo pipefail
TAG=$1
mkdir -p /opt/agentlinux-src
cd /opt/agentlinux-src
tar -xzf "/tmp/agentlinux-${TAG}.tar.gz"
tar -xzf /tmp/tests.tar.gz
bash plugin/bin/agentlinux-install
REMOTE_INSTALL

# ---------------------------------------------------------------------------
# 12. Run bats in-guest (full suite — includes AGT-02 release gate 51-*.bats).
# ---------------------------------------------------------------------------
printf 'running bats tests/bats/ inside the guest\n'
BATS_STATUS=0
ssh "${SSH_OPTS[@]}" root@localhost bash -s <<'REMOTE_BATS' || BATS_STATUS=$?
set -euo pipefail
cd /opt/agentlinux-src
if [[ -x node_modules/bats/bin/bats ]]; then
  ./node_modules/bats/bin/bats tests/bats/
else
  bats tests/bats/
fi
REMOTE_BATS

# ---------------------------------------------------------------------------
# 13. Artifacts on failure — copy serial.log into tests/qemu/artifacts/.
# ---------------------------------------------------------------------------
if ((BATS_STATUS != 0)); then
  ARTIFACTS="${REPO_ROOT}/tests/qemu/artifacts"
  mkdir -p "$ARTIFACTS"
  TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
  cp -f "${RUN_DIR}/serial.log" \
    "${ARTIFACTS}/serial-${RELEASE}-${TIMESTAMP}.log" || true
  printf 'ERROR: in-guest bats exited %d on Ubuntu %s; serial log in %s\n' \
    "$BATS_STATUS" "$UBUNTU_VERSION" "$ARTIFACTS" >&2
fi

# ---------------------------------------------------------------------------
# 14. Graceful poweroff; the EXIT trap will reap QEMU_PID.
# ---------------------------------------------------------------------------
ssh "${SSH_OPTS[@]}" root@localhost poweroff 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

exit "$BATS_STATUS"
