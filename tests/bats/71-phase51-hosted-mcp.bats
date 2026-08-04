#!/usr/bin/env bats
# Phase 51 hosted-MCP regression coverage — the ANTIGRAVITY adapter specifically.
#
# Scope boundary with 60-catalog-hosted-mcp.bats: that file owns the catalog
# entry shape and the bare-URL register→deregister lifecycle for all six hosted
# entries across all five adapters. This file covers what a table-driven
# lifecycle cannot: Antigravity's native config format, its fan-out across
# providers, and its preserve/malformed-config edge cases.
#
# These tests deliberately inspect the shipped catalog and recipes rather than
# logging into a vendor account. Authentication belongs to the client that
# owns the OAuth/API-key session; AgentLinux must not persist a secret.

load 'helpers/assertions'

SOURCE_ROOT=${AGENTLINUX_SOURCE_ROOT:-/opt/agentlinux-src}
CATALOG=${AGENTLINUX_CATALOG:-/opt/agentlinux/catalog/$(jq -r .version "$SOURCE_ROOT/plugin/catalog/catalog.json")/catalog.json}
LOG=/var/log/agentlinux-install.log

@test "MCP-08: Firecrawl and GitHub recipes surface client-owned OAuth/API-key diagnostics" {
  # The diagnostics live in the shipped recipes themselves — a permanent bats
  # test must assert against source that survives the release, not against a
  # .planning/ phase artifact (intermediate state stripped before merge per the
  # planning-workflow policy).
  run grep -Eni 'oauth|api.key|opencode mcp debug|dynamic client registration|auth server' \
    "$SOURCE_ROOT/plugin/catalog/agents/firecrawl-mcp/install.sh" \
    "$SOURCE_ROOT/plugin/catalog/agents/github-mcp/install.sh"
  assert_exit_zero "MCP-08/auth-guidance"
}

@test "MCP-03: Antigravity adapter writes serverUrl into its native config" {
  local tmp_bin tmp_home url bin
  tmp_bin=$(mktemp -d)
  tmp_home=$(mktemp -d)
  url=$(jq -r '.agents[] | select(.id=="github-mcp") | .endpoint_url' "$CATALOG")

  # Isolate the adapter from host-installed clients. Presence-only stubs let the
  # shared helper exercise every writer while all state remains disposable.
  for bin in agy claude codex opencode qwen; do
    if [[ "$bin" == claude ]]; then
      printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "${1:-}" == mcp && "${2:-}" == add ]]; then' \
        '  mkdir -p "$HOME"' \
        '  jq -n --arg u "${6:-}" '\''{mcpServers:{"github-mcp":{type:"http",url:$u}}}'\'' >"$HOME/.claude.json"' \
        'fi' \
        'exit 0' >"${tmp_bin}/${bin}"
    else
      printf '#!/usr/bin/env bash\nexit 0\n' >"${tmp_bin}/${bin}"
    fi
    chmod 0755 "${tmp_bin}/${bin}"
  done

  run env \
    AGENTLINUX_AGENT_HOME="$tmp_home" \
    HOME="$tmp_home" \
    AGENTLINUX_CATALOG_DIR="$SOURCE_ROOT/plugin/catalog" \
    PATH="${tmp_bin}:/usr/bin:/bin" \
    bash "$SOURCE_ROOT/plugin/catalog/agents/github-mcp/install.sh"
  assert_exit_zero "MCP-03/antigravity-adapter"
  run jq -e --arg u "$url" \
    '.mcpServers["github-mcp"] | .serverUrl == $u and (has("headers") | not)' \
    "${tmp_home}/.gemini/config/mcp_config.json"
  assert_exit_zero "MCP-03/antigravity-serverUrl"

  rm -rf -- "$tmp_bin" "$tmp_home"
}

