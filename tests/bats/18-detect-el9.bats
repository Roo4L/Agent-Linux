#!/usr/bin/env bats
# tests/bats/18-detect-el9.bats — EL-07 brownfield EL9 detection unit fixtures.
#
# Phase 18 (Detection + Branching Foundation) — the rhel arm of the brownfield
# detection layer. These @tests prove that, on AGENTLINUX_DISTRO_FAMILY=rhel:
#   - detect/nodejs.sh classifies a pre-existing Node by its REAL EL9 source:
#       NodeSource-RPM   (rpm RELEASE carries the `nodesource` substring AND a
#                         path emitted by nodesource_repo_paths is present)
#       AppStream-module (rpm has nodejs but the RELEASE lacks `nodesource`) —
#                         a DISTINCT source class, never miscounted as NodeSource
#       absent           (rpm -q nodejs fails) → no nodejs entry
#   - detect/user.sh branches the sudo-capability probe BINARY to /usr/bin/dnf
#     while keeping the DET-01 contract field name `can_sudo_apt` unchanged
#   - detection stays READ-ONLY — only `rpm -q` / file probes, never a write-path
#     dnf subcommand (which would touch /var/cache/dnf and break the read-only
#     invariant 15-detection.bats asserts).
#
# These are pure dev-host-runnable unit fixtures (no Docker, no root, no real
# EL9 host): a PATH-stub harness shadows rpm / dnf / sudo with capturing stubs,
# the NodeSource yum-repo presence is driven through an in-test override of the
# nodesource_repo_paths (pkg.sh) lockstep verb pointed at a temp path the @test
# creates/removes, and a configurable rpm stub emits the
# `%{VERSION}-%{RELEASE}` line that distinguishes the NodeSource-RPM vs
# AppStream-module cases. real jq builds + parses the emitted fragment.
#
# Open Q1 (carried): the EXACT `%{RELEASE}` string is live-verified on
# almalinux:9 in Phase 19; the classifier keys on the `nodesource` substring.

LIB_DIR="${BATS_TEST_DIRNAME}/../../plugin/lib"

# __el07_fail <expected> <observed> — TST-04-style diagnostic.
__el07_fail() {
  {
    printf '# FAIL: EL-07\n'
    printf '#   expected: %s\n' "$1"
    printf '#   observed: %s\n' "$2"
    printf '#   capture:  %s\n' "${CAPTURE:-unset}"
  } >&2
  return 1
}

# setup — build the PATH-stub bindir, a capture file, temp fragment paths, and
# an empty temp home (no version-manager dirs, so the per-user manager scans are
# no-ops). The rpm stub emits $RPM_NODEJS_NEVR (set per @test) on stdout and
# exits 0; with NEVR empty it exits 1 to simulate an absent package. The sudo
# stub logs its args and exits 1 (probe fails deterministically → can_sudo_apt
# and home_writable are false) WITHOUT exec'ing the absolute-path binary. The
# dnf stub logs + exits 0 and must never be reached by a read-only probe.
setup() {
  STUBDIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$STUBDIR"
  CAPTURE="${BATS_TEST_TMPDIR}/capture.log"
  : >"$CAPTURE"
  FRAGMENT="${BATS_TEST_TMPDIR}/nodejs.json"
  USER_FRAGMENT="${BATS_TEST_TMPDIR}/user.json"
  HOME_DIR="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME_DIR"
  # The temp stand-in for the NodeSource yum-repo file; presence is toggled per
  # @test by touching / rm-ing this path, and the nodesource_repo_paths override
  # echoes it so the rhel detect gate reads it as the repo-presence signal.
  REPO_PATH="${BATS_TEST_TMPDIR}/nodesource-nodejs.repo"
  # A real, existing user so detect::user_probe takes the present-user branch and
  # actually runs the sudo-capability probe (a non-existent user short-circuits).
  USERNAME="$(id -un)"

  # rpm: configurable presence/version via $RPM_NODEJS_NEVR.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''rpm %%s\\n'\'' "$*" >> "$AGENTLINUX_TEST_CAPTURE"\n'
    printf 'if [[ -n "${RPM_NODEJS_NEVR:-}" ]]; then\n'
    printf '  printf '\''%%s\\n'\'' "$RPM_NODEJS_NEVR"\n'
    printf '  exit 0\n'
    printf 'fi\n'
    printf 'exit 1\n'
  } >"$STUBDIR/rpm"
  chmod +x "$STUBDIR/rpm"

  # dnf: log + exit 0. A read-only probe must NEVER invoke it.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''dnf %%s\\n'\'' "$*" >> "$AGENTLINUX_TEST_CAPTURE"\n'
    printf 'exit 0\n'
  } >"$STUBDIR/dnf"
  chmod +x "$STUBDIR/dnf"

  # sudo: log + exit 1 (never exec the absolute-path probe binary on the dev host).
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''sudo %%s\\n'\'' "$*" >> "$AGENTLINUX_TEST_CAPTURE"\n'
    printf 'exit 1\n'
  } >"$STUBDIR/sudo"
  chmod +x "$STUBDIR/sudo"
}

