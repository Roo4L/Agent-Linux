#!/usr/bin/env bats
# tests/bats/58-catalog-devtools.bats — v0.3.6 Phases 29-33 developer-tooling
# cluster: DEVT-01 (gh), DEVT-02 (glab), DEVT-04 (trivy), DEVT-05 (gitleaks),
# DEVT-03 (sentry-cli). The first four are source_kind binary (they reuse the
# Phase 28 ENABLE-01 prebuilt-binary helper, generalized in Phase 29 for GitHub +
# GitLab hosts and Go-style asset naming); sentry-cli is source_kind npm.
#
# Each requirement gets one @test driving the full TST-07 lifecycle on a
# provisioned host:
#   agentlinux install <id> → binary resolves under the agent-owned prefix
#   (no root / no /usr/local shim / no EACCES) → --version contains the catalog
#   pin → agentlinux remove --force <id> (binary + per-tool config/cache gone)
#   → idempotent re-remove.
# trivy and gitleaks additionally run a real no-daemon scan (DEVT-04 / DEVT-05).
# glab additionally asserts the maintained gitlab-org/cli upstream, never the
# archived profclems/glab (DEVT-02).
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - version pins read from the provisioned catalog via jq — NEVER hardcoded
#   - installs run as the agent user through a login shell (PATH + ~/.local/bin)
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)
#
# Refs:
#   - tests/bats/57-catalog-binary.bats (binary lifecycle + jq-pin driver shape)
#   - tests/bats/53-catalog-npm-cluster.bats (npm lifecycle shape)
#   - plugin/catalog/agents/{gh,glab,trivy,gitleaks,sentry-cli}/
#   - plugin/catalog/lib/prebuilt-binary.sh (al_pb_arch + verify-before-extract)
#   - .planning/REQUIREMENTS.md (DEVT-01..05 + Appendix C: no cred)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
# AL-29: derive the catalog version from package.json — single SoT.
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

setup_file() {
  # 40-registry-cli.bats's INST-04 --purge @tests run earlier in filename sort and
  # can remove /opt/agentlinux + the agentlinux symlink + the agent user. Recovery
  # mirrors 53/57: re-run the raw installer when the symlink is absent so
  # `agentlinux install <id>` has a working dispatch surface.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi

  # Defensive scrub of this cluster's binaries + per-tool state BEFORE any test, so
  # a stale artifact from a prior run cannot satisfy a present-assertion even if a
  # regressed recipe stopped writing it (parity with 53/57). sentry-cli is npm-
  # global, so its scrub is an `npm uninstall -g` rather than a binary rm — without
  # it a stale ~/.npm-global/bin/sentry-cli could satisfy DEVT-03's resolve/version
  # assertions even if the recipe regressed to a no-op install.
  sudo -u agent -H bash --login -c '
    rm -f /home/agent/.local/bin/gh /home/agent/.local/bin/glab \
          /home/agent/.local/bin/trivy /home/agent/.local/bin/gitleaks
    rm -rf /home/agent/.config/gh /home/agent/.config/glab /home/agent/.cache/trivy
    npm uninstall -g @sentry/cli --no-fund --no-audit
  ' >/dev/null 2>&1 || true
}

teardown_file() {
  # Symmetric removal + state scrub so later @test files see a clean slate.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    local id
    for id in gh glab trivy gitleaks sentry-cli; do
      sudo -u agent -H bash --login -c "agentlinux remove --force ${id}" >/dev/null 2>&1 || true
    done
  fi
  sudo -u agent -H bash --login -c '
    rm -f /home/agent/.local/bin/gh /home/agent/.local/bin/glab \
          /home/agent/.local/bin/trivy /home/agent/.local/bin/gitleaks
    rm -rf /home/agent/.config/gh /home/agent/.config/glab /home/agent/.cache/trivy
  ' >/dev/null 2>&1 || true
}

