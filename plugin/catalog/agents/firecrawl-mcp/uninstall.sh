#!/usr/bin/env bash
set -euo pipefail
# firecrawl-mcp uninstall.sh — symmetric inverse.
#
# Deregisters the server from every present MCP-capable agent and asserts no
# residue. Deregistration IS the uninstall: nothing was installed to a prefix,
# and AgentLinux never stored a credential (ADR-018 thin installer).

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

al_mcp_uninstall_http "firecrawl-mcp" "Firecrawl remote MCP server"
