#!/usr/bin/env bats
# tests/bats/59-catalog-mcp.bats — v0.3.6 Phase 34 (chrome-devtools-mcp 🔧) the
# MCP-server source_kind gate: MCP-01 (register the Chrome DevTools MCP server
# into Claude Code user scope, Chrome-present requirement surfaced, symmetric
# residue-free deregister) + ENABLE-02 (the MCP recipe pattern — `claude mcp add
# --scope user` register / `claude mcp remove` deregister; keyless here, the
# requires_secret/secret_env convention lands with its first secret consumer).
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

  # Defensive scrub of any prior chrome-devtools-mcp registration BEFORE any test,
  # so a stale ~/.claude.json entry cannot satisfy a present-assertion even if a
  # regressed recipe stopped registering it (parity with 53/57/58).
  sudo -u agent -H bash --login -c \
    'command -v claude >/dev/null 2>&1 && claude mcp remove chrome-devtools-mcp --scope user' \
    >/dev/null 2>&1 || true
}

teardown_file() {
  # Symmetric removal so later @test files see a clean slate.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force chrome-devtools-mcp' >/dev/null 2>&1 || true
  fi
  sudo -u agent -H bash --login -c \
    'command -v claude >/dev/null 2>&1 && claude mcp remove chrome-devtools-mcp --scope user' \
    >/dev/null 2>&1 || true
}

# _pin <req> — echo chrome-devtools-mcp's pin from the provisioned catalog (jq,
# never hardcoded) and guard it non-empty/non-null.
_pin() {
  local req=$1 pinned
  pinned=$(jq -r '.agents[] | select(.id=="chrome-devtools-mcp") | .pinned_version' "$CATALOG")
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "$req" "non-empty pinned_version for chrome-devtools-mcp" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"
  fi
  printf '%s' "$pinned"
}

@test "MCP-01: chrome-devtools-mcp registers into Claude Code user scope (no EACCES), surfaces the Chrome requirement, and deregisters with no residue" {
  local pinned
  pinned=$(_pin "MCP-01") || return 1

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
