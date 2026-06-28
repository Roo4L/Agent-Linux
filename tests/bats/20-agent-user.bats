#!/usr/bin/env bats
# tests/bats/20-agent-user.bats — BHV-01..BHV-06.
#
# Every @test name starts with the requirement ID (BHV-XX:) so
# behavior-coverage-auditor's TST-07 gate greps pass.
#
# Preconditions (set up by tests/docker/run.sh before bats runs):
#   - agentlinux-install has already been invoked once. Agent user, PATH
#     wiring artefacts, DOC-02 CLAUDE.md, and the system locale file (at the
#     family-correct path, dispatched by distro_locale_file) are all in place.
#   - Installer sources staged at /opt/agentlinux-src (used only by
#     10-installer.bats's INST-02 re-run test).
#
# setup() generates a per-container SSH keypair lazily on first call and
# starts sshd. The keypair never lives on the host and never reaches the
# repo — it is an ephemeral artifact of the test container (threat T-02-15
# in the plan's STRIDE register).

load 'helpers/invoke_modes'
load 'helpers/assertions'
load 'helpers/distro'

LOG=/var/log/agentlinux-install.log

setup() {
  # Generate root SSH keypair + authorize it for the agent user the first
  # time a test runs. Subsequent tests re-enter setup() but short-circuit
  # on the keypair-present check.
  if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    install -d -m 0700 -o root -g root /root/.ssh
    ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519 -q
    install -d -m 0700 -o agent -g agent /home/agent/.ssh
    install -m 0600 -o agent -g agent \
      /root/.ssh/id_ed25519.pub /home/agent/.ssh/authorized_keys
    # Best-effort sshd start. On a systemd container this brings the family
    # ssh unit (sshd on EL9, ssh on Debian) up; on a non-systemd container it
    # silently fails — individual BHV-02 tests will then observe ssh connection
    # errors and diagnose.
    systemctl start "$(distro_ssh_unit)" >/dev/null 2>&1 || true
    # Wait up to 5s for sshd to accept connections.
    for _ in $(seq 1 5); do
      if ss -lnt 2>/dev/null | grep -q ':22 '; then break; fi
      sleep 1
    done
  fi
}

# --- BHV-01 ------------------------------------------------------------------
# agent user identity: bash shell, /home/agent home, C.UTF-8 locale.

@test "BHV-01: agent user exists with bash shell and /home/agent home" {
  run getent passwd agent
  assert_exit_zero "BHV-01"
  [[ "$output" == *":/home/agent:/bin/bash" ]] \
    || __fail "BHV-01" \
      "passwd entry ends ':/home/agent:/bin/bash'" \
      "$output" \
      "$LOG"
}

@test "BHV-01: system locale file has LANG=C.UTF-8" {
  # Same observable at the family-correct path (distro_assert_locale dispatches
  # via distro_locale_file). Never skipped, never weakened to a locale-a-only
  # check — the locked decision forbids weakening.
  run distro_assert_locale LANG
  assert_exit_zero "BHV-01"
}

@test "BHV-01: system locale file has LC_ALL=C.UTF-8" {
  run distro_assert_locale LC_ALL
  assert_exit_zero "BHV-01"
}

@test "BHV-01: C.UTF-8 is available in locale -a" {
  # Accept both canonical (C.UTF-8) and Ubuntu's reported form (C.utf8).
  run bash -c "locale -a 2>/dev/null | grep -Eiq '^c\\.utf-?8$'"
  assert_exit_zero "BHV-01"
}

# --- BHV-02: non-interactive SSH --------------------------------------------

@test "BHV-02: non-interactive SSH sees /home/agent/.local/bin on PATH" {
  run_ssh 'echo "$PATH"'
  assert_exit_zero "BHV-02"
  assert_path_has "BHV-02" "/home/agent/.local/bin"
}

