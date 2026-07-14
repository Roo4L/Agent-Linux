#!/usr/bin/env bats
# tests/bats/66-catalog-spec-kit.bats — v0.3.6 Phase 44 (spec-kit 🔧) the Python+uv
# source_kind gate: ENABLE-03 (per-user uv bootstrapped with a checksum-verified
# static binary → `uv tool install` a git-pinned Python CLI → no root / no
# /usr/local shim / no EACCES → symmetric residue-free remove that tears down the
# AgentLinux-managed uv but NEVER a project .specify/) + WORK-03 (catalog pin, the
# `specify` CLI resolves and version-locks) + an OPS-01 real-operation smoke
# (`specify check` actually runs as the agent user).
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - the version pin is read from the provisioned catalog via jq — NEVER hardcoded
#   - installs run as the agent user through a login shell (PATH + ~/.local/bin)
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)
#
# Refs:
#   - tests/bats/57-catalog-binary.bats (jq-pin + lifecycle driver shape)
#   - plugin/catalog/agents/spec-kit/{install,uninstall}.sh
#   - plugin/catalog/lib/uv-bootstrap.sh (al_uv_ensure / al_uv_remove_if_managed_and_unused)
#   - plugin/catalog/lib/prebuilt-binary.sh (uv binary is fetched checksum-verified)
#   - .planning/REQUIREMENTS.md (ENABLE-03, WORK-03, OPS-01 + Appendix C: no cred)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

# Absolute agent-owned paths (spec-kit installs entirely under $HOME — never /usr/local).
UV_BIN=/home/agent/.local/bin/uv
UV_MARKER=/home/agent/.local/share/agentlinux/uv.managed
UV_DATA=/home/agent/.local/share/uv
# A real project scaffolded by `specify init` (OPS-01 real op); .specify/ lives under it.
SPEC_PROJ=/home/agent/specdemo

# _scrub_uv_state — remove every spec-kit + AgentLinux-managed-uv artifact so the
# managed-removal assertions are deterministic (spec-kit is the suite's sole uv
# consumer, so a full scrub is safe and mirrors 57's defensive pre/post scrub).
# TODO(ENABLE-07 growth-kit / next uv tool): the ~/.local/share/agentlinux scrub wipes
# the SHARED managed-uv marker — revisit when a second uv tool can be installed
# concurrently, so this file's scrub no longer clobbers another uv tool's marker.
_scrub_uv_state() {
  sudo -u agent -H bash --login -c '
    command -v uv >/dev/null 2>&1 && uv tool uninstall specify-cli >/dev/null 2>&1
    rm -f  /home/agent/.local/bin/uv /home/agent/.local/bin/uvx /home/agent/.local/bin/specify
    rm -rf /home/agent/.local/share/uv /home/agent/.cache/uv /home/agent/.local/share/agentlinux
    rm -rf /home/agent/specdemo
  ' >/dev/null 2>&1 || true
}

setup_file() {
  # 40-registry-cli.bats's INST-04 --purge @tests run earlier in filename sort and
  # can remove /opt/agentlinux + the agentlinux symlink. Recovery mirrors 53/57:
  # re-run the raw installer when the symlink is absent.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  _scrub_uv_state
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force spec-kit' >/dev/null 2>&1 || true
  fi
  _scrub_uv_state
}

# _speckit_pin — echo the spec-kit pin from the provisioned catalog (jq, never
# hardcoded) and guard it non-empty/non-null (a blank pin makes `grep -F -- ""`
# match ANY output, silently defeating the version-lock).
_speckit_pin() {
  local req=$1 pinned
  pinned=$(jq -r '.agents[] | select(.id=="spec-kit") | .pinned_version' "$CATALOG")
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "$req" "non-empty pinned_version from catalog" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"
  fi
  printf '%s' "$pinned"
}

