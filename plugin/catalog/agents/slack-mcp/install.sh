#!/usr/bin/env bash
set -euo pipefail
# slack-mcp install.sh — source_kind: mcp, remote-http.
#
# Thin client-config installer (ADR-018): registers Slack's official HOSTED remote
# MCP server (bare URL, NO credential) into every installed MCP-capable agent.
#
# Auth (ADR-018): AgentLinux bakes NOTHING — the user authenticates from within
# their coding agent on first use. See the NOTE printed at the end.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="slack-mcp"
# The hosted endpoint — kept in sync with the catalog entry's endpoint_url (bats
# cross-asserts they match).
url="https://mcp.slack.com/mcp"

al_mcp_install_http "$server" "$url" "official Slack remote MCP server"

echo "${server}:        (Slack OAuth login). Your workspace admin may need to approve the"
echo "${server}:        MCP integration. No token is stored by AgentLinux."
