#!/usr/bin/env bash
set -euo pipefail
# gemini-cli install.sh — real body (Phase 24, AGT-06).
#
# npm_package_name: @google/gemini-cli (verified 2026-06-29 via npm view).
#   npm view @google/gemini-cli@0.49.0 bin -> { gemini: 'bundle/gemini.js' }
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
# Binary name is `gemini`, NOT `gemini-cli` (the catalog id) — the bats test
# and post_install_verify invoke `gemini`.
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts) keeps the global
# install agent-owned, no root, no /usr/local shim (RT-02, ADR-004).
# Google auth (OAuth / GEMINI_API_KEY) is supplied post-install — never baked.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"

echo "gemini-cli: installing @google/gemini-cli@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@google/gemini-cli@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v gemini || true)
if [[ -z "$bin_path" ]]; then
  echo "gemini-cli install: gemini not on PATH after install" >&2
  exit 1
fi

# `gemini --version` prints the bare version (e.g. "0.49.0").
version_line=$(gemini --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'gemini-cli install: pinned=%s but `gemini --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

echo "gemini-cli: install complete (resolves at ${bin_path}; version matches pin)"
