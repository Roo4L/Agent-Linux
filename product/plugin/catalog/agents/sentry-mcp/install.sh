#!/usr/bin/env bash
set -euo pipefail
# sentry-mcp install.sh — source_kind: mcp, remote-http.
#
# Thin client-config installer (ADR-018): registers Sentry's HOSTED remote MCP
# server (bare URL, NO credential) into every installed MCP-capable coding agent.
#
# Auth (ADR-018): AgentLinux bakes NOTHING — the user authenticates from within
# their coding agent on first use. See the NOTE printed at the end.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="sentry-mcp"
# The hosted endpoint — kept in sync with the catalog entry's endpoint_url (bats
# cross-asserts they match).
url="https://mcp.sentry.dev/mcp"

al_mcp_install_http "$server" "$url" "Sentry remote MCP server"

echo "${server}:        (Claude Code prompts a Sentry OAuth login). No token is stored by AgentLinux."
