#!/usr/bin/env bats
# tests/bats/55-catalog-autoupdate.bats — AGT-02-style self-update / autoupdate
# coexistence for the v0.3.6 npm cluster, mirroring the Claude Code self-update
# gate (51-agt02-release-gate.bats). No credentials needed — this is a
# binary/updater-level check, not a model call.
#
# The canonical AgentLinux concern (the recursive-shim + EACCES bug that
# motivated the project): when a tool self-updates, it must do so AS THE AGENT
# USER without permission fights and without minting a /usr/local shim that
# breaks the next invocation. For each cluster tool that ships a self-updater
# (codex `update`, opencode `upgrade`) we assert:
#   - the update command itself exits 0 (it actually ran — a hung/timed-out or
#     refusing updater is NOT a pass);
#   - it runs with NO EACCES / permission-denied;
#   - the binary stays agent-owned under $HOME (never a /usr/local shim);
#   - the reported version is monotonic non-decreasing (pin not silently broken
#     / downgraded), same shape as the claude `update` gate.
# Tools with NO in-tool updater (gemini-cli, qwen-code, ccusage) are asserted to
# expose none — their version is governed solely by the catalog pin and
# `agentlinux upgrade`, so there is no in-tool path to bypass the pin.
#
# codex re-exercises ENABLE-05: with the catalog pin already at latest,
# `codex update` must leave the pinned, npm-managed install authoritative.
# opencode also ships a self-updater but is deliberately NOT ENABLE-05-frozen —
# its updater is allowed to run, so the assertion is "updates cleanly +
# monotonic", not "pin frozen".

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c 'rm -rf ~/.codex ~/.gemini ~/.qwen ~/.config/opencode ~/.local/share/opencode 2>/dev/null' >/dev/null 2>&1 || true
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    local id
    for id in codex opencode gemini-cli qwen-code ccusage; do
      sudo -u agent -H bash --login -c "agentlinux remove --force ${id}" >/dev/null 2>&1 || true
    done
  fi
  sudo -u agent -H bash --login -c 'rm -rf ~/.codex ~/.gemini ~/.qwen ~/.config/opencode ~/.local/share/opencode 2>/dev/null' >/dev/null 2>&1 || true
}

