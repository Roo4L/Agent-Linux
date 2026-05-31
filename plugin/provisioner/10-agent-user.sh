#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/provisioner/10-agent-user.sh — agent user creation, locale, CLAUDE.md.
#
# Sourced by agentlinux-install. Inherits set -euo pipefail, the ERR trap, and
# the tee redirect — MUST NOT set its own strict-mode flags.
#
# Satisfies BHV-01 (agent user: /bin/bash, real home, C.UTF-8 locale) and
# DOC-02 (/home/agent/CLAUDE.md with the anti-pattern list). Every mutation
# routes through idempotency.sh primitives (ensure_user / ensure_dir /
# ensure_marker_block) so re-runs converge — no raw useradd / echo >> / sed -i.
#
# Locale is folded in here (rather than a separate 20-locale.sh) — it is tied
# to the agent user identity and fits in ~10 lines.

log_info "10-agent-user: starting"

# Dispatch on the pre-resolved RESOLUTIONS[user] token (decisions are made
# up-front in main()). On a REUSE-compatible user, skip useradd + locale-gen +
# ensure_dir on the existing home; Step 3 (CLAUDE.md) and 40-path-wiring.sh
# still run unconditionally (additive).
#
# Caveat: this file hardcodes literal `agent` paths. Those resolve correctly
# under REUSE only because the user-decision bails on a name mismatch — REUSE
# fires only when the user is named `agent`. The bail arm is unreachable
# (flush_bails_or_continue would have exited 65); enumerated defensively.
REUSED_USER=false
case "${RESOLUTIONS[user]:-create}" in
  reuse)
    reuse::log_user_reuse "${INSTALL_USER:-agent}"
    log_info "10-agent-user: REUSE branch — skipping useradd + locale-gen for existing user"
    REUSED_USER=true
    ;;
  create)
    # Fall through to the existing CREATE path (unchanged from v0.3.0).
    REUSED_USER=false
    ;;
  remediate)
    # user "remediate" maps to the sudoers fix owned by 20-sudoers.sh
    # (RESOLUTIONS[sudoers]); here we just reuse the user so that provisioner
    # has a valid target.
    reuse::log_user_reuse "${INSTALL_USER:-agent}"
    log_info "10-agent-user: REUSE branch (sudoers fix dispatched to 20-sudoers.sh per RESOLUTIONS[sudoers])"
    REUSED_USER=true
    ;;
  reuse-with-warning)
    # Defensive arm — user-decision never currently produces a state-overwriting
    # action through the prompt loop. If a future plan does and the operator
    # declines, keep the existing user and emit a [REUSE-WARN] marker.
    reuse::log_user_reuse "${INSTALL_USER:-agent}"
    log_warn "[REUSE-WARN] component=user decline_reason=${DECLINED_COMPONENTS[user]:-unknown} — skipped (user declined remediation; manual fix needed). Existing user unchanged."
    REUSED_USER=true
    ;;
  bail)
    # Unreachable — flush_bails_or_continue should have exited 65 before now.
    log_error "10-agent-user: unreachable bail arm — flush_bails_or_continue should have gated this"
    return 1
    ;;
esac

# Steps 1+2 (CREATE path) run only when the user was not reused — REUSE means
# "do nothing" to the existing user's identity + locale state.
if [[ "${REUSED_USER:-false}" != true ]]; then
  # The alt-user flow may have updated INSTALL_USER; honor it here. Fall back
  # to literal `agent` when unset/empty.
  _AL_INSTALL_USER="${INSTALL_USER:-agent}"
  _AL_INSTALL_HOME="/home/${_AL_INSTALL_USER}"
  # Step 1: install user (BHV-01). ensure_user is a no-op if the user already
  # exists (an existing user belonging to a different human is not modified —
  # we only assert existence); ensure_dir then corrects home mode/ownership.
  ensure_user "${_AL_INSTALL_USER}"
  ensure_dir "${_AL_INSTALL_HOME}" 0755 "${_AL_INSTALL_USER}:${_AL_INSTALL_USER}"

  # Step 2: locale (BHV-01 — LANG/LC_ALL=C.UTF-8 system-wide).
  # locale-gen C.UTF-8 is a no-op on glibc 2.35+ (Ubuntu 22.04+) since C.UTF-8
  # is built in, so we don't trust its exit code and verify via `locale -a`.
  # Docker slim images strip the `locales` package; install it first.
  # apt-get update first — the cache may be empty on fresh containers and
  # long-idle hosts, else apt-get install reports "no installation candidate".
  if ! command -v locale-gen >/dev/null 2>&1; then
    log_warn "locale-gen not found; installing 'locales' package"
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales
  fi

  # The one allowed `|| true` here: locale-gen may exit non-zero when
  # /etc/locale.gen has no matching line (the expected state on 22.04+, where
  # C.UTF-8 is a glibc built-in). The `locale -a` check below is the real test.
  locale-gen C.UTF-8 >/dev/null 2>&1 || true
  update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8

  # Accept both `C.UTF-8` and `C.utf8` (the form Ubuntu 24.04 reports);
  # case-insensitive, optional dash before the 8.
  if ! locale -a 2>/dev/null | grep -Eiq '^c\.utf-?8$'; then
    log_error "C.UTF-8 locale not available after locale-gen + update-locale"
    return 1
  fi
  log_info "locale C.UTF-8 enforced (LANG + LC_ALL in /etc/default/locale)"
