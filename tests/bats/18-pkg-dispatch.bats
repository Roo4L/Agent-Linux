#!/usr/bin/env bats
# tests/bats/18-pkg-dispatch.bats — EL-02 package-verb dispatch unit fixtures.
#
# Phase 18 (Detection + Branching Foundation) — the load-bearing apt↔dnf branch.
# These @tests source plugin/lib/log.sh + plugin/lib/idempotency.sh +
# plugin/lib/pkg.sh in a fresh `bash -c` subshell (so the source-once `readonly`
# guards never leak between tests), set AGENTLINUX_DISTRO_FAMILY, call one verb,
# and assert which package-manager binary the verb dispatched to.
#
# Dispatch is proven with a PATH-stub harness: `setup` writes executable stubs
# for apt-get / dnf / rpm / dpkg-query / curl / locale / locale-gen /
# update-locale into a temp bindir that echo "<tool> <args>" to a capture file
# (and exit 0), then prepends the bindir to PATH. Each @test greps the capture
# file for the expected tool+args. No installer run, no Docker, no root — these
# are pure dev-host-runnable unit fixtures.
#
# EL-02 contract surface (per AGENTLINUX_DISTRO_FAMILY):
#   rhel   → pkg_install→dnf, pkg_is_installed→rpm -q, remove/auto→dnf,
#            nodesource_setup→rpm.nodesource.com, prereqs→ca-certificates ONLY
#            (never curl/gnupg/apt-transport-https), repo path→yum.repos.d,
#            locale_ensure→write /etc/locale.conf
#   debian → pkg_install→apt-get, pkg_is_installed→dpkg-query, remove/auto→apt-get,
#            nodesource_setup→deb.nodesource.com, prereqs→curl gnupg ca-certificates
#            apt-transport-https (byte-for-byte the current call site), repo
#            paths→apt sources.list.d + preferences.d

load 'helpers/tmpdir'

LIB_DIR="${BATS_TEST_DIRNAME}/../../plugin/lib"

# __elNN_fail <id> <expected> <observed> — TST-04-style four-line diagnostic.
__elNN_fail() {
  {
    printf '# FAIL: %s\n' "$1"
    printf '#   expected: %s\n' "$2"
    printf '#   observed: %s\n' "$3"
    printf '#   log:      plugin/lib/pkg.sh dispatch (capture: %s)\n' "${CAPTURE:-unset}"
  } >&2
  return 1
}

# __el02_fail / __el03_fail / __el04_fail / __el05_fail — per-requirement thin
# wrappers so each new @test cites its own EL-ID in the diagnostic banner.
__el02_fail() { __elNN_fail EL-02 "$1" "$2"; }
__el03_fail() { __elNN_fail EL-03 "$1" "$2"; }
__el04_fail() { __elNN_fail EL-04 "$1" "$2"; }
__el05_fail() { __elNN_fail EL-05 "$1" "$2"; }

# setup — build the PATH-stub bindir + an empty capture file. Every stubbed tool
# appends "<tool> <args>" to $CAPTURE and exits 0; `locale`/`dpkg-query` also emit
# the stdout the verbs grep so the success path is exercised.
setup() {
  # Resolve a writable temp root that is safe even on bats < 1.4 (Ubuntu 22.04
  # ships 1.2.1, which leaves BATS_TEST_TMPDIR unset → a bare expansion of
  # "${BATS_TEST_TMPDIR}/bin" would be "/bin" and the stubs below would clobber
  # the real /usr/bin/{apt-get,dnf,rpm,...} via usr-merge). See helpers/tmpdir.bash.
  al_tmpdir_init || { printf 'setup: no safe temp dir\n' >&2; return 1; }
  STUBDIR="$AL_TMPDIR/bin"
  mkdir -p "$STUBDIR"
  CAPTURE="$AL_TMPDIR/capture.log"
  : > "$CAPTURE"
  export AGENTLINUX_TEST_CAPTURE="$CAPTURE"
  # Temp stand-in for the rhel locale write target (write_file_atomic is
  # overridden in-test to land here instead of the root-owned /etc/locale.conf).
  LOCALE_CONF="$AL_TMPDIR/locale.conf"
  export AGENTLINUX_TEST_LOCALE_CONF="$LOCALE_CONF"

  local tool
  for tool in apt-get dnf rpm curl locale-gen update-locale; do
    {
      printf '#!/usr/bin/env bash\n'
      printf 'printf '\''%s %%s\\n'\'' "$*" >> "$AGENTLINUX_TEST_CAPTURE"\n' "$tool"
      printf 'exit 0\n'
    } > "$STUBDIR/$tool"
    chmod +x "$STUBDIR/$tool"
  done

  # dpkg-query: log + emit the "install ok installed" line pkg_is_installed greps.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''dpkg-query %%s\\n'\'' "$*" >> "$AGENTLINUX_TEST_CAPTURE"\n'
    printf 'printf '\''install ok installed\\n'\''\n'
    printf 'exit 0\n'
  } > "$STUBDIR/dpkg-query"
  chmod +x "$STUBDIR/dpkg-query"

  # locale: log + always emit a C.UTF-8 line so the locale_ensure `locale -a` gate
  # (`grep -Eiq '^c\.utf-?8$'`) passes on both arms.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''locale %%s\\n'\'' "$*" >> "$AGENTLINUX_TEST_CAPTURE"\n'
    printf 'printf '\''C.UTF-8\\n'\''\n'
    printf 'exit 0\n'
  } > "$STUBDIR/locale"
  chmod +x "$STUBDIR/locale"

  PATH="$STUBDIR:$PATH"
  export PATH
}

