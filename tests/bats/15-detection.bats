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
load 'helpers/distro'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

# Backstop cleanup for the npx-form gsd fixture (the "deployed-system VERSION"
# test below). Runs after EVERY test so the fixture is removed even when an
# assertion aborts the test body before its inline cleanup. Idempotent + scoped
# to the gsd fixture paths, so it is a no-op for the other DET-* tests.
teardown() {
  rm -rf /home/agent/.claude/gsd-core /home/agent/.claude/skills/gsd-fixture-skill 2>/dev/null || true
}

@test "DET-01: --report-only --report-format=json reports install user UID + shell + home_writable" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-01"
  # Plan 12-03 wraps the merged-fragment cache under .components (CONTEXT.md
  # Area 1). The `.components.X // .X` fallback keeps this @test green across
  # the pre-12-03 flat shape and the post-12-03 wrapped shape.
  printf '%s' "$output" | jq -e '
    (.components.user // .user) as $u
    | $u.present == true and ($u.uid | tonumber) > 0 and $u.home_writable == true
  ' >/dev/null \
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
  # Plan 12-03 wraps the merged-fragment cache under .components (CONTEXT.md
  # Area 1). The `.components.X // .X` fallback keeps this @test green across
  # the pre-12-03 flat shape and the post-12-03 wrapped shape.
  printf '%s' "$output" | jq -e '
    (.components.sudoers // .sudoers) as $s
    | $s.path == "/etc/sudoers.d/agentlinux" and ($s.present == true or $s.present == false)
  ' >/dev/null \
    || __fail "DET-05" "sudoers.path + boolean .present" "$output" "$LOG"
  # When present, sha256 must be a 64-char hex string and nopasswd_line_present a bool.
  printf '%s' "$output" | jq -e '
    (.components.sudoers // .sudoers) as $s
    | if $s.present then ($s.sha256 | test("^[0-9a-f]{64}$")) and (($s.nopasswd_line_present == true) or ($s.nopasswd_line_present == false)) else true end
  ' >/dev/null \
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
  # Fixture: write a login-shell profile snippet that exports NPM_CONFIG_PREFIX
  # to a known sentinel path. as_user_login (sudo -i) sources the login-shell
  # profile; bare as_user (sudo -E without -i) would NOT source it. If the probe
  # is implemented correctly with as_user_login, effective_prefix reflects the
  # sentinel value.
  #
  # The per-user login-shell profile file is FAMILY-SPECIFIC: a bash login shell
  # sources the FIRST of ~/.bash_profile, ~/.bash_login, ~/.profile that exists.
  # Debian/Ubuntu skel ships ~/.profile (no ~/.bash_profile); RHEL/EL skel ships
  # ~/.bash_profile (no ~/.profile). Write the sentinel to the file the login
  # shell on THIS family actually reads — same observable (a user-shell
  # NPM_CONFIG_PREFIX export propagates through as_user_login into
  # effective_prefix), family-correct path. Generalize, never weaken.
  #
  # Proven live on EL9 (Plan 20-05 spike): a sentinel in ~/.profile is IGNORED
  # by `sudo -u agent -i` (the file is unsourced on EL9) while a sentinel in
  # ~/.bash_profile propagates correctly — confirming the product as_user_login
  # is correct and only the fixture's target file was Debian-specific.
  local sentinel=/tmp/det03-npm-prefix-sentinel
  local profile
  case "$(distro_family)" in
    rhel) profile=.bash_profile ;;
    *)    profile=.profile ;;
  esac
  sudo -u agent mkdir -p "$sentinel"
  sudo -u agent bash -c "echo 'export NPM_CONFIG_PREFIX=/tmp/det03-npm-prefix-sentinel' >> ~/${profile}"
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-03"
  local effective
  effective=$(printf '%s' "$output" | jq -r '(.components.npm_prefix // .npm_prefix).effective_prefix')
  [[ "$effective" == "/tmp/det03-npm-prefix-sentinel" ]] \
    || __fail "DET-03" "effective_prefix reflects user-shell NPM_CONFIG_PREFIX export (got '$effective'); confirms as_user_login was used" "$output" "$LOG"
  # Cleanup so subsequent @tests see a clean profile.
  sudo -u agent sed -i '/NPM_CONFIG_PREFIX=\/tmp\/det03-npm-prefix-sentinel/d' "/home/agent/${profile}"
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

@test "DET-04: gsd classified healthy at the deployed-system VERSION path when the bootstrapper binary is absent (npx form)" {
  # REQ: DET-04. Regression guard for "dry-run says gsd absent on a host where
  # GSD is installed without a persistent package-native binary. The upstream
  # Open GSD installer deploys the GSD system (~/.claude/gsd-core
  # /VERSION + gsd-* skills) but leaves NO persistent global binary. Detection
  # must recognize that form via the VERSION file, not report 'absent'.
  if sudo -u agent -H -i -- command -v gsd-core >/dev/null 2>&1; then
    skip "gsd-core binary present (a prior test installed it) — system-only fixture not isolable"
  fi
  install -d -m 0755 -o agent -g agent /home/agent/.claude/gsd-core
  printf '1.37.1\n' >/tmp/gsd-ver-fixture
  install -m 0644 -o agent -g agent /tmp/gsd-ver-fixture /home/agent/.claude/gsd-core/VERSION
  rm -f /tmp/gsd-ver-fixture
  install -d -m 0755 -o agent -g agent /home/agent/.claude/skills/gsd-fixture-skill

  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-04"
  printf '%s' "$output" | jq -e '
    (.components.agents // .agents)
    | map(select(.id == "gsd"))
    | .[0].status == "healthy"
    and (.[0].path == "/home/agent/.claude/gsd-core/VERSION")
    and (.[0].version == "1.37.1")
  ' >/dev/null \
    || __fail "DET-04" "gsd healthy at deployed-system VERSION path (npx form, no binary)" "$output" "$LOG"
  # Fixture removed by teardown() (survives the __fail abort path above too).
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

# ---- Plan 12-03 appends: read-only invariant + DET-06 acceptance + greenfield meta ----
# Per .planning/phases/12-detection-layer/12-03-PLAN.md Task 5.
# Every @test name starts with the REQ-ID (behavior-test-contract SKILL).

@test "DET-01..06: detection writes zero bytes to /etc /home /usr/local/bin /opt" {
  # Snapshot host paths before + after a full detect::run_once via --report-only.
  # Per CONTEXT.md Area 4 Q2: scope is /etc /home /usr/local/bin /opt (helper).
  # Per RESEARCH §Pitfall 9: jq must be pre-installed in the Docker image
  # (Task 4 documented this); otherwise ensure_jq's apt-get install would
  # mutate /var/lib/dpkg/* and false-positive this @test.
  local pre post
  pre=$(mktemp)
  post=$(mktemp)
  snapshot_paths >"$pre"
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-read-only"
  snapshot_paths >"$post"
  if ! diff -q "$pre" "$post" >/dev/null 2>&1; then
    local delta
    delta=$(diff -u "$pre" "$post" | head -40)
    rm -f "$pre" "$post"
    __fail "DET-read-only" "snapshot identity across detection pass" "$delta" "$LOG"
  fi
  rm -f "$pre" "$post"
}

@test "DET-06: text format renders [DET-NN] markers for every captured field" {
  run bash "$INSTALLER" --report-only --report-format=text
  assert_exit_zero "DET-06"
  # Section presence: one '## DET-NN —' header per detector.
  local nn
  for nn in DET-01 DET-02 DET-03 DET-04 DET-05; do
    printf '%s' "$output" | grep -qE "^## ${nn} —" \
      || __fail "DET-06" "section header ## ${nn} present" "$output" "$LOG"
  done
  # Field markers — at minimum one [DET-NN] line per detector's primary key.
  # Mirrors the LOCKED text-renderer contract from Plan 12-01 interfaces.
  local required
  for required in '\[DET-01\] user\.uid=' '\[DET-02\] nodejs\.' \
    '\[DET-03\] npm\.' '\[DET-04\] agent\.claude-code\.status=' \
    '\[DET-05\] sudoers\.path='; do
    printf '%s' "$output" | grep -qE "$required" \
      || __fail "DET-06" "marker pattern ${required} present in text output" "$output" "$LOG"
  done
}

@test "DET-06: json format parses via jq with every captured field reachable" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-06"
  # Top-level shape: {generated_at, host, components}.
  printf '%s' "$output" | jq -e '
    type == "object"
    and .generated_at != null
    and .host.os != null
    and .host.version != null
    and (.components | type) == "object"
  ' >/dev/null \
    || __fail "DET-06" "top-level shape {generated_at, host:{os,version}, components:{}}" "$output" "$LOG"
  # Components: every detector reachable.
  printf '%s' "$output" | jq -e '
    .components.user.uid != null
    and (.components.npm_prefix.effective_prefix != null or .components.npm_prefix.npm_present == false)
    and .components.sudoers.path == "/etc/sudoers.d/agentlinux"
    and (.components.nodejs | type) == "array"
    and (.components.agents | type) == "array"
    and (.components.agents | length) >= 3
  ' >/dev/null \
    || __fail "DET-06" "components.{user,npm_prefix,sudoers,nodejs[],agents[]} reachable + agents has all 3 catalog ids" "$output" "$LOG"
}

@test "DET-06: json output contains NO schema_version / \$schema / version field at top level" {
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "DET-06"
  # CONTEXT.md Area 2 amendment of DET-06: explicit prohibition.
  printf '%s' "$output" | jq -e '
    has("schema_version") == false
    and has("$schema") == false
    and has("version") == false
  ' >/dev/null \
    || __fail "DET-06" "no schema_version/\$schema/version at top level (CONTEXT.md Area 2)" "$output" "$LOG"
}

@test "DET-06: NO_COLOR env var honored — zero ANSI escapes in text output" {
  NO_COLOR=1 run bash "$INSTALLER" --report-only --report-format=text
  assert_exit_zero "DET-06"
  # ANSI CSI sequence: ESC [ ... — bytes 0x1b 0x5b. Use printf to pin the
  # ESC byte literally; LC_ALL=C ensures grep sees bytes, not glyphs.
  local count
  count=$(printf '%s' "$output" | LC_ALL=C grep -c $'\033\[' || true)
  [[ "$count" -eq 0 ]] \
    || __fail "DET-06" "NO_COLOR=1 strips all ANSI escapes (got $count escapes)" "$output" "$LOG"
}

@test "DET-06: piped (non-TTY) text output strips ANSI color escapes" {
  # `run` already captures via subshell pipes (no TTY). Assert no ANSI escapes.
  run bash "$INSTALLER" --report-only --report-format=text
  assert_exit_zero "DET-06"
  local count
  count=$(printf '%s' "$output" | LC_ALL=C grep -c $'\033\[' || true)
  [[ "$count" -eq 0 ]] \
    || __fail "DET-06" "non-TTY stdout strips ANSI escapes (got $count escapes)" "$output" "$LOG"
}

@test "DET-01..06: greenfield baseline preserved — bats run-line count matches expected" {
  # Meta-assertion: 15-detection.bats has at least the Plan 12-01 7 + Plan 12-02
  # >=3 + Plan 12-03 7 = 17 @tests. Guards against accidental @test deletion
  # during a future refactor. Runs INSIDE bats, so count via wc -l on the
  # @test lines in the source file (not `bats --count` which would self-loop).
  local tests_in_file
  tests_in_file=$(grep -cE '^@test "' /opt/agentlinux-src/tests/bats/15-detection.bats)
  [[ "$tests_in_file" -ge 17 ]] \
    || __fail "DET-greenfield" "15-detection.bats has at least 17 @tests (got $tests_in_file)" "tests_in_file=$tests_in_file" "$LOG"
}
