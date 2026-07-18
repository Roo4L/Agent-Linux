#!/usr/bin/env bash
set -euo pipefail
# sentry-mcp install.sh — source_kind: mcp, remote-http (Phase 37, MCP-04).
#
# Thin client-config installer (ADR-017): registers Sentry's HOSTED remote MCP
# server (bare URL, NO credential) into EVERY installed MCP-capable coding agent
# via the shared helper. Reuses the ENABLE-02 remote-http machinery built in
# Phase 36 (github-mcp).
#
# Sentry's hosted MCP is a rolling service at a stable URL. pinned_version names
# the curated upstream @sentry/mcp-server release the endpoint is validated
# against (ADR-011); the registration target is the URL.
#
# Auth (ADR-017): AgentLinux bakes NOTHING. Sentry's hosted MCP drives an OAuth
# login, so the user authenticates from within their coding agent on first use.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="sentry-mcp"
# The hosted endpoint (kept in sync with the catalog entry's endpoint_url; bats
# cross-asserts they match). Self-hosted Sentry users point at their own host.
url="https://mcp.sentry.dev/mcp"

echo "${server}: registering the Sentry remote MCP server (${url}) into installed MCP-capable agents"

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
echo "${server}:        (Claude Code prompts a Sentry OAuth login). No token is stored by AgentLinux."
