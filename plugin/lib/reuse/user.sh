#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse/user.sh — REUSE-01 user-compatibility decision.
#
# Five predicates, ALL required for REUSE. Returns {reuse, create, remediate,
# bail}:
#   1. detect::user_present                              (else → create)
#   2. detect::user_shell ∈ {/bin/bash, /usr/bin/bash}   (else → bail)
#   3. detect::user_home_writable                        (else → bail)
#   4. --user=NAME (when supplied) == DETECT_USER_NAME   (else → bail)
#   5. detect::user_can_sudo_apt                         (else → remediate)
#
# Ordering: cheap irreconcilable structural failures FIRST, then the only
# fixable check (sudo-apt) last — so a wrong-shell user bails immediately
# instead of triggering a sudoers install on a user we can't use anyway.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags; uses `return 1` on error.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse/user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# reuse::user_decision <requested_user>
# Returns {reuse, create, remediate, bail} per the five-predicate check.
# <requested_user> (typically $INSTALL_USER) is compared against
# DETECT_USER_NAME to detect a --user=NAME mismatch.
reuse::user_decision() {
  local requested_user=${1:-}

  # Clear any stale DETECT_USER_BAIL_REASON before evaluating — the export is
  # set ONLY on bail paths below, so main()'s alt-user gate can trust it.
  # NOTE: cmd-sub callers ($(reuse::user_decision)) run in a subshell and won't
  # see the export — main()'s alt-user gate routes around that via a tmp-file
  # capture; collect_all_decisions uses cmd-sub but doesn't consume the reason.
  unset DETECT_USER_BAIL_REASON

  # Predicate 1: presence. Absent → no user to reuse.
  if ! detect::user_present; then
    printf 'create'
    return 0
  fi

  # Predicate 2: shell. Exact-path match against {/bin/bash, /usr/bin/bash}
  # after readlink -f resolves the symlink chain; falls back to the raw value
  # on a broken symlink. Wrong-shell is irreconcilable (no chsh handler).
  local shell shell_real
  shell=$(detect::user_shell)
  shell_real=$(readlink -f "$shell" 2>/dev/null || printf '%s' "$shell")
  case "$shell_real" in
    /bin/bash | /usr/bin/bash) ;;
    *)
      # Record the bail reason so main()'s alt-user gate renders the right hint.
      export DETECT_USER_BAIL_REASON=wrong-shell
      printf 'bail'
      return 0
      ;;
  esac

  # Predicate 3: writable home — irreconcilable (PATH wiring writes ~/.bashrc,
  # the npm bootstrap writes ~/.npmrc; no chmod-home handler).
  if ! detect::user_home_writable; then
    export DETECT_USER_BAIL_REASON=home-unwritable
    printf 'bail'
    return 0
  fi

  # Predicate 4 (before sudo-apt because it's structural): --user=NAME mismatch
  # is its own incompatibility class — bail so the operator passes the right name.
  if [[ -n "$requested_user" && "$requested_user" != "${DETECT_USER_NAME:-}" ]]; then
    export DETECT_USER_BAIL_REASON=name-mismatch
    printf 'bail'
    return 0
  fi

  # Predicate 5 (last — the only fixable failure): NOPASSWD-for-apt.
  # REMEDIATE-03 installs the canonical sudoers drop-in on this branch.
  if ! detect::user_can_sudo_apt; then
    printf 'remediate'
    return 0
  fi

  # All five predicates hold: REUSE the existing user.
  printf 'reuse'
  return 0
}

# reuse::log_user_reuse <user>
# Emits the [REUSE-01] marker; called from 10-agent-user.sh after the
# case-branch dispatches to `reuse`.
reuse::log_user_reuse() {
  local user=${1:-${DETECT_USER_NAME:-agent}}
  log_info "[REUSE-01] agent user reused: uid=${DETECT_USER_UID:-} shell=${DETECT_USER_SHELL:-} home=${DETECT_USER_HOME:-} home_writable=${DETECT_USER_HOME_WRITABLE:-false} sudo_apt=${DETECT_USER_CAN_SUDO_APT:-false} (requested=${user})"
}
