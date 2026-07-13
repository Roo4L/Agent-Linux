#!/usr/bin/env bash
set -euo pipefail
# github-mcp install.sh — source_kind: mcp, remote-http (Phase 36, MCP-03).
#
# Registers GitHub's HOSTED remote MCP server into EVERY installed MCP-capable
# coding agent (claude-code, codex, gemini-cli, opencode, qwen-code) via the
# shared cross-agent helper. This is the first consumer of the ENABLE-02
# remote-http machinery (reused by linear-mcp / jira-atlassian-mcp) and the first
# mandatory-secret MCP entry (requires_secret: true).
#
# The GitHub MCP server has no npm package: it is a rolling hosted service at a
# stable URL. pinned_version names the curated upstream github-mcp-server release
# the endpoint is validated against (ADR-011); the registration target is the URL.
#
# Never-bake (CAT-02): the PAT is NEVER written to disk. The helper stores an
# env-var REFERENCE (`Bearer ${GITHUB_MCP_PAT}`) that each agent expands at
# server-launch from its environment; codex keeps it off disk via
# bearer_token_env_var. The user exports GITHUB_MCP_PAT post-install.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"

# shellcheck source=../../lib/mcp-register.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"

server="github-mcp"
# The hosted endpoint (kept in sync with the catalog entry's endpoint_url; bats
# cross-asserts they match). GHE-Cloud users point at their own subdomain.
url="https://api.githubcopilot.com/mcp/"
secret_env="GITHUB_MCP_PAT"

echo "${server}: registering the GitHub remote MCP server (${url}) into installed MCP-capable agents"

# Fan out. al_mcp_register_http returns non-zero when NO agent is present (nothing
# to register into) OR when a present agent fails — distinguish the two so the
# no-agent case gets a friendly pointer instead of a cryptic error.
if ! al_mcp_register_http "$server" "$url" "$secret_env"; then
  if [[ -z "${AL_MCP_TARGETS:-}" ]]; then
    echo "${server} install: no MCP-capable coding agent is installed." >&2
    echo "${server} install: install one first, e.g.  agentlinux install claude-code" >&2
    exit 1
  fi
  echo "${server} install: registration failed for one of: ${AL_MCP_TARGETS}" >&2
  exit 1
fi

echo "${server}: registered into: ${AL_MCP_TARGETS}"
# MCP-03 mandatory-secret instruction. The token is required for the server to
# work; it is supplied at runtime via the environment, never baked here.
echo "${server}: NOTE — a GitHub Personal Access Token is REQUIRED. Export it in the"
echo "${server}:        environment your agents run in (e.g. add to ~/.profile):"
echo "${server}:          export ${secret_env}=<your GitHub PAT>   # classic scopes: repo, read:org, read:packages"
echo "${server}:        The token is never written to any config — agents read \$${secret_env} at launch."
