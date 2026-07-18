#!/usr/bin/env bash
set -euo pipefail
# rtk rewire.sh — WIRE-02 reverse-trigger (#4 dogfood).
#
# Dispatched by the CLI's post-install reconcile (plugin/cli/src/rewire.ts) after
# a coding agent is installed while rtk is already present. Re-fans rtk's `init`
# wiring into every present agent — including the one just installed — WITHOUT
# re-downloading the binary, so rtk wiring converges regardless of install order.
#
# No-op (exit 0) when rtk isn't on PATH: the reconcile only dispatches this for an
# installed rtk, but a half-removed rtk must not error the agent install that
# triggered the reconcile.

: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

if ! command -v rtk >/dev/null 2>&1; then
  echo "rtk rewire: rtk not on PATH — nothing to re-wire"
  exit 0
fi

# shellcheck source=../../lib/rtk-wire.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/rtk-wire.sh"
al_rtk_wire
