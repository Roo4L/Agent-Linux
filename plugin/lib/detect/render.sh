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
    __det_field DET-01 user.can_sudo_apt "${DETECT_USER_CAN_SUDO_APT:-false}"
    __det_field DET-01 user.groups "${DETECT_USER_GROUPS:-}"
  else
    printf '%s absent\n' "$(__det_glyph absent)"
    __det_field DET-01 user.name "${DETECT_USER_NAME:-}"
    __det_field DET-01 user.present false
    __det_field DET-01 user.can_sudo_apt false
  fi

  __det_section "DET-02" "Node.js Installations"
  if [[ "${DETECT_NODEJS_COUNT:-0}" -gt 0 ]]; then
    printf '%s present (%s source(s))\n' "$(__det_glyph ok)" "${DETECT_NODEJS_COUNT}"
    local i s_var p_var v_var w_var r_var
    for ((i = 0; i < DETECT_NODEJS_COUNT; i++)); do
      s_var="DETECT_NODEJS_${i}_SOURCE"
      p_var="DETECT_NODEJS_${i}_PATH"
      v_var="DETECT_NODEJS_${i}_VERSION"
      w_var="DETECT_NODEJS_${i}_WRITABLE"
      r_var="DETECT_NODEJS_${i}_PREFIX_ROOT"
      __det_field DET-02 "nodejs.${i}.source" "${!s_var:-}"
      __det_field DET-02 "nodejs.${i}.path" "${!p_var:-}"
      __det_field DET-02 "nodejs.${i}.version" "${!v_var:-}"
      __det_field DET-02 "nodejs.${i}.install_user_can_write_prefix" "${!w_var:-false}"
      __det_field DET-02 "nodejs.${i}.prefix_root" "${!r_var:-}"
    done
  else
    printf '%s absent\n' "$(__det_glyph absent)"
    __det_field DET-02 nodejs.count 0
  fi

  __det_section "DET-03" "npm Global Prefix"
  if [[ "${DETECT_NPM_PREFIX_SECTION_STATUS:-stub}" == "present" ]]; then
    printf '%s present\n' "$(__det_glyph ok)"
    __det_field DET-03 npm.user_prefix "${DETECT_NPM_PREFIX_USER_VALUE:-}"
    __det_field DET-03 npm.system_prefix "${DETECT_NPM_PREFIX_SYSTEM_VALUE:-}"
    __det_field DET-03 npm.effective_prefix "${DETECT_NPM_PREFIX_PATH:-}"
    __det_field DET-03 npm.effective_owner "${DETECT_NPM_PREFIX_EFFECTIVE_OWNER:-}"
    __det_field DET-03 npm.effective_mode "${DETECT_NPM_PREFIX_EFFECTIVE_MODE:-}"
    __det_field DET-03 npm.install_user_writable "${DETECT_NPM_PREFIX_USER_WRITABLE:-false}"
    __det_field DET-03 npm.prefix_declarations "${DETECT_NPM_PREFIX_DECLARATIONS:-0}"
  else
    printf '%s absent — npm not installed\n' "$(__det_glyph absent)"
    __det_field DET-03 npm.section_status "${DETECT_NPM_PREFIX_SECTION_STATUS:-stub}"
  fi

  __det_section "DET-04" "Catalog Agents"
  if [[ "${DETECT_AGENTS_SECTION_STATUS:-stub}" == "present" ]]; then
    printf '%s present (%s agent(s))\n' "$(__det_glyph ok)" "${DETECT_AGENTS_COUNT:-0}"
    local id upper s_var p_var v_var o_var status path version glyph
    for id in claude-code gsd playwright-cli; do
      # Sanitize id to suffix used in DETECT_AGENT_* export names. Plan 12-02
      # convention: uppercase + replace '-' with '_' (e.g. claude-code → CLAUDE_CODE).
      upper=${id^^}
      upper=${upper//-/_}
      s_var="DETECT_AGENT_${upper}_STATUS"
      p_var="DETECT_AGENT_${upper}_PATH"
      v_var="DETECT_AGENT_${upper}_VERSION"
      o_var="DETECT_AGENT_${upper}_OWNER"
      status="${!s_var:-absent}"
      path="${!p_var:-}"
      version="${!v_var:-}"
      case "$status" in
        healthy) glyph=$(__det_glyph ok) ;;
        broken) glyph=$(__det_glyph bad) ;;
        absent) glyph=$(__det_glyph absent) ;;
        *) glyph=$(__det_glyph warn) ;;
      esac
      printf '%s %s: %s' "$glyph" "$id" "$status"
      [[ -n "$path" ]] && printf ' at %s' "$path"
      [[ -n "$version" ]] && printf ' (%s)' "$version"
      printf '\n'
      __det_field DET-04 "agent.${id}.status" "$status"
      __det_field DET-04 "agent.${id}.path" "$path"
      __det_field DET-04 "agent.${id}.version" "$version"
      __det_field DET-04 "agent.${id}.owner" "${!o_var:-}"
    done
  else
    printf '%s absent\n' "$(__det_glyph absent)"
    __det_field DET-04 agent.section_status "${DETECT_AGENTS_SECTION_STATUS:-stub}"
  fi

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