teardown() {
  al_tmpdir_teardown
}

# run_verb <FAMILY> <verb> [args...] — source the three libs in a fresh subshell
# under the stubbed PATH and invoke the verb. Captured stdout/stderr land in
# $output/$status; dispatched tool calls land in $CAPTURE.
run_verb() {
  local family="$1"; shift
  run env AGENTLINUX_DISTRO_FAMILY="$family" bash -c '
    set +e
    . "$1/log.sh"
    . "$1/idempotency.sh"
    . "$1/pkg.sh"
    shift
    "$@"
  ' _ "$LIB_DIR" "$@"
}

# run_locale_ensure <FAMILY> — like run_verb but overrides write_file_atomic so
# the rhel arm's /etc/locale.conf write is captured to a writable temp path
# (keeps the fixture root-free); still logs the verbatim args for assertion.
run_locale_ensure() {
  local family="$1"
  run env AGENTLINUX_DISTRO_FAMILY="$family" bash -c '
    set +e
    . "$1/log.sh"
    . "$1/idempotency.sh"
    . "$1/pkg.sh"
    write_file_atomic() {
      printf "write_file_atomic %s\n" "$*" >> "$AGENTLINUX_TEST_CAPTURE"
      cat > "$AGENTLINUX_TEST_LOCALE_CONF"
    }
    locale_ensure C.UTF-8
  ' _ "$LIB_DIR"
}

# ---- pkg_install ----------------------------------------------------------

@test "EL-02: pkg_install jq on rhel dispatches to dnf (not apt-get)" {
  run_verb rhel pkg_install jq
  [[ "$status" -eq 0 ]] || __el02_fail "pkg_install rc 0" "status=$status; $output"
  grep -q 'dnf install -y --setopt=install_weak_deps=False jq' "$CAPTURE" \
    || __el02_fail "dnf install ... jq in capture" "$(cat "$CAPTURE")"
  ! grep -q 'apt-get' "$CAPTURE" \
    || __el02_fail "no apt-get on rhel" "$(cat "$CAPTURE")"
}

@test "EL-02: pkg_install jq on debian dispatches to apt-get (not dnf)" {
  run_verb debian pkg_install jq
  [[ "$status" -eq 0 ]] || __el02_fail "pkg_install rc 0" "status=$status; $output"
  grep -q 'apt-get install -y --no-install-recommends jq' "$CAPTURE" \
    || __el02_fail "apt-get install ... jq in capture" "$(cat "$CAPTURE")"
  grep -q 'apt-get update' "$CAPTURE" \
    || __el02_fail "apt-get update first (byte-for-byte)" "$(cat "$CAPTURE")"
  ! grep -q 'dnf' "$CAPTURE" \
    || __el02_fail "no dnf on debian" "$(cat "$CAPTURE")"
}

# ---- pkg_is_installed -----------------------------------------------------

@test "EL-02: pkg_is_installed on rhel uses rpm -q (not dpkg-query)" {
  run_verb rhel pkg_is_installed nodejs
  grep -q 'rpm -q nodejs' "$CAPTURE" \
    || __el02_fail "rpm -q nodejs in capture" "$(cat "$CAPTURE")"
  ! grep -q 'dpkg-query' "$CAPTURE" \
    || __el02_fail "no dpkg-query on rhel" "$(cat "$CAPTURE")"
}

