#!/usr/bin/env bash
set -euo pipefail
# context7 install.sh — source_kind: mcp (Phase 35, MCP-02 / ENABLE-02).
#
# Registers the Context7 MCP server (Upstash's up-to-date library-docs server)
# into Claude Code's USER-scope config (~/.claude.json) via `claude mcp add
# --scope user`. Like chrome-devtools-mcp this is a registration, not a binary
# install: the server itself is fetched on demand by npx at launch time
# (npx -y @upstash/context7-mcp@<pin>), so nothing lands in the agent prefix.
#
# context7 is the first SECRET-CARRYING MCP entry (ENABLE-02). Its key is
# OPTIONAL: the server works keyless (lower rate limit), and a free
# CONTEXT7_API_KEY raises the limit. Per the secret contract the key is NEVER
# baked into this recipe or the registration — the server is registered keyless
# and `install` prints the post-install instruction for supplying the key. The
# catalog entry declares secret_env=CONTEXT7_API_KEY / requires_secret=false
# (optional) as the machine-readable counterpart of that instruction.
#
# The pin is read from AGENTLINUX_PINNED_VERSION (ADR-011) — never hardcoded.
#
# Dependency: `claude mcp add` requires Claude Code. If claude is not on PATH the
# recipe fails with a clear pointer rather than a cryptic command-not-found.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

server="context7"
pkg="@upstash/context7-mcp"
ver="${AGENTLINUX_PINNED_VERSION}"
secret_env="CONTEXT7_API_KEY"
claude_json="${AGENTLINUX_AGENT_HOME}/.claude.json"

if ! command -v claude >/dev/null 2>&1; then
  echo "${server} install: Claude Code not found — an MCP server registers into Claude Code." >&2
  echo "${server} install: install it first with:  agentlinux install claude-code" >&2
  exit 1
fi

echo "${server}: registering ${pkg}@${ver} into Claude Code user config (--scope user)"

# Remove-then-add makes the registration idempotent AND guarantees the pinned
# version is the one registered: `claude mcp add` on an existing name is a no-op
# that would leave a stale pin (or a previously-keyed spec) in place, so drop any
# prior registration first. Both subcommands exit 0 when the server is absent, so
# this is safe on a first install. The key is NOT passed here — keyless by design.
claude mcp remove "${server}" --scope user >/dev/null 2>&1 || true
claude mcp add "${server}" --scope user -- npx -y "${pkg}@${ver}"

# Deterministic post-register assertion: the server is present in ~/.claude.json's
# user-scope mcpServers with the pinned npx spec. jq (not `claude mcp get`, which
# health-checks by spawning the server) keeps this fast and offline.
if ! jq -e --arg s "${server}" --arg v "${pkg}@${ver}" \
  '.mcpServers[$s].args // [] | index($v)' "${claude_json}" >/dev/null 2>&1; then
  echo "${server} install: registration not found in ${claude_json} after add" >&2
  exit 1
fi

# Secret contract (ENABLE-02): the registration MUST be keyless — assert no key
# leaked into the stored spec. A regression that baked ${secret_env} into args or
# env would defeat the never-bake guarantee, so fail loud if the value appears.
# The env-var name is passed with jq --arg and matched with LITERAL `contains`
# (not a regex `test`), so this guard stays correct if a later MCP recipe reuses
# the pattern with a secret_env name that contains regex metacharacters.
if jq -e --arg s "${server}" --arg k "${secret_env}" \
  '.mcpServers[$s] | (.env // {}) as $e
     | ((.args // []) | any(contains($k + "=")))
       or (($e | has($k)) and (($e[$k] // "") != ""))' \
  "${claude_json}" >/dev/null 2>&1; then
  echo "${server} install: ${secret_env} unexpectedly baked into the registration" >&2
  exit 1
fi

echo "${server}: registered keyless (appears in \`claude mcp list\` under user scope)"
# MCP-02 / ENABLE-02: surface the OPTIONAL post-install key instruction. The
# server works without a key; a free key raises the rate limit. Supplying it is
# the user's step — never baked by this recipe.
echo "${server}: NOTE — works keyless. For a higher rate limit, get a free key at"
echo "${server}:        https://context7.com/dashboard and re-register with it:"
echo "${server}:          claude mcp remove ${server} --scope user"
echo "${server}:          claude mcp add ${server} --scope user --env ${secret_env}=<your-key> -- npx -y ${pkg}@${ver}"
