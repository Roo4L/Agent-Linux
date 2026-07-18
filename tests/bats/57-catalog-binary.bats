#!/usr/bin/env bats
# tests/bats/57-catalog-binary.bats — v0.3.6 Phase 28 (rtk 🔧) the prebuilt-binary
# source_kind gate: ENABLE-01 (checksum-verified fetch → ~/.local/bin, no root /
# no /usr/local shim / no EACCES, symmetric residue-free remove, verify-before-
# extract abort) + WORK-02 (catalog pin, opt-in ~/.claude hook reverted on remove)
# + an OPS-01 real-operation smoke (a true offline rtk op as the agent user).
#
# Each requirement gets one @test driving the full TST-07 lifecycle on a
# provisioned host:
#   agentlinux install rtk → binary resolves under /home/agent/.local/bin
#   → rtk --version contains the catalog pin → agentlinux remove --force rtk
#   (binary + ~/.config/rtk + ~/.local/share/rtk gone) → idempotent re-remove.
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - version pins read from the provisioned catalog via jq — NEVER hardcoded
#   - installs run as the agent user through a login shell (PATH + ~/.local/bin)
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088: a
#     tilde does not expand inside a quoted string handed to bash -c)
#
# Refs:
#   - tests/bats/53-catalog-npm-cluster.bats (jq-pin + lifecycle driver shape)
#   - tests/bats/56-catalog-skill-wiring.bats (absolute-path discipline)
#   - plugin/catalog/agents/rtk/{install,uninstall}.sh
#   - plugin/catalog/lib/prebuilt-binary.sh (al_pb_fetch_and_verify gate)
#   - .planning/REQUIREMENTS.md (ENABLE-01, WORK-02, OPS-01 + Appendix C: no cred)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
# AL-29: derive the catalog version from package.json — single SoT.
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

setup_file() {
  # 40-registry-cli.bats's INST-04 --purge @tests run earlier in filename sort
  # and can remove /opt/agentlinux + the agentlinux symlink + the agent user.
  # Recovery mirrors 53/56: re-run the raw installer when the symlink is absent
  # so `agentlinux install rtk` has a working dispatch surface.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi

  # Defensive scrub of rtk's own state BEFORE any test (parity with 53). Without
  # it a stale binary/hook from a prior run could satisfy a present-assertion even
  # if a regressed recipe stopped writing it — exactly what these tests catch.
  # NOTE: only rtk-OWNED artifacts (RTK.md / settings.json.bak), never the
  # user-owned settings.json itself (threat T-28-14 / V4 trust boundary).
  sudo -u agent -H bash --login -c '
    rm -rf /home/agent/.local/bin/rtk /home/agent/.config/rtk /home/agent/.local/share/rtk
    rm -f /home/agent/.claude/RTK.md /home/agent/.claude/settings.json.bak
  ' >/dev/null 2>&1 || true
}

teardown_file() {
  # Symmetric removal + state scrub so later @test files see a clean slate.
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force rtk' >/dev/null 2>&1 || true
  fi
  sudo -u agent -H bash --login -c '
    rm -rf /home/agent/.local/bin/rtk /home/agent/.config/rtk /home/agent/.local/share/rtk
    rm -f /home/agent/.claude/RTK.md /home/agent/.claude/settings.json.bak
  ' >/dev/null 2>&1 || true
}

# _rtk_pin — echo the rtk pin from the provisioned catalog (jq, never hardcoded)
# and guard it non-empty/non-null. A blank pin would make `grep -F -- ""` match
# ANY output, silently defeating the version-lock assertion (missing catalog /
# renamed id) — so a missing pin fails LOUD here instead.
_rtk_pin() {
  local req=$1 pinned
  pinned=$(jq -r '.agents[] | select(.id=="rtk") | .pinned_version' "$CATALOG")
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "$req" "non-empty pinned_version from catalog" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"
  fi
  printf '%s' "$pinned"
}

