#!/usr/bin/env bash
set -euo pipefail
# linear-mcp install.sh — source_kind: mcp, remote-http.
#
# Thin client-config installer (ADR-018): registers Linear's official HOSTED
# remote MCP server (bare URL, NO credential) into every MCP-capable agent.
#
# Auth (ADR-018): AgentLinux bakes NOTHING — the user authenticates from within
# their coding agent on first use. See the NOTE printed at the end.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="linear-mcp"
# The hosted endpoint — kept in sync with the catalog entry's endpoint_url (bats
# cross-asserts they match).
url="https://mcp.linear.app/mcp"

al_mcp_install_http "$server" "$url" "official Linear remote MCP server"

echo "${server}:        (Linear OAuth login). Works on Linear's free plan. No token is stored by AgentLinux."
