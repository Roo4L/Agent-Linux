#!/usr/bin/env bats
# tests/bats/22-agent-sudo.bats — INST-06 + BHV-07 per ADR-012.
#
# Every @test name starts with the requirement ID (INST-XX: / BHV-XX:) so
# behavior-coverage-auditor's TST-07 gate greps pass. Phase 5.1 ships
# exactly one provisioner (20-sudoers.sh) plus this suite; closing this
# plan closes Phase 5.1 as a whole.
#
# Preconditions (set up by tests/docker/run.sh before bats runs):
#   - agentlinux-install has already been invoked once, so
#     /etc/sudoers.d/agentlinux exists with mode 0440 root:root.
#   - Installer sources are staged at /opt/agentlinux-src/ so the
#     idempotency @test can re-run the installer from inside a bats test
#     (same path convention as tests/bats/10-installer.bats INST-02).
#
# Slot numbering: 22 signals "agent-user-related, between 20-agent-user.bats
# and 30-runtime.bats" per the 05.1-CONTEXT.md plan direction.

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
SUDOERS_FILE=/etc/sudoers.d/agentlinux
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

# --- BHV-07: file integrity --------------------------------------------------

@test "BHV-07: /etc/sudoers.d/agentlinux exists" {
  [[ -f "$SUDOERS_FILE" ]] \
    || __fail "BHV-07" "$SUDOERS_FILE exists" "not found" "$LOG"
}

@test "BHV-07: /etc/sudoers.d/agentlinux has mode 0440 and owner root:root" {
  # `stat -c '%a %U:%G'` prints the octal mode + owner:group on one line.
  # Mode is 440 (not 0440) in %a — the leading zero is implicit. Any other
  # mode (e.g. 640 or 644) means install(1) didn't set -m correctly OR
  # something chmod-drifted the file out-of-band; either way BHV-07 fails.
  run stat -c '%a %U:%G' "$SUDOERS_FILE"
  assert_exit_zero "BHV-07"
  [[ "$output" == "440 root:root" ]] \
    || __fail "BHV-07" \
      "stat output '440 root:root'" \
      "$output" \
      "$LOG"
}

@test "BHV-07: /etc/sudoers.d/agentlinux contains exact NOPASSWD policy line" {
  # grep -Fx: fixed-string, whole-line match. `agent ALL=(ALL) NOPASSWD: ALL`
  # is the ADR-012 policy verbatim — ANY drift (extra whitespace, different
  # host spec, missing NOPASSWD tag) flips this red.
  run grep -Fx 'agent ALL=(ALL) NOPASSWD: ALL' "$SUDOERS_FILE"
  assert_exit_zero "BHV-07"
}

@test "BHV-07: /etc/sudoers.d/agentlinux passes visudo -cf validation" {
  # visudo -cf is the authoritative syntax checker. T-05.1-01 post-condition:
  # if the installer shipped a syntax-invalid file somehow, visudo -cf catches
  # it here. Stderr merged into $output so failure diagnostics are visible.
  run visudo -cf "$SUDOERS_FILE"
  assert_exit_zero "BHV-07"
}

# --- INST-06: agent user has passwordless sudo -------------------------------

@test "INST-06: agent user can run 'sudo -n true' without prompt or error" {
  # `sudo -n true` is the canonical INST-06 probe: -n disables any
  # password/PAM prompt, so the command exits 0 iff the sudoers policy grants
  # passwordless access. Routed through run_sudo_u so we exercise the real
  # `sudo -u agent -H bash --login -c` invocation path BHV-05 uses — exit 0
  # there means an actual agent-user sudo call resolved against the drop-in.
  run_sudo_u 'sudo -n true'
  assert_exit_zero "INST-06"
}

@test "INST-06: agent user's sudo -l lists NOPASSWD for ALL commands" {
  # `sudo -l` prints the effective policy for the invoking user. Even though
  # mode 0440 prevents the agent from reading /etc/sudoers.d/agentlinux
  # directly (T-05.1-03), sudo -l surfaces the effective grant. Grep for the
  # canonical "(ALL) NOPASSWD: ALL" token — matches both Ubuntu 22.04's
  # policy-line format and 24.04's (both emit "(ALL) NOPASSWD: ALL" verbatim
  # as part of the User agent may run the following commands block).
  run_sudo_u 'sudo -n -l'
  assert_exit_zero "INST-06"
  [[ "$output" == *"(ALL) NOPASSWD: ALL"* ]] \
    || __fail "INST-06" \
      "sudo -l output contains '(ALL) NOPASSWD: ALL'" \
      "$output" \
      "$LOG"
}

# --- BHV-07: byte-stability on re-run (idempotency, T-05.1-04) --------------

@test "BHV-07: sudoers drop-in is sha256 byte-stable across installer re-run" {
  # T-05.1-04 mitigation: re-running agentlinux-install MUST produce a
  # byte-identical /etc/sudoers.d/agentlinux (otherwise a future installer
  # drift could double-append a second NOPASSWD line, break visudo -cf, or
  # silently rotate the policy). Snapshot the sha256 before + after a re-run
  # and compare.
  #
  # This is distinct from 10-installer.bats INST-02's file-set idempotency:
  # INST-02 covers the Phase 2/3/4 artefacts; this @test extends the contract
  # to the Phase 5.1 drop-in. Keeping it local to 22-agent-sudo.bats keeps
  # INST-02 focused (per the bats slot-numbering convention) and lets Phase
  # 5.1 close without editing 10-installer.bats.
  local pre post
  pre=$(sha256sum "$SUDOERS_FILE" | cut -d' ' -f1)
  [[ -n "$pre" ]] || __fail "BHV-07" \
    "sha256sum returned non-empty hash for pre-snapshot" \
    "empty" "$LOG"

  run bash "$INSTALLER"
  assert_exit_zero "BHV-07"

  post=$(sha256sum "$SUDOERS_FILE" | cut -d' ' -f1)
  [[ "$pre" == "$post" ]] \
    || __fail "BHV-07" \
      "sha256 byte-stable across re-run" \
      "before=${pre} after=${post}" \
      "$LOG"
}
