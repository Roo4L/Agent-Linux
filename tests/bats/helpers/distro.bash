# tests/bats/helpers/distro.bash
# Phase 20 (PAR-01 / EL-06 / EL-08) distro-family dispatch helper.
#
# The single fork point the bats behavior contract uses to build family-correct
# fixture state and assert family-correct observables on BOTH the Debian
# (Ubuntu) rows and the RHEL (AlmaLinux 9) row. The behavior contract is the
# invariant; the *implementation* may branch (apt→dnf, dpkg→rpm,
# /etc/default/locale→/etc/locale.conf, ssh→sshd) but the asserted observable
# must hold identically on both families.
#
# GENERALIZE, NEVER WEAKEN: every verb's `debian` arm is the CURRENT hardcoded
# line lifted byte-for-byte from brownfield.bash / invoke_modes.bash /
# 20-agent-user.bats, so the Ubuntu rows execute the identical commands — only
# the `case` selector is new. The `rhel` arm asserts/builds the SAME observable
# at the EL9-correct path/tool. No `skip` to make EL9 green.
#
# Design invariants:
#   - No `set -euo pipefail` at top: this file is SOURCED by bats via
#     `load 'helpers/distro'` (and by brownfield.bash); strict mode inside a
#     sourced library leaks into the test framework and breaks TAP output.
#   - Container-side, STANDALONE: dispatches on /etc/os-release ID inside the
#     test container WITHOUT sourcing any product lib (plugin/lib/*). This keeps
#     distro.bash usable in places where no product lib is loaded (e.g. the
#     10-installer INST-02 snapshot test).
#   - Family is cached in `_AGENTLINUX_TEST_FAMILY` after the first read;
#     override it (export `_AGENTLINUX_TEST_FAMILY=rhel|debian`) for unit
#     coverage of the non-host arm.
#
# Refs: 20-RESEARCH.md §Distro-Aware Helper Design; 20-PATTERNS.md Wave 2.

# distro_family
# Prints `rhel` (AlmaLinux/EL9) or `debian` (Ubuntu) by reading the in-image
# /etc/os-release ID. Cached. Mirrors the product-side detect_distro
# (plugin/lib/distro_detect.sh) but reads os-release directly so no product lib
# is required.
distro_family() {
  [[ -n "${_AGENTLINUX_TEST_FAMILY:-}" ]] && {
    printf '%s' "$_AGENTLINUX_TEST_FAMILY"
    return 0
  }
  local id=""
  [[ -r /etc/os-release ]] && id=$(
    . /etc/os-release
    printf '%s' "${ID:-}"
  )
  case "$id" in almalinux) _AGENTLINUX_TEST_FAMILY=rhel ;; *) _AGENTLINUX_TEST_FAMILY=debian ;; esac
  printf '%s' "$_AGENTLINUX_TEST_FAMILY"
}

# distro_locale_file
# Prints the family's system locale file path. One observable (LANG/LC_ALL set
# to C.UTF-8), two paths. Consumer: BHV-01 (20-agent-user).
distro_locale_file() {
  case "$(distro_family)" in
    rhel) printf '%s' /etc/locale.conf ;;
    debian) printf '%s' /etc/default/locale ;;
  esac
}

# distro_assert_locale <LANG|LC_ALL>
# Greps `^<VAR>=C.UTF-8$` in the family locale file (the SAME observable at the
# family-correct path — never a skip). Returns grep's exit status so callers can
# `run distro_assert_locale LANG` and assert exit zero. Consumer: BHV-01.
distro_assert_locale() {
  local var=$1
  grep -E "^${var}=C\.UTF-8\$" "$(distro_locale_file)"
}

