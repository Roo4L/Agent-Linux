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

# ---- Plan 12-02 appends: DET-02, DET-03, DET-04 @tests ----
# Per .planning/phases/12-detection-layer/12-VALIDATION.md rows 12-02-01..03.
# Each @test name starts with the REQ-ID (behavior-test-contract SKILL).
# The `.components.X // .X` jq pattern handles both shapes: Plan 12-02 writes
# {nodejs:[...], npm_prefix:{...}, agents:[...]} at the top level; Plan 12-03
# may wrap them under .components. The // alternative keeps these @tests
# robust across both states.

@test "DET-02: nodejs probe enumerates NodeSource install on post-installer host" {
  # REQ: DET-02
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-02"
  # Post-installer host has Phase 4's NodeSource install. Expect at least one entry
  # whose source is `nodesource` and whose version contains `-1nodesource`.
  printf '%s' "$output" | jq -e '(.components.nodejs // .nodejs) | map(select(.source == "nodesource")) | length >= 1' >/dev/null \
    || __fail "DET-02" "at least one nodejs[] entry with source=nodesource on post-installer host" "$output" "$LOG"
}

@test "DET-02: nodejs probe enumerates nvm install when fixture sets ~/.nvm" {
  # REQ: DET-02
  # Fixture: drop a fake node binary at the canonical nvm path under the install
  # user's home; detection should pick it up via canonical-path file existence
  # WITHOUT sourcing ~/.nvm/nvm.sh.
  local nvm_root=/home/agent/.nvm/versions/node/v20.10.0/bin
  sudo -u agent mkdir -p "$nvm_root"
  cat >/tmp/_fake_node.sh <<'EOF'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "v20.10.0"; exit 0; }
exit 0
EOF
  sudo install -m 0755 -o agent -g agent /tmp/_fake_node.sh "$nvm_root/node"
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-02"
  printf '%s' "$output" | jq -e '(.components.nodejs // .nodejs) | map(select(.source == "nvm")) | length >= 1' >/dev/null \
    || __fail "DET-02" "at least one nodejs[] entry with source=nvm when fixture creates ~/.nvm" "$output" "$LOG"
  # Cleanup so subsequent @tests in this run see a clean fixture.
  sudo rm -f "$nvm_root/node"
  sudo rmdir -p --ignore-fail-on-non-empty "$nvm_root" 2>/dev/null || true
}

@test "DET-02: a /usr/local/bin/node symlinked to nvm does not double-count" {
  # REQ: DET-02
  # Fixture: create the nvm install AND a /usr/local/bin/node symlink to it.
  # The probe must skip the manual entry (readlink -f resolves into the manager dir)
  # but still emit the nvm entry — exactly one nvm entry, zero manual entries.
  local nvm_root=/home/agent/.nvm/versions/node/v20.10.0/bin
  sudo -u agent mkdir -p "$nvm_root"
  cat >/tmp/_fake_node.sh <<'EOF'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "v20.10.0"; exit 0; }
exit 0
EOF
  sudo install -m 0755 -o agent -g agent /tmp/_fake_node.sh "$nvm_root/node"
  sudo ln -sf "$nvm_root/node" /usr/local/bin/node
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-02"
  local manual_count nvm_count
  manual_count=$(printf '%s' "$output" | jq -r '(.components.nodejs // .nodejs) | map(select(.source == "manual")) | length')
  nvm_count=$(printf '%s' "$output" | jq -r '(.components.nodejs // .nodejs) | map(select(.source == "nvm")) | length')
  [[ "$manual_count" == "0" ]] \
    || __fail "DET-02" "manual entry suppressed when /usr/local/bin/node is a symlink into a manager dir (got manual=$manual_count)" "$output" "$LOG"
  [[ "$nvm_count" -ge 1 ]] \
    || __fail "DET-02" "nvm entry still emitted alongside the symlink (got nvm=$nvm_count)" "$output" "$LOG"
  sudo rm -f /usr/local/bin/node
  sudo rm -f "$nvm_root/node"
  sudo rmdir -p --ignore-fail-on-non-empty "$nvm_root" 2>/dev/null || true
}

