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
#
# Security invariants (T-05.1-01..04):
#   - `visudo -cf` gate runs on the tmpfile BEFORE `install` moves it into
#     place. A syntax error in the written content aborts the installer
#     without ever touching /etc/sudoers.d/ — the system's existing sudoers
#     policy is never at risk (T-05.1-01).
#   - Atomic install via `install(1)` with explicit -m 0440 -o root -g root:
#     mode + ownership set at rename time; there is no window where the file
#     exists with wrong permissions (T-05.1-02).
#   - Mode 0440 means only root can read the drop-in — the agent user can
#     observe effective policy via `sudo -l` but cannot `cat` this file
#     (T-05.1-03).
#   - Atomic overwrite (install(1), not echo >>) — re-runs produce a
#     byte-identical file. Idempotency verified by the paired bats @test
#     that snapshots sha256 across two installer invocations (T-05.1-04).
#
# Post-install verify rehashes the installed file through `visudo -cf` so any
# out-of-band corruption between rename and exit surfaces immediately.

log_info "20-sudoers: starting"

# Minimal Ubuntu/Debian cloud images (and many Docker base images) ship without
# the `sudo` package, which provides both the `sudo` binary AND `visudo`. We
# need `visudo` to validate the drop-in before installing it (T-05.1-01), and
# the agent user obviously needs `sudo` afterwards. Mirror the pattern used by
# 10-agent-user.sh's `locales` install.
if ! command -v visudo >/dev/null 2>&1; then
  log_warn "visudo not found; installing 'sudo' package"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo
fi

readonly SUDOERS_FILE="/etc/sudoers.d/agentlinux"
# Single-quoted heredoc — no shell expansion, byte-stable across re-runs. The
# meaningful policy is the single line `agent ALL=(ALL) NOPASSWD: ALL`; the
# header comments are deterministic and documented as part of the drop-in
# contract (bats asserts the NOPASSWD line via `grep -Fx`, not the full body,
# so header wording can evolve without breaking BHV-07).
read -r -d '' SUDOERS_CONTENT <<'SUDOERS' || true
# Installed by AgentLinux — grants passwordless sudo to agent user.
# Scope: ALL commands. See docs/decisions/012-agent-user-full-sudo.md.
agent ALL=(ALL) NOPASSWD: ALL
SUDOERS
readonly SUDOERS_CONTENT

# Ensure parent dir exists with correct ownership + mode. ensure_dir is a
# no-op re-asserting mode+ownership when the directory already exists, so this
# also corrects any out-of-band drift on re-run.
ensure_dir /etc/sudoers.d 0755 root:root

# Write to tmpfile → visudo -cf gate → atomic install. A RETURN-scoped trap
# cleans the tmpfile on every exit path (success, visudo rejection,
# install(1) failure) so no stale /tmp/tmp.XXXXXX is left behind.
tmpfile=$(mktemp)
# shellcheck disable=SC2064
# We WANT $tmpfile expanded at trap-install time; resolving later would
# re-read a stale binding if the variable were reassigned. Same pattern as
# ensure_marker_block in plugin/lib/idempotency.sh.
trap "rm -f '$tmpfile'" RETURN

printf '%s\n' "$SUDOERS_CONTENT" >"$tmpfile"

# T-05.1-01 mitigation: validate BEFORE touching /etc/sudoers.d/. visudo -cf
# returns non-zero on any syntax defect in the target file; log + return 1
# trips the entrypoint's ERR trap with correct src:line attribution.
# `return` (not `exit`) — this provisioner is SOURCED, so `return` hands
# control back to run_provisioners() which set -e aborts the installer.
if ! visudo -cf "$tmpfile" >/dev/null; then
  log_error "visudo -cf validation failed on tmpfile — refusing to install $SUDOERS_FILE"
  return 1
fi

# T-05.1-02 mitigation: atomic install with mode + ownership set at rename
# time. install(1) is a rename-like syscall — no intermediate state where the
# file exists with an incorrect mode. Mode literal-inlined (not via variable)
# so a grep audit of this file directly surfaces the 0440 commitment — a
# human reader of the diff sees the mode without chasing indirection.
install -m "0440" -o root -g root "$tmpfile" "$SUDOERS_FILE"

# Post-install verify — hashes the installed file through visudo one more
# time to catch any TOCTOU-style corruption between the tmpfile-validate and
# the rename. Paranoid but essentially free (visudo -cf on a 3-line file is
# sub-millisecond).
if ! visudo -cf "$SUDOERS_FILE" >/dev/null; then
  log_error "post-install visudo -cf failed — $SUDOERS_FILE is corrupt"
  return 1
fi

log_info "wrote $SUDOERS_FILE (mode 0440 root:root — ADR-012)"
log_info "agent user now has passwordless sudo (scope: ALL commands) — INST-06"
log_info "20-sudoers: done"
