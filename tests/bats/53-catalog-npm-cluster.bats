#!/usr/bin/env bats
# tests/bats/53-catalog-npm-cluster.bats — v0.3.6 Phases 23-27 npm catalog
# cluster: AGT-07 (codex) + ENABLE-05, AGT-06 (gemini-cli), AGT-05 (opencode),
# AGT-08 (qwen-code), WORK-01 (ccusage).
#
# Each requirement gets one @test that drives the full TST-07 lifecycle:
#   agentlinux install <id> → post-install version-pin verify → no-EACCES
#   → no /usr/local shim (binary resolves under the agent npm prefix)
#   → agentlinux remove --force <id> (symmetric) → binary gone
#   → second remove is idempotent.
# codex additionally gets a dedicated ENABLE-05 @test (self-updater
# coexistence: in-app startup update check disabled + pin authoritative +
# ~/.codex preserved across remove, CAT-04).
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - version pins read from the provisioned catalog via jq — NEVER hardcoded
#   - installs run as the agent user through a login shell (PATH wiring)
#
# Refs:
#   - tests/bats/50-agents.bats (setup_file recovery + jq-pin precedent)
#   - plugin/catalog/agents/{codex,gemini-cli,opencode,qwen-code,ccusage}/
#   - .planning/REQUIREMENTS.md (AGT-05..08, WORK-01, ENABLE-05)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
# AL-29: derive the catalog version from package.json — single SoT.
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

setup_file() {
  # 40-registry-cli.bats's INST-04 --purge @tests run earlier in filename sort
  # and can remove /opt/agentlinux + the agentlinux symlink + the agent user.
  # Recovery mirrors 50-agents.bats: re-run the raw installer when the symlink
  # is absent so `agentlinux install <id>` has a working dispatch surface.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi

  # Defensive scrub of per-tool user state BEFORE any install (parity with
  # 50-agents.bats). Without it, a stale ~/.codex/config.toml from a prior run
  # could satisfy the ENABLE-05 knob + CAT-04 preservation checks even if a
  # regressed recipe stopped writing the knob — exactly the regression those
  # assertions exist to catch.
  sudo -u agent -H bash --login -c '
    rm -rf ~/.codex ~/.gemini ~/.qwen ~/.config/opencode ~/.local/share/opencode 2>/dev/null
  ' >/dev/null 2>&1 || true
}

teardown_file() {
  # Symmetric removal + state scrub so later @test files see a clean slate.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    local id
    for id in codex gemini-cli opencode qwen-code ccusage; do
      sudo -u agent -H bash --login -c "agentlinux remove --force ${id}" >/dev/null 2>&1 || true
    done
  fi
  # Drop the per-tool user state that the recipes preserve on remove (CAT-04),
  # so it does not leak into unrelated downstream test files.
  sudo -u agent -H bash --login -c '
    rm -rf ~/.codex ~/.gemini ~/.qwen ~/.config/opencode ~/.local/share/opencode 2>/dev/null
  ' >/dev/null 2>&1 || true
}