@test "ENABLE-03: spec-kit bootstraps a per-user uv + installs the specify CLI (no root/shim/EACCES), runs a real op, and removes symmetrically — project .specify/ preserved" {
  local pinned
  pinned=$(_speckit_pin "ENABLE-03") || return 1

  # --- install: uv bootstrap (checksum-verified) + uv tool install specify-cli ---
  run sudo -u agent -H bash --login -c 'agentlinux install spec-kit'
  assert_exit_zero "ENABLE-03 (install)"
  assert_no_eacces "ENABLE-03 (install)" "$output"

  # uv landed in the agent-owned ~/.local/bin — never a /usr/local shim (the exact
  # anti-pattern that breaks self-update).
  run sudo -u agent -H bash --login -c 'command -v uv'
  assert_exit_zero "ENABLE-03 (uv resolve)"
  case "${output}" in
    /home/agent/.local/bin/uv) : ;;
    *) __fail "ENABLE-03" "uv resolves at /home/agent/.local/bin/uv (no /usr/local shim)" "${output:-<empty>}" "$LOG" ;;
  esac

  # specify (the tool) resolves under ~/.local/bin too.
  run sudo -u agent -H bash --login -c 'command -v specify'
  assert_exit_zero "ENABLE-03 (specify resolve)"
  case "${output}" in
    /home/agent/.local/bin/specify) : ;;
    *) __fail "WORK-03" "specify resolves at /home/agent/.local/bin/specify (no /usr/local shim)" "${output:-<empty>}" "$LOG" ;;
  esac

  # WORK-03 version-lock: specify --version contains the catalog pin (jq-derived).
  run sudo -u agent -H bash --login -c 'specify --version'
  assert_exit_zero "WORK-03 (version)"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "WORK-03" "specify --version contains pinned ${pinned}" "${output:-<empty>}" "$LOG"
  fi

  # OPS-01 real operation (token/workflow category = "spec-kit scaffolds a temp
  # project", REQUIREMENTS.md OPS-01): the tool actually performs its PRIMARY function
  # — `specify init` scaffolds a real project — not just install/version. This both
  # satisfies OPS-01 and makes the preserve-on-remove assertion below guard the tool's
  # genuine work product rather than a hand-faked directory. --ignore-agent-tools keeps
  # it non-interactive; --script sh pins the POSIX flavor.
  run sudo -u agent -H bash --login -c \
    'cd /home/agent && specify init specdemo --integration claude --ignore-agent-tools --script sh </dev/null'
  assert_exit_zero "OPS-01 (specify init scaffolds a project)"
  # The tool itself must have created the .specify/ work tree (not the test).
  run sudo -u agent -H bash --login -c 'test -d '"$SPEC_PROJ"'/.specify'
  [[ "${status}" -eq 0 ]] \
    || __fail "OPS-01" "specify init creates the project .specify/ (real op produced its work product)" "${SPEC_PROJ}/.specify absent" "$LOG"

  # Managed marker must exist now (uv was absent → AgentLinux installed it) so the
  # post-remove managed-uv teardown assertions are real kills, not vacuous passes.
  run sudo -u agent -H bash --login -c 'test -f '"$UV_MARKER"
  [[ "${status}" -eq 0 ]] \
    || __fail "ENABLE-03" "AgentLinux dropped the uv.managed marker on bootstrap" "marker absent at ${UV_MARKER}" "$LOG"

  # --- symmetric remove: specify tool + managed uv gone, project .specify/ kept ---
  run sudo -u agent -H bash --login -c 'agentlinux remove --force spec-kit'
  assert_exit_zero "ENABLE-03 (remove)"
  assert_no_eacces "ENABLE-03 (remove)" "$output"

  run sudo -u agent -H bash --login -c 'command -v specify'
  [[ "${status}" -ne 0 ]] \
    || __fail "WORK-03" "specify NOT on PATH after remove" "still resolves: ${output}" "$LOG"

  # Managed uv is torn down (marker present + no tools remain → uv removed).
  run sudo -u agent -H bash --login -c 'test -e '"$UV_BIN"
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-03" "AgentLinux-managed uv removed on uninstall (no tools remain)" "${UV_BIN} still exists" "$LOG"
  run sudo -u agent -H bash --login -c 'test -e '"$UV_DATA"
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-03" "managed uv data dir removed on uninstall" "${UV_DATA} still exists" "$LOG"

  # The user's tool-created project .specify/ MUST survive untouched (D6 trust
  # boundary) — uninstall removes only the uv tool + managed uv, never project work.
  run sudo -u agent -H bash --login -c 'test -d '"$SPEC_PROJ"'/.specify'
  [[ "${status}" -eq 0 ]] \
    || __fail "WORK-03" "project .specify/ preserved on remove (never AgentLinux's to delete)" "${SPEC_PROJ}/.specify was deleted by remove" "$LOG"

  # Idempotent re-remove (uninstall.sh guards every step / best-effort).
  run sudo -u agent -H bash --login -c 'agentlinux remove --force spec-kit'
  assert_exit_zero "ENABLE-03 (idempotent remove)"
}

