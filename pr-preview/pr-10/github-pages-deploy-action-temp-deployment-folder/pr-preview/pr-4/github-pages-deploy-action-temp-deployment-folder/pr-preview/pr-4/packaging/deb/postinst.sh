#!/usr/bin/env bash
# packaging/deb/postinst.sh — Debian postinst hook for the optional .deb
# produced by scripts/build-release.sh via fpm.
#
# Lifecycle: dpkg extracts the .deb payload (plugin/ → /opt/agentlinux/) then
# invokes this script with dpkg's standard postinst args ($1 = "configure",
# optionally $2 = previous-version). fpm wires this as the --after-install
# hook, so the bridge from dpkg → agentlinux-install lives here.
#
# Responsibility: locate /opt/agentlinux/bin/agentlinux-install and exec into
# it. Using `exec` (instead of plain invocation) means the installer's exit
# code replaces this script's — dpkg then sees the real install outcome
# instead of a bash wrapper always exiting 0 (the "dpkg says success but
# installer actually failed" bug class ADR-006 flags).
#
# Why minimal: ADR-006 scopes .deb as OPTIONAL for v0.3.0. If fpm integration
# proves brittle, the curl-pipe-bash channel (tarball + sha256) is the
# authoritative path and this hook is inert. Keeping it tiny minimizes the
# fpm-specific surface under test.
#
# Referenced by:
#   scripts/build-release.sh (fpm --after-install ... packaging/deb/postinst.sh)
#   docs/decisions/006-curl-pipe-bash-plus-deb.md (ADR-006 — .deb optional)

set -euo pipefail

INSTALLER=/opt/agentlinux/bin/agentlinux-install
if [[ ! -x "$INSTALLER" ]]; then
  printf 'postinst: %s missing or not executable; aborting\n' "$INSTALLER" >&2
  exit 1
fi

# Pass dpkg's lifecycle args through so the installer can distinguish a first
# install ($1=configure, $2 unset) from an upgrade ($1=configure, $2=old-ver).
# For v0.3.0 the installer ignores these, but propagating them keeps us
# forward-compatible with ADR-011 reconcile semantics.
exec "$INSTALLER" "$@"
