#!/usr/bin/env bash
set -euo pipefail
# slack-mcp uninstall.sh — symmetric inverse (Phase 41, MCP-08).
#
# Deregisters the Slack remote MCP server from EVERY present MCP-capable agent
# via the shared helper. Deregistration IS the uninstall — nothing was installed
# to a prefix; the registration lived only in each agent's config. Idempotent and
# residue-free. AgentLinux never stored a credential (ADR-017), so nothing to leak.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="slack-mcp"

echo "${server}: deregistering the Slack remote MCP server from all present agents"

al_mcp_deregister "$server"

# Truth check: no residue in any present agent's config.
al_mcp_assert_absent "$server"

echo "${server}: deregistered (no residue in any agent config)"
