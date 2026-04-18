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
