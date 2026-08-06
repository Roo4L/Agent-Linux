#!/usr/bin/env bats
# tests/bats/74-catalog-brownfield-detection.bats — DET-04 generalized beyond the
# original three agents (v0.3.6 catalog expansion).
#
# The detect probe (rust/crates/agentlinux/src/detect.rs) derives its tool list from the
# catalog, so a manually-installed CLI catalog tool (no AgentLinux sentinel) is
# reported present instead of invisible. MCP entries (registration-based, no PATH
# binary) are excluded from the PATH probe. Runs on the post-installer Docker host
# via the read-only --report-only pass, so it mutates nothing but a scoped fixture.

load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux

# Brownfield fixture: a real catalog binary id (rtk) placed on the agent's login
# PATH with NO sentinel and NO AgentLinux install. rtk is not in the CI base, so
# detection of it is unambiguous. Emits a semver on --version so the generic
# version probe classifies it healthy.
FAKE_BIN=/home/agent/.local/bin/rtk

# The same fixture at the OTHER agent-owned bin dir. `~/.local/bin` is a poor
# regression guard on its own: EL9's stock ~/.bash_profile puts it on PATH
# independently of anything AgentLinux writes, so a probe whose login shell
# never ran /etc/profile.d/agentlinux.sh still finds it. `~/.npm-global/bin`
# has no such fallback and is therefore the honest test of whether the profile
# actually loaded. See the AGENTLINUX_PROFILE_SOURCED test below.
FAKE_NPM_BIN=/home/agent/.npm-global/bin/rtk

# Scoped sentinel store so the adopt/pin management tests don't pollute the real
# /opt/agentlinux/state — agent-owned (under $HOME), auto-created by writeSentinel,
# torn down per test. AGENTLINUX_STATE_DIR is the installed.d dir itself.
SCOPED_STATE=/home/agent/.al-brownfield-test/installed.d

# Run the CLI as the agent login user with the scoped sentinel store.
al_agent() {
  sudo -u agent -H bash --login -c "AGENTLINUX_STATE_DIR=$SCOPED_STATE agentlinux $*"
}

setup() {
  install -d -m 0755 -o agent -g agent /home/agent/.local/bin
  cat >"$FAKE_BIN" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && echo "rtk 0.42.4"
exit 0
SH
  chmod 0755 "$FAKE_BIN"
  chown agent:agent "$FAKE_BIN"
  rm -rf /home/agent/.al-brownfield-test 2>/dev/null || true
}

teardown() {
  rm -f "$FAKE_BIN" "$FAKE_NPM_BIN" 2>/dev/null || true
  rm -rf /home/agent/.al-brownfield-test 2>/dev/null || true
}

# AL-124 regression guard.
#
# /etc/profile.d/agentlinux.sh opens with a re-source guard:
#
#   [ -n "${AGENTLINUX_PROFILE_SOURCED:-}" ] && return
#
# and only AFTER that prepends ~/.npm-global/bin and ~/.local/bin. detect's
# probe forwarded every AGENTLINUX_* var into its login-shell child, so a
# provisioner running with the guard already in its own environment handed the
# probe a shell that returned before wiring PATH — and every tool installed at
# ~/.npm-global/bin reported `absent` on a host where it was plainly present.
#
# This went undiagnosed through two wrong hypotheses and four QEMU cycles
# because the only tests that caught it were the four REMEDIATE-04 brownfield
# E2E cases, and they caught it ONLY on almalinux-9 — on Ubuntu the probe's own
# PATH survives sudo, so the profile bailing costs nothing. That is an accident
# of distro, not a specification. This test pins the contract directly on every
# platform: the probe must see the agent's bin dirs no matter what the
# provisioner inherited.
@test "DET-04: an inherited profile re-source guard does not blind the probe (AL-124)" {
  # REQ: DET-04
  install -d -m 0755 -o agent -g agent /home/agent/.npm-global/bin
  cp "$FAKE_BIN" "$FAKE_NPM_BIN"
  chown agent:agent "$FAKE_NPM_BIN"
  # Remove the canonical copy so ~/.bash_profile's independent PATH entry
  # cannot mask a profile that never loaded — ~/.npm-global/bin is reachable
  # ONLY via /etc/profile.d/agentlinux.sh.
  rm -f "$FAKE_BIN"

  # `env` rather than a `VAR=1 run ...` prefix: `run` is a shell function, and a
  # prefix assignment on a function is not reliably exported to the process it
  # spawns. If the variable failed to reach the installer this test would pass
  # whether or not the bug was fixed — which is worse than no test.
  run env AGENTLINUX_PROFILE_SOURCED=1 "$INSTALLER" provision --report-only --report-format=json
  assert_exit_zero "DET-04/profile-guard"
  printf '%s' "$output" \
    | jq -e '(.components.agents // .agents) | map(select(.id == "rtk" and .status == "healthy")) | length == 1' >/dev/null \
    || __fail "DET-04/profile-guard" \
      "rtk at ~/.npm-global/bin is still detected when the provisioner inherits AGENTLINUX_PROFILE_SOURCED=1" \
      "$output" "$LOG"
}

