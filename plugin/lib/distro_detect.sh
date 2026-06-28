#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/distro_detect.sh — supported-distro gate + family bucket.
#
# The installer accepts Ubuntu 22.04 / 24.04 / 26.04 (FAMILY=debian) and
# AlmaLinux 9.x (FAMILY=rhel); everything else is refused with a message that
# names the supported set. `detect_distro` exports two values downstream layers
# read instead of re-parsing /etc/os-release:
#   - AGENTLINUX_DISTRO_FAMILY ∈ {debian, rhel} — the single fork point every
#     later layer (lib/pkg.sh verbs, provisioners, detect fragments) branches on.
#   - AGENTLINUX_DISTRO_VERSION — the os-release VERSION_ID (e.g. 22.04, 9.4),
#     for provisioners that still branch on the exact version (ADR-017).
# Matches `ID` EXACTLY (never the looser os-release similarity field) so
# Rocky/RHEL/CentOS/Fedora and AlmaLinux 8/10 stay explicitly refused — no silent
# admission of an untested family. Keep this allowlist in lockstep with
# packaging/curl-installer/install.sh.
#
# Source-once guard: safe to `. distro_detect.sh` repeatedly.
[[ -n "${AGENTLINUX_DISTRO_DETECT_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DISTRO_DETECT_SH_SOURCED=1

# Precondition: log.sh must already have been sourced so log_info / log_error
# are available. Fail fast (and loudly) otherwise — sourcing order matters.
if ! command -v log_error >/dev/null 2>&1; then
  printf 'distro_detect.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# detect_distro — read os-release, accept ubuntu 22.04|24.04|26.04 (debian) and
# almalinux 9.x (rhel), reject everything else. Exports AGENTLINUX_DISTRO_FAMILY
# and AGENTLINUX_DISTRO_VERSION on success. Returns non-zero on refusal so the
# entrypoint can decide whether to `|| exit 1`.
#
# Test seam: AGENTLINUX_OS_RELEASE_PATH overrides the os-release path (defaults
# to /etc/os-release in production) so bats unit fixtures can drive the gate with
# a temp os-release without being the target distro.
#
# Escape hatch: AGENTLINUX_SKIP_DISTRO_CHECK=1 bypasses validation and exports
# AGENTLINUX_DISTRO_VERSION=unchecked. It ALSO seeds AGENTLINUX_DISTRO_FAMILY so
# a unit-sourced lib/pkg.sh does not dispatch on an empty bucket: an explicit
# AGENTLINUX_DISTRO_FAMILY override wins; else the os-release ID is consulted
# (almalinux→rhel, ubuntu→debian); else it defaults to debian. Intended ONLY for
# bats unit sourcing on dev hosts that are not a supported target. Real installer
# runs MUST NOT set this.
detect_distro() {
  local os_release="${AGENTLINUX_OS_RELEASE_PATH:-/etc/os-release}"

  if [[ "${AGENTLINUX_SKIP_DISTRO_CHECK:-0}" == "1" ]]; then
    export AGENTLINUX_DISTRO_VERSION="unchecked"
    # Seed the family bucket so a unit-sourced pkg.sh has a valid arm to dispatch
    # on. Honor an explicit override; else read ID from the os-release file if
    # present; else default debian. Reading ID in a subshell keeps it scoped.
    if [[ -z "${AGENTLINUX_DISTRO_FAMILY:-}" ]]; then
      local seed_id=""
      if [[ -r "$os_release" ]]; then
        # shellcheck disable=SC1090
        seed_id=$(. "$os_release" && printf '%s' "${ID:-}")
      fi
      case "$seed_id" in
        almalinux) export AGENTLINUX_DISTRO_FAMILY=rhel ;;
        *) export AGENTLINUX_DISTRO_FAMILY=debian ;;
      esac
    fi
    log_warn "AGENTLINUX_SKIP_DISTRO_CHECK=1 — skipping ${os_release} validation (family=${AGENTLINUX_DISTRO_FAMILY})"
    return 0
  fi

  if [[ ! -r "$os_release" ]]; then
    log_error "cannot read ${os_release}; unsupported system"
    return 1
  fi

  # `.` inside a function body keeps ID / VERSION_ID scoped to this invocation —
  # no global pollution of the caller's shell.
  # shellcheck disable=SC1090,SC1091
  . "$os_release"

  # Match ID EXACTLY — never the looser similarity field — so Rocky/RHEL/CentOS/
  # Fedora and AlmaLinux 8/10 stay refused. The debian arm preserves the prior
  # Ubuntu behavior byte-for-byte; the rhel arm is purely additive.
  case "${ID:-}" in
    ubuntu)
      export AGENTLINUX_DISTRO_FAMILY=debian
      case "${VERSION_ID:-}" in
        22.04 | 24.04 | 26.04)
          export AGENTLINUX_DISTRO_VERSION="$VERSION_ID"
          log_info "detected ubuntu ${VERSION_ID} (family=debian)"
          ;;
        *)
          log_error "unsupported ubuntu version: ${VERSION_ID:-unset} (required: 22.04, 24.04 or 26.04)"
          return 1
          ;;
      esac
      ;;
    almalinux)
      export AGENTLINUX_DISTRO_FAMILY=rhel
      case "${VERSION_ID:-}" in
        9 | 9.*)
          export AGENTLINUX_DISTRO_VERSION="$VERSION_ID"
          log_info "detected almalinux ${VERSION_ID} (family=rhel)"
          ;;
        *)
          log_error "unsupported almalinux version: ${VERSION_ID:-unset} (required: 9.x)"
          return 1
          ;;
      esac
      ;;
    *)
      log_error "unsupported distro: ID=${ID:-unset} (required: ubuntu | almalinux)"
      return 1
      ;;
  esac
}
