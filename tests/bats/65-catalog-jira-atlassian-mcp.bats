#!/usr/bin/env bats
# tests/bats/65-catalog-jira-atlassian-mcp.bats — v0.3.6 Phase 43 (jira-atlassian-mcp) MCP-10.
#
# THIN INSTALLER (ADR-017): jira-atlassian-mcp registers Atlassian's OFFICIAL hosted
# Rovo MCP server as a BARE URL — no credential — into EVERY installed MCP-capable
# agent (claude-code, codex, gemini-cli, opencode, qwen-code) via the shared helper
# plugin/catalog/lib/mcp-register.sh. AgentLinux stores NO token; the user
# authenticates in-client (Atlassian OAuth) on first use. `remove` deregisters from
# all agents symmetrically. Sixth consumer of the ENABLE-02 remote-http helper.
#
# Entry-shape note: unlike slack/linear (no package → license omitted), this hosted
# service HAS an official Apache-2.0 repo (github.com/atlassian/atlassian-mcp-server),
# so the entry records license Apache-2.0 while still using a GA-date pinned_version
# (the endpoint is rolling, with no downloadable release). Version and license are
# independent axes.
#
# Design invariants: see tests/bats/61-catalog-sentry-mcp.bats (identical shape).

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
CLAUDE_JSON=/home/agent/.claude.json
CODEX_TOML=/home/agent/.codex/config.toml
# Credential-shaped strings that must NEVER appear in a config (ADR-017). Kept
# tight (auth-header + token-field shapes + Atlassian API-token prefixes ATATT/ATCTT)
# to avoid false positives from unrelated claude-code state written into ~/.claude.json.
CRED_RE='[Aa]uthorization|[Bb]earer|bearer_token|ATATT|ATCTT'

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux install codex' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux remove --force jira-atlassian-mcp' >/dev/null 2>&1 || true
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force jira-atlassian-mcp' >/dev/null 2>&1 || true
  fi
}

_assert_present_if_installed() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 \
    || { __diag "MCP-10: ${bin} not installed — fan-out assertion skipped"; return 0; }
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "MCP-10 (${bin} carries the bare jira-atlassian-mcp entry)"
}

_assert_gone_if_present() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-10" "${bin} config still carries jira-atlassian-mcp after remove" "residue" "$LOG"
}

@test "MCP-10: jira-atlassian-mcp registers a BARE remote URL (no credential, ADR-017) into every installed agent, then deregisters with no residue" {
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-10 (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "MCP-10 (codex present precondition)"

  local url
  url=$(jq -r '.agents[] | select(.id=="jira-atlassian-mcp") | .endpoint_url' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "MCP-10" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi

  run sudo -u agent -H bash --login -c 'agentlinux install jira-atlassian-mcp'
  assert_exit_zero "MCP-10 (install)"
  assert_no_eacces "MCP-10 (install)" "$output"

  if ! printf '%s' "${output}" | grep -qiE 'authenticate from within your coding agent|in-client|oauth'; then
    __fail "MCP-10" "install surfaces the in-client auth pointer" "${output:-<empty>}" "$LOG"
  fi

  # claude: bare http registration at the pinned endpoint, NO auth header.
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"jira-atlassian-mcp\"] | .type==\"http\" and .url==\$u and (has(\"headers\")|not)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-10 (claude bare http registration, no headers)"

  # codex: pinned url in the jira-atlassian-mcp marker block, NO bearer/token field.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:jira-atlassian-mcp >>>/,/agentlinux-mcp:jira-atlassian-mcp <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "MCP-10 (codex registered at pinned url)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:jira-atlassian-mcp >>>/,/agentlinux-mcp:jira-atlassian-mcp <<</p' ${CODEX_TOML} | grep -qiE 'bearer|token'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-10" "codex jira-atlassian-mcp block carries NO bearer/token (bare url)" "token field present" "$LOG"

  _assert_present_if_installed gemini "jq -e --arg u \"${url}\" '.mcpServers[\"jira-atlassian-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.gemini/settings.json"
  _assert_present_if_installed qwen "jq -e --arg u \"${url}\" '.mcpServers[\"jira-atlassian-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.qwen/settings.json"
  _assert_present_if_installed opencode "jq -e --arg u \"${url}\" '.mcp[\"jira-atlassian-mcp\"] | .type==\"remote\" and .url==\$u and (has(\"headers\")|not)' /home/agent/.config/opencode/opencode.json"

  # THIN INSTALLER: no credential-shaped string in ANY agent config (ADR-017).
  run sudo -u agent -H bash --login -c \
    "grep -rIqE '${CRED_RE}' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-10" "NO credential in any agent config (thin installer, ADR-017)" "credential-shaped string found" "$LOG"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force jira-atlassian-mcp'
  assert_exit_zero "MCP-10 (remove)"
  assert_no_eacces "MCP-10 (remove)" "$output"

  run sudo -u agent -H bash --login -c "jq -e '.mcpServers | has(\"jira-atlassian-mcp\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-10" "jira-atlassian-mcp gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"
  run sudo -u agent -H bash --login -c "grep -q 'agentlinux-mcp:jira-atlassian-mcp' ${CODEX_TOML}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-10" "jira-atlassian-mcp block gone from ${CODEX_TOML} after remove" "block remains" "$LOG"
  _assert_gone_if_present gemini "jq -e '.mcpServers | has(\"jira-atlassian-mcp\")' /home/agent/.gemini/settings.json"
  _assert_gone_if_present qwen "jq -e '.mcpServers | has(\"jira-atlassian-mcp\")' /home/agent/.qwen/settings.json"
  _assert_gone_if_present opencode "jq -e '.mcp | has(\"jira-atlassian-mcp\")' /home/agent/.config/opencode/opencode.json"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force jira-atlassian-mcp'
  assert_exit_zero "MCP-10 (idempotent re-remove)"
}

@test "MCP-10: jira-atlassian-mcp entry shape — official hosted remote-http, thin installer, Apache-2.0 + GA-date pin" {
  # source_kind mcp, https endpoint_url, requires_secret true (needs in-client
  # auth), NO secret_env (ADR-017), license Apache-2.0 (the official repo's
  # license — recorded even though pinned_version is a GA date, since the hosted
  # endpoint has no downloadable release: version and license are independent).
  run bash -c "jq -r '.agents[] | select(.id==\"jira-atlassian-mcp\") | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.license) \\(.pinned_version) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "MCP-10 (entry shape)"
  if [[ "${output}" != "mcp true null Apache-2.0 2026.2.4 https://mcp.atlassian.com/v1/mcp/authv2" ]]; then
    __fail "MCP-10" "mcp + requires_secret true + NO secret_env + Apache-2.0 + GA-date pin + https endpoint" "${output:-<empty>}" "$LOG"
  fi

  # Official hosted only: the recipe must register the URL, NOT a third-party
  # stdio server (npx) or a Docker image.
  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/jira-atlassian-mcp/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE 'npx|docker|ghcr\\.io'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-10" "recipe registers ONLY the official hosted endpoint (no npx/docker)" "${output}" "$LOG"
}
