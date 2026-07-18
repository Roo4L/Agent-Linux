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
# Agents used: codex (`rtk init --codex` -> ~/.codex/RTK.md) and gemini-cli
# (`rtk init --gemini` -> rtk block in ~/.gemini/GEMINI.md) — two distinct rtk
# wire paths, both reliable npm installs. Pure filesystem assertions, no model
# calls. qwen-code is intentionally NOT exercised: rtk ships no qwen target (N/A).

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
  _remove gemini-cli
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
  _install gemini-cli
  run _install rtk
  assert_exit_zero "WIRE-02 (rtk install)"
  assert_no_eacces "WIRE-02 (rtk install)" "$output"

  _agent_test "WIRE-02/rtk/codex" "rtk wired into codex (~/.codex/RTK.md)" \
    "test -f /home/agent/.codex/RTK.md"
  _agent_test "WIRE-02/rtk/gemini" "rtk block present in ~/.gemini/GEMINI.md" \
    "grep -qi rtk /home/agent/.gemini/GEMINI.md"

  # Symmetric teardown: remove rtk unwires from BOTH agents.
  run sudo -u agent -H bash --login -c "agentlinux remove --force rtk"
  assert_exit_zero "WIRE-02 (rtk remove)"
  _agent_test "WIRE-02/rtk/remove-codex" "rtk unwired from codex after remove" \
    "! test -e /home/agent/.codex/RTK.md"
  _agent_test "WIRE-02/rtk/remove-gemini" "no rtk block in ~/.gemini/GEMINI.md after remove" \
    "! grep -qi rtk /home/agent/.gemini/GEMINI.md 2>/dev/null"
}

@test "WIRE-02: reverse-trigger — installing an agent AFTER rtk wires rtk into the new agent" {
  # Direction (b): rtk FIRST (with no wireable agent present), then codex — the
  # CLI reconcile must re-run rtk's rewire recipe so codex ends up wired too.
  _remove codex
  _remove gemini-cli
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

@test "WIRE-02: removing Gemini and OpenCode before rtk removes both preserved hooks" {
  # The same consumer-before-provider order must converge for every supported
  # RTK integration, not just Codex.
  _install gemini-cli
  _install opencode
  _install rtk
  run sudo -u agent -H bash --login -c "agentlinux remove --force gemini-cli"
  assert_exit_zero "WIRE-02 (remove gemini before rtk)"
  run sudo -u agent -H bash --login -c "agentlinux remove --force opencode"
  assert_exit_zero "WIRE-02 (remove opencode before rtk)"
  _agent_test "WIRE-02/order/gemini" "Gemini config is preserved before provider removal" \
    "grep -qi rtk /home/agent/.gemini/GEMINI.md"
  _agent_test "WIRE-02/order/opencode" "OpenCode RTK plugin is preserved before provider removal" \
    "test -f /home/agent/.config/opencode/plugins/rtk.ts"

  run sudo -u agent -H bash --login -c "agentlinux remove --force rtk"
  assert_exit_zero "WIRE-02 (remove rtk after Gemini and OpenCode)"
  _agent_test "WIRE-02/order/gemini-clean" "rtk removes the stale Gemini hook" \
    "! test -e /home/agent/.gemini/hooks/rtk-hook-gemini.sh"
  _agent_test "WIRE-02/order/opencode-clean" "rtk removes the stale OpenCode plugin" \
    "! test -e /home/agent/.config/opencode/plugins/rtk.ts"

  # A preserved user-owned GEMINI.md may mention rtk without containing the
  # RTK-owned marker. Removing the provider must leave that content intact.
  _install gemini-cli
  _install rtk
  run sudo -u agent -H bash --login -c "agentlinux remove --force gemini-cli"
  assert_exit_zero "WIRE-02 (remove Gemini before rtk, preservation case)"
  run sudo -u agent -H bash --login -c \
    "printf '%s\\n' '# User instructions: rtk is a preference' > /home/agent/.gemini/GEMINI.md"
  assert_exit_zero "WIRE-02 (seed user-owned Gemini instructions)"
  run sudo -u agent -H bash --login -c \
    "printf '%s\\n' '{\"hooks\":{\"BeforeTool\":[{\"matcher\":\"run_shell_command\",\"hooks\":[{\"type\":\"command\",\"command\":\"/home/agent/user-hook.sh\"},{\"type\":\"command\",\"command\":\"/home/agent/.gemini/hooks/rtk-hook-gemini.sh\"}]}]}}' > /home/agent/.gemini/settings.json"
  assert_exit_zero "WIRE-02 (seed mixed Gemini hooks)"
  run sudo -u agent -H bash --login -c "agentlinux remove --force rtk"
  assert_exit_zero "WIRE-02 (preserve user-owned Gemini instructions)"
  _agent_test "WIRE-02/order/gemini-preserve" "user-owned Gemini instructions survive rtk removal" \
    "test -f /home/agent/.gemini/GEMINI.md && grep -qF 'User instructions: rtk is a preference' /home/agent/.gemini/GEMINI.md"
  _agent_test "WIRE-02/order/gemini-hook-preserve" "non-RTK Gemini hook survives rtk removal" \
    "grep -qF '/home/agent/user-hook.sh' /home/agent/.gemini/settings.json && ! grep -qF 'rtk-hook-gemini' /home/agent/.gemini/settings.json"
}
