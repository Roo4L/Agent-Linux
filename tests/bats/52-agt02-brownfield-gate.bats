#!/usr/bin/env bats
# tests/bats/52-agt02-brownfield-gate.bats — Phase 16 milestone-close gate.
#
# brownfield-AGT-02: pre-populated host (manual agent user + NodeSource Node 22
# + claude-code at PATH-MISMATCH location + gsd + playwright-cli) MUST complete
# `agentlinux install --yes` AND `claude update` against the live Anthropic CDN
# MUST exit 0 with zero EACCES/permission-denied lines, AND version monotonicity
# MUST hold (post-update version >= pre-update version via sort -V).
#
# This is v0.3.4's TST-07 equivalent — the release-readiness gate. The captured
# transcript is written to docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md
# and committed alongside this test as the milestone-close evidence artifact.
#
# GREENFIELD INVARIANT (D-16-08): tests/bats/51-agt02-release-gate.bats remains
# UNCHANGED — this is the brownfield counterpart, additive only.
#
# Live-CDN dependency (T-16-01-01): set AGENTLINUX_SKIP_CDN_TESTS=1 to skip
# both @tests during Anthropic CDN outages (operationally-supported escape hatch).
#
# Refs:
#   - tests/bats/51-agt02-release-gate.bats (shape reference — greenfield gate)
#   - .planning/phases/16-documentation-brownfield-acceptance/16-CONTEXT.md (D-16-03, D-16-09)
#   - docs/decisions/011-stability-first-version-pinning.md §Consequences (AGT-02 = permission invariant)

# T-16-01-06: bats-core serializes within a file by default; this var makes the
# requirement explicit + forward-compatible if defaults change. shellcheck
# does not know bats reads this env at file scope.
# shellcheck disable=SC2034
BATS_NO_PARALLELIZE_WITHIN_FILE=1

load 'helpers/assertions'
load 'helpers/brownfield'

# AL-29: derive the catalog version from package.json — single SoT (matches 51-*'s pattern).
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

# teardown_file invariant — restore canonical post-installer state so downstream
# bats files see the same shape the docker harness staged for them. Mirrors
# 14-remediate.bats's teardown discipline + 15-preflight-ux.bats's.
teardown_file() {
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  bash "$INSTALLER" >/dev/null 2>&1 || true
}

@test "BHV-52a (brownfield-AGT-02 milestone-close gate): pre-populated host + agentlinux install --yes + claude update zero EACCES + version monotonicity + transcript captured" {
  if [[ "${AGENTLINUX_SKIP_CDN_TESTS:-0}" == "1" ]]; then
    skip "CDN tests disabled (AGENTLINUX_SKIP_CDN_TESTS=1) — T-16-01-01 offline fallback"
  fi

  # Step 1: pre-populate the host with all 5 brownfield artifacts.
  setup_brownfield_host_full

  # Step 2: run the installer with --yes to opt into REMEDIATE-04 reinstall
  # of claude-code at the canonical path. Non-TTY context (bats subshell);
  # without --yes this would correctly bail with exit 65 per UX-03.
  run bash "$INSTALLER" --yes
  [[ "$status" -eq 0 ]] || {
    printf 'agentlinux install --yes FAILED (status=%d):\n%s\n' "$status" "$output" >&2
    false
  }

  # Step 3: capture pre-update version for monotonicity check.
  local pre_version
  pre_version=$(sudo -u agent -H bash --login -c 'claude --version' 2>/dev/null | head -1)

  # Step 4: run claude update against the live Anthropic CDN. Capture
  # transcript to a dedicated file (Pitfall 4 — binary stdio interleave
  # mitigation; same shape as 51-agt02-release-gate.bats:65).
  local transcript
  transcript=$(mktemp /tmp/brownfield-agt02-claude-update.XXXXXX.log)
  run bash -c "timeout 120s sudo -u agent -H bash --login -c 'claude update' >${transcript} 2>&1"

  # Step 5: primary assertions — same shape as greenfield 51-*.bats.
  assert_exit_zero "brownfield-AGT-02"
  assert_no_eacces "brownfield-AGT-02" "$transcript"

  # Step 6: version monotonicity (sort -V; matches 51-*.bats:78-94).
  local post_version pinned pinned_v post_v lowest
  post_version=$(sudo -u agent -H bash --login -c 'claude --version' 2>/dev/null | head -1)
  pinned=$(jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' "$CATALOG")
  pinned_v=$(printf '%s' "$pinned" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  post_v=$(printf '%s' "$post_version" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  lowest=$(printf '%s\n%s\n' "$pinned_v" "$post_v" | sort -V | head -1)
  [[ "$lowest" == "$pinned_v" ]] || {
    printf 'monotonicity violated: pinned=%s post=%s pre=%s\n' \
      "$pinned_v" "$post_v" "$pre_version" >&2
    false
  }

  # Step 7: capture the transcript to the milestone-close audit doc (D-16-09).
  # `run` re-binds $output, so re-read the transcript file into $output via
  # a no-op `run cat` so capture_transcript_to picks it up.
  run cat "$transcript"
  capture_transcript_to \
    docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md \
    "$pre_version" \
    "$post_version"

  # Cleanup the tmp transcript (the committed audit doc holds the canonical copy).
  rm -f "$transcript"
}

@test "BHV-52b (setup_brownfield_host_full helper validation): all 5 brownfield artifacts present after setup" {
  if [[ "${AGENTLINUX_SKIP_CDN_TESTS:-0}" == "1" ]]; then
    skip "CDN tests disabled — npm registry dependency"
  fi

  setup_brownfield_host_full

  # Artifact 1: agent user with /bin/bash + writable home.
  id -u agent
  [[ "$(getent passwd agent | cut -d: -f7)" == "/bin/bash" ]]
  sudo -u agent -H test -w /home/agent

  # Artifact 2: canonical ADR-012 sudoers drop-in.
  [[ -f /etc/sudoers.d/agentlinux ]]
  grep -Fx 'agent ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/agentlinux

  # Artifact 3: NodeSource Node 22 (apt-installed).
  dpkg-query -W -f='${Status}' nodejs | grep -q "install ok installed"
  sudo -u agent -H bash --login -c 'node --version' | grep -Eq '^v22\.'

  # Artifact 4: claude-code at PATH-MISMATCH location (npm-global, not native).
  sudo -u agent -H test -x /home/agent/.npm-global/bin/claude

  # Artifact 5: gsd + playwright-cli at canonical npm-global path.
  sudo -u agent -H test -x /home/agent/.npm-global/bin/get-shit-done-cc
  sudo -u agent -H test -x /home/agent/.npm-global/bin/playwright-cli

  # Pre-existing user-data marker survives setup (CAT-04 fixture seed).
  [[ -f /home/agent/.claude/test-marker-file ]]
  grep -Fxq 'preserve-this-test-marker-content-line' /home/agent/.claude/test-marker-file
}
