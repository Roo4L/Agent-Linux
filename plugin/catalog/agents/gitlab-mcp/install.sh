#!/usr/bin/env bash
set -euo pipefail
# gitlab-mcp install.sh — source_kind: mcp, remote-http (Phase 38, MCP-05).
#
# Thin client-config installer (ADR-017): registers GitLab's OFFICIAL hosted MCP
# endpoint (bare URL, NO credential) into EVERY installed MCP-capable coding agent
# via the shared helper. First-party GitLab Duo MCP, OAuth Dynamic Client
# Registration — the user authenticates in-client on first use.
#
# The endpoint is a rolling GitLab API surface (no npm package). pinned_version
# names the GitLab release the endpoint is validated against (ADR-011); it went
# beta in GitLab 18.6. Self-managed users point at their own https://<host>/api/v4/mcp.
#
# Auth (ADR-017): AgentLinux bakes NOTHING. The user authenticates from within
# their coding agent on first use (GitLab OAuth).

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="gitlab-mcp"
# The official hosted endpoint (kept in sync with the catalog entry's endpoint_url;
# bats cross-asserts they match).
url="https://gitlab.com/api/v4/mcp"

echo "${server}: registering the GitLab remote MCP server (${url}) into installed MCP-capable agents"

# Fan out. al_mcp_register_http returns non-zero when NO agent is present (nothing
# to register into) OR when a present agent fails — distinguish the two so the
# no-agent case gets a friendly pointer instead of a cryptic error.
if ! al_mcp_register_http "$server" "$url"; then
  if [[ -z "${AL_MCP_TARGETS:-}" ]]; then
    echo "${server} install: no MCP-capable coding agent is installed." >&2
    echo "${server} install: install one first, e.g.  agentlinux install claude-code" >&2
    exit 1
  fi
  echo "${server} install: registration failed for one of: ${AL_MCP_TARGETS}" >&2
  exit 1
fi

echo "${server}: registered into: ${AL_MCP_TARGETS}"
# ADR-017: auth is completed IN-CLIENT — AgentLinux stores no token.
echo "${server}: NOTE — authenticate from within your coding agent on first use"
echo "${server}:        (Claude Code prompts a GitLab OAuth login). No token is stored by AgentLinux."
echo "${server}:        Self-managed GitLab: re-register against https://<your-host>/api/v4/mcp."
