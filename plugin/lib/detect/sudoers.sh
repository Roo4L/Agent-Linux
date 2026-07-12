#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/sudoers.sh — DET-05 sudoers drop-in discovery probe.
#
# Sourced fragment: inherits set -euo pipefail / ERR trap / log.sh and uses
# `return 1` (not `exit 1`).
#
# Read-only by contract: uses ONLY stat, sha256sum, and grep -Fxq. Never
# `visudo` (no-arg visudo opens the editor), never install/chmod, never a `>`
# redirect to the drop-in.
[[ -n "${AGENTLINUX_DETECT_SUDOERS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_SUDOERS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/sudoers.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# LOCKED path (ADR-012, mirrored from provisioner/20-sudoers.sh). The PROBE PATH
# stays hardcoded so a tampered env can't redirect the probe at a different file.
readonly DETECT_SUDOERS_PATH=/etc/sudoers.d/agentlinux
# The expected NOPASSWD line's username column is parameterized on the resolved
# install user (AL-50) so a correctly-provisioned alt-user host (e.g.
# `claude ALL=(ALL) NOPASSWD: ALL`) reads as REUSE, not drift. INSTALL_USER is
# the installer's own charset-validated variable (not arbitrary external input)
# and is set before detect::run_once sources this fragment; defaults to `agent`.
DETECT_SUDOERS_EXPECTED_LINE="${INSTALL_USER:-agent} ALL=(ALL) NOPASSWD: ALL"
readonly DETECT_SUDOERS_EXPECTED_LINE

# detect::sudoers_probe <fragment_path>
#
# Populates DETECT_SUDOERS_* exports and writes a `{sudoers: {...}}` fragment.
detect::sudoers_probe() {
  local fragment_path=$1
  local present mode owner sha256 nopasswd_present

  if [[ -f "$DETECT_SUDOERS_PATH" ]]; then
    present=true
    mode=$(stat -c '%a' "$DETECT_SUDOERS_PATH" 2>/dev/null || echo "")
    owner=$(stat -c '%U:%G' "$DETECT_SUDOERS_PATH" 2>/dev/null || echo "unknown")
    sha256=$(sha256sum "$DETECT_SUDOERS_PATH" | cut -d' ' -f1)
    # `--` terminates grep options so leading-dash content can't be reparsed as
    # a flag (defense-in-depth).
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

  # Export for in-process readers + the renderer.
  export DETECT_SUDOERS_PRESENT="$present"
  export DETECT_SUDOERS_MODE="$mode"
  export DETECT_SUDOERS_OWNER="$owner"
  export DETECT_SUDOERS_SHA256="$sha256"
  export DETECT_SUDOERS_NOPASSWD_OK="$nopasswd_present"

  # --argjson for the true/false booleans (jq boolean, not a quoted string).
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
