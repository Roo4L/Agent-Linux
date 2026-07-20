#!/usr/bin/env bash
set -euo pipefail
# hermes-agent uninstall.sh — symmetric inverse of install.sh (Phase 48, ASST-02 / ENABLE-04).
#
# Tears down the per-user Gateway daemon and removes exactly what AgentLinux installed — the
# `hermes` launcher (~/.local/bin/hermes) and the code checkout + venv (~/.hermes/hermes-agent)
# — while PRESERVING the user's data and secrets that live alongside the checkout in ~/.hermes
# (.env, config.yaml, SOUL.md, memories/, sessions/, skills/). This is the CAT-04 stance every
# authenticated agent follows: a `remove` never destroys the user's assistant data or keys; only
# `agentlinux --purge` wipes the whole agent home.
#
# Why surgical (not a preserve_paths.json gate): ~/.hermes MIXES the installed code with user
# data in one dir, so a whole-dir preserve would also block removing the code. Instead we delete
# ONLY the two install artifacts and leave every sibling untouched — symmetric AND data-safe.
# We deliberately do NOT call `hermes uninstall` (its data-retention semantics are the tool's,
# not ours to depend on); explicit removal keeps the footprint predictable.
#
# Every destructive step is guarded / best-effort, so a second remove on a missing install exits
# 0 (idempotent). The truth check asserts on the concrete agent-owned launcher path.

: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/daemon-lifecycle.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/daemon-lifecycle.sh"

LAUNCHER="${AGENTLINUX_AGENT_HOME}/.local/bin/hermes"
CODE_DIR="${AGENTLINUX_AGENT_HOME}/.hermes/hermes-agent"

echo "hermes-agent: removing hermes-agent"

# --- 1. tear down the per-user Gateway (best-effort; only where a user systemd bus exists) ---
if command -v hermes >/dev/null 2>&1 && al_daemon_user_systemd_available; then
  hermes gateway stop </dev/null >/dev/null 2>&1 || true
  hermes gateway uninstall </dev/null >/dev/null 2>&1 || true
fi

# --- 2. remove exactly the AgentLinux-installed artifacts (launcher + code checkout/venv).
# User data + secrets in ~/.hermes (.env, config.yaml, SOUL.md, memories/, sessions/) are left
# untouched — preserved per CAT-04, wiped only by --purge. ---
rm -f "$LAUNCHER"
rm -rf "$CODE_DIR"

# --- 3. drop the daemon marker + revert linger only if AgentLinux enabled it and no other
# daemon tool remains ---
al_daemon_unmark hermes-agent
al_daemon_revert_linger_if_unused

# --- 4. truth check: the agent-owned launcher is gone (assert on the concrete path, not
# PATH-wide command -v, so a hermes elsewhere cannot mask a correct removal) ---
hash -r
if [[ -e "$LAUNCHER" ]]; then
  echo "hermes-agent uninstall: ${LAUNCHER} still present after removal" >&2
  exit 1
fi

echo "hermes-agent: uninstall complete (~/.hermes user data preserved; --purge wipes it)"
