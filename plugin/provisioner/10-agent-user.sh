#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/provisioner/10-agent-user.sh — agent user creation, locale, DOC-02 CLAUDE.md.
#
# Sourced by plugin/bin/agentlinux-install. Inherits `set -euo pipefail`, the
# ERR trap, and the tee redirect to /var/log/agentlinux-install.log from the
# entrypoint; this fragment therefore MUST NOT set its own strict-mode flags.
#
# Requirements satisfied:
#   BHV-01 — agent user exists, has /bin/bash, real home, C.UTF-8 locale
#   DOC-02 — /home/agent/CLAUDE.md with explicit anti-pattern list
#
# Every state mutation routes through plugin/lib/idempotency.sh primitives
# (ensure_user / ensure_dir / ensure_marker_block). Raw `useradd`, `install -d`,
# `echo >>`, `sed -i` are forbidden in this file — re-runs must converge.
#
# Locale handling folds into this provisioner (RESEARCH §"Architectural
# Responsibility Map": "20-locale.sh OR folded into 10-"). Locale is tied to
# the agent user identity, fits in ~10 lines, and keeps the Phase 2 provisioner
# count minimal. See DEVIATIONS in 02-03-SUMMARY for the fold-vs-split call.

log_info "10-agent-user: starting"

# Phase 13 (REUSE-01) — dispatch on reuse::user_decision before any state
# mutation. When the install user is REUSE-compatible (CONTEXT.md Area 1 Q1's
# five predicates — present, /bin/bash shell, writable home, NOPASSWD-for-apt,
# --user-name match), skip useradd + locale-gen + ensure_dir on the existing
# home. Step 3 (DOC-02 CLAUDE.md ensure_marker_block) and 40-path-wiring.sh
# still run UNCONDITIONALLY — additive against existing user content per the
# non-mutating REUSE semantics for "attach to existing user".
#
# Phase 14 will replace the `remediate)` and `bail)` branches with real
# handlers WITHOUT changing the dispatch shape (CONTEXT.md "Phase 13 → Phase
# 14 contract"). The case enumerates all four dispatch tokens even though
# Phase 13's reuse::user_decision emits all four — explicit-enumeration form
# keeps the surface stable across the contract.
#
# CRITICAL caveat — 10-agent-user.sh hardcodes literal `agent` paths
# throughout (Step 1 ensure_dir /home/agent, Step 3 DOC-02 CLAUDE.md path).
# When --user=NAME is supplied and the user IS REUSE-compatible, those literal
# paths still resolve correctly only because CONTEXT.md Area 1 Q1 predicate 5
# bails on name mismatch — i.e., REUSE only fires when the requested user is
# named `agent` OR no --user was supplied. Phase 14/15 will extend to alt-user
# names; Phase 13 keeps the literal `agent` paths intact under REUSE-compatible
# cases.
REUSED_USER=false
# Phase 14 (Plan 14-01): provisioner reads pre-resolved token from RESOLUTIONS
# map. Decisions are made up-front in main() by remediate::collect_all_decisions
# BEFORE any provisioner runs, so the `bail` arm here is unreachable — if a
# bail had fired, remediate::flush_bails_or_continue would have exited 65
# already. The case still enumerates all four tokens defensively.
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
    # The user-decision "remediate" token maps to REMEDIATE-03 (sudoers fix —
    # agent exists but lacks NOPASSWD-for-apt). That fix is OWNED by
    # 20-sudoers.sh via RESOLUTIONS[sudoers]. Here we reuse the existing user
    # so the downstream sudoers provisioner has a valid target.
    reuse::log_user_reuse "${INSTALL_USER:-agent}"
    log_info "10-agent-user: REUSE branch (sudoers fix dispatched to 20-sudoers.sh per RESOLUTIONS[sudoers])"
    REUSED_USER=true
    ;;
  bail)
    # UNREACHABLE: flush_bails_or_continue should have exited 65 before
    # run_provisioners. If we somehow get here, it's a hard programming error
    # (e.g., remediate.sh not sourced, or collect_all_decisions not called).
    log_error "10-agent-user: unreachable bail arm — flush_bails_or_continue should have gated this"
    return 1
    ;;
