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
load 'helpers/brownfield'

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

# ---- Task 2: REUSE decision functions + entrypoint sourcing order ------------

@test "REUSE-01: reuse::user_decision returns 'reuse' on post-installer host (5 predicates pass)" {
  # REQ: REUSE-01 (all five predicates hold on the post-installer host —
  # agent user present + /bin/bash + writable home + name match + NOPASSWD-for-apt
  # via ADR-012's NOPASSWD: ALL which subsumes apt).
  __source_lib_chain_with_reuse
  detect::run_once agent
  run reuse::user_decision agent
  assert_exit_zero "REUSE-01"
  [[ "$output" == "reuse" ]] \
    || __fail "REUSE-01" "reuse::user_decision agent == 'reuse' on post-installer host" "$output (DETECT_USER_PRESENT=$DETECT_USER_PRESENT shell=$DETECT_USER_SHELL home_writable=$DETECT_USER_HOME_WRITABLE can_sudo_apt=$DETECT_USER_CAN_SUDO_APT)" "$LOG"
}

@test "REUSE-01: reuse::user_decision returns 'create' when DETECT_USER_PRESENT=false (greenfield)" {
  # REQ: REUSE-01 (predicate 1 — user absent falls through to CREATE).
  __source_lib_chain_with_reuse
  DETECT_USER_PRESENT=false run reuse::user_decision agent
  assert_exit_zero "REUSE-01"
  [[ "$output" == "create" ]] \
    || __fail "REUSE-01" "reuse::user_decision agent == 'create' when DETECT_USER_PRESENT=false" "$output" "$LOG"
}

@test "REUSE-01: reuse::user_decision returns 'remediate' when sudo_apt=false but other predicates hold" {
  # REQ: REUSE-01 (predicate 4 — fixable defect; Phase 14 REMEDIATE-03 will register
  # a real handler on this branch without changing the dispatch shape).
  __source_lib_chain_with_reuse
  DETECT_USER_PRESENT=true \
    DETECT_USER_NAME=agent \
    DETECT_USER_SHELL=/bin/bash \
    DETECT_USER_HOME=/home/agent \
    DETECT_USER_HOME_WRITABLE=true \
    DETECT_USER_CAN_SUDO_APT=false \
    run reuse::user_decision agent
  assert_exit_zero "REUSE-01"
  [[ "$output" == "remediate" ]] \
    || __fail "REUSE-01" "reuse::user_decision == 'remediate' when only sudo_apt fails" "$output" "$LOG"
}

@test "REUSE-01: reuse::user_decision returns 'bail' when shell is /usr/sbin/nologin (irreconcilable)" {
  # REQ: REUSE-01 (predicate 2 — wrong shell is irreconcilable per CONTEXT.md Area 1 Q1).
  __source_lib_chain_with_reuse
  DETECT_USER_PRESENT=true \
    DETECT_USER_NAME=agent \
    DETECT_USER_SHELL=/usr/sbin/nologin \
    DETECT_USER_HOME=/home/agent \
    DETECT_USER_HOME_WRITABLE=true \
    DETECT_USER_CAN_SUDO_APT=true \
    run reuse::user_decision agent
  assert_exit_zero "REUSE-01"
  [[ "$output" == "bail" ]] \
    || __fail "REUSE-01" "reuse::user_decision == 'bail' when shell=/usr/sbin/nologin" "$output" "$LOG"
}

@test "REUSE-01: reuse::user_decision returns 'bail' when home is not writable (irreconcilable)" {
  # REQ: REUSE-01 (predicate 3 — read-only home is irreconcilable).
  __source_lib_chain_with_reuse
  DETECT_USER_PRESENT=true \
    DETECT_USER_NAME=agent \
    DETECT_USER_SHELL=/bin/bash \
    DETECT_USER_HOME=/home/agent \
    DETECT_USER_HOME_WRITABLE=false \
    DETECT_USER_CAN_SUDO_APT=true \
    run reuse::user_decision agent
  assert_exit_zero "REUSE-01"
  [[ "$output" == "bail" ]] \
    || __fail "REUSE-01" "reuse::user_decision == 'bail' when home_writable=false" "$output" "$LOG"
}

@test "REUSE-01: reuse::user_decision returns 'bail' when --user=NAME mismatches DETECT_USER_NAME" {
  # REQ: REUSE-01 (predicate 5 — --user=NAME mismatch is its own incompatibility class).
  # Defensive check: the orchestrator passes the requested user; if DETECT_USER_NAME
  # diverges (manual export, future cross-user code path), bail rather than risk
  # adopting the wrong user.
  __source_lib_chain_with_reuse
  DETECT_USER_PRESENT=true \
    DETECT_USER_NAME=alice \
    DETECT_USER_SHELL=/bin/bash \
    DETECT_USER_HOME=/home/alice \
    DETECT_USER_HOME_WRITABLE=true \
    DETECT_USER_CAN_SUDO_APT=true \
    run reuse::user_decision agent
  assert_exit_zero "REUSE-01"
  [[ "$output" == "bail" ]] \
    || __fail "REUSE-01" "reuse::user_decision == 'bail' when requested=agent but DETECT_USER_NAME=alice" "$output" "$LOG"
}

