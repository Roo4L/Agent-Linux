#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/render.sh — text renderer helpers for the detection layer.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, and the log.sh dependency from the
# entrypoint. MUST NOT set its own strict-mode flags. Uses `return 1` (not
# `exit 1`) on any error path — this is a sourced fragment.
#
# Renders the detection report on stdout in a grep-stable shape:
#   ## DET-NN — <Title>          (section header)
#   ✓ present                    (one glyph line per section, optional)
#   [DET-NN] key=value           (one field marker per captured probe)
# Glyphs: ✓ (ok, green) / ✗ (bad, red) / • (warn, yellow) / — (absent, dim).
# TTY-aware via [[ -t 1 ]]; honor NO_COLOR env var per https://no-color.org.
#
# Plan 12-01 wires DET-01 + DET-05 sections with full field listings; DET-02 /
# DET-03 / DET-04 sections print one placeholder marker line each so the
# DET-06: "[DET-NN] markers present" @test passes for all five marker IDs from
# day one. Plan 12-02 fills the DET-02/03/04 section bodies.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_RENDER_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_RENDER_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/render.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# __det_color <fd> <name> — emit ANSI escape for <name> only when:
#   (a) <fd> is a TTY ([[ -t $fd ]])
#   (b) NO_COLOR env var is unset/empty (https://no-color.org)
# Modeled on plugin/lib/log.sh:23-35 (__log_color); separated here because the
# detection report goes to stdout (FD 1) while log.sh's color emit targets FD 2.
__det_color() {
  local fd=$1 color=$2
  [[ -t $fd ]] || {
    printf ''
    return
  }
  [[ -n "${NO_COLOR:-}" ]] && {
    printf ''
    return
  }
  case "$color" in
    green) printf '\033[32m' ;;
    red) printf '\033[31m' ;;
    yellow) printf '\033[33m' ;;
    dim) printf '\033[2m' ;;
    reset) printf '\033[0m' ;;
  esac
}

# __det_glyph <kind> — colored ✓ / ✗ / • / — marker.
__det_glyph() {
  case "$1" in
    ok) printf '%s✓%s' "$(__det_color 1 green)" "$(__det_color 1 reset)" ;;
    bad) printf '%s✗%s' "$(__det_color 1 red)" "$(__det_color 1 reset)" ;;
    warn) printf '%s•%s' "$(__det_color 1 yellow)" "$(__det_color 1 reset)" ;;
    absent) printf '%s—%s' "$(__det_color 1 dim)" "$(__det_color 1 reset)" ;;
  esac
}

# Render a single DET-NN field line with the grep-stable [DET-NN] prefix.
# Usage: __det_field DET-01 user.uid "$DETECT_USER_UID"
__det_field() {
  local req=$1 key=$2 val=$3
  printf '[%s] %s=%s\n' "$req" "$key" "$val"
}

# Section header line. One '## DET-NN' marker per section so a human reader
# (and a future bats @test) can locate sections without parsing JSON.
__det_section() {
  local req=$1 title=$2
  printf '\n## %s — %s\n' "$req" "$title"
}

# detect::render_text — emit the full text report on stdout.
#
# Section ordering matches REQUIREMENTS.md / ROADMAP success-criteria order:
# User → Node.js → npm prefix → Catalog agents → Sudoers. Plan 12-01 wires the
# DET-01 + DET-05 fields fully; DET-02/03/04 sections print one
# `[DET-NN] section.status=stub` line each so the marker @test (Task 2) passes
# without surfacing fake data. Plan 12-02 rewrites the placeholder lines into
# full field listings as it fills the per-detector probes.
detect::render_text() {
  __det_section "DET-01" "Install User"
  if [[ "${DETECT_USER_PRESENT:-false}" == "true" ]]; then
    printf '%s present\n' "$(__det_glyph ok)"
    __det_field DET-01 user.name "${DETECT_USER_NAME:-}"
    __det_field DET-01 user.uid "${DETECT_USER_UID:-}"
    __det_field DET-01 user.gid "${DETECT_USER_GID:-}"
    __det_field DET-01 user.shell "${DETECT_USER_SHELL:-}"
    __det_field DET-01 user.home "${DETECT_USER_HOME:-}"
    __det_field DET-01 user.home_writable "${DETECT_USER_HOME_WRITABLE:-false}"
    __det_field DET-01 user.groups "${DETECT_USER_GROUPS:-}"
  else
    printf '%s absent\n' "$(__det_glyph absent)"
    __det_field DET-01 user.name "${DETECT_USER_NAME:-}"
    __det_field DET-01 user.present false
  fi

  __det_section "DET-02" "Node.js Installations"
  __det_field DET-02 nodejs.section_status "${DETECT_NODEJS_SECTION_STATUS:-stub}"

  __det_section "DET-03" "npm Global Prefix"
  __det_field DET-03 npm.section_status "${DETECT_NPM_PREFIX_SECTION_STATUS:-stub}"

  __det_section "DET-04" "Catalog Agents"
  __det_field DET-04 agents.section_status "${DETECT_AGENTS_SECTION_STATUS:-stub}"

  __det_section "DET-05" "Sudoers Drop-In"
  if [[ "${DETECT_SUDOERS_PRESENT:-false}" == "true" ]]; then
    printf '%s present\n' "$(__det_glyph ok)"
    __det_field DET-05 sudoers.path "${DETECT_SUDOERS_PATH:-}"
    __det_field DET-05 sudoers.mode "${DETECT_SUDOERS_MODE:-}"
    __det_field DET-05 sudoers.owner "${DETECT_SUDOERS_OWNER:-}"
    __det_field DET-05 sudoers.sha256 "${DETECT_SUDOERS_SHA256:-}"
    __det_field DET-05 sudoers.nopasswd_line_present "${DETECT_SUDOERS_NOPASSWD_OK:-false}"
  else
    printf '%s absent\n' "$(__det_glyph absent)"
    __det_field DET-05 sudoers.path "${DETECT_SUDOERS_PATH:-}"
    __det_field DET-05 sudoers.present false
  fi
}