@test "BHV-02: non-interactive SSH sees C.UTF-8 locale" {
  run_ssh 'printf "%s" "$LANG"'
  assert_exit_zero "BHV-02"
  [[ "$output" == *"C.UTF-8"* ]] \
    || __fail "BHV-02" "LANG=C.UTF-8 over SSH" "$output" "$LOG"
}

# --- BHV-03: cron -----------------------------------------------------------

@test "BHV-03: cron job for agent user sees /home/agent/.local/bin on PATH" {
  # run_cron writes a per-test /etc/cron.d/agentlinux-test-<stamp> entry
  # with its own PATH header + the command, waits up to 70s, and captures
  # the output file into $output.
  run_cron 'echo "$PATH"'
  # run_cron populates $output via `run cat -- $out`; exit 1 here means cron
  # never ran (no output file). Fail loudly in that case.
  if [[ "${status:-1}" -ne 0 ]]; then
    __fail "BHV-03" \
      "cron job produced output within 70s" \
      "no output file; cron may not be running" \
      "$LOG"
  fi
  assert_path_has "BHV-03" "/home/agent/.local/bin"
}

# --- BHV-04: systemd User=agent ---------------------------------------------

@test "BHV-04: systemd User=agent transient unit sees /home/agent/.local/bin on PATH" {
  run_systemd_user 'echo "$PATH"'
  if [[ "${output:-}" == *"SKIP_SYSTEMD_UNAVAILABLE"* ]]; then
    skip "BHV-04: systemd PID 1 not running in this container (tag @qemu-only if CI-persistent)"
  fi
  assert_exit_zero "BHV-04"
  assert_path_has "BHV-04" "/home/agent/.local/bin"
}

@test "BHV-04: systemd User=agent transient unit sees C.UTF-8 locale" {
  run_systemd_user 'printf "%s" "$LANG"'
  if [[ "${output:-}" == *"SKIP_SYSTEMD_UNAVAILABLE"* ]]; then
    skip "BHV-04: systemd PID 1 not running in this container (tag @qemu-only if CI-persistent)"
  fi
  assert_exit_zero "BHV-04"
  [[ "$output" == *"C.UTF-8"* ]] \
    || __fail "BHV-04" "LANG=C.UTF-8 under systemd User=agent" "$output" "$LOG"
}

# --- BHV-05: sudo -u agent (both -i login and non-login) --------------------

@test "BHV-05: sudo -u agent (non-login) sees /home/agent/.local/bin on PATH" {
  run_sudo_u 'echo "$PATH"'
  assert_exit_zero "BHV-05"
  assert_path_has "BHV-05" "/home/agent/.local/bin"
}

@test "BHV-05: sudo -u agent -i (login) sees /home/agent/.local/bin on PATH" {
  run_sudo_u_i 'echo "$PATH"'
  assert_exit_zero "BHV-05"
  assert_path_has "BHV-05" "/home/agent/.local/bin"
}

@test "BHV-05: sudo -u agent -i sees C.UTF-8 locale" {
  run_sudo_u_i 'printf "%s" "$LANG"'
  assert_exit_zero "BHV-05"
  [[ "$output" == *"C.UTF-8"* ]] \
    || __fail "BHV-05" "LANG=C.UTF-8 under sudo -u agent -i" "$output" "$LOG"
}

# --- BHV-06: interactive bash login -----------------------------------------

@test "BHV-06: interactive bash login sees /home/agent/.local/bin on PATH" {
  run_interactive 'echo "$PATH"'
  assert_exit_zero "BHV-06"
  assert_path_has "BHV-06" "/home/agent/.local/bin"
}

@test "BHV-06: interactive bash login sees C.UTF-8 locale" {
  run_interactive 'printf "%s" "$LANG"'
  assert_exit_zero "BHV-06"
  [[ "$output" == *"C.UTF-8"* ]] \
    || __fail "BHV-06" "LANG=C.UTF-8 under su - agent" "$output" "$LOG"
}
