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
# `apt-get update` runs first because the cache is empty on freshly pulled
# Ubuntu containers and long-idle hosts; without it `apt-get install` exits
# with "Package locales has no installation candidate" (AL-37). Mirrors the
# canonical pattern at 30-nodejs.sh:33.
if ! command -v locale-gen >/dev/null 2>&1; then
  log_warn "locale-gen not found; installing 'locales' package"
  DEBIAN_FRONTEND=noninteractive apt-get update
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
