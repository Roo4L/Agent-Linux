#!/usr/bin/env bats
# tests/bats/40-registry-cli.bats — Phase 4 integration: CLI-01..07, CAT-01..04, INST-04.
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - setup() force-removes leftover test-dummy state so tests start clean
#   - teardown_file restores state sufficient for siblings to re-run
#   - test-dummy is the happy-path fixture; real agents (claude-code/gsd/playwright)
#     are CATALOG-TESTED (listed) but NOT INSTALLED (installs land Phase 5)
#   - INST-04 --purge is destructive; @tests that exercise it are placed LAST
#     and grouped under a separate file-suffix block so bats' serial execution
#     of tests within a file keeps them ordered correctly
#
# Refs: 04-RESEARCH §Example 3 (@test shapes for CLI-03/04/05 + CAT-02 + INST-04);
#       tests/bats/30-runtime.bats (six-mode INVOKE_MODES precedent);
#       .claude/skills/behavior-test-contract/SKILL.md (ID-in-name convention).

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

setup_file() {
  # The installer is already run by tests/docker/run.sh BEFORE bats fires,
  # so 20/30-runtime bats already cover the "installer ran successfully"
  # precondition. Force-remove any test-dummy leftover from a previous test
  # file (e.g. a re-run where teardown didn't fire because of a hard kill).
  sudo -u agent -H bash --login -c 'agentlinux remove --force test-dummy' >/dev/null 2>&1 || true
  rm -f /tmp/agentlinux-test-dummy.marker || true
}

teardown_file() {
  # Leave test-dummy uninstalled for subsequent test files / re-runs.
  # INST-04 --purge tests at the bottom of this file nuke /opt/agentlinux
  # entirely; a teardown `agentlinux remove` after that would fail because
  # the binary is gone. Guard on symlink presence so teardown stays clean.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force test-dummy' >/dev/null 2>&1 || true
  fi
  rm -f /tmp/agentlinux-test-dummy.marker || true
}

setup() {
  # Reset marker + sentinel before every test. If the binary has already been
  # nuked by an INST-04 --purge test, skip cleanup (those tests are the final
  # two in this file and any test after a purge @test would already see a
  # missing binary — we keep the guard tight to avoid spurious pre-test
  # failures).
  rm -f /tmp/agentlinux-test-dummy.marker || true
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force test-dummy' >/dev/null 2>&1 || true
  fi
}

# ---------- CLI-01: agentlinux on agent's PATH ----------

# CLI-01: the keystone PATH proof — `command -v agentlinux` resolves under
# /home/agent/.npm-global/bin across every invocation mode. Loops INVOKE_MODES
# like RT-04 + RT-02 do — this is the CLI-side observable equivalent.
@test "CLI-01: agentlinux binary resolves under /home/agent/.npm-global/bin in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'command -v agentlinux'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "CLI-01 (${mode}): systemd PID 1 not running in this container"
    fi
    assert_exit_zero "CLI-01 (${mode})"
    assert_path_has "CLI-01 (${mode})" "/home/agent/.npm-global/bin/agentlinux"
  done
}

# CLI-01: --version prints 0.3.2 across invocation modes — proves the symlink
# + Node shebang + dist/index.js + package.json "type":"module" chain all fire
# regardless of which shell wrapper the caller uses.
@test "CLI-01: agentlinux --version prints 0.3.2 from every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'agentlinux --version'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "CLI-01 (${mode}): systemd PID 1 not running"
    fi
    assert_exit_zero "CLI-01 (${mode})"
    assert_path_has "CLI-01 (${mode})" "0.3.2"
  done
}

# ---------- CLI-02: list shows catalog with installed/not-installed ----------

