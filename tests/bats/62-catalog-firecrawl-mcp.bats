#!/usr/bin/env bats
# tests/bats/62-catalog-firecrawl-mcp.bats — v0.3.6 Phase 40 (firecrawl-mcp) MCP-07.
#
# THIN INSTALLER (ADR-017): firecrawl-mcp registers Firecrawl's hosted remote MCP
# server as a BARE URL — no credential — into EVERY installed MCP-capable agent
# (claude-code, codex, gemini-cli, opencode, qwen-code) via the shared helper
# plugin/catalog/lib/mcp-register.sh. AgentLinux stores NO token.
#
# Distinct from sentry-mcp/github-mcp: Firecrawl's endpoint is KEYLESS — the bare
# URL works out of the box with no signup (requires_secret=false). A user who
# wants their own recurring quota re-registers with a personal key in the URL path
# (Firecrawl authenticates by URL path, not a header). `remove` deregisters from
# all agents symmetrically. Third consumer of the ENABLE-02 remote-http helper.
#
# Installs claude-code + codex as preconditions and asserts bare-URL fan-out into
# BOTH, that NO credential lands in any config, and residue-free symmetric removal.
# gemini/opencode/qwen are asserted only if present.
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
# tight (auth-header + token-field shapes + the Firecrawl key prefix `fc-`) to
# avoid false positives from unrelated claude-code state written into ~/.claude.json.
CRED_RE='[Aa]uthorization|[Bb]earer|bearer_token|fc-[0-9A-Fa-f]'

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux install codex' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux remove --force firecrawl-mcp' >/dev/null 2>&1 || true
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force firecrawl-mcp' >/dev/null 2>&1 || true
  fi
}

_assert_present_if_installed() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 \
    || { __diag "MCP-07: ${bin} not installed — fan-out assertion skipped"; return 0; }
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "MCP-07 (${bin} carries the bare firecrawl-mcp entry)"
}

_assert_gone_if_present() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-07" "${bin} config still carries firecrawl-mcp after remove" "residue" "$LOG"
}

@test "MCP-07: firecrawl-mcp registers a BARE keyless remote URL (no credential, ADR-017) into every installed agent, then deregisters with no residue" {
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-07 (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "MCP-07 (codex present precondition)"

  local url
  url=$(jq -r '.agents[] | select(.id=="firecrawl-mcp") | .endpoint_url' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "MCP-07" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi

  run sudo -u agent -H bash --login -c 'agentlinux install firecrawl-mcp'
  assert_exit_zero "MCP-07 (install)"
  assert_no_eacces "MCP-07 (install)" "$output"

  # Keyless installer surfaces the optional-key upgrade pointer (NOT an OAuth note).
  if ! printf '%s' "${output}" | grep -qiE 'keyless|api-keys|re-register'; then
    __fail "MCP-07" "install surfaces the keyless / optional-key pointer" "${output:-<empty>}" "$LOG"
  fi

  # claude: bare http registration at the pinned endpoint, NO auth header.
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"firecrawl-mcp\"] | .type==\"http\" and .url==\$u and (has(\"headers\")|not)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-07 (claude bare http registration, no headers)"

  # codex: pinned url in the firecrawl-mcp marker block, NO bearer/token field.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:firecrawl-mcp >>>/,/agentlinux-mcp:firecrawl-mcp <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "MCP-07 (codex registered at pinned url)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:firecrawl-mcp >>>/,/agentlinux-mcp:firecrawl-mcp <<</p' ${CODEX_TOML} | grep -qiE 'bearer|token'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-07" "codex firecrawl-mcp block carries NO bearer/token (bare url)" "token field present" "$LOG"

  _assert_present_if_installed gemini "jq -e --arg u \"${url}\" '.mcpServers[\"firecrawl-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.gemini/settings.json"
  _assert_present_if_installed qwen "jq -e --arg u \"${url}\" '.mcpServers[\"firecrawl-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.qwen/settings.json"
  _assert_present_if_installed opencode "jq -e --arg u \"${url}\" '.mcp[\"firecrawl-mcp\"] | .type==\"remote\" and .url==\$u and (has(\"headers\")|not)' /home/agent/.config/opencode/opencode.json"

  # THIN INSTALLER: no credential-shaped string in ANY agent config (ADR-017).
  run sudo -u agent -H bash --login -c \
    "grep -rIqE '${CRED_RE}' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-07" "NO credential in any agent config (thin installer, ADR-017)" "credential-shaped string found" "$LOG"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force firecrawl-mcp'
  assert_exit_zero "MCP-07 (remove)"
  assert_no_eacces "MCP-07 (remove)" "$output"

  run sudo -u agent -H bash --login -c "jq -e '.mcpServers | has(\"firecrawl-mcp\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-07" "firecrawl-mcp gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"
  run sudo -u agent -H bash --login -c "grep -q 'agentlinux-mcp:firecrawl-mcp' ${CODEX_TOML}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-07" "firecrawl-mcp block gone from ${CODEX_TOML} after remove" "block remains" "$LOG"
  _assert_gone_if_present gemini "jq -e '.mcpServers | has(\"firecrawl-mcp\")' /home/agent/.gemini/settings.json"
  _assert_gone_if_present qwen "jq -e '.mcpServers | has(\"firecrawl-mcp\")' /home/agent/.qwen/settings.json"
  _assert_gone_if_present opencode "jq -e '.mcp | has(\"firecrawl-mcp\")' /home/agent/.config/opencode/opencode.json"

  run sudo -u agent -H bash --login -c 'agentlinux remove --force firecrawl-mcp'
  assert_exit_zero "MCP-07 (idempotent re-remove)"
}

@test "MCP-07: firecrawl-mcp entry shape — hosted keyless remote-http, thin installer, MIT license" {
  # source_kind mcp, https endpoint_url, requires_secret FALSE (keyless — no
  # in-client auth needed), NO secret_env (ADR-017), MIT license.
  run bash -c "jq -r '.agents[] | select(.id==\"firecrawl-mcp\") | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.license) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "MCP-07 (entry shape)"
  if [[ "${output}" != "mcp false null MIT https://mcp.firecrawl.dev/v2/mcp" ]]; then
    __fail "MCP-07" "mcp + requires_secret false + NO secret_env + MIT + https endpoint" "${output:-<empty>}" "$LOG"
  fi

  # No Docker recipe (consistency with the whole MCP cluster).
  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/firecrawl-mcp/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE 'docker|ghcr\\.io'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-07" "recipe uses NO docker/ghcr" "${output}" "$LOG"
}
