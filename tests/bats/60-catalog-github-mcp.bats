#!/usr/bin/env bats
# tests/bats/60-catalog-github-mcp.bats — v0.3.6 Phase 36 (github-mcp) MCP-03:
# the FIRST remote-http MCP entry AND the first CROSS-AGENT MCP registration.
#
# github-mcp registers GitHub's hosted remote MCP server into EVERY installed
# MCP-capable agent (claude-code, codex, gemini-cli, opencode, qwen-code) via the
# shared helper plugin/catalog/lib/mcp-register.sh. The mandatory GitHub PAT is
# NEVER baked: each agent config stores an env-var REFERENCE (`Bearer
# ${GITHUB_MCP_PAT}`) that the agent expands at launch; codex keeps it off disk
# via bearer_token_env_var. `remove` deregisters from all agents symmetrically.
#
# This gate installs claude-code + codex as preconditions (the two the maintainer
# named) and asserts fan-out into BOTH, plus never-bake + no-Docker shape +
# residue-free symmetric removal. gemini/opencode/qwen are asserted only if
# present (the npm cluster may or may not have left them installed).
#
# Design invariants (behavior-test-contract):
#   - every @test name prefixed with the requirement ID
#   - failures emit __fail four-line TST-04 diagnostics
#   - version pins / endpoint read from the provisioned catalog via jq (never hardcoded)
#   - installs run as the agent user through a login shell
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
CLAUDE_JSON=/home/agent/.claude.json
CODEX_TOML=/home/agent/.codex/config.toml
REF='Bearer ${GITHUB_MCP_PAT}'

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