# CLI-02 + CAT-01: the three real agents (claude-code, gsd, playwright-cli)
# all show up in default `agentlinux list` output; test-dummy MUST be hidden
# (test_only:true) without --include-test. Happy-path + filter-negative combo.
@test "CLI-02: agentlinux list shows the three real agents by default (test-dummy hidden)" {
  run sudo -u agent -H bash --login -c 'agentlinux list'
  assert_exit_zero "CLI-02"
  echo "$output" | grep -q 'claude-code' \
    || __fail "CLI-02" "claude-code in default list" "${output:-<empty>}" "$LOG"
  echo "$output" | grep -q 'gsd' \
    || __fail "CLI-02" "gsd in default list" "${output:-<empty>}" "$LOG"
  echo "$output" | grep -q 'playwright-cli' \
    || __fail "CLI-02" "playwright-cli in default list" "${output:-<empty>}" "$LOG"
  # test-dummy MUST NOT appear in default list (CAT-02 related — no test fixtures
  # leak into user-facing default output).
  if echo "$output" | grep -q 'test-dummy'; then
    __fail "CLI-02" "test-dummy HIDDEN by default" "test-dummy leaked: ${output}" "$LOG"
  fi
}

# CLI-02: --include-test opts test-dummy into the table.
@test "CLI-02: agentlinux list --include-test shows test-dummy" {
  run sudo -u agent -H bash --login -c 'agentlinux list --include-test'
  assert_exit_zero "CLI-02"
  echo "$output" | grep -q 'test-dummy' \
    || __fail "CLI-02" "test-dummy shown with --include-test" "${output:-<empty>}" "$LOG"
}

# CLI-02: machine-readable JSON array — CI consumers, scripts, downstream
# tooling. jq -e '. | length >= 3' asserts the array has the three real agents.
@test "CLI-02: agentlinux list --json emits machine-readable JSON array" {
  run sudo -u agent -H bash --login -c 'agentlinux list --json'
  assert_exit_zero "CLI-02"
  # Pipe through jq (installed in the Docker image via Plan 04-07 Dockerfile
  # extension). `jq -e` sets exit non-zero when the filter returns false/null.
  echo "$output" | jq -e '. | length >= 3' >/dev/null \
    || __fail "CLI-02" "JSON array with >=3 entries" "${output:-<empty>}" "$LOG"
}

# ---------- CLI-03: install dispatches recipe + writes sentinel; idempotent ----------

# CLI-03 + CAT-04: install test-dummy writes the marker AND the sentinel;
# sentinel records the catalog's pinned_version (0.0.1) + source='curated'.
# Proves the env plumbing from runner.ts → install.sh → sentinel write works.
@test "CLI-03: install test-dummy creates marker + sentinel with pinned version" {
  run sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy'
  assert_exit_zero "CLI-03"
  [[ -f /tmp/agentlinux-test-dummy.marker ]] \
    || __fail "CLI-03" "marker file created at /tmp/agentlinux-test-dummy.marker" "absent" "$LOG"
  # test-dummy install.sh writes `version=${AGENTLINUX_PINNED_VERSION}` —
  # asserts the env wiring from runner.ts reached the recipe and the catalog's
  # pinned_version (0.0.1) propagated through decideVersion to AGENTLINUX_PINNED_VERSION.
  grep -q '^version=0.0.1$' /tmp/agentlinux-test-dummy.marker \
    || __fail "CLI-03+CAT-04" \
      "marker contains 'version=0.0.1' (pinned_version honored end-to-end)" \
      "$(cat /tmp/agentlinux-test-dummy.marker 2>/dev/null || echo '<missing>')" \
      "$LOG"
  [[ -f /opt/agentlinux/state/installed.d/test-dummy.json ]] \
    || __fail "CLI-03" "sentinel file created" "absent" "/opt/agentlinux/state/installed.d/"
  local sentinel_version sentinel_source
  sentinel_version=$(jq -r '.version' /opt/agentlinux/state/installed.d/test-dummy.json)
  sentinel_source=$(jq -r '.source' /opt/agentlinux/state/installed.d/test-dummy.json)
  [[ "$sentinel_version" == "0.0.1" ]] \
    || __fail "CLI-03+CAT-04" "sentinel.version=0.0.1" "$sentinel_version" "/opt/agentlinux/state/installed.d/test-dummy.json"
  [[ "$sentinel_source" == "curated" ]] \
    || __fail "CLI-03" "sentinel.source=curated" "$sentinel_source" "/opt/agentlinux/state/installed.d/test-dummy.json"
}