# run_nodejs_probe <family> <nevr> <repo_present:0|1> — source the libs + the
# detect fragment in a fresh subshell under the stubbed PATH, override the
# lockstep nodesource_repo_paths verb to echo the temp repo path, and run the
# probe against $FRAGMENT. The @test then jq-asserts the emitted source class.
run_nodejs_probe() {
  local family="$1" nevr="$2" repo_present="$3"
  if [[ "$repo_present" == "1" ]]; then : >"$REPO_PATH"; else rm -f "$REPO_PATH"; fi
  run env \
    AGENTLINUX_DISTRO_FAMILY="$family" \
    RPM_NODEJS_NEVR="$nevr" \
    AGENTLINUX_TEST_CAPTURE="$CAPTURE" \
    AGENTLINUX_TEST_REPO_PATH="$REPO_PATH" \
    FRAGMENT="$FRAGMENT" \
    HOME_DIR="$HOME_DIR" \
    PATH="$STUBDIR:$PATH" \
    bash -c '
      set +e
      . "$1/log.sh"
      . "$1/as_user.sh"
      . "$1/pkg.sh"
      . "$1/detect/nodejs.sh"
      # Drive repo-file presence through the lockstep verb (pkg.sh) the rhel gate
      # calls — the @test owns the temp path it points at.
      nodesource_repo_paths() { printf "%s\n" "$AGENTLINUX_TEST_REPO_PATH"; }
      detect::nodejs_probe testuser "$HOME_DIR" "$FRAGMENT"
    ' _ "$LIB_DIR"
}

# run_user_probe <family> — source log.sh + as_user.sh + detect/user.sh and run
# the install-user probe (against the real current user) so the sudo-capability
# probe branch actually executes.
run_user_probe() {
  local family="$1"
  run env \
    AGENTLINUX_DISTRO_FAMILY="$family" \
    AGENTLINUX_TEST_CAPTURE="$CAPTURE" \
    USER_FRAGMENT="$USER_FRAGMENT" \
    PATH="$STUBDIR:$PATH" \
    bash -c '
      set +e
      . "$1/log.sh"
      . "$1/as_user.sh"
      . "$1/detect/user.sh"
      detect::user_probe "$2" "$USER_FRAGMENT"
    ' _ "$LIB_DIR" "$USERNAME"
}

# ---- detect/nodejs.sh rhel classification ---------------------------------

@test "EL-07: rhel NodeSource-RPM (release has nodesource + yum repo present) classifies nodesource" {
  run_nodejs_probe rhel "22.14.0-1nodesource.el9" 1
  [[ "$status" -eq 0 ]] || __el07_fail "nodejs_probe rc 0" "status=$status; $output"
  local n
  n=$(jq -r '.nodejs | map(select(.source == "nodesource")) | length' "$FRAGMENT")
  [[ "$n" == "1" ]] \
    || __el07_fail "exactly one source=nodesource entry" "nodesource_count=$n; $(cat "$FRAGMENT")"
  # The version emitted is the rpm NEVR — proves the rpm -q arm fed the entry.
  jq -e '.nodejs | map(select(.source == "nodesource" and (.version | test("nodesource")))) | length == 1' "$FRAGMENT" >/dev/null \
    || __el07_fail "nodesource entry version carries the rpm NEVR" "$(cat "$FRAGMENT")"
}

