#!/usr/bin/env bash
set -euo pipefail
# glab install.sh — source_kind: binary (Phase 30, DEVT-02).
#
# Installs the GitLab CLI from the pinned `gitlab-org/cli` release — the current,
# maintained upstream. NOT the archived `profclems/glab` (DEVT-02): that repo is
# deprecated and its releases are stale, so this recipe resolves gitlab-org/cli
# exclusively.
#
# glab is the one binary tool in this cluster served from GitLab, not GitHub — its
# release download base is gitlab.com/gitlab-org/cli/-/releases/<tag>/downloads.
# The shared helper (ENABLE-01) takes the base URL as a parameter for exactly this
# reason, so no helper change is needed. glab publishes a flat `checksums.txt`
# (not a per-version name) and nests the binary under `bin/glab` in the tarball.
#
# Secrets are NOT baked (Appendix C): `glab auth login` is run by the user post-
# install; this recipe never writes credentials.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/prebuilt-binary.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"

ver="${AGENTLINUX_PINNED_VERSION}"
arch=$(al_pb_arch "amd64" "arm64") || exit 1
base="https://gitlab.com/gitlab-org/cli/-/releases/v${ver}/downloads"
asset="glab_${ver}_linux_${arch}.tar.gz"
checksums="checksums.txt"
bin_in_archive="bin/glab"
bin_name="glab"
dest="${AGENTLINUX_AGENT_HOME}/.local/bin"

echo "glab: installing gitlab-org/cli@v${ver} (source_kind binary) to ${dest}"

al_pb_install "$base" "$asset" "$checksums" "$bin_in_archive" "$bin_name" "$dest" "$ver" || {
  echo "glab install: al_pb_install failed for gitlab-org/cli@v${ver}" >&2
  exit 1
}

echo "glab: installed at ${dest}/glab"
echo "glab: to authenticate, run:  glab auth login"
