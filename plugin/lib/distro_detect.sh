#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/distro_detect.sh — Ubuntu 22.04 / 24.04 / 26.04 detection.
#
# The installer refuses to run on anything other than Ubuntu 22.04, 24.04 or
# 26.04 — future distros land in v0.4+ per ADR. `detect_distro` exports
# AGENTLINUX_DISTRO_VERSION for downstream provisioners that need to branch
# (e.g. locale-gen no-op on C.UTF-8, Pitfall 5 in 02-RESEARCH.md).
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

# detect_distro — read /etc/os-release, accept ubuntu 22.04|24.04, reject else.
# Exports AGENTLINUX_DISTRO_VERSION on success. Returns non-zero on refusal so
# the entrypoint can decide whether to `|| exit 1`.
#
# Escape hatch: AGENTLINUX_SKIP_DISTRO_CHECK=1 bypasses validation and exports
# AGENTLINUX_DISTRO_VERSION=unchecked. Intended ONLY for bats unit sourcing on
# dev hosts that are not themselves Ubuntu 22.04/24.04/26.04. Real installer
# runs MUST NOT set this.
detect_distro() {
  if [[ "${AGENTLINUX_SKIP_DISTRO_CHECK:-0}" == "1" ]]; then
    export AGENTLINUX_DISTRO_VERSION="unchecked"
    log_warn "AGENTLINUX_SKIP_DISTRO_CHECK=1 — skipping /etc/os-release validation"
    return 0
  fi

  if [[ ! -r /etc/os-release ]]; then
    log_error "cannot read /etc/os-release; unsupported system"
    return 1
  fi

  # `.` inside a function body keeps ID / VERSION_ID scoped to this invocation —
  # no global pollution of the caller's shell.
  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    log_error "unsupported distro: ID=${ID:-unset} (required: ubuntu)"
    return 1
  fi

  case "${VERSION_ID:-}" in
    22.04 | 24.04 | 26.04)
      export AGENTLINUX_DISTRO_VERSION="$VERSION_ID"
      log_info "detected ubuntu ${VERSION_ID}"
      ;;
    *)
      log_error "unsupported ubuntu version: ${VERSION_ID:-unset} (required: 22.04, 24.04 or 26.04)"
      return 1
      ;;
  esac
}
