#!/usr/bin/env bash
set -euo pipefail
# firecrawl-mcp install.sh — source_kind: mcp, remote-http (Phase 40, MCP-07).
#
# Thin client-config installer (ADR-017): registers Firecrawl's HOSTED remote MCP
# server (bare URL, NO credential) into EVERY installed MCP-capable coding agent
# via the shared helper. Reuses the ENABLE-02 remote-http machinery (Phase 36).
#
# The bare endpoint uses Firecrawl's documented MCP OAuth flow (including dynamic
# client registration). Clients that cannot complete that flow may use a personal
# API key in the URL path at runtime; AgentLinux never stores or prints that key.
#
# pinned_version names the curated upstream firecrawl-mcp release the endpoint is
# validated against (ADR-011); the registration target is the URL.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="firecrawl-mcp"
# The keyless hosted endpoint (kept in sync with the catalog entry's endpoint_url;
# bats cross-asserts they match). Self-hosted Firecrawl users point at their own
# host via the same re-registration path.
url="https://mcp.firecrawl.dev/v2/mcp"

echo "${server}: registering the Firecrawl remote MCP server (${url}) into installed MCP-capable agents"

# Fan out. al_mcp_register_http returns non-zero when NO agent is present (nothing
# to register into) OR when a present agent fails — distinguish the two so the
# no-agent case gets a friendly pointer instead of a cryptic error.
if ! al_mcp_register_http "$server" "$url"; then
  if [[ -z "${AL_MCP_TARGETS:-}" ]]; then
    echo "${server} install: no MCP-capable coding agent is installed." >&2
    echo "${server} install: install one first, e.g.  agentlinux install claude-code" >&2
    exit 1
  fi
  echo "${server} install: registration failed for one of: ${AL_MCP_TARGETS}" >&2
  exit 1
fi

echo "${server}: registered into: ${AL_MCP_TARGETS}"
# ADR-017: no token stored by AgentLinux. The client completes OAuth at runtime.
echo "${server}: NOTE — authenticate through the client's OAuth flow on first use."
echo "${server}:        If your client cannot complete Firecrawl OAuth, get a personal key at"
echo "${server}:        https://firecrawl.dev/app/api-keys and re-register it at runtime"
echo "${server}:        with the key in the URL path — e.g. for Claude Code:"
echo "${server}:          claude mcp remove ${server} --scope user"
echo "${server}:          claude mcp add --transport http ${server} https://mcp.firecrawl.dev/<your-key>/v2/mcp --scope user"
echo "${server}:        (other MCP-capable agents: repeat with each client's own MCP-add.)"