# _assert_ref_if_present <agent-bin> <jq-cmd> — when <agent-bin> is on the agent
# user's PATH, assert <jq-cmd> (its config carries github-mcp with the reference)
# exits 0. Absent agents are skipped cleanly (fan-out only touches present agents).
_assert_ref_if_present() {
  local bin=$1 cmd=$2
  sudo -u agent -H bash --login -c "command -v ${bin}" >/dev/null 2>&1 || return 0
  run sudo -u agent -H bash --login -c "$cmd"
  assert_exit_zero "MCP-03 (${bin} carries the env-var reference)"
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

@test "MCP-03: github-mcp registers the GitHub remote MCP into every installed agent (never-baked PAT, no-Docker), then deregisters with no residue" {
  # Guard: both named-agent preconditions actually held. Fail loud on a missing
  # precondition rather than let a skipped fan-out target look like a register bug.
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-03 (claude present precondition)"
  run sudo -u agent -H bash --login -c 'command -v codex'
  assert_exit_zero "MCP-03 (codex present precondition)"

  # Endpoint + pin are jq-derived from the provisioned catalog (never hardcoded).
  local url pinned
  url=$(jq -r '.agents[] | select(.id=="github-mcp") | .endpoint_url' "$CATALOG")
  pinned=$(jq -r '.agents[] | select(.id=="github-mcp") | .pinned_version' "$CATALOG")
  if [[ -z "$url" || "$url" == "null" || "$url" != https://* ]]; then
    __fail "MCP-03" "https endpoint_url in catalog" "url=[${url}]" "$LOG"
  fi
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "MCP-03" "non-empty pinned_version" "pinned=[${pinned}]" "$LOG"
  fi

  # Register (fan out).
  run sudo -u agent -H bash --login -c 'agentlinux install github-mcp'
  assert_exit_zero "MCP-03 (install)"
  assert_no_eacces "MCP-03 (install)" "$output"

  # Mandatory-secret instruction surfaced (anchor on wording, not the server name).
  if ! printf '%s' "${output}" | grep -qiE 'personal access token is required|export GITHUB_MCP_PAT'; then
    __fail "MCP-03" "install surfaces the mandatory PAT instruction" "${output:-<empty>}" "$LOG"
  fi

  # claude-code: registered as an http server pointing at the pinned endpoint,
  # carrying the env-var REFERENCE (never a literal token).
  run sudo -u agent -H bash --login -c \
    "jq -e --arg u \"${url}\" '.mcpServers[\"github-mcp\"] | .type==\"http\" and .url==\$u' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-03 (claude http registration at pinned url)"
  run sudo -u agent -H bash --login -c \
    "jq -e --arg r '${REF}' '.mcpServers[\"github-mcp\"].headers.Authorization == \$r' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-03 (claude carries env-var reference, not a literal token)"

  # codex: registered with the pinned url + bearer_token_env_var (token OFF disk),
  # both scoped to github-mcp's own marker block so a stray line elsewhere in
  # config.toml can't satisfy the assertion.
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:github-mcp >>>/,/agentlinux-mcp:github-mcp <<</p' ${CODEX_TOML} | grep -q 'bearer_token_env_var = \"GITHUB_MCP_PAT\"'"
  assert_exit_zero "MCP-03 (codex bearer_token_env_var, token off disk)"
  run sudo -u agent -H bash --login -c \
    "sed -n '/agentlinux-mcp:github-mcp >>>/,/agentlinux-mcp:github-mcp <<</p' ${CODEX_TOML} | grep -qF 'url = \"${url}\"'"
  assert_exit_zero "MCP-03 (codex registered at pinned url)"

  # Cross-agent fan-out: the gemini-family + opencode agents get the SAME env-var
  # reference when present. They may or may not be installed on this container
  # (the npm cluster may have left them), so assert conditionally — if the agent
  # is on PATH, its config MUST carry github-mcp with the reference (never a token).
  _assert_ref_if_present gemini "jq -e --arg r '${REF}' '.mcpServers[\"github-mcp\"].headers.Authorization==\$r' /home/agent/.gemini/settings.json"
  _assert_ref_if_present qwen "jq -e --arg r '${REF}' '.mcpServers[\"github-mcp\"].headers.Authorization==\$r' /home/agent/.qwen/settings.json"
  _assert_ref_if_present opencode "jq -e --arg r '${REF}' '.mcp[\"github-mcp\"] | .type==\"remote\" and .headers.Authorization==\$r' /home/agent/.config/opencode/opencode.json"

  # NEVER-BAKED: no literal GitHub token in ANY agent config.
  run sudo -u agent -H bash --login -c \
    "grep -rIqE 'ghp_[A-Za-z0-9]|github_pat_[A-Za-z0-9]' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "no literal GitHub token in any agent config (never-baked)" "token pattern found" "$LOG"

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

  # No leaked PAT anywhere AFTER remove either (removal must not expose a token).
  run sudo -u agent -H bash --login -c \
    "grep -rIqE 'ghp_[A-Za-z0-9]|github_pat_[A-Za-z0-9]' /home/agent/.claude.json /home/agent/.codex /home/agent/.gemini /home/agent/.qwen /home/agent/.config/opencode 2>/dev/null"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "no literal GitHub token in any config after remove" "token pattern found" "$LOG"

  # Idempotent re-remove.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force github-mcp'
  assert_exit_zero "MCP-03 (idempotent re-remove)"
}

@test "MCP-03: github-mcp is remote-http and NEVER the Docker recipe (no docker/ghcr invocation in the recipe)" {
  # The success criterion forbids the Docker recipe. Assert the install recipe
  # invokes no docker/ghcr container (strip comments so the word in prose — e.g.
  # the catalog description — cannot mask a real invocation regression).
  local recipe=/opt/agentlinux/catalog/${PKG_VERSION}/agents/github-mcp/install.sh
  run bash -c "grep -vE '^[[:space:]]*#' '${recipe}' | grep -nE 'docker|ghcr\\.io'"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-03" "recipe uses NO docker/ghcr (remote-http only)" "${output}" "$LOG"

  # And it IS remote-http: the entry declares an https endpoint_url + mandatory secret.
  run bash -c "jq -r '.agents[] | select(.id==\"github-mcp\") | \"\\(.source_kind) \\(.requires_secret) \\(.secret_env) \\(.endpoint_url)\"' ${CATALOG}"
  assert_exit_zero "MCP-03 (entry shape)"
  if [[ "${output}" != "mcp true GITHUB_MCP_PAT https://api.githubcopilot.com/mcp/" ]]; then
    __fail "MCP-03" "mcp + requires_secret true + secret_env GITHUB_MCP_PAT + https endpoint" "${output:-<empty>}" "$LOG"
  fi
}