@test "REUSE-02: reuse::nodejs_decision returns 'reuse' when DETECT exports satisfy BOTH predicates (Node 22 + writable prefix)" {
  # REQ: REUSE-02 (both predicates satisfied — Node 22 LTS pin matches AND
  # install user can write to the prefix). Force the exports inline because
  # the post-installer host's NodeSource Node lives at /usr (root-owned, not
  # writable by agent) — agent owns its OWN prefix at ~/.npm-global but the
  # detect::nodejs_probe records install_user_can_write_prefix per-Node-binary
  # (the /usr/bin/node binary's prefix is /usr, which agent cannot write to
  # without sudo). The reuse predicate is per the CONTEXT.md Area 1 Q2 contract
  # — version + writability — so the inline-export shape is the contract test
  # here. Plan 13-02's brownfield smoke uses a Docker fixture where Node 22 is
  # installed under the agent's own home (writable), exercising the end-to-end
  # `reuse` branch via real-state predicates rather than forced exports.
  __source_lib_chain_with_reuse
  DETECT_NODEJS_COUNT=1 \
    DETECT_NODEJS_0_SOURCE=nodesource \
    DETECT_NODEJS_0_VERSION=v22.4.0 \
    DETECT_NODEJS_0_WRITABLE=true \
    DETECT_NODEJS_0_PREFIX_ROOT=/home/agent/.npm-global \
    run reuse::nodejs_decision
  assert_exit_zero "REUSE-02"
  [[ "$output" == "reuse" ]] \
    || __fail "REUSE-02" "reuse::nodejs_decision == 'reuse' when one entry has v22.x + writable=true" "$output" "$LOG"
}

@test "REUSE-02: reuse::nodejs_decision returns 'create' on post-installer host (Node 22 present but /usr prefix not agent-writable)" {
  # REQ: REUSE-02 (CREATE branch when no entry has BOTH predicates true — the
  # canonical greenfield-post-Phase-3 shape where NodeSource Node lives at /usr
  # and agent cannot write to that prefix. This is the EXPECTED post-installer
  # observation: AgentLinux's prefix discipline keeps the npm globals at
  # ~/.npm-global, NOT at the Node binary's install prefix. REUSE-02 fires only
  # on brownfield hosts where Node 22 is already installed under a path the
  # install user owns — Plan 13-02's brownfield fixture exercises that case.
  __source_lib_chain_with_reuse
  detect::run_once agent
  run reuse::nodejs_decision
  assert_exit_zero "REUSE-02"
  [[ "$output" == "create" ]] \
    || __fail "REUSE-02" "reuse::nodejs_decision == 'create' on post-installer host (Node 22 at /usr, not agent-writable)" "$output (DETECT_NODEJS_COUNT=${DETECT_NODEJS_COUNT:-0} DETECT_NODEJS_0_WRITABLE=${DETECT_NODEJS_0_WRITABLE:-unset})" "$LOG"
}

@test "REUSE-02: reuse::nodejs_decision returns 'create' when DETECT_NODEJS_COUNT=0 (greenfield no-node)" {
  # REQ: REUSE-02 (no detected Node → fall through to CREATE; no remediate branch
  # for nodejs per CONTEXT.md Area 1 Q2).
  __source_lib_chain_with_reuse
  DETECT_NODEJS_COUNT=0 run reuse::nodejs_decision
  assert_exit_zero "REUSE-02"
  [[ "$output" == "create" ]] \
    || __fail "REUSE-02" "reuse::nodejs_decision == 'create' when DETECT_NODEJS_COUNT=0" "$output" "$LOG"
}

@test "REUSE-02: reuse::nodejs_decision returns 'create' when Node version is < 22 (Node 20 case)" {
  # REQ: REUSE-02 (version predicate failure → CREATE; defensive coverage that
  # the satisfies_pin reader rejects Node < 22).
  __source_lib_chain_with_reuse
  DETECT_NODEJS_COUNT=1 \
    DETECT_NODEJS_0_SOURCE=nvm \
    DETECT_NODEJS_0_VERSION=v20.10.0 \
    DETECT_NODEJS_0_WRITABLE=true \
    DETECT_NODEJS_0_PREFIX_ROOT=/home/agent/.nvm/versions/node/v20.10.0 \
    run reuse::nodejs_decision
  assert_exit_zero "REUSE-02"
  [[ "$output" == "create" ]] \
    || __fail "REUSE-02" "reuse::nodejs_decision == 'create' when only Node 20 is present" "$output" "$LOG"
}

