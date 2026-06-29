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
# Checksum helpers (HARN-02).
# ---------------------------------------------------------------------------
# verify_one_checksum <cache-dir> <image-filename> <checksums-file>
# Verifies EXACTLY the pinned image against its line in the GNU-format checksums
# file (Ubuntu SHA256SUMS and AlmaLinux CHECKSUM are both `<sha256hex>  <name>`).
# `sha256sum --ignore-missing --check` exits 0 when ZERO listed files are present
# (the HARN-02 false-pass), so instead this REQUIRES the pinned filename's line
# to exist (≥1 row matched) and pipes only that line to `sha256sum --check
# --strict`. A missing line, a malformed line, or a digest mismatch all fail.
verify_one_checksum() {
  local cache=$1 img_name=$2 checksums=$3
  local line
  # Select the line whose FILENAME field equals the pinned image, field-exact
  # via awk (no regex). This is immune to filename metacharacters AND to the two
  # GNU coreutils separator modes: Ubuntu's SHA256SUMS is BINARY mode
  # (`<hash> *name` — the `*` attaches to the last field), AlmaLinux's CHECKSUM
  # is TEXT mode (`<hash>  name`). Both reduce to "$NF is `name` or `*name`".
  # Cloud image filenames contain no whitespace, so $NF is the whole name. awk
  # `exit !found` makes a zero-match return non-zero — the HARN-02 >=1-match gate.
  line=$(awk -v n="$img_name" '$NF==n || $NF=="*"n {print; found=1} END{exit !found}' \
    "$checksums") || {
    printf 'ERROR: %s has no line in %s — cannot verify (HARN-02 >=1-match gate)\n' \
      "$img_name" "$checksums" >&2
    return 1
  }
  # `sha256sum --check --strict` parses both text- and binary-mode lines.
  (cd "$cache" && printf '%s\n' "$line" | sha256sum --check --strict -)
}

# selftest_checksum_guard
# Proves the verification path actually REJECTS corruption, on every run, using a
# tiny synthetic file (no cost to copy the multi-hundred-MB image). Asserts an
# intact check passes, then flips the first byte and asserts the check FAILS. If
# corruption is NOT detected the guard is broken and we refuse to proceed — a
# green run would otherwise be a false pass.
selftest_checksum_guard() {
  local d probe
  d=$(mktemp -d -t agentlinux-cksum.XXXXXX) || return 1
  probe="$d/probe.bin"
  printf 'agentlinux-checksum-guard-probe\n' >"$probe"
  (cd "$d" && sha256sum probe.bin >sums)
  if ! (cd "$d" && sha256sum --check --strict sums) >/dev/null 2>&1; then
    printf 'ERROR: checksum self-test: intact file failed to verify\n' >&2
    rm -rf "$d"
    return 1
  fi
  # Flip the first byte ('a' -> 'b') — a guaranteed content change.
  printf 'b' | dd of="$probe" bs=1 count=1 conv=notrunc status=none
  if (cd "$d" && sha256sum --check --strict sums) >/dev/null 2>&1; then
    printf 'ERROR: checksum self-test: flipped-byte corruption NOT detected — guard broken\n' >&2
    rm -rf "$d"
    return 1
  fi
  rm -rf "$d"
}

# ---------------------------------------------------------------------------
# 0. Argument parsing.
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
usage: tests/qemu/boot.sh <22.04|24.04|26.04|almalinux-9>

Runs the AgentLinux QEMU release-gate harness against a fresh cloud image
(Ubuntu LTS or AlmaLinux 9). Exits 0 on a fully green run (cloud-init seed →
installer → bats), exits 1 on any in-guest failure, exits 64 on bad usage.

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

