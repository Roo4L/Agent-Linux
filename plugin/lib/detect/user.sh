#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/user.sh — DET-01 install user discovery probe.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, the tee redirect, and the log.sh /
# as_user.sh dependencies from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — this is a sourced
# fragment (pattern from plugin/provisioner/30-nodejs.sh:71).
#
# Allowed primitives (Q4 read-only contract): getent, id, stat, test -w (via
# as_user — root sees every dir as writable). Per the read-only contract:
# never any package-manager mutation, never any write to /etc /home
# /usr/local/bin /opt.
#
# Probes whether <user> exists; if so, captures UID, GID, login shell, home
# directory, group memberships (id -nG), and home writability AS THE USER.
# Populates DETECT_USER_* exports (Phase 13 readers consume these) and writes
# one JSON object fragment to the path passed by the orchestrator.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect::user_probe <user> <fragment_path>
#
# Populates DETECT_USER_* exports and writes a `{user: {...}}` JSON object to
# <fragment_path>. The orchestrator merges this with the other detector
# fragments via `jq -s 'add'`.
detect::user_probe() {
  local user=${1:-agent} fragment_path=$2

  local pwent uid gid shell home groups present home_writable
  if pwent=$(getent passwd "$user" 2>/dev/null); then
    present=true
    # passwd format: name:x:uid:gid:gecos:home:shell
    IFS=: read -r _ _ uid gid _ home shell <<<"$pwent"
    groups=$(id -nG "$user" 2>/dev/null || echo "")
    # `as_user agent test -w "$home"` is the ONLY portable answer to "can the
    # user write here?" — root sees every dir as writable, so probing as root
    # would always report true. Pitfall 4 territory.
    if as_user "$user" test -w "$home"; then
      home_writable=true
    else
      home_writable=false
    fi
  else
    present=false
    uid=""
    gid=""
    shell=""
    home=""
    groups=""
    home_writable=false
  fi

  # Export for in-process readers (Phase 13 reader functions consume these).
  export DETECT_USER_NAME="$user"
  export DETECT_USER_PRESENT="$present"
  export DETECT_USER_UID="$uid"
  export DETECT_USER_GID="$gid"
  export DETECT_USER_SHELL="$shell"
  export DETECT_USER_HOME="$home"
  export DETECT_USER_GROUPS="$groups"
  export DETECT_USER_HOME_WRITABLE="$home_writable"

  # Emit JSON fragment for orchestrator slurping. `--arg` quotes strings; jq
  # handles escape edge cases (newlines, quotes, unicode) correctly. Splitting
  # groups on " " inside jq because id -nG is whitespace-separated.
  jq -n \
    --arg name "$user" \
    --argjson present "$present" \
    --arg uid "${uid:-}" \
    --arg gid "${gid:-}" \
    --arg shell "${shell:-}" \
    --arg home "${home:-}" \
    --arg groups "${groups:-}" \
    --argjson home_writable "$home_writable" \
    '{user: {name: $name, present: $present, uid: $uid, gid: $gid, shell: $shell, home: $home, groups: ($groups | split(" ")), home_writable: $home_writable}}' \
    >"$fragment_path"
}

# --- Phase 13 reader functions (CONTEXT.md "Phase 12 → Phase 13 contract") ---
# Thin accessors over exported DETECT_USER_* vars; Phase 13 provisioners source
# detect.sh and call these to make REUSE decisions without parsing JSON.

detect::user_present() { [[ "${DETECT_USER_PRESENT:-false}" == "true" ]]; }
detect::user_uid() { printf '%s' "${DETECT_USER_UID:-}"; }
detect::user_shell() { printf '%s' "${DETECT_USER_SHELL:-}"; }
detect::user_home_writable() { [[ "${DETECT_USER_HOME_WRITABLE:-false}" == "true" ]]; }
