#!/usr/bin/env bash
set -euo pipefail
# antigravity-cli install.sh — source_kind: binary.
#
# The official installer tracks the latest release, so this recipe uses the
# official architecture-specific Linux archive and its published SHA-512 from
# the 1.1.4 manifest.
# Keeping the URL and digest together makes the catalog pin reproducible and
# avoids executing an unpinned remote installer as the agent user.
#
# Authentication is deliberately post-install: run `agy` and complete Google
# Sign-In (or the enterprise/SSH flow) in Antigravity. AgentLinux never stores
# or injects a credential.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

readonly EXPECTED_VERSION="1.1.4"
readonly DEST_DIR="${AGENTLINUX_AGENT_HOME}/.local/bin"

if [[ "$AGENTLINUX_PINNED_VERSION" != "$EXPECTED_VERSION" ]]; then
  printf 'antigravity-cli: recipe supports pin %s, catalog requested %s\n' \
    "$EXPECTED_VERSION" "$AGENTLINUX_PINNED_VERSION" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64 | amd64)
    ARCHIVE_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.4-6277569641840640/linux-x64/cli_linux_x64.tar.gz"
    EXPECTED_SHA512="a088a1f231d8565b6673cecd8656fc3504e49c89e9c6b8c4116937b5fe7069c8dcfba78bbb2bc5c0ff8e87ba64fe21b63db7001e3a5794504927dad9e89da973"
    ;;
  aarch64 | arm64)
    ARCHIVE_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.4-6277569641840640/linux-arm/cli_linux_arm64.tar.gz"
    EXPECTED_SHA512="8d3c464303b235b6f2c2d441eca07b0c1cc35efa68f7ae16b167a5a2d49373903efdf686b3e41063424f0cf0c5b5d5eb056f7944dade7abf1b8eb225cb8c438c"
    ;;
  *)
    printf 'antigravity-cli: unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

staging_dir=$(mktemp -d -t agentlinux-antigravity.XXXXXX)
cleanup() {
  rm -rf -- "$staging_dir"
}
trap cleanup EXIT

archive="${staging_dir}/antigravity-cli.tar.gz"
curl -fsSL --proto '=https' --proto-redir '=https' "$ARCHIVE_URL" -o "$archive"

actual_sha512=$(sha512sum "$archive" | awk '{print $1}')
if [[ "$actual_sha512" != "$EXPECTED_SHA512" ]]; then
  printf 'antigravity-cli: SHA-512 mismatch (expected %s, got %s)\n' \
    "$EXPECTED_SHA512" "$actual_sha512" >&2
  exit 1
fi

# Restrict extraction to the exact regular-file member shipped by Google. The
# archive is checked before extraction so a changed payload cannot overwrite a
# path outside the staging directory.
if [[ "$(tar -tzf "$archive")" != "antigravity" ]]; then
  echo 'antigravity-cli: archive does not contain exactly the antigravity binary' >&2
  exit 1
fi
tar -xzf "$archive" --no-same-owner --directory "$staging_dir" antigravity
if [[ ! -f "${staging_dir}/antigravity" || -L "${staging_dir}/antigravity" ]]; then
  echo 'antigravity-cli: extracted payload is not a regular binary' >&2
  exit 1
fi

if [[ -L "${AGENTLINUX_AGENT_HOME}/.local" || -L "$DEST_DIR" ]]; then
  echo 'antigravity-cli: refusing symlinked ~/.local/bin destination' >&2
  exit 1
fi
mkdir -p "$DEST_DIR"
if [[ -L "$DEST_DIR" ]]; then
  echo 'antigravity-cli: refusing symlinked ~/.local/bin destination' >&2
  exit 1
fi
installed_path="${DEST_DIR}/agy"
if [[ -L "$installed_path" ]]; then
  echo 'antigravity-cli: refusing symlinked ~/.local/bin/agy destination' >&2
  exit 1
fi
install -m 0755 "${staging_dir}/antigravity" "$installed_path"
hash -r

version_line=$("$installed_path" --version 2>&1 | head -1)
if ! grep -q -F -- "$AGENTLINUX_PINNED_VERSION" <<<"$version_line"; then
  printf "antigravity-cli: pinned=%s but \`agy --version\`: %s\n" \
    "$AGENTLINUX_PINNED_VERSION" "$version_line" >&2
  exit 1
fi

echo "antigravity-cli: installed agy ${AGENTLINUX_PINNED_VERSION} at ${DEST_DIR}/agy"
echo "antigravity-cli: authenticate after install by running \`agy\` and completing Google Sign-In"
echo 'antigravity-cli: user state under ~/.gemini is preserved on remove'
