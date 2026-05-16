#!/usr/bin/env bats
# tests/bats/13-reuse.bats — REUSE-01 + REUSE-02 + detect::user_can_sudo_apt.
#
# Phase 13 reuse-wiring coverage. Slot 13 is a sort key — file dependencies are
# inverted vs slot number: reuse depends on detection (15-detection.bats wires
# the DET-* readers Phase 13 consumes), but the bats runner sorts by name so 13
# loads first. Both files use the same `bats` $INSTALLER pointer and run
# against the post-installer host state (the harness at tests/docker/run.sh
# executes `agentlinux-install` before bats), so the order does not matter for
# correctness — every @test sources its own lib chain.
#
# Plan 13-01 ships:
#   - REUSE-01 detector @tests (Task 1) — 4 @tests covering the NOPASSWD-for-apt
#     reader + JSON shape + text marker (DET-01 fragment now carries the field).
#   - REUSE decision-function @tests (Task 2) — 7 @tests covering the four
#     dispatch tokens {reuse, create, remediate, bail} + entrypoint sourcing
#     order (reuse.sh AFTER detect.sh).
#   - REUSE wiring @tests (Task 3) — marker-presence + dispatch-shape gates;
#     comprehensive brownfield smoke lands in Plan 13-02.
#
# Per .planning/phases/13-reuse-wiring/13-01-PLAN.md success_criteria: each
# @test name starts with the REQ-ID (REUSE-01 / REUSE-02 / "REUSE-01 detector"
# for the can_sudo_apt reader since it's the REUSE-01 sudo bar from CONTEXT.md
# Area 1 / Q1 amendment).

load 'helpers/assertions'
load 'helpers/detection'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install
LIB_DIR=/opt/agentlinux-src/plugin/lib

# Helper: source the lib chain a @test needs to call detect:: / reuse:: directly.
# Mirrors the source order plugin/bin/agentlinux-install uses (log.sh first,
# then distro_detect.sh, then as_user.sh, then detect.sh; reuse.sh layered on
# top in Task 2). Quiet stdout/stderr so source noise does not pollute bats
# output diagnostics on failure.
__source_lib_chain() {
  # shellcheck disable=SC1091
  source "$LIB_DIR/log.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/distro_detect.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/as_user.sh"
  # shellcheck disable=SC1091
  source "$LIB_DIR/detect.sh"
}

__source_lib_chain_with_reuse() {
  __source_lib_chain
  # shellcheck disable=SC1091
  source "$LIB_DIR/reuse.sh"
}

# ---- Task 1: REUSE-01 detector (detect::user_can_sudo_apt) -------------------

@test "REUSE-01 detector: detect::user_can_sudo_apt exits 0 when agent has NOPASSWD-for-apt on post-installer host" {
  # REQ: REUSE-01 (sudo-bar predicate; T-13-02 mitigation verified by the
  # detect::user_probe absolute-path /usr/bin/apt-get probe).
  # Post-installer host has /etc/sudoers.d/agentlinux (ADR-012 NOPASSWD: ALL)
  # which subsumes apt — the probe must return exit 0.
  __source_lib_chain
  detect::run_once agent
  run detect::user_can_sudo_apt
  assert_exit_zero "REUSE-01"
  [[ "$DETECT_USER_CAN_SUDO_APT" == "true" ]] \
    || __fail "REUSE-01" "DETECT_USER_CAN_SUDO_APT=true on post-installer host" "DETECT_USER_CAN_SUDO_APT=${DETECT_USER_CAN_SUDO_APT:-unset}" "$LOG"
}

@test "REUSE-01 detector: detect::user_can_sudo_apt exits non-zero when DETECT_USER_CAN_SUDO_APT=false" {
  # REQ: REUSE-01 (reader contract — thin accessor over the export).
  # Unit-shape test: with the export forced to false, the reader returns 1.
  # Validates the reader's contract independent of any host state.
  __source_lib_chain
  DETECT_USER_CAN_SUDO_APT=false run detect::user_can_sudo_apt
  [[ "$status" -ne 0 ]] \
    || __fail "REUSE-01" "detect::user_can_sudo_apt exit non-zero when export is false" "exit=$status" "$LOG"
}

@test "REUSE-01 detector: --report-only JSON includes .components.user.can_sudo_apt boolean (true on post-installer host)" {
  # REQ: REUSE-01 (DET-01 JSON fragment now carries the field).
  run bash "$INSTALLER" --report-only --report-format=json
  assert_exit_zero "REUSE-01"
  # Plan 12-03 wraps the merged-fragment cache under .components (CONTEXT.md
  # Area 1). The `.components.X // .X` fallback keeps this @test green across
  # the pre-12-03 flat shape and the post-12-03 wrapped shape.
  printf '%s' "$output" | jq -e '
    (.components.user // .user) as $u
    | $u.can_sudo_apt == true
  ' >/dev/null \
    || __fail "REUSE-01" ".components.user.can_sudo_apt == true on post-installer host" "$output" "$LOG"
}

@test "REUSE-01 detector: --report-only text emits [DET-01] user.can_sudo_apt= marker line" {
  # REQ: REUSE-01 (grep-stable DET-NN marker convention from Phase 12).
  run bash "$INSTALLER" --report-only
  assert_exit_zero "REUSE-01"
  printf '%s' "$output" | grep -qE '^\[DET-01\] user\.can_sudo_apt=' \
    || __fail "REUSE-01" "[DET-01] user.can_sudo_apt= marker line in text output" "$output" "$LOG"
}
