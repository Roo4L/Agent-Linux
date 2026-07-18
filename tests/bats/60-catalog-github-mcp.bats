#!/usr/bin/env bats
# tests/bats/60-catalog-github-mcp.bats — v0.3.6 Phase 36 (github-mcp) MCP-03:
# the FIRST remote-http MCP entry AND the first CROSS-AGENT MCP registration.
#
# THIN INSTALLER (ADR-017): github-mcp registers GitHub's hosted remote MCP server
# as a BARE URL — no credential — into EVERY installed MCP-capable agent
# (claude-code, codex, gemini-cli, opencode, qwen-code) via the shared helper
# plugin/catalog/lib/mcp-register.sh. AgentLinux stores NO token; the user
# authenticates in-client (OAuth) on first use. `remove` deregisters from all
# agents symmetrically.
#
# This gate installs claude-code + codex as preconditions (the two the maintainer
# named) and asserts bare-URL fan-out into BOTH, that NO credential lands in any
# config, the no-Docker shape, and residue-free symmetric removal.
# gemini/opencode/qwen are asserted only if present.
#
# Design invariants (behavior-test-contract):
#   - every @test name prefixed with the requirement ID
#   - failures emit __fail four-line TST-04 diagnostics
#   - endpoint read from the provisioned catalog via jq (never hardcoded)
#   - installs run as the agent user through a login shell
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
CLAUDE_JSON=/home/agent/.claude.json
CODEX_TOML=/home/agent/.codex/config.toml
# Any credential-shaped string that must NEVER appear in a config under the
# thin-installer model (ADR-017): auth headers, bearer/token fields, GitHub PATs.
CRED_RE='ghp_[A-Za-z0-9]|github_pat_[A-Za-z0-9]|[Aa]uthorization|[Bb]earer|bearer_token'

setup_file() {
  # Recover the CLI if an earlier --purge @test removed it (mirrors 53/57/58/59).
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  # Preconditions: cross-agent fan-out needs agents present. Install the two the
  # maintainer named (idempotent no-ops if already installed).
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true
  sudo -u agent -H bash --login -c 'agentlinux install codex' >/dev/null 2>&1 || true
  # Defensive scrub of any prior github-mcp registration before any @test.
  sudo -u agent -H bash --login -c 'agentlinux remove --force github-mcp' >/dev/null 2>&1 || true
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force github-mcp' >/dev/null 2>&1 || true
  fi
}

# _assert_present_if_installed <agent-bin> <jq-cmd> — when <agent-bin> is on the
# agent user's PATH, assert <jq-cmd> (its config carries the bare github-mcp entry)
# exits 0. Absent agents are skipped (fan-out only touches present agents).
_assert_present_if_installed() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 \
    || { __diag "MCP-03: ${bin} not installed — fan-out assertion skipped"; return 0; }
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "MCP-03 (${bin} carries the bare github-mcp entry)"
}

# _assert_gone_if_present <agent-bin> <jq-cmd> — when present, assert <jq-cmd>
# (github-mcp still registered) exits NON-zero, i.e. no residue after remove.
_assert_gone_if_present() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "${bin} config still carries github-mcp after remove" "residue" "$LOG"
}

