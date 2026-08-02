# tests/bats/helpers/assertions.bash
# TST-04 diagnostic contract: every failure prints the requirement ID,
# expected value, observed value, and the log path the caller should grep.
#
# Design invariants:
#   - No `set -euo pipefail` at top: this file is SOURCED by bats via
#     `load 'helpers/assertions'`; strict mode inside a sourced library
#     breaks TAP output on the first non-zero command.
#   - Every assertion's failure path goes through __fail, which emits the
#     four canonical lines on stderr. bats TAP output surfaces these in the
#     `# FAIL: ...` diagnostic block attached to the test.
#   - __fail ends with `return 1` — callers that use `|| __fail ...` get
#     the test-killing exit code automatically.
#   - assert_no_eacces accepts EITHER a file path OR a literal string so
#     tests can feed it "$output" from a recent `run` OR the installer log.
#
# Refs: 02-RESEARCH.md §Example 3, §Pitfall 7 (stdout+stderr merge).

# Print a TAP-friendly diagnostic line (visible on passing + failing tests)
# via FD 3 — bats's "detail channel" that prints between test output lines.
__diag() {
  printf '# %s\n' "$*" >&3
}

# Hard-fail the current test with a formatted diagnostic. All four fields are
# required; the log_hint is where a human should look first (typically the
# installer's tee'd transcript).
#
# Usage: __fail "<req-id>" "<expected>" "<observed>" "<log-hint>"
__fail() {
  local req_id=$1 expected=$2 observed=$3 log_hint=$4
  {
    printf '# FAIL: %s\n' "$req_id"
    printf '#   expected: %s\n' "$expected"
    printf '#   observed: %s\n' "$observed"
    printf '#   log:      %s\n' "$log_hint"
  } >&2
  return 1
}

# INST-05 gate. Input is either stdout+stderr merged in a variable OR a log
# file path. Any line containing `EACCES` or `permission denied`
# (case-sensitive on EACCES per the no-EACCES contract in the
# behavior-test-contract skill) fails the test.
#
# Usage:
#   assert_no_eacces "INST-05" "$output"
#   assert_no_eacces "INST-05" /var/log/agentlinux-install.log
assert_no_eacces() {
  local req_id=$1 src=$2 content
  if [[ -f $src ]]; then
    content=$(cat -- "$src")
  else
    content=$src
  fi
  if printf '%s' "$content" | grep -Eq 'EACCES|permission denied'; then
    local hits
    hits=$(printf '%s' "$content" | grep -E 'EACCES|permission denied' | head -5 | tr '\n' '|')
    __fail "$req_id" \
      "no 'EACCES' or 'permission denied' in output" \
      "found: ${hits}" \
      "${src}"
    return 1
  fi
}

# BHV-02..06 helper. After an invoke_mode ran, asserts that `$output`
# contains the expected substring. Uses fixed-string grep (`grep -F`) so the
# caller does not have to escape PATH separators or forward slashes.
#
# Usage (caller has just called `run_ssh 'echo $PATH'`):
#   assert_path_has "BHV-02" "/home/agent/.local/bin"
assert_path_has() {
  local req_id=$1 expected=$2
  if ! printf '%s' "${output:-}" | grep -qF -- "$expected"; then
    __fail "$req_id" \
      "output contains '${expected}'" \
      "${output:-<empty>}" \
      "/var/log/agentlinux-install.log"
  fi
}

# BHV / INST common precondition. After a `run` (or any helper that wraps
# `run`), asserts the captured exit status is zero. Emits output on failure
# so the test diagnostic points at the command that failed.
assert_exit_zero() {
  local req_id=$1
  if [[ ${status:-1} -ne 0 ]]; then
    __fail "$req_id" \
      "exit status 0" \
      "exit status ${status:-unset}; output: ${output:-<empty>}" \
      "/var/log/agentlinux-install.log"
  fi
}

