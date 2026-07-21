#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/catalog/lib/daemon-lifecycle.sh — ENABLE-04 shared AI-assistant daemon helper.
#
# SOURCED, NOT EXECUTED. A daemon-class catalog recipe (agents/<id>/install.sh)
# sources this via:
#
#   source "${AGENTLINUX_CATALOG_DIR}/lib/daemon-lifecycle.sh"
#
# and uses the primitives to bring up / tear down a PER-USER background service with
# no root, the same way every daemon-class tool must. The provisioner stages the whole
# lib/ subdir automatically (50-registry-cli.sh copies the catalog tree with `cp -R`),
# so shipping this needs no provisioner edit.
#
# Why a helper (CAT-03 reuse): a per-user daemon needs (a) a usable per-user systemd
# instance that survives logout (linger), (b) XDG_RUNTIME_DIR pointed at the user bus,
# and (c) a SYMMETRIC teardown that reverts linger ONLY if AgentLinux enabled it AND no
# other AgentLinux daemon still needs it. That bookkeeping is identical for every daemon
# tool, so it lives here once. The named consumers are openclaw (Phase 47, first) and
# hermes-agent (Phase 48); the Phase 49 ENABLE-07 growth-kit template points new daemon
# recipes here.
#
# THE DOCKER-vs-REAL SPLIT (why al_daemon_user_systemd_available exists): the Docker CI
# harness masks systemd-logind (no /run/user, no user bus), so `systemctl --user` and
# `openclaw daemon install` (systemd --user) CANNOT run there. A recipe therefore probes
# al_daemon_user_systemd_available and only drives the systemd path when it is usable —
# so `agentlinux install` succeeds in a container (binary + config, no auto-started
# daemon) AND on a real host (full per-user daemon). The systemd-user lifecycle is a
# QEMU-gated behavior (ADR-007); Docker verifies the tool's process-level path instead.
#
# Deliberately NOT `set -euo pipefail` at file top: sourced into recipes that own their
# own shell options. Each function returns non-zero on failure so the caller can react.

# Where AgentLinux ownership markers live (shared with uv-bootstrap.sh's convention).
_al_daemon_dir() { printf '%s/.local/share/agentlinux' "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"; }
# The linger marker: its presence means AgentLinux ran `loginctl enable-linger` (a user
# who already had linger on keeps it, and we never touch theirs — no marker recorded).
_al_daemon_linger_marker() { printf '%s/linger.managed' "$(_al_daemon_dir)"; }

# al_daemon_export_xdg
# Point XDG_RUNTIME_DIR at the per-user bus if unset. `systemctl --user` and every
# per-user unit need this; login shells that never opened a graphical/PAM session leave
# it empty. Harmless when already set. Does not create the dir (logind owns it).
al_daemon_export_xdg() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    local uid
    uid="$(id -u)"
    export XDG_RUNTIME_DIR="/run/user/${uid}"
  fi
  return 0
}

