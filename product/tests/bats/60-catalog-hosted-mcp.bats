#!/usr/bin/env bats
# tests/bats/60-catalog-hosted-mcp.bats — every HOSTED remote-http MCP entry.
#
# Replaces six near-identical per-tool files (60-github / 61-sentry /
# 62-firecrawl / 63-slack / 64-linear / 65-jira-atlassian, ~860 lines). They
# differed in four values — the tool id, its credential regex, its catalog entry
# shape, and the third-party-server pattern its recipe must not contain — so they
# are a table here, driven through two shared helpers. This mirrors the house
# pattern already used by 53-catalog-npm-cluster.bats's `_agent_lifecycle`.
#
# THIN INSTALLER (ADR-018): each of these registers a vendor's OFFICIAL hosted
# remote MCP server as a BARE URL — no credential — into EVERY installed
# MCP-capable agent (claude-code, codex, antigravity-cli, opencode, qwen-code)
# via plugin/catalog/lib/mcp-register.sh. AgentLinux stores NO token; the user
# authenticates in-client on first use. `remove` deregisters from all agents
# symmetrically and leaves no residue.

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/catalog/catalog.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
CLAUDE_JSON=/home/agent/.claude.json
CODEX_TOML=/home/agent/.codex/config.toml

# Every hosted-MCP id this file covers — the one list setup/teardown iterate.
HOSTED_MCP_IDS=(github-mcp sentry-mcp firecrawl-mcp slack-mcp linear-mcp jira-atlassian-mcp)

# Credential-shaped strings that must NEVER reach a config (ADR-018). The common
# half (auth header + token field) is shared; each tool adds its own vendor token
# prefix. Kept tight to avoid false positives from unrelated claude-code state
# already present in ~/.claude.json.
CRED_RE_COMMON='[Aa]uthorization|[Bb]earer|bearer_token'

# Per-tool vendor token prefixes, appended to CRED_RE_COMMON.
_cred_re() {
  case "$1" in
    github-mcp) printf '%s|ghp_[A-Za-z0-9]|github_pat_[A-Za-z0-9]' "$CRED_RE_COMMON" ;;
    sentry-mcp) printf '%s|sntrys_' "$CRED_RE_COMMON" ;;
    firecrawl-mcp) printf '%s|fc-[0-9A-Fa-f]' "$CRED_RE_COMMON" ;;
    slack-mcp) printf '%s|xox[bpcd]-' "$CRED_RE_COMMON" ;;
    linear-mcp) printf '%s|lin_(api|oauth)_' "$CRED_RE_COMMON" ;;
    jira-atlassian-mcp) printf '%s|ATATT|ATCTT' "$CRED_RE_COMMON" ;;
    *) printf '%s' "$CRED_RE_COMMON" ;;
  esac
}

# Third-party / stdio / container server patterns a recipe must NOT contain: each
# entry must register the OFFICIAL hosted endpoint and nothing else. `docker` and
# `ghcr.io` are universal; the rest are the specific community servers that exist
# for that vendor and would be the tempting wrong answer.
_forbidden_re() {
  case "$1" in
    slack-mcp) printf 'korotovsky|npx|xox[cd]|docker|ghcr\\.io' ;;
    linear-mcp) printf 'npx|tacticlaunch|jerhadf|docker|ghcr\\.io' ;;
    jira-atlassian-mcp) printf 'npx|docker|ghcr\\.io' ;;
    *) printf 'docker|ghcr\\.io' ;;
  esac
}

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    /opt/agentlinux-src/plugin/bin/agentlinux provision --user agent --yes >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux install codex' >/dev/null 2>&1 || true
  local id
  for id in "${HOSTED_MCP_IDS[@]}"; do
    sudo -u agent -H bash --login -c "agentlinux remove --force ${id}" >/dev/null 2>&1 || true
  done
}

teardown_file() {
  [[ -L /home/agent/.npm-global/bin/agentlinux ]] || return 0
  local id
  for id in "${HOSTED_MCP_IDS[@]}"; do
    sudo -u agent -H bash --login -c "agentlinux remove --force ${id}" >/dev/null 2>&1 || true
  done
}