# ---------------------------------------------------------------------------
# Appended in Phase 3 (Plan 03-02).
#
# RT-04 gate. Input is the bats `$output` populated by a prior `run` or
# `invoke_mode` that executed `npm config get prefix`. Passes if the prefix
# starts with `/home/agent/` (the trailing slash is load-bearing — it
# prevents a hypothetical `/home/agent-staging/...` path from matching).
# Fails every other shape with a TST-04 four-line diagnostic naming the
# expected prefix, the observed value, and the likely source the debugger
# should read first (`~agent/.npmrc`).
#
# T-03-07 mitigation: catches a regression where npm resolves the prefix to
# /usr, /usr/local, or any non-agent-owned path in any INVOKE_MODE.
#
# Usage (note the req-id carries the mode suffix for multi-mode loops so
# failure diagnostics pinpoint WHICH mode regressed):
#   invoke_mode "$mode" 'npm config get prefix'
#   assert_user_prefix_in_home "RT-04 (${mode})"
# ---------------------------------------------------------------------------
assert_user_prefix_in_home() {
  local req_id=$1
  local observed
  observed=$(printf '%s' "${output:-}" | tr -d '[:space:]')

  case "$observed" in
    /home/agent/*)
      return 0
      ;;
    *)
      __fail "$req_id" \
        "npm config get prefix under /home/agent/" \
        "observed: ${observed:-<empty>}" \
        "~agent/.npmrc (expected: prefix=/home/agent/.npm-global)"
      ;;
  esac
}

# assert_detect_cache_has <agent-id> <provision-output>
#
# The REMEDIATE-04 / REUSE-03 E2E tests all depend on one precondition: the
# provision that ran just before them re-ran detect and RECORDED the brownfield
# binary in the detect cache. When that does not happen the CLI is correct to do
# a plain install — so the test fails several assertions later, on a missing
# `[REMEDIATE-04]` marker, describing a symptom rather than the cause.
#
# Written after four such tests failed on almalinux-9 under QEMU while passing
# on the same distro under Docker and on Ubuntu under QEMU. The provision output
# that would have explained it was being sent to /dev/null by the tests
# themselves, so the transcript held no evidence at all. Hence both halves here:
# name the missing precondition, AND quote the provision run that was supposed
# to establish it.
#
# `$AGENTLINUX_DETECT_CACHE` else the /run default, matching cache.rs.
assert_detect_cache_has() {
  local id=$1 prov_out=${2:-<not captured>} want_path=${3:-}
  local cache=${AGENTLINUX_DETECT_CACHE:-/run/agentlinux-detect.json}

  [[ -f $cache ]] || __fail "REMEDIATE-04" \
    "detect cache $cache exists after provision" \
    "absent — provision did not persist it; its output was:
$prov_out" "$cache"

  grep -qF "\"$id\"" "$cache" || __fail "REMEDIATE-04" \
    "detect cache records '$id' (the brownfield binary detect was meant to find)" \
    "not in $cache. cache=$(cat "$cache" 2>&1). provision output was:
$prov_out" "$cache"

  # The PATH is the whole point, not merely the id. REMEDIATE-04 fires on a
  # MISMATCH between the detected path and the canonical one, so a cache that
  # records the agent at its canonical location is indistinguishable from a
  # clean install — the CLI then correctly declines to remediate and the marker
  # assertion downstream fails with nothing to explain it. Checking only the id
  # let exactly that through on almalinux-9/QEMU.
  if [[ -n $want_path ]]; then
    grep -qF "$want_path" "$cache" || __fail "REMEDIATE-04" \
      "detect cache records '$id' at the BROWNFIELD path '$want_path'" \
      "recorded elsewhere — REMEDIATE-04 cannot fire without a path mismatch.
cache=$(cat "$cache" 2>&1)
also on host: .local/bin/claude=$(ls -l /home/agent/.local/bin/claude 2>&1), .npm-global/bin/claude=$(ls -l /home/agent/.npm-global/bin/claude 2>&1)
provision output was:
$prov_out" "$cache"
  fi
}
