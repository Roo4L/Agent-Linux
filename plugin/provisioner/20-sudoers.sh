#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/provisioner/20-sudoers.sh — install /etc/sudoers.d/agentlinux granting
# passwordless sudo to the agent user (scope: ALL commands, per ADR-012).
#
# Sourced by plugin/bin/agentlinux-install. Inherits `set -euo pipefail`, the
# ERR trap, and the tee redirect to /var/log/agentlinux-install.log from the
# entrypoint; this fragment therefore MUST NOT set its own strict-mode flags.
#
# Runs AFTER 10-agent-user.sh (agent user must exist — the sudoers line
# references `agent`) and BEFORE 30-nodejs.sh / 40-path-wiring.sh. Numeric
# dispatch (10 → 20 → 30 → 40) guarantees the order in run_provisioners().
#
# Requirements satisfied:
#   INST-06 — `sudo -u agent sudo -n true` exit 0 (agent has passwordless sudo)
#   BHV-07  — /etc/sudoers.d/agentlinux mode 0440 root:root, visudo -cf clean,
#             contains exactly `agent ALL=(ALL) NOPASSWD: ALL`, byte-stable on
#             re-run.
#   REMEDIATE-03 — both missing-file install AND drift overwrite route through
#                  the same plugin/lib/remediate/sudoers.sh helper.
#
# Security invariants (T-05.1-01..04, T-14-02):
#   - `visudo -cf` gate runs on the tmpfile BEFORE `install` moves it into
#     place (T-05.1-01) — for BOTH the additive create AND the state-
#     overwriting drift remediation (Plan 14-02 helper factoring eliminates
#     the divergence-between-arms class of bug).
#   - Atomic install via `install(1)` with explicit -m 0440 -o root -g root
#     (T-05.1-02).
#   - Mode 0440 restricts read to root (T-05.1-03).
#   - Atomic overwrite produces byte-identical files on re-run (T-05.1-04).
#   - T-14-02: drift overwrite (when --yes is passed) uses the SAME visudo
#     gate as the additive create path — see plugin/lib/remediate/sudoers.sh's
#     install_or_overwrite helper (the single source of truth for both arms).
#
# Plan 14-02 refactor: the visudo+install machinery is now in
# plugin/lib/remediate/sudoers.sh::install_or_overwrite. This provisioner
# orchestrates the RESOLUTIONS dispatch and delegates the actual file-write
# to that helper, so the create + remediate arms cannot drift in semantics.

log_info "20-sudoers: starting"

# Minimal Ubuntu/Debian cloud images (and many Docker base images) ship without
# the `sudo` package, which provides both the `sudo` binary AND `visudo`. We
# need `visudo` to validate the drop-in before installing it (T-05.1-01), and
# the agent user obviously needs `sudo` afterwards. Mirror the pattern used by
# 10-agent-user.sh's `locales` install: apt-get update first (cache may be
# empty on freshly pulled containers and long-idle hosts — AL-37), then
# apt-get install gated on prereq absence. Run BEFORE the dispatch so that
# even REUSE / REMEDIATE arms have visudo available for their own validation.
if ! command -v visudo >/dev/null 2>&1; then
  log_warn "visudo not found; installing 'sudo' package"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo
fi

# Ensure parent dir exists with correct ownership + mode. ensure_dir is a
# no-op re-asserting mode+ownership when the directory already exists, so this
# also corrects any out-of-band drift on re-run.
ensure_dir /etc/sudoers.d 0755 root:root

# Phase 14 (Plan 14-01 dispatch, Plan 14-02 helper refactor) — dispatch on
# pre-resolved RESOLUTIONS[sudoers] token. Decisions are made up-front in
# main() by remediate::collect_all_decisions BEFORE any provisioner runs:
#   reuse     — /etc/sudoers.d/agentlinux exists AND contains the canonical
#               ADR-012 line; nothing to do.
#   remediate — file exists but drifted from the ADR-012 line. The consent
#               gate in remediate.sh has already enforced --yes (or registered
#               a bail). Call install_or_overwrite with action=overwrite.
#   create    — file absent; additive install. Call install_or_overwrite with
#               action=install (no --yes consent gate consulted — additive
#               action per CONTEXT.md Area 1 Q1).
#   bail      — UNREACHABLE; flush_bails_or_continue would have exited 65.
#
# Plan 14-02 refactor: BOTH the create AND remediate arms route through the
# same remediate::sudoers::install_or_overwrite helper. The action_label
# distinguishes them in the [REMEDIATE-03] log marker for transcript clarity.
case "${RESOLUTIONS[sudoers]:-create}" in
  reuse)
    log_info "[REUSE] sudoers: /etc/sudoers.d/agentlinux already canonical (ADR-012 line present)"
    log_info "20-sudoers: done"
    return 0
    ;;
  remediate)
    # Gate already passed — flush_bails_or_continue would have exited 65 if
    # --yes was missing. Plan 14-02: factored helper, action=overwrite.
    remediate::sudoers::install_or_overwrite "overwrite" || return 1
    log_info "agent user now has passwordless sudo (scope: ALL commands — drift remediated) — INST-06"
    log_info "20-sudoers: done"
    return 0
    ;;
  create)
    # Additive missing-file install — Plan 14-02 factored helper, action=install.
    remediate::sudoers::install_or_overwrite "install" || return 1
    log_info "agent user now has passwordless sudo (scope: ALL commands) — INST-06"
    log_info "20-sudoers: done"
    return 0
    ;;
  reuse-with-warning)
    # Plan 15-01 (UX-02 / D-15-02): TTY operator declined the sudoers drift
    # overwrite. /etc/sudoers.d/agentlinux stays at its drifted content; we
    # do NOT install or modify the file. Operator now bears manual
    # responsibility for ensuring NOPASSWD-for-apt-or-broader works.
    log_warn "[REUSE-WARN] component=sudoers decline_reason=${DECLINED_COMPONENTS[sudoers]:-unknown} — skipped (user declined remediation; manual fix needed). /etc/sudoers.d/agentlinux unchanged."
    log_info "20-sudoers: done"
    return 0
    ;;
  bail)
    log_error "20-sudoers: unreachable bail arm — flush_bails_or_continue should have gated this"
    return 1
    ;;
esac
