# tests/bats/helpers/interactive.bash
# Thin bash wrappers around the standalone `.exp` scripts under
# helpers/expect/. The .exp files own the pty pair (Bun/Ink raw-mode TTY
# requirement); these functions are the bats-side ergonomics layer.
#
# Design invariants (mirror helpers/assertions.bash + helpers/secrets.bash):
#   - No `set -euo pipefail` at top: this file is SOURCED by bats via
#     `load 'helpers/interactive'`; strict mode inside a sourced library
#     breaks TAP output on the first non-zero command.
#   - No `eval`, no command substitution on env var names — keeps the
#     helper auditable by a single grep.
#   - claude_login MUST NOT echo $ANTHROPIC_API_KEY anywhere (not in
#     comments, not via echo, not into bats $output). The .exp script's
#     `log_user 0` is the primary defence; the bash wrapper passes the
#     key via the SUBPROCESS ENV (not argv, not stdin echo).
#   - Failure paths return non-zero; the caller wraps in `run` and uses
#     `__fail` from helpers/assertions.bash with REDACTED observed-fields
#     (print `<set>` / `<unset>` shape, never the value). This keeps the
#     secret out of the helper's own failure path entirely.
#
# Refs: docs/internals/test-interactive.md (when to use, gotchas, debugging).

# Resolve the helpers/expect directory once at source-time. BATS_TEST_DIRNAME
# is set by bats when this file is `load`ed; absolute-path the .exp scripts
# so the helper works regardless of the test's cwd. The `:-` fallback covers
# the rare case where the helper is sourced outside a bats run (e.g. a
# scratch shell for debugging) so the path resolution still terminates.
__interactive_expect_dir="${BATS_TEST_DIRNAME:-$(dirname "${BASH_SOURCE[0]}")/..}/helpers/expect"

# claude_login: drive `claude /login` once. Designed to be called from
# `setup_file` (auth state persists in ~agent/.claude/ for the file's
# subsequent @tests). Reads ANTHROPIC_API_KEY from THIS shell's env and
# forwards via the subprocess env (sudo -E + expect inherits) so the value
# never lands in any process's argv or /proc/<pid>/cmdline.
#
# Usage in setup_file:
#   require_secret ANTHROPIC_API_KEY
#   claude_login || skip "claude_login failed (transient API or upstream prompt change)"
#
# Returns 0 on success, 1 on any .exp-side failure. The bash side does
# NOT print the key on failure; the .exp script prints redacted diagnostics
# to stderr (via log_user 0 + explicit `puts stderr`).
claude_login() {
  # Dispatch as the agent user so ~agent/.claude/ is written with correct
  # ownership. `-E` preserves ANTHROPIC_API_KEY across the sudo boundary;
  # `--preserve-env=ANTHROPIC_API_KEY` would be tighter but is not portable
  # across all Ubuntu sudo versions in the support matrix (22.04 / 24.04 /
  # 26.04), so `-E` is the safer default.
  sudo -E -u agent -H expect "${__interactive_expect_dir}/claude-login.exp"
}

# claude_interactive_run: reserved name for a future prompt-round-trip
# helper. Not yet implemented — the AGT-02d test only needs claude_login
# and claude_idle_for; per the project's "avoid ceremony" rule, the third
# function is deferred until a concrete consumer arrives. Calling it now
# errors loudly so a future contributor doesn't silently get a no-op.
#
# When implemented: write a new helpers/expect/claude-run.exp that takes
# the prompt text as argv 1, sends it, captures the response up to the
# REPL prompt return, exits 0 / 1. Update this wrapper to dispatch to
# that script with `sudo -u agent -H expect ... "$@"`.
claude_interactive_run() {
  echo "claude_interactive_run: not yet implemented (no consumer; see docs/internals/test-interactive.md)" >&2
  return 2
}

# claude_idle_for <seconds>: hold an interactive `claude` session for N
# seconds doing nothing, then close cleanly via Ctrl-D. Used to exercise
# CLI background loops (auto-updater, telemetry, MCP polling) that only
# fire when the process believes it's attached to a real terminal.
#
# Usage:
#   claude_idle_for 90
#
# Returns 0 on clean exit, 1 on expect timeout / eof failure, 2 on usage
# error (missing or non-numeric argv 1).
claude_idle_for() {
  local seconds=$1
  if [[ -z "${seconds:-}" ]] || ! [[ "${seconds}" =~ ^[0-9]+$ ]]; then
    echo "claude_idle_for: argv 1 must be a positive integer (got: '${seconds-}')" >&2
    return 2
  fi
  sudo -u agent -H expect "${__interactive_expect_dir}/claude-idle.exp" "${seconds}"
}
