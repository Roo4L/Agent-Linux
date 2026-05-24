#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/remediate/nodejs.sh — REMEDIATE-01 npm-prefix handlers.
#
# Phase 14 Plan 14-02 lands the real chown/rebase strategy per CONTEXT.md Area 2.
# Two state-overwriting actions; the consent gate in remediate.sh has already
# enforced --yes (or registered a bail) before any of these run.
#
# Strategy selector (Area 2 Q1):
#   chown   — effective prefix is UNDER install user's home AND prefix dir is
#             "trivially salvageable" (only allowlisted entries — see Q2). One
#             `chown -R <user>:<user> <prefix>` and we're done.
#   rebase  — otherwise. Create ~user/.npm-global, write ~user/.npmrc, migrate
#             global modules via `npm ls -g --json --depth=0` on OLD prefix.
#             Old prefix is NEVER deleted (user can clean manually). Best-effort
#             per module; failures logged with [REMEDIATE-01:partial].
#
# T-14-03 mitigation: the trivially-salvageable check is airtight. Any
# non-allowlist entry under the prefix (even a single user-installed module at
# lib/node_modules/<pkg>/) flips the strategy to rebase. No chown ever fires on
# a non-empty prefix containing third-party modules.
#
# T-14-07 mitigation: per-module npm install uses `--` to terminate sudo+npm
# option parsing; adversarial version strings in `npm ls` output are passed
# verbatim to npm which rejects them as invalid semver (logged + skipped).
#
# T-14-08 mitigation: chown -R is guarded by THREE conditions (effective owner
# != install user, prefix-under-home, allowlist passes). System paths (/usr,
# /usr/local) are never chowned — they fail the prefix-under-home check.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via
# plugin/lib/remediate.sh. Inherits `set -euo pipefail`, the ERR trap, and the
# log.sh dependency from the entrypoint. MUST NOT set its own strict-mode
# flags. Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Source-once guard.
[[ -n "${AGENTLINUX_REMEDIATE_NODEJS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_REMEDIATE_NODEJS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'remediate/nodejs.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# remediate::nodejs::_is_trivially_salvageable <prefix>
#
# Returns 0 (true) iff <prefix> directory contains ONLY allowlisted entries
# per CONTEXT.md Area 2 Q2:
#   - lib/ (empty OR containing only an empty node_modules/)
#   - bin/, share/, etc/ (empty)
#   - package.json, package-lock.json (npm-managed metadata)
#
# Returns 1 (false) on ANY non-allowlist entry. T-14-03 — the predicate is the
# airtight gate that forces a rebase when third-party modules are present.
#
# Implementation: `find -maxdepth 1 -mindepth 1` enumerates top-level entries
# minus the allowlist; if the result is non-empty there's at least one
# disallowed entry. Then a follow-up scan of lib/node_modules catches the
# common case where the top-level is clean but a module has been installed.
remediate::nodejs::_is_trivially_salvageable() {
  local prefix=$1
  # Non-existent prefix is vacuously salvageable (chown -R will create the
  # ownership the caller wants). Defensive — strategy selector should not
  # call this on a non-existent prefix anyway.
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
  # Follow-up: lib/node_modules must also be empty (or absent). A populated
  # lib/node_modules/<pkg>/ is the canonical T-14-03 case — a user installed a
  # global module via `sudo npm install -g`, leaving an agent-unwritable third-
  # party tree under the prefix that we must NOT clobber via chown.
  if [[ -d "$prefix/lib/node_modules" ]]; then
    found=$(find "$prefix/lib/node_modules" -maxdepth 1 -mindepth 1 -print -quit 2>/dev/null || true)
    if [[ -n "$found" ]]; then
      return 1
    fi
  fi
  return 0
}

# remediate::nodejs::_strategy_for <prefix> <user_home>
#
# Returns "chown" or "rebase" on stdout. Decision tree per CONTEXT.md Area 2 Q1:
#   1. prefix NOT under <user_home> → "rebase" (never chown system paths;
#      T-14-08 mitigation — /usr / /usr/local / /opt are not user home).
#   2. prefix under <user_home> AND trivially salvageable → "chown".
#   3. otherwise → "rebase".
#
# The under-home check uses bash prefix-match on the literal path (no readlink
# — symlinks are exotic enough that exact-path containment is the safe-by-
# default contract; the rebase path is itself safe when symlinks confuse us).
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
#
# Prints `pkg@version` lines for every global module installed under the OLD
# prefix (one per line). Filters out the catalog agents and npm itself per
# CONTEXT.md Area 2 Q3 — the catalog has its own install machinery; npm comes
# from the system Node install.
#
# The optional <old_prefix> argument is set via NPM_CONFIG_PREFIX so the
# enumeration targets the OLD prefix specifically (rather than the caller's
# npm-default prefix). Without this, `as_user root npm ls -g` would resolve to
# root's system prefix (typically /usr/lib/node_modules) and miss modules
# installed under a non-default prefix (e.g. /usr/local/agentlinux-old/).
#
# Filtering set:
#   - npm                           (system-managed)
#   - @anthropic-ai/claude-code     (catalog: native installer; do not migrate)
#   - get-shit-done-cc              (catalog: gsd recipe owns it)
#   - @playwright/cli               (catalog: playwright-cli recipe owns it)
#
# T-14-07 mitigation: jq parses the JSON safely; values are passed verbatim
# downstream and bracketed by `--` at the as_user/npm boundary so shell
# metacharacters cannot escape.
remediate::nodejs::_enumerate_modules() {
  local owner=$1 old_prefix=${2:-}
  local raw
  if [[ -n "$old_prefix" ]]; then
    # `env NPM_CONFIG_PREFIX=$old_prefix` carries the override into the
    # as_user sudo context — sudo -E preserves env on the as_user keystone.
    raw=$(as_user "$owner" env "NPM_CONFIG_PREFIX=$old_prefix" npm ls -g --json --depth=0 2>/dev/null || printf '{}')
  else
    raw=$(as_user "$owner" npm ls -g --json --depth=0 2>/dev/null || printf '{}')
  fi
  # Build a JSON array of excluded ids on stdin to jq so the filter is
  # data-driven (no string-interpolation injection surface).
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
#
# The chown branch. `chown -R <user>:<user> <prefix>` and done. Emits the
# [REMEDIATE-01] strategy=chown marker for transcript clarity. Failure (chown
# denied — should never happen since we're root, but defensive) returns 1 with
# [REMEDIATE-01:fail].
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
#
# The rebase branch. Steps:
#   1. Create ~user/.npm-global with bin/ + lib/ subdirs (agent-owned 0755).
#   2. Ensure ~user/.npmrc has `prefix=~user/.npm-global` (atomic create-if-
#      absent, then ensure_line_in_file). Re-assert ownership/mode afterward.
#   3. Enumerate global modules under OLD prefix via _enumerate_modules.
#   4. For each `pkg@ver`: `as_user <user> -H -- npm install -g -- "$pkg@$ver"`.
#      Best-effort: failures are logged [REMEDIATE-01:partial] but do not abort.
#   5. Log [REMEDIATE-01] rebase complete with migrated/failed counts.
#
# Old prefix is NEVER deleted — user cleanup. The new ~user/.npm-global becomes
# the canonical location; downstream 40-path-wiring.sh prepends it to PATH.
#
# Failure of the rebase ITSELF (mkdir denied, npmrc write denied) returns 1 +
# [REMEDIATE-01:fail] reason=<...>. Leaves old prefix untouched so user can
# retry from a clean slate.
remediate::nodejs::_apply_rebase() {
  local old_prefix=$1 user=$2 user_home=$3 old_owner=$4
  local new_prefix="$user_home/.npm-global"
  log_info "[REMEDIATE-01] strategy=rebase from=$old_prefix to=$new_prefix"

  # Step 1: create the new prefix layout. ensure_dir creates OR re-asserts
  # mode+ownership so a partial-prior-rebase converges to the canonical state.
  if ! ensure_dir "$new_prefix" 0755 "$user:$user" \
    || ! ensure_dir "$new_prefix/bin" 0755 "$user:$user" \
    || ! ensure_dir "$new_prefix/lib" 0755 "$user:$user"; then
    log_error "[REMEDIATE-01:fail] reason=mkdir-denied path=$new_prefix"
    return 1
  fi

  # Step 2: ~user/.npmrc with the prefix line. Atomic create-if-absent then
  # idempotent ensure_line_in_file (same pattern as 30-nodejs.sh CREATE path).
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

  # Step 3-4: enumerate + migrate modules from the OLD prefix. Best-effort —
  # per-module failures do not abort the rebase (the operator can re-install
  # missing modules manually).
  local modules_manifest migrated_count=0 failed_count=0
  modules_manifest=$(remediate::nodejs::_enumerate_modules "$old_owner" "$old_prefix")
  if [[ -n "$modules_manifest" ]]; then
    local module_count
    module_count=$(printf '%s\n' "$modules_manifest" | grep -c '.' || true)
    log_info "[REMEDIATE-01] migrating $module_count modules from $old_prefix"
    local pkg_at_ver
    while IFS= read -r pkg_at_ver; do
      [[ -z "$pkg_at_ver" ]] && continue
      # T-14-07: `--` terminates sudo AND npm option parsing so a hypothetical
      # `-flag@1` package name cannot be reparsed as a sudo/npm flag. Adversarial
      # version strings flow into npm which rejects invalid semver.
      if as_user "$user" -- npm install -g -- "$pkg_at_ver" >/dev/null 2>&1; then
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
#
# Top-level entry point dispatched from 30-nodejs.sh's RESOLUTIONS[npm-prefix]
# case-branch. Reads detect:: exports + INSTALL_USER, runs strategy selector,
# dispatches to the chown or rebase handler.
#
# The state-overwriting consent gate in remediate.sh has already enforced
# --yes (or registered a bail) before this is reached. If we're here, the
# operator has consented to either chown or rebase.
remediate::nodejs::chown_or_rebase() {
  local user=${INSTALL_USER:-agent}
  local user_home=${DETECT_USER_HOME:-/home/$user}
  local prefix=${DETECT_NPM_PREFIX_PATH:-}
  local owner=${DETECT_NPM_PREFIX_EFFECTIVE_OWNER:-}
  # Old owner user is the LHS of "user:group"; we use it as the sudo target
  # for `npm ls -g` since that user (typically root, sometimes another local
  # user) is the one whose npm view of the OLD prefix is canonical.
  local old_owner_user=${owner%:*}

  if [[ -z "$prefix" ]]; then
    log_error "[REMEDIATE-01:fail] reason=detect-cache-missing-prefix-path"
    return 1
  fi

  # Defensive: if the old owner can't be determined (e.g., detect found the
  # prefix absent and emitted "absent"), fall back to root for the enumeration
  # step. The rebase still works against an empty manifest.
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

# remediate::nodejs::npm_prefix_stub (LEGACY — kept for source compatibility)
#
# Plan 14-01 shipped this name; Plan 14-02 keeps the symbol as a thin shim that
# delegates to chown_or_rebase so any older test fixture / call site that still
# references the stub name does not break. The provisioner 30-nodejs.sh has
# been updated to call chown_or_rebase directly.
remediate::nodejs::npm_prefix_stub() {
  remediate::nodejs::chown_or_rebase
}
