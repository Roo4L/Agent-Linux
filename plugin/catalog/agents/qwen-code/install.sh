#!/usr/bin/env bash
set -euo pipefail
# qwen-code install.sh — real body (Phase 26, AGT-08).
#
# npm_package_name: @qwen-code/qwen-code (verified 2026-06-29 via npm view).
#   npm view @qwen-code/qwen-code@0.19.2 bin -> { qwen: 'cli-entry.js' }
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
# Binary name is `qwen`, NOT `qwen-code` (the catalog id).
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts) keeps the install
# agent-owned, no root, no /usr/local shim (RT-02, ADR-004).
# Provider auth (DASHSCOPE_API_KEY / OpenAI-compatible creds) is supplied
# post-install — never baked into the recipe.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"

echo "qwen-code: installing @qwen-code/qwen-code@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@qwen-code/qwen-code@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v qwen || true)
if [[ -z "$bin_path" ]]; then
  echo "qwen-code install: qwen not on PATH after install" >&2
  exit 1
fi

# `qwen --version` prints the bare version (e.g. "0.19.2").
version_line=$(qwen --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'qwen-code install: pinned=%s but `qwen --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

echo "qwen-code: install complete (resolves at ${bin_path}; version matches pin)"