@test "REUSE-01 + REUSE-02: agentlinux-install sources reuse.sh AFTER detect.sh (entrypoint order)" {
  # REQ: REUSE-01 + REUSE-02 (T-13-01 mitigation — detect::run_once populates
  # DETECT_* exports before any reuse:: call can consume them; verify by source-
  # order grep on the entrypoint).
  local entry=/opt/agentlinux-src/plugin/bin/agentlinux-install
  local d_line r_line
  d_line=$(grep -nF '. "$LIB_DIR/detect.sh"' "$entry" | head -1 | cut -d: -f1)
  r_line=$(grep -nF '. "$LIB_DIR/reuse.sh"' "$entry" | head -1 | cut -d: -f1)
  [[ -n "$d_line" && -n "$r_line" ]] \
    || __fail "REUSE-01" "both detect.sh + reuse.sh source lines present" "detect@${d_line:-MISSING} reuse@${r_line:-MISSING}" "$entry"
  [[ "$r_line" -gt "$d_line" ]] \
    || __fail "REUSE-01" "reuse.sh sourced AFTER detect.sh (reuse@$r_line > detect@$d_line)" "reuse@$r_line not > detect@$d_line" "$entry"
}

# ---- Task 3: provisioner wiring — case-branch dispatch + marker presence -----
# Comprehensive end-to-end brownfield smoke @tests for behaviors 1/3/4/5 land
# in Plan 13-02 (which owns the brownfield fixture helper). Plan 13-01 ships
# the dispatch-shape + marker-presence gates sufficient to verify the wiring.

@test "REUSE-01: re-running installer on post-installer host emits [REUSE-01] marker (REUSE branch fires)" {
  # REQ: REUSE-01 (post-installer host has agent + NOPASSWD: ALL via ADR-012 →
  # 5/5 predicates pass → second install run reuses, NOT recreates). Marker
  # presence in the tee'd transcript proves the case-branch dispatch fired the
  # `reuse)` arm; the surrounding log_info from reuse::log_user_reuse confirms
  # the existing user was adopted. The earlier 10-installer.bats INST-02 @test
  # uses this same re-run pattern (run bash "$INSTALLER") for byte-stability.
  #
  # NB: the entrypoint TRUNCATES the log on every run (plugin/bin/agentlinux-install
  # line 114: `install -m 0644 /dev/null "$LOG_FILE"`), so the captured `$output`
  # of the bats `run` is the authoritative transcript here — NOT the on-disk log
  # (which contains only the just-completed install's transcript by the time we
  # grep it). Capturing $output preserves the second-install transcript even
  # after subsequent @tests re-run the installer (which would truncate again).
  run bash "$INSTALLER"
  assert_exit_zero "REUSE-01"
  printf '%s' "$output" | grep -qF '[REUSE-01]' \
    || __fail "REUSE-01" "[REUSE-01] marker present in re-run install transcript (captured \$output)" "$output" "$LOG"
  # Defensive: the REUSE branch must NOT issue a 'useradd agent' invocation in
  # the re-run transcript (the entire CREATE-path block is wrapped in
  # `if [[ REUSED_USER != true ]]; then` so ensure_user is not even CALLED on
  # the REUSE branch). Excludes the literal log_info message "skipping useradd"
  # — that's the EXPECTED REUSE-branch line proving the wrapping took effect,
  # NOT a real useradd invocation. Real invocations would be `+ useradd ...`
  # under set -x trace, or appear without a "skipping" qualifier. Filtering
  # out the marker lines (which we ASSERTED are present above) leaves only
  # actual invocations.
  local without_markers
  without_markers=$(printf '%s' "$output" | grep -vE 'skipping useradd|\[REUSE-01\]')
  printf '%s' "$without_markers" | grep -qE '\busers add\b|\buseradd\b' \
    && __fail "REUSE-01" "ZERO real useradd invocations in REUSE-branch transcript (excluding REUSE marker lines)" "$without_markers" "$LOG"
  true
}

@test "REUSE-01: re-run REUSE branch still ensures DOC-02 CLAUDE.md marker block (additive against existing user)" {
  # REQ: REUSE-01 (CONTEXT.md "REUSE-01 fires + 40-path-wiring.sh still runs +
  # DOC-02 CLAUDE.md ensure_marker_block stays unconditional"). Verify the
  # anti-pattern strings are still present after a REUSE-branch re-run. Three
  # canonical strings are required by the v0.3.0 contract (per 02-RESEARCH.md
  # Pitfall 5 / DOC-02 grep targets).
  [[ -f /home/agent/CLAUDE.md ]] \
    || __fail "REUSE-01" "/home/agent/CLAUDE.md exists" "missing file" "$LOG"
  for needle in 'usr/local/bin' 'sudo npm install -g' 'second Node.js install'; do
    grep -qF -- "$needle" /home/agent/CLAUDE.md \
      || __fail "REUSE-01" "DOC-02 anti-pattern string '${needle}' present in /home/agent/CLAUDE.md after REUSE branch" "missing" "/home/agent/CLAUDE.md"
  done
}