@test "DET-04: a brownfield catalog CLI tool (rtk) is detected healthy with its version" {
  # REQ: DET-04
  run "$INSTALLER" provision --report-only --report-format=json
  assert_exit_zero "DET-04/brownfield-cli"
  printf '%s' "$output" \
    | jq -e '(.components.agents // .agents) | map(select(.id == "rtk" and .status == "healthy" and .version == "0.42.4")) | length == 1' >/dev/null \
    || __fail "DET-04/brownfield-cli" "rtk reported healthy at 0.42.4 in the agents probe" "$output" "$LOG"
}

@test "DET-04: MCP catalog entries are NOT PATH-probed (github-mcp absent from agents[])" {
  # REQ: DET-04 — MCP entries register into client configs; they have no binary to
  # resolve, so the PATH probe must skip them (detection of registration is a
  # separate concern).
  run "$INSTALLER" provision --report-only --report-format=json
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
  run "$INSTALLER" provision --report-only --report-format=json
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
  run "$INSTALLER" provision --report-only --report-format=json
  assert_exit_zero "DET-04/legacy-preserved"
  printf '%s' "$output" \
    | jq -e '(.components.agents // .agents) | map(.id) | (index("claude-code") and index("gsd") and index("playwright-cli"))' >/dev/null \
    || __fail "DET-04/legacy-preserved" "claude-code + gsd + playwright-cli present in agents[]" "$output" "$LOG"
}

@test "DET-04: agentlinux upgrade surfaces the brownfield tool as present (not not-installed)" {
  # REQ: DET-04 — `upgrade` must agree with `list`: a detected-but-unmanaged tool
  # reads 'present', never 'not-installed' (the reported inconsistency).
  run "$INSTALLER" provision --report-only --report-format=json
  assert_exit_zero "DET-04/upgrade-refresh"
  run al_agent upgrade
  assert_exit_zero "DET-04/upgrade-present"
  printf '%s' "$output" | grep -Eq 'rtk[[:space:]]+present' \
    || __fail "DET-04/upgrade-present" "rtk reads 'present' in agentlinux upgrade" "$output" "$LOG"
}

@test "DET-04: pin on a present brownfield tool directs to adopt, not install" {
  # REQ: DET-04 — pin must route a present-but-unmanaged tool to `adopt` (records
  # the existing bits), not `install` (a fresh copy over them).
  run "$INSTALLER" provision --report-only --report-format=json
  assert_exit_zero "DET-04/pin-refresh"
  run al_agent pin rtk=curated
  [ "$status" -eq 1 ] \
    || __fail "DET-04/pin-present" "pin on a present tool exits 1" "$output" "$LOG"
  printf '%s' "$output" | grep -Fq 'present but not managed' \
    || __fail "DET-04/pin-present" "pin message names the present-but-unmanaged state" "$output" "$LOG"
  printf '%s' "$output" | grep -Fq 'agentlinux adopt rtk' \
    || __fail "DET-04/pin-present" "pin directs the user to 'agentlinux adopt rtk'" "$output" "$LOG"
}

