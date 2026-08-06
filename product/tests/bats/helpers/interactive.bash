# tests/bats/helpers/interactive.bash
# Thin bash wrapper around the standalone `.exp` scripts under
# helpers/expect/. The .exp files own the pty pair (Bun/Ink raw-mode TTY
# requirement); these functions are the bats-side ergonomics layer.
#
# Refs: docs/internals/test-interactive.md.

__interactive_expect_dir="$(dirname "${BASH_SOURCE[0]}")/expect"

# claude_idle_for <seconds>: hold an interactive `claude` session for N
# seconds doing nothing, then close cleanly via Ctrl-D. Used to exercise
# CLI background loops (auto-updater, telemetry, MCP polling) that only
# fire when the process believes it's attached to a real terminal.
#
# Auth: `claude` reads ANTHROPIC_API_KEY from its environment when no
# stored credentials exist — no `/login` dance required. The
# `--preserve-env=ANTHROPIC_API_KEY` flag forwards the key across the
# sudo boundary; plain `-E` is silently dropped by Ubuntu's default
# sudoers (env_reset + restrictive env_keep).
claude_idle_for() {
  local seconds="${1-}"
  if [[ -z "${seconds}" ]] || ! [[ "${seconds}" =~ ^[0-9]+$ ]]; then
    echo "claude_idle_for: argv 1 must be a positive integer (got: '${seconds-}')" >&2
    return 2
  fi
  sudo --preserve-env=ANTHROPIC_API_KEY -u agent -H expect \
    "${__interactive_expect_dir}/claude-idle.exp" "${seconds}"
}
