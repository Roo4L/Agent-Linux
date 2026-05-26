#!/usr/bin/env bats
# tests/bats/51-cc-no-autoupdate.bats — behavioral pair for AGT-02c.
#
# AGT-02d: the runtime effect of the DISABLE_AUTOUPDATER stamp. AGT-02b proves
# `claude --version` matches the catalog pin at install time; AGT-02c proves
# the stamp is WRITTEN; AGT-02d proves the stamp's RUNTIME EFFECT — the
# binary does not drift forward over a 90s idle interactive session (which
# it would otherwise, given a valid login + sandbox key).
#
# Red-green pair design:
#   PHASE 1 (RED, control): strip the stamp, idle 90s, observe drift > 0.
#     Without this control, PHASE 2 passes vacuously (no drift could mean
#     "stamp works" OR "updater never fires for unrelated reasons").
#   PHASE 2 (GREEN, fix-acceptance): re-stamp, idle 90s, observe zero drift.
#
# Skip-yellow path:
#   setup_file → require_secret ANTHROPIC_API_KEY → skip if unset/empty.
#   Per-PR Docker CI never sees the key; AGT-02d skips yellow there.
#   Release-gate (nightly-qemu) sees the key via the workflow-env + ssh
#   SendEnv path; AGT-02d runs green there.
#
# Wall-clock budget: two 90s idle windows + login + version checks ≈ 200s
# per test file. The release-gate workflow timeout is 45min total across
# the matrix; 200s is well within budget for a single matrix leg.
#
# Refs:
#   - .claude/skills/behavior-test-contract/SKILL.md (ID-in-@test-name)
#   - docs/internals/test-interactive.md (helper contract)
#   - docs/internals/test-secrets.md (the secret pipeline being consumed)

load 'helpers/invoke_modes'
load 'helpers/assertions'
load 'helpers/secrets'
load 'helpers/interactive'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
SETTINGS=/home/agent/.claude/settings.json

setup_file() {
  # Skip yellow if no key — gates EVERY @test in the file when bats sees
  # `skip` inside setup_file (bats >=1.5 behavior). On per-PR Docker CI
  # the key is never provisioned, so the file skips cleanly without
  # touching the installer state at all.
  require_secret ANTHROPIC_API_KEY

  # Recovery primitives mirror 51-agt02-release-gate.bats setup_file:
  # filename sort puts 40-*.bats (INST-04 --purge) before 51-*.bats, so by
  # the time we get here the installer may have been torn down. Re-run
  # plugin/bin/agentlinux-install when the agentlinux symlink is absent.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi

  # Re-install at the catalog-pinned version with --force so we start at a
  # known floor. The DISABLE_AUTOUPDATER stamp is written here by install.sh.
  sudo -u agent -H bash --login -c 'agentlinux install --force claude-code' >/dev/null 2>&1

  # Authenticate once per file via the interactive helper. claude_login
  # reads ANTHROPIC_API_KEY from env (no argv exposure) and the .exp
  # script's log_user 0 keeps the key off stdout.
  if ! claude_login; then
    # The .exp script's diagnostics already went to stderr (redacted).
    # Skip rather than fail: a Claude API outage or upstream prompt
    # rewording is a transient environmental issue, NOT a regression
    # in the AL-51 fix being verified.
    skip "claude_login failed (transient Anthropic API or upstream prompt change; see docs/internals/test-interactive.md)"
  fi
}

teardown_file() {
  # Restore the stamp to whatever install.sh writes — symmetric with the
  # disturbance PHASE 1 introduces. Re-running --force claude-code is the
  # blunt-and-correct primitive (matches 51-agt02-release-gate.bats's
  # "leave the install in a known state" teardown philosophy).
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux install --force claude-code' >/dev/null 2>&1 || true
  fi
}

