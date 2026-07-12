#!/usr/bin/env bats
# tests/bats/59-catalog-mcp.bats — v0.3.6 MCP-server catalog gate.
#   Phase 34 (chrome-devtools-mcp 🔧): MCP-01 (register the Chrome DevTools MCP
#     server into Claude Code user scope, Chrome-present requirement surfaced,
#     symmetric residue-free deregister) + ENABLE-02 (the MCP recipe pattern —
#     `claude mcp add --scope user` register / `claude mcp remove` deregister;
#     keyless here).
#   Phase 35 (context7): MCP-02 — register the Context7 MCP server (npx), assert
#     the registration is KEYLESS (no baked CONTEXT7_API_KEY) and that install
#     surfaces the optional post-install key instruction, then deregister with no
#     residue. context7 is the first consumer of the requires_secret/secret_env
#     convention (declared optional: requires_secret=false, secret_env set).
#
# The full TST-07 lifecycle on a provisioned host:
#   agentlinux install claude-code  (precondition — an MCP server registers INTO
#     Claude Code, so the host tool must exist first)
#   agentlinux install chrome-devtools-mcp
#     → ~/.claude.json .mcpServers["chrome-devtools-mcp"] carries the pinned npx
#       spec (jq, pin from the catalog — never hardcoded)
#     → install surfaces the Chrome-present requirement (MCP-01)
#   agentlinux remove --force chrome-devtools-mcp
#     → the key is gone from ~/.claude.json (no residue)
#     → idempotent re-remove
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - version pins read from the provisioned catalog via jq — NEVER hardcoded
#   - installs run as the agent user through a login shell (PATH + claude)
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)
#
# Refs:
#   - tests/bats/58-catalog-devtools.bats (lifecycle + jq-pin driver shape)
#   - plugin/catalog/agents/chrome-devtools-mcp/{install,uninstall}.sh
#   - plugin/cli/test/schema.test.ts (ENABLE-02 source_kind mcp + secret fields)
#   - .planning/REQUIREMENTS.md (MCP-01, ENABLE-02)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
# AL-29: derive the catalog version from package.json — single SoT.
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
CLAUDE_JSON=/home/agent/.claude.json

setup_file() {
  # 40-registry-cli.bats's INST-04 --purge @tests run earlier in filename sort and
  # can remove /opt/agentlinux + the agentlinux symlink + the agent user. Recovery
  # mirrors 53/57/58: re-run the raw installer when the symlink is absent.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi

  # Precondition: an MCP server registers INTO Claude Code, so claude must be on
  # PATH. Install the catalog claude-code entry (native installer, as the agent).
  # Idempotent — a no-op if an earlier file left it installed.
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1 || true

  # Defensive scrub of any prior MCP registrations BEFORE any test, so a stale
  # ~/.claude.json entry cannot satisfy a present-assertion even if a regressed
  # recipe stopped registering it (parity with 53/57/58).
  sudo -u agent -H bash --login -c \
    'command -v claude >/dev/null 2>&1 && { claude mcp remove chrome-devtools-mcp --scope user; claude mcp remove context7 --scope user; }' \
    >/dev/null 2>&1 || true
}

teardown_file() {
  # Symmetric removal so later @test files see a clean slate.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force chrome-devtools-mcp' >/dev/null 2>&1 || true
    sudo -u agent -H bash --login -c 'agentlinux remove --force context7' >/dev/null 2>&1 || true
  fi
  sudo -u agent -H bash --login -c \
    'command -v claude >/dev/null 2>&1 && { claude mcp remove chrome-devtools-mcp --scope user; claude mcp remove context7 --scope user; }' \
    >/dev/null 2>&1 || true
}

# _pin <req> <id> — echo <id>'s pin from the provisioned catalog (jq, never
# hardcoded) and guard it non-empty/non-null.
_pin() {
  local req=$1 id=$2 pinned
  pinned=$(jq -r --arg id "$id" '.agents[] | select(.id==$id) | .pinned_version' "$CATALOG")
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "$req" "non-empty pinned_version for ${id}" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"
    # __fail returns from its OWN frame, so return here too — otherwise the
    # trailing printf resets $? to 0 and the call site's `|| return 1` is dead.
    return 1
  fi
  printf '%s' "$pinned"
}

