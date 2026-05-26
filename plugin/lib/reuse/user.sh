#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/reuse/user.sh — REUSE-01 user-compatibility decision.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/reuse.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Implements CONTEXT.md Area 1 / Q1 (user-amended 2026-05-16): five predicates,
# ALL must hold for REUSE. Returns one of {reuse, create, remediate, bail} on
# stdout — provisioner case-branch is the dispatcher.
#
# Predicates (per 13-CONTEXT.md Area 1 / REUSE-01):
#   1. detect::user_present                                       (else → create)
#   2. detect::user_shell ∈ {/bin/bash, /usr/bin/bash}            (else → bail)
#   3. detect::user_home_writable                                 (else → bail)
#   4. --user=NAME (when supplied) == DETECT_USER_NAME            (else → bail)
#   5. detect::user_can_sudo_apt                                  (else → remediate)
#
# Predicate ordering: cheap structural failures FIRST (present, shell, home,
# name-mismatch — all irreconcilable defects that bail), THEN the fixable
# sudo-apt check (which falls into the Phase 14 remediate branch). This means
# a user with the wrong shell never reaches the remediate branch — wrong-shell
# is irreconcilable per CONTEXT.md, so we bail immediately rather than letting
# Phase 14 attempt a sudoers install on a user we cannot use anyway.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REUSE_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REUSE_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'reuse/user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# reuse::user_decision <requested_user>
#
# Returns one of {reuse, create, remediate, bail} on stdout per the five-
# predicate check. <requested_user> is the value passed by the caller
# (typically $INSTALL_USER from agentlinux-install); the function compares it
# against DETECT_USER_NAME (populated by detect::user_probe in the prior
# detect::run_once call) to detect a --user=NAME mismatch.
reuse::user_decision() {
  local requested_user=${1:-}

  # Plan 15-02 (T-15-02-01): clear any stale DETECT_USER_BAIL_REASON from a
  # previous invocation BEFORE evaluating predicates. The export is set ONLY
  # on bail-returning paths below so main()'s alt-user gate can trust it as
  # a non-stale signal. Defense in depth: main() also gates on the return
  # token ('bail') BEFORE reading the reason.
  #
  # CRITICAL: callers that invoke this function via `$(reuse::user_decision)`
  # cmd-sub will NOT see the DETECT_USER_BAIL_REASON export because cmd-sub
  # runs in a subshell. The Plan 15-02 alt-user gate in main() therefore
  # routes around cmd-sub via a tmp-file capture (see agentlinux-install
  # main()). The remediate.sh collect_all_decisions caller uses cmd-sub but
  # does NOT consume DETECT_USER_BAIL_REASON (it bail-registers without the
  # reason), so the subshell loss is harmless on that path. Unsetting here
  # in BOTH parent and subshell contexts protects against stale-reason
  # leakage across multiple invocations in the parent shell.
  unset DETECT_USER_BAIL_REASON

  # Predicate 1: presence. Absent → no user to reuse, fall through to Create.
  if ! detect::user_present; then
    printf 'create'
    return 0
  fi

  # Predicate 2: shell. CONTEXT.md Area 1 Q1 demands exact-path match against
  # {/bin/bash, /usr/bin/bash} after symlink resolution. readlink -f resolves
  # the full chain — a /bin/bash symlink to /usr/bin/bash (or vice versa)
  # collapses to one of the accepted paths. Fall back to the raw shell value
  # when readlink fails (broken symlink); the exact-string check still rejects
  # /bin/sh / /usr/sbin/nologin / /bin/dash / etc. Wrong-shell is
  # irreconcilable per CONTEXT.md — Phase 13 bails immediately (Phase 14 does
  # not have a chsh handler).
  local shell shell_real
  shell=$(detect::user_shell)
  shell_real=$(readlink -f "$shell" 2>/dev/null || printf '%s' "$shell")
  case "$shell_real" in
    /bin/bash | /usr/bin/bash) ;;
    *)
      # Plan 15-02 (D-15-07 / D-15-08): record the bail reason so main()'s
      # alt-user gate knows WHY and renders the right prompt + hint message.
      export DETECT_USER_BAIL_REASON=wrong-shell
      printf 'bail'
      return 0
      ;;
  esac

  # Predicate 3: writable home. A read-only home directory is irreconcilable
  # — the PATH-wiring provisioner needs to write ~/.bashrc and the npm prefix
  # bootstrap needs to write ~/.npmrc. Phase 14 does not own a chmod-home
  # handler (out of scope per CONTEXT.md Area 1 Q1).
  if ! detect::user_home_writable; then
    # Plan 15-02 (D-15-07): home-unwritable bail reason.
    export DETECT_USER_BAIL_REASON=home-unwritable
    printf 'bail'
    return 0
  fi

  # Predicate 5 (ordered before sudo-apt because it's structural, not fixable):
  # --user=NAME mismatch. When the caller supplied a requested user name and
  # DETECT_USER_NAME does not match, the install user is its own incompatibility
  # class (CONTEXT.md "user mismatch is its own incompatibility class") — bail
  # immediately so the operator passes --user=<correct-name>.
  if [[ -n "$requested_user" && "$requested_user" != "${DETECT_USER_NAME:-}" ]]; then
    # Plan 15-02 (D-15-07): name-mismatch bail reason.
    export DETECT_USER_BAIL_REASON=name-mismatch
    printf 'bail'
    return 0
  fi

  # Predicate 4 (last because it's the only fixable failure mode): NOPASSWD-
  # for-apt. Phase 14 REMEDIATE-03 will install the canonical /etc/sudoers.d/
  # agentlinux drop-in on this branch; Phase 13 surfaces the token so the
  # dispatcher in 10-agent-user.sh can register a placeholder return 1 (the
  # Phase 14 handler replaces that branch without changing the dispatch shape).
  if ! detect::user_can_sudo_apt; then
    printf 'remediate'
    return 0
  fi

  # All five predicates hold: REUSE the existing user.
  printf 'reuse'
  return 0
}

# reuse::log_user_reuse <user>
#
# Emits the canonical [REUSE-01] marker line via log_info (tee'd to
# /var/log/agentlinux-install.log). Called from 10-agent-user.sh AFTER the
# case-branch dispatches to `reuse`. Format mirrors Phase 12's [DET-NN]
# key=value convention (CONTEXT.md Area 1 Q4 — bats greps `[REUSE-01]`
# reliably; humans read the same line).
reuse::log_user_reuse() {
  local user=${1:-${DETECT_USER_NAME:-agent}}
  log_info "[REUSE-01] agent user reused: uid=${DETECT_USER_UID:-} shell=${DETECT_USER_SHELL:-} home=${DETECT_USER_HOME:-} home_writable=${DETECT_USER_HOME_WRITABLE:-false} sudo_apt=${DETECT_USER_CAN_SUDO_APT:-false} (requested=${user})"
}
