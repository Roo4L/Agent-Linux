#!/usr/bin/env bats
# tests/bats/56-catalog-skill-wiring.bats — WIRE-01 cross-agent skill wiring.
#
# A skill PROVIDER in the catalog (GSD, playwright-cli) must light up EVERY
# shipped coding agent the concept applies to — not just Claude Code — and tear
# the wiring down symmetrically on remove. This is the behavior contract behind
# the user-visible intent "installing GSD/Playwright lights them up in my whole
# agent fleet". Pure filesystem + install/remove assertions: no credentials, no
# model calls (those live in 54-catalog-npm-smoke.bats).
#
# The wiring is applied UNCONDITIONALLY at the provider's install time (the
# provider writes each target agent's own config dir whether or not that agent
# is installed yet), so it is install-order-independent — an agent installed
# later already finds the skills present. These tests therefore install ONLY the
# provider and assert the target dirs are populated, exactly mirroring the
# order-independent contract.

load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
}

_install() { sudo -u agent -H bash --login -c "agentlinux install ${1}"; }
_remove() { sudo -u agent -H bash --login -c "agentlinux remove --force ${1}" >/dev/null 2>&1 || true; }
# _reinstall — force the recipe to actually RUN (agentlinux install is a no-op
# when the tool is already installed, which would make the present-assertions
# validate STALE wiring from a prior install rather than this test's). Remove
# first so install re-executes install.sh and re-wires from scratch.
_reinstall() {
  _remove "$1"
  sudo -u agent -H bash --login -c "agentlinux install ${1}"
}

# Belt-and-braces cleanup: if any assertion fails mid-test, the provider stays
# installed + wired across five agent dirs and would pollute later test files on
# the same container. teardown runs after every @test regardless of outcome.
teardown() {
  _remove gsd
  _remove playwright-cli
  # Drop every agent any @test in this file can install (the order-independence
  # @tests install target agents LATER) so a mid-test failure can't leak an
  # install into the next test file. Keep this list == the union of installs here.
  _remove antigravity-cli
  _remove codex
  _remove opencode
  _remove qwen-code
}

# _agent_test <req> <what> <shell-test> — run <shell-test> as the agent user in
# a login shell (PATH + npm prefix loaded); fail with a 4-line diagnostic if it
# exits non-zero. The shell-test is the source of truth (a find/test pipeline),
# so each assertion reads as the literal filesystem condition WIRE-01 promises.
_agent_test() {
  local req=$1 what=$2 cmd=$3
  run sudo -u agent -H bash --login -c "$cmd"
  if [[ ${status} -ne 0 ]]; then
    __fail "$req" "$what" "exit ${status}: ${output:-<empty>}" "$LOG"
  fi
}

@test "WIRE-01: install gsd wires Open GSD into every supported upstream runtime" {
  _reinstall gsd

  # Each shipped agent gets GSD in its own native surface. The layouts are
  # observed from the pinned Open GSD release; these assertions re-validate
  # them whenever the catalog pin changes.
  _agent_test "WIRE-01/gsd/claude" "gsd-* skills under /home/agent/.claude/skills" \
    "find /home/agent/.claude/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  _agent_test "WIRE-01/gsd/opencode" "gsd-* skills under /home/agent/.config/opencode/skills" \
    "find /home/agent/.config/opencode/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  _agent_test "WIRE-01/gsd/codex" "gsd-* skills under /home/agent/.agents/skills" \
    "find /home/agent/.agents/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  _agent_test "WIRE-01/gsd/qwen" "gsd-* skills under /home/agent/.qwen/skills" \
    "find /home/agent/.qwen/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."

  # Symmetric teardown: every wired surface is removed across the wired agents.
  _remove gsd
  _agent_test "WIRE-01/gsd/remove-claude" "no gsd-* under /home/agent/.claude/skills after remove" \
    "! find /home/agent/.claude/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  _agent_test "WIRE-01/gsd/remove-opencode" "no gsd-* under /home/agent/.config/opencode/skills after remove" \
    "! find /home/agent/.config/opencode/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  _agent_test "WIRE-01/gsd/remove-codex" "no gsd-* under /home/agent/.agents/skills after remove" \
    "! find /home/agent/.agents/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  _agent_test "WIRE-01/gsd/remove-qwen" "no gsd-* under /home/agent/.qwen/skills after remove" \
    "! find /home/agent/.qwen/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
}

@test "WIRE-01: installing Open GSD wires Codex without reintroducing invalid hooks" {
  # Regression for the dogfood bug (2026-07-16): the old GSD package emitted an
  # array-of-tables `[[hooks]]` block that Codex rejected. Open GSD owns the
  # Codex adapter now, so Codex wiring is mandatory while this parse-safety
  # assertion guards against a future upstream regression.
  _reinstall codex
  _install gsd

  _agent_test "WIRE-01/gsd/codex-skills" "Open GSD skills under ~/.agents/skills" \
    "find /home/agent/.agents/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  _agent_test "WIRE-01/gsd/codex-safe-config" "no invalid [[hooks]] in ~/.codex/config.toml after gsd install" \
    "! grep -qE '^\\[\\[hooks\\]\\]' /home/agent/.codex/config.toml 2>/dev/null"

  # And codex actually launches (config loads) — the user-visible symptom.
  run sudo -u agent -H bash --login -c 'codex --version'
  assert_exit_zero "WIRE-01/gsd/codex-launches"
  if printf '%s' "${output}" | grep -qiE 'HooksToml|expected struct|invalid type'; then
    __fail "WIRE-01" "codex --version launches cleanly after gsd install" "${output:-<empty>}" "$LOG"
  fi

  _remove gsd
  _remove codex
}