TARGET_ARG=$1
# Accept `22.04`, `ubuntu-22.04` (Ubuntu rows strip the optional `ubuntu-`
# prefix), and `almalinux-9` (the AlmaLinux row key, used verbatim — it has no
# `ubuntu-` prefix to strip).
TARGET=${TARGET_ARG#ubuntu-}

# ---------------------------------------------------------------------------
# 1. Locate the cloud-images.txt manifest + resolve URLs for this version.
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGES_MANIFEST="${SCRIPT_DIR}/cloud-images.txt"
if [[ ! -f "$IMAGES_MANIFEST" ]]; then
  printf 'ERROR: cloud-images manifest not found at %s\n' "$IMAGES_MANIFEST" >&2
  exit 1
fi

# Match the leading target-key field; dots are escaped in the grep literal.
MANIFEST_LINE=$(grep -E "^${TARGET//./\\.}[[:space:]]" "$IMAGES_MANIFEST" || true)
if [[ -z "$MANIFEST_LINE" ]]; then
  printf 'ERROR: unsupported target %q (must appear in %s)\n' \
    "$TARGET_ARG" "$IMAGES_MANIFEST" >&2
  exit 64
fi
# shellcheck disable=SC2034  # _TK echoed back out of the split for clarity
read -r _TK IMG_URL SHASUMS_URL <<<"$MANIFEST_LINE"

# Family dispatch. FAMILY drives the cloud-init seed (debian: ssh + apt bats;
# rhel: sshd + EPEL bats — see cloud-init/user-data.almalinux9). RELEASE is a
# label used for the instance-id and the failure-artifact filename. The SSH
# model is root@ for BOTH families: AlmaLinux's GenericCloud image ships
# `PermitRootLogin yes` (only the root password is locked), so the in-guest
# installer + bats run as root with no sudo wrapper, byte-equivalent to Ubuntu.
# (Escape hatch if a future EL image drops root key-login: almalinux@ + sudo.)
case "$TARGET" in
  22.04) FAMILY=debian RELEASE=jammy ;;
  24.04) FAMILY=debian RELEASE=noble ;;
  26.04) FAMILY=debian RELEASE=resolute ;;
  almalinux-9) FAMILY=rhel RELEASE=almalinux-9 ;;
  *)
    printf 'ERROR: unsupported target %q (no family/release mapping)\n' \
      "$TARGET_ARG" >&2
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
# Derive the local image filename from the URL basename so both families work
# (Ubuntu `ubuntu-..-cloudimg-amd64.img`, AlmaLinux `AlmaLinux-9-GenericCloud-
# <minor>-<date>.x86_64.qcow2`). The checksums file is cached under a generic
# per-target name (its CONTENT references IMG_NAME; the local name is arbitrary).
IMG_NAME=$(basename "$IMG_URL")
IMG="${CACHE}/${IMG_NAME}"
CHECKSUMS="${CACHE}/${TARGET}.checksums"

# Download the cloud image on cold cache; the checksums manifest is refetched on
# EVERY run (Pitfall 10: never trust cached bytes without re-verification).
if [[ ! -f "$IMG" ]]; then
  printf 'fetching %s\n' "$IMG_URL"
  curl -fsSL -o "$IMG" "$IMG_URL"
else
  printf 'using cached image %s\n' "$IMG"
fi

printf 'refreshing checksums manifest from %s\n' "$SHASUMS_URL"
curl -fsSL -o "$CHECKSUMS" "$SHASUMS_URL"

# HARN-02: first prove the verification path rejects corruption (self-test on a
# synthetic file), then verify the pinned image against its published digest
# with a POSITIVE >=1-match assertion (verify_one_checksum requires the pinned
# filename's line to exist — closing the `--ignore-missing` zero-match false
# pass). Both run on every invocation, including cache hits.
selftest_checksum_guard || exit 1
if ! verify_one_checksum "$CACHE" "$IMG_NAME" "$CHECKSUMS"; then
  cat >&2 <<EOF
