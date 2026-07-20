#!/usr/bin/env bash
set -euo pipefail
# trivy install.sh — source_kind: binary (Phase 31, DEVT-04).
#
# Installs Trivy (vulnerability + secret + misconfig scanner) from the pinned
# `aquasecurity/trivy` GitHub release via the shared prebuilt-binary helper
# (ENABLE-01). The pin is read from AGENTLINUX_PINNED_VERSION (ADR-011) — never
# hardcoded.
#
# Trivy names its Linux assets `Linux-64bit` / `Linux-ARM64` (its own spelling, not
# amd64/arm64) with a per-version `trivy_<ver>_checksums.txt`, and ships the binary
# flat at the tarball root. trivy runs its `fs`/`repo`/`image --input` scans with no
# Docker daemon (DEVT-04) — it is a self-contained Go binary.
#
# No secret is required for local fs/repo scans, so nothing is baked (Appendix C).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/prebuilt-binary.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"

ver="${AGENTLINUX_PINNED_VERSION}"
arch=$(al_pb_arch "64bit" "ARM64") || exit 1
base="https://github.com/aquasecurity/trivy/releases/download/v${ver}"
asset="trivy_${ver}_Linux-${arch}.tar.gz"
checksums="trivy_${ver}_checksums.txt"
bin_in_archive="trivy"
bin_name="trivy"
dest="${AGENTLINUX_AGENT_HOME}/.local/bin"

echo "trivy: installing aquasecurity/trivy@v${ver} (source_kind binary) to ${dest}"

al_pb_install "$base" "$asset" "$checksums" "$bin_in_archive" "$bin_name" "$dest" "$ver" || {
  echo "trivy install: al_pb_install failed for aquasecurity/trivy@v${ver}" >&2
  exit 1
}

echo "trivy: installed at ${dest}/trivy"
echo "trivy: local fs/repo scans need no Docker, e.g.:  trivy fs ."