# An agent that is not installed cannot carry a registration — skip its assertion
# rather than failing, so the file stays green whichever agents a host has.
_assert_present_if_installed() {
  local req=$1 bin=$2 cmd=$3
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 \
    || { __diag "${req}: ${bin} not installed — fan-out assertion skipped"; return 0; }
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "${req} (${bin} carries the bare entry)"
}

_assert_gone_if_present() {
  local req=$1 id=$2 bin=$3 cmd=$4
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "${bin} config still carries ${id} after remove" "residue" "$LOG"
}

# _hosted_mcp_lifecycle <req> <id>
# install → assert a BARE url landed in every present agent → assert NO
# credential anywhere → remove → assert no residue → idempotent re-remove.
_hosted_mcp_lifecycle() {
  local req=$1 id=$2
  local cred_re
  cred_re=$(_cred_re "$id")

  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "${req} (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "${req} (codex present precondition)"

  local url
  url=$(jq -r --arg i "$id" '.agents[] | select(.id==$i) | .endpoint_url' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "$req" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi

  run sudo -u agent -H bash --login -c "agentlinux install ${id}"
  assert_exit_zero "${req} (install)"
  assert_no_eacces "${req} (install)" "$output"

  if ! printf '%s' "${output}" | grep -qiE 'authenticate from within your coding agent|in-client|oauth'; then
    __fail "$req" "install surfaces the in-client auth pointer" "${output:-<empty>}" "$LOG"
  fi

  # claude: bare http registration at the pinned endpoint, NO auth header.
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"${id}\"] | .type==\"http\" and .url==\$u and (has(\"headers\")|not)' ${CLAUDE_JSON}"
  assert_exit_zero "${req} (claude bare http registration, no headers)"

  # codex: pinned url inside the marker block, NO bearer/token field.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:${id} >>>/,/agentlinux-mcp:${id} <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "${req} (codex registered at pinned url)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:${id} >>>/,/agentlinux-mcp:${id} <<</p' ${CODEX_TOML} | grep -qiE 'bearer|token'"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "codex ${id} block carries NO bearer/token (bare url)" "token field present" "$LOG"

  _assert_present_if_installed "$req" agy \
    "jq -e --arg u \"${url}\" '.mcpServers[\"${id}\"] | .serverUrl==\$u and (has(\"headers\")|not)' /home/agent/.gemini/config/mcp_config.json"
  _assert_present_if_installed "$req" qwen \
    "jq -e --arg u \"${url}\" '.mcpServers[\"${id}\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.qwen/settings.json"
  _assert_present_if_installed "$req" opencode \
    "jq -e --arg u \"${url}\" '.mcp[\"${id}\"] | .type==\"remote\" and .url==\$u and (has(\"headers\")|not)' /home/agent/.config/opencode/opencode.json"

  # THIN INSTALLER: no credential-shaped string in ANY agent config (ADR-018).
  run sudo -u agent -H bash --login -c \
    "grep -rIqE '${cred_re}' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "NO credential in any agent config (thin installer, ADR-018)" "credential-shaped string found" "$LOG"

  run sudo -u agent -H bash --login -c "agentlinux remove --force ${id}"
  assert_exit_zero "${req} (remove)"
  assert_no_eacces "${req} (remove)" "$output"

  run sudo -u agent -H bash --login -c "jq -e '.mcpServers | has(\"${id}\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "${id} gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"
  run sudo -u agent -H bash --login -c "grep -q 'agentlinux-mcp:${id}' ${CODEX_TOML}"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "${id} block gone from ${CODEX_TOML} after remove" "block remains" "$LOG"
  _assert_gone_if_present "$req" "$id" agy \
    "jq -e '.mcpServers | has(\"${id}\")' /home/agent/.gemini/config/mcp_config.json"
  _assert_gone_if_present "$req" "$id" qwen \
    "jq -e '.mcpServers | has(\"${id}\")' /home/agent/.qwen/settings.json"
  _assert_gone_if_present "$req" "$id" opencode \
    "jq -e '.mcp | has(\"${id}\")' /home/agent/.config/opencode/opencode.json"

  run sudo -u agent -H bash --login -c "agentlinux remove --force ${id}"
  assert_exit_zero "${req} (idempotent re-remove)"
}

# _hosted_mcp_entry_shape <req> <id> <expected>
# The catalog entry is a thin hosted remote: source_kind mcp, requires_secret
# true (in-client auth IS required), NO secret_env (ADR-018 bakes nothing), the
# declared license, and an https endpoint. `pinned_version` is deliberately NOT
# asserted here — it churns with every curated bump and is gated by CAT-04
# (40-registry-cli.bats) plus the required+semver pattern in schema.json.
#
# Also asserts the recipe registers ONLY the official hosted endpoint: no
# third-party stdio server, no npx, no container image.
_hosted_mcp_entry_shape() {
  local req=$1 id=$2 expected=$3
  local forbidden
  forbidden=$(_forbidden_re "$id")

  run bash -c "jq -r --arg i '${id}' '.agents[] | select(.id==\$i) | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.license) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "${req} (entry shape)"
  if [[ "${output}" != "$expected" ]]; then
    __fail "$req" "entry shape: ${expected}" "${output:-<empty>}" "$LOG"
  fi

  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/${id}/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE '${forbidden}'"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "recipe registers ONLY the official hosted endpoint (no third-party/stdio/docker)" "${output}" "$LOG"
}

# ---- per-tool tests ---------------------------------------------------------

@test "MCP-03: github-mcp bare-URL register → deregister lifecycle" {
  _hosted_mcp_lifecycle "MCP-03" github-mcp
}

@test "MCP-03: github-mcp entry shape — official hosted remote-http, thin installer" {
  _hosted_mcp_entry_shape "MCP-03" github-mcp "mcp true null MIT https://api.githubcopilot.com/mcp/"
}

@test "MCP-04: sentry-mcp bare-URL register → deregister lifecycle" {
  _hosted_mcp_lifecycle "MCP-04" sentry-mcp
}

@test "MCP-04: sentry-mcp entry shape — official hosted remote-http, thin installer" {
  _hosted_mcp_entry_shape "MCP-04" sentry-mcp "mcp true null FSL-1.1-ALv2 https://mcp.sentry.dev/mcp"
}

@test "MCP-07: firecrawl-mcp bare-URL register → deregister lifecycle" {
  _hosted_mcp_lifecycle "MCP-07" firecrawl-mcp
}

@test "MCP-07: firecrawl-mcp entry shape — official hosted remote-http, thin installer" {
  _hosted_mcp_entry_shape "MCP-07" firecrawl-mcp "mcp true null MIT https://mcp.firecrawl.dev/v2/mcp"
}

@test "MCP-08: slack-mcp bare-URL register → deregister lifecycle" {
  _hosted_mcp_lifecycle "MCP-08" slack-mcp
}

@test "MCP-08: slack-mcp entry shape — official hosted remote-http, thin installer" {
  _hosted_mcp_entry_shape "MCP-08" slack-mcp "mcp true null null https://mcp.slack.com/mcp"
}

@test "MCP-09: linear-mcp bare-URL register → deregister lifecycle" {
  _hosted_mcp_lifecycle "MCP-09" linear-mcp
}

@test "MCP-09: linear-mcp entry shape — official hosted remote-http, thin installer" {
  _hosted_mcp_entry_shape "MCP-09" linear-mcp "mcp true null null https://mcp.linear.app/mcp"
}

@test "MCP-10: jira-atlassian-mcp bare-URL register → deregister lifecycle" {
  _hosted_mcp_lifecycle "MCP-10" jira-atlassian-mcp
}

@test "MCP-10: jira-atlassian-mcp entry shape — official hosted remote-http, thin installer" {
  _hosted_mcp_entry_shape "MCP-10" jira-atlassian-mcp "mcp true null Apache-2.0 https://mcp.atlassian.com/v1/mcp/authv2"
}