@test "MCP-03: github-mcp registers a BARE remote URL (no credential, ADR-017) into every installed agent, then deregisters with no residue" {
  # Guard: both named-agent preconditions actually held. Fail loud on a missing
  # precondition rather than let a skipped fan-out target look like a register bug.
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-03 (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "MCP-03 (codex present precondition)"

  # Endpoint is jq-derived from the provisioned catalog (never hardcoded).
  local url
  url=$(jq -r '.agents[] | select(.id=="github-mcp") | .endpoint_url' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "MCP-03" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi

  # Register (fan out).
  run sudo -u agent -H bash --login -c 'agentlinux install github-mcp'
  assert_exit_zero "MCP-03 (install)"
  assert_no_eacces "MCP-03 (install)" "$output"

  # In-client-auth pointer surfaced (anchor on wording, not the server name).
  if ! printf '%s' "${output}" | grep -qiE 'authenticate from within your coding agent|in-client|oauth'; then
    __fail "MCP-03" "install surfaces the in-client auth pointer" "${output:-<empty>}" "$LOG"
  fi

  # claude-code: registered as an http server at the pinned endpoint with NO auth
  # header (bare URL — the user OAuths in-client).
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"github-mcp\"] | .type==\"http\" and .url==\$u and (has(\"headers\")|not)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-03 (claude bare http registration, no headers)"

  # codex: the pinned url is registered in github-mcp's marker block, with NO
  # bearer/token field anywhere in that block.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:github-mcp >>>/,/agentlinux-mcp:github-mcp <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "MCP-03 (codex registered at pinned url)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:github-mcp >>>/,/agentlinux-mcp:github-mcp <<</p' ${CODEX_TOML} | grep -qiE 'bearer|token'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "codex github-mcp block carries NO bearer/token (bare url)" "token field present" "$LOG"

  # Cross-agent fan-out: gemini-family + opencode get the SAME bare entry when
  # present. Assert conditionally (they may not be installed on this container).
  _assert_present_if_installed gemini "jq -e --arg u \"${url}\" '.mcpServers[\"github-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.gemini/settings.json"
  _assert_present_if_installed qwen "jq -e --arg u \"${url}\" '.mcpServers[\"github-mcp\"] | .httpUrl==\$u and (has(\"headers\")|not)' /home/agent/.qwen/settings.json"
  _assert_present_if_installed opencode "jq -e --arg u \"${url}\" '.mcp[\"github-mcp\"] | .type==\"remote\" and .url==\$u and (has(\"headers\")|not)' /home/agent/.config/opencode/opencode.json"

  # THIN INSTALLER: no credential-shaped string in ANY agent config (no header,
  # no bearer/token field, no literal PAT). This is the ADR-017 contract.
  run sudo -u agent -H bash --login -c \
    "grep -rIqE '${CRED_RE}' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "NO credential in any agent config (thin installer, ADR-017)" "credential-shaped string found" "$LOG"

  # Deregister (fan out).
  run sudo -u agent -H bash --login -c 'agentlinux remove --force github-mcp'
  assert_exit_zero "MCP-03 (remove)"
  assert_no_eacces "MCP-03 (remove)" "$output"

  # No residue in ANY present agent's config (symmetric multi-agent teardown).
  run sudo -u agent -H bash --login -c "jq -e '.mcpServers | has(\"github-mcp\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "github-mcp gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"
  run sudo -u agent -H bash --login -c "grep -q 'agentlinux-mcp:github-mcp' ${CODEX_TOML}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "github-mcp block gone from ${CODEX_TOML} after remove" "block remains" "$LOG"
  _assert_gone_if_present gemini "jq -e '.mcpServers | has(\"github-mcp\")' /home/agent/.gemini/settings.json"
  _assert_gone_if_present qwen "jq -e '.mcpServers | has(\"github-mcp\")' /home/agent/.qwen/settings.json"
  _assert_gone_if_present opencode "jq -e '.mcp | has(\"github-mcp\")' /home/agent/.config/opencode/opencode.json"

  # Idempotent re-remove.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force github-mcp'
  assert_exit_zero "MCP-03 (idempotent re-remove)"
}

@test "MCP-03: github-mcp is remote-http and NEVER the Docker recipe (no docker/ghcr invocation in the recipe)" {
  # The success criterion forbids the Docker recipe. Assert the install recipe
  # invokes no docker/ghcr container (strip comments so the word in prose cannot
  # mask a real invocation regression).
  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/github-mcp/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE 'docker|ghcr\\.io'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "recipe uses NO docker/ghcr (remote-http only)" "${output}" "$LOG"

  # And it IS remote-http with the thin-installer shape: source_kind mcp, an https
  # endpoint_url, requires_secret true (needs in-client auth), and NO secret_env
  # (ADR-017 dropped it — AgentLinux carries no credential).
  run bash -c "jq -r '.agents[] | select(.id==\"github-mcp\") | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "MCP-03 (entry shape)"
  if [[ "${output}" != "mcp true null https://api.githubcopilot.com/mcp/" ]]; then
    __fail "MCP-03" "mcp + requires_secret true + NO secret_env + https endpoint" "${output:-<empty>}" "$LOG"
  fi
}
