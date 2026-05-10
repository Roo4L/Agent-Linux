#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/sudoers.sh — DET-05 sudoers drop-in discovery probe.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, the tee redirect, and the log.sh
# dependency from the entrypoint. MUST NOT set its own strict-mode flags. Uses
# `return 1` (not `exit 1`) on any error path — this is a sourced fragment
# (pattern from plugin/provisioner/30-nodejs.sh:71).
#
# READ-ONLY by contract (T-12-01 mitigation): the probe uses ONLY stat,
# sha256sum, and grep -Fxq. NEVER `visudo` (no-arg visudo opens the editor —
# would be a side effect), NEVER `install`, NEVER `chmod`, NEVER `>` redirect
# to /etc/sudoers.d/agentlinux. The dedicated bats @test in
# tests/bats/15-detection.bats captures sha256 before+after a --report-only
# invocation and asserts byte-equality.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_SUDOERS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_SUDOERS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/sudoers.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# DETECT_SUDOERS_PATH and DETECT_SUDOERS_EXPECTED_LINE are LOCKED constants
# (ADR-012; mirrored from plugin/provisioner/20-sudoers.sh:50 + :59 and
# tests/bats/22-agent-sudo.bats:51). Hardcoded — never $VAR-driven path — so a
# tampered env cannot redirect the probe at a different file.
readonly DETECT_SUDOERS_PATH=/etc/sudoers.d/agentlinux
readonly DETECT_SUDOERS_EXPECTED_LINE='agent ALL=(ALL) NOPASSWD: ALL'

# detect::sudoers_probe <fragment_path>
#
# Populates DETECT_SUDOERS_* exports and writes a `{sudoers: {...}}` JSON
# object to <fragment_path>. The orchestrator merges this with the other
# detector fragments via `jq -s 'add'`.
detect::sudoers_probe() {
  local fragment_path=$1
  local present mode owner sha256 nopasswd_present

  if [[ -f "$DETECT_SUDOERS_PATH" ]]; then
    present=true
    mode=$(stat -c '%a' "$DETECT_SUDOERS_PATH" 2>/dev/null || echo "")
    owner=$(stat -c '%U:%G' "$DETECT_SUDOERS_PATH" 2>/dev/null || echo "unknown")
    sha256=$(sha256sum "$DETECT_SUDOERS_PATH" | cut -d' ' -f1)
    # `--` terminates options for grep so a hypothetical leading-dash content
    # cannot be reparsed as a flag (defense-in-depth — the expected line begins
    # with `agent`, but `--` is the safe pattern in tests/bats/22-agent-sudo.bats).
    if grep -Fxq -- "$DETECT_SUDOERS_EXPECTED_LINE" "$DETECT_SUDOERS_PATH"; then
      nopasswd_present=true
    else
      nopasswd_present=false
    fi
  else
    present=false
    mode=""
    owner=""
    sha256=""
    nopasswd_present=false
  fi

  # Export for in-process readers + the renderer (render.sh reads
  # DETECT_SUDOERS_{PRESENT,PATH,MODE,OWNER,SHA256,NOPASSWD_OK}).
  export DETECT_SUDOERS_PRESENT="$present"
  export DETECT_SUDOERS_MODE="$mode"
  export DETECT_SUDOERS_OWNER="$owner"
  export DETECT_SUDOERS_SHA256="$sha256"
  export DETECT_SUDOERS_NOPASSWD_OK="$nopasswd_present"

  # `--argjson present` because $present is the literal token true/false (jq
  # boolean), not a quoted string. `--arg sha256 ""` is fine when absent.
  jq -n \
    --arg path "$DETECT_SUDOERS_PATH" \
    --argjson present "$present" \
    --arg mode "$mode" \
    --arg owner "$owner" \
    --arg sha256 "$sha256" \
    --argjson nopasswd_present "$nopasswd_present" \
    '{sudoers: {
      path: $path,
      present: $present,
      mode: $mode,
      owner: $owner,
      sha256: $sha256,
      nopasswd_line_present: $nopasswd_present
    }}' \
    >"$fragment_path"
}