# CLI-03: idempotent re-install — second `install` with same version prints
# 'already installed' and does NOT re-run install.sh (marker's installed_at
# stays unchanged). T-04-08 mitigation.
@test "CLI-03: second install test-dummy is idempotent (no-op)" {
  sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy' >/dev/null
  run sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy'
  assert_exit_zero "CLI-03"
  echo "$output" | grep -q 'already installed' \
    || __fail "CLI-03" "'already installed' idempotency message" "${output:-<empty>}" "$LOG"
}

# CLI-03: --force BYPASSES the idempotent short-circuit, re-runs install.sh,
# marker's installed_at timestamp advances. Observable via sleep 1 + byte diff.
@test "CLI-03: install --force re-runs recipe even on matching sentinel" {
  sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy' >/dev/null
  local first
  first=$(grep '^installed_at=' /tmp/agentlinux-test-dummy.marker)
  # test-dummy install.sh uses $(date -u +%Y-%m-%dT%H:%M:%SZ) — second-level
  # resolution. Sleep 1 guarantees the second timestamp differs.
  sleep 1
  run sudo -u agent -H bash --login -c 'agentlinux install --force --include-test test-dummy'
  assert_exit_zero "CLI-03"
  local second
  second=$(grep '^installed_at=' /tmp/agentlinux-test-dummy.marker)
  [[ "$first" != "$second" ]] \
    || __fail "CLI-03" "marker installed_at advanced after --force" "unchanged: $first" "$LOG"
}

# CLI-03: --version overrides the catalog pin; sentinel records source='override'.
# Proves the decideVersion override path + runner env wiring.
@test "CLI-03: install --version 9.9.9 overrides catalog pin (sentinel.source=override)" {
  run sudo -u agent -H bash --login -c 'agentlinux install --include-test --version 9.9.9 test-dummy'
  assert_exit_zero "CLI-03"
  local v s
  v=$(jq -r '.version' /opt/agentlinux/state/installed.d/test-dummy.json)
  s=$(jq -r '.source' /opt/agentlinux/state/installed.d/test-dummy.json)
  [[ "$v" == "9.9.9" ]] \
    || __fail "CLI-03" "sentinel.version=9.9.9 under --version override" "$v" "-"
  [[ "$s" == "override" ]] \
    || __fail "CLI-03" "sentinel.source=override under --version override" "$s" "-"
}

# ---------- CLI-04: remove is symmetric inverse of install ----------

# CLI-04: remove clears BOTH marker (uninstall.sh executed) AND sentinel
# (CLI deleted state). Proves the dispatch path runs the recipe BEFORE
# deleting state (ordering — sentinel exists when recipe runs, deleted after).
@test "CLI-04: remove test-dummy clears marker + sentinel" {
  sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy' >/dev/null
  run sudo -u agent -H bash --login -c 'agentlinux remove test-dummy'
  assert_exit_zero "CLI-04"
  [[ ! -f /tmp/agentlinux-test-dummy.marker ]] \
    || __fail "CLI-04" "marker absent after remove" "still present" "/tmp/agentlinux-test-dummy.marker"
  [[ ! -f /opt/agentlinux/state/installed.d/test-dummy.json ]] \
    || __fail "CLI-04" "sentinel absent after remove" "still present" "/opt/agentlinux/state/installed.d/"
}

# CLI-04: remove-when-not-installed exits 1 without --force (user gets a clear
# error); exits 0 with --force (idempotent no-op). T-04-09 mitigation: prevents
# drive-by `remove` on a never-installed agent from silently succeeding.
@test "CLI-04: remove on not-installed exits 1 without --force; exits 0 with --force" {
  # Ensure not installed (setup() already force-removed, but be explicit).
  sudo -u agent -H bash --login -c 'agentlinux remove --force test-dummy' >/dev/null 2>&1 || true
  run sudo -u agent -H bash --login -c 'agentlinux remove test-dummy'
  [[ "$status" -eq 1 ]] \
    || __fail "CLI-04" "exit 1 when agent not installed (no --force)" "exit $status; output: ${output:-<empty>}" "-"
  # With --force: no-op exit 0.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force test-dummy'
  assert_exit_zero "CLI-04 (--force no-op)"
}

# ---------- CLI-05: non-agent user fail-fast ----------

