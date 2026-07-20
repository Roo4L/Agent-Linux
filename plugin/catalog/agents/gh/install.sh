#!/usr/bin/env bash
set -euo pipefail
# gh install.sh — source_kind: binary (Phase 29, DEVT-01).
#
# Installs the GitHub CLI from the pinned `cli/cli` GitHub release. The fetch +
# checksum-verify-before-extract + arch-detect + install logic lives in the shared
# helper plugin/catalog/lib/prebuilt-binary.sh (ENABLE-01); this recipe only names
# gh's release layout and calls al_pb_install. The pin is read from
# AGENTLINUX_PINNED_VERSION (ADR-011 single source of truth) — never hardcoded.
#
# gh's release differs from rtk's in three ways the shared helper is parameterized
# for: the asset uses Go-style os_arch names (`gh_<ver>_linux_amd64.tar.gz`), the
# checksums file is per-version (`gh_<ver>_checksums.txt`), and the binary is nested
# under an arch-named top dir (`gh_<ver>_linux_amd64/bin/gh`) rather than flat.
#
# Secrets are NOT baked (Appendix C): `gh auth login` is run by the user post-
# install; this recipe never writes credentials.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/prebuilt-binary.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"

ver="${AGENTLINUX_PINNED_VERSION}"
arch=$(al_pb_arch "amd64" "arm64") || exit 1
base="https://github.com/cli/cli/releases/download/v${ver}"
asset="gh_${ver}_linux_${arch}.tar.gz"
checksums="gh_${ver}_checksums.txt"
bin_in_archive="gh_${ver}_linux_${arch}/bin/gh"
bin_name="gh"
dest="${AGENTLINUX_AGENT_HOME}/.local/bin"

echo "gh: installing cli/cli@v${ver} (source_kind binary) to ${dest}"

al_pb_install "$base" "$asset" "$checksums" "$bin_in_archive" "$bin_name" "$dest" "$ver" || {
  echo "gh install: al_pb_install failed for cli/cli@v${ver}" >&2
  exit 1
}

echo "gh: installed at ${dest}/gh"
echo "gh: to authenticate, run:  gh auth login"
