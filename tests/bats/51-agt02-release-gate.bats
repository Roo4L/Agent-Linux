#!/usr/bin/env bats
# tests/bats/51-agt02-release-gate.bats — Phase 5 canonical acceptance test.
#
# AGT-02: agent user can self-update Claude Code without sudo / EACCES.
# This is THE test that v0.3.0 exists to make green. It runs a REAL
# `claude update` against the live Anthropic CDN, captures the transcript,
# and asserts zero EACCES / "permission denied" lines.
#
# PLACED IN A SEPARATE FILE so Phase 6 CI can select it via:
#   bats tests/bats/51-*.bats
# for the TST-05 release-gate step. The file is named with a sortable prefix
# so the destructive test runs AFTER all non-destructive Phase 5 tests.
#
# Refs:
#   - docs/decisions/011-stability-first-version-pinning.md §Consequences
#     (AGT-02 is a permission invariant, not a version invariant)
#   - .planning/phases/05-agent-installability/05-RESEARCH.md §Pitfall 4
#     (dedicated transcript file for binary stdio interleaving)
#   - .planning/phases/05-agent-installability/05-RESEARCH.md §Pattern 8
#     (canonical shape; see also Anti-Pattern: don't loop over INVOKE_MODES)

load 'helpers/invoke_modes'
load 'helpers/assertions'

# AL-29: derive the catalog version from package.json — single SoT.
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

setup_file() {
  # 40-registry-cli.bats's INST-04 @tests run --purge at the end of that file
  # — filename sort puts 40-*.bats before 51-*.bats, so by the time we get
  # here the installer has been torn down (/opt/agentlinux gone, symlink gone,
  # agent user removed). Re-run agentlinux-install to restore state before
  # we can `agentlinux install --force claude-code`. If the symlink is still
  # present (e.g. this file is being run in isolation via `bats 51-*.bats`),
  # skip the re-install to keep setup_file fast.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi

  # Ensure claude-code is installed at the pinned version before exercising
  # the update path. If a previous 50-agents.bats run left it installed,
  # re-install with --force to guarantee we start at the pin (not at whatever
  # version a prior AGT-02 run bumped us to). Idempotent on first-run of this
  # file via `agentlinux install --force`.
  sudo -u agent -H bash --login -c 'agentlinux install --force claude-code' >/dev/null 2>&1
}

# AGT-02 is NOT looped across all six invocation modes — the update path is
# identical regardless of invocation mode; looping would multiply the network
# fetch time by 6. Sampling rate: one invocation per release-gate CI run.

@test "AGT-02 (release-gate): claude update exits 0 with zero EACCES/permission-denied lines" {
  local pinned
  pinned=$(jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' "$CATALOG")

  # Before-state: record current version for monotonicity check.
  local before_version
  before_version=$(sudo -u agent -H bash --login -c 'claude --version' | head -1)

  # Capture the update transcript to a dedicated log so assert_no_eacces
  # can inspect file rather than $output (more robust against binary stderr
  # interleaving; Pitfall 4).
  local transcript
  transcript=$(mktemp /tmp/agt02-claude-update.XXXXXX.log)

  # Bound wall-time to 120s: real update downloads ~8 MB binary; 120s gives
  # a safety margin against slow CI network + installer-side checksum verify.
  run bash -c "timeout 120s sudo -u agent -H bash --login -c 'claude update' >${transcript} 2>&1"

  # Primary assertion: exit 0. Non-zero = update failed (network, disk, perms).
  assert_exit_zero "AGT-02"

  # Canonical permission-invariant assertion (the whole reason v0.3.0 exists).
  assert_no_eacces "AGT-02" "$transcript"

  # Monotonicity: post-update version >= pinned. sort -V provides semver
  # ordering. If `claude update` is a no-op (already at latest),
  # after_version == before_version, which still satisfies >= pinned.
  local after_version
  after_version=$(sudo -u agent -H bash --login -c 'claude --version' | head -1)
  local pinned_v after_v
  pinned_v=$(printf '%s' "$pinned" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  after_v=$(printf '%s' "$after_version" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  # sort -V orders lowest first; if after_v is NOT less than pinned_v, head -1
  # returns pinned_v.
  local lowest
  lowest=$(printf '%s\n%s\n' "$pinned_v" "$after_v" | sort -V | head -1)
  if [[ "$lowest" != "$pinned_v" ]]; then
    __fail "AGT-02" \
      "after-update version >= pinned (${pinned_v})" \
      "after=${after_v}, before=${before_version}" \
      "$transcript"
  fi

  # Cleanup (only on pass — on failure leave the log for post-mortem).
  rm -f "$transcript"
}
