#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect.sh — detection-layer orchestrator.
#
# Sourced by plugin/bin/agentlinux-install (Phase 12 entrypoint integration)
# and by Phase 13 provisioners that need to consult cached detection results
# via the `detect::*` reader functions defined in the per-detector files under
# plugin/lib/detect/.
#
# Inherits `set -euo pipefail`, the ERR trap, the tee redirect, and the log.sh
# / as_user.sh dependencies from the entrypoint. MUST NOT set its own
# strict-mode flags. Uses `return 1` (not `exit 1`) on any error path —
# sourced fragment (pattern from plugin/provisioner/30-nodejs.sh:71).
#
# Responsibilities:
#   - Source the five per-detector files + the renderer (one-time).
#   - detect::run_once <user> — memoized (DETECT_RAN=1). First call runs all 5
#     probes into per-fragment tmpfiles, jq -s 'add' merges them, jq -S '.' sorts
#     keys for byte-stability, writes to /run/agentlinux-detect.json (tmpfs).
#     Subsequent calls return 0 immediately.
#   - detect::emit_report <text|json> — text → detect::render_text;
#     json → detect::render_json (locked top-level shape per CONTEXT.md
#     Area 1); unknown → log_error + return 64.
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# Resolve the per-detector dir relative to this file. Split declare/assign per
# SC2155 so a cmdsub failure surfaces as non-zero rather than being masked by
# the readonly wrapper. Same idiom as plugin/bin/agentlinux-install BIN_DIR.
DETECT_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/detect" && pwd)
readonly DETECT_LIB_DIR

# Source dependencies + per-detector files. (Caller — agentlinux-install — has
# already sourced log.sh + as_user.sh.) Render first so the rest can be loaded
# in any order; per-detector files have their own source-once guards.
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

# DETECT_CACHE_PATH — tmpfs path for the merged JSON. /run is tmpfs by
# convention on Ubuntu 22.04/24.04/26.04 systemd hosts and Docker containers
# with `--tmpfs /run` (the Docker harness sets this), so the cache evaporates
# at reboot — no stale persistent cache hazard. NOT in the no-op snapshot
# scope per Q2 (D-04 area).
readonly DETECT_CACHE_PATH=/run/agentlinux-detect.json

# detect::run_once <install_user>
#
# Memoized per process. First call: mktemp -d, run all 5 probes into
# per-fragment tmpfiles, jq -s 'add' merge, jq -S '.' sort keys, write to
# DETECT_CACHE_PATH. Subsequent calls: return 0 immediately.
#
# RETURN-trap cleans the tmpdir on every exit path (pattern mirrors
# plugin/lib/idempotency.sh:55-56).
detect::run_once() {
  local user=${1:-agent}
  [[ -n "${DETECT_RAN:-}" ]] && return 0

  # Plan 13-01 Rule 1 fix: when this function is called from a caller that has
  # functrace enabled (`set -T`), the RETURN trap installed below is INHERITED
  # by every function this function calls (detect::*_probe). The first such
  # inner-function RETURN fires the trap, deleting $tmpdir mid-stream, and
  # subsequent probes fail with "No such file or directory" on their fragment
  # writes. bats enables `set -ET` per @test (see /usr/lib/bats-core/
  # test_functions.bash:368 `set +eET` inside the `run` builtin — confirms the
  # outer test body runs WITH `-T`), so direct `detect::run_once` calls from
  # tests/bats/13-reuse.bats surface the bug. Phase 12's entrypoint integration
  # does not trigger it because plugin/bin/agentlinux-install does not set
  # functrace. Mitigation: save the functrace shellopt, disable it for the
  # scope of this function, restore it before the trap fires (the trap is set
  # AFTER `set +T`, so the trap installation captures the disabled state for
  # this scope; restoration before the body's last line keeps the caller-side
  # shellopt intact). Verified locally + in Docker bats run.
  local _saved_functrace=
  [[ $- == *T* ]] && _saved_functrace=1
  set +T

  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  # Expand $tmpdir at trap-install time (function-local var); resolving later
  # would re-read a stale binding if the variable were reassigned. Same idiom
  # as ensure_marker_block in plugin/lib/idempotency.sh.
  trap "rm -rf -- '$tmpdir'" RETURN

  # Each probe writes its own fragment (one JSON object) to tmpdir. Order
  # matches REQUIREMENTS.md / ROADMAP success-criteria order.
  detect::user_probe "$user" "$tmpdir/01-user.json"
  # nodejs probe needs the install user's home — comes from DETECT_USER_HOME
  # which user_probe just exported. Fall back to /home/<user> when DET-01
  # reported the user as absent (stub-side path so the probe still runs).
  detect::nodejs_probe "$user" "${DETECT_USER_HOME:-/home/$user}" "$tmpdir/02-nodejs.json"
  detect::npm_prefix_probe "$user" "$tmpdir/03-npm.json"
  detect::agents_probe "$user" "$tmpdir/04-agents.json"
  detect::sudoers_probe "$tmpdir/05-sudoers.json"

  # Merge into a single object via `jq -s 'add'` (slurp every fragment as the
  # one element of an array, then add() flattens to a single object). `-S` on
  # the second pass sorts keys for byte-stability — RESEARCH §Open Q4
  # recommendation; matters for any future @test that diffs the cache file.
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

  # Restore caller-side functrace shellopt (Plan 13-01 Rule 1 fix — see header
  # above for context). Set BEFORE the function returns so the RETURN trap
  # (which fires AFTER this line) does not capture the +T state and leak it
  # back to the caller. The `if` form (vs `[[ ]] && set -T`) keeps the function
  # exit status at zero when _saved_functrace is empty — under `set -e` the
  # short-circuit form would make the function return 1 because the `[[ ]]`
  # test is the function's last command and evaluates false.
  if [[ -n "$_saved_functrace" ]]; then set -T; fi
  return 0
}

# detect::emit_report <format>
#
# Stdout-emit the detection report in the requested format. text →
# detect::render_text (the renderer reads exported DETECT_* vars populated by
# run_once); json → detect::render_json (wraps the cached merge under the
# locked CONTEXT.md Area 1 top-level shape {generated_at, host, components}).
# Unknown format → log_error + return 64 (EX_USAGE).
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
