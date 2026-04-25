#!/usr/bin/env bash
# plugin/lib/log.sh — structured logging primitives.
#
# AgentLinux installer primitives: every user-visible message from the
# entrypoint or a provisioner routes through log_info / log_warn / log_error /
# log_debug. Output format is deterministic and ANSI-color is stripped when the
# target FD is not a tty — keeping the transcript tee'd into
# /var/log/agentlinux-install.log plain-ASCII so INST-05 can grep
# `EACCES|permission denied` without stripping escape codes.
#
# smoke: Engineer-Alpha @ 2026-04-25T16:31:21Z
# smoke: arm-A @ 2026-04-25T16:53:35Z
# Source-once guard: safe to `. log.sh` repeatedly across library files.
[[ -n "${AGENTLINUX_LOG_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_LOG_SH_SOURCED=1

# AGENTLINUX_LOG_LEVEL ∈ {DEBUG, INFO, WARN, ERROR}; default INFO.
: "${AGENTLINUX_LOG_LEVEL:=INFO}"

__log_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# __log_color <fd> <name> — emit ANSI escape for <name> only when <fd> is a tty.
# Supported names: red, yellow, dim, reset.
__log_color() {
  local fd=$1 color=$2
  [[ -t $fd ]] || {
    printf ''
    return
  }
  case "$color" in
    red) printf '\033[31m' ;;
    yellow) printf '\033[33m' ;;
    dim) printf '\033[2m' ;;
    reset) printf '\033[0m' ;;
  esac
}

# log_info <msg...> — INFO to stdout. Captured by entrypoint's tee into the log file.
log_info() { printf '[%s] [INFO]  %s\n' "$(__log_ts)" "$*"; }

# log_warn <msg...> — WARN to stderr, yellow on tty.
log_warn() {
  printf '%s[%s] [WARN]  %s%s\n' "$(__log_color 2 yellow)" "$(__log_ts)" "$*" "$(__log_color 2 reset)" >&2
}

# log_error <msg...> — ERROR to stderr, red on tty.
log_error() {
  printf '%s[%s] [ERROR] %s%s\n' "$(__log_color 2 red)" "$(__log_ts)" "$*" "$(__log_color 2 reset)" >&2
}

# log_debug <msg...> — gated on AGENTLINUX_LOG_LEVEL=DEBUG; dim on tty.
log_debug() {
  [[ ${AGENTLINUX_LOG_LEVEL} == DEBUG ]] || return 0
  printf '%s[%s] [DEBUG] %s%s\n' "$(__log_color 2 dim)" "$(__log_ts)" "$*" "$(__log_color 2 reset)" >&2
}
