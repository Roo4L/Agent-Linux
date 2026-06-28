#!/usr/bin/env bats
# tests/bats/18-distro-detect.bats — EL-01 distro-detect unit fixtures.
#
# Phase 18 (Detection + Branching Foundation) load-bearing recognition layer.
# These @tests source plugin/lib/log.sh + plugin/lib/distro_detect.sh in a fresh
# subshell, point detect_distro at a fixture /etc/os-release via the
# AGENTLINUX_OS_RELEASE_PATH seam (Task 2 adds it; defaults to /etc/os-release in
# production), and assert the return code + the exported FAMILY/VERSION.
#
# EL-01 contract surface:
#   - ubuntu 22.04/24.04/26.04 → rc 0, FAMILY=debian (preserved byte-for-byte)
#   - almalinux 9 and 9.x      → rc 0, FAMILY=rhel
#   - almalinux 8 / 10         → reject (9.x ONLY)
#   - rocky / rhel / centos / fedora → reject (ID-exact, never ID_LIKE)
#   - AGENTLINUX_SKIP_DISTRO_CHECK=1 seeds FAMILY (explicit override else
#     os-release ID else debian) instead of leaving it empty
#
# These are pure unit fixtures: no installer run, no Docker, dev-host runnable.
# Failures use a plain four-line diagnostic mirroring helpers/assertions __fail.

# Resolve the lib dir relative to this bats file so the suite runs identically on
# the Ubuntu dev host (repo root) and the Docker substrate (/opt/agentlinux-src).
LIB_DIR="${BATS_TEST_DIRNAME}/../../plugin/lib"

# __el01_fail <expected> <observed> — TST-04-style four-line diagnostic.
__el01_fail() {
  {
    printf '# FAIL: EL-01\n'
    printf '#   expected: %s\n' "$1"
    printf '#   observed: %s\n' "$2"
    printf '#   log:      plugin/lib/distro_detect.sh::detect_distro\n'
  } >&2
  return 1
}

# write_osrelease <line>... — write a fixture os-release into the bats temp dir
# and export the AGENTLINUX_OS_RELEASE_PATH seam so detect_distro reads it.
write_osrelease() {
  local f="${BATS_TEST_TMPDIR}/os-release"
  printf '%s\n' "$@" > "$f"
  export AGENTLINUX_OS_RELEASE_PATH="$f"
}

# run_detect — source log.sh + distro_detect.sh in a fresh `bash -c` (so the
# source-once `readonly` guards and exports never leak between tests), call
# detect_distro, and print the resulting FAMILY/VERSION on stdout. The exit code
# is detect_distro's return code, captured by bats into $status.
run_detect() {
  run bash -c '
    set +e
    . "$1/log.sh"
    . "$1/distro_detect.sh"
    detect_distro
    rc=$?
    printf "FAMILY=%s\n" "${AGENTLINUX_DISTRO_FAMILY:-}"
    printf "VERSION=%s\n" "${AGENTLINUX_DISTRO_VERSION:-}"
    exit "$rc"
  ' _ "$LIB_DIR"
}

@test "EL-01: ubuntu 22.04 → rc0 FAMILY=debian VERSION=22.04 (preserved)" {
  write_osrelease 'ID=ubuntu' 'VERSION_ID=22.04'
  run_detect
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 for ubuntu 22.04" "status=$status; $output"
  [[ "$output" == *"FAMILY=debian"* ]] || __el01_fail "FAMILY=debian" "$output"
  [[ "$output" == *"VERSION=22.04"* ]] || __el01_fail "VERSION=22.04" "$output"
}

@test "EL-01: ubuntu 24.04 → rc0 FAMILY=debian" {
  write_osrelease 'ID=ubuntu' 'VERSION_ID=24.04'
  run_detect
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 for ubuntu 24.04" "status=$status; $output"
  [[ "$output" == *"FAMILY=debian"* ]] || __el01_fail "FAMILY=debian" "$output"
}

@test "EL-01: ubuntu 26.04 → rc0 FAMILY=debian VERSION=26.04 (preserved)" {
  write_osrelease 'ID=ubuntu' 'VERSION_ID=26.04'
  run_detect
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 for ubuntu 26.04" "status=$status; $output"
  [[ "$output" == *"FAMILY=debian"* ]] || __el01_fail "FAMILY=debian" "$output"
  [[ "$output" == *"VERSION=26.04"* ]] || __el01_fail "VERSION=26.04" "$output"
}

@test "EL-01: ubuntu 20.04 → rejected (unsupported version, exercises ubuntu reject arm)" {
  write_osrelease 'ID=ubuntu' 'VERSION_ID=20.04'
  run_detect
  [[ "$status" -ne 0 ]] || __el01_fail "non-zero exit for ubuntu 20.04" "status=$status; $output"
  [[ "$output" == *"ubuntu"* ]] || __el01_fail "message names ubuntu" "$output"
}

