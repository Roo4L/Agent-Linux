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

  local pwent uid gid shell home groups present home_writable can_sudo_apt
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
    # NEW Phase 13 (REUSE-01 sudo bar — CONTEXT.md Area 1 Q1 amendment
    # 2026-05-16): can the user run `apt-get` non-interactively via sudo?
    #
    # T-13-02 mitigation: use ABSOLUTE path /usr/bin/apt-get (NOT bare
    # `apt-get`). A user with NOPASSWD for `/usr/bin/apt-get` who also has
    # write access to an earlier-PATH dir (e.g. ~/.local/bin) could otherwise
    # shadow apt-get with a malicious binary the probe would happily run; the
    # absolute-path form forces sudo to resolve the argument literally, so the
    # NOPASSWD grant is anchored to the real apt-get binary.
    #
    # NOT routed through `as_user` (which adds -H -E -- and would carry caller
    # env). The probe needs the raw `sudo -u <user> -n` shape so passwordless
    # failure surfaces as exit 1 (not a hanging password prompt).
    #
    # `--help` is read-side (no package mutation, no network); satisfies the
    # DET-* read-only invariant (Q4 contract — never any package-manager
    # mutation). Exit 0 iff user has NOPASSWD for at least apt-get.
    if sudo -u "$user" -n /usr/bin/apt-get --help >/dev/null 2>&1; then
      can_sudo_apt=true
    else
      can_sudo_apt=false
    fi
  else
    present=false
    uid=""
    gid=""
    shell=""
    home=""
    groups=""
    home_writable=false
    can_sudo_apt=false
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
  export DETECT_USER_CAN_SUDO_APT="$can_sudo_apt"

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
    --argjson can_sudo_apt "$can_sudo_apt" \
    '{user: {name: $name, present: $present, uid: $uid, gid: $gid, shell: $shell, home: $home, groups: ($groups | split(" ")), home_writable: $home_writable, can_sudo_apt: $can_sudo_apt}}' \
    >"$fragment_path"
}

# --- Phase 13 reader functions (CONTEXT.md "Phase 12 → Phase 13 contract") ---
# Thin accessors over exported DETECT_USER_* vars; Phase 13 provisioners source
# detect.sh and call these to make REUSE decisions without parsing JSON.

detect::user_present() { [[ "${DETECT_USER_PRESENT:-false}" == "true" ]]; }
detect::user_uid() { printf '%s' "${DETECT_USER_UID:-}"; }
detect::user_shell() { printf '%s' "${DETECT_USER_SHELL:-}"; }
detect::user_home_writable() { [[ "${DETECT_USER_HOME_WRITABLE:-false}" == "true" ]]; }

# detect::user_can_sudo_apt — exit 0 if DETECT_USER_CAN_SUDO_APT == true.
#
# NOPASSWD-for-apt is the REUSE-01 sudo bar (per CONTEXT.md Area 1 / Q1 user
# amendment 2026-05-16). T-13-02 mitigation: the probe in detect::user_probe
# uses the absolute path /usr/bin/apt-get to defeat a PATH-shim attack against
# bare apt-get. This reader is a thin accessor over the export — Phase 13
# REUSE-01 consults it to gate the reuse decision.
detect::user_can_sudo_apt() { [[ "${DETECT_USER_CAN_SUDO_APT:-false}" == "true" ]]; }