@test "REUSE-01: case-branch in 10-agent-user.sh dispatches on RESOLUTIONS[user] (Phase 14 DECIDE-THEN-ACT)" {
  # REQ: REUSE-01 (CONTEXT.md "Phase 13 → Phase 14 contract" — case-branch
  # MUST enumerate all four dispatch tokens so Phase 14 can extend the
  # remediate/bail handlers without changing the surface).
  #
  # Phase 14 (Plan 14-01) transformed the dispatch shape from a direct
  # `reuse::user_decision` cmdsub to a pre-resolved RESOLUTIONS[user] lookup
  # — decisions are made up-front in main() by remediate::collect_all_decisions
  # BEFORE any provisioner runs, so the bail arm here is unreachable (the
  # flush_bails_or_continue policy gate would have exited 65 first). All four
  # dispatch tokens stay handled (CONTEXT.md "Phase 13 → Phase 14 contract");
  # only the source of the token changed. `reuse` and `remediate` may share one
  # arm (`reuse | remediate)`) — the user component's remediate is definitionally
  # identical to reuse (the sudoers fix is owned by RESOLUTIONS[sudoers], not
  # here), so the check verifies each token is DISPATCHED, not that it sits in
  # its own arm.
  local prov=/opt/agentlinux-src/plugin/provisioner/10-agent-user.sh
  grep -qE '\$\{RESOLUTIONS\[user\]' "$prov" \
    || __fail "REUSE-01" "10-agent-user.sh dispatches on \${RESOLUTIONS[user]}" "no RESOLUTIONS lookup found" "$prov"
  # Extract the case-block body and assert each of the four tokens labels a case
  # arm (followed by `|` or `)`), tolerant of combined arms.
  local case_body
  case_body=$(awk '/case .*RESOLUTIONS\[user\]/,/esac/' "$prov")
  for token in reuse create remediate bail; do
    printf '%s' "$case_body" | grep -qE "(^|[[:space:]|])${token}[[:space:]]*[|)]" \
      || __fail "REUSE-01" "case-branch dispatches token '$token'" "case body: $case_body" "$prov"
  done
  # REUSED_USER guard wraps Steps 1+2 (CREATE path) but NOT Step 3 (DOC-02
  # ensure_marker_block). Verify by awk-extracting the REUSED_USER block and
  # asserting it does NOT contain the CLAUDE.md ensure_marker_block call.
  local guarded
  guarded=$(awk '/if \[\[ "\${REUSED_USER:-false}" != true \]\]/,/^fi$/' "$prov")
  printf '%s' "$guarded" | grep -qF 'ensure_marker_block /home/agent/CLAUDE.md' \
    && __fail "REUSE-01" "DOC-02 ensure_marker_block is OUTSIDE the REUSED_USER guard" "found inside guard" "$prov"
  true
}

@test "REUSE-02: case-branch in 30-nodejs.sh dispatches on RESOLUTIONS[node] (Phase 14 DECIDE-THEN-ACT)" {
  # REQ: REUSE-02 (CONTEXT.md "Phase 13 → Phase 14 contract" — case-branch
  # MUST enumerate reuse + create tokens; no remediate branch at the Node-
  # install layer per Area 1 Q2 — REMEDIATE-01 lives in the npm-prefix
  # dispatch later in the same file).
  #
  # Phase 14 (Plan 14-01) transformed the dispatch shape from a direct
  # `reuse::nodejs_decision` cmdsub to a pre-resolved RESOLUTIONS[node]
  # lookup. The 4-token enumeration is preserved defensively (Plan 14-01
  # added remediate|bail arms as unreachable assertions for forward-compat).
  local prov=/opt/agentlinux-src/plugin/provisioner/30-nodejs.sh
  grep -qE '\$\{RESOLUTIONS\[node\]' "$prov" \
    || __fail "REUSE-02" "30-nodejs.sh dispatches on \${RESOLUTIONS[node]}" "no RESOLUTIONS lookup found" "$prov"
  local case_body
  case_body=$(awk '/case .*RESOLUTIONS\[node\]/,/esac/' "$prov")
  for token in 'reuse)' 'create)'; do
    printf '%s' "$case_body" | grep -qF "$token" \
      || __fail "REUSE-02" "case-branch enumerates dispatch token '$token'" "case body: $case_body" "$prov"
  done
  # Marker emission helper must be called from the reuse) arm.
  printf '%s' "$case_body" | grep -qF 'reuse::log_nodejs_reuse' \
    || __fail "REUSE-02" "reuse::log_nodejs_reuse called from reuse) arm" "$case_body" "$prov"
}