# _npm_agent_lifecycle <req-id> <catalog-id> <binary> — shared install→verify→
# remove driver. Asserts: install exit 0, no EACCES, version matches the
# catalog pin, binary resolves under the agent npm prefix (no /usr/local shim),
# symmetric remove drops it from PATH, and a second remove is idempotent.
_npm_agent_lifecycle() {
  local req=$1 id=$2 bin=$3 pinned
  pinned=$(jq -r ".agents[] | select(.id==\"${id}\") | .pinned_version" "$CATALOG")
  # Guard: an empty/null pin would make `grep -F -- ""` match ANY output,
  # silently defeating the version-lock assertion (missing catalog, bad id).
  [[ -n "$pinned" && "$pinned" != "null" ]] \
    || __fail "$req" "non-empty pinned_version from catalog" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"

  run sudo -u agent -H bash --login -c "agentlinux install ${id}"
  assert_exit_zero "${req} (install)"
  assert_no_eacces "${req} (install)" "$output"

  run sudo -u agent -H bash --login -c "${bin} --version"
  assert_exit_zero "${req} (version)"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "$req" "${bin} --version contains pinned ${pinned}" "${output:-<empty>}" "$LOG"
  fi

  run sudo -u agent -H bash --login -c "command -v ${bin}"
  assert_exit_zero "${req} (resolve)"
  case "${output}" in
    /home/agent/.npm-global/bin/*) : ;;
    *) __fail "$req" "${bin} resolves under /home/agent/.npm-global/bin (no /usr/local shim)" "${output:-<empty>}" "$LOG" ;;
  esac

  run sudo -u agent -H bash --login -c "agentlinux remove --force ${id}"
  assert_exit_zero "${req} (remove)"
  assert_no_eacces "${req} (remove)" "$output"
  run sudo -u agent -H bash --login -c "command -v ${bin}"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "${bin} NOT on PATH after remove" "still resolves: ${output}" "$LOG"

  # Idempotent re-remove (uninstall.sh is npm-uninstall-|| true).
  run sudo -u agent -H bash --login -c "agentlinux remove --force ${id}"
  assert_exit_zero "${req} (idempotent remove)"
}

@test "AGT-07: codex install→version-pin→symmetric remove lifecycle" {
  _npm_agent_lifecycle "AGT-07" codex codex
}

@test "ENABLE-05: codex install disables the in-app startup update check and keeps the npm pin authoritative" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="codex") | .pinned_version' "$CATALOG")
  [[ -n "$pinned" && "$pinned" != "null" ]] \
    || __fail "ENABLE-05" "non-empty pinned_version from catalog" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"

  run sudo -u agent -H bash --login -c 'agentlinux install codex'
  assert_exit_zero "ENABLE-05 (install)"
  assert_no_eacces "ENABLE-05 (install)" "$output"

  # (a) in-app updater disabled: ~/.codex/config.toml sets the knob to false.
  run sudo -u agent -H bash --login -c 'cat ~/.codex/config.toml'
  assert_exit_zero "ENABLE-05 (config.toml exists)"
  if ! printf '%s' "${output}" | grep -Eq '^[[:space:]]*check_for_update_on_startup[[:space:]]*=[[:space:]]*false'; then
    __fail "ENABLE-05" "config.toml sets check_for_update_on_startup = false" "${output:-<empty>}" "$LOG"
  fi

  # (b) pin authoritative: codex is npm-managed under the agent prefix — not a
  # /usr/local shim a self-updater could hijack — and reports the pinned version.
  run sudo -u agent -H bash --login -c 'command -v codex'
  case "${output}" in
    /home/agent/.npm-global/bin/*) : ;;
    *) __fail "ENABLE-05" "codex npm-managed under /home/agent/.npm-global/bin" "${output:-<empty>}" "$LOG" ;;
  esac
  run sudo -u agent -H bash --login -c 'codex --version'
  assert_exit_zero "ENABLE-05 (version)"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "ENABLE-05" "codex --version is pinned ${pinned}" "${output:-<empty>}" "$LOG"
  fi

  # (b2) codex install brings in the system bubblewrap sandbox so codex stops
  # nagging about a missing `bwrap` on launch. The recipe step is non-fatal, but
  # a standard AgentLinux host has agent NOPASSWD sudo + apt (ADR-012), so bwrap
  # installs deterministically here.
  run sudo -u agent -H bash --login -c 'command -v bwrap'
  assert_exit_zero "ENABLE-05 (bubblewrap system sandbox installed)"

  # (c) CAT-04: ~/.codex (config + auth) survives a remove.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force codex'
  assert_exit_zero "ENABLE-05 (remove)"
  run sudo -u agent -H bash --login -c 'test -f ~/.codex/config.toml && echo PRESENT'
  if ! printf '%s' "${output}" | grep -q 'PRESENT'; then
    __fail "ENABLE-05" "codex config.toml preserved after remove (CAT-04)" "${output:-<empty>}" "$LOG"
  fi
}

@test "AGT-06: gemini-cli install→version-pin→symmetric remove lifecycle" {
  _npm_agent_lifecycle "AGT-06" gemini-cli gemini
}

@test "AGT-05: opencode install→version-pin→symmetric remove lifecycle" {
  _npm_agent_lifecycle "AGT-05" opencode opencode
}

@test "AGT-08: qwen-code install→version-pin→symmetric remove lifecycle" {
  _npm_agent_lifecycle "AGT-08" qwen-code qwen
}

@test "WORK-01: ccusage install→version-pin→symmetric remove lifecycle" {
  _npm_agent_lifecycle "WORK-01" ccusage ccusage
}
