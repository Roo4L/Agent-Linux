#!/usr/bin/env bash
set -euo pipefail
# jira-atlassian-mcp install.sh — source_kind: mcp, remote-http.
#
# Thin client-config installer (ADR-018): registers Atlassian's official HOSTED
# Rovo MCP server (bare URL, NO credential) into every MCP-capable agent.
#
# Auth (ADR-018): AgentLinux bakes NOTHING — the user authenticates from within
# their coding agent on first use. See the NOTE printed at the end.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="jira-atlassian-mcp"
# The hosted endpoint — kept in sync with the catalog entry's endpoint_url (bats
# cross-asserts they match).
url="https://mcp.atlassian.com/v1/mcp/authv2"

al_mcp_install_http "$server" "$url" "official Atlassian Rovo MCP server"

echo "${server}:        (Atlassian OAuth login). Cloud-only; free Cloud sites are supported."
echo "${server}:        No token is stored by AgentLinux."
