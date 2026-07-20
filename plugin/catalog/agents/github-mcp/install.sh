#!/usr/bin/env bash
set -euo pipefail
# github-mcp install.sh — source_kind: mcp, remote-http (Phase 36, MCP-03).
#
# Thin client-config installer (ADR-017): registers GitHub's HOSTED remote MCP
# server (bare URL, NO credential) into EVERY installed MCP-capable coding agent
# (claude-code, codex, antigravity-cli, opencode, qwen-code) via the shared helper.
# First consumer of the ENABLE-02 remote-http machinery (reused by linear-mcp /
# jira-atlassian-mcp).
#
# The GitHub MCP server has no npm package: it is a rolling hosted service at a
# stable URL. pinned_version names the curated upstream github-mcp-server release
# the endpoint is validated against (ADR-011); the registration target is the URL.
#
# Auth (ADR-017): AgentLinux bakes NOTHING. GitHub's hosted MCP supports in-client
# OAuth, so the user authenticates from within their coding agent on first use
# (Claude Code prompts a login; codex `codex mcp login`; etc.).

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="github-mcp"
# The hosted endpoint (kept in sync with the catalog entry's endpoint_url; bats
# cross-asserts they match). GHE-Cloud users point at their own subdomain.
url="https://api.githubcopilot.com/mcp/"

echo "${server}: registering the GitHub remote MCP server (${url}) into installed MCP-capable agents"

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
echo "${server}:        (Claude Code prompts a GitHub OAuth login; codex: \`codex mcp login\`)."
echo "${server}:        OpenCode diagnostics: \`opencode mcp debug ${server}\`, then \`opencode mcp auth ${server}\`"
echo "${server}:        and \`opencode auth list\`. GitHub's hosted OAuth metadata may not support"
echo "${server}:        dynamic client registration; if so, OpenCode reports that external limitation."
echo "${server}:        No token is stored by AgentLinux."
