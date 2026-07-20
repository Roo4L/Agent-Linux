#!/usr/bin/env bats
# tests/bats/70-catalog-cross-wire.bats — WIRE-02 cross-agent PROXY wiring.
#
# Unlike WIRE-01 (skill/command FILES dropped into each agent's dir, which are
# order-independent because they are written unconditionally at provider-install
# time), a proxy like rtk edits each agent's OWN LIVE config via `rtk init`, which
# needs that agent present. So order-independence needs TWO mechanisms:
#   (a) installing the provider fans its wiring out to every agent present THEN;
#   (b) installing an agent LATER re-wires every installed provider into it —
#       driven by the CLI post-install reconcile (plugin/cli/src/rewire.ts) +
#       the provider's rewire_recipe_path (rtk -> agents/rtk/rewire.sh).
# Both directions must converge to the same wired set; `remove` unwires all.
#
# Agents used: codex (`rtk init --codex` -> ~/.codex/RTK.md) and opencode
# (`rtk init --opencode` -> ~/.config/opencode/plugins/rtk.ts) — two distinct
# rtk wire paths. Pure filesystem assertions, no model calls. Antigravity and
# qwen-code are intentionally not wired: rtk ships no target for either.

load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
}

_install() { sudo -u agent -H bash --login -c "agentlinux install ${1}"; }
_remove() { sudo -u agent -H bash --login -c "agentlinux remove --force ${1}" >/dev/null 2>&1 || true; }

# Belt-and-braces: leave no rtk wiring or installs behind for later test files.
teardown() {
  _remove rtk
  _remove codex
  _remove antigravity-cli
  _remove opencode
}

_agent_test() {
  local req=$1 what=$2 cmd=$3
  run sudo -u agent -H bash --login -c "$cmd"
  if [[ ${status} -ne 0 ]]; then
    __fail "$req" "$what" "exit ${status}: ${output:-<empty>}" "$LOG"
  fi
}

@test "WIRE-02: installing rtk fans its hook into every present coding agent; remove unwires all" {
  # Direction (a): agents FIRST, then the provider.
  _install codex
  _install opencode
  run _install rtk
  assert_exit_zero "WIRE-02 (rtk install)"
  assert_no_eacces "WIRE-02 (rtk install)" "$output"

  _agent_test "WIRE-02/rtk/codex" "rtk wired into codex (~/.codex/RTK.md)" \
    "test -f /home/agent/.codex/RTK.md"
  _agent_test "WIRE-02/rtk/opencode" "rtk plugin present under ~/.config/opencode/plugins" \
    "test -f /home/agent/.config/opencode/plugins/rtk.ts"

  # Symmetric teardown: remove rtk unwires from BOTH agents.
  run sudo -u agent -H bash --login -c "agentlinux remove --force rtk"
  assert_exit_zero "WIRE-02 (rtk remove)"
  _agent_test "WIRE-02/rtk/remove-codex" "rtk unwired from codex after remove" \
    "! test -e /home/agent/.codex/RTK.md"
  _agent_test "WIRE-02/rtk/remove-opencode" "no rtk plugin after remove" \
    "! test -e /home/agent/.config/opencode/plugins/rtk.ts"
}

@test "WIRE-02: reverse-trigger — installing an agent AFTER rtk wires rtk into the new agent" {
  # Direction (b): rtk FIRST (with no wireable agent present), then codex — the
  # CLI reconcile must re-run rtk's rewire recipe so codex ends up wired too.
  _remove codex
  _remove antigravity-cli
  run _install rtk
  assert_exit_zero "WIRE-02 (rtk install, no agents present)"

  # Nothing to wire yet: codex isn't installed, so it must NOT be wired.
  run sudo -u agent -H bash --login -c "test -e /home/agent/.codex/RTK.md"
  [[ ${status} -ne 0 ]] \
    || __fail "WIRE-02" "codex NOT wired before it is installed" "/home/agent/.codex/RTK.md present too early" "$LOG"

  # Install codex LATER → post-install reconcile fans rtk into it.
  run _install codex
  assert_exit_zero "WIRE-02 (codex install triggers reconcile)"
  _agent_test "WIRE-02/reverse/codex" "reverse-trigger wired rtk into codex" \
    "test -f /home/agent/.codex/RTK.md"

  _remove rtk
  _remove codex
}

@test "WIRE-02: removing an agent before rtk still removes the preserved RTK hook" {
  # Consumer FIRST, provider SECOND: removing the consumer preserves its
  # config, so the provider's later uninstall must clean the RTK-owned files
  # without relying on the consumer binary still being present.
  _install codex
  _install rtk
  run sudo -u agent -H bash --login -c "agentlinux remove --force codex"
  assert_exit_zero "WIRE-02 (remove codex before rtk)"
  _agent_test "WIRE-02/order/codex" "codex config is preserved before provider removal" \
    "test -f /home/agent/.codex/RTK.md"

  run sudo -u agent -H bash --login -c "agentlinux remove --force rtk"
  assert_exit_zero "WIRE-02 (remove rtk after codex)"
  _agent_test "WIRE-02/order/rtk" "rtk removes the stale codex hook" \
    "! test -e /home/agent/.codex/RTK.md"
}

@test "WIRE-02: removing OpenCode before rtk removes the preserved hook" {
  # The same consumer-before-provider order must converge for every supported
  # RTK integration, not just Codex. Antigravity is intentionally N/A: rtk
  # exposes no Antigravity target.
  _install opencode
  _install rtk
  run sudo -u agent -H bash --login -c "agentlinux remove --force opencode"
  assert_exit_zero "WIRE-02 (remove opencode before rtk)"
  _agent_test "WIRE-02/order/opencode" "OpenCode RTK plugin is preserved before provider removal" \
    "test -f /home/agent/.config/opencode/plugins/rtk.ts"

  run sudo -u agent -H bash --login -c "agentlinux remove --force rtk"
  assert_exit_zero "WIRE-02 (remove rtk after OpenCode)"
  _agent_test "WIRE-02/order/opencode-clean" "rtk removes the stale OpenCode plugin" \
    "! test -e /home/agent/.config/opencode/plugins/rtk.ts"
}

@test "WIRE-02: rtk removal preserves Antigravity's shared user state" {
  _remove antigravity-cli
  run sudo -u agent -H bash --login -c \
    'mkdir -p ~/.gemini && printf "%s\\n" user-state > ~/.gemini/agentlinux-rtk-preserve-sentinel'
  assert_exit_zero "WIRE-02/antigravity-state (seed)"

  _install rtk
  _remove rtk
  _agent_test "WIRE-02/antigravity-state" "rtk removal leaves shared ~/.gemini state intact" \
    "test \"\$(cat ~/.gemini/agentlinux-rtk-preserve-sentinel)\" = user-state"
  run sudo -u agent -H bash --login -c 'rm -f ~/.gemini/agentlinux-rtk-preserve-sentinel'
  assert_exit_zero "WIRE-02/antigravity-state (cleanup)"
}
