#!/usr/bin/env bats
# tests/bats/54-catalog-npm-smoke.bats — OPS-01 operational smokes for the
# v0.3.6 npm cluster: each tool is run in a minimal REAL scenario as the agent
# user (not just install/version), proving it operates correctly under
# AgentLinux.
#
# OPS-01 contract (.planning/REQUIREMENTS.md):
#   - real but minimal op (one tiny prompt / one local op);
#   - auth supplied at RUNTIME via env only, never baked — the credential
#     reaches the agent shell through `sudo --preserve-env=<VAR>` so the secret
#     stays in the environment and never appears on a command line;
#   - SKIP cleanly when the required credential env var is absent, so
#     credential-free CI and contributors stay green;
#   - no-auth tools (ccusage) run unconditionally on seeded local data.
#
# Run with credentials via tests/docker/run-smoke.sh (forwards the provider
# vars to the in-container bats process). Absent a credential, the matching
# @test skips — the file is safe in credential-free CI.
#
# Provider routing (Appendix C): codex→OpenAI (required; OpenAI-only),
# gemini-cli→Gemini (free), opencode→Anthropic, qwen-code→Anthropic
# (OpenAI-compatible/native also supported), ccusage→none.
#
# The probe prompt is a trivia question whose one-word answer ("Paris") does
# NOT appear in the prompt text — so a tool that merely echoes the user turn
# into its transcript cannot satisfy the assertion; only a real model reply
# containing the answer passes.

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log

PROMPT='What is the capital of France? Reply with the single word only, lowercase.'
EXPECT='paris'

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  sudo -u agent -H bash --login -c '
    rm -rf ~/.codex ~/.gemini ~/.qwen ~/.config/opencode ~/.local/share/opencode 2>/dev/null
  ' >/dev/null 2>&1 || true
}

teardown_file() {
  # Symmetric cleanup: remove the tools AND scrub per-tool user state so no
  # provider auth material (e.g. ~/.codex/auth.json written by `codex login`)
  # is left on disk and no state leaks into downstream test files.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    local id
    for id in codex gemini-cli opencode qwen-code ccusage; do
      sudo -u agent -H bash --login -c "agentlinux remove --force ${id}" >/dev/null 2>&1 || true
    done
  fi
  sudo -u agent -H bash --login -c '
    rm -rf ~/.codex ~/.gemini ~/.qwen ~/.config/opencode ~/.local/share/opencode 2>/dev/null
  ' >/dev/null 2>&1 || true
}

_install() { sudo -u agent -H bash --login -c "agentlinux install ${1}"; }
_remove() { sudo -u agent -H bash --login -c "agentlinux remove --force ${1}" >/dev/null 2>&1 || true; }

# _redact <string> — strip any provided key values before a string lands in a
# CI log (defense-in-depth: the tested CLIs don't echo keys, but a misbehaving
# one could). Never prints the keys themselves.
_redact() {
  local s=$1 k
  for k in "${OPENAI_API_KEY:-}" "${GEMINI_API_KEY:-}" "${ANTHROPIC_API_KEY:-}" "${DASHSCOPE_API_KEY:-}"; do
    [[ -n "$k" ]] && s=${s//"$k"/<redacted>}
  done
  printf '%s' "$s"
}

# _skip_if_unavailable <label> — when ${output} shows the request reached the
# provider but the model was TRANSIENTLY unavailable (503/overload) or
# rate-limited (429), skip with a clear reason instead of red-failing. This
# proves the tool is wired correctly (authenticated + reached the API) while
# keeping the smoke non-flaky against upstream weather. A genuine wiring error
# (401, bad key, unknown model) matches none of these and still red-fails.
_skip_if_unavailable() {
  if printf '%s' "${output}" \
    | grep -qiE '503|UNAVAILABLE|overloaded|high demand|service unavailable|429|too many requests|rate limit'; then
    skip "${1}: tool wired OK (request authenticated + reached the provider) but the model was transiently unavailable (overload/rate-limit) — retry later"
  fi
}

@test "OPS-01: gemini-cli answers a real prompt (skips without GEMINI_API_KEY)" {
  [[ -n "${GEMINI_API_KEY:-}" ]] || skip "GEMINI_API_KEY not set"
  _install gemini-cli
  run sudo --preserve-env=GEMINI_API_KEY -u agent -H bash --login -c \
    "cd /tmp && gemini --skip-trust -m gemini-2.5-flash -p '${PROMPT}'"
  _remove gemini-cli
  _skip_if_unavailable "OPS-01/gemini-cli"
  assert_exit_zero "OPS-01/gemini-cli"
  printf '%s' "${output}" | grep -qi "${EXPECT}" \
    || __fail "OPS-01/gemini-cli" "model reply contains '${EXPECT}'" "$(_redact "${output:-<empty>}")" "$LOG"
}

@test "OPS-01: opencode answers a real prompt (skips without ANTHROPIC_API_KEY)" {
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] || skip "ANTHROPIC_API_KEY not set"
  _install opencode
  run sudo --preserve-env=ANTHROPIC_API_KEY -u agent -H bash --login -c \
    "cd /tmp && opencode run -m anthropic/claude-haiku-4-5 '${PROMPT}'"
  _remove opencode
  _skip_if_unavailable "OPS-01/opencode"
  assert_exit_zero "OPS-01/opencode"
  printf '%s' "${output}" | grep -qi "${EXPECT}" \
    || __fail "OPS-01/opencode" "model reply contains '${EXPECT}'" "$(_redact "${output:-<empty>}")" "$LOG"
}

