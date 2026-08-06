#!/usr/bin/env bash
set -euo pipefail
# spec-kit uninstall.sh — symmetric, idempotent remove (Phase 44, WORK-03/ENABLE-03).
#
# Removes the specify-cli uv tool and, ONLY when AgentLinux itself bootstrapped uv
# (managed marker present) AND no other uv tools remain, the managed uv + its data
# too. A user-brought uv is never touched. Any project-local .specify/ directory is
# the user's work product (outside the tool footprint) and is NEVER removed.
#
# Idempotent: a re-remove with nothing installed is a clean success.

: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/uv-bootstrap.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/uv-bootstrap.sh"

echo "spec-kit: removing the specify-cli uv tool"
al_uv_tool_uninstall "specify-cli" ||
  echo "spec-kit remove: uv tool uninstall reported an issue (continuing best-effort)" >&2

# Tear down the uv bootstrap only if we own it and nothing else uses it.
al_uv_remove_if_managed_and_unused ||
  echo "spec-kit remove: uv teardown reported an issue (continuing best-effort)" >&2

echo "spec-kit: removed. Any project .specify/ directories are left untouched (yours)."
