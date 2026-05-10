#!/usr/bin/env bats
# tests/bats/15-detection.bats — DET-01..06 + read-only invariant + Phase 13 contract.
#
# Slot 15: before installer-foundation (20-*) so detection probes the host
# state agentlinux-install will (in non-report-only mode) create. The harness
# at tests/docker/run.sh runs `agentlinux-install` BEFORE bats, so by the time
# DET-* @tests fire, /etc/sudoers.d/agentlinux exists and the agent user is
# present — making the "present" branch of every DET-* the default observation.
#
# Plan 12-01 ships DET-01:, DET-05:, DET-06: @tests (this file).
# Plan 12-02 appends DET-02:, DET-03:, DET-04: @tests.
# Plan 12-03 appends "DET read-only:" and "DET-contract:" @tests.

load 'helpers/assertions'
load 'helpers/detection'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

@test "DET-01: --report-only --report-format=json reports install user UID + shell + home_writable" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-01"
  printf '%s' "$output" | jq -e '.user.present == true and (.user.uid | tonumber) > 0 and .user.home_writable == true' >/dev/null \
    || __fail "DET-01" "user.present + parsable uid + home_writable" "$output" "$LOG"
}

@test "DET-01: text format includes [DET-01] markers for user.uid + user.shell + user.home" {
  run bash "$INSTALLER" --report-only
  assert_exit_zero "DET-01"
  for marker_field in user.uid user.shell user.home user.home_writable; do
    printf '%s' "$output" | grep -qE "^\[DET-01\] ${marker_field}=" \
      || __fail "DET-01" "[DET-01] ${marker_field}= line in text output" "$output" "$LOG"
  done
}

@test "DET-05: sudoers drop-in metadata captured (path + present + sha256 + nopasswd_line_present)" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-05"
  printf '%s' "$output" | jq -e '.sudoers.path == "/etc/sudoers.d/agentlinux" and (.sudoers.present == true or .sudoers.present == false)' >/dev/null \
    || __fail "DET-05" "sudoers.path + boolean .present" "$output" "$LOG"
  # When present, sha256 must be a 64-char hex string and nopasswd_line_present a bool.
  printf '%s' "$output" | jq -e 'if .sudoers.present then (.sudoers.sha256 | test("^[0-9a-f]{64}$")) and ((.sudoers.nopasswd_line_present == true) or (.sudoers.nopasswd_line_present == false)) else true end' >/dev/null \
    || __fail "DET-05" "sha256 is 64-hex when present + nopasswd_line_present is bool" "$output" "$LOG"
}

@test "DET-05: sudoers file SHA256 unchanged across detection pass (read-only invariant on sudoers)" {
  # Defense-in-depth: even before Plan 12-03's full-snapshot @test, prove the one file
  # detection cares about is byte-identical before and after a --report-only run.
  [[ -f /etc/sudoers.d/agentlinux ]] || skip "sudoers drop-in not present in this fixture (expected only after install ran)"
  local pre post
  pre=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-05"
  post=$(sha256sum /etc/sudoers.d/agentlinux | cut -d' ' -f1)
  [[ "$pre" == "$post" ]] \
    || __fail "DET-05" "sudoers SHA256 byte-stable across detection" "before=${pre} after=${post}" "$LOG"
}

@test "DET-06: --report-format=json emits valid JSON parseable by jq (object at top level)" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-06"
  printf '%s' "$output" | jq -e 'type == "object"' >/dev/null \
    || __fail "DET-06" "valid JSON object at top level" "$output" "$LOG"
}

@test "DET-06: text format contains [DET-NN] markers for grep stability (DET-01 + DET-05 wired in this plan)" {
  run bash "$INSTALLER" --report-only
  assert_exit_zero "DET-06"
  # Plans 12-02/12-03 expand the marker set to include DET-02..04 and the section headers;
  # this plan only wires DET-01 + DET-05 detectors, so only those markers must be present here.
  for marker in DET-01 DET-05; do
    printf '%s' "$output" | grep -qE "\[$marker\]" \
      || __fail "DET-06" "[$marker] marker present in text output" "$output" "$LOG"
  done
}

@test "DET-06: --report-only exits 0 and skips run_provisioners (no /opt/agentlinux/cli/<v>/dist edits during report)" {
  # Negative-side check: --report-only must NOT fall through to run_provisioners.
  # After a --report-only call, /var/log/agentlinux-install.log MUST NOT contain
  # any "running 30-nodejs.sh" / "running 50-registry-cli.sh" line emitted in this run.
  # We snapshot the log size before and after; the new tail must lack provisioner-dispatch markers.
  local before_size
  before_size=$(stat -c '%s' "$LOG" 2>/dev/null || echo 0)
  run bash "$INSTALLER" --report-only --report-format=text
  assert_exit_zero "DET-06"
  local after_tail
  after_tail=$(tail -c "+$((before_size + 1))" "$LOG" 2>/dev/null || echo "")
  printf '%s' "$after_tail" | grep -qE 'running [0-9]{2}-[a-z-]+\.sh' \
    && __fail "DET-06" "no provisioner dispatch markers in --report-only tail" "$after_tail" "$LOG"
  true
}