@test "ENABLE-01: rtk install fetches+checksum-verifies a binary into ~/.local/bin (no root/shim/EACCES) and removes symmetrically" {
  local pinned
  pinned=$(_rtk_pin "ENABLE-01") || return 1

  run sudo -u agent -H bash --login -c 'agentlinux install rtk'
  assert_exit_zero "ENABLE-01 (install)"
  assert_no_eacces "ENABLE-01 (install)" "$output"

  # The binary lands in the agent-owned ~/.local/bin — never a /usr/local shim
  # (the exact anti-pattern that breaks self-update). command -v must resolve
  # there and nowhere else.
  run sudo -u agent -H bash --login -c 'command -v rtk'
  assert_exit_zero "ENABLE-01 (resolve)"
  case "${output}" in
    /home/agent/.local/bin/rtk) : ;;
    *) __fail "ENABLE-01" "rtk resolves at /home/agent/.local/bin/rtk (no /usr/local shim)" "${output:-<empty>}" "$LOG" ;;
  esac

  # WORK-02 version-lock: --version contains the catalog pin (jq-derived).
  run sudo -u agent -H bash --login -c 'rtk --version'
  assert_exit_zero "ENABLE-01 (version)"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "WORK-02" "rtk --version contains pinned ${pinned}" "${output:-<empty>}" "$LOG"
  fi

  # Seed rtk's config + cache dirs (with a file inside) BEFORE the remove so the
  # post-remove `! test -e` assertions actually kill a deletion regression — without
  # this seeding the dirs never exist and the assertions pass vacuously.
  run sudo -u agent -H bash --login -c \
    'mkdir -p /home/agent/.config/rtk /home/agent/.local/share/rtk && : >/home/agent/.config/rtk/state'
  assert_exit_zero "ENABLE-01 (seed residue dirs)"

  # Symmetric remove: binary off PATH AND config + cache deleted (no residue).
  run sudo -u agent -H bash --login -c 'agentlinux remove --force rtk'
  assert_exit_zero "ENABLE-01 (remove)"
  assert_no_eacces "ENABLE-01 (remove)" "$output"

  run sudo -u agent -H bash --login -c 'command -v rtk'
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-01" "rtk NOT on PATH after remove" "still resolves: ${output}" "$LOG"
  run sudo -u agent -H bash --login -c 'test -e /home/agent/.config/rtk'
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-01" "/home/agent/.config/rtk deleted on remove (no residue)" "still exists" "$LOG"
  run sudo -u agent -H bash --login -c 'test -e /home/agent/.local/share/rtk'
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-01" "/home/agent/.local/share/rtk deleted on remove (no residue)" "still exists" "$LOG"

  # Idempotent re-remove (uninstall.sh guards every destructive step / || true).
  run sudo -u agent -H bash --login -c 'agentlinux remove --force rtk'
  assert_exit_zero "ENABLE-01 (idempotent remove)"
}