# distro_nodesource_repo_paths
# Prints the family's NodeSource repo-definition path. Consumer: INST-02
# idempotency snapshot file-list (10-installer), container-side where no product
# lib is sourced. Where a product lib IS sourced, prefer the product
# nodesource_repo_paths verb (plugin/lib/pkg.sh) — the single source of truth.
distro_nodesource_repo_paths() {
  case "$(distro_family)" in
    rhel) printf '%s\n' /etc/yum.repos.d/nodesource-nodejs.repo ;;
    debian) printf '%s\n' /etc/apt/sources.list.d/nodesource.sources ;;
  esac
}

# distro_pkg_is_installed <pkg>
# True iff <pkg> is installed, via the family package DB. The debian arm is the
# brownfield.bash Node-present gate verbatim. Consumer: brownfield Node gate.
distro_pkg_is_installed() {
  local pkg=$1
  case "$(distro_family)" in
    rhel) rpm -q "$pkg" >/dev/null 2>&1 ;;
    debian) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' ;;
  esac
}

# distro_install_node22
# Ensures NodeSource Node 22 is present (no-op if already installed). The debian
# arm is exactly the current brownfield.bash NodeSource block (lines 86-89 /
# 139-141 / 503-507) byte-for-byte; the rhel arm is the EL9 equivalent (rpm
# NodeSource repo + dnf module reset + dnf install). Consumers:
# setup_brownfield_host, _brownfield_baseline, _setup_brownfield_apt_layer.
distro_install_node22() {
  case "$(distro_family)" in
    rhel)
      command -v node >/dev/null && rpm -q nodejs >/dev/null 2>&1 && return 0
      curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
      dnf -y module reset nodejs >/dev/null 2>&1 || true
      dnf install -y nodejs >/dev/null 2>&1
      ;;
    debian)
      dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q 'install ok installed' && return 0
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1
      ;;
  esac
}

# distro_sudoers_pkg_line <user> [full|narrow]
# Prints a single NOPASSWD-for-package-manager sudoers line for <user>. `full`
# (default) is the brownfield REUSE-01 fixture grant; `narrow` is the
# single-binary drift grant (REMEDIATE-03). On rhel dnf is one binary so full
# and narrow coincide; on debian the full grant is the current verbatim
# `/usr/bin/apt-get, /usr/bin/apt` and narrow is the verbatim `/usr/bin/apt-get`.
# Consumers: brownfield NOPASSWD-for-pkg fixtures (REUSE-01 + REMEDIATE-03).
distro_sudoers_pkg_line() {
  local user=${1:-agent} form=${2:-full}
  case "$(distro_family)" in
    rhel)
      printf '%s ALL=(ALL) NOPASSWD: /usr/bin/dnf\n' "$user"
      ;;
    debian)
      if [[ "$form" == narrow ]]; then
        printf '%s ALL=(ALL) NOPASSWD: /usr/bin/apt-get\n' "$user"
      else
        printf '%s ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt\n' "$user"
      fi
      ;;
  esac
}

# distro_ssh_unit
# Prints the family's sshd systemd unit name. Consumer: setup `systemctl start
# "$(distro_ssh_unit)"` (20-agent-user, 50-agents).
distro_ssh_unit() {
  case "$(distro_family)" in
    rhel) printf 'sshd' ;;
    debian) printf 'ssh' ;;
  esac
}

# distro_restore_ssh_context <dir>
# After seeding ~agent/.ssh/authorized_keys, relabels the SELinux file context
# so a confined sshd_t can read the key under real (Phase 22 QEMU) enforcement.
# The rhel arm is GUARDED (`command -v restorecon`) because policycoreutils is
# absent from the Docker image — an unguarded call would abort the harness; on
# the Docker row the call is a deliberate no-op. The debian arm is `:` (no
# SELinux). SELinux enforcement is never disabled — this guarded relabel is the
# only sanctioned fix. Consumer: the two SSH-seeding sites (EL-06).
distro_restore_ssh_context() {
  local dir=$1
  case "$(distro_family)" in
    rhel) command -v restorecon >/dev/null && restorecon -R -F "$dir" || true ;;
    debian) : ;;
  esac
}