ERROR: cloud image SHA256 verification failed for ${IMG_NAME} — refusing to boot.
       Either the cached image does not match the upstream ${SHASUMS_URL##*/}
       manifest (tampered cache / mid-download corruption), or the pinned
       filename is absent from it (image rotated upstream — bump the row in
       tests/qemu/cloud-images.txt). Force a re-download:
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
# Public artifacts dir (CI workflow upload-artifact reads from here on
# failure). Mirrors RUN_DIR contents on cleanup so logs survive RUN_DIR
# teardown. Local runs: empty unless boot.sh exited non-zero.
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
mkdir -p "$ARTIFACTS_DIR"

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
  # On failure: copy logs to public artifacts dir so CI's upload-artifact
  # step can find them. On success: skip (don't pollute artifacts/).
  if [[ "$rc" -ne 0 && -d "$RUN_DIR" ]]; then
    cp -f "${RUN_DIR}/serial.log" "$ARTIFACTS_DIR/serial.log" 2>/dev/null || true
    cp -f "${RUN_DIR}/user-data" "$ARTIFACTS_DIR/user-data" 2>/dev/null || true
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

# Select the family-correct seed template: the EL9 sibling uses `sshd` + EPEL
# bats, the Ubuntu seed uses `ssh` + apt bats. Both carry the same root-pubkey
# placeholder and meta-data contract.
case "$FAMILY" in
  rhel) SEED_TEMPLATE="${SCRIPT_DIR}/cloud-init/user-data.almalinux9" ;;
  debian) SEED_TEMPLATE="${SCRIPT_DIR}/cloud-init/user-data" ;;
esac

# sed delimiter is | because the pubkey never contains | but does contain /.
# PUBKEY is a single-line ssh-ed25519 payload; no escaping of sed metachars
# is necessary (ssh-keygen output is alphanumerics + ` ` + `+/=` base64).
sed "s|__AGENTLINUX_QEMU_PUBKEY__|${PUBKEY}|" \
  "$SEED_TEMPLATE" >"${RUN_DIR}/user-data"
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

printf 'booting QEMU (target %s / %s; mem=%s smp=%s port=%s)\n' \
  "$TARGET" "$RELEASE" "$QEMU_MEM" "$QEMU_SMP" "$QEMU_PORT"

## Build a writable qcow2 overlay backed by the cached cloud image.
## `-drive ...,snapshot=on` would also work in theory, but QEMU 8.2+ is
## strict about read-only backing semantics and reports "Block node is
## read-only" on some host filesystems. An explicit overlay is portable
## across QEMU versions and keeps the cached backing file untouched
## (Pitfall 10 defense-in-depth, plus reproducible cache hits).
qemu-img create -q -f qcow2 -F qcow2 -b "${IMG}" "${RUN_DIR}/disk.qcow2"

## Grow the overlay's virtual size so cloud-init's growpart can resize
## the root filesystem to fit Node.js, npm, claude-code, gsd, playwright,
## chromium (~ 281 MB), and apt cache. Default cloud images are sized for
## minimal install (~ 2 GB usable on 22.04) — too tight for our matrix.
## resize is metadata-only on qcow2; no I/O cost until the guest writes.
qemu-img resize -q "${RUN_DIR}/disk.qcow2" 12G

## -cdrom is the canonical idiom for an attached read-only ISO (cloud-init
## seed). QEMU 8.2 chokes on `-drive ...,format=raw,readonly=on` for the
## seed.iso with "Block node is read-only" — switching to -cdrom is more
## portable and what cloud-init docs recommend.
qemu-system-x86_64 \
  -cpu host -enable-kvm \
  -m "$QEMU_MEM" -smp "$QEMU_SMP" \
  -drive "file=${RUN_DIR}/disk.qcow2,if=virtio,format=qcow2" \
  -cdrom "${RUN_DIR}/seed.iso" \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${QEMU_PORT}-:22" \
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
  # `status --wait` returns non-zero either because sshd isn't up yet OR because
  # cloud-init reached a TERMINAL `error` state (e.g. an EL9 `dnf install` in
  # runcmd failed) — in which case --wait returns immediately and the loop would
  # otherwise spin uselessly to the deadline. Probe the state explicitly and
  # fail fast with the real diagnostic instead of a misleading timeout.
  if ssh "${SSH_OPTS[@]}" root@localhost 'cloud-init status' 2>/dev/null \
    | grep -q 'status: error'; then
    printf 'ERROR: cloud-init reported status: error on the guest — failing fast\n' >&2
    ssh "${SSH_OPTS[@]}" root@localhost 'cloud-init status --long' >&2 2>/dev/null || true
    tail -n 200 "${RUN_DIR}/serial.log" >&2 || true
    exit 1
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

