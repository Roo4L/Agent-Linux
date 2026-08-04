#!/usr/bin/env bats
# tests/bats/30-runtime.bats — Phase 3 runtime + per-user npm prefix behavior.
#
# Covers: RT-01 (Node LTS), RT-02 (install -g unprivileged across invocation
# modes + no-EACCES under npm pressure), RT-03 (uninstall byte-clean),
# RT-04 (prefix under /home/agent). All six INVOKE_MODES reused from
# tests/bats/helpers/invoke_modes.bash (shipped in Phase 2 Plan 02-05).
# Only new helper is assert_user_prefix_in_home (appended in Plan 03-02
# Task 1). Every @test name starts with its requirement ID so the TST-07
# behavior-coverage-auditor grep gate resolves.
#
# Preconditions (set up by tests/docker/run.sh before bats fires):
#   - agentlinux-install has already run: agent user exists, Node 22 LTS
#     installed via 30-nodejs.sh, ~agent/.npmrc carries
#     prefix=/home/agent/.npm-global, 40-path-wiring.sh has prepended
#     /home/agent/.npm-global/bin FIRST across profile.d + agentlinux.env +
#     cron.d.
#   - cowsay is NOT installed at test start (CAT-02 contract — no default
#     agents). setup_file installs it; teardown_file best-effort removes it.
#
# Sudo invocation shape note: every `sudo -u agent -H bash --login -c`
# call below matches the run_sudo_u helper's working shape from Phase 2
# (STATE.md 02-05 deviation: non-login bash -c is broken under Ubuntu's
# default sudoers secure_path; --login triggers profile.d which carries
# the npm-global PATH prepend). The inner command runs AS AGENT because
# the OUTER sudo -u agent switched the user — so the inner `npm install -g`
# is an agent-user invocation, never a sudo-npm invocation.
#
# Refs: 03-RESEARCH.md §Architecture Patterns → Pattern 3 + Pattern 4;
#       §Code Examples §Example 3.

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log

setup_file() {
  # Install cowsay once for the entire file (no per-test reinstalls). The
  # outer `sudo -u agent -H bash --login -c` drops privilege BEFORE npm
  # runs — so the npm process is an agent-user process and writes to
  # /home/agent/.npm-global (agent-owned prefix from 30-nodejs.sh).
  sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0' 2>&1 || true
}

teardown_file() {
  # Hygiene: best-effort uninstall so repeat bats runs start clean. Exit
  # code ignored because RT-03 may already have uninstalled mid-file.
  sudo -u agent -H bash --login -c 'npm uninstall -g cowsay' 2>&1 || true
}

# --- RT-01 ------------------------------------------------------------------
# Observable: `node --version` returns v22.* in every invocation mode.

@test "RT-01: agent user sees node v22 LTS in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'node --version'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "RT-01 (${mode}): systemd PID 1 not running in this environment"
    fi
    assert_exit_zero "RT-01 (${mode})"
    # Strong assertion: observed version STARTS WITH v22. (MAJOR-only per
    # RESEARCH Open Question 4 — patch bumps must not break the test.)
    if ! printf '%s' "${output:-}" | grep -Eq '^v22\.'; then
      __fail "RT-01 (${mode})" \
        "node --version starts with v22." \
        "${output:-<empty>}" \
        "$LOG"
    fi
  done
}

# --- RT-04 ------------------------------------------------------------------
# Observable: `npm config get prefix` returns a path under /home/agent/ in
# every invocation mode. Keystone ownership proof (ADR-004).

@test "RT-04: npm config get prefix is under /home/agent in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'npm config get prefix'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "RT-04 (${mode}): systemd PID 1 not running in this environment"
    fi
    assert_exit_zero "RT-04 (${mode})"
    assert_user_prefix_in_home "RT-04 (${mode})"
  done
}

# --- RT-02 ------------------------------------------------------------------
# Observable: `command -v cowsay` resolves under /home/agent/.npm-global/bin
# AND `cowsay hi` runs successfully. Six-mode loop.

@test "RT-02: cowsay binary resolves to /home/agent/.npm-global/bin in every mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'command -v cowsay'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "RT-02 (${mode}): systemd PID 1 not running in this environment"
    fi
    assert_exit_zero "RT-02 (${mode})"
    assert_path_has "RT-02 (${mode})" "/home/agent/.npm-global/bin/cowsay"

    # Second strong assertion: the binary RUNS and cowsay echoes the text
    # (inside the ASCII cow). If the binary is a broken shim or mis-linked
    # lib, `cowsay hi` fails even though `command -v` succeeded.
    invoke_mode "$mode" 'cowsay hi'
    assert_exit_zero "RT-02 (${mode})"
    assert_path_has "RT-02 (${mode})" "hi"
  done
}

# --- RT-02 (reinforcement: no EACCES under npm install pressure) -----------
# INST-05 reinforcement per VALIDATION task 03-02-05. A second install is
# a no-op for npm — but it re-exercises the write path to
# /home/agent/.npm-global/ and catches any permission regression between
# the provisioner's initial install and bats run time.

@test "RT-02: no EACCES during cowsay re-install (INST-05 under npm pressure)" {
  run sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0 2>&1'
  assert_exit_zero "RT-02 (re-install no-eacces)"
  assert_no_eacces "RT-02" "${output:-}"
}

# --- RT-03 ------------------------------------------------------------------
# Observable: after `npm uninstall -g cowsay`, filesystem is byte-clean
# (cowsay, cowthink, AND the lib module directory all absent) AND cowsay
# does NOT resolve on PATH in any invocation mode.
#
# Pitfall 9: cowsay@1.6.0 ships TWO bin entries (cowsay AND cowthink); a
# cleanliness check that only looks at `cowsay` would miss a partial-uninstall
# regression. This test catches it by checking BOTH.

@test "RT-03: npm uninstall -g cowsay leaves no trace" {
  # Uninstall once (merged stdout+stderr).
  run sudo -u agent -H bash --login -c 'npm uninstall -g cowsay 2>&1'
  assert_exit_zero "RT-03 (uninstall)"
  assert_no_eacces "RT-03" "${output:-}"

  # Strongest form of the cleanliness contract: three filesystem paths
  # (Pitfall 8 + Pitfall 9 — both bins + the lib module dir) are absent.
  local target
  for target in /home/agent/.npm-global/bin/cowsay \
                /home/agent/.npm-global/bin/cowthink \
                /home/agent/.npm-global/lib/node_modules/cowsay; do
    if [[ -e $target ]]; then
      __fail "RT-03 (filesystem)" \
        "no trace of cowsay/cowthink under /home/agent/.npm-global" \
        "observed: ${target} still exists" \
        "$LOG"
    fi
  done

  # Not-on-PATH assertion across every invocation mode. The `|| echo NOT-FOUND`
  # keeps the command exit code 0 so the sudo/ssh/cron wrapper stays in the
  # happy path; the output-check is what carries the signal.
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'command -v cowsay || echo NOT-FOUND'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "RT-03 (${mode}): systemd PID 1 not running in this environment"
    fi
    if printf '%s' "${output:-}" | grep -q '/cowsay'; then
      __fail "RT-03 (${mode})" \
        "cowsay NOT findable on PATH after uninstall" \
        "found: ${output:-<empty>}" \
        "$LOG"
    fi
  done

  # Re-install for hygiene so a hypothetical later test in this file sees
  # cowsay present. Best-effort; doesn't affect RT-03's own pass/fail.
  sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0' >/dev/null 2>&1 || true
}
