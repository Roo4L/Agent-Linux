#!/usr/bin/env bash
set -euo pipefail
# firecrawl-mcp uninstall.sh — symmetric inverse (Phase 40, MCP-07).
#
# Deregisters the Firecrawl remote MCP server from EVERY present MCP-capable agent
# via the shared helper. Deregistration IS the uninstall — nothing was installed
# to a prefix; the registration lived only in each agent's config. Idempotent and
# residue-free. AgentLinux never stored a credential (ADR-017), so nothing to leak.
#
# A user who re-registered with a personal key in the URL path (see install.sh)
# used the SAME server name, so this deregistration removes that variant too.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="firecrawl-mcp"

echo "${server}: deregistering the Firecrawl remote MCP server from all present agents"

al_mcp_deregister "$server"

# Truth check: no residue in any present agent's config.
al_mcp_assert_absent "$server"

echo "${server}: deregistered (no residue in any agent config)"