esac

# Steps 1 + 2 (CREATE path) are wrapped in the REUSED_USER guard so the REUSE
# branch skips them entirely; the existing user's identity + locale state is
# the user's own configuration (idempotent re-runs against a REUSE branch were
# never the use case here — REUSE is "do nothing" and we mean it).
if [[ "${REUSED_USER:-false}" != true ]]; then
  # Step 1: agent user (BHV-01 — bash shell, home directory).
  # ensure_user is a no-op if `agent` already exists (T-02-05 mitigation:
  # existing `agent` user belonging to a different human is not modified; we
  # only assert existence). ensure_dir then asserts mode/ownership on the
  # already-created /home/agent to correct any out-of-band drift on re-run.
  ensure_user agent
  ensure_dir /home/agent 0755 agent:agent

  # Step 2: Locale (BHV-01 — LANG=C.UTF-8, LC_ALL=C.UTF-8 system-wide).
  #
  # Pitfall 5 (02-RESEARCH.md): `locale-gen C.UTF-8` is a no-op on glibc 2.35+
  # (Ubuntu 22.04 and later) because C.UTF-8 is a built-in locale. That is why
  # we do NOT rely on its exit code — it may legitimately succeed without doing
  # anything — and instead verify outcome with `locale -a` below.
  #
  # Docker slim images strip the `locales` package entirely, so ensure it is
  # installed before invoking locale-gen / update-locale. DEBIAN_FRONTEND +
  # --no-install-recommends keep the install non-interactive and minimal.
  if ! command -v locale-gen >/dev/null 2>&1; then
    log_warn "locale-gen not found; installing 'locales' package"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales
  fi

  # The one documented `|| true` skip-path in this provisioner (per CLAUDE.md
  # "unconditional || true hides real failures" rule). Allowed here because
  # C.UTF-8 is a glibc built-in on every supported host — locale-gen may exit
  # non-zero if /etc/locale.gen has no matching line, which is the expected
  # state on Ubuntu 22.04+. The `locale -a` verification below is the real
  # correctness check.
  locale-gen C.UTF-8 >/dev/null 2>&1 || true
  update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8

  # Outcome verification: accept both `C.UTF-8` (canonical) and `C.utf8` (the
  # form Ubuntu 24.04 reports via `locale -a`). Case-insensitive; optional dash
  # before the `8` per RESEARCH Pitfall 5's verification regex.
  if ! locale -a 2>/dev/null | grep -Eiq '^c\.utf-?8$'; then
    log_error "C.UTF-8 locale not available after locale-gen + update-locale"
    return 1
  fi
  log_info "locale C.UTF-8 enforced (LANG + LC_ALL in /etc/default/locale)"
fi

# Step 3: DOC-02 — /home/agent/CLAUDE.md with anti-pattern guidance.
#
# Uses ensure_marker_block with the stable tag `agentlinux-doc-02` and --top
# placement so:
#   (a) Re-runs are idempotent — identical body produces zero diff (T-02-07).
#   (b) User-added content OUTSIDE the marker block survives re-run.
#   (c) Anti-pattern guidance appears before any user-added sections, so
#       agent tooling reading the file encounters DO-NOT first.
#
# The heredoc tag is stable across phases: Phase 4/5 may extend this block
# but MUST reuse the `agentlinux-doc-02` tag. Do not rename.
#
# The body MUST include the three canonical anti-pattern strings that bats
# tests in Plan 02-05 grep-verify: `usr/local/bin`, `sudo npm install -g`,
# and `second Node.js install`.
ensure_marker_block /home/agent/CLAUDE.md "agentlinux-doc-02" --top <<'DOC02'
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

# ensure_marker_block uses `install -m 0644` which leaves the file root-owned;
# re-assert agent:agent ownership so the agent user can read + edit it outside
# the marker block on subsequent runs.
chmod 0644 /home/agent/CLAUDE.md
chown agent:agent /home/agent/CLAUDE.md
log_info "wrote DOC-02 CLAUDE.md to /home/agent/CLAUDE.md"

log_info "10-agent-user: done"
