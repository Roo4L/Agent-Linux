#!/usr/bin/env bash
# plugin/lib/as_user.sh — keystone: route every agent-owned command through
# `sudo -u <user> -H -E --`. Violating this function is the "sudo npm install -g"
# anti-pattern AgentLinux exists to eliminate (see CLAUDE.md "Critical Rules"
# and 02-RESEARCH.md "Pitfall 1" / "Pattern 5").
#
# The `as_user` keystone has three load-bearing sudo flags:
#   -H  force HOME=target-user-home (load-bearing for ~/.npmrc lookups, Phase 3).
#   -E  preserve env; secure_path in sudoers still shadows PATH — see Pitfall 1.
#   --  end sudo option parsing so user-controlled args can never be reparsed
#       as sudo flags (e.g. a filename starting with `-`).
#
# Source-once guard: safe to `. as_user.sh` repeatedly.
[[ -n "${AGENTLINUX_AS_USER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_AS_USER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'as_user.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# as_user <user> <cmd...> — run <cmd...> as <user> with:
#   - HOME set to target user's home directory (-H),
#   - env preserved (-E, subject to secure_path in sudoers),
#   - sudo option parsing terminated (--), so "$@" is passed verbatim.
# Returns the command's exit status; returns 64 (EX_USAGE) on misuse.
as_user() {
  local user=$1
  shift
  if [[ $# -eq 0 ]]; then
    log_error "as_user: no command given (usage: as_user <user> <cmd...>)"
    return 64
  fi
  sudo -u "$user" -H -E -- "$@"
}

# as_user_login <user> <cmd...> — login-shell semantics via sudo -i; sources
# /etc/profile + target user's ~/.profile before executing <cmd...>. Use this
# when the callee depends on PATH exports set up by the six-mode PATH matrix
# in plugin/provisioner/40-path-wiring.sh.
as_user_login() {
  local user=$1
  shift
  if [[ $# -eq 0 ]]; then
    log_error "as_user_login: no command given (usage: as_user_login <user> <cmd...>)"
    return 64
  fi
  sudo -u "$user" -H -i -- "$@"
}
