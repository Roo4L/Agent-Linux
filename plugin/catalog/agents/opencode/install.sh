#!/usr/bin/env bash
set -euo pipefail
# opencode install.sh — real body (Phase 25, AGT-05).
#
# npm_package_name: opencode-ai (verified 2026-06-29 via npm view).
#   npm view opencode-ai@1.17.11 bin -> { opencode: 'bin/opencode.exe' }
# The bin/opencode.exe shim is a cross-platform launcher that execs the
# platform-native binary shipped as an optionalDependency; on linux-x64 npm
# resolves opencode-linux-x64 automatically. Binary name is `opencode`.
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts) keeps the install
# agent-owned, no root, no /usr/local shim (RT-02, ADR-004).
# Provider auth is supplied post-install (opencode auth login) — never baked.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"

echo "opencode: installing opencode-ai@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "opencode-ai@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v opencode || true)
if [[ -z "$bin_path" ]]; then
  echo "opencode install: opencode not on PATH after install" >&2
  exit 1
fi

# `opencode --version` prints the bare version (e.g. "1.17.11").
version_line=$(opencode --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'opencode install: pinned=%s but `opencode --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

echo "opencode: install complete (resolves at ${bin_path}; version matches pin)"
