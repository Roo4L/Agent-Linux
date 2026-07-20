#!/usr/bin/env bash
set -euo pipefail
# linear-mcp install.sh — source_kind: mcp, remote-http (Phase 42, MCP-09).
#
# Thin client-config installer (ADR-017): registers Linear's OFFICIAL hosted
# remote MCP server (bare URL, NO credential) into EVERY installed MCP-capable
# coding agent via the shared helper. Reuses the ENABLE-02 remote-http machinery
# (Phase 36) — the "OAuth handling enabler" the roadmap tagged here was already
# delivered there, so linear-mcp is just another consumer.
#
# SOURCE DECISION (2026-07-14): Linear ships a first-party hosted MCP server (GA
# May 2025) at the URL below — Streamable HTTP, OAuth 2.1 with dynamic client
# registration, centrally hosted and managed by Linear. It is free-tier usable —
# MCP rides on Linear's GraphQL API, a Free-plan feature, so it is not paywalled
# like the dropped gitlab endpoint. ADR-017-aligned: hosted bare URL, no baked
# credential, user auths in-client (Linear OAuth on first use).
#
# Linear's hosted MCP is a rolling service with no downloadable release to pin, so
# pinned_version carries the GA date (2025.5.1) the endpoint is validated against
# (ADR-011); the registration target is the URL.
#
# Auth (ADR-017): AgentLinux bakes NOTHING. The user completes Linear's OAuth login
# from within their coding agent on first use.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="linear-mcp"
# The official hosted endpoint (kept in sync with the catalog entry's endpoint_url;
# bats cross-asserts they match).
url="https://mcp.linear.app/mcp"

echo "${server}: registering the official Linear remote MCP server (${url}) into installed MCP-capable agents"

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
echo "${server}:        (Linear OAuth login). Works on Linear's free plan. No token is stored by AgentLinux."