@test "EL-02: pkg_is_installed on debian uses dpkg-query (not rpm)" {
  run_verb debian pkg_is_installed nodejs
  grep -q 'dpkg-query' "$CAPTURE" \
    || __el02_fail "dpkg-query in capture" "$(cat "$CAPTURE")"
  ! grep -q 'rpm -q' "$CAPTURE" \
    || __el02_fail "no rpm on debian" "$(cat "$CAPTURE")"
}

# ---- pkg_remove / pkg_autoremove ------------------------------------------

@test "EL-02: pkg_remove + pkg_autoremove dispatch dnf on rhel, apt-get on debian" {
  run_verb rhel pkg_remove nodejs
  grep -q 'dnf remove -y nodejs' "$CAPTURE" \
    || __el02_fail "dnf remove -y nodejs" "$(cat "$CAPTURE")"
  : > "$CAPTURE"
  run_verb rhel pkg_autoremove
  grep -q 'dnf autoremove -y' "$CAPTURE" \
    || __el02_fail "dnf autoremove -y" "$(cat "$CAPTURE")"
  : > "$CAPTURE"
  run_verb debian pkg_remove nodejs
  grep -q 'apt-get purge -y nodejs' "$CAPTURE" \
    || __el02_fail "apt-get purge -y nodejs" "$(cat "$CAPTURE")"
  : > "$CAPTURE"
  run_verb debian pkg_autoremove
  grep -q 'apt-get autoremove -y' "$CAPTURE" \
    || __el02_fail "apt-get autoremove -y" "$(cat "$CAPTURE")"
}

# ---- nodesource_setup -----------------------------------------------------

@test "EL-02: nodesource_setup on rhel curls rpm.nodesource.com" {
  run_verb rhel nodesource_setup
  grep -q 'rpm.nodesource.com/setup_22.x' "$CAPTURE" \
    || __el02_fail "curl rpm.nodesource.com/setup_22.x" "$(cat "$CAPTURE")"
  ! grep -q 'deb.nodesource.com' "$CAPTURE" \
    || __el02_fail "no deb.nodesource.com on rhel" "$(cat "$CAPTURE")"
}

@test "EL-02: nodesource_setup on debian curls deb.nodesource.com" {
  run_verb debian nodesource_setup
  grep -q 'deb.nodesource.com/setup_22.x' "$CAPTURE" \
    || __el02_fail "curl deb.nodesource.com/setup_22.x" "$(cat "$CAPTURE")"
  ! grep -q 'rpm.nodesource.com' "$CAPTURE" \
    || __el02_fail "no rpm.nodesource.com on debian" "$(cat "$CAPTURE")"
}

@test "EL-03: nodesource_setup on rhel fetches the Node 22 RPM setup script (rc 0)" {
  # EL-03's Phase-18 unit surface: the rhel arm fetches the pinned NodeSource
  # Node 22 RPM bootstrap (rpm.nodesource.com/setup_22.x) and succeeds. The live
  # `dnf install nodejs` + RT-01 `node >= 22` guard is owned by Phase 19/20.
  run_verb rhel nodesource_setup
  [[ "$status" -eq 0 ]] || __el03_fail "nodesource_setup rc 0 on rhel" "status=$status; $output"
  grep -q 'rpm.nodesource.com/setup_22.x' "$CAPTURE" \
    || __el03_fail "curl rpm.nodesource.com/setup_22.x (Node 22 RPM path)" "$(cat "$CAPTURE")"
}

# ---- nodesource_module_reset (AppStream-module-wins defense, Pitfall 4) ----

@test "EL-03: nodesource_module_reset on rhel runs dnf module reset nodejs" {
  # Pitfall 4: setup_22.x does NOT defuse the AppStream `nodejs` module, so the
  # older distro module could win over the NodeSource repo. The rhel arm resets
  # it explicitly; a no-op mutation of this arm must fail here.
  run_verb rhel nodesource_module_reset
  [[ "$status" -eq 0 ]] || __el03_fail "module_reset rc 0 on rhel" "status=$status; $output"
  grep -q 'dnf -y module reset nodejs' "$CAPTURE" \
    || __el03_fail "dnf -y module reset nodejs in capture" "$(cat "$CAPTURE")"
}

@test "EL-03: nodesource_module_reset on debian is a no-op (no dnf)" {
  run_verb debian nodesource_module_reset
  [[ "$status" -eq 0 ]] || __el03_fail "module_reset rc 0 on debian" "status=$status; $output"
  ! grep -q 'dnf' "$CAPTURE" \
    || __el03_fail "debian module_reset invokes no dnf (no-op)" "$(cat "$CAPTURE")"
}

