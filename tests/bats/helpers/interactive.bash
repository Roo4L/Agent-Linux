# tests/bats/helpers/interactive.bash
# Thin bash wrappers around the standalone `.exp` scripts under
# helpers/expect/. The .exp files own the pty pair (Bun/Ink raw-mode TTY
# requirement); these functions are the bats-side ergonomics layer.
#
# Design invariants (mirror helpers/assertions.bash + helpers/secrets.bash):
#   - No `set -euo pipefail` at top: sourced by bats via `load 'helpers/interactive'`.
#   - No `eval`, no command substitution on env var names.
#   - claude_login MUST NOT echo $ANTHROPIC_API_KEY anywhere. Defence:
#     `log_user 0` in the .exp script + key forwarded via subprocess env
#     (not argv, not stdin echo) via `sudo --preserve-env=ANTHROPIC_API_KEY`.
#   - Failure paths return non-zero; the caller wraps in `run` and uses
#     `__fail` from helpers/assertions.bash with REDACTED observed-fields
#     (`<set>` / `<unset>` shape, never the value).
#
# Refs: docs/internals/test-interactive.md (when to use, gotchas, debugging).

# Anchor the .exp directory to this helper file's own location so it
# resolves the same way regardless of how bats was invoked.
__interactive_expect_dir="$(dirname "${BASH_SOURCE[0]}")/expect"

# claude_login: drive `claude /login` once. Designed to be called from
# `setup_file` (auth state persists in ~agent/.claude/ for the file's
# subsequent @tests). Reads ANTHROPIC_API_KEY from THIS shell's env and
# forwards it via the subprocess env (sudo --preserve-env), never argv.
#
# Usage in setup_file:
#   require_secret ANTHROPIC_API_KEY
#   claude_login || skip "claude_login failed (transient API or upstream prompt change)"
#
# Returns 0 on success, 1 on any .exp-side failure. The bash side does
# NOT print the key on failure; the .exp script prints redacted diagnostics.
claude_login() {
  # `--preserve-env=ANTHROPIC_API_KEY` forwards exactly that one variable
  # across the sudo boundary. `-E` would silently drop it on Ubuntu's
  # default sudoers (env_reset + a fixed env_keep that excludes
  # ANTHROPIC_API_KEY), so the explicit allowlist is the only correct
  # form for the support matrix (22.04 / 24.04 / 26.04; sudo --preserve-env
  # has been available since 1.8.4 / 2012).
  sudo --preserve-env=ANTHROPIC_API_KEY -u agent -H expect \
    "${__interactive_expect_dir}/claude-login.exp"
}

# claude_interactive_run: reserved name for a future prompt-round-trip
# helper. Not yet implemented — the AGT-02d test only needs claude_login
# and claude_idle_for. Errors loudly so a future contributor doesn't get
# a silent no-op.
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