@test "REUSE-01 + REUSE-02: no --reuse-strict / --reuse-best-effort / --no-reuse flags introduced (per-component, no mode flags)" {
  # REQ: REUSE-01 + REUSE-02 (CONTEXT.md Q4 user-locked decision — no mode
  # flags; per-component decisions only). Grep-verify the entrypoint + reuse
  # libs do not learn any such flag.
  local files=(
    /opt/agentlinux-src/plugin/bin/agentlinux-install
    /opt/agentlinux-src/plugin/lib/reuse.sh
    /opt/agentlinux-src/plugin/lib/reuse/user.sh
    /opt/agentlinux-src/plugin/lib/reuse/nodejs.sh
  )
  for f in "${files[@]}"; do
    grep -qE 'reuse-strict|reuse-best-effort|no-reuse' "$f" \
      && __fail "REUSE-01" "no reuse-mode flags in $f" "found flag" "$f"
  done
  true
}

@test "REUSE: greenfield invariant preserved — bats @test count unchanged from baseline (defense against accidental @test deletion)" {
  # REQ: REUSE-01 + REUSE-02 (CONTEXT.md "greenfield invariant — first-install
  # run on a fresh container completes identically to v0.3.0 + Phase 12
  # baseline"). The post-Plan-13-01 baseline is 97 + 15 (this file) = 112.
  # Defensive check that no existing bats file lost @tests. Plan 13-02 raises
  # the baseline to 119 (Plan 13-01 = 112; + 7 task-1 REUSE-03 decision @tests).
  # Plan 13-02 Task 3 adds 2 more E2E smoke @tests that may skip without
  # network; the count check uses the raw `grep -cE '^@test "'` total which
  # is independent of skip status (skipped @tests are still counted).
  local total
  total=$(grep -cE '^@test "' /opt/agentlinux-src/tests/bats/*.bats | awk -F: '{s+=$2} END {print s}')
  [[ "$total" -ge 119 ]] \
    || __fail "REUSE-01" "bats @test count >= 119 (post-Plan-13-02 Task-1 baseline)" "total=$total" "$LOG"
}

# ---- Plan 13-02 Task 1: REUSE-03 reuse::agent_decision (catalog-agent) -------
# Behaviors 1-4 of Task 1: schema validates compatibility_window; reuse::agent_decision
# returns reuse / remediate / create per the 3-predicate check (+ defensive
# unknown-id path). Predicate 3 (version-in-window) is layered on top by the CLI
# install.ts (Task 2); the bash decision function returns reuse on healthy +
# path-match + status=healthy alone.

@test "REUSE-03: reuse::agent_decision returns 'create' when DETECT_AGENT_<ID>_STATUS=absent" {
  # REQ: REUSE-03 (predicate 1 — agent absent → fall through to CREATE).
  # NB: `export` is required because detect::agent_status performs an indirect
  # variable lookup (${!var:-absent}) inside a subshell spawned by bats `run`
  # via command substitution — env-prefix `X=y run ...` does not propagate
  # through nested subshell chains the way exported vars do.
  __source_lib_chain_with_reuse
  export DETECT_AGENT_CLAUDE_CODE_STATUS=absent
  run reuse::agent_decision claude-code
  unset DETECT_AGENT_CLAUDE_CODE_STATUS
  assert_exit_zero "REUSE-03"
  [[ "$output" == "create" ]] \
    || __fail "REUSE-03" "reuse::agent_decision claude-code == 'create' when status=absent" "$output" "$LOG"
}

@test "REUSE-03: reuse::agent_decision returns 'reuse' when status=healthy AND path matches canonical" {
  # REQ: REUSE-03 (predicates 1 + 2 — healthy + canonical-path-match). The
  # version-in-window predicate (predicate 3) is layered on by the CLI
  # install.ts; the bash function returns `reuse` on healthy + path-match alone.
  __source_lib_chain_with_reuse
  export DETECT_AGENT_CLAUDE_CODE_STATUS=healthy
  export DETECT_AGENT_CLAUDE_CODE_PATH=/home/agent/.local/bin/claude
  export DETECT_AGENT_CLAUDE_CODE_VERSION=2.1.98
  run reuse::agent_decision claude-code
  unset DETECT_AGENT_CLAUDE_CODE_STATUS DETECT_AGENT_CLAUDE_CODE_PATH DETECT_AGENT_CLAUDE_CODE_VERSION
  assert_exit_zero "REUSE-03"
  [[ "$output" == "reuse" ]] \
    || __fail "REUSE-03" "reuse::agent_decision claude-code == 'reuse' when healthy + canonical path" "$output" "$LOG"
}

@test "REUSE-03: reuse::agent_decision returns 'remediate' when status=healthy BUT path != canonical (path-mismatch)" {
  # REQ: REUSE-03 (path-mismatch case — Phase 14 REMEDIATE-04 reinstalls at
  # the canonical path per CONTEXT.md Area 1 Q3 fall-through). The classic
  # case: claude installed via `npm install -g @anthropic-ai/claude-code` at
  # ~/.npm-global/bin/claude rather than the native installer's
  # ~/.local/bin/claude — DIFFERENT path → REUSE-03 path-match check FAILS.
  __source_lib_chain_with_reuse
  export DETECT_AGENT_CLAUDE_CODE_STATUS=healthy
  export DETECT_AGENT_CLAUDE_CODE_PATH=/home/agent/.npm-global/bin/claude
  export DETECT_AGENT_CLAUDE_CODE_VERSION=2.1.98
  run reuse::agent_decision claude-code
  unset DETECT_AGENT_CLAUDE_CODE_STATUS DETECT_AGENT_CLAUDE_CODE_PATH DETECT_AGENT_CLAUDE_CODE_VERSION
  assert_exit_zero "REUSE-03"
  [[ "$output" == "remediate" ]] \
    || __fail "REUSE-03" "reuse::agent_decision == 'remediate' on healthy + path-mismatch" "$output" "$LOG"
}

@test "REUSE-03 / DET-04: reuse::agent_decision returns 'reuse' for gsd at the deployed-system VERSION path (npx form)" {
  # REQ: REUSE-03 / DET-04. GSD's `get-shit-done-cc` is a bootstrapper; the
  # upstream `npx get-shit-done-cc` install deploys the GSD system (VERSION file
  # + gsd-* skills) but leaves NO persistent global binary, so detect/agents.sh
  # reports gsd at the deployed-system VERSION file. That path is a SECOND valid
  # canonical presence → reuse, NOT a wrong-path remediate. Regression guard for
  # "dry-run says gsd absent on a host where GSD is installed via npx".
  __source_lib_chain_with_reuse
  export DETECT_AGENT_GSD_STATUS=healthy
  export DETECT_AGENT_GSD_PATH=/home/agent/.claude/get-shit-done/VERSION
  export DETECT_AGENT_GSD_VERSION=1.37.1
  run reuse::agent_decision gsd
  unset DETECT_AGENT_GSD_STATUS DETECT_AGENT_GSD_PATH DETECT_AGENT_GSD_VERSION
  assert_exit_zero "REUSE-03"
  [[ "$output" == "reuse" ]] \
    || __fail "REUSE-03" "gsd at deployed-system VERSION path == 'reuse' (npx form, not remediate)" "$output" "$LOG"
}

@test "REUSE-03: reuse::agent_decision returns 'remediate' when status=broken" {
  # REQ: REUSE-03 (broken catalog agent always → Phase 14 REMEDIATE-04 territory:
  # uninstall + reinstall via the recipe).
  __source_lib_chain_with_reuse
  export DETECT_AGENT_CLAUDE_CODE_STATUS=broken
  export DETECT_AGENT_CLAUDE_CODE_PATH=/home/agent/.local/bin/claude
  export DETECT_AGENT_CLAUDE_CODE_VERSION=""
  run reuse::agent_decision claude-code
  unset DETECT_AGENT_CLAUDE_CODE_STATUS DETECT_AGENT_CLAUDE_CODE_PATH DETECT_AGENT_CLAUDE_CODE_VERSION
  assert_exit_zero "REUSE-03"
  [[ "$output" == "remediate" ]] \
    || __fail "REUSE-03" "reuse::agent_decision == 'remediate' on broken catalog agent" "$output" "$LOG"
}

@test "REUSE-03: reuse::agent_decision returns 'create' on unknown catalog id (defensive)" {
  # REQ: REUSE-03 (defensive — future catalog ids not in the hardcoded
  # canonical-path map fall through to install rather than incorrectly REUSE).
  __source_lib_chain_with_reuse
  export DETECT_AGENT_NEW_THING_STATUS=healthy
  export DETECT_AGENT_NEW_THING_PATH=/usr/local/bin/new-thing
  run reuse::agent_decision new-thing
  unset DETECT_AGENT_NEW_THING_STATUS DETECT_AGENT_NEW_THING_PATH
  assert_exit_zero "REUSE-03"
  [[ "$output" == "create" ]] \
    || __fail "REUSE-03" "reuse::agent_decision == 'create' on unknown catalog id" "$output" "$LOG"
}

@test "REUSE-03: catalog.json has compatibility_window on exactly 3 non-test entries" {
  # REQ: REUSE-03 (catalog.json compatibility_window field — semver range used
  # by the CLI install.ts to layer the version-in-window predicate on top of
  # reuse::agent_decision's path-match decision).
  local catalog=/opt/agentlinux-src/plugin/catalog/catalog.json
  local count
  count=$(grep -c 'compatibility_window' "$catalog")
  [[ "$count" -eq 3 ]] \
    || __fail "REUSE-03" "catalog.json has compatibility_window on exactly 3 non-test entries" "count=$count" "$catalog"
  # test-dummy entry MUST NOT have compatibility_window (test_only: true; never
  # participates in REUSE).
  if jq -e '.agents[] | select(.test_only == true) | has("compatibility_window")' "$catalog" >/dev/null; then
    __fail "REUSE-03" "test-dummy MUST NOT carry compatibility_window" "found compatibility_window on a test_only entry" "$catalog"
  fi
}

@test "REUSE-03: schema.json declares compatibility_window field" {
  # REQ: REUSE-03 (schema-validator accepts the new field; node-side ajv
  # validation passes — bats only grep-asserts the declaration here since the
  # CLI test suite covers full validate-catalog.mjs round-tripping).
  local schema=/opt/agentlinux-src/plugin/catalog/schema.json
  jq -e '.["$defs"].agent.properties.compatibility_window.type == "string"' "$schema" >/dev/null \
    || __fail "REUSE-03" 'schema.json $defs.agent.properties.compatibility_window is type=string' "$(jq '.["$defs"].agent.properties.compatibility_window // {}' "$schema")" "$schema"
}

@test "REUSE-03: plugin/lib/reuse.sh sources reuse/agents.sh (dispatch surface includes catalog-agent decision)" {
  # REQ: REUSE-03 (orchestrator extends the per-component decision pattern by
  # sourcing the new file; Phase 14 may add reuse::agent_remediate functions
  # alongside without changing this surface).
  local orch=/opt/agentlinux-src/plugin/lib/reuse.sh
  grep -qF '. "$REUSE_LIB_DIR/agents.sh"' "$orch" \
    || __fail "REUSE-03" "reuse.sh sources reuse/agents.sh" "no source line for agents.sh" "$orch"
}

# ---- Plan 13-02 Task 3: brownfield E2E smoke (REUSE-01 + REUSE-02 + REUSE-03) ----
#
# FIXTURE-CHOICE NOTE (mirrors brownfield.bash disclosure): the brownfield
# helper installs claude via the native installer at ~/.local/bin/claude —
# the catalog canonical path. The @tests below assert the CANONICAL-PATH-MATCH
# case for REUSE-03 (fires `reuse`). The PATH-MISMATCH case (npm install -g
# at ~/.npm-global/bin/claude → emits `remediate`) is Phase 14 REMEDIATE-04
# territory and is NOT exercised here.

@test "REUSE-03 brownfield E2E: agentlinux-install on pre-populated host fires REUSE-01 + REUSE-03 + writes reused sentinel" {
  # REQ: REUSE-01 + REUSE-03 (the canonical brownfield smoke — CANONICAL-PATH-MATCH
  # case per CONTEXT.md Area 2 Q3 + Q4). Asserts the installer detects the
  # pre-populated agent user (REUSE-01 fires) and the CLI install adopts the
  # pre-existing claude-code at the canonical path (REUSE-03 fires).
  #
  # NB on REUSE-02: the brownfield helper installs NodeSource Node 22 at /usr
  # (root-owned prefix, not agent-writable). REUSE-02's predicate requires
  # nodejs_prefix_writable=true, which fails for /usr → REUSE-02 returns
  # `create` and 30-nodejs.sh re-runs (apt-get install is itself idempotent
  # when nodejs is already installed; the line appears in the log even on the
  # no-op happy path). A future brownfield variant could install Node via nvm
  # at ~/.nvm to exercise REUSE-02; gated as Phase-14 work to keep the fixture
  # small here. Plan 13-01's "REUSE-02: reuse::nodejs_decision returns 'create'
  # on post-installer host" @test documents this exact case.
  #
  # The helper requires network access to NodeSource + claude.ai. Skip when
  # the test image lacks outbound HTTP (offline CI mode).
  if ! curl -fsSL --max-time 5 -o /dev/null https://claude.ai/install.sh 2>/dev/null; then
    skip "no network access to claude.ai (offline test mode)"
  fi

  setup_brownfield_host

  # Run the installer; capture the full transcript via $output (the entrypoint
  # truncates /var/log/agentlinux-install.log at start so $output is the
  # authoritative capture).
  #
  # Phase 14 (Plan 14-01) adjustment: the brownfield helper installs Node 22
  # at /usr (root-owned prefix). reuse::npm_prefix_decision now returns
  # `remediate` for the root-owned prefix, which without --yes triggers the
  # DECIDE-THEN-ACT bail gate and exits 65. Pass --yes to consent so the
  # Plan 14-01 npm-prefix stub fires (Plan 14-02 wires the real chown/rebase
  # body) and the installer reaches the CLI install step where REUSE-03
  # adopts the pre-existing claude-code.
  run bash "$INSTALLER" --yes
  assert_exit_zero "REUSE-03"

  # ZERO real `useradd agent` invocations in transcript — REUSE-01 must have
  # fired. Filter out the REUSE marker line + skipping-useradd diagnostic which
  # both contain "useradd" but are NOT real invocations.
  local without_markers
  without_markers=$(printf '%s' "$output" | grep -vE 'skipping useradd|\[REUSE-01\]')
  if printf '%s' "$without_markers" | grep -qE '\buseradd\b'; then
    __fail "REUSE-03" "ZERO real useradd invocations on brownfield host" "$without_markers" "$LOG"
  fi

  # AT LEAST one [REUSE-01] marker.
  printf '%s' "$output" | grep -qF '[REUSE-01]' \
    || __fail "REUSE-03" "[REUSE-01] marker in install transcript" "$output" "$LOG"

  # Trigger REUSE-03 via the CLI install (the bash entrypoint does NOT trigger
  # REUSE-03 — that's per-catalog-agent and dispatched by the CLI).
  local cli
  cli=$(find /opt/agentlinux/cli -maxdepth 3 -name index.js -path '*/dist/*' 2>/dev/null | head -1)
  [[ -n "$cli" ]] \
    || __fail "REUSE-03" "CLI index.js exists under /opt/agentlinux/cli/<ver>/dist/" "no match" "/opt/agentlinux/cli/"

  run sudo -u agent "$cli" install claude-code
  assert_exit_zero "REUSE-03"
  printf '%s' "$output" | grep -qF '[REUSE-03]' \
    || __fail "REUSE-03" "[REUSE-03] marker in CLI install output" "$output" "$LOG"

  # Sentinel exists with status=reused. The CLI writes sentinels at the
  # state dir (defaults to /opt/agentlinux/state/installed.d).
  local sentinel=/opt/agentlinux/state/installed.d/claude-code.json
  [[ -f "$sentinel" ]] \
    || __fail "REUSE-03" "sentinel written at $sentinel" "(missing)" "$LOG"
  jq -e '.status == "reused"' "$sentinel" >/dev/null \
    || __fail "REUSE-03" "sentinel has status=reused" "$(cat "$sentinel")" "$LOG"
  jq -e '.binary_path == "/home/agent/.local/bin/claude"' "$sentinel" >/dev/null \
    || __fail "REUSE-03" "sentinel binary_path == canonical claude path" "$(cat "$sentinel")" "$LOG"
  # NB: the next @test (list-suffix) reads + then cleans up this sentinel so
  # downstream CAT-02 @test stays green. The sentinel is intentionally LEFT
  # here as a handoff to the next @test — DO NOT remove it inline.
}

@test "REUSE-03 brownfield E2E: agentlinux list shows (reused — managed) suffix on the reused entry" {
  # REQ: REUSE-03 (AGGRESSIVE-ownership disclosure surface — CONTEXT.md Area 2
  # Q2; the suffix wording is binding). Depends on the previous brownfield E2E
  # @test having left a reused sentinel; skip if not present (e.g. running this
  # @test in isolation or after the previous one was skipped due to no network).
  local sentinel=/opt/agentlinux/state/installed.d/claude-code.json
  [[ -f "$sentinel" ]] || skip "no claude-code sentinel from prior brownfield @test"
  jq -e '.status == "reused"' "$sentinel" >/dev/null || skip "claude-code sentinel is not reused"

  local cli
  cli=$(find /opt/agentlinux/cli -maxdepth 3 -name index.js -path '*/dist/*' 2>/dev/null | head -1)
  [[ -n "$cli" ]] || skip "no CLI index.js found"

  run sudo -u agent "$cli" list
  assert_exit_zero "REUSE-03"
  printf '%s' "$output" | grep -qF 'reused — managed by agentlinux upgrade/remove' \
    || __fail "REUSE-03" "reused suffix present in list output" "$output" "$LOG"

  # Cleanup: remove the claude-code sentinel left by the brownfield E2E
  # fixture so the downstream CAT-02 @test (zero residual sentinels in
  # installed.d) keeps passing. Idempotent — works whether the prior @test
  # wrote the sentinel or skipped.
  rm -f "$sentinel"
}