# ---- nodesource_prereqs (divergent package set) ---------------------------

@test "EL-02: nodesource_prereqs on rhel installs ONLY ca-certificates" {
  run_verb rhel nodesource_prereqs
  grep -q 'dnf install -y --setopt=install_weak_deps=False ca-certificates' "$CAPTURE" \
    || __el02_fail "dnf install ... ca-certificates" "$(cat "$CAPTURE")"
  # Pitfall 6: never curl (curl-minimal conflict); gnupg/apt-transport-https do
  # not exist on EL9.
  ! grep -Eq 'curl|gnupg|apt-transport-https' "$CAPTURE" \
    || __el02_fail "rhel prereqs are ca-certificates ONLY" "$(cat "$CAPTURE")"
}

@test "EL-02: nodesource_prereqs on debian preserves the current apt prereq set byte-for-byte" {
  run_verb debian nodesource_prereqs
  grep -q 'apt-get update' "$CAPTURE" \
    || __el02_fail "apt-get update first" "$(cat "$CAPTURE")"
  grep -q 'apt-get install -y --no-install-recommends curl gnupg ca-certificates apt-transport-https' "$CAPTURE" \
    || __el02_fail "verbatim curl gnupg ca-certificates apt-transport-https" "$(cat "$CAPTURE")"
}

# ---- nodesource_repo_paths ------------------------------------------------

@test "EL-02: nodesource_repo_paths prints the yum repo path on rhel" {
  run_verb rhel nodesource_repo_paths
  [[ "$status" -eq 0 ]] || __el02_fail "repo_paths rc 0" "status=$status; $output"
  [[ "$output" == *"/etc/yum.repos.d/nodesource-nodejs.repo"* ]] \
    || __el02_fail "yum.repos.d/nodesource-nodejs.repo on stdout" "$output"
  [[ "$output" != *"sources.list.d"* ]] \
    || __el02_fail "no apt paths on rhel" "$output"
}

@test "EL-02: nodesource_repo_paths prints the apt sources paths on debian" {
  run_verb debian nodesource_repo_paths
  [[ "$status" -eq 0 ]] || __el02_fail "repo_paths rc 0" "status=$status; $output"
  [[ "$output" == *"/etc/apt/sources.list.d/nodesource.sources"* ]] \
    || __el02_fail "nodesource.sources on stdout" "$output"
  [[ "$output" == *"/etc/apt/sources.list.d/nodesource.list"* ]] \
    || __el02_fail "nodesource.list on stdout" "$output"
  [[ "$output" != *"yum.repos.d"* ]] \
    || __el02_fail "no yum paths on debian" "$output"
}

# ---- locale_ensure --------------------------------------------------------

@test "EL-02: locale_ensure on rhel writes /etc/locale.conf via write_file_atomic" {
  run_locale_ensure rhel
  [[ "$status" -eq 0 ]] || __el02_fail "locale_ensure rc 0" "status=$status; $output"
  grep -q 'write_file_atomic 0644 /etc/locale.conf' "$CAPTURE" \
    || __el02_fail "write_file_atomic 0644 /etc/locale.conf" "$(cat "$CAPTURE")"
  grep -q 'LANG=C.UTF-8' "$AGENTLINUX_TEST_LOCALE_CONF" \
    || __el02_fail "LANG=C.UTF-8 written to locale.conf" "$(cat "$AGENTLINUX_TEST_LOCALE_CONF" 2>/dev/null)"
  grep -q 'LC_ALL=C.UTF-8' "$AGENTLINUX_TEST_LOCALE_CONF" \
    || __el02_fail "LC_ALL=C.UTF-8 written to locale.conf" "$(cat "$AGENTLINUX_TEST_LOCALE_CONF" 2>/dev/null)"
}

@test "EL-02: locale_ensure on debian keeps the locale-gen path (not locale.conf)" {
  run_verb debian locale_ensure C.UTF-8
  [[ "$status" -eq 0 ]] || __el02_fail "locale_ensure rc 0" "status=$status; $output"
  grep -q 'update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8' "$CAPTURE" \
    || __el02_fail "update-locale on debian arm" "$(cat "$CAPTURE")"
  ! grep -q 'write_file_atomic' "$CAPTURE" \
    || __el02_fail "debian arm does not write locale.conf" "$(cat "$CAPTURE")"
}