# al_daemon_user_systemd_available
# 0 iff a per-user systemd instance is reachable (the user D-Bus responds). This is the
# Docker-vs-real discriminator: masked logind (CI containers) returns non-zero, so the
# recipe degrades to a config-only install instead of hard-failing. `show-environment`
# is a cheap read that requires the bus and mutates nothing.
al_daemon_user_systemd_available() {
  al_daemon_export_xdg
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

# al_daemon_in_container
# 0 iff we are running inside a container (Docker/Podman/OCI). Lets the caller name the
# real reason the per-user daemon is skipped: "inside a container" (expected) vs "on a host
# but the user bus is unreachable" (a real problem worth flagging). Checks, in cheap order:
# the Docker/Podman marker files, an explicit `container=` env (systemd and Podman set it),
# then the cgroup path. Detection-only — never gates install success on its own;
# al_daemon_user_systemd_available remains the functional discriminator.
al_daemon_in_container() {
  [[ -f /.dockerenv || -f /run/.containerenv ]] && return 0
  [[ -n "${container:-}" ]] && return 0
  grep -qaE '(docker|containerd|podman|libpod|kubepods)' /proc/1/cgroup 2>/dev/null && return 0
  return 1
}

# al_daemon_report_no_daemon <tool> <foreground-cmd>
# Shared "daemon not started" explanation for the systemd-unavailable branch. Names the
# actual reason — container vs bus-unreachable host — then points at the foreground
# fallback. Keeps the two recipes' user-facing copy identical.
al_daemon_report_no_daemon() {
  local tool="${1:?al_daemon_report_no_daemon: tool required}" fg_cmd="${2:-}"
  if al_daemon_in_container; then
    printf '%s: running inside a container — per-user systemd (the Gateway daemon) is not available here; installed config-only.\n' "$tool"
    printf '%s:   this is expected in Docker/CI; the managed daemon is validated on a real host (QEMU).\n' "$tool"
  else
    printf '%s: per-user systemd is not reachable on this host — Gateway NOT auto-started (installed config-only).\n' "$tool" >&2
    printf '%s:   enable a per-user systemd session (loginctl enable-linger) and re-install for the managed daemon.\n' "$tool" >&2
  fi
  [[ -n "$fg_cmd" ]] && printf '%s:   or run it in the foreground now: %s\n' "$tool" "$fg_cmd"
  return 0
}

# al_daemon_enable_linger
# Ensure the agent user's systemd instance persists across logout so a per-user daemon
# keeps running on a headless host. Idempotent, and OWNERSHIP-AWARE: if linger is already
# on (the user brought it), we leave it and record NOTHING — teardown must never revert a
# user's own linger. Only when WE turn it on do we drop the managed marker. Uses agent
# NOPASSWD sudo (ADR-012); `loginctl enable-linger <user>` is the documented headless fix.
al_daemon_enable_linger() {
  local user marker
  user="$(id -un)"
  marker="$(_al_daemon_linger_marker)"

  if loginctl show-user "$user" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
    printf 'daemon-lifecycle: linger already enabled for %s (left as-is)\n' "$user"
    return 0
  fi

  printf 'daemon-lifecycle: enabling linger for %s\n' "$user"
  if ! sudo loginctl enable-linger "$user" 2>/dev/null; then
    printf 'daemon-lifecycle: could not enable linger for %s\n' "$user" >&2
    return 1
  fi
  mkdir -p "$(_al_daemon_dir)"
  printf '%s\n' "$user" >"$marker"
  return 0
}

# al_daemon_mark <tool>   /   al_daemon_unmark <tool>
# Per-tool marker recording that AgentLinux set up a daemon for <tool>. Its presence
# gates linger revert (see al_daemon_revert_linger_if_unused). Idempotent.
al_daemon_mark() {
  local tool="${1:?al_daemon_mark: tool name required}"
  mkdir -p "$(_al_daemon_dir)"
  touch "$(_al_daemon_dir)/${tool}.daemon"
}
al_daemon_unmark() {
  local tool="${1:?al_daemon_unmark: tool name required}"
  rm -f "$(_al_daemon_dir)/${tool}.daemon"
}

# al_daemon_revert_linger_if_unused
# Revert linger ONLY when BOTH hold: (1) AgentLinux enabled it (the managed marker
# exists — a user-brought linger has none and is left untouched), and (2) no other
# AgentLinux daemon tool remains (no *.daemon markers). This keeps `agentlinux remove`
# residue-free for the last daemon tool without cutting linger out from under a second
# daemon the user still runs. Best-effort: a disable-linger failure is logged, not fatal.
al_daemon_revert_linger_if_unused() {
  local marker dir remaining user
  marker="$(_al_daemon_linger_marker)"
  dir="$(_al_daemon_dir)"
  [[ -f "$marker" ]] || return 0

  # Count remaining per-tool daemon markers. `find -printf '.' | wc -c` counts one dot per
  # match (newline-immune, and cleanly 0 on no match — no glob guard needed). Tool names
  # are trusted identifiers (al_daemon_mark takes a literal id like "openclaw").
  remaining=$(find "$dir" -maxdepth 1 -name '*.daemon' -type f -printf '.' 2>/dev/null | wc -c)
  if [[ "$remaining" -gt 0 ]]; then
    printf 'daemon-lifecycle: %s daemon tool(s) remain; keeping linger\n' "$remaining"
    return 0
  fi

  user="$(id -un)"
  printf 'daemon-lifecycle: reverting AgentLinux-enabled linger for %s\n' "$user"
  sudo loginctl disable-linger "$user" 2>/dev/null \
    || printf 'daemon-lifecycle: disable-linger for %s failed (non-fatal)\n' "$user" >&2
  rm -f "$marker"
  rmdir "$dir" 2>/dev/null || true
  return 0
}