@test "WORK-02: rtk install does NOT mutate ~/.claude; opt-in rtk init -g wires the hook; remove reverts it (no orphan)" {
  # Honest pre-condition: drop any rtk-owned ~/.claude artifacts a prior run left.
  # Never touches the user-owned settings.json itself (T-28-14).
  sudo -u agent -H bash --login -c \
    'rm -f /home/agent/.claude/RTK.md /home/agent/.claude/settings.json.bak' >/dev/null 2>&1 || true

  # Seed a USER-owned ~/.claude/settings.json carrying a sentinel key BEFORE rtk
  # touches anything. Two jobs: (1) rtk init now has a real prior file to back up,
  # so the settings.json.bak it creates is a genuine artifact — making its later
  # removal a real kill, not vacuous (D3). (2) the sentinel key lets us prove the
  # remove leaves the user's settings.json untouched (T-28-14 trust boundary, D4).
  sudo -u agent -H bash --login -c \
    'mkdir -p /home/agent/.claude && printf "%s\n" "{\"_al28_sentinel\":\"keepme\"}" >/home/agent/.claude/settings.json' >/dev/null 2>&1 || true

  run sudo -u agent -H bash --login -c 'agentlinux install rtk'
  assert_exit_zero "WORK-02 (install)"
  assert_no_eacces "WORK-02 (install)" "$output"

  # Opt-in contract: a bare install MUST NOT write rtk's ~/.claude hook artifact.
  run sudo -u agent -H bash --login -c 'test -e /home/agent/.claude/RTK.md'
  [[ "${status}" -ne 0 ]] \
    || __fail "WORK-02" "install does NOT create /home/agent/.claude/RTK.md (opt-in)" "RTK.md present after a bare install" "$LOG"

  # The user opts in explicitly. --auto-patch keeps it non-interactive.
  run sudo -u agent -H bash --login -c 'rtk init -g --auto-patch'
  assert_exit_zero "WORK-02 (rtk init -g)"
  run sudo -u agent -H bash --login -c 'test -e /home/agent/.claude/RTK.md'
  [[ "${status}" -eq 0 ]] \
    || __fail "WORK-02" "rtk init -g wires /home/agent/.claude/RTK.md" "RTK.md absent after opt-in init" "$LOG"

  # D3: patching the seeded settings.json must have produced a real backup. Assert
  # it EXISTS now so the post-remove "settings.json.bak gone" assertion below is a
  # genuine kill rather than a vacuous pass on a never-created file.
  run sudo -u agent -H bash --login -c 'test -e /home/agent/.claude/settings.json.bak'
  [[ "${status}" -eq 0 ]] \
    || __fail "WORK-02" "rtk init -g backs up settings.json to settings.json.bak" "settings.json.bak absent after opt-in init" "$LOG"

  # Symmetric remove reverts the opt-in hook AND drops the backup residue — no
  # orphan hook pointing at a deleted binary.
  run sudo -u agent -H bash --login -c 'agentlinux remove --force rtk'
  assert_exit_zero "WORK-02 (remove)"
  assert_no_eacces "WORK-02 (remove)" "$output"
  run sudo -u agent -H bash --login -c 'test -e /home/agent/.claude/RTK.md'
  [[ "${status}" -ne 0 ]] \
    || __fail "WORK-02" "remove reverts the opt-in hook (RTK.md gone, no orphan)" "RTK.md survived remove" "$LOG"
  run sudo -u agent -H bash --login -c 'test -e /home/agent/.claude/settings.json.bak'
  [[ "${status}" -ne 0 ]] \
    || __fail "WORK-02" "remove drops rtk's settings.json.bak residue" "settings.json.bak survived remove" "$LOG"

  # D4 (T-28-14 trust boundary): the user-owned settings.json — and its sentinel
  # key — must SURVIVE the remove untouched. rtk reverts only its own hook entry.
  run sudo -u agent -H bash --login -c 'jq -r "._al28_sentinel // empty" /home/agent/.claude/settings.json'
  if [[ "${output}" != "keepme" ]]; then
    __fail "WORK-02" "remove leaves the user settings.json + sentinel intact (T-28-14)" "_al28_sentinel=[${output:-<empty>}]" "$LOG"
  fi

  # Drop the test's own sentinel settings.json (this @test owns it — not a shared
  # rtk artifact), so it does not leak into later @test files.
  sudo -u agent -H bash --login -c 'rm -f /home/agent/.claude/settings.json' >/dev/null 2>&1 || true
}

