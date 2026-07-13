#!/usr/bin/env bats
# tests/bats/62-catalog-gitlab-mcp.bats — v0.3.6 Phase 38 (gitlab-mcp) MCP-05.
#
# THIN INSTALLER (ADR-017): gitlab-mcp registers GitLab's OFFICIAL first-party
# hosted MCP endpoint as a BARE URL — no credential — into EVERY installed
# MCP-capable agent via the shared helper plugin/catalog/lib/mcp-register.sh.
# AgentLinux stores NO token; the user authenticates in-client (GitLab OAuth).
# `remove` deregisters from all agents symmetrically. Third consumer of the
# ENABLE-02 remote-http helper.
#
# Installs claude-code + codex as preconditions and asserts bare-URL fan-out into
# BOTH, that NO credential lands in any config, and residue-free symmetric removal.
# gemini/opencode/qwen are asserted only if present.
#
# Design invariants: see tests/bats/60-catalog-github-mcp.bats (identical shape).

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
CLAUDE_JSON=/home/agent/.claude.json
CODEX_TOML=/home/agent/.codex/config.toml
# Credential-shaped strings that must NEVER appear in a config (ADR-017): kept
# tight (auth-header + token-field shapes + the GitLab PAT prefix) to avoid
# false positives from unrelated client state.
CRED_RE='[Aa]uthorization|[Bb]earer|bearer_token|PRIVATE-TOKEN|glpat-'

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux install codex' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux remove --force gitlab-mcp' >/dev/null 2>&1 || true
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force gitlab-mcp' >/dev/null 2>&1 || true
  fi
}

_assert_present_if_installed() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 \
    || { __diag "MCP-05: ${bin} not installed — fan-out assertion skipped"; return 0; }
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "MCP-05 (${bin} carries the bare gitlab-mcp entry)"
}

_assert_gone_if_present() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-05" "${bin} config still carries gitlab-mcp after remove" "residue" "$LOG"
}

@test "MCP-05: gitlab-mcp registers a BARE remote URL (no credential, ADR-017) into every installed agent, then deregisters with no residue" {
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-05 (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "MCP-05 (codex present precondition)"

  local url
  url=$(jq -r '.agents[] | select(.id=="gitlab-mcp") | .endpoint_url' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "MCP-05" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi

  run sudo -u agent -H bash --login -c 'agentlinux install gitlab-mcp'
  assert_exit_zero "MCP-05 (install)"
  assert_no_eacces "MCP-05 (install)" "$output"

  if ! printf '%s' "${output}" | grep -qiE 'authenticate from within your coding agent|in-client|oauth'; then
    __fail "MCP-05" "install surfaces the in-client auth pointer" "${output:-<empty>}" "$LOG"
  fi

  # claude: bare http registration at the pinned endpoint, NO auth header.
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"gitlab-mcp\"] | .type==\"http\" and .url==\$u and (has(\"headers\")|not)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-05 (claude bare http registration, no headers)"

  # codex: pinned url in the gitlab-mcp marker block, NO bearer/token field.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:gitlab-mcp >>>/,/agentlinux-mcp:gitlab-mcp <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "MCP-05 (codex registered at pinned url)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:gitlab-mcp >>>/,/agentlinux-mcp:gitlab-mcp <<</p' ${CODEX_TOML} | grep -qiE 'bearer|token'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-05" "codex gitlab-mcp block carries NO bearer/token (bare url)" "token field present" "$LOG"

  _assert_present_if_installed gemini "jq -e --arg u \"${url}\" '.mcpServers[\"gitlab-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.gemini/settings.json"
  _assert_present_if_installed qwen "jq -e --arg u \"${url}\" '.mcpServers[\"gitlab-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.qwen/settings.json"
  _assert_present_if_installed opencode "jq -e --arg u \"${url}\" '.mcp[\"gitlab-mcp\"] | .type==\"remote\" and .url==\$u and (has(\"headers\")|not)' /home/agent/.config/opencode/opencode.json"

  # THIN INSTALLER: no credential-shaped string in ANY agent config (ADR-017).
  run sudo -u agent -H bash --login -c \
    "grep -rIqE '${CRED_RE}' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-05" "NO credential in any agent config (thin installer, ADR-017)" "credential-shaped string found" "$LOG"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force gitlab-mcp'
  assert_exit_zero "MCP-05 (remove)"
  assert_no_eacces "MCP-05 (remove)" "$output"

  run sudo -u agent -H bash --login -c "jq -e '.mcpServers | has(\"gitlab-mcp\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-05" "gitlab-mcp gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"
  run sudo -u agent -H bash --login -c "grep -q 'agentlinux-mcp:gitlab-mcp' ${CODEX_TOML}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-05" "gitlab-mcp block gone from ${CODEX_TOML} after remove" "block remains" "$LOG"
  _assert_gone_if_present gemini "jq -e '.mcpServers | has(\"gitlab-mcp\")' /home/agent/.gemini/settings.json"
  _assert_gone_if_present qwen "jq -e '.mcpServers | has(\"gitlab-mcp\")' /home/agent/.qwen/settings.json"
  _assert_gone_if_present opencode "jq -e '.mcp | has(\"gitlab-mcp\")' /home/agent/.config/opencode/opencode.json"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force gitlab-mcp'
  assert_exit_zero "MCP-05 (idempotent re-remove)"
}

@test "MCP-05: gitlab-mcp entry shape — official first-party hosted remote-http, thin installer" {
  # source_kind mcp, https endpoint_url, requires_secret true (needs in-client
  # auth), NO secret_env (ADR-017).
  run bash -c "jq -r '.agents[] | select(.id==\"gitlab-mcp\") | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "MCP-05 (entry shape)"
  if [[ "${output}" != "mcp true null https://gitlab.com/api/v4/mcp" ]]; then
    __fail "MCP-05" "mcp + requires_secret true + NO secret_env + https endpoint" "${output:-<empty>}" "$LOG"
  fi

  # No Docker recipe, and NOT the third-party npx server (first-party hosted only).
  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/gitlab-mcp/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE 'docker|ghcr\\.io|zereight|npx'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-05" "recipe uses the official hosted endpoint (no docker/npx/third-party)" "${output}" "$LOG"
}