_install() { sudo -u agent -H bash --login -c "agentlinux install ${1}"; }
_remove() { sudo -u agent -H bash --login -c "agentlinux remove --force ${1}" >/dev/null 2>&1 || true; }
# extract the first semver from a --version line
_semver() { grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$1" | head -1; }

# _assert_agent_owned <req> <bin> — the binary resolves under the agent's $HOME
# (agent-owned), never a /usr/local shim. $output must hold `command -v <bin>`.
# Note: `command -v` reports only the ACTIVE PATH resolution — that is exactly
# the AGT-02 concern (a self-updater that re-points the live binary to a
# /usr/local shim). A dormant shim later in PATH is out of scope by design.
_assert_agent_owned() {
  local req=$1 bin=$2
  case "${output}" in
    /home/agent/*) : ;;
    *) __fail "$req" "${bin} resolves under /home/agent (agent-owned, no /usr/local shim)" "${output:-<empty>}" "$LOG" ;;
  esac
}

# _assert_monotonic <req> <before> <after> — both must be semver-shaped and
# after >= before. An empty `before` means `--version` broke post-install (a
# regression in its own right), so we fail rather than silently skip.
_assert_monotonic() {
  local req=$1 before=$2 after=$3
  [[ -n "$before" ]] || __fail "$req" "a semver-shaped version BEFORE self-update" "<empty> (post-install --version broke?)" "$LOG"
  [[ -n "$after" ]] || __fail "$req" "a semver-shaped version AFTER self-update" "<empty>" "$LOG"
  if [[ "$(printf '%s\n%s\n' "$before" "$after" | sort -V | tail -1)" != "$after" ]]; then
    __fail "$req" "version monotonic non-decreasing across self-update" "before=${before} after=${after}" "$LOG"
  fi
}

# _assert_no_updater <req> <tool> — assert <tool> --help lists no update/upgrade
# SUBCOMMAND. Word-boundary anchored so it does not false-fail on "updated",
# "up to date", or an update-available nag in prose; scoped to the pinned
# version (a future pin's help copy is re-validated when the pin bumps).
_assert_no_updater() {
  local req=$1 tool=$2
  run sudo -u agent -H bash --login -c "${tool} --help </dev/null 2>&1"
  assert_exit_zero "${req} (--help)"
  if printf '%s' "${output}" | grep -qiE '(^|[[:space:]])(update|upgrade)([[:space:]]|$)'; then
    __fail "$req" "${tool} exposes no in-tool self-updater subcommand" "${output:-<empty>}" "$LOG"
  fi
}

@test "AGT-02-style/ENABLE-05: codex update runs as agent — exits 0, no EACCES, no /usr/local shim, pin stays authoritative" {
  local pinned before after
  pinned=$(jq -r '.agents[] | select(.id=="codex") | .pinned_version' "$CATALOG")
  _install codex

  run sudo -u agent -H bash --login -c 'codex --version </dev/null'
  before=$(_semver "${output}")

  # The self-updater. codex is npm-managed (CODEX_MANAGED_PACKAGE_ROOT); with
  # the pin already at latest it routes through npm and stays at the pin. It
  # must exit 0, not EACCES, not mint a /usr/local shim, not downgrade.
  run sudo -u agent -H bash --login -c 'cd /tmp && timeout 150 codex update </dev/null 2>&1'
  assert_exit_zero "AGT-02-style/codex (update)"
  assert_no_eacces "AGT-02-style/codex (update)" "$output"

  run sudo -u agent -H bash --login -c 'command -v codex'
  _assert_agent_owned "AGT-02-style/codex" codex

  run sudo -u agent -H bash --login -c 'codex --version </dev/null'
  after=$(_semver "${output}")
  _assert_monotonic "AGT-02-style/codex" "$before" "$after"
  # Pin authority: with pin == latest, the version must still satisfy the pin.
  if [[ "$(printf '%s\n%s\n' "$pinned" "$after" | sort -V | tail -1)" != "$after" ]]; then
    __fail "ENABLE-05/codex" "post-update version >= pinned ${pinned}" "after=${after}" "$LOG"
  fi
  _remove codex
}

@test "AGT-02-style: opencode upgrade runs as agent — exits 0, no EACCES, stays agent-owned, version monotonic" {
  local before after
  _install opencode

  run sudo -u agent -H bash --login -c 'opencode --version </dev/null'
  before=$(_semver "${output}")

  # opencode ships a real self-updater (`opencode upgrade`) that is allowed to
  # run (not ENABLE-05-frozen). It must run as the unprivileged agent user with
  # no permission fight and keep the binary agent-owned.
  run sudo -u agent -H bash --login -c 'cd /tmp && timeout 180 opencode upgrade </dev/null 2>&1'
  assert_exit_zero "AGT-02-style/opencode (upgrade)"
  assert_no_eacces "AGT-02-style/opencode (upgrade)" "$output"

  run sudo -u agent -H bash --login -c 'command -v opencode'
  _assert_agent_owned "AGT-02-style/opencode" opencode

  run sudo -u agent -H bash --login -c 'opencode --version </dev/null'
  after=$(_semver "${output}")
  _assert_monotonic "AGT-02-style/opencode" "$before" "$after"
  _remove opencode
}

@test "AGT-02-style: gemini-cli exposes no in-tool self-updater (pin governed by agentlinux upgrade)" {
  _install gemini-cli
  _assert_no_updater "AGT-02-style/gemini-cli" gemini
  _remove gemini-cli
}

@test "AGT-02-style: qwen-code exposes no in-tool self-updater (pin governed by agentlinux upgrade)" {
  _install qwen-code
  _assert_no_updater "AGT-02-style/qwen-code" qwen
  _remove qwen-code
}

@test "AGT-02-style: ccusage exposes no in-tool self-updater (read-only; pin governed by agentlinux upgrade)" {
  _install ccusage
  _assert_no_updater "AGT-02-style/ccusage" ccusage
  _remove ccusage
}
