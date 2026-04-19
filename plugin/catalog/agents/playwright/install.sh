#!/usr/bin/env bash
set -euo pipefail
# playwright install.sh — real body (Phase 5 AGT-05).
#
# Three-part install:
#   (1) npm install -g playwright@$PIN          — CLI + JS bindings, agent-owned
#   (2) npx playwright install --with-deps      — downloads chromium + apt deps
#       chromium                                  in one shot. install-deps
#                                                 auto-prepends sudo when
#                                                 getuid() != 0 (source:
#                                                 playwright-core/src/server/
#                                                 registry/dependencies.ts).
#                                                 With ADR-012 sudoers drop-in
#                                                 (NOPASSWD: ALL), the
#                                                 apt-get install -y ...
#                                                 succeeds without prompt.
#
# Why --with-deps instead of separate install + install-deps:
#   - Upstream-recommended for CI (cited: playwright.dev/docs/ci)
#   - Single command = single exit code; easier error handling
#   - install-deps is browser-scoped when a browser arg is given
#
# Browser cache: ~/.cache/ms-playwright/ (agent-owned, ADR-004 compliant).
# Chromium download is ~281 MB (playwright.dev/docs/browsers) — CI time cost
# is accepted per 05-CONTEXT.md; caching is a Phase 6 optimization.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "playwright: installing playwright@${AGENTLINUX_PINNED_VERSION} (CLI + bindings)"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "playwright@${AGENTLINUX_PINNED_VERSION}"

if ! command -v playwright >/dev/null 2>&1; then
  echo "playwright install: playwright CLI not on PATH after npm install -g" >&2
  exit 1
fi

# Verify CLI version matches pin before downloading browsers — don't waste
# ~281 MB of download on a mispinned install.
pw_version=$(playwright --version 2>&1 | head -1)
if ! printf '%s' "$pw_version" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'playwright install: pinned=%s but --version: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$pw_version" >&2
  exit 1
fi

echo "playwright: CLI at $(command -v playwright), ${pw_version}"
echo "playwright: downloading chromium + system deps (~281 MB; uses elevated privileges for apt)"

# --with-deps triggers the apt-privileged path internally. ADR-012's
# /etc/sudoers.d/agentlinux grant (agent ALL=(ALL) NOPASSWD: ALL) means
# Playwright's internal privileged invocation is non-interactive. If ADR-012
# regresses, this will fail with "a password is required" — a clear signal.
#
# NPX note: npx needs HOME set for its cache. runner.ts sets HOME=/home/agent.
# If this recipe is ever invoked without HOME (e.g. a raw systemd unit without
# EnvironmentFile), npx falls back to /tmp and still works.
npx --yes playwright install --with-deps chromium

# Post-install smoke: chromium binary exists in the expected cache location.
cache_dir="${AGENTLINUX_AGENT_HOME}/.cache/ms-playwright"
if [[ ! -d "$cache_dir" ]]; then
  printf 'playwright install: browser cache dir %s not created\n' "$cache_dir" >&2
  exit 1
fi

# Find at least one chromium-* dir (name is like chromium-1234).
if ! find "$cache_dir" -maxdepth 1 -type d -name 'chromium-*' | head -1 | grep -q .; then
  printf 'playwright install: no chromium-* dir in %s\n' "$cache_dir" >&2
  exit 1
fi

echo "playwright: install complete (chromium in ${cache_dir})"