# HARN-02 / EL-06: the milestone's headline is "six invocation modes under
# ENFORCING SELinux". The in-guest bats suite exercises enforcement only
# IMPLICITLY (the non-interactive-SSH mode would fail under sshd_t confinement
# without the guarded restorecon) — so a guest that booted permissive/disabled
# (image rotation, a stray `enforcing=0` cmdline) would pass every mode trivially
# and silently degrade the proof. Assert enforcement explicitly here, on the
# real guest, BEFORE the suite runs. rhel-only; Debian has no SELinux. SELinux is
# never disabled to pass — this is a read-only check.
if [[ "$FAMILY" == rhel ]]; then
  SE_MODE=$(ssh "${SSH_OPTS[@]}" root@localhost getenforce 2>/dev/null || true)
  if [[ "$SE_MODE" != Enforcing ]]; then
    printf 'ERROR: SELinux is %q on the EL9 guest, expected Enforcing — refusing (green-on-permissive is a false pass)\n' \
      "${SE_MODE:-unknown}" >&2
    exit 1
  fi
  printf 'SELinux: Enforcing confirmed on the EL9 guest\n'
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
## tests/bats/60-curl-installer.bats hardcodes
## /opt/agentlinux-src/packaging/curl-installer/install.sh — that file is NOT
## in the plugin/ release tarball (06-01 locked decision: tarball ships
## ONLY plugin/). Bundle packaging/ alongside tests/ so the in-guest layout
## matches what the bats helper expects.
TESTS_TAR="${RUN_DIR}/tests.tar.gz"
tar --create --gzip --file="$TESTS_TAR" -C "$REPO_ROOT" \
  tests/bats packaging \
  node_modules/bats 2>/dev/null || tar --create --gzip --file="$TESTS_TAR" \
  -C "$REPO_ROOT" tests/bats packaging

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
#
# Forward ANTHROPIC_API_KEY into the in-guest bats process so behavioral tests
# that require_secret can run on the release-gate substrate. The host-side
# value arrives via the workflow step-level `env:` block in
# .github/workflows/nightly-qemu.yml; OpenSSH reads it at exec time, so the
# value never appears in this script's body or in any process's argv. Paired
# with the AcceptEnv ANTHROPIC_API_KEY drop-in dropped by
# tests/qemu/cloud-init/user-data (sshd silently drops any SendEnv var not
# named in AcceptEnv — both halves are required).
#
# SendEnv is scoped to this hop ONLY — not the cloud-init wait, not the
# installer dispatch — minimizing the blast radius matches the secret
# pipeline's step-level-env philosophy (see docs/internals/test-secrets.md).
# ---------------------------------------------------------------------------
printf 'running bats tests/bats/ inside the guest\n'
BATS_STATUS=0
ssh -o SendEnv=ANTHROPIC_API_KEY "${SSH_OPTS[@]}" root@localhost bash -s <<'REMOTE_BATS' || BATS_STATUS=$?
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
  printf 'ERROR: in-guest bats exited %d on target %s; serial log in %s\n' \
    "$BATS_STATUS" "$TARGET" "$ARTIFACTS" >&2
fi

# ---------------------------------------------------------------------------
# 14. Graceful poweroff; the EXIT trap will reap QEMU_PID.
# ---------------------------------------------------------------------------
ssh "${SSH_OPTS[@]}" root@localhost poweroff 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

exit "$BATS_STATUS"