@test "WIRE-01: removing Open GSD preserves shared Antigravity user state" {
  run sudo -u agent -H bash --login -c \
    'mkdir -p ~/.gemini && printf "%s\\n" user-state > ~/.gemini/gsd-preserve-sentinel'
  assert_exit_zero "WIRE-01/gsd-antigravity-state (seed)"

  _reinstall gsd
  _remove gsd
  _agent_test "WIRE-01/gsd-antigravity-state" "GSD removal leaves shared ~/.gemini state intact" \
    "test \"\$(cat ~/.gemini/gsd-preserve-sentinel)\" = user-state"
  run sudo -u agent -H bash --login -c 'rm -f ~/.gemini/gsd-preserve-sentinel'
  assert_exit_zero "WIRE-01/gsd-antigravity-state (cleanup)"
}

@test "WIRE-01: install playwright-cli mirrors its skill into /home/agent/.agents/skills (codex/opencode scan path)" {
  _reinstall playwright-cli

  # Claude Code surface (the bootstrapper's native target) ...
  _agent_test "WIRE-01/playwright/claude" "playwright-cli SKILL.md under /home/agent/.claude/skills" \
    "test -f /home/agent/.claude/skills/playwright-cli/SKILL.md"
  # ... plus the cross-tool /home/agent/.agents/skills mirror that BOTH codex and opencode
  # scan (opencode also reads /home/agent/.claude/skills directly — so it is doubly
  # covered). The references/ tree must ride along, not just SKILL.md.
  _agent_test "WIRE-01/playwright/agents" "playwright-cli SKILL.md mirrored under /home/agent/.agents/skills" \
    "test -f /home/agent/.agents/skills/playwright-cli/SKILL.md"
  _agent_test "WIRE-01/playwright/agents-refs" "references/ tree rode along into the mirror" \
    "test -d /home/agent/.agents/skills/playwright-cli/references"

  # Symmetric teardown: BOTH the Claude skill and the .agents/skills mirror go.
  _remove playwright-cli
  _agent_test "WIRE-01/playwright/remove-claude" "claude skill DIR gone after remove" \
    "! test -e /home/agent/.claude/skills/playwright-cli"
  _agent_test "WIRE-01/playwright/remove-agents" ".agents/skills mirror DIR gone after remove" \
    "! test -e /home/agent/.agents/skills/playwright-cli"
}

@test "WIRE-01: order-independence — installing opencode AFTER gsd leaves GSD wiring intact" {
  # WIRE-01 promises the wired set is the same regardless of install order. GSD
  # writes each target agent's dir unconditionally; a target agent installed
  # later must not clobber that wiring.
  _reinstall gsd
  _agent_test "WIRE-01/order/gsd-pre" "gsd OpenCode commands before opencode install" \
    "find /home/agent/.config/opencode/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."

  # Install OpenCode LATER; its install must NOT wipe GSD's command dir.
  run sudo -u agent -H bash --login -c "agentlinux install opencode"
  assert_exit_zero "WIRE-01/order (opencode install)"
  _agent_test "WIRE-01/order/gsd-post" "gsd wiring SURVIVES a later opencode install" \
    "find /home/agent/.config/opencode/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."
  # The Claude surface is likewise untouched.
  _agent_test "WIRE-01/order/gsd-claude" "gsd Claude skills intact after OpenCode install" \
    "find /home/agent/.claude/skills -maxdepth 1 -type d -name 'gsd-*' | grep -q ."

  _remove opencode
  _remove gsd
}

@test "WIRE-01: order-independence — installing codex AFTER playwright-cli leaves the .agents/skills mirror intact" {
  # playwright-cli mirrors its skill into the cross-tool ~/.agents/skills scan
  # path (codex + opencode read it). Installing codex LATER must not disturb that
  # mirror or the Claude skill — the provider-first direction of the WIRE-01
  # order-independence contract.
  _reinstall playwright-cli
  _agent_test "WIRE-01/order/pw-pre" "playwright mirror present before codex install" \
    "test -f /home/agent/.agents/skills/playwright-cli/SKILL.md"

  run sudo -u agent -H bash --login -c "agentlinux install codex"
  assert_exit_zero "WIRE-01/order (codex install)"
  _agent_test "WIRE-01/order/pw-post" "playwright mirror SURVIVES a later codex install" \
    "test -f /home/agent/.agents/skills/playwright-cli/SKILL.md"
  _agent_test "WIRE-01/order/pw-claude" "playwright claude skill intact after codex install" \
    "test -f /home/agent/.claude/skills/playwright-cli/SKILL.md"

  _remove codex
  _remove playwright-cli
}