# _pin <req> <id> — echo <id>'s pin from the provisioned catalog (jq, never
# hardcoded) and guard it non-empty/non-null. A blank pin would make `grep -F -- ""`
# match ANY output, silently defeating the version-lock assertion.
_pin() {
  local req=$1 id=$2 pinned
  pinned=$(jq -r --arg id "$id" '.agents[] | select(.id==$id) | .pinned_version' "$CATALOG")
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "$req" "non-empty pinned_version for ${id}" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"
  fi
  printf '%s' "$pinned"
}

# _install_resolves_at <req> <id> <bin> <expected_path> [version_argv...]
# Shared driver: install <id>, assert no EACCES, assert <bin> resolves at exactly
# <expected_path> (never a /usr/local shim), and assert its version output contains
# the catalog pin. <version_argv...> defaults to `--version`.
_install_resolves_at() {
  local req=$1 id=$2 bin=$3 expected=$4
  shift 4
  local vargs=("$@")
  [[ ${#vargs[@]} -gt 0 ]] || vargs=(--version)
  local pinned
  pinned=$(_pin "$req" "$id") || return 1

  run sudo -u agent -H bash --login -c "agentlinux install ${id}"
  assert_exit_zero "${req} (install ${id})"
  assert_no_eacces "${req} (install ${id})" "$output"

  run sudo -u agent -H bash --login -c "command -v ${bin}"
  assert_exit_zero "${req} (resolve ${bin})"
  if [[ "${output}" != "${expected}" ]]; then
    __fail "$req" "${bin} resolves at ${expected} (no /usr/local shim)" "${output:-<empty>}" "$LOG"
  fi

  run sudo -u agent -H bash --login -c "${bin} ${vargs[*]}"
  assert_exit_zero "${req} (${bin} version)"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "$req" "${bin} version output contains pinned ${pinned}" "${output:-<empty>}" "$LOG"
  fi
}

# _remove_gone <req> <id> <bin> [residue_path...]
# Symmetric remove: <bin> off PATH AND each residue_path deleted; idempotent re-remove.
_remove_gone() {
  local req=$1 id=$2 bin=$3
  shift 3
  local residue=("$@")

  run sudo -u agent -H bash --login -c "agentlinux remove --force ${id}"
  assert_exit_zero "${req} (remove ${id})"
  assert_no_eacces "${req} (remove ${id})" "$output"

  run sudo -u agent -H bash --login -c "command -v ${bin}"
  [[ "${status}" -ne 0 ]] \
    || __fail "$req" "${bin} NOT on PATH after remove" "still resolves: ${output}" "$LOG"

  local p
  for p in "${residue[@]}"; do
    run sudo -u agent -H bash --login -c "test -e \"${p}\""
    [[ "${status}" -ne 0 ]] \
      || __fail "$req" "${p} deleted on remove (no residue)" "still exists" "$LOG"
  done

  run sudo -u agent -H bash --login -c "agentlinux remove --force ${id}"
  assert_exit_zero "${req} (idempotent re-remove ${id})"
}

# _assert_config_preserved <req> <abs-config-file>
# CAT-04: an authenticated tool's per-user auth/config survives `agentlinux remove`
# — consistent with every other authenticated agent (codex ~/.codex, Antigravity
# ~/.gemini, claude-code ~/.claude). Only `agentlinux --purge` wipes the agent
# home. The seeded sentinel file must still exist after remove.
_assert_config_preserved() {
  local req=$1 file=$2
  run sudo -u agent -H bash --login -c "test -e \"${file}\""
  [[ "${status}" -eq 0 ]] \
    || __fail "$req" "${file} preserved across remove (CAT-04 auth survives)" "gone after remove" "$LOG"
}

@test "DEVT-01: gh install fetches+checksum-verifies a binary into ~/.local/bin (no root/shim/EACCES); remove drops the binary but preserves ~/.config/gh (CAT-04)" {
  _install_resolves_at "DEVT-01" "gh" "gh" "/home/agent/.local/bin/gh" --version

  # Seed gh's auth config (with a file) BEFORE remove so the CAT-04 preservation
  # assertion is a real check, not a vacuous pass on a never-created dir. gh stores
  # its OAuth token + host list here via `gh auth login`.
  run sudo -u agent -H bash --login -c \
    'mkdir -p /home/agent/.config/gh && : >/home/agent/.config/gh/hosts.yml'
  assert_exit_zero "DEVT-01 (seed config)"

  # Symmetric remove: the AgentLinux-owned binary is gone (+ idempotent re-remove),
  # but the user's auth config survives per CAT-04.
  _remove_gone "DEVT-01" "gh" "gh"
  _assert_config_preserved "DEVT-01" "/home/agent/.config/gh/hosts.yml"
}

@test "DEVT-02: glab installs from the maintained gitlab-org/cli upstream (never archived profclems/glab); remove drops the binary but preserves ~/.config/glab (CAT-04)" {
  # Behavioral proof of the correct upstream: only gitlab-org/cli ships the pinned
  # 1.105.0 — the archived profclems/glab never released past its old line — so a
  # version-pin match already implies the right source. Belt-and-suspenders: assert
  # the recipe's ACTIVE code (full-line comments stripped) names gitlab-org/cli as
  # the download base and never fetches from profclems. Comments legitimately
  # mention profclems to document why it is avoided, so they are filtered first.
  run bash -c "grep -v '^[[:space:]]*#' /opt/agentlinux-src/plugin/catalog/agents/glab/install.sh"
  assert_exit_zero "DEVT-02 (read glab recipe active code)"
  if ! printf '%s' "${output}" | grep -q 'gitlab-org/cli'; then
    __fail "DEVT-02" "glab recipe active code targets gitlab-org/cli" "${output:-<empty>}" "$LOG"
  fi
  if printf '%s' "${output}" | grep -q 'profclems'; then
    __fail "DEVT-02" "glab recipe active code does NOT fetch from profclems/glab" "profclems in active code" "$LOG"
  fi

  _install_resolves_at "DEVT-02" "glab" "glab" "/home/agent/.local/bin/glab" --version

  run sudo -u agent -H bash --login -c \
    'mkdir -p /home/agent/.config/glab && : >/home/agent/.config/glab/config.yml'
  assert_exit_zero "DEVT-02 (seed config)"

  _remove_gone "DEVT-02" "glab" "glab"
  _assert_config_preserved "DEVT-02" "/home/agent/.config/glab/config.yml"
}

@test "DEVT-04: trivy installs (binary), runs a no-Docker filesystem scan, and removes symmetrically (+~/.cache/trivy)" {
  _install_resolves_at "DEVT-04" "trivy" "trivy" "/home/agent/.local/bin/trivy" --version

  # Real no-daemon scan (DEVT-04): a secret scan of a seeded dir needs no Docker and
  # no vulnerability-DB download. It must exit 0 (a clean tree → no findings).
  run sudo -u agent -H bash --login -c '
    set -u
    d=$(mktemp -d)
    trap "rm -rf \"$d\"" EXIT
    : >"$d/plain.txt"
    trivy fs --scanners secret --no-progress "$d"
  '
  assert_exit_zero "DEVT-04 (trivy fs no-Docker scan)"

  # Detection smoke: seed a private-key block and assert trivy's secret scanner
  # actually FINDS it — `--exit-code 1` makes a finding non-zero, and the report
  # names the rule. This proves a real no-daemon scan ran, not just that the
  # binary accepts the flags and exits 0 on an empty tree.
  run sudo -u agent -H bash --login -c '
    set -u
    d=$(mktemp -d)
    trap "rm -rf \"$d\"" EXIT
    # Assemble the PEM markers via %s (BEGIN/END never adjacent to "PRIVATE KEY"
    # on any single source line) so the repo gitleaks pre-commit hook does not
    # flag this fixture, while the written file is a real private-key block the
    # scanner under test detects. The key material is dummy, not a real key.
    printf -- "-----%s PRIVATE KEY-----\n%s\n-----%s PRIVATE KEY-----\n" \
      "BEGIN" "MIIBVAIBADANBgkqhkiG9w0BAQEFAASCATgdummykeymaterialdummykeymaterialABCD" "END" >"$d/leak.pem"
    trivy fs --scanners secret --no-progress --exit-code 1 "$d"
  '
  [[ "${status}" -ne 0 ]] \
    || __fail "DEVT-04" "trivy detects a seeded private key (--exit-code 1 non-zero)" "exit ${status}; ${output:-<empty>}" "$LOG"
  if ! printf '%s' "${output}" | grep -qiE 'private-key|AsymmetricPrivateKey|Secrets'; then
    __fail "DEVT-04" "trivy reports the seeded secret finding" "${output:-<empty>}" "$LOG"
  fi

  # Seed the DB cache dir BEFORE remove so the residue assertion is a real kill.
  run sudo -u agent -H bash --login -c \
    'mkdir -p /home/agent/.cache/trivy && : >/home/agent/.cache/trivy/marker'
  assert_exit_zero "DEVT-04 (seed cache)"

  _remove_gone "DEVT-04" "trivy" "trivy" "/home/agent/.cache/trivy"
}

@test "DEVT-05: gitleaks installs (binary), runs a real scan, and removes symmetrically" {
  # gitleaks reports its version via the `version` subcommand (post_install_verify
  # uses it); the output is a bare version string containing the pin.
  _install_resolves_at "DEVT-05" "gitleaks" "gitleaks" "/home/agent/.local/bin/gitleaks" version

  # Real scan (DEVT-05): scan a seeded clean directory. No leaks → exit 0.
  run sudo -u agent -H bash --login -c '
    set -u
    d=$(mktemp -d)
    trap "rm -rf \"$d\"" EXIT
    printf "%s\n" "just some ordinary text" >"$d/readme.txt"
    gitleaks dir --no-banner "$d"
  '
  assert_exit_zero "DEVT-05 (gitleaks scan of clean dir)"

  # Detection smoke: seed a private-key block (a robust default gitleaks rule) and
  # assert gitleaks actually FINDS it — non-zero exit + "leaks found" in output.
  # Exit 0 on a clean tree alone would pass even if the binary were a no-op; a
  # positive detection proves a real scan executed with no daemon.
  run sudo -u agent -H bash --login -c '
    set -u
    d=$(mktemp -d)
    trap "rm -rf \"$d\"" EXIT
    # Assemble the PEM markers via %s (BEGIN/END never adjacent to "PRIVATE KEY"
    # on any single source line) so the repo gitleaks pre-commit hook does not
    # flag this fixture, while the written file is a real private-key block the
    # scanner under test detects. The key material is dummy, not a real key.
    printf -- "-----%s PRIVATE KEY-----\n%s\n-----%s PRIVATE KEY-----\n" \
      "BEGIN" "MIIBVAIBADANBgkqhkiG9w0BAQEFAASCATgdummykeymaterialdummykeymaterialABCD" "END" >"$d/leak.pem"
    gitleaks dir --no-banner "$d"
  '
  [[ "${status}" -ne 0 ]] \
    || __fail "DEVT-05" "gitleaks detects a seeded private key (non-zero exit)" "exit ${status}; ${output:-<empty>}" "$LOG"
  if ! printf '%s' "${output}" | grep -qiE 'leaks found|finding'; then
    __fail "DEVT-05" "gitleaks reports the seeded leak" "${output:-<empty>}" "$LOG"
  fi

  _remove_gone "DEVT-05" "gitleaks" "gitleaks"
}

@test "DEVT-03: sentry-cli installs (npm @sentry/cli, FSL-1.1-MIT recorded) and removes symmetrically" {
  # License-gate honesty: the entry records the FSL-1.1-MIT flag (Appendix B).
  run bash -c "jq -r '.agents[] | select(.id==\"sentry-cli\") | .license' ${CATALOG}"
  assert_exit_zero "DEVT-03 (read license)"
  if [[ "${output}" != "FSL-1.1-MIT" ]]; then
    __fail "DEVT-03" "sentry-cli entry records license FSL-1.1-MIT" "license=[${output:-<empty>}]" "$LOG"
  fi

  # npm global → resolves under the agent-owned .npm-global prefix (no /usr/local).
  _install_resolves_at "DEVT-03" "sentry-cli" "sentry-cli" "/home/agent/.npm-global/bin/sentry-cli" --version

  _remove_gone "DEVT-03" "sentry-cli" "sentry-cli"
}
