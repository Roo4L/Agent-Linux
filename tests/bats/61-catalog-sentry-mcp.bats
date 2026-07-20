#!/usr/bin/env bats
# tests/bats/61-catalog-sentry-mcp.bats — v0.3.6 Phase 37 (sentry-mcp) MCP-04.
#
# THIN INSTALLER (ADR-017): sentry-mcp registers Sentry's hosted remote MCP server
# as a BARE URL — no credential — into EVERY installed MCP-capable agent
# (claude-code, codex, antigravity-cli, opencode, qwen-code) via the shared helper
# plugin/catalog/lib/mcp-register.sh. AgentLinux stores NO token; the user
# authenticates in-client (Sentry OAuth) on first use. `remove` deregisters from
# all agents symmetrically. Second consumer of the ENABLE-02 remote-http helper.
#
# Installs claude-code + codex as preconditions and asserts bare-URL fan-out into
# BOTH, that NO credential lands in any config, and residue-free symmetric removal.
# antigravity/opencode/qwen are asserted only if present.
#
# Design invariants: see tests/bats/60-catalog-github-mcp.bats (identical shape).

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
CLAUDE_JSON=/home/agent/.claude.json
CODEX_TOML=/home/agent/.codex/config.toml
# Credential-shaped strings that must NEVER appear in a config (ADR-017). Kept
# tight (auth-header + token-field shapes + the Sentry token prefix) to avoid
# false positives from unrelated claude-code state written into ~/.claude.json.
CRED_RE='[Aa]uthorization|[Bb]earer|bearer_token|sntrys_'

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux install codex' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux remove --force sentry-mcp' >/dev/null 2>&1 || true
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force sentry-mcp' >/dev/null 2>&1 || true
  fi
}

_assert_present_if_installed() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 \
    || { __diag "MCP-04: ${bin} not installed — fan-out assertion skipped"; return 0; }
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "MCP-04 (${bin} carries the bare sentry-mcp entry)"
}

_assert_gone_if_present() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-04" "${bin} config still carries sentry-mcp after remove" "residue" "$LOG"
}

@test "MCP-04: sentry-mcp registers a BARE remote URL (no credential, ADR-017) into every installed agent, then deregisters with no residue" {
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-04 (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "MCP-04 (codex present precondition)"

  local url
  url=$(jq -r '.agents[] | select(.id=="sentry-mcp") | .endpoint_url' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "MCP-04" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi

  run sudo -u agent -H bash --login -c 'agentlinux install sentry-mcp'
  assert_exit_zero "MCP-04 (install)"
  assert_no_eacces "MCP-04 (install)" "$output"

  if ! printf '%s' "${output}" | grep -qiE 'authenticate from within your coding agent|in-client|oauth'; then
    __fail "MCP-04" "install surfaces the in-client auth pointer" "${output:-<empty>}" "$LOG"
  fi

  # claude: bare http registration at the pinned endpoint, NO auth header.
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"sentry-mcp\"] | .type==\"http\" and .url==\$u and (has(\"headers\")|not)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-04 (claude bare http registration, no headers)"

  # codex: pinned url in the sentry-mcp marker block, NO bearer/token field.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:sentry-mcp >>>/,/agentlinux-mcp:sentry-mcp <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "MCP-04 (codex registered at pinned url)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:sentry-mcp >>>/,/agentlinux-mcp:sentry-mcp <<</p' ${CODEX_TOML} | grep -qiE 'bearer|token'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-04" "codex sentry-mcp block carries NO bearer/token (bare url)" "token field present" "$LOG"

  _assert_present_if_installed agy "jq -e --arg u \"${url}\" '.mcpServers[\"sentry-mcp\"] | .serverUrl==\$u and (has(\"headers\")|not)' /home/agent/.gemini/config/mcp_config.json"
  _assert_present_if_installed qwen "jq -e --arg u \"${url}\" '.mcpServers[\"sentry-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.qwen/settings.json"
  _assert_present_if_installed opencode "jq -e --arg u \"${url}\" '.mcp[\"sentry-mcp\"] | .type==\"remote\" and .url==\$u and (has(\"headers\")|not)' /home/agent/.config/opencode/opencode.json"

  # THIN INSTALLER: no credential-shaped string in ANY agent config (ADR-017).
  run sudo -u agent -H bash --login -c \
    "grep -rIqE '${CRED_RE}' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-04" "NO credential in any agent config (thin installer, ADR-017)" "credential-shaped string found" "$LOG"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force sentry-mcp'
  assert_exit_zero "MCP-04 (remove)"
  assert_no_eacces "MCP-04 (remove)" "$output"

  run sudo -u agent -H bash --login -c "jq -e '.mcpServers | has(\"sentry-mcp\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-04" "sentry-mcp gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"
  run sudo -u agent -H bash --login -c "grep -q 'agentlinux-mcp:sentry-mcp' ${CODEX_TOML}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-04" "sentry-mcp block gone from ${CODEX_TOML} after remove" "block remains" "$LOG"
  _assert_gone_if_present agy "jq -e '.mcpServers | has(\"sentry-mcp\")' /home/agent/.gemini/config/mcp_config.json"
  _assert_gone_if_present qwen "jq -e '.mcpServers | has(\"sentry-mcp\")' /home/agent/.qwen/settings.json"
  _assert_gone_if_present opencode "jq -e '.mcp | has(\"sentry-mcp\")' /home/agent/.config/opencode/opencode.json"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force sentry-mcp'
  assert_exit_zero "MCP-04 (idempotent re-remove)"
}

@test "MCP-04: sentry-mcp entry shape — hosted remote-http, thin installer, FSL license recorded" {
  # source_kind mcp, https endpoint_url, requires_secret true (needs in-client
  # auth), NO secret_env (ADR-017), and the FSL-1.1-ALv2 license flag recorded.
  run bash -c "jq -r '.agents[] | select(.id==\"sentry-mcp\") | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.license) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "MCP-04 (entry shape)"
  if [[ "${output}" != "mcp true null FSL-1.1-ALv2 https://mcp.sentry.dev/mcp" ]]; then
    __fail "MCP-04" "mcp + requires_secret true + NO secret_env + FSL-1.1-ALv2 + https endpoint" "${output:-<empty>}" "$LOG"
  fi

  # No Docker recipe (consistency with the whole MCP cluster).
  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/sentry-mcp/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE 'docker|ghcr\\.io'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-04" "recipe uses NO docker/ghcr" "${output}" "$LOG"
}
