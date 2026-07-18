#!/usr/bin/env bash
set -euo pipefail
# ccusage install.sh — real body (Phase 27, WORK-01).
#
# npm_package_name: ccusage (verified 2026-06-29 via npm view).
#   npm view ccusage@20.0.14 bin -> { ccusage: './src/cli.js' }
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
#
# ccusage is a READ-ONLY Claude Code cost/usage reporter: it parses the local
# ~/.claude usage logs and prints token/cost tables. No API token or secret is
# required or accepted, so nothing is baked and there is no per-tool config to
# preserve (it owns no state of its own) — hence no preserve_paths.json.
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts) keeps the install
# agent-owned, no root, no /usr/local shim (RT-02, ADR-004).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"

echo "ccusage: installing ccusage@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "ccusage@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v ccusage || true)
if [[ -z "$bin_path" ]]; then
  echo "ccusage install: ccusage not on PATH after install" >&2
  exit 1
fi

# `ccusage --version` prints "ccusage <version>".
version_line=$(ccusage --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'ccusage install: pinned=%s but `ccusage --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

echo "ccusage: install complete (resolves at ${bin_path}; version matches pin; read-only — no secret required)"
