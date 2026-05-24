#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/sudoers.sh — REMEDIATE-03 sudoers handlers.
#
# Phase 14 Plan 14-02 lands the install_or_overwrite helper that BOTH
# additive missing-file install AND state-overwriting drift overwrite call.
# Factored out of the original 20-sudoers.sh CREATE-path body (visudo-cf
# gate → install -m 0440 root:root → post-install visudo-cf gate) so the
# two arms cannot drift in semantics.
#
# Per CONTEXT.md Area 1 Q1:
#   sudoers-missing-install  — additive (no --yes); collect_all_decisions
#                              registers no bail when DETECT_SUDOERS_PRESENT
#                              is false.
#   sudoers-drift-overwrite  — state-overwriting (--yes required); without
#                              --yes the bail gate exits 65 before this
#                              handler ever runs.
#
# T-14-02 mitigation: the drift overwrite uses the SAME visudo -cf gate as
# the create path (pre-install + post-install). install_or_overwrite is the
# single function both paths call, so a future change to the validation
# protocol cannot drift between additive and overwriting arms.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/remediate.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_SUDOERS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_SUDOERS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/sudoers.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::sudoers::install_or_overwrite [action_label]
#
# The single helper called by BOTH 20-sudoers.sh's CREATE arm AND its
# REMEDIATE arm. action_label is "install" (additive missing-file) or
# "overwrite" (drift overwrite); it appears in the [REMEDIATE-03] log marker
# for transcript clarity. Behavior is identical between arms — the
# distinction is purely diagnostic.
#
# Steps:
#   1. Compose the canonical ADR-012 content (single-quoted heredoc — byte-
#      stable across re-runs; BHV-07 sha256-stability contract).
#   2. Write content to a tmpfile in $TMPDIR.
#   3. visudo -cf <tmpfile>  — pre-install syntax gate (T-05.1-01).
#   4. install -m 0440 -o root -g root <tmpfile> /etc/sudoers.d/agentlinux
#      (atomic rename with mode+ownership set at install time; T-05.1-02).
#   5. visudo -cf <sudoers_file>  — post-install verify (TOCTOU belt).
#   6. Emit [REMEDIATE-03] marker.
#   7. RETURN-scoped trap cleans the tmpfile on every exit path.
#
# Test hatch: AGENTLINUX_TEST_MODE=1 + AGENTLINUX_TEST_SUDOERS_OVERRIDE=<body>
# replaces the canonical content with the override body. This lets the bats
# T-14-02 mitigation test (Test 41) force visudo -cf to fail by injecting
# deliberately invalid syntax. Both env vars must be set; production builds
# leave them unset and the branch is dead code.
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
  # Test-only override hatch (Test 41 — T-14-02 visudo-fail mitigation).
  # In production both env vars are unset and this branch is dead.
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

  # T-05.1-01 / T-14-02 pre-install gate: visudo -cf catches syntax errors
  # before /etc/sudoers.d/ is touched. Drift overwrite uses the SAME gate as
  # missing-file install (factored helper — both arms share semantics).
  if ! visudo -cf "$tmpfile" >/dev/null; then
    log_error "[REMEDIATE-03:visudo-fail] tmpfile syntax check failed; refusing to install $sudoers_file"
    return 1
  fi

  # T-05.1-02 atomic install: mode + ownership set at rename time. install(1)
  # is rename-like — no window where the file exists with wrong permissions.
  if ! install -m "0440" -o root -g root "$tmpfile" "$sudoers_file"; then
    log_error "[REMEDIATE-03:install-fail] install -m 0440 failed for $sudoers_file"
    return 1
  fi

  # Post-install verify — hashes the installed file through visudo to catch
  # any TOCTOU corruption between rename and exit (paranoid; visudo -cf on a
  # 3-line file is sub-millisecond).
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
