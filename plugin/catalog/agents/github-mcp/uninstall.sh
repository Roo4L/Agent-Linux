#!/usr/bin/env bash
set -euo pipefail
# github-mcp uninstall.sh — symmetric inverse (Phase 36, MCP-03).
#
# Deregisters the GitHub remote MCP server from EVERY present MCP-capable agent
# via the shared cross-agent helper. Deregistration IS the uninstall — nothing
# was installed to a prefix; the registration lived only in each agent's config.
# Idempotent (a no-op where the entry is already absent) and residue-free. Because
# only an env-var REFERENCE was ever stored (never a literal PAT), no secret can
# leak on removal.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="github-mcp"

echo "${server}: deregistering the GitHub remote MCP server from all present agents"

al_mcp_deregister "$server"

# Truth check: no residue in any present agent's config.
al_mcp_assert_absent "$server"

echo "${server}: deregistered (no residue in any agent config)"
