#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/sudoers.sh — REMEDIATE-03 sudoers handlers.
#
# install_or_overwrite is the single helper BOTH the additive missing-file
# install AND the state-overwriting drift overwrite call, so the two arms cannot
# drift in semantics — both share the same visudo -cf gate (pre + post). The
# additive arm runs without --yes; the overwrite arm is gated by the bail
# (which exits 65 before this handler runs when --yes is absent).
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags; uses `return 1` on error.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_SUDOERS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_SUDOERS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/sudoers.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::sudoers::install_or_overwrite [action_label]
# Called by both the CREATE arm and the REMEDIATE arm; action_label
# ("install"/"overwrite") is purely diagnostic in the [REMEDIATE-03] marker —
# behavior is identical. Composes the canonical ADR-012 content, writes a
# tmpfile, gates it through visudo -cf (pre-install), installs atomically at
# 0440 root:root, then re-verifies with visudo -cf (post-install TOCTOU belt).
# A RETURN-scoped trap cleans the tmpfile on every exit path.
#
# Test hatch: AGENTLINUX_TEST_MODE=1 + AGENTLINUX_TEST_SUDOERS_OVERRIDE=<body>
# swaps in override content so a test can force visudo -cf to fail. Both env
# vars are unset in production (dead branch).
remediate::sudoers::install_or_overwrite() {
  local action=${1:-install}
  local sudoers_file=/etc/sudoers.d/agentlinux
  local content
  # Heredoc tag single-quoted so the content is byte-stable (no shell expansion).
  read -r -d '' content <<'SUDOERS' || true
# Installed by AgentLinux — grants passwordless sudo to agent user.
# Scope: ALL commands. See docs/decisions/012-agent-user-full-sudo.md.
agent ALL=(ALL) NOPASSWD: ALL
SUDOERS
  # Test-only override hatch (production: both unset, dead branch).
  if [[ "${AGENTLINUX_TEST_MODE:-}" == "1" && -n "${AGENTLINUX_TEST_SUDOERS_OVERRIDE:-}" ]]; then
    content=$AGENTLINUX_TEST_SUDOERS_OVERRIDE
  fi

  local tmpfile
  tmpfile=$(mktemp)
  # shellcheck disable=SC2064
  # Expand $tmpfile at trap-install time (function-local var); resolving later
  # would re-read a stale binding if the variable were reassigned.
  trap "rm -f -- '$tmpfile'" RETURN

  printf '%s\n' "$content" >"$tmpfile"

  # Pre-install gate: visudo -cf catches syntax errors before /etc/sudoers.d/
  # is touched.
  if ! visudo -cf "$tmpfile" >/dev/null; then
    log_error "[REMEDIATE-03:visudo-fail] tmpfile syntax check failed; refusing to install $sudoers_file"
    return 1
  fi

  # Atomic install: install(1) sets mode + ownership at rename time — no window
  # where the file exists with wrong permissions.
  if ! install -m "0440" -o root -g root "$tmpfile" "$sudoers_file"; then
    log_error "[REMEDIATE-03:install-fail] install -m 0440 failed for $sudoers_file"
    return 1
  fi

  # Post-install verify — catches any TOCTOU corruption between rename and exit.
  if ! visudo -cf "$sudoers_file" >/dev/null; then
    log_error "[REMEDIATE-03:visudo-fail] post-install verify failed for $sudoers_file"
    return 1
  fi

  log_info "[REMEDIATE-03] component=sudoers action=$action path=$sudoers_file (mode 0440 root:root — ADR-012)"
  return 0
}

# remediate::sudoers::install_stub (LEGACY symbol kept for source compat)
remediate::sudoers::install_stub() {
  remediate::sudoers::install_or_overwrite "install"
}

# remediate::sudoers::overwrite_stub (LEGACY symbol kept for source compat)
remediate::sudoers::overwrite_stub() {
  remediate::sudoers::install_or_overwrite "overwrite"
}
