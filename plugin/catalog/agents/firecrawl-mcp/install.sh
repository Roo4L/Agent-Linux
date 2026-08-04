#!/usr/bin/env bash
set -euo pipefail
# firecrawl-mcp install.sh — source_kind: mcp, remote-http.
#
# Thin client-config installer (ADR-018): registers Firecrawl's HOSTED remote MCP
# server (bare URL, NO credential) into every installed MCP-capable agent.
#
# Auth (ADR-018): AgentLinux bakes NOTHING — the user authenticates from within
# their coding agent on first use. See the NOTE printed at the end.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="firecrawl-mcp"
# The hosted endpoint — kept in sync with the catalog entry's endpoint_url (bats
# cross-asserts they match).
url="https://mcp.firecrawl.dev/v2/mcp"

al_mcp_install_http "$server" "$url" "Firecrawl remote MCP server"

echo "${server}:        If your client cannot complete Firecrawl OAuth, get a personal key at"
echo "${server}:        https://firecrawl.dev/app/api-keys and re-register it at runtime"
echo "${server}:        with the key in the URL path — e.g. for Claude Code:"
echo "${server}:          claude mcp remove ${server} --scope user"
echo "${server}:          claude mcp add --transport http ${server} https://mcp.firecrawl.dev/<your-key>/v2/mcp --scope user"
echo "${server}:        (other MCP-capable agents: repeat with each client's own MCP-add.)"
