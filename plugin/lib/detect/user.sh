#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/user.sh — DET-01 install user discovery probe.
#
# Sourced fragment: inherits set -euo pipefail / ERR trap / log.sh / as_user.sh
# and uses `return 1` (not `exit 1`).
#
# Read-only: uses only getent, id, stat, and test -w (via as_user). No package
# mutation, no writes.
#
# Probes whether <user> exists; if so, captures UID, GID, login shell, home,
# group memberships, and home writability as the user. Populates DETECT_USER_*
# exports and writes one JSON fragment.
[[ -n "${AGENTLINUX_DETECT_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect::user_probe <user> <fragment_path>
#
# Populates DETECT_USER_* exports and writes a `{user: {...}}` fragment.
detect::user_probe() {
  local user=${1:-agent} fragment_path=$2

  local pwent uid gid shell home groups present home_writable can_sudo_apt
  if pwent=$(getent passwd "$user" 2>/dev/null); then
    present=true
    # passwd format: name:x:uid:gid:gecos:home:shell
    IFS=: read -r _ _ uid gid _ home shell <<<"$pwent"
    groups=$(id -nG "$user" 2>/dev/null || echo "")
    # Probe writability as the user — root sees every dir as writable, so
    # probing as root would always report true.
    if as_user "$user" test -w "$home"; then
      home_writable=true
    else
      home_writable=false
    fi
    # Can the user run apt-get non-interactively via sudo? Use the ABSOLUTE
    # path /usr/bin/apt-get (not bare `apt-get`): a user with NOPASSWD for the
    # absolute path plus write access to an earlier-PATH dir could otherwise
    # shadow apt-get with a malicious binary; the absolute form anchors the
    # grant to the real binary. Run as raw `sudo -u <user> -n` (not via
    # as_user, which carries caller env) so a passwordless failure surfaces as
    # exit 1 rather than a hanging prompt. `--help` is read-only.
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

  # Export for in-process readers.
  export DETECT_USER_NAME="$user"
  export DETECT_USER_PRESENT="$present"
  export DETECT_USER_UID="$uid"
  export DETECT_USER_GID="$gid"
  export DETECT_USER_SHELL="$shell"
  export DETECT_USER_HOME="$home"
  export DETECT_USER_GROUPS="$groups"
  export DETECT_USER_HOME_WRITABLE="$home_writable"
  export DETECT_USER_CAN_SUDO_APT="$can_sudo_apt"

  # Emit JSON fragment. --arg quotes strings (jq handles newlines/quotes/unicode);
  # groups split on " " inside jq because id -nG is whitespace-separated.
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

# Thin accessors over the exported DETECT_USER_* vars (REUSE decisions without
# parsing JSON).
detect::user_present() { [[ "${DETECT_USER_PRESENT:-false}" == "true" ]]; }
detect::user_shell() { printf '%s' "${DETECT_USER_SHELL:-}"; }
detect::user_home_writable() { [[ "${DETECT_USER_HOME_WRITABLE:-false}" == "true" ]]; }

# detect::user_can_sudo_apt — exit 0 if DETECT_USER_CAN_SUDO_APT == true (the
# user has NOPASSWD sudo for apt-get).
detect::user_can_sudo_apt() { [[ "${DETECT_USER_CAN_SUDO_APT:-false}" == "true" ]]; }
