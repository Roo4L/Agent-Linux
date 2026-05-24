#!/usr/bin/env bats
# tests/bats/50-agents.bats — Phase 5 integration: AGT-01, AGT-02b, AGT-03, AGT-04, AGT-05.
#
# Non-destructive tests. AGT-02 (real self-update path) lives in
# tests/bats/51-agt02-release-gate.bats so Phase 6 CI can select it via
# `bats tests/bats/51-*.bats` for the TST-05 release-gate step. The filename
# sort puts 50-*.bats BEFORE 51-*.bats, so 50's tests get first crack at the
# install state, and 51's destructive self-update test never contaminates the
# AGT-02b pinned-version assertion here.
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - setup_file installs all three agents ONCE for the whole file; teardown_file
#     removes them. Serial installs keep sentinel writes unambiguous.
#   - version pins are read from /opt/agentlinux/catalog/0.3.0/catalog.json via
#     jq — NEVER hardcoded in @test bodies (so a catalog version bump does not
#     require editing this file).
#
# Refs:
#   - .claude/skills/behavior-test-contract/SKILL.md (ID-in-@test-name required)
#   - 05-RESEARCH.md §Pattern 7 (canonical skeleton for this file)
#   - tests/bats/40-registry-cli.bats (setup_file/teardown_file precedent)
#   - tests/bats/51-agt02-release-gate.bats (sibling destructive test file)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
CATALOG=/opt/agentlinux/catalog/0.3.0/catalog.json

setup_file() {
  # 40-registry-cli.bats's INST-04 --purge @tests run earlier in filename sort
  # and can destroy /opt/agentlinux + the /home/agent/.npm-global/bin/agentlinux
  # symlink + the agent user. Recovery pattern mirrors 51-agt02-release-gate.bats
  # setup_file: when the agentlinux symlink is absent, re-run the raw installer
  # so `agentlinux install <id>` below has a working dispatch surface.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi

  # SSH keypair recovery: 20-agent-user.bats's setup() generates /root/.ssh/
  # id_ed25519 + /home/agent/.ssh/authorized_keys for BHV-02's run_ssh helper.
  # 40-*.bats's INST-04 --purge runs `userdel -r agent` which deletes
  # /home/agent/ (including ~/.ssh/authorized_keys). The re-provisioner above
  # re-creates /home/agent (empty skel) but does NOT re-authorize the keypair
  # — that's test-harness setup, not installer scope. AGT-01's ssh mode needs
  # the authorization restored, so re-install the pubkey when absent. The
  # /root/.ssh/id_ed25519 pair survives --purge (root's $HOME is untouched).
  if [[ -f /root/.ssh/id_ed25519.pub ]] \
    && [[ ! -f /home/agent/.ssh/authorized_keys ]]; then
    install -d -m 0700 -o agent -g agent /home/agent/.ssh
    install -m 0600 -o agent -g agent \
      /root/.ssh/id_ed25519.pub /home/agent/.ssh/authorized_keys
    systemctl start ssh >/dev/null 2>&1 || true
    # Wait up to 5s for sshd to accept connections (mirrors 20-*.bats setup).
    for _ in $(seq 1 5); do
      if ss -lnt 2>/dev/null | grep -q ':22 '; then break; fi
      sleep 1
    done
  fi

  # Install all three agents once for the file. Each @test assumes the install
  # has already happened; we trade setup-file time for test-case simplicity.
  # Serial installs keep sentinel writes unambiguous (no flock dance).
  sudo -u agent -H bash --login -c 'agentlinux install claude-code' >/dev/null 2>&1
  sudo -u agent -H bash --login -c 'agentlinux install gsd' >/dev/null 2>&1
  sudo -u agent -H bash --login -c 'agentlinux install playwright' >/dev/null 2>&1
}

teardown_file() {
  # Symmetric removal so downstream @test files see a clean slate.
  # Guard on agentlinux binary presence — INST-04 --purge from any earlier
  # test run may have removed it; in that case teardown is a no-op.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force claude-code' >/dev/null 2>&1 || true
    sudo -u agent -H bash --login -c 'agentlinux remove --force gsd' >/dev/null 2>&1 || true
    sudo -u agent -H bash --login -c 'agentlinux remove --force playwright' >/dev/null 2>&1 || true
  fi
}

# ---------- AGT-01: six-mode loop × three agents ----------

