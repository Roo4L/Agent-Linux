#!/usr/bin/env bats
# tests/bats/74-catalog-brownfield-detection.bats — DET-04 generalized beyond the
# original three agents (v0.3.6 catalog expansion).
#
# The detect probe (plugin/lib/detect/agents.sh) derives its tool list from the
# catalog, so a manually-installed CLI catalog tool (no AgentLinux sentinel) is
# reported present instead of invisible. MCP entries (registration-based, no PATH
# binary) are excluded from the PATH probe. Runs on the post-installer Docker host
# via the read-only --report-only pass, so it mutates nothing but a scoped fixture.

load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

# Brownfield fixture: a real catalog binary id (rtk) placed on the agent's login
# PATH with NO sentinel and NO AgentLinux install. rtk is not in the CI base, so
# detection of it is unambiguous. Emits a semver on --version so the generic
# version probe classifies it healthy.
FAKE_BIN=/home/agent/.local/bin/rtk

setup() {
  install -d -m 0755 -o agent -g agent /home/agent/.local/bin
  cat >"$FAKE_BIN" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && echo "rtk 0.42.4"
exit 0
SH
  chmod 0755 "$FAKE_BIN"
  chown agent:agent "$FAKE_BIN"
}

teardown() {
  rm -f "$FAKE_BIN" 2>/dev/null || true
}

@test "DET-04: a brownfield catalog CLI tool (rtk) is detected healthy with its version" {
  # REQ: DET-04
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04/brownfield-cli"
  printf '%s' "$output" \
    | jq -e '(.components.agents // .agents) | map(select(.id == "rtk" and .status == "healthy" and .version == "0.42.4")) | length == 1' >/dev/null \
    || __fail "DET-04/brownfield-cli" "rtk reported healthy at 0.42.4 in the agents probe" "$output" "$LOG"
}

@test "DET-04: MCP catalog entries are NOT PATH-probed (github-mcp absent from agents[])" {
  # REQ: DET-04 — MCP entries register into client configs; they have no binary to
  # resolve, so the PATH probe must skip them (detection of registration is a
  # separate concern).
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04/mcp-excluded"
  printf '%s' "$output" \
    | jq -e '(.components.agents // .agents) | map(select(.id == "github-mcp")) | length == 0' >/dev/null \
    || __fail "DET-04/mcp-excluded" "github-mcp (mcp source_kind) excluded from the PATH agents probe" "$output" "$LOG"
}

@test "DET-04: agentlinux list surfaces the brownfield tool as present (end-to-end)" {
  # REQ: DET-04 — the user-facing complaint. --report-only refreshes the detect
  # cache at /run/agentlinux-detect.json; `agentlinux list` reads that same cache
  # and its presence overlay must render the brownfield rtk as "present" with the
  # adopt hint (it sits at the managed ~/.local/bin), not "not-installed".
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04/list-refresh"
  run sudo -u agent -H bash --login -c 'agentlinux list 2>&1'
  assert_exit_zero "DET-04/list-e2e"
  printf '%s' "$output" | grep -Eq 'rtk[[:space:]]+present' \
    || __fail "DET-04/list-e2e" "rtk row reads 'present' in agentlinux list" "$output" "$LOG"
  printf '%s' "$output" | grep -Fq 'to manage' \
    || __fail "DET-04/list-e2e" "brownfield rtk at the managed path shows the adopt hint" "$output" "$LOG"
}

@test "DET-04: the original three agents still appear in the probe (no regression)" {
  # REQ: DET-04 — generalization must not drop the original hardcoded set.
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04/legacy-preserved"
  printf '%s' "$output" \
    | jq -e '(.components.agents // .agents) | map(.id) | (index("claude-code") and index("gsd") and index("playwright-cli"))' >/dev/null \
    || __fail "DET-04/legacy-preserved" "claude-code + gsd + playwright-cli present in agents[]" "$output" "$LOG"
}
