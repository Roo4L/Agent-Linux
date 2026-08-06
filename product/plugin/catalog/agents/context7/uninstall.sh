#!/usr/bin/env bash
set -euo pipefail
# context7 uninstall.sh — symmetric inverse (Phase 35, MCP-02 / ENABLE-02).
#
# Deregistration IS the uninstall — npx never persisted a binary, so removing the
# ~/.claude.json registration is all there is. `claude mcp remove --scope user` is
# idempotent (exit 0 when the server is absent). Fallback: if Claude Code is itself
# already gone (claude off PATH), strip the key directly with jq so no orphaned
# registration is left behind either way. Removing the key also drops any env the
# user attached to it (e.g. an optional CONTEXT7_API_KEY), so no secret lingers.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

server="context7"
claude_json="${AGENTLINUX_AGENT_HOME}/.claude.json"

echo "${server}: deregistering ${server} from Claude Code user config"

if command -v claude >/dev/null 2>&1; then
  claude mcp remove "${server}" --scope user >/dev/null 2>&1 || true
elif [[ -f "${claude_json}" ]]; then
  # claude is gone but its config may still carry the registration — remove the key
  # atomically (tmp + mv). mktemp in the same dir keeps the rename atomic (same
  # filesystem) and avoids a predictable $$ path; an EXIT trap cleans the tmp on any
  # early exit. A parse failure leaves the original untouched (idempotent).
  tmp=$(mktemp "${claude_json}.tmp.XXXXXX")
  trap 'rm -f "${tmp}"' EXIT
  if jq --arg s "${server}" 'if (.mcpServers | type) == "object" then .mcpServers |= del(.[$s]) else . end' \
    "${claude_json}" >"${tmp}" 2>/dev/null; then
    mv "${tmp}" "${claude_json}"
  fi
fi

# Truth check: the server key is gone from ~/.claude.json (no residue). A missing
# file counts as clean.
if [[ -f "${claude_json}" ]] \
  && jq -e --arg s "${server}" '.mcpServers | has($s)' "${claude_json}" >/dev/null 2>&1; then
  echo "${server} uninstall: still registered in ${claude_json} after remove" >&2
  exit 1
fi

echo "${server}: deregistered (no residue in ${claude_json})"