# detect::render_json — emit the locked top-level shape on stdout.
#
# Reads the merged-fragment cache at $DETECT_CACHE_PATH (populated by
# detect::run_once). Wraps it under {generated_at, host, components: {...}}.
# Final output goes through `jq -S` for byte-stable key sort order
# (RESEARCH §Open Question 4 — critical for Phase 13 REUSE-02 which may
# re-run detection multiple times and compare outputs).
#
# Per CONTEXT.md Area 2 amendment of DET-06: the top-level object emits ONLY
# generated_at + host + components. No phase-or-format version string, no
# schema URL, no ADR-style consumer contract. Reviewers (security-engineer +
# technical-writer) gate this on PR.
#
# T-12-02 mitigation (Plan 12-03 threat model): JSON construction uses the
# `jq -n --arg / --slurpfile` family exclusively. The function NEVER builds
# JSON via printf-with-quotes, shell-evaluator, or nested-shell interpolation.
# Probed values that flow into this function (generated_at + host strings)
# reach jq through --arg, which quotes the value as a JSON string regardless
# of bytes — newlines, embedded quotes, dollar-signs, command-substitutions,
# unicode escapes are all neutered by jq's string parser. The cache file is
# read via --slurpfile, making jq own the parse — a malformed fragment fails
# the merge instead of corrupting output.
detect::render_json() {
  [[ -r "$DETECT_CACHE_PATH" ]] || {
    log_error "detect::render_json: cache file not found at $DETECT_CACHE_PATH (was detect::run_once called?)"
    return 1
  }

  local generated_at os version
  generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # AGENTLINUX_DISTRO_VERSION is the only distro export emitted by
  # plugin/lib/distro_detect.sh (the value is the VERSION_ID like "22.04").
  # The locked CONTEXT.md Area 1 host shape requires {os, version}, so source
  # /etc/os-release directly here for the ID. Sourcing in a function body
  # scopes ID / VERSION_ID to this invocation — no caller-shell pollution.
  # Falls back to "unknown" when /etc/os-release is missing (CI fixture / dev
  # host that bypassed detect_distro).
  os="unknown"
  version="${AGENTLINUX_DISTRO_VERSION:-unknown}"
  if [[ -r /etc/os-release ]]; then
    local ID="" VERSION_ID=""
    # shellcheck disable=SC1091
    . /etc/os-release
    os="${ID:-unknown}"
    [[ "$version" == "unknown" ]] && version="${VERSION_ID:-unknown}"
  fi

  # Use --arg for strings + --slurpfile for the cache (slurpfile reads the
  # file as a single-element array; [0] unwraps to the merged object). Final
  # `jq -n -S` (capital S) sorts keys recursively for byte-stable output
  # across runs on an unchanged host (RESEARCH §Open Question 4).
  jq -n -S \
    --arg generated_at "$generated_at" \
    --arg os "$os" \
    --arg version "$version" \
    --slurpfile components "$DETECT_CACHE_PATH" \
    '{
      generated_at: $generated_at,
      host: {os: $os, version: $version},
      components: $components[0]
    }'
}
