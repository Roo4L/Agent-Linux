#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/nodejs.sh — REMEDIATE-01 npm-prefix handlers.
#
# Two state-overwriting actions; the consent gate in remediate.sh has already
# enforced --yes (or registered a bail) before any of these run.
#
# Strategy selector:
#   chown   — prefix is UNDER the install user's home AND trivially salvageable
#             (only allowlisted entries). One `chown -R <user>:<user> <prefix>`.
#   rebase  — otherwise. Create ~user/.npm-global, write ~user/.npmrc, migrate
#             global modules; old prefix is NEVER deleted. Best-effort per
#             module; failures logged [REMEDIATE-01:partial].
#
# Security: chown -R fires only when all three of {owner != install user,
# prefix-under-home, allowlist passes} hold — so system paths (/usr,
# /usr/local) and prefixes containing third-party modules are never chowned.
#
# Sourced fragment: inherits `set -euo pipefail` + ERR trap + log.sh from the
# entrypoint; MUST NOT set its own strict-mode flags; uses `return 1` on error.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_NODEJS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_NODEJS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/nodejs.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::nodejs::_is_trivially_salvageable <prefix>
# Returns 0 iff <prefix> contains ONLY allowlisted entries: lib/, bin/, share/,
# etc/, package.json, package-lock.json — and lib/node_modules is empty/absent.
# Any non-allowlist entry (e.g. a user-installed module) returns 1 and forces a
# rebase. This is the gate that prevents chown from clobbering third-party trees.
remediate::nodejs::_is_trivially_salvageable() {
  local prefix=$1
  # Non-existent prefix is vacuously salvageable; the selector should not call
  # this on a missing prefix anyway.
  [[ -d "$prefix" ]] || return 0
  local found
  found=$(find "$prefix" -maxdepth 1 -mindepth 1 \
    -not -path "$prefix/lib" \
    -not -path "$prefix/bin" \
    -not -path "$prefix/share" \
    -not -path "$prefix/etc" \
    -not -name "package.json" \
    -not -name "package-lock.json" \
    -print -quit 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    return 1
  fi
  # A populated lib/node_modules/<pkg>/ means a user installed a global module
  # under the prefix — an agent-unwritable third-party tree we must NOT chown.
  if [[ -d "$prefix/lib/node_modules" ]]; then
    found=$(find "$prefix/lib/node_modules" -maxdepth 1 -mindepth 1 -print -quit 2>/dev/null || true)
    if [[ -n "$found" ]]; then
      return 1
    fi
  fi
  return 0
}

# remediate::nodejs::_strategy_for <prefix> <user_home>
# Prints "chown" or "rebase". chown only when prefix is under <user_home> AND
# trivially salvageable; rebase otherwise (incl. system paths). Under-home is a
# literal prefix-match (no readlink) — rebase is the safe default when symlinks
# would confuse containment.
remediate::nodejs::_strategy_for() {
  local prefix=$1 user_home=$2
  if [[ "$prefix" != "$user_home"/* ]]; then
    printf 'rebase'
    return 0
  fi
  if remediate::nodejs::_is_trivially_salvageable "$prefix"; then
    printf 'chown'
  else
    printf 'rebase'
  fi
  return 0
}

# remediate::nodejs::_enumerate_modules <old_owner> [old_prefix]
# Prints `pkg@version` (one per line) for every global module under the OLD
# prefix, minus npm and the catalog agents (which own their own install). The
# optional <old_prefix> is set via NPM_CONFIG_PREFIX so enumeration targets the
# OLD prefix rather than the caller's npm-default; without it `npm ls -g` would
# resolve root's system prefix and miss a non-default prefix.
# jq parses the JSON safely; values are bracketed by `--` downstream so shell
# metacharacters cannot escape.
remediate::nodejs::_enumerate_modules() {
  local owner=$1 old_prefix=${2:-}
  local raw
  if [[ -n "$old_prefix" ]]; then
    raw=$(as_user "$owner" env "NPM_CONFIG_PREFIX=$old_prefix" npm ls -g --json --depth=0 2>/dev/null || printf '{}')
  else
    raw=$(as_user "$owner" npm ls -g --json --depth=0 2>/dev/null || printf '{}')
  fi
  # Excluded ids fed to jq via stdin (data-driven; no interpolation injection).
  local excluded_json
  excluded_json=$(printf '%s\n' \
    "npm" \
    "@anthropic-ai/claude-code" \
    "get-shit-done-cc" \
    "@playwright/cli" \
    | jq -R . | jq -s .)
  jq -r --argjson excluded "$excluded_json" '
    (.dependencies // {})
    | to_entries[]
    | select(.key as $k | ($excluded | index($k) | not))
    | "\(.key)@\(.value.version // "latest")"
  ' <<<"$raw" 2>/dev/null || true
}

# remediate::nodejs::_apply_chown <prefix> <user>
# `chown -R <user>:<user> <prefix>`. Emits the [REMEDIATE-01] strategy=chown
# marker; on failure returns 1 with [REMEDIATE-01:fail].
remediate::nodejs::_apply_chown() {
  local prefix=$1 user=$2
  log_info "[REMEDIATE-01] strategy=chown path=$prefix new_owner=$user:$user"
  if ! chown -R "$user:$user" "$prefix"; then
    log_error "[REMEDIATE-01:fail] reason=chown-denied path=$prefix"
    return 1
  fi
  log_info "[REMEDIATE-01] chown complete: $prefix now $user:$user"
  return 0
}

# remediate::nodejs::_apply_rebase <old_prefix> <user> <user_home> <old_owner>
# Create ~user/.npm-global (bin/ + lib/), point ~user/.npmrc at it, then migrate
# global modules from the OLD prefix best-effort (per-module failures logged
# [REMEDIATE-01:partial], no abort). Old prefix is NEVER deleted. A failure of
# the rebase itself (mkdir/npmrc-write denied) returns 1 + [REMEDIATE-01:fail],
# leaving the old prefix untouched for a clean retry.
remediate::nodejs::_apply_rebase() {
  local old_prefix=$1 user=$2 user_home=$3 old_owner=$4
  local new_prefix="$user_home/.npm-global"
  log_info "[REMEDIATE-01] strategy=rebase from=$old_prefix to=$new_prefix"

  # ensure_dir creates OR re-asserts mode+ownership, so a partial prior rebase
  # converges to the canonical state.
  if ! ensure_dir "$new_prefix" 0755 "$user:$user" \
    || ! ensure_dir "$new_prefix/bin" 0755 "$user:$user" \
    || ! ensure_dir "$new_prefix/lib" 0755 "$user:$user"; then
    log_error "[REMEDIATE-01:fail] reason=mkdir-denied path=$new_prefix"
    return 1
  fi

  # ~user/.npmrc with the prefix line: atomic create-if-absent, then idempotent
  # ensure_line_in_file.
  if [[ ! -f "$user_home/.npmrc" ]]; then
    if ! install -m 0644 -o "$user" -g "$user" /dev/null "$user_home/.npmrc"; then
      log_error "[REMEDIATE-01:fail] reason=npmrc-write-denied path=$user_home/.npmrc"
      return 1
    fi
  fi
  ensure_line_in_file "prefix=$new_prefix" "$user_home/.npmrc"
  # ensure_line_in_file runs with root's umask and doesn't chown; re-assert
  # ownership + mode so the user can edit and npm can read.
  chown "$user:$user" "$user_home/.npmrc"
  chmod 0644 "$user_home/.npmrc"
  log_info "[REMEDIATE-01] wrote ~$user/.npmrc with prefix=$new_prefix"

  # Enumerate + migrate modules from the OLD prefix, best-effort.
  local modules_manifest migrated_count=0 failed_count=0
  modules_manifest=$(remediate::nodejs::_enumerate_modules "$old_owner" "$old_prefix")
  if [[ -n "$modules_manifest" ]]; then
    local module_count
    module_count=$(printf '%s\n' "$modules_manifest" | grep -c '.' || true)
    log_info "[REMEDIATE-01] migrating $module_count modules from $old_prefix"
    local pkg_at_ver
    while IFS= read -r pkg_at_ver; do
      [[ -z "$pkg_at_ver" ]] && continue
      # The npm-level `--` stops a `-flag@1` package name being reparsed as an
      # npm flag. (as_user already supplies sudo's `--`; a second one here would
      # make sudo treat `--` as the command name and fail.)
      if as_user "$user" npm install -g -- "$pkg_at_ver" >/dev/null 2>&1; then
        log_info "[REMEDIATE-01:migrated] module=$pkg_at_ver"
        migrated_count=$((migrated_count + 1))
      else
        log_warn "[REMEDIATE-01:partial] module=$pkg_at_ver reason=npm-install-failed"
        failed_count=$((failed_count + 1))
      fi
    done <<<"$modules_manifest"
  else
    log_info "[REMEDIATE-01] no modules to migrate from $old_prefix (empty or only catalog/npm entries)"
  fi

  log_info "[REMEDIATE-01] rebase complete: migrated=$migrated_count failed=$failed_count old_prefix=$old_prefix (NOT deleted; user cleanup)"
  return 0
}

# remediate::nodejs::chown_or_rebase
# Entry point dispatched from 30-nodejs.sh. Reads detect:: exports, runs the
# strategy selector, dispatches to chown or rebase. The consent gate has
# already enforced --yes (or bailed) before this is reached.
remediate::nodejs::chown_or_rebase() {
  local user=${INSTALL_USER:-agent}
  local user_home=${DETECT_USER_HOME:-/home/$user}
  local prefix=${DETECT_NPM_PREFIX_PATH:-}
  local owner=${DETECT_NPM_PREFIX_EFFECTIVE_OWNER:-}
  # Old owner (LHS of "user:group") is the sudo target for `npm ls -g` — its
  # npm view of the OLD prefix is canonical.
  local old_owner_user=${owner%:*}

  if [[ -z "$prefix" ]]; then
    log_error "[REMEDIATE-01:fail] reason=detect-cache-missing-prefix-path"
    return 1
  fi

  # Fall back to root when the old owner is unknown/absent; rebase still works
  # against an empty manifest.
  if [[ -z "$old_owner_user" || "$old_owner_user" == "absent" || "$old_owner_user" == "unknown" ]]; then
    old_owner_user=root
  fi

  local strategy
  strategy=$(remediate::nodejs::_strategy_for "$prefix" "$user_home")
  case "$strategy" in
    chown) remediate::nodejs::_apply_chown "$prefix" "$user" ;;
    rebase) remediate::nodejs::_apply_rebase "$prefix" "$user" "$user_home" "$old_owner_user" ;;
    *)
      log_error "[REMEDIATE-01:fail] reason=unknown-strategy strategy=$strategy"
      return 1
      ;;
  esac
}

# remediate::nodejs::npm_prefix_stub — LEGACY shim kept for source compat;
# delegates to chown_or_rebase.
remediate::nodejs::npm_prefix_stub() {
  remediate::nodejs::chown_or_rebase
}