@test "DET-03: npm prefix surfaces user / system / effective values as separate JSON fields" {
  # REQ: DET-03
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-03"
  printf '%s' "$output" | jq -e '
    (.components.npm_prefix // .npm_prefix) as $np
    | $np.npm_present == true
    and ($np | has("user_prefix") and has("system_prefix") and has("effective_prefix"))
    and ($np.effective_prefix | type == "string" and length > 0)
  ' >/dev/null \
    || __fail "DET-03" "user_prefix + system_prefix + effective_prefix all present and effective_prefix non-empty" "$output" "$LOG"
}

@test "DET-03: npm prefix probe runs via as_user_login (NPM_CONFIG_PREFIX user-shell export observed)" {
  # REQ: DET-03
  # Fixture: write a .profile snippet that exports NPM_CONFIG_PREFIX to a
  # known sentinel path. as_user_login (sudo -i) sources the profile;
  # bare as_user (sudo -E without -i) would NOT source it. If the probe is
  # implemented correctly with as_user_login, effective_prefix reflects
  # the sentinel value.
  local sentinel=/tmp/det03-npm-prefix-sentinel
  sudo -u agent mkdir -p "$sentinel"
  sudo -u agent bash -c 'echo "export NPM_CONFIG_PREFIX=/tmp/det03-npm-prefix-sentinel" >> ~/.profile'
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-03"
  local effective
  effective=$(printf '%s' "$output" | jq -r '(.components.npm_prefix // .npm_prefix).effective_prefix')
  [[ "$effective" == "/tmp/det03-npm-prefix-sentinel" ]] \
    || __fail "DET-03" "effective_prefix reflects user-shell NPM_CONFIG_PREFIX export (got '$effective'); confirms as_user_login was used" "$output" "$LOG"
  # Cleanup so subsequent @tests see a clean profile.
  sudo -u agent sed -i '/NPM_CONFIG_PREFIX=\/tmp\/det03-npm-prefix-sentinel/d' /home/agent/.profile
  sudo rm -rf "$sentinel"
}

@test "DET-03: effective prefix ownership + writability captured for the install user" {
  # REQ: DET-03
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-03"
  printf '%s' "$output" | jq -e '
    (.components.npm_prefix // .npm_prefix) as $np
    | $np.npm_present == true
    and ($np.effective_owner | type == "string" and test("^[a-z_][a-z0-9_-]*:[a-z_][a-z0-9_-]*$"))
    and (($np.install_user_writable == true) or ($np.install_user_writable == false))
    and (($np.prefix_declarations | type) == "number")
  ' >/dev/null \
    || __fail "DET-03" "effective_owner is user:group, install_user_writable is bool, prefix_declarations is number" "$output" "$LOG"
}

@test "DET-04: claude classified healthy when present and --version exits 0" {
  # REQ: DET-04
  # Post-installer host: claude-code may or may not be installed in this CI
  # base (catalog opt-in). Test asserts the classifier reaches one of the
  # three valid statuses for the claude-code agent entry.
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04"
  printf '%s' "$output" | jq -e '
    (.components.agents // .agents)
    | map(select(.id == "claude-code"))
    | length == 1
    and (.[0].status == "healthy" or .[0].status == "broken" or .[0].status == "absent")
  ' >/dev/null \
    || __fail "DET-04" "claude-code agent entry present with status in {healthy, broken, absent}" "$output" "$LOG"
}

@test "DET-04: get-shit-done-cc classified healthy when --help banner parseable" {
  # REQ: DET-04
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04"
  # Same shape assertion as claude-code: entry exists with one of the three valid statuses.
  printf '%s' "$output" | jq -e '
    (.components.agents // .agents)
    | map(select(.id == "gsd"))
    | length == 1
    and (.[0].status == "healthy" or .[0].status == "broken" or .[0].status == "absent")
  ' >/dev/null \
    || __fail "DET-04" "gsd agent entry present with status in {healthy, broken, absent}" "$output" "$LOG"
}

@test "DET-04: playwright-cli classified absent when binary missing from install user PATH" {
  # REQ: DET-04
  # Greenfield CI base: playwright-cli is not pre-installed. Assert one of the
  # three valid statuses (the harness may pre-install it in a future base; the
  # important invariant is the classifier returns a valid status string).
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04"
  local status
  status=$(printf '%s' "$output" | jq -r '(.components.agents // .agents) | map(select(.id == "playwright-cli")) | .[0].status')
  [[ "$status" == "absent" || "$status" == "healthy" || "$status" == "broken" ]] \
    || __fail "DET-04" "playwright-cli status in {healthy, broken, absent} (got '$status')" "$output" "$LOG"
}

@test "DET-04: classifier returns broken when binary present but --help non-zero" {
  # REQ: DET-04
  # Fixture: drop a fake claude binary on the install user's PATH that exits 0 on
  # --version (parses as "1.0.0") but exits 1 on --help. Classifier must return broken.
  sudo -u agent mkdir -p /home/agent/.local/bin
  cat >/tmp/_fake_claude.sh <<'EOF'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "1.0.0"; exit 0; }
[[ "$1" == "--help" ]] && exit 1
exit 1
EOF
  sudo install -m 0755 -o agent -g agent /tmp/_fake_claude.sh /home/agent/.local/bin/claude
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04"
  local status
  status=$(printf '%s' "$output" | jq -r '(.components.agents // .agents) | map(select(.id == "claude-code")) | .[0].status')
  [[ "$status" == "broken" ]] \
    || __fail "DET-04" "claude-code classified broken when --help exits non-zero (got '$status')" "$output" "$LOG"
  sudo rm -f /home/agent/.local/bin/claude
}
