#!/usr/bin/env bash
set -euo pipefail
# chrome-devtools-mcp install.sh — source_kind: mcp (Phase 34, MCP-01 / ENABLE-02).
#
# Registers the Chrome DevTools MCP server into Claude Code's USER-scope config
# (~/.claude.json) via `claude mcp add --scope user`. This is the first consumer
# of the MCP-server entry kind: an MCP recipe registers a server with claude
# rather than installing a binary or npm package. The server itself is fetched
# on-demand by npx at launch time (npx -y chrome-devtools-mcp@<pin>), so there is
# nothing to install into the agent prefix — the "install" is the registration.
#
# The pin is read from AGENTLINUX_PINNED_VERSION (ADR-011) — never hardcoded.
# chrome-devtools-mcp is KEYLESS (requires_secret is absent from the catalog
# entry), so nothing prints a token instruction.
#
# Dependency: `claude mcp add` requires Claude Code. If claude is not on PATH the
# recipe fails with a clear pointer rather than a cryptic command-not-found.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/browser-deps.sh
source "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}/lib/browser-deps.sh"

server="chrome-devtools-mcp"
ver="${AGENTLINUX_PINNED_VERSION}"
claude_json="${AGENTLINUX_AGENT_HOME}/.claude.json"

if ! command -v claude >/dev/null 2>&1; then
  echo "${server} install: Claude Code not found — an MCP server registers into Claude Code." >&2
  echo "${server} install: install it first with:  agentlinux install claude-code" >&2
  exit 1
fi

# Chrome DevTools MCP's default browser discovery requires the branded Chrome
# executable, not merely an npm package or a Playwright cache browser.
al_browser_ensure_chrome

echo "${server}: registering ${server}@${ver} into Claude Code user config (--scope user)"

# Remove-then-add makes the registration idempotent AND guarantees the pinned
# version is the one registered: `claude mcp add` on an existing name is a no-op
# that would leave a stale pin in place, so drop any prior registration first.
# Both subcommands exit 0 when the server is absent (verified), so this is safe on
# a first install.
claude mcp remove "${server}" --scope user >/dev/null 2>&1 || true
claude mcp add "${server}" --scope user -- npx -y "${server}@${ver}"

# Deterministic post-register assertion: the server is present in ~/.claude.json's
# user-scope mcpServers with the pinned npx spec. jq (not `claude mcp get`, which
# health-checks by spawning the server) keeps this fast and offline.
if ! jq -e --arg s "${server}" --arg v "${server}@${ver}" \
  '.mcpServers[$s].args // [] | index($v)' "${claude_json}" >/dev/null 2>&1; then
  echo "${server} install: registration not found in ${claude_json} after add" >&2
  exit 1
fi

echo "${server}: registered (appears in \`claude mcp list\` under user scope)"
# MCP-01: surface the Chrome-present requirement (the MCP process starts without a
# Chrome, but its browser tool calls need one).
echo "${server}: NOTE — browser tools need a local Chrome/Chromium present"
echo "${server}:        (e.g. \`agentlinux install playwright-cli\` provides one, or install system Chrome)"