@test "MCP-01: chrome-devtools-mcp registers into Claude Code user scope (no EACCES), surfaces the Chrome requirement, and deregisters with no residue" {
  local pinned
  pinned=$(_pin "MCP-01" chrome-devtools-mcp) || return 1

  # Guard: the precondition (claude present) actually held. If claude-code install
  # failed in setup, fail loud here rather than let the register no-op look green.
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-01 (claude present precondition)"

  # Register.
  run sudo -u agent -H bash --login -c 'agentlinux install chrome-devtools-mcp'
  assert_exit_zero "MCP-01 (install)"
  assert_no_eacces "MCP-01 (install)" "$output"

  # MCP-01: install surfaces the Chrome-present requirement. Anchor on the notice
  # WORDING, not a bare "chrome" — the server name (chrome-devtools-mcp) is echoed
  # regardless, so a bare-substring grep would pass even if the recipe dropped the
  # requirement notice entirely. This matches the actual "browser tools need a
  # local Chrome/Chromium" line, so a mutation removing it fails loud.
  if ! printf '%s' "${output}" | grep -qiE 'browser tools need|local chrome/chromium'; then
    __fail "MCP-01" "install surfaces the Chrome-present requirement notice" "${output:-<empty>}" "$LOG"
  fi

  # ENABLE-02: the server is registered in ~/.claude.json user-scope mcpServers
  # with the pinned npx spec (jq-derived pin, never hardcoded). This is the
  # observable registration state, deterministic and offline (no server spawn).
  run sudo -u agent -H bash --login -c \
    "jq -e --arg v \"chrome-devtools-mcp@${pinned}\" '.mcpServers[\"chrome-devtools-mcp\"].args // [] | index(\$v)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-01 (registered with pinned spec)"

  # Deregister.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force chrome-devtools-mcp'
  assert_exit_zero "MCP-01 (remove)"
  assert_no_eacces "MCP-01 (remove)" "$output"

  # No residue: the server key is gone from ~/.claude.json.
  run sudo -u agent -H bash --login -c \
    "jq -e '.mcpServers | has(\"chrome-devtools-mcp\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-01" "chrome-devtools-mcp key gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"

  # Idempotent re-remove.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force chrome-devtools-mcp'
  assert_exit_zero "MCP-01 (idempotent re-remove)"
}

@test "ENABLE-02: chrome-devtools-mcp is a keyless mcp entry (source_kind mcp, no requires_secret) — the secret convention lands with its first consumer" {
  # The ENABLE-02 schema contract (source_kind "mcp" + requires_secret/secret_env)
  # is unit-tested in plugin/cli/test/schema.test.ts. Here we assert the catalog
  # entry's shape: chrome-devtools-mcp is source_kind mcp and declares NO secret
  # (it is keyless), so a bare install prints no token instruction. The
  # requires_secret/secret_env path is exercised by the first secret-carrying MCP
  # entry (context7, Phase 35).
  run bash -c "jq -r '.agents[] | select(.id==\"chrome-devtools-mcp\") | .source_kind' ${CATALOG}"
  assert_exit_zero "ENABLE-02 (read source_kind)"
  if [[ "${output}" != "mcp" ]]; then
    __fail "ENABLE-02" "chrome-devtools-mcp entry is source_kind mcp" "source_kind=[${output:-<empty>}]" "$LOG"
  fi

  run bash -c "jq -r '.agents[] | select(.id==\"chrome-devtools-mcp\") | .requires_secret // false' ${CATALOG}"
  assert_exit_zero "ENABLE-02 (read requires_secret)"
  if [[ "${output}" != "false" ]]; then
    __fail "ENABLE-02" "chrome-devtools-mcp is keyless (requires_secret false/absent)" "requires_secret=[${output:-<empty>}]" "$LOG"
  fi
}

