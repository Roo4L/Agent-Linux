#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/npm_prefix.sh — DET-03 npm global prefix discovery probe.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, and the log.sh / as_user.sh
# dependencies from the entrypoint. MUST NOT set its own strict-mode flags.
# Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Three-value report (per RESEARCH §Pattern 3):
#   user_prefix      — `npm config get prefix --location=user` (reads ONLY
#                      ~/.npmrc; returns the npm builtin /usr when ~/.npmrc has
#                      no prefix= line — disambiguated by prefix_declarations
#                      counter per Pitfall 6).
#   system_prefix    — `env NPM_CONFIG_PREFIX= npm config get prefix
#                      --no-userconfig` (npm builtin default; clears env so
#                      sudo -E does not carry over an existing override).
#   effective_prefix — `npm config get prefix` (resolves precedence:
#                      env > project .npmrc > user ~/.npmrc > builtin).
#
# CRITICAL: every npm config get goes through `as_user_login` (sudo -i, login
# shell) so the install user's ~/.profile / ~/.bashrc NPM_CONFIG_PREFIX export
# propagates — Pitfall 7 mitigation. Bare `as_user` (sudo -E without -i) does
# NOT source the profile.
#
# READ-ONLY contract: never any package-manager mutation, never any write to
# /etc /home /usr/local/bin /opt. Reading ~/.npmrc as root is fine (root can
# stat + grep), only writing would violate the contract.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_NPM_PREFIX_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_NPM_PREFIX_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/npm_prefix.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect::npm_prefix_probe <user> <fragment_path>
#
# Populates DETECT_NPM_PREFIX_* exports and writes a `{npm_prefix: {...}}`
# JSON object to <fragment_path>. The orchestrator merges this with the other
# detector fragments via `jq -s 'add'`.
detect::npm_prefix_probe() {
  local user=$1 fragment_path=$2

  # ---- Early bail when npm is absent ----
  # The entrypoint may have been invoked --report-only on a host that hasn't
  # run 30-nodejs.sh yet. Emit a npm_present=false fragment with all nulls.
  if ! as_user_login "$user" command -v npm >/dev/null 2>&1; then
    jq -n --arg user "$user" \
      '{npm_prefix: {npm_present: false, user_prefix: null, system_prefix: null, effective_prefix: null, effective_owner: null, effective_mode: null, install_user_writable: false, prefix_declarations: 0}}' \
      >"$fragment_path"
    export DETECT_NPM_PREFIX_PATH=""
    export DETECT_NPM_PREFIX_USER_WRITABLE=false
    export DETECT_NPM_PREFIX_USER_VALUE=""
    export DETECT_NPM_PREFIX_SYSTEM_VALUE=""
    export DETECT_NPM_PREFIX_EFFECTIVE_OWNER=""
    export DETECT_NPM_PREFIX_EFFECTIVE_MODE=""
    export DETECT_NPM_PREFIX_DECLARATIONS=0
    export DETECT_NPM_PREFIX_SECTION_STATUS=absent
    return 0
  fi

  # ---- user_prefix: per-user override (Pitfall 2 location semantics) ----
  # `--location=user` reads ONLY ~/.npmrc; returns /usr when the file lacks
  # a `prefix=` line. Disambiguated by prefix_declarations below.
  local user_prefix
  user_prefix=$(as_user_login "$user" npm config get prefix --location=user 2>/dev/null | tr -d '[:space:]')

  # ---- system_prefix: npm builtin default ----
  # --no-userconfig instructs npm to ignore ~/.npmrc; env NPM_CONFIG_PREFIX=
  # clears the env override that sudo -E may have carried in. The builtin
  # default is typically /usr on Debian/Ubuntu.
  local system_prefix
  system_prefix=$(as_user_login "$user" env NPM_CONFIG_PREFIX= npm config get prefix --no-userconfig 2>/dev/null | tr -d '[:space:]')

  # ---- effective_prefix: resolved precedence (Pitfall 7 user-shell exports) ----
  # Precedence: env (NPM_CONFIG_PREFIX) > project .npmrc > user ~/.npmrc >
  # builtin. as_user_login sources the user's profile, so a user-shell
  # NPM_CONFIG_PREFIX export propagates.
  local effective_prefix
  effective_prefix=$(as_user_login "$user" npm config get prefix 2>/dev/null | tr -d '[:space:]')

  # ---- Ownership + mode + writability on effective_prefix ----
  local owner mode user_writable
  if [[ -d "$effective_prefix" ]]; then
    owner=$(stat -c '%U:%G' "$effective_prefix" 2>/dev/null || echo "unknown")
    mode=$(stat -c '%a' "$effective_prefix" 2>/dev/null || echo "")
    if as_user "$user" test -w "$effective_prefix"; then
      user_writable=true
    else
      user_writable=false
    fi
  else
    owner="absent"
    mode=""
    user_writable=false
  fi

  # ---- prefix_declarations: count `^prefix=` lines in ~/.npmrc (Pitfall 6) ----
  # Reads ~/.npmrc as root (root can read; we don't write). Discover the home
  # dir from getent passwd column 6 — same idiom as detect/user.sh.
  local home count=0
  home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)
  if [[ -n "$home" && -f "$home/.npmrc" ]]; then
    count=$(grep -cE '^prefix=' "$home/.npmrc" 2>/dev/null || true)
    # Defensive: grep -c may print empty on some pathological inputs; coerce
    # to numeric 0.
    [[ -z "$count" ]] && count=0
  fi

  # ---- JSON fragment via jq -n with --arg / --argjson exclusively ----
  jq -n \
    --argjson npm_present true \
    --arg user_prefix "$user_prefix" \
    --arg system_prefix "$system_prefix" \
    --arg effective_prefix "$effective_prefix" \
    --arg owner "$owner" \
    --arg mode "$mode" \
    --argjson install_user_writable "$user_writable" \
    --argjson prefix_declarations "$count" \
    '{npm_prefix: {
      npm_present: $npm_present,
      user_prefix: $user_prefix,
      system_prefix: $system_prefix,
      effective_prefix: $effective_prefix,
      effective_owner: $owner,
      effective_mode: $mode,
      install_user_writable: $install_user_writable,
      prefix_declarations: $prefix_declarations
    }}' \
    >"$fragment_path"

  # ---- Exports (renderer + Phase 13 readers consume these) ----
  export DETECT_NPM_PREFIX_PATH="$effective_prefix"
  export DETECT_NPM_PREFIX_USER_WRITABLE="$user_writable"
  export DETECT_NPM_PREFIX_USER_VALUE="$user_prefix"
  export DETECT_NPM_PREFIX_SYSTEM_VALUE="$system_prefix"
  export DETECT_NPM_PREFIX_EFFECTIVE_OWNER="$owner"
  export DETECT_NPM_PREFIX_EFFECTIVE_MODE="$mode"
  export DETECT_NPM_PREFIX_DECLARATIONS="$count"
  export DETECT_NPM_PREFIX_SECTION_STATUS=present
}

# --- Phase 13 reader functions (CONTEXT.md "Phase 12 → Phase 13 contract") ---
# Body unchanged from Plan 12-01 stub — already correct accessors over the
# DETECT_NPM_PREFIX_* exports populated above.

detect::npm_prefix_path() { printf '%s' "${DETECT_NPM_PREFIX_PATH:-}"; }
detect::npm_prefix_writable_by_install_user() {
  [[ "${DETECT_NPM_PREFIX_USER_WRITABLE:-false}" == "true" ]]
}