@test "ENABLE-01: a mismatched checksum aborts BEFORE extract (pre-existing binary not replaced)" {
  # Verify-before-extract security gate (threat T-28-12), driven at the INSTALL
  # level — not just al_pb_fetch_and_verify in isolation. We seed a SENTINEL binary
  # at the real install destination (/home/agent/.local/bin/rtk), then replicate
  # al_pb_install's exact ordering (`fetch_and_verify && extract_install`) against a
  # LOCALLY-corrupted asset + wrong-hash checksums.txt over file:// (offline/green
  # in Docker). A real gzip is used so the rejection is the SHA256 mismatch
  # specifically — not the gzip-magic guard. The binding assertion: because verify
  # fails, extract_install is never reached, so the pre-existing sentinel binary is
  # byte-for-byte UNCHANGED (no extract, no replace).
  run sudo -u agent -H bash --login -c '
    set -u
    helper="/opt/agentlinux/catalog/'"${PKG_VERSION}"'/lib/prebuilt-binary.sh"
    test -f "$helper" || { echo "MISSING_HELPER:$helper" >&2; exit 70; }
    # shellcheck source=/dev/null
    source "$helper"
    arch=$(al_pb_arch "x86_64-unknown-linux-musl" "aarch64-unknown-linux-gnu") || { echo "ASSET_DETECT_FAIL" >&2; exit 71; }
    asset="rtk-${arch}.tar.gz"
    stage=$(mktemp -d); verify=$(mktemp -d)
    dest="/home/agent/.local/bin"
    mkdir -p "$dest"
    # Seed a pre-existing binary at the real install destination.
    printf "%s" "SENTINEL" >"$dest/rtk"
    before=$(sha256sum "$dest/rtk" | cut -d" " -f1)
    trap "rm -rf \"$stage\" \"$verify\"; rm -f \"$dest/rtk\"" EXIT
    # A real gzip whose sha256 does NOT match the all-zero checksums.txt entry.
    echo "tampered-payload" | gzip -c >"$stage/$asset"
    printf "%s  %s\n" "0000000000000000000000000000000000000000000000000000000000000000" "$asset" >"$stage/checksums.txt"
    # Replicate al_pb_install ordering: extract/install runs ONLY if verify passes.
    if al_pb_fetch_and_verify "file://$stage" "$asset" "checksums.txt" "$verify"; then
      rc=0
      al_pb_extract_install "$verify" "$asset" rtk rtk "$dest"
    else
      rc=$?
      echo "VERIFY_REJECTED rc=$rc"
    fi
    after=$(sha256sum "$dest/rtk" | cut -d" " -f1)
    if [ "$before" = "$after" ]; then echo "SENTINEL_INTACT"; else echo "SENTINEL_REPLACED"; fi
    if [ "$rc" -eq 0 ]; then
      echo "VERIFY_PASSED_ON_BAD_CHECKSUM" >&2
      exit 73
    fi
    exit "$rc"
  '
  # The gate must abort non-zero ...
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-01" "mismatched checksum aborts with non-zero exit" "exit ${status}; ${output:-<empty>}" "$LOG"
  # ... reach the reject branch (verify returned non-zero) ...
  if ! printf '%s' "${output}" | grep -q 'VERIFY_REJECTED'; then
    __fail "ENABLE-01" "al_pb_fetch_and_verify rejected the mismatched checksum" "${output:-<empty>}" "$LOG"
  fi
  # ... emit a 'verification failed'-class message ...
  if ! printf '%s' "${output}" | grep -qi 'verification failed'; then
    __fail "ENABLE-01" "a 'verification failed'-class diagnostic on mismatch" "${output:-<empty>}" "$LOG"
  fi
  # ... and the pre-existing binary must be byte-unchanged (extract never reached).
  if ! printf '%s' "${output}" | grep -q 'SENTINEL_INTACT'; then
    __fail "ENABLE-01" "pre-existing binary NOT replaced when checksum mismatches" "${output:-<empty>}" "$LOG"
  fi
}

@test "OPS-01: rtk performs a real offline operation as the agent user" {
  # Phase-close OPS-01 smoke: the tool actually RUNS (not just installs) in a
  # real minimal scenario, as the agent user, with NO credential (Appendix C —
  # rtk is offline/local). Seed a uniquely-named file in a tmp dir and have rtk's
  # token-optimized `ls` proxy list it back.
  run sudo -u agent -H bash --login -c 'agentlinux install rtk'
  assert_exit_zero "OPS-01 (install)"
  assert_no_eacces "OPS-01 (install)" "$output"

  run sudo -u agent -H bash --login -c '
    set -u
    d=$(mktemp -d)
    trap "rm -rf \"$d\"" EXIT
    : >"$d/ops01_rtk_smoke_marker.txt"
    rtk ls "$d"
  '
  assert_exit_zero "OPS-01 (rtk ls)"
  if ! printf '%s' "${output}" | grep -q 'ops01_rtk_smoke_marker.txt'; then
    __fail "OPS-01" "rtk ls lists the seeded marker file (real offline op)" "${output:-<empty>}" "$LOG"
  fi
}