@test "OPS-01: qwen-code answers a real prompt (skips without ANTHROPIC_API_KEY)" {
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] || skip "ANTHROPIC_API_KEY not set"
  _install qwen-code
  # ANTHROPIC_BASE_URL + workspace-trust are non-secret, set inline; only the
  # API key is preserved through sudo's env reset.
  run sudo --preserve-env=ANTHROPIC_API_KEY -u agent -H bash --login -c \
    "cd /tmp && GEMINI_CLI_TRUST_WORKSPACE=true ANTHROPIC_BASE_URL='https://api.anthropic.com' qwen --auth-type anthropic -m claude-haiku-4-5-20251001 '${PROMPT}'"
  _remove qwen-code
  _skip_if_unavailable "OPS-01/qwen-code"
  assert_exit_zero "OPS-01/qwen-code"
  printf '%s' "${output}" | grep -qi "${EXPECT}" \
    || __fail "OPS-01/qwen-code" "model reply contains '${EXPECT}'" "$(_redact "${output:-<empty>}")" "$LOG"
}

@test "OPS-01: codex answers a real prompt (skips without OPENAI_API_KEY / unfunded key)" {
  [[ -n "${OPENAI_API_KEY:-}" ]] || skip "OPENAI_API_KEY not set"
  _install codex
  # codex authenticates from an API key written via `login --with-api-key`
  # (read from stdin — never on argv). The pipe keeps the secret out of args;
  # output suppressed so no "logged in" banner can echo the key.
  sudo --preserve-env=OPENAI_API_KEY -u agent -H bash --login -c \
    'printf %s "$OPENAI_API_KEY" | codex login --with-api-key' >/dev/null 2>&1
  run sudo --preserve-env=OPENAI_API_KEY -u agent -H bash --login -c \
    "cd /tmp && codex exec -m gpt-4o-mini --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox '${PROMPT}'"
  _remove codex
  # Distinguish a wiring failure from an unfunded account: if the request
  # reached OpenAI and was rejected for quota/billing, the integration is
  # proven (auth OK) — skip with a clear reason rather than red-failing.
  if printf '%s' "${output}" | grep -qiE 'quota exceeded|insufficient_quota|billing|exceeded your current quota'; then
    skip "codex wired OK (login succeeded, request authenticated) but OPENAI_API_KEY has no API quota — enable billing on the OpenAI account to complete this smoke"
  fi
  _skip_if_unavailable "OPS-01/codex"
  assert_exit_zero "OPS-01/codex"
  printf '%s' "${output}" | grep -qi "${EXPECT}" \
    || __fail "OPS-01/codex" "model reply contains '${EXPECT}' (exit 0)" "$(_redact "${output:-<empty>}")" "$LOG"
}

@test "OPS-01: ccusage parses a seeded usage log and reports cost (no credential)" {
  _install ccusage
  run sudo -u agent -H bash --login -c '
    d=$(mktemp -d)
    mkdir -p "$d/projects/smoke"
    cat > "$d/projects/smoke/session.jsonl" <<JSONL
{"timestamp":"2026-06-01T10:00:00.000Z","sessionId":"smoke","requestId":"r1","message":{"id":"m1","model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":1000,"output_tokens":500}}}
{"timestamp":"2026-06-01T10:05:00.000Z","sessionId":"smoke","requestId":"r2","message":{"id":"m2","model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":2000,"output_tokens":800}}}
JSONL
    CLAUDE_CONFIG_DIR="$d" ccusage daily --json
    rc=$?
    rm -rf "$d"
    exit $rc
  '
  _remove ccusage
  assert_exit_zero "OPS-01/ccusage"
  # Assert the summed token total (1000+2000) without coupling to JSON spacing.
  printf '%s' "${output}" | grep -Eq '"inputTokens":[[:space:]]*3000' \
    || __fail "OPS-01/ccusage" "ccusage daily --json totals the seeded 3000 input tokens" "${output:-<empty>}" "$LOG"
}
