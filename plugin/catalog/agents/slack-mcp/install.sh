#!/usr/bin/env bash
set -euo pipefail
# slack-mcp install.sh — source_kind: mcp, remote-http (Phase 41, MCP-08).
#
# Thin client-config installer (ADR-017): registers Slack's OFFICIAL hosted remote
# MCP server (bare URL, NO credential) into EVERY installed MCP-capable coding
# agent via the shared helper. Reuses the ENABLE-02 remote-http machinery
# (Phase 36).
#
# SOURCE DECISION (2026-07-14): Slack shipped a first-party hosted MCP server (GA
# Feb 2026) at the URL below — Streamable HTTP, Slack-brokered OAuth 2.0, and
# workspace-admin-approved by design. This SUPERSEDES the roadmap's third-party
# npm pick (korotovsky/slack-mcp-server), whose headline "stealth mode" auth
# (xoxc/xoxd session tokens scraped from a browser) bypasses workspace-admin app
# approval — a governance-bypass footgun we deliberately do NOT ship. The official
# endpoint is admin-governed and free for workspace members (no paywall), so it is
# the ADR-017-aligned choice: hosted bare URL, no baked credential, user auths
# in-client, admin-revocable.
#
# Slack's hosted MCP is a rolling service with no downloadable release to pin, so
# pinned_version carries the GA date (2026.2.17) the endpoint is validated against
# (ADR-011); the registration target is the URL.
#
# Auth (ADR-017): AgentLinux bakes NOTHING. The user completes Slack's OAuth login
# from within their coding agent on first use (subject to the workspace admin's
# MCP-integration approval).

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="slack-mcp"
# The official hosted endpoint (kept in sync with the catalog entry's endpoint_url;
# bats cross-asserts they match).
url="https://mcp.slack.com/mcp"

echo "${server}: registering the official Slack remote MCP server (${url}) into installed MCP-capable agents"

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
echo "${server}:        (Slack OAuth login). Your workspace admin may need to approve the"
echo "${server}:        MCP integration. No token is stored by AgentLinux."
