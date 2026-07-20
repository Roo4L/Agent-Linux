#!/usr/bin/env bash
set -euo pipefail
# sentry-cli install.sh — source_kind: npm (Phase 33, DEVT-03).
#
# npm_package_name: @sentry/cli (verified 2026-07-02 via the npm registry).
#   @sentry/cli exposes the `sentry-cli` bin.
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
#
# The @sentry/cli npm package's postinstall downloads the matching prebuilt
# sentry-cli binary from Sentry's CDN into the package dir; NPM_CONFIG_PREFIX=
# /home/agent/.npm-global (runner.ts) keeps that agent-owned — no root, no
# /usr/local shim (RT-02, ADR-004).
#
# License: FSL-1.1-MIT (Functional Source License) — free to use; it is NOT
# OSI-approved, and the entry's `license` field records that honestly (Appendix B).
#
# Secrets are NOT baked (Appendix C): SENTRY_AUTH_TOKEN is supplied by the user
# post-install (env var or `sentry-cli login`); this recipe never writes it.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"

echo "sentry-cli: installing @sentry/cli@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@sentry/cli@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v sentry-cli || true)
if [[ -z "$bin_path" ]]; then
  echo "sentry-cli install: sentry-cli not on PATH after install" >&2
  exit 1
fi

# `sentry-cli --version` prints "sentry-cli <version>".
version_line=$(sentry-cli --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'sentry-cli install: pinned=%s but `sentry-cli --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

echo "sentry-cli: install complete (resolves at ${bin_path}; version matches pin)"
echo "sentry-cli: to authenticate, set SENTRY_AUTH_TOKEN or run:  sentry-cli login"
