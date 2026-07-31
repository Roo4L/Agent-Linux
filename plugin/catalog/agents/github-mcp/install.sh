#!/usr/bin/env bash
set -euo pipefail
# github-mcp install.sh — source_kind: mcp, remote-http (MCP-03).
#
# Thin client-config installer (ADR-018): registers GitHub's HOSTED remote MCP
# server (bare URL, NO credential) into every installed MCP-capable coding agent.
#
# The GitHub MCP server has no npm package: it is a rolling hosted service at a
# stable URL. pinned_version names the curated upstream github-mcp-server release
# the endpoint is validated against (ADR-011); the registration target is the URL.
#
# Auth (ADR-018): AgentLinux bakes NOTHING — the user authenticates from within
# their coding agent on first use. See the NOTE printed at the end.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="github-mcp"
# The hosted endpoint — kept in sync with the catalog entry's endpoint_url (bats
# cross-asserts they match).
url="https://api.githubcopilot.com/mcp/"

al_mcp_install_http "$server" "$url" "GitHub remote MCP server"

echo "${server}:        (Claude Code prompts a GitHub OAuth login; codex: \`codex mcp login\`)."
echo "${server}:        OpenCode diagnostics: \`opencode mcp debug ${server}\`, then \`opencode mcp auth ${server}\`"
echo "${server}:        and \`opencode auth list\`. GitHub's hosted OAuth metadata may not support"
echo "${server}:        dynamic client registration; if so, OpenCode reports that external limitation."
echo "${server}:        No token is stored by AgentLinux."