@test "DET-04: adopt brings the brownfield tool under management (list/pin then consistent)" {
  # REQ: DET-04 — the keystone: adopt a non-canonical catalog tool, then list
  # reads it managed (reused/synced) and pin succeeds. This closes the loop the
  # user hit — present in `list` but un-adoptable / un-pinnable.
  run "$INSTALLER" provision --report-only --report-format=json
  assert_exit_zero "DET-04/adopt-refresh"

  run al_agent adopt rtk
  assert_exit_zero "DET-04/adopt"
  printf '%s' "$output" | grep -Fq '[ADOPT] rtk' \
    || __fail "DET-04/adopt" "adopt records the brownfield rtk into a reused sentinel" "$output" "$LOG"

  # Now managed: list shows synced (0.42.4 == pin) with the reused suffix.
  run al_agent list
  assert_exit_zero "DET-04/list-after-adopt"
  printf '%s' "$output" | grep -Eq 'rtk[[:space:]]+synced' \
    || __fail "DET-04/list-after-adopt" "rtk reads 'synced' after adopt" "$output" "$LOG"
  printf '%s' "$output" | grep -Fq 'reused' \
    || __fail "DET-04/list-after-adopt" "rtk carries the reused (managed) suffix" "$output" "$LOG"

  # And pin now succeeds against the managed sentinel.
  run al_agent pin rtk=curated
  assert_exit_zero "DET-04/pin-after-adopt"
  printf '%s' "$output" | grep -Fq 'pin cleared' \
    || __fail "DET-04/pin-after-adopt" "pin succeeds once rtk is managed" "$output" "$LOG"
}

@test "DET-04: a present tool OUT of the compatibility window routes to install, not adopt (QA F-QA-02)" {
  # REQ: DET-04 — a brownfield tool at its managed path but outside the catalog's
  # compatibility_window is present-but-NOT-adoptable: adopt would refuse, so both
  # `list` and `pin` must point at `install` (reconcile at the pin), never `adopt`.
  # Re-plant rtk at 0.99.0 (window is >=0.42.0 <0.43.0) for this test only.
  cat >"$FAKE_BIN" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && echo "rtk 0.99.0"
exit 0
SH
  chmod 0755 "$FAKE_BIN"; chown agent:agent "$FAKE_BIN"

  run "$INSTALLER" provision --report-only --report-format=json
  assert_exit_zero "DET-04/oow-refresh"

  run al_agent list
  assert_exit_zero "DET-04/oow-list"
  printf '%s' "$output" | grep -Fq 'detected out-of-window — run: agentlinux install rtk to manage' \
    || __fail "DET-04/oow-list" "out-of-window rtk points at install-to-manage" "$output" "$LOG"
  printf '%s' "$output" | grep -Fq 'agentlinux adopt rtk' \
    && __fail "DET-04/oow-list" "out-of-window rtk must NOT recommend adopt (dead-end)" "$output" "$LOG"

  run al_agent adopt rtk
  assert_exit_zero "DET-04/oow-adopt"
  printf '%s' "$output" | grep -Fq 'nothing to adopt' \
    || __fail "DET-04/oow-adopt" "adopt declines an out-of-window tool" "$output" "$LOG"

  run al_agent pin rtk=curated
  [ "$status" -eq 1 ] \
    || __fail "DET-04/oow-pin" "pin on an out-of-window present tool exits 1" "$output" "$LOG"
  printf '%s' "$output" | grep -Fq 'out of the compatibility window' \
    || __fail "DET-04/oow-pin" "pin names the out-of-window state and points at install" "$output" "$LOG"
}
