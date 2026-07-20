#!/usr/bin/env bats
# tests/bats/63-catalog-slack-mcp.bats — v0.3.6 Phase 41 (slack-mcp) MCP-08.
#
# THIN INSTALLER (ADR-017): slack-mcp registers Slack's OFFICIAL hosted remote MCP
# server as a BARE URL — no credential — into EVERY installed MCP-capable agent
# (claude-code, codex, antigravity-cli, opencode, qwen-code) via the shared helper
# plugin/catalog/lib/mcp-register.sh. AgentLinux stores NO token; the user
# authenticates in-client (Slack OAuth, admin-approved) on first use. `remove`
# deregisters from all agents symmetrically. Fourth consumer of the ENABLE-02
# remote-http helper.
#
# Source note: this uses Slack's first-party admin-governed endpoint
# (https://mcp.slack.com/mcp), NOT the third-party korotovsky server whose
# xoxc/xoxd "stealth" tokens bypass workspace-admin approval. The no-credential
# grep below asserts no Slack token (xoxb/xoxp/xoxc/xoxd) ever lands in a config.
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
# tight (auth-header + token-field shapes + every Slack token prefix) to avoid
# false positives from unrelated claude-code state written into ~/.claude.json.
CRED_RE='[Aa]uthorization|[Bb]earer|bearer_token|xox[bpcd]-'

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux install codex' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux remove --force slack-mcp' >/dev/null 2>&1 || true
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force slack-mcp' >/dev/null 2>&1 || true
  fi
}

_assert_present_if_installed() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 \
    || { __diag "MCP-08: ${bin} not installed — fan-out assertion skipped"; return 0; }
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "MCP-08 (${bin} carries the bare slack-mcp entry)"
}

_assert_gone_if_present() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-08" "${bin} config still carries slack-mcp after remove" "residue" "$LOG"
}

@test "MCP-08: slack-mcp registers a BARE remote URL (no credential, ADR-017) into every installed agent, then deregisters with no residue" {
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-08 (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "MCP-08 (codex present precondition)"

  local url
  url=$(jq -r '.agents[] | select(.id=="slack-mcp") | .endpoint_url' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "MCP-08" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi

  run sudo -u agent -H bash --login -c 'agentlinux install slack-mcp'
  assert_exit_zero "MCP-08 (install)"
  assert_no_eacces "MCP-08 (install)" "$output"

  if ! printf '%s' "${output}" | grep -qiE 'authenticate from within your coding agent|in-client|oauth'; then
    __fail "MCP-08" "install surfaces the in-client auth pointer" "${output:-<empty>}" "$LOG"
  fi

  # claude: bare http registration at the pinned endpoint, NO auth header.
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"slack-mcp\"] | .type==\"http\" and .url==\$u and (has(\"headers\")|not)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-08 (claude bare http registration, no headers)"

  # codex: pinned url in the slack-mcp marker block, NO bearer/token field.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:slack-mcp >>>/,/agentlinux-mcp:slack-mcp <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "MCP-08 (codex registered at pinned url)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:slack-mcp >>>/,/agentlinux-mcp:slack-mcp <<</p' ${CODEX_TOML} | grep -qiE 'bearer|token'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-08" "codex slack-mcp block carries NO bearer/token (bare url)" "token field present" "$LOG"

  _assert_present_if_installed agy "jq -e --arg u \"${url}\" '.mcpServers[\"slack-mcp\"] | .serverUrl==\$u and (has(\"headers\")|not)' /home/agent/.gemini/config/mcp_config.json"
  _assert_present_if_installed qwen "jq -e --arg u \"${url}\" '.mcpServers[\"slack-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.qwen/settings.json"
  _assert_present_if_installed opencode "jq -e --arg u \"${url}\" '.mcp[\"slack-mcp\"] | .type==\"remote\" and .url==\$u and (has(\"headers\")|not)' /home/agent/.config/opencode/opencode.json"

  # THIN INSTALLER: no credential-shaped string in ANY agent config (ADR-017) —
  # in particular no Slack token (xoxb/xoxp/xoxc/xoxd).
  run sudo -u agent -H bash --login -c \
    "grep -rIqE '${CRED_RE}' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-08" "NO credential in any agent config (thin installer, ADR-017)" "credential-shaped string found" "$LOG"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force slack-mcp'
  assert_exit_zero "MCP-08 (remove)"
  assert_no_eacces "MCP-08 (remove)" "$output"

  run sudo -u agent -H bash --login -c "jq -e '.mcpServers | has(\"slack-mcp\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-08" "slack-mcp gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"
  run sudo -u agent -H bash --login -c "grep -q 'agentlinux-mcp:slack-mcp' ${CODEX_TOML}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-08" "slack-mcp block gone from ${CODEX_TOML} after remove" "block remains" "$LOG"
  _assert_gone_if_present agy "jq -e '.mcpServers | has(\"slack-mcp\")' /home/agent/.gemini/config/mcp_config.json"
  _assert_gone_if_present qwen "jq -e '.mcpServers | has(\"slack-mcp\")' /home/agent/.qwen/settings.json"
  _assert_gone_if_present opencode "jq -e '.mcp | has(\"slack-mcp\")' /home/agent/.config/opencode/opencode.json"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force slack-mcp'
  assert_exit_zero "MCP-08 (idempotent re-remove)"
}

@test "MCP-08: slack-mcp entry shape — official hosted remote-http, thin installer, no package license" {
  # source_kind mcp, https endpoint_url, requires_secret true (needs in-client
  # auth), NO secret_env (ADR-017), and NO license (Slack's proprietary hosted
  # service has no downloadable package to license).
  run bash -c "jq -r '.agents[] | select(.id==\"slack-mcp\") | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.license) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "MCP-08 (entry shape)"
  if [[ "${output}" != "mcp true null null https://mcp.slack.com/mcp" ]]; then
    __fail "MCP-08" "mcp + requires_secret true + NO secret_env + NO license + https endpoint" "${output:-<empty>}" "$LOG"
  fi

  # First-party only: the recipe must NOT reference the third-party stealth-token
  # server (korotovsky / xoxc / xoxd / npx slack-mcp-server).
  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/slack-mcp/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE 'korotovsky|npx|xox[cd]|docker|ghcr\\.io'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-08" "recipe registers ONLY the official hosted endpoint (no third-party/stealth/docker)" "${output}" "$LOG"
}