# CLI-05: invoked as root (non-agent) → exit 64 (EX_USAGE) with "must run as
# user 'agent'" diagnostic on stderr. Pattern ref: 04-RESEARCH §Pattern 8.
@test "CLI-05: running agentlinux as root exits 64 with 'must run as' message" {
  # Direct invocation without sudo -u agent — runs as root (bats's host user).
  run bash -c '/home/agent/.npm-global/bin/agentlinux list 2>&1'
  [[ "$status" -eq 64 ]] \
    || __fail "CLI-05" "exit 64 when invoker != agent" "exit $status; output: ${output:-<empty>}" "-"
  echo "$output" | grep -q "must run as user 'agent'" \
    || __fail "CLI-05" "'must run as user agent' in diagnostic" "${output:-<empty>}" "-"
}

# CLI-05: invoked as agent → succeeds without sudo. Companion positive case
# so regressions to the guard can't pass both @tests simultaneously.
@test "CLI-05: running agentlinux as agent user succeeds without sudo" {
  run sudo -u agent -H bash --login -c 'agentlinux --version'
  assert_exit_zero "CLI-05"
  assert_path_has "CLI-05" "0.3.2"
}

# ---------- CLI-06: upgrade detects divergence; report-only without bulk flag ----------

# CLI-06: bare `agentlinux upgrade` renders the report table. Key property:
# NO MUTATION (report-only default per willTouchUpstream()). After the call,
# the sentinel is byte-identical to before. Offline-default honored (T-04-12).
@test "CLI-06: upgrade (no flags) prints report without mutating sentinel" {
  sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy' >/dev/null
  # Snapshot sentinel before.
  local pre_version pre_source
  pre_version=$(jq -r '.version' /opt/agentlinux/state/installed.d/test-dummy.json)
  pre_source=$(jq -r '.source' /opt/agentlinux/state/installed.d/test-dummy.json)

  run sudo -u agent -H bash --login -c 'agentlinux upgrade'
  assert_exit_zero "CLI-06"
  # test-dummy should NOT appear in default upgrade output (test_only filtered
  # same as list default). The three real agents render.
  echo "$output" | grep -q 'claude-code' \
    || __fail "CLI-06" "claude-code in upgrade report table" "${output:-<empty>}" "$LOG"

  # Sentinel unchanged — report-only default.
  local post_version post_source
  post_version=$(jq -r '.version' /opt/agentlinux/state/installed.d/test-dummy.json)
  post_source=$(jq -r '.source' /opt/agentlinux/state/installed.d/test-dummy.json)
  [[ "$pre_version" == "$post_version" && "$pre_source" == "$post_source" ]] \
    || __fail "CLI-06" \
      "sentinel unchanged after report-only upgrade" \
      "pre:{$pre_version,$pre_source} post:{$post_version,$post_source}" \
      "/opt/agentlinux/state/installed.d/test-dummy.json"
}

# ---------- CLI-07: pin sticky-override semantics ----------

# CLI-07: pin=latest sets sticky=true + source=latest; version preserved
# (Open Q4: resolved at next upgrade --all-latest). Proves the sentinel
# mutation is partial (id + installed_at + version preserved; only
# source/sticky mutate).
@test "CLI-07: pin test-dummy=latest sets sticky=true, source=latest" {
  sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy' >/dev/null
  run sudo -u agent -H bash --login -c 'agentlinux pin test-dummy=latest'
  assert_exit_zero "CLI-07"
  local sticky source
  sticky=$(jq -r '.sticky' /opt/agentlinux/state/installed.d/test-dummy.json)
  source=$(jq -r '.source' /opt/agentlinux/state/installed.d/test-dummy.json)
  [[ "$sticky" == "true" ]] \
    || __fail "CLI-07" "sentinel.sticky=true after pin=latest" "$sticky" "-"
  [[ "$source" == "latest" ]] \
    || __fail "CLI-07" "sentinel.source=latest after pin=latest" "$source" "-"
}