@test "MCP-02: context7 registers into Claude Code user scope (no EACCES), KEYLESS with no baked CONTEXT7_API_KEY, surfaces the optional key instruction, and deregisters with no residue" {
  local pinned
  pinned=$(_pin "MCP-02" context7) || return 1

  # Guard: the precondition (claude present) actually held. If claude-code install
  # failed in setup, fail loud here rather than let the register no-op look green.
  run sudo -u agent -H bash --login -c 'command -v claude'
  assert_exit_zero "MCP-02 (claude present precondition)"

  # Register.
  run sudo -u agent -H bash --login -c 'agentlinux install context7'
  assert_exit_zero "MCP-02 (install)"
  assert_no_eacces "MCP-02 (install)" "$output"

  # ENABLE-02 secret contract: install surfaces the OPTIONAL post-install key
  # instruction. Anchor on the instruction WORDING, not a bare "context7" (the
  # server name is echoed regardless) — so a mutation dropping the key notice fails
  # loud. context7 works keyless, so the notice is about raising the rate limit.
  if ! printf '%s' "${output}" | grep -qiE 'higher rate limit|works keyless'; then
    __fail "MCP-02" "install surfaces the optional CONTEXT7_API_KEY instruction" "${output:-<empty>}" "$LOG"
  fi

  # The server is registered in ~/.claude.json user-scope mcpServers with the
  # pinned npx spec (jq-derived pin, never hardcoded). @upstash/context7-mcp is the
  # published package name; the entry id (context7) is the registration key.
  run sudo -u agent -H bash --login -c \
    "jq -e --arg v \"@upstash/context7-mcp@${pinned}\" '.mcpServers[\"context7\"].args // [] | index(\$v)' ${CLAUDE_JSON}"
  assert_exit_zero "MCP-02 (registered with pinned spec)"

  # Secret NEVER baked (ENABLE-02 keystone): the stored registration carries no
  # CONTEXT7_API_KEY — not in the env block, not smuggled into args. A regression
  # that baked the key would leak a credential into ~/.claude.json; fail loud.
  run sudo -u agent -H bash --login -c \
    "jq -e '.mcpServers[\"context7\"] | ((.args // []) | any(test(\"CONTEXT7_API_KEY\"))) or ((.env // {}) | has(\"CONTEXT7_API_KEY\"))' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-02" "context7 registration carries NO baked CONTEXT7_API_KEY" "key found in stored spec" "$LOG"

  # Deregister.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force context7'
  assert_exit_zero "MCP-02 (remove)"
  assert_no_eacces "MCP-02 (remove)" "$output"

  # No residue: the server key is gone from ~/.claude.json.
  run sudo -u agent -H bash --login -c \
    "jq -e '.mcpServers | has(\"context7\")' ${CLAUDE_JSON}"
  [[ "${status}" -ne 0 ]] \
    || __fail "MCP-02" "context7 key gone from ${CLAUDE_JSON} after remove" "still registered" "$LOG"

  # Idempotent re-remove.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force context7'
  assert_exit_zero "MCP-02 (idempotent re-remove)"
}

@test "ENABLE-02: context7 is the first secret-carrying mcp entry — declares secret_env=CONTEXT7_API_KEY with requires_secret=false (optional key)" {
  # context7 is the first entry to exercise the requires_secret/secret_env
  # convention. Its key is OPTIONAL (the server works keyless), so requires_secret
  # is false while secret_env names the env var the post-install instruction and a
  # user-supplied registration would carry. The schema itself is unit-tested in
  # plugin/cli/test/schema.test.ts; here we assert the catalog entry's shape.
  run bash -c "jq -r '.agents[] | select(.id==\"context7\") | .source_kind' ${CATALOG}"
  assert_exit_zero "ENABLE-02 (context7 read source_kind)"
  if [[ "${output}" != "mcp" ]]; then
    __fail "ENABLE-02" "context7 entry is source_kind mcp" "source_kind=[${output:-<empty>}]" "$LOG"
  fi

  run bash -c "jq -r '.agents[] | select(.id==\"context7\") | .secret_env // \"\"' ${CATALOG}"
  assert_exit_zero "ENABLE-02 (context7 read secret_env)"
  if [[ "${output}" != "CONTEXT7_API_KEY" ]]; then
    __fail "ENABLE-02" "context7 declares secret_env=CONTEXT7_API_KEY" "secret_env=[${output:-<empty>}]" "$LOG"
  fi

  run bash -c "jq -r '.agents[] | select(.id==\"context7\") | .requires_secret // false' ${CATALOG}"
  assert_exit_zero "ENABLE-02 (context7 read requires_secret)"
  if [[ "${output}" != "false" ]]; then
    __fail "ENABLE-02" "context7 key is optional (requires_secret false)" "requires_secret=[${output:-<empty>}]" "$LOG"
  fi
}