@test "AGT-02d: claude binary does not drift forward over 90s idle when DISABLE_AUTOUPDATER stamp is present (with red-phase control)" {
  local pinned before_v after_v_phase1 after_v_phase2

  pinned=$(jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' "$CATALOG")
  before_v=$(sudo -u agent -H bash --login -c 'claude --version' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  # ----------------------------------------------------------------------
  # PHASE 1 (RED, control): strip the stamp, idle 90s, version SHOULD drift.
  # If it doesn't, the test environment lacks something the updater needs
  # (network, valid auth, time-of-day update window) — and PHASE 2 below
  # would pass vacuously. Fail loud here so a substrate change is caught.
  # ----------------------------------------------------------------------
  sudo -u agent -H rm -f "$SETTINGS"

  if ! claude_idle_for 90; then
    __fail "AGT-02d" \
      "claude_idle_for 90 returned 0 (clean Ctrl-D + EOF)" \
      "claude_idle_for failed; see helpers/expect/claude-idle.exp stderr" \
      "$LOG"
  fi

  after_v_phase1=$(sudo -u agent -H bash --login -c 'claude --version' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  # Drift = after_v_phase1 > before_v (sort -V semver order). If they're
  # equal, the updater did not fire — control invalid; the GREEN phase
  # below would pass for the wrong reason. Fail loud naming both versions
  # (version numbers, not secrets, so no redaction needed).
  local lowest
  lowest=$(printf '%s\n%s\n' "$before_v" "$after_v_phase1" | sort -V | head -1)
  if [[ "$lowest" != "$before_v" ]] || [[ "$after_v_phase1" == "$before_v" ]]; then
    __fail "AGT-02d (RED control)" \
      "binary drifts forward (after > before) when stamp absent + 90s idle" \
      "before=${before_v} after=${after_v_phase1} (no drift — control invalid)" \
      "$LOG"
  fi

  # ----------------------------------------------------------------------
  # PHASE 2 (GREEN, fix-acceptance): re-stamp, idle 90s, version MUST NOT drift.
  # ----------------------------------------------------------------------
  # Reset to the pin and re-write the stamp via --force install.
  sudo -u agent -H bash --login -c 'agentlinux install --force claude-code' >/dev/null 2>&1

  # Confirm the stamp is present before idling (gate AGT-02c shares).
  local stamped
  stamped=$(sudo -u agent -H bash --login -c "jq -r '.env.DISABLE_AUTOUPDATER // empty' $SETTINGS 2>/dev/null")
  if [[ "$stamped" != "1" ]]; then
    __fail "AGT-02d (GREEN gate)" \
      ".env.DISABLE_AUTOUPDATER == 1 after re-install" \
      "stamped=${stamped:-<empty>}" \
      "$LOG"
  fi

  local before_v_phase2
  before_v_phase2=$(sudo -u agent -H bash --login -c 'claude --version' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if ! claude_idle_for 90; then
    __fail "AGT-02d (GREEN idle)" \
      "claude_idle_for 90 returned 0 (clean Ctrl-D + EOF)" \
      "claude_idle_for failed; see helpers/expect/claude-idle.exp stderr" \
      "$LOG"
  fi

  after_v_phase2=$(sudo -u agent -H bash --login -c 'claude --version' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  # GREEN assertion: zero drift across the idle window with the stamp present.
  if [[ "$before_v_phase2" != "$after_v_phase2" ]]; then
    __fail "AGT-02d" \
      "no drift with DISABLE_AUTOUPDATER=1 stamp across 90s idle (before == after)" \
      "before=${before_v_phase2} after=${after_v_phase2}" \
      "$LOG"
  fi

  # pinned is asserted at install time by AGT-02b — referenced here so the
  # variable is materialized (`sort -V` semver compare would be a future
  # tightening; today's invariant is just "no drift from the install-time
  # state when stamped").
  [[ -n "$pinned" ]] || __fail "AGT-02d (catalog gate)" \
    "pinned_version present in catalog" "<empty>" "$LOG"
}
