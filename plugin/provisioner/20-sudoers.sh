#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/provisioner/20-sudoers.sh — install /etc/sudoers.d/agentlinux granting
# passwordless sudo to the agent user (scope: ALL commands, per ADR-012).
#
# Sourced by agentlinux-install. Inherits set -euo pipefail, the ERR trap, and
# the tee redirect — MUST NOT set its own strict-mode flags. Runs after
# 10-agent-user.sh (the user must exist) and before 30/40 via numeric dispatch.
#
# Satisfies INST-06 (agent has passwordless sudo), BHV-07 (/etc/sudoers.d/
# agentlinux 0440 root:root, visudo-clean, byte-stable), and REMEDIATE-03.
#
# Security: visudo -cf validates the tmpfile BEFORE install moves it into place,
# for both the create and the drift-overwrite arms; install(1) -m 0440 -o root
# -g root is atomic and restricts read to root; re-runs are byte-identical.
# Both arms route through remediate::sudoers::install_or_overwrite (single
# source of truth) so they cannot drift in semantics.

log_info "20-sudoers: starting"

# Minimal cloud/Docker images ship without the `sudo` package (which provides
# both `sudo` and `visudo`); we need visudo to validate the drop-in. apt-get
# update first — the cache may be empty on fresh/idle hosts. Run BEFORE the
# dispatch so even REUSE/REMEDIATE arms have visudo for validation.
if ! command -v visudo >/dev/null 2>&1; then
  log_warn "visudo not found; installing 'sudo' package"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo
fi

# ensure_dir is a no-op re-asserting mode+ownership when the dir exists.
ensure_dir /etc/sudoers.d 0755 root:root

# Dispatch on the pre-resolved RESOLUTIONS[sudoers] token:
#   reuse     — file present and canonical; nothing to do.
#   remediate — file drifted; consent gate already enforced --yes. Overwrite.
#   create    — file absent; additive install (no consent gate — additive).
#   bail      — unreachable; flush_bails_or_continue would have exited 65.
# Both create and remediate route through the same install_or_overwrite helper;
# the action label distinguishes them in the [REMEDIATE-03] log marker.
case "${RESOLUTIONS[sudoers]:-create}" in
  reuse)
    log_info "[REUSE] sudoers: /etc/sudoers.d/agentlinux already canonical (ADR-012 line present)"
    log_info "20-sudoers: done"
    return 0
    ;;
  remediate)
    # Gate already passed (would have exited 65 if --yes were missing).
    remediate::sudoers::install_or_overwrite "overwrite" || return 1
    log_info "install user '${INSTALL_USER:-agent}' now has passwordless sudo (scope: ALL commands — drift remediated) — INST-06"
    log_info "20-sudoers: done"
    return 0
    ;;
  create)
    remediate::sudoers::install_or_overwrite "install" || return 1
    log_info "install user '${INSTALL_USER:-agent}' now has passwordless sudo (scope: ALL commands) — INST-06"
    log_info "20-sudoers: done"
    return 0
    ;;
  reuse-with-warning)
    # TTY operator declined the drift overwrite; leave the file as-is. Operator
    # now owns ensuring the grant works.
    log_warn "[REUSE-WARN] component=sudoers decline_reason=${DECLINED_COMPONENTS[sudoers]:-unknown} — skipped (user declined remediation; manual fix needed). /etc/sudoers.d/agentlinux unchanged."
    log_info "20-sudoers: done"
    return 0
    ;;
  bail)
    log_error "20-sudoers: unreachable bail arm — flush_bails_or_continue should have gated this"
    return 1
    ;;
esac