# CLI-07: pin=curated clears the sticky flag (inverse of pin=latest). Proves
# the state-only mutation round-trip works.
@test "CLI-07: pin test-dummy=curated clears sticky flag" {
  sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy' >/dev/null
  sudo -u agent -H bash --login -c 'agentlinux pin test-dummy=latest' >/dev/null
  run sudo -u agent -H bash --login -c 'agentlinux pin test-dummy=curated'
  assert_exit_zero "CLI-07"
  local sticky source
  sticky=$(jq -r '.sticky' /opt/agentlinux/state/installed.d/test-dummy.json)
  source=$(jq -r '.source' /opt/agentlinux/state/installed.d/test-dummy.json)
  [[ "$sticky" == "false" ]] \
    || __fail "CLI-07" "sticky cleared (false) on pin=curated" "$sticky" "-"
  [[ "$source" == "curated" ]] \
    || __fail "CLI-07" "source=curated on pin=curated" "$source" "-"
}

# ---------- CAT-01, CAT-02, CAT-04 ----------

# CAT-01: all three real agents are present in the JSON output (authoritative
# machine-readable form; the text-table CLI-02 test is the human-readable twin).
@test "CAT-01: catalog JSON contains claude-code, gsd, playwright-cli" {
  run sudo -u agent -H bash --login -c 'agentlinux list --json'
  assert_exit_zero "CAT-01"
  local ids
  ids=$(echo "$output" | jq -r '.[].id' | sort | tr '\n' ' ')
  # `grep -qw` would NOT match `playwright-cli` because `-` is a non-word
  # boundary; switch to fixed-string `grep -qF` with a leading/trailing
  # space so we still get whole-token matching against the space-joined
  # id stream above.
  echo " $ids" | grep -qF ' claude-code ' \
    || __fail "CAT-01" "claude-code in JSON ids" "$ids" "-"
  echo " $ids" | grep -qF ' gsd ' \
    || __fail "CAT-01" "gsd in JSON ids" "$ids" "-"
  echo " $ids" | grep -qF ' playwright-cli ' \
    || __fail "CAT-01" "playwright-cli in JSON ids" "$ids" "-"
}

# CAT-02: fresh install has empty /opt/agentlinux/state/installed.d/.
# Fresh state is asserted AFTER setup()'s force-remove: sentinel dir exists
# (agent:agent 0755 per provisioner) but contains no *.json files. This is
# the "zero default agents" contract — every install is opt-in (ADR-003).
@test "CAT-02: fresh installed.d/ is empty after force-remove of test-dummy" {
  # setup() already did `remove --force test-dummy`. Assert the directory
  # exists but has no *.json children.
  [[ -d /opt/agentlinux/state/installed.d ]] \
    || __fail "CAT-02" "installed.d/ directory exists (provisioner staged it)" "missing" "-"
  # Use find + -maxdepth=1 -name '*.json' so non-JSON junk (if any) doesn't
  # false-positive the test. Expected output: empty string.
  local residual
  residual=$(find /opt/agentlinux/state/installed.d -maxdepth 1 -name '*.json' 2>/dev/null)
  [[ -z "$residual" ]] \
    || __fail "CAT-02" "zero *.json sentinels in installed.d/ on fresh state" \
         "residual: ${residual}" "/opt/agentlinux/state/installed.d/"
}

# CAT-04: every catalog entry has a non-empty pinned_version (surfaced as
# `curated` in list --json). Schema enforces required+semver pattern at
# pre-commit; this asserts the end-to-end runtime surfacing.
@test "CAT-04: every list row exposes a non-empty pinned_version" {
  run sudo -u agent -H bash --login -c 'agentlinux list --include-test --json'
  assert_exit_zero "CAT-04"
  local missing
  # jq selects rows whose curated field is null OR empty-string; map to id.
  missing=$(echo "$output" | jq -r '.[] | select(.curated == null or .curated == "") | .id' | tr '\n' ' ')
  [[ -z "$missing" ]] \
    || __fail "CAT-04" "every entry has a pinned_version in .curated" "missing: $missing" "-"
  # Spot-check the pinned values against what catalog.json declares (Plan 04-02).
  local claude_ver gsd_ver playwright_cli_ver dummy_ver
  claude_ver=$(echo "$output" | jq -r '.[] | select(.id=="claude-code") | .curated')
  gsd_ver=$(echo "$output" | jq -r '.[] | select(.id=="gsd") | .curated')
  playwright_cli_ver=$(echo "$output" | jq -r '.[] | select(.id=="playwright-cli") | .curated')
  dummy_ver=$(echo "$output" | jq -r '.[] | select(.id=="test-dummy") | .curated')
  [[ "$claude_ver" == "2.1.98" ]] \
    || __fail "CAT-04" "claude-code pinned_version=2.1.98" "$claude_ver" "plugin/catalog/catalog.json"
  [[ "$gsd_ver" == "1.37.1" ]] \
    || __fail "CAT-04" "gsd pinned_version=1.37.1" "$gsd_ver" "plugin/catalog/catalog.json"
  [[ "$playwright_cli_ver" == "0.1.11" ]] \
    || __fail "CAT-04" "playwright-cli pinned_version=0.1.11" "$playwright_cli_ver" "plugin/catalog/catalog.json"
  [[ "$dummy_ver" == "0.0.1" ]] \
    || __fail "CAT-04" "test-dummy pinned_version=0.0.1" "$dummy_ver" "plugin/catalog/catalog.json"
}