# AGT-01: `claude --version` resolves AND prints a semver-shaped string in all
# six invocation modes (interactive, ssh, cron, systemd_user, sudo_u, sudo_u_i).
# The additional semver-shape regex check defends against a silent regression
# where the binary exits 0 but emits empty output (prevents false-pass on a
# mis-symlinked wrapper).
@test "AGT-01: claude --version exits 0 in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'claude --version'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "AGT-01 (${mode}): systemd PID 1 not running in this container"
    fi
    assert_exit_zero "AGT-01 (${mode})"
    # Additional invariant: the output contains digits+dots (a plausible version).
    # Prevents false-positive on a binary that exits 0 but prints nothing.
    if ! printf '%s' "${output}" | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+'; then
      __fail "AGT-01 (${mode})" \
        "claude --version prints a semver-shaped string" \
        "${output:-<empty>}" \
        "$LOG"
    fi
  done
}

# AGT-01 (gsd): `get-shit-done-cc --help` exits 0 in all six invocation modes.
# `--help` is used instead of `--version` because the package has no `--version`
# flag (verified via `npm view get-shit-done-cc bin` — only the `get-shit-done-cc`
# entry, no separate version-reporter). Post-install verify in the recipe relies
# on the banner-grep; here AGT-01 just proves PATH-resolution under every mode.
@test "AGT-01: get-shit-done-cc --help exits 0 in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'get-shit-done-cc --help'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "AGT-01 (${mode}): systemd PID 1 not running"
    fi
    assert_exit_zero "AGT-01/GSD (${mode})"
  done
}

# AGT-01 (playwright): `npx playwright --version` exits 0 in all six modes.
# Using `npx --yes` forces non-interactive (no "install this package?" prompt)
# even though the CLI is already globally installed by setup_file — matches
# how cron/systemd units would invoke it. The setup_file install lands the
# playwright binary at /home/agent/.npm-global/bin/playwright; npx resolves
# to that same path but exercises the full CLI surface (bindings + browsers).
@test "AGT-01: npx playwright --version exits 0 in every invocation mode" {
  local mode
  for mode in "${INVOKE_MODES[@]}"; do
    invoke_mode "$mode" 'npx --yes playwright --version'
    if [[ "${output:-}" == *SKIP_SYSTEMD_UNAVAILABLE* ]]; then
      skip "AGT-01 (${mode}): systemd PID 1 not running"
    fi
    assert_exit_zero "AGT-01/Playwright (${mode})"
  done
}

# ---------- AGT-02b: claude --version matches pinned_version from catalog ----------

# AGT-02b: ADR-011 stability-first mechanism proven end-to-end. `claude --version`
# output must contain the catalog's pinned_version substring (NOT an exact-string
# compare — upstream format may be "X.Y.Z (Claude Code)" or similar). This is
# the bats-side companion to install.sh's in-recipe version-lock grep; the
# in-recipe assertion fails fast at install time if upstream drifts, this
# assertion proves the post-install observable state matches the pin.
@test "AGT-02b: claude --version returns exactly pinned_version from catalog.json" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' "$CATALOG")
  run sudo -u agent -H bash --login -c 'claude --version'
  assert_exit_zero "AGT-02b"
  # Exact-string presence: the version token must appear as a substring.
  # We don't assert full equality because upstream format may be "X.Y.Z (Claude Code)".
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "AGT-02b" \
      "claude --version contains pinned=${pinned}" \
      "${output:-<empty>}" \
      "$LOG"
  fi
}

# ---------- AGT-03: claude diagnostic (substituted by --help; see research §Open Q2) ----------

# AGT-03: `claude doctor` waits for stdin (github.com/anthropics/claude-code/
# issues/26487), unusable in bats non-interactive context. `claude --help` is
# the closest scriptable positive-signal substitute: exits 0, rich output, no
# network. Negative assertions catch error-path leakage without requiring an
# exact output shape (which would couple this test to upstream CLI wording).
#
# NOTE on regex shape: we check for failure-prefix patterns (`error:`, `Error:`,
# `ERROR:`), not the bare word "error" — upstream help text legitimately names
# options like `--mcp-debug` whose description contains the NOUN "errors"
# ("shows MCP server errors"). A case-insensitive `error` match would fail
# healthy --help output. Standard CLI failure convention is `<name>: error:
# <message>`, so the colon anchor is the right boundary. Stack traces (Python
# `traceback`) and filesystem perm errors (`permission denied`, `EACCES`) are
# distinctive enough to match case-insensitively without false positives.
@test "AGT-03: claude --help exits 0 and prints no error strings" {
  run sudo -u agent -H bash --login -c 'claude --help'
  assert_exit_zero "AGT-03"
  # Negative asserts: failure-shape patterns, not the noun "error".
  if printf '%s' "${output:-}" | grep -Eq 'error:|Error:|ERROR:|Traceback|traceback \(' \
    || printf '%s' "${output:-}" | grep -Eiq 'permission denied|EACCES'; then
    __fail "AGT-03" \
      "claude --help output free of error:/EACCES/permission-denied strings" \
      "${output}" \
      "$LOG"
  fi
}