fi

# Step 3: DOC-02 — /home/agent/CLAUDE.md with anti-pattern guidance.
# ensure_marker_block with the stable `agentlinux-doc-02` tag and --top
# placement: re-runs are idempotent, user content outside the block survives,
# and the DO-NOT guidance lands before any user-added sections. Do not rename
# the tag. The body must keep the three anti-pattern strings the bats tests
# grep for: `usr/local/bin`, `sudo npm install -g`, `second Node.js install`.
_AL_DOC02_USER="${INSTALL_USER:-agent}"
_AL_DOC02_HOME="/home/${_AL_DOC02_USER}"
ensure_marker_block "${_AL_DOC02_HOME}/CLAUDE.md" "agentlinux-doc-02" --top <<'DOC02'
# /home/agent/CLAUDE.md — AgentLinux agent-user guidance

## This environment is correctly owned

This agent user was provisioned by AgentLinux. Your home directory,
npm global prefix (arrives Phase 3), and per-tool config paths are all owned
by you. You do NOT need sudo for routine agent operations.

If you hit a permission error, that is a BUG in the environment — do NOT
paper over it by climbing the privilege ladder. Exit non-zero, log the
error, and let the human or AgentLinux maintainer diagnose.

## DO NOT (anti-patterns — canonical bugs AgentLinux exists to eliminate)

- **No wrapper shims under `/usr/local/bin/`.** A shim at `/usr/local/bin/claude`
  (or any tool) that `exec`s an agent-owned binary breaks Claude Code's
  self-update: the update rewrites the agent-owned binary, not the shim, so
  the next invocation still points at the old code. This is the canonical
  v0.1 / v0.2 bug that motivated this project.

- **No `sudo npm install -g`.** If `npm install -g <pkg>` fails with EACCES,
  the environment is broken. Fix the environment; do not work around it.
  The agent's npm prefix is under `$HOME` (arrives Phase 3); global installs
  work without sudo by design.

- **No second Node.js install (nvm, fnm, volta, manual tarball).** The system
  Node.js from NodeSource (Phase 3+) is correctly owned. A second Node.js
  install creates a PATH race that breaks cron and systemd invocations.

- **No `sudo $0 "$@"` self-re-exec.** If you need a privilege you do not
  have, stop and report — do not recover by climbing the privilege ladder.

- **No writes to installer-owned paths:** `/usr/local/lib/node_modules`,
  `/opt`, `/etc/agentlinux.env`, `/etc/profile.d/*.sh`, `/etc/sudoers.d/*`.

## Where you (the agent tool) SHOULD write

- `$HOME/.npm-global/` — npm globals (arrives Phase 3)
- `$HOME/.local/bin` — per-user scripts
- `$HOME/.config/<tool>/` — per-tool config
- `$HOME/.cache/<tool>/` — per-tool cache

## Signal when you hit a permission error

Exit non-zero, log the error, let the human or AgentLinux maintainer
diagnose. DO NOT "recover" by climbing the privilege ladder — that is
precisely the bug class AgentLinux exists to prevent.
DOC02

# ensure_marker_block leaves the file root-owned; re-assert agent:agent so the
# user can read + edit it outside the marker block.
chmod 0644 "${_AL_DOC02_HOME}/CLAUDE.md"
chown "${_AL_DOC02_USER}:${_AL_DOC02_USER}" "${_AL_DOC02_HOME}/CLAUDE.md"
log_info "wrote DOC-02 CLAUDE.md to ${_AL_DOC02_HOME}/CLAUDE.md"

log_info "10-agent-user: done"