@test "EL-01: almalinux 9 → rc0 FAMILY=rhel VERSION=9" {
  write_osrelease 'ID=almalinux' 'VERSION_ID=9'
  run_detect
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 for almalinux 9" "status=$status; $output"
  [[ "$output" == *"FAMILY=rhel"* ]] || __el01_fail "FAMILY=rhel" "$output"
  [[ "$output" == *"VERSION=9"* ]] || __el01_fail "VERSION=9" "$output"
}

@test "EL-01: almalinux 9.4 → rc0 FAMILY=rhel VERSION=9.4" {
  write_osrelease 'ID=almalinux' 'VERSION_ID=9.4'
  run_detect
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 for almalinux 9.4" "status=$status; $output"
  [[ "$output" == *"FAMILY=rhel"* ]] || __el01_fail "FAMILY=rhel" "$output"
  [[ "$output" == *"VERSION=9.4"* ]] || __el01_fail "VERSION=9.4" "$output"
}

@test "EL-01: almalinux 8 → rejected (9.x only)" {
  write_osrelease 'ID=almalinux' 'VERSION_ID=8'
  run_detect
  [[ "$status" -ne 0 ]] || __el01_fail "non-zero exit for almalinux 8" "status=$status; $output"
  [[ "$output" == *"almalinux"* ]] || __el01_fail "message names almalinux" "$output"
}

@test "EL-01: almalinux 10 → rejected (9.x only)" {
  write_osrelease 'ID=almalinux' 'VERSION_ID=10'
  run_detect
  [[ "$status" -ne 0 ]] || __el01_fail "non-zero exit for almalinux 10" "status=$status; $output"
}

@test "EL-01: rocky 9 → rejected (ID-exact, never ID_LIKE)" {
  write_osrelease 'ID=rocky' 'VERSION_ID=9.4' 'ID_LIKE="rhel centos fedora"'
  run_detect
  [[ "$status" -ne 0 ]] || __el01_fail "non-zero exit for rocky 9" "status=$status; $output"
}

@test "EL-01: rhel 9 → rejected (ID-exact, never ID_LIKE)" {
  write_osrelease 'ID=rhel' 'VERSION_ID=9.4' 'ID_LIKE="fedora"'
  run_detect
  [[ "$status" -ne 0 ]] || __el01_fail "non-zero exit for rhel 9" "status=$status; $output"
}

@test "EL-01: centos 9 → rejected (ID-exact, never ID_LIKE)" {
  write_osrelease 'ID=centos' 'VERSION_ID=9' 'ID_LIKE="rhel fedora"'
  run_detect
  [[ "$status" -ne 0 ]] || __el01_fail "non-zero exit for centos 9" "status=$status; $output"
}

@test "EL-01: fedora 40 → rejected (ID-exact)" {
  write_osrelease 'ID=fedora' 'VERSION_ID=40'
  run_detect
  [[ "$status" -ne 0 ]] || __el01_fail "non-zero exit for fedora 40" "status=$status; $output"
}

@test "EL-01: SKIP_DISTRO_CHECK=1 with FAMILY=rhel preset → rc0, FAMILY stays rhel" {
  write_osrelease 'ID=ubuntu' 'VERSION_ID=22.04'
  export AGENTLINUX_SKIP_DISTRO_CHECK=1
  export AGENTLINUX_DISTRO_FAMILY=rhel
  run_detect
  unset AGENTLINUX_SKIP_DISTRO_CHECK AGENTLINUX_DISTRO_FAMILY
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 with escape hatch" "status=$status; $output"
  [[ "$output" == *"FAMILY=rhel"* ]] || __el01_fail "explicit FAMILY=rhel honored" "$output"
}

@test "EL-01: SKIP_DISTRO_CHECK=1 no preset, fixture ID=almalinux → seeds FAMILY=rhel" {
  write_osrelease 'ID=almalinux' 'VERSION_ID=9.4'
  export AGENTLINUX_SKIP_DISTRO_CHECK=1
  run_detect
  unset AGENTLINUX_SKIP_DISTRO_CHECK
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 with escape hatch" "status=$status; $output"
  [[ "$output" == *"FAMILY=rhel"* ]] || __el01_fail "seeded FAMILY=rhel from os-release ID" "$output"
}

@test "EL-01: SKIP_DISTRO_CHECK=1 no preset, no readable os-release → defaults FAMILY=debian" {
  export AGENTLINUX_SKIP_DISTRO_CHECK=1
  export AGENTLINUX_OS_RELEASE_PATH="${BATS_TEST_TMPDIR}/does-not-exist"
  run_detect
  unset AGENTLINUX_SKIP_DISTRO_CHECK AGENTLINUX_OS_RELEASE_PATH
  [[ "$status" -eq 0 ]] || __el01_fail "exit 0 with escape hatch" "status=$status; $output"
  [[ "$output" == *"FAMILY=debian"* ]] || __el01_fail "default FAMILY=debian" "$output"
}