@test "MCP-03/04/07-10: every hosted provider fans out to Antigravity and removes cleanly" {
  local tmp_bin tmp_home cfg id url pin
  tmp_bin=$(mktemp -d)
  tmp_home=$(mktemp -d)
  cfg="${tmp_home}/.gemini/config/mcp_config.json"

  # Deterministic client-presence fixtures. The Claude fixture implements the
  # two operations the shared helper invokes so each provider can be installed
  # and removed in isolation without touching the host's real configurations.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'cfg="$HOME/.claude.json"' \
    'mkdir -p "$HOME"' \
    'case "${2:-}" in' \
    '  add) jq -n --arg s "${5:?}" --arg u "${6:?}" '\''{mcpServers: {($s): {type: "http", url: $u}}}'\'' >"$cfg" ;;' \
    '  remove) jq -n '\''{mcpServers: {}}'\'' >"$cfg" ;;' \
    'esac' \
    >"${tmp_bin}/claude"
  chmod 0755 "${tmp_bin}/claude"
  for id in agy codex opencode qwen; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"${tmp_bin}/${id}"
    chmod 0755 "${tmp_bin}/${id}"
  done

  for id in github-mcp sentry-mcp firecrawl-mcp slack-mcp linear-mcp jira-atlassian-mcp; do
    url=$(jq -r --arg id "$id" '.agents[] | select(.id == $id) | .endpoint_url' "$CATALOG")
    pin=$(jq -r --arg id "$id" '.agents[] | select(.id == $id) | .pinned_version' "$CATALOG")
    run env \
      AGENTLINUX_AGENT_HOME="$tmp_home" \
      AGENTLINUX_CATALOG_DIR="$SOURCE_ROOT/plugin/catalog" \
      PATH="${tmp_bin}:/usr/bin:/bin" \
      AGENTLINUX_PINNED_VERSION="$pin" \
      HOME="$tmp_home" \
      bash "$SOURCE_ROOT/plugin/catalog/agents/${id}/install.sh"
    assert_exit_zero "${id}/antigravity install"
    run jq -e --arg id "$id" --arg u "$url" \
      '.mcpServers[$id] | .serverUrl == $u and (has("headers") | not)' "$cfg"
    assert_exit_zero "${id}/antigravity serverUrl"

    run env \
      AGENTLINUX_AGENT_HOME="$tmp_home" \
      AGENTLINUX_CATALOG_DIR="$SOURCE_ROOT/plugin/catalog" \
      PATH="${tmp_bin}:/usr/bin:/bin" \
      AGENTLINUX_PINNED_VERSION="$pin" \
      HOME="$tmp_home" \
      bash "$SOURCE_ROOT/plugin/catalog/agents/${id}/uninstall.sh"
    assert_exit_zero "${id}/antigravity remove"
    run jq -e --arg id "$id" '.mcpServers | has($id)' "$cfg"
    [[ "$status" -ne 0 ]] || \
      __fail "${id}/antigravity remove" "registration is gone" "residue" "$LOG"
  done

  rm -rf -- "$tmp_bin" "$tmp_home"
}

@test "MCP-03: provider removal cleans preserved Antigravity config after agent removal" {
  local tmp_home cfg
  tmp_home=$(mktemp -d)
  cfg="${tmp_home}/.gemini/config/mcp_config.json"
  mkdir -p "$(dirname "$cfg")"
  printf '%s\n' '{"mcpServers":{"github-mcp":{"serverUrl":"https://api.githubcopilot.com/mcp/"}}}' >"$cfg"

  run env AGENTLINUX_AGENT_HOME="$tmp_home" bash -c \
    'source "$1/lib/mcp-register.sh" && al_mcp_deregister github-mcp && al_mcp_assert_absent github-mcp' \
    _ "$SOURCE_ROOT/plugin/catalog"
  assert_exit_zero "MCP-03/preserved-config-cleanup"
  run jq -e '.mcpServers | has("github-mcp")' "$cfg"
  [[ "$status" -ne 0 ]] || __fail "MCP-03/preserved-config-cleanup" \
    "provider removal leaves no Antigravity registration" "residue" "$LOG"

  rm -rf -- "$tmp_home"
}

@test "MCP-03: malformed preserved Antigravity config does not block unrelated removal" {
  local tmp_home cfg
  tmp_home=$(mktemp -d)
  cfg="${tmp_home}/.gemini/config/mcp_config.json"
  mkdir -p "$(dirname "$cfg")"
  printf '%s\n' '{not-json' >"$cfg"

  run env AGENTLINUX_AGENT_HOME="$tmp_home" bash -c \
    'source "$1/lib/mcp-register.sh" && al_mcp_deregister github-mcp' \
    _ "$SOURCE_ROOT/plugin/catalog"
  assert_exit_zero "MCP-03/malformed-preserved-config"

  rm -rf -- "$tmp_home"
}