@test "ENABLE-03: a user-brought uv (no managed marker) is never removed by the uv teardown" {
  # Trust-boundary unit test for the shared helper's core safety guarantee — offline,
  # no real uv needed. Source the staged helper, simulate a user-owned uv (a sentinel
  # binary on PATH) with NO managed marker, and prove al_uv_remove_if_managed_and_unused
  # leaves it untouched. This guards the "never clobber a uv the user brought" invariant
  # that the marker gating exists to enforce.
  run sudo -u agent -H bash --login -c '
    set -euo pipefail
    export AGENTLINUX_AGENT_HOME=/home/agent
    export AGENTLINUX_CATALOG_DIR=/opt/agentlinux/catalog/'"${PKG_VERSION}"'
    # shellcheck source=/dev/null
    source "$AGENTLINUX_CATALOG_DIR/lib/uv-bootstrap.sh"
    rm -f  /home/agent/.local/share/agentlinux/uv.managed
    mkdir -p /home/agent/.local/bin
    printf "#!/bin/sh\necho user-brought-uv\n" > /home/agent/.local/bin/uv
    chmod +x /home/agent/.local/bin/uv
    al_uv_remove_if_managed_and_unused
    test -x /home/agent/.local/bin/uv && echo USER_UV_SURVIVED
    rm -f /home/agent/.local/bin/uv   # dont leak the sentinel to later @tests
  '
  assert_exit_zero "ENABLE-03 (no-marker guard)"
  if ! printf '%s' "${output}" | grep -q 'USER_UV_SURVIVED'; then
    __fail "ENABLE-03" "user-brought uv (no marker) survives al_uv_remove_if_managed_and_unused" "${output:-<empty>}" "$LOG"
  fi
}

@test "WORK-03: the spec-kit catalog entry is a script-kind, MIT, git-tag-pinned workflow tool" {
  # Offline entry-shape assertion — the recipe is hosted-tool-agnostic; the catalog
  # entry is the contract. Exact tuple guards against silent drift.
  run bash -c "jq -r '.agents[] | select(.id==\"spec-kit\") | \"\(.source_kind) \(.license) \(.pinned_version) \(.install_recipe_path) \(.uninstall_recipe_path)\"' '$CATALOG'"
  assert_exit_zero "WORK-03 (entry shape)"
  if [[ "${output}" != "script MIT 0.12.11 install.sh uninstall.sh" ]]; then
    __fail "WORK-03" "spec-kit entry = 'script MIT 0.12.11 install.sh uninstall.sh'" "${output:-<empty>}" "$LOG"
  fi

  # It carries the workflow category tag (ENABLE-06 list grouping, Phase 49).
  run bash -c "jq -r '.agents[] | select(.id==\"spec-kit\") | .tags | index(\"workflow\") // empty' '$CATALOG'"
  if [[ -z "${output}" ]]; then
    __fail "WORK-03" "spec-kit entry carries the 'workflow' category tag" "tags missing 'workflow'" "$LOG"
  fi
}
