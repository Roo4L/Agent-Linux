#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/pkg.sh — package-manager-neutral verbs (apt↔dnf) on $AGENTLINUX_DISTRO_FAMILY.
#
# The ONE auditable place the apt↔dnf branch lives. Every hardcoded apt-get /
# dpkg / locale-gen / NodeSource site in the provisioners + entrypoint collapses
# to a single verb call here, so the family fork is never an inline
# `if [[ $FAMILY == rhel ]]` scattered across five files (18-RESEARCH.md
# Anti-Pattern 2). Each verb branches exactly once on AGENTLINUX_DISTRO_FAMILY
# (exported by distro_detect.sh::detect_distro):
#   - debian arm = the current Ubuntu command lifted BYTE-FOR-BYTE from its
#     present call site (no behavior change on Ubuntu).
#   - rhel arm   = the EL9 equivalent (dnf/rpm/locale.conf), per 18-RESEARCH.md
#     Pattern 2 + the v0.3.5 STACK decisions.
#
# Source-once guard: safe to `. pkg.sh` repeatedly.
[[ -n "${AGENTLINUX_PKG_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_PKG_SH_SOURCED=1

# Precondition: log.sh must already have been sourced so log_info / log_error
# are available. Fail fast (and loudly) otherwise — sourcing order matters.
if ! command -v log_error >/dev/null 2>&1; then
  printf 'pkg.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# pkg_install <pkg...> — install one or more packages.
#   debian: apt-get install --no-install-recommends.
#   rhel:   `--setopt=install_weak_deps=False` ≈ apt's `--no-install-recommends`.
pkg_install() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      DEBIAN_FRONTEND=noninteractive apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
      ;;
    rhel)
      dnf install -y --setopt=install_weak_deps=False "$@"
      ;;
    *)
      log_error "pkg_install: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}

# pkg_is_installed <pkg> — true (rc 0) iff <pkg> is installed.
#   debian: dpkg-query Status check.
#   rhel:   rpm presence query.
pkg_is_installed() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
      ;;
    rhel)
      rpm -q "$1" >/dev/null 2>&1
      ;;
    *)
      log_error "pkg_is_installed: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}

# pkg_remove <pkg...> — remove packages (purge config on debian).
#   debian: apt-get purge (also removes config files).
pkg_remove() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"
      ;;
    rhel)
      dnf remove -y "$@"
      ;;
    *)
      log_error "pkg_remove: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}

# pkg_autoremove — drop orphaned dependencies.
#   debian: apt-get autoremove.
pkg_autoremove() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
      ;;
    rhel)
      dnf autoremove -y
      ;;
    *)
      log_error "pkg_autoremove: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}

# nodesource_prereqs — install the prerequisites NodeSource's setup_22.x expects.
#   debian: curl gnupg ca-certificates apt-transport-https (the apt prereq set).
#   rhel:   ONLY ca-certificates. NEVER curl (curl-minimal conflict, Pitfall 6),
#           and gnupg / apt-transport-https do not exist on EL9. This is a verb,
#           not an inline pkg_install list, so an apt-only package name can never
#           reach dnf.
nodesource_prereqs() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      DEBIAN_FRONTEND=noninteractive apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates apt-transport-https
      ;;
    rhel)
      dnf install -y --setopt=install_weak_deps=False ca-certificates
      ;;
    *)
      log_error "nodesource_prereqs: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}

# nodesource_setup — run the pinned NodeSource setup_22.x script (ADR-005).
#   HTTPS + `curl -fsSL` cert verification is the fetch integrity control;
#   ongoing package integrity comes from the repo gpgkey the script installs.
#   debian: deb.nodesource.com. rhel: rpm.nodesource.com.
nodesource_setup() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
      ;;
    rhel)
      curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
      ;;
    *)
      log_error "nodesource_setup: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}

# nodesource_repo_paths — print the family's NodeSource repo file paths, one per
# line. The single source of truth shared by the 30-nodejs idempotency gate, the
# detect/nodejs gate, and the run_purge cleanup so they never drift apart.
#   debian: apt sources.list.d (deb822 + legacy) + the preferences pin.
#   rhel:   the yum.repos.d repo files setup_22.x drops.
nodesource_repo_paths() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      printf '%s\n' \
        /etc/apt/sources.list.d/nodesource.sources \
        /etc/apt/sources.list.d/nodesource.list \
        /etc/apt/preferences.d/nodejs
      ;;
    rhel)
      printf '%s\n' \
        /etc/yum.repos.d/nodesource-nodejs.repo \
        /etc/yum.repos.d/nodesource-nsolid.repo
      ;;
    *)
      log_error "nodesource_repo_paths: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}

# nodesource_module_reset — defuse the AppStream `nodejs` module so the older
# distro module cannot win over the NodeSource repo (Pitfall 4). setup_22.x does
# NOT do this itself. rhel-only and non-fatal; a no-op on debian so the family
# branch stays inside the verb — no inline `if` at the call site.
nodesource_module_reset() {
  case "$AGENTLINUX_DISTRO_FAMILY" in
    rhel)
      dnf -y module reset nodejs || true
      ;;
    *)
      :
      ;;
  esac
}

# locale_ensure <locale> — enforce <locale> as the system LANG/LC_ALL, then
# verify it is actually available via the portable `locale -a` gate (BHV-01).
#   debian: the standard locales install + locale-gen + update-locale, with
#           /etc/default/locale as the write target.
#   rhel:   write /etc/locale.conf atomically (write_file_atomic, stdin body) —
#           NEVER cat>/tee. No locale-gen on EL9; glibc-langpack provides C.UTF-8.
# Both arms end with the same `locale -a … grep -Eiq '^c\.utf-?8$'` correctness
# gate (accepts `C.UTF-8` and the `C.utf8` form 24.04 reports).
locale_ensure() {
  local loc=$1
  # C.UTF-8-only contract: the debian arm is the byte-for-byte Ubuntu path
  # (hardcoded C.UTF-8 + a C.UTF-8 `locale -a` gate) and ignores $loc, while the
  # rhel arm honors it. Reject any other locale rather than silently enforcing
  # C.UTF-8 on debian — fail closed so a future mismatched call site is caught.
  if [[ "$loc" != "C.UTF-8" ]]; then
    log_error "locale_ensure supports only C.UTF-8 (got: ${loc:-unset})"
    return 1
  fi
  case "$AGENTLINUX_DISTRO_FAMILY" in
    debian)
      if ! command -v locale-gen >/dev/null 2>&1; then
        log_warn "locale-gen not found; installing 'locales' package"
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales
      fi
      locale-gen C.UTF-8 >/dev/null 2>&1 || true
      update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8
      if ! locale -a 2>/dev/null | grep -Eiq '^c\.utf-?8$'; then
        log_error "C.UTF-8 locale not available after locale-gen + update-locale"
        return 1
      fi
      log_info "locale C.UTF-8 enforced (LANG + LC_ALL in /etc/default/locale)"
      ;;
    rhel)
      printf 'LANG=%s\nLC_ALL=%s\n' "$loc" "$loc" | write_file_atomic 0644 /etc/locale.conf
      if ! locale -a 2>/dev/null | grep -Eiq '^c\.utf-?8$'; then
        log_error "${loc} locale not available after writing /etc/locale.conf"
        return 1
      fi
      log_info "locale ${loc} enforced (LANG + LC_ALL in /etc/locale.conf)"
      ;;
    *)
      log_error "locale_ensure: unknown distro family '${AGENTLINUX_DISTRO_FAMILY:-unset}'"
      return 1
      ;;
  esac
}
