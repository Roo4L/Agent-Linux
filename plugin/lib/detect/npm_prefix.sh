#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/npm_prefix.sh — DET-03 npm global prefix discovery probe.
#
# Sourced fragment: inherits set -euo pipefail / ERR trap / log.sh / as_user.sh
# and uses `return 1` (not `exit 1`).
#
# Three-value report:
#   user_prefix      — `npm config get prefix --location=user` (reads ONLY
#                      ~/.npmrc; returns the builtin /usr when no prefix= line —
#                      disambiguated by the prefix_declarations counter).
#   system_prefix    — `env NPM_CONFIG_PREFIX= npm config get prefix
#                      --no-userconfig` (builtin default; clears env so sudo -E
#                      doesn't carry over an existing override).
#   effective_prefix — `npm config get prefix` (resolved precedence:
#                      env > project .npmrc > user ~/.npmrc > builtin).
#
# Every `npm config get` runs through as_user_login (login shell) so the install
# user's profile NPM_CONFIG_PREFIX export propagates; bare as_user wouldn't.
#
# Read-only: no package mutation, no writes. Reading ~/.npmrc as root is fine.
# `npm config get` would otherwise write a debug log on every read; the
# npm_config_logs_max=0 + npm_config_loglevel=silent vars below suppress it to
# keep the probe side-effect-free.
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

  # Early bail when npm is absent (e.g. --report-only before Node is installed):
  # emit a npm_present=false fragment with all nulls.
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

  # The npm_config_* vars below are passed via `env` (as_user_login uses
  # `sudo -i`, which doesn't preserve caller env) to suppress npm's per-read
  # debug log; see the header.

  # ---- user_prefix: per-user override ----
  # `--location=user` reads ONLY ~/.npmrc; returns /usr when the file lacks a
  # `prefix=` line. Disambiguated by prefix_declarations below.
  local user_prefix
  user_prefix=$(as_user_login "$user" env npm_config_logs_max=0 npm_config_loglevel=silent npm config get prefix --location=user 2>/dev/null | tr -d '[:space:]')

  # ---- system_prefix: npm builtin default ----
  # --no-userconfig instructs npm to ignore ~/.npmrc; env NPM_CONFIG_PREFIX=
  # clears the env override that sudo -E may have carried in. The builtin
  # default is typically /usr on Debian/Ubuntu.
  local system_prefix
  system_prefix=$(as_user_login "$user" env npm_config_logs_max=0 npm_config_loglevel=silent NPM_CONFIG_PREFIX= npm config get prefix --no-userconfig 2>/dev/null | tr -d '[:space:]')

  # ---- effective_prefix: resolved precedence ----
  # env (NPM_CONFIG_PREFIX) > project .npmrc > user ~/.npmrc > builtin.
  # as_user_login sources the profile so a user-shell export propagates.
  local effective_prefix
  effective_prefix=$(as_user_login "$user" env npm_config_logs_max=0 npm_config_loglevel=silent npm config get prefix 2>/dev/null | tr -d '[:space:]')

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

  # ---- prefix_declarations: count `^prefix=` lines in ~/.npmrc ----
  # Reads ~/.npmrc as root (no write). Home comes from getent passwd column 6.
  local home count=0
  home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)
  if [[ -n "$home" && -f "$home/.npmrc" ]]; then
    count=$(grep -cE '^prefix=' "$home/.npmrc" 2>/dev/null || true)
    # grep -c can print empty on pathological input; coerce to 0.
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

  # ---- Exports (renderer + readers consume these) ----
  export DETECT_NPM_PREFIX_PATH="$effective_prefix"
  export DETECT_NPM_PREFIX_USER_WRITABLE="$user_writable"
  export DETECT_NPM_PREFIX_USER_VALUE="$user_prefix"
  export DETECT_NPM_PREFIX_SYSTEM_VALUE="$system_prefix"
  export DETECT_NPM_PREFIX_EFFECTIVE_OWNER="$owner"
  export DETECT_NPM_PREFIX_EFFECTIVE_MODE="$mode"
  export DETECT_NPM_PREFIX_DECLARATIONS="$count"
  export DETECT_NPM_PREFIX_SECTION_STATUS=present
}

# Thin accessors over the DETECT_NPM_PREFIX_* exports populated above.
detect::npm_prefix_path() { printf '%s' "${DETECT_NPM_PREFIX_PATH:-}"; }
detect::npm_prefix_writable_by_install_user() {
  [[ "${DETECT_NPM_PREFIX_USER_WRITABLE:-false}" == "true" ]]
}