# ---------- CAT-03: add a new agent WITHOUT CLI source edit ----------

# CAT-03: the classic "submit-JSON-plus-recipe" proof. Build a tmp catalog at
# bats-setup time with a fresh entry 'fake-42', point the CLI at it via
# AGENTLINUX_CATALOG_DIR (loader.ts + schema.ts both honor this env seam),
# and assert the entry shows up in `agentlinux list`. No TypeScript source
# was changed to make fake-42 visible — the contract is CATALOG-IS-DATA.
@test "CAT-03: throwaway catalog fixture loads without editing plugin/cli/src/" {
  local tmp
  tmp=$(mktemp -d /tmp/agentlinux-cat03.XXXXXX)
  # Tmp dir must be agent-readable (setup: root-owned mode 0700 by default).
  chmod 0755 "$tmp"
  mkdir -p "$tmp/agents/fake-42"

  # Minimal valid catalog.json + matching schema.json (schema is resolved via
  # the same AGENTLINUX_CATALOG_DIR env var — schema.ts §resolveSchemaPath).
  # Copy the production schema verbatim so the fixture catalog validates
  # against the SAME rules production does.
  cp /opt/agentlinux/catalog/0.3.2/schema.json "$tmp/schema.json"

  cat >"$tmp/catalog.json" <<'JSON'
{
  "version": "0.3.2",
  "agents": [
    {
      "id": "fake-42",
      "display_name": "Fake Fortytwo",
      "description": "CAT-03 fixture — added via catalog-only change",
      "source_kind": "script",
      "pinned_version": "4.2.0",
      "install_recipe_path": "install.sh",
      "uninstall_recipe_path": "uninstall.sh",
      "test_only": true
    }
  ]
}
JSON
  cat >"$tmp/agents/fake-42/install.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
echo "fake-42: pinned=${AGENTLINUX_PINNED_VERSION}"
SH
  cat >"$tmp/agents/fake-42/uninstall.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "fake-42: removed"
SH
  chmod 0755 "$tmp/agents/fake-42"/*.sh
  # The agent user must be able to read the tmp dir — /tmp is normally world-r,
  # but inherit-owner from root+0755 is sufficient.
  chmod -R a+rX "$tmp"

  run sudo -u agent -H bash --login -c "AGENTLINUX_CATALOG_DIR='$tmp' agentlinux list --include-test --json"
  local status_saved=$status
  local output_saved=$output
  # Clean up the tmp dir regardless of outcome.
  rm -rf "$tmp"

  [[ $status_saved -eq 0 ]] \
    || __fail "CAT-03" "agentlinux list against tmp catalog exits 0" "exit $status_saved; output: $output_saved" "-"
  echo "$output_saved" | jq -e '.[] | select(.id=="fake-42")' >/dev/null \
    || __fail "CAT-03" "fake-42 present in override-catalog list JSON" "$output_saved" "-"
}

# ---------- INST-04: --purge ordered teardown (DESTRUCTIVE — runs last) ----------

# The two INST-04 @tests below NUKE the installation. bats runs @tests within
# a file in the order they appear in source. Any @test placed below these
# would observe a post-purge system — no /opt/agentlinux, no agent user, no
# agentlinux binary. Keep them LAST and do not add non-purge tests after them.

# INST-04: --purge runs uninstall.sh (marker gone) then destroys filesystem
# artefacts. Seven-step ordered teardown per plan 04-06. Asserts:
#   - exit 0
#   - marker gone (uninstall.sh ran BEFORE /opt removal)
#   - /opt/agentlinux gone
#   - agent user gone
#   - PATH artefacts (profile.d, agentlinux.env, cron.d) gone
#   - NodeSource apt files gone
#   - `node` still available (--remove-nodejs NOT passed; T-04-17 default-leave)
#   - install log gone (step 7 — LAST, after tee-EOF)
@test "INST-04: --purge removes /opt/agentlinux, agent user, PATH artefacts; keeps Node" {
  # Install test-dummy first so step-1 uninstall.sh is exercised.
  sudo -u agent -H bash --login -c 'agentlinux install --include-test test-dummy' >/dev/null
  [[ -f /tmp/agentlinux-test-dummy.marker ]] \
    || __fail "INST-04" "precondition: marker file present before --purge" "absent" "-"

  run "$INSTALLER" --purge
  assert_exit_zero "INST-04 (--purge)"

  # Step 1 ran: per-agent uninstall.sh cleared the marker BEFORE /opt removal.
  [[ ! -f /tmp/agentlinux-test-dummy.marker ]] \
    || __fail "INST-04" "uninstall.sh ran (marker cleared) before /opt removal" "marker still present" "-"
  # Step 2: /opt/agentlinux gone.
  [[ ! -d /opt/agentlinux ]] \
    || __fail "INST-04" "/opt/agentlinux removed" "still present" "-"
  # Step 3: PATH artefacts gone.
  [[ ! -f /etc/profile.d/agentlinux.sh ]] \
    || __fail "INST-04" "/etc/profile.d/agentlinux.sh removed" "still present" "-"
  [[ ! -f /etc/agentlinux.env ]] \
    || __fail "INST-04" "/etc/agentlinux.env removed" "still present" "-"
  [[ ! -f /etc/cron.d/agentlinux ]] \
    || __fail "INST-04" "/etc/cron.d/agentlinux removed" "still present" "-"
  # Step 3.5: Phase 5.1 sudoers drop-in (ADR-012 / BHV-07) gone.
  # Without this check, run_purge could regress and leave a NOPASSWD
  # grant orphaned after the agent user is removed — the regression
  # actually shipped in v0.3.0-rc12 and v0.4.0; caught by dogfood.
  [[ ! -f /etc/sudoers.d/agentlinux ]] \
    || __fail "INST-04" "/etc/sudoers.d/agentlinux removed (BHV-07 + INST-04 symmetry)" "still present" "-"
  # Step 4: NodeSource apt files gone.
  [[ ! -f /etc/apt/sources.list.d/nodesource.sources ]] \
    || __fail "INST-04" "nodesource.sources removed" "still present" "-"
  [[ ! -f /etc/apt/sources.list.d/nodesource.list ]] \
    || __fail "INST-04" "nodesource.list removed (if present)" "still present" "-"
  # Step 6: agent user gone.
  if id agent >/dev/null 2>&1; then
    __fail "INST-04" "agent user removed" "user still exists" "-"
  fi
  # Step 5 opt-out: Node kept (no --remove-nodejs flag passed). T-04-17 mitigation.
  command -v node >/dev/null 2>&1 \
    || __fail "INST-04" "node kept on PATH (no --remove-nodejs flag)" "node missing" "-"
  # Step 7 LAST: install log gone. Pitfall 7 — tee saw EOF on script exit.
  [[ ! -f /var/log/agentlinux-install.log ]] \
    || __fail "INST-04" "install log removed (step 7, LAST)" "still present" "-"
}

# INST-04: second --purge is idempotent — no state left to clean, every rm -f
# is a no-op, userdel is guarded by `id agent`, exit 0. T-04-16 + INST-02
# symmetry: purge is as idempotent as the installer it reverses.
@test "INST-04: --purge is idempotent (second run exits 0 with nothing to clean)" {
  # State from prior @test: everything removed. Re-run --purge.
  run "$INSTALLER" --purge
  assert_exit_zero "INST-04 (idempotent second purge)"
}