@test "EL-04: locale_ensure writes /etc/locale.conf with LANG/LC_ALL=C.UTF-8 on rhel; debian keeps locale-gen" {
  # EL-04: EL9 glibc ships C.UTF-8 built-in — no locale-gen. The rhel arm writes
  # /etc/locale.conf atomically; the debian arm keeps the byte-for-byte
  # locale-gen / update-locale path. One test asserts both halves diverge.
  run_locale_ensure rhel
  [[ "$status" -eq 0 ]] || __el04_fail "locale_ensure rc 0 on rhel" "status=$status; $output"
  grep -q 'write_file_atomic 0644 /etc/locale.conf' "$CAPTURE" \
    || __el04_fail "rhel writes /etc/locale.conf via write_file_atomic" "$(cat "$CAPTURE")"
  grep -q '^LANG=C.UTF-8$' "$AGENTLINUX_TEST_LOCALE_CONF" \
    || __el04_fail "LANG=C.UTF-8 in locale.conf" "$(cat "$AGENTLINUX_TEST_LOCALE_CONF" 2>/dev/null)"
  grep -q '^LC_ALL=C.UTF-8$' "$AGENTLINUX_TEST_LOCALE_CONF" \
    || __el04_fail "LC_ALL=C.UTF-8 in locale.conf" "$(cat "$AGENTLINUX_TEST_LOCALE_CONF" 2>/dev/null)"
  : >"$CAPTURE"
  run_verb debian locale_ensure C.UTF-8
  [[ "$status" -eq 0 ]] || __el04_fail "locale_ensure rc 0 on debian" "status=$status; $output"
  grep -q 'update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8' "$CAPTURE" \
    || __el04_fail "debian keeps the locale-gen / update-locale path" "$(cat "$CAPTURE")"
  ! grep -q 'write_file_atomic' "$CAPTURE" \
    || __el04_fail "debian arm does not write locale.conf" "$(cat "$CAPTURE")"
}

# ---- EL-05 sudo-package install verb (the verb 20-sudoers.sh uses) ----------

@test "EL-05: the sudo package installs via pkg_install — dnf on rhel, apt-get on debian" {
  # EL-05's Phase-18 unit surface is the package-install-verb swap only: the
  # install/validate (visudo-gated 0440 drop-in) logic is distro-agnostic. The
  # live six-invocation-mode passwordless-sudo acceptance under enforcing SELinux
  # is owned by Phase 20.
  run_verb rhel pkg_install sudo
  [[ "$status" -eq 0 ]] || __el05_fail "pkg_install sudo rc 0 on rhel" "status=$status; $output"
  grep -q 'dnf install -y --setopt=install_weak_deps=False sudo' "$CAPTURE" \
    || __el05_fail "dnf install ... sudo on rhel" "$(cat "$CAPTURE")"
  ! grep -q 'apt-get' "$CAPTURE" \
    || __el05_fail "no apt-get on rhel" "$(cat "$CAPTURE")"
  : >"$CAPTURE"
  run_verb debian pkg_install sudo
  [[ "$status" -eq 0 ]] || __el05_fail "pkg_install sudo rc 0 on debian" "status=$status; $output"
  grep -q 'apt-get install -y --no-install-recommends sudo' "$CAPTURE" \
    || __el05_fail "apt-get install ... sudo on debian" "$(cat "$CAPTURE")"
  ! grep -q 'dnf' "$CAPTURE" \
    || __el05_fail "no dnf on debian" "$(cat "$CAPTURE")"
}

# ---- fail-closed on an unknown/garbage distro family (qa mutation guard) ----

@test "EL-02: pkg_install fails closed (non-zero) on an empty AGENTLINUX_DISTRO_FAMILY" {
  run_verb "" pkg_install jq
  [[ "$status" -ne 0 ]] || __el02_fail "non-zero exit on empty family (fail closed)" "status=$status; $output"
  ! grep -Eq 'apt-get|dnf' "$CAPTURE" \
    || __el02_fail "no package manager dispatched on empty family" "$(cat "$CAPTURE")"
}

@test "EL-02: pkg_install fails closed (non-zero) on a garbage AGENTLINUX_DISTRO_FAMILY" {
  run_verb bogus-family pkg_install jq
  [[ "$status" -ne 0 ]] || __el02_fail "non-zero exit on garbage family (fail closed)" "status=$status; $output"
  ! grep -Eq 'apt-get|dnf' "$CAPTURE" \
    || __el02_fail "no package manager dispatched on garbage family" "$(cat "$CAPTURE")"
}