# ---------- AGT-04: gsd version-equivalent smoke ----------

# AGT-04: get-shit-done-cc has no --version flag; its --help banner prints
# "Get Shit Done v<pinned>" (verified: ANSI-color-wrapped, head -20 captures
# it, grep -F matches through ANSI codes). This is the version-lock mechanism
# for the gsd agent. Catalog-driven pin lookup (no hardcoding) so a version
# bump updates the assertion without editing this file.
@test "AGT-04: get-shit-done-cc --help banner reports pinned version" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="gsd") | .pinned_version' "$CATALOG")
  run sudo -u agent -H bash --login -c 'get-shit-done-cc --help'
  assert_exit_zero "AGT-04"
  # GSD has no --version flag; its banner prints "Get Shit Done vX.Y.Z".
  if ! printf '%s' "${output}" | grep -q -F -- "v${pinned}"; then
    __fail "AGT-04" \
      "get-shit-done-cc --help banner contains v${pinned}" \
      "${output:-<empty>}" \
      "$LOG"
  fi
}

# ---------- AGT-05: playwright + chromium ----------

# AGT-05 (version): `npx playwright --version` output must contain the pinned
# version substring. Catalog-driven pin lookup mirrors AGT-02b/AGT-04.
@test "AGT-05: npx playwright --version exits 0 with pinned version string" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="playwright") | .pinned_version' "$CATALOG")
  run sudo -u agent -H bash --login -c 'npx --yes playwright --version'
  assert_exit_zero "AGT-05"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "AGT-05" \
      "playwright --version contains pinned=${pinned}" \
      "${output:-<empty>}" \
      "$LOG"
  fi
}

# AGT-05 (chromium cache): install.sh's third step already downloaded chromium
# into ~agent/.cache/ms-playwright/chromium-<rev>. Re-verify the dir exists AND
# is owned by `agent` (NOT root — the ADR-004 keystone: no wrapper shim + no
# root-owned agent-runtime). `stat -c '%U'` prints the owner username; owner
# mismatch flags a sudo-path bug in the Playwright install-deps hook.
@test "AGT-05: chromium cached under ~agent/.cache/ms-playwright (no sudo/EACCES)" {
  # Install.sh already downloaded chromium. Re-verify cache exists and is
  # agent-owned (ADR-004 keystone).
  run sudo -u agent -H bash --login -c 'find /home/agent/.cache/ms-playwright -maxdepth 1 -type d -name "chromium-*" | head -1'
  assert_exit_zero "AGT-05"
  if [[ -z "${output}" ]]; then
    __fail "AGT-05" \
      "at least one chromium-* dir under ~agent/.cache/ms-playwright" \
      "none" \
      "$LOG"
  fi
  # Ownership check: chromium dir must be agent:agent (not root-owned via
  # a sudo-path bug). stat -c '%U' prints owner username.
  local owner
  owner=$(stat -c '%U' "${output}")
  if [[ "$owner" != "agent" ]]; then
    __fail "AGT-05" \
      "chromium cache owned by agent" \
      "owner=${owner} (path: ${output})" \
      "$LOG"
  fi
}

# AGT-05 (idempotency): CLI-03's "already installed" short-circuit must hold
# on a real (non-test-dummy) agent. setup_file already installed; a second
# invocation with the same pin must print "already installed" and NOT re-download
# chromium (~281 MB). This is the real-agent twin of 40-*.bats's test-dummy
# CLI-03 idempotency @test.
@test "AGT-05: re-install playwright is idempotent (CLI-03 invariant on real agent)" {
  # setup_file already installed; a second install with the same pin should
  # print "already installed" and not re-download chromium.
  run sudo -u agent -H bash --login -c 'agentlinux install playwright'
  assert_exit_zero "AGT-05 re-install"
  echo "$output" | grep -q 'already installed' \
    || __fail "AGT-05" "idempotent re-install prints 'already installed'" "${output:-<empty>}" "$LOG"
}
