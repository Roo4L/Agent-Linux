#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect.sh — detection-layer orchestrator.
#
# Sourced fragment: inherits set -euo pipefail / ERR trap / log.sh / as_user.sh
# from the entrypoint and uses `return 1` (not `exit 1`) to preserve ERR-trap
# attribution. Sources the per-detector files + renderer, runs the probes once,
# and emits the report in text or json form.
[[ -n "${AGENTLINUX_DETECT_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Resolve the per-detector dir relative to this file. Split declare/assign per
# SC2155 so a cmdsub failure surfaces as non-zero rather than being masked by
# the readonly wrapper.
DETECT_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/detect" && pwd)
readonly DETECT_LIB_DIR

# Render first; per-detector files have their own source-once guards.
# shellcheck source=detect/render.sh
. "$DETECT_LIB_DIR/render.sh"
# shellcheck source=detect/user.sh
. "$DETECT_LIB_DIR/user.sh"
# shellcheck source=detect/nodejs.sh
. "$DETECT_LIB_DIR/nodejs.sh"
# shellcheck source=detect/npm_prefix.sh
. "$DETECT_LIB_DIR/npm_prefix.sh"
# shellcheck source=detect/agents.sh
. "$DETECT_LIB_DIR/agents.sh"
# shellcheck source=detect/sudoers.sh
. "$DETECT_LIB_DIR/sudoers.sh"

# Merged JSON lives on tmpfs (/run) so the cache evaporates at reboot — no
# stale-cache hazard.
readonly DETECT_CACHE_PATH=/run/agentlinux-detect.json

# detect::run_once <install_user> — memoized per process. First call runs all 5
# probes into per-fragment tmpfiles, merges them, and writes the cache;
# subsequent calls return 0 immediately. A RETURN trap cleans the tmpdir on
# every exit path.
detect::run_once() {
  local user=${1:-agent}
  [[ -n "${DETECT_RAN:-}" ]] && return 0

  # Under functrace (`set -T`, which bats enables per @test) a RETURN trap is
  # inherited by every called function, so the first inner probe's RETURN would
  # delete $tmpdir mid-stream. Disable functrace for this function's scope and
  # restore it before returning; the trap is installed after `set +T` so it
  # captures the disabled state.
  local _saved_functrace=
  [[ $- == *T* ]] && _saved_functrace=1
  set +T

  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  # Expand $tmpdir at trap-install time so a later reassignment can't leave a
  # stale binding in the trap.
  trap "rm -rf -- '$tmpdir'" RETURN

  # Each probe writes its own JSON fragment to tmpdir.
  detect::user_probe "$user" "$tmpdir/01-user.json"
  # nodejs needs the install user's home from DETECT_USER_HOME (just exported by
  # user_probe); fall back to /home/<user> when the user is absent.
  detect::nodejs_probe "$user" "${DETECT_USER_HOME:-/home/$user}" "$tmpdir/02-nodejs.json"
  detect::npm_prefix_probe "$user" "$tmpdir/03-npm.json"
  detect::agents_probe "$user" "$tmpdir/04-agents.json"
  detect::sudoers_probe "$tmpdir/05-sudoers.json"

  # `jq -s 'add'` merges the fragments into one object; the second pass `-S`
  # sorts keys for byte-stable output across re-runs.
  jq -s 'add' \
    "$tmpdir/01-user.json" \
    "$tmpdir/02-nodejs.json" \
    "$tmpdir/03-npm.json" \
    "$tmpdir/04-agents.json" \
    "$tmpdir/05-sudoers.json" \
    | jq -S '.' \
      >"$DETECT_CACHE_PATH"

  export DETECT_RAN=1
  export DETECT_CACHE_PATH

  # Restore caller-side functrace before returning. The `if` form (vs
  # `[[ ]] && set -T`) keeps the function's exit status at zero under `set -e`
  # when _saved_functrace is empty.
  if [[ -n "$_saved_functrace" ]]; then set -T; fi
  return 0
}

# detect::emit_report <format> — emit the report on stdout: text → render_text,
# json → render_json, unknown → return 64 (EX_USAGE).
detect::emit_report() {
  local format=${1:-text}
  case "$format" in
    text) detect::render_text ;;
    json) detect::render_json ;;
    *)
      log_error "detect::emit_report: unknown format '$format' (expected text or json)"
      return 64
      ;;
  esac
}
