#!/usr/bin/env bash
set -euo pipefail
# gitleaks install.sh — source_kind: binary (Phase 32, DEVT-05).
#
# Installs Gitleaks (secret scanner) from the pinned `gitleaks/gitleaks` GitHub
# release via the shared prebuilt-binary helper (ENABLE-01). The pin is read from
# AGENTLINUX_PINNED_VERSION (ADR-011) — never hardcoded.
#
# gitleaks names its Linux assets `linux_x64` / `linux_arm64` with a per-version
# `gitleaks_<ver>_checksums.txt`, and ships the binary flat at the tarball root. It
# is a self-contained Go binary; a scan needs no daemon and no secret, so nothing is
# baked (Appendix C).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/prebuilt-binary.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"

ver="${AGENTLINUX_PINNED_VERSION}"
arch=$(al_pb_arch "x64" "arm64") || exit 1
base="https://github.com/gitleaks/gitleaks/releases/download/v${ver}"
asset="gitleaks_${ver}_linux_${arch}.tar.gz"
checksums="gitleaks_${ver}_checksums.txt"
bin_in_archive="gitleaks"
bin_name="gitleaks"
dest="${AGENTLINUX_AGENT_HOME}/.local/bin"

echo "gitleaks: installing gitleaks/gitleaks@v${ver} (source_kind binary) to ${dest}"

al_pb_install "$base" "$asset" "$checksums" "$bin_in_archive" "$bin_name" "$dest" "$ver" || {
  echo "gitleaks install: al_pb_install failed for gitleaks/gitleaks@v${ver}" >&2
  exit 1
}

echo "gitleaks: installed at ${dest}/gitleaks"
echo "gitleaks: scan a working tree with, e.g.:  gitleaks dir ."