@test "EL-07: rhel AppStream-module (rpm has nodejs, release lacks nodesource) is a DISTINCT non-nodesource class" {
  # rpm reports a nodejs NEVR with no `nodesource` marker and no yum repo file.
  run_nodejs_probe rhel "22.13.1-1.el9" 0
  [[ "$status" -eq 0 ]] || __el07_fail "nodejs_probe rc 0" "status=$status; $output"
  local ns appstream
  ns=$(jq -r '.nodejs | map(select(.source == "nodesource")) | length' "$FRAGMENT")
  appstream=$(jq -r '.nodejs | map(select(.source == "distro_dnf")) | length' "$FRAGMENT")
  [[ "$ns" == "0" ]] \
    || __el07_fail "AppStream Node is NOT classified nodesource" "nodesource_count=$ns; $(cat "$FRAGMENT")"
  [[ "$appstream" == "1" ]] \
    || __el07_fail "AppStream Node classified as the distinct distro_dnf class" "distro_dnf_count=$appstream; $(cat "$FRAGMENT")"
}

@test "EL-07: rhel + rpm -q nodejs fails (absent) emits no rpm-sourced nodejs entry" {
  run_nodejs_probe rhel "" 0
  [[ "$status" -eq 0 ]] || __el07_fail "nodejs_probe rc 0" "status=$status; $output"
  local rpm_sourced
  rpm_sourced=$(jq -r '.nodejs | map(select(.source == "nodesource" or .source == "distro_dnf")) | length' "$FRAGMENT")
  [[ "$rpm_sourced" == "0" ]] \
    || __el07_fail "no nodesource/distro_dnf entry when rpm reports absent" "count=$rpm_sourced; $(cat "$FRAGMENT")"
}

@test "EL-07: rhel detection is READ-ONLY — no write-path dnf subcommand invoked" {
  run_nodejs_probe rhel "22.14.0-1nodesource.el9" 1
  [[ "$status" -eq 0 ]] || __el07_fail "nodejs_probe rc 0" "status=$status; $output"
  # The rhel arm probes with `rpm -q` + file tests only; the dnf stub must never
  # be reached, and no write-path subcommand may appear in the capture.
  ! grep -qE '^dnf ' "$CAPTURE" \
    || __el07_fail "no direct dnf invocation during detection" "$(cat "$CAPTURE")"
  ! grep -qE 'dnf (install|makecache|module|update|upgrade|remove|autoremove)' "$CAPTURE" \
    || __el07_fail "no write-path dnf subcommand during detection" "$(cat "$CAPTURE")"
}

# ---- detect/user.sh sudo-probe binary branch (contract field preserved) ----

@test "EL-07: rhel user probe branches the sudo-capability binary to /usr/bin/dnf --version" {
  run_user_probe rhel
  grep -q '/usr/bin/dnf --version' "$CAPTURE" \
    || __el07_fail "rhel probe binary is /usr/bin/dnf --version" "$(cat "$CAPTURE")"
  ! grep -q '/usr/bin/apt-get' "$CAPTURE" \
    || __el07_fail "no apt-get probe on rhel" "$(cat "$CAPTURE")"
}

@test "EL-07: user probe preserves the can_sudo_apt JSON field name after a rhel dnf probe" {
  run_user_probe rhel
  jq -e '.user | has("can_sudo_apt")' "$USER_FRAGMENT" >/dev/null \
    || __el07_fail "JSON field user.can_sudo_apt emitted (contract preserved)" "$(cat "$USER_FRAGMENT")"
  jq -e '.user | has("can_sudo_pkg") | not' "$USER_FRAGMENT" >/dev/null \
    || __el07_fail "no renamed can_sudo_pkg field" "$(cat "$USER_FRAGMENT")"
}
