#!/usr/bin/env bash
set -euo pipefail
# jira-atlassian-mcp install.sh — source_kind: mcp, remote-http (Phase 43, MCP-10).
#
# Thin client-config installer (ADR-017): registers Atlassian's OFFICIAL hosted
# Rovo MCP server (bare URL, NO credential) into EVERY installed MCP-capable coding
# agent via the shared helper. Reuses the ENABLE-02 remote-http machinery (Phase 36).
#
# SOURCE DECISION (2026-07-14): Atlassian ships a first-party hosted MCP server —
# the Atlassian Rovo MCP Server (GA Feb 2026) — covering Jira and Confluence at GA,
# with more Atlassian products (JSM, Bitbucket, Compass) rolling out over time.
# Streamable HTTP + OAuth 2.1 (browser sign-in), operating
# within the signed-in user's permissions. It is **free-tier usable**: Atlassian's
# platform page lists Free at 500 calls/hour and states all Cloud customers have
# access — NOT gated behind a paid plan or a paid Rovo add-on (verified; unlike the
# dropped gitlab endpoint). ADR-017-aligned: hosted bare URL, no baked credential,
# user auths in-client. Cloud-only (no Data Center / Server).
#
# The hosted endpoint is a rolling service with no downloadable release, so
# pinned_version carries the GA date (2026.2.4) the endpoint is validated against
# (ADR-011); the registration target is the URL. The endpoint is the current
# Streamable-HTTP OAuth path (the older /v1/sse SSE path is deprecated).
#
# Auth (ADR-017): AgentLinux bakes NOTHING. The user completes Atlassian's OAuth
# login from within their coding agent on first use.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="jira-atlassian-mcp"
# The official hosted endpoint (kept in sync with the catalog entry's endpoint_url;
# bats cross-asserts they match).
url="https://mcp.atlassian.com/v1/mcp/authv2"

echo "${server}: registering the official Atlassian Rovo MCP server (${url}) into installed MCP-capable agents"

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
echo "${server}:        (Atlassian OAuth login). Cloud-only; free Cloud sites are supported."
echo "${server}:        No token is stored by AgentLinux."
