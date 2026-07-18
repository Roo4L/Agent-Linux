#!/usr/bin/env bash
set -euo pipefail
# _template/uninstall.sh — ENABLE-07 recipe TEMPLATE (copy, do not run). The SYMMETRIC
# inverse of install.sh: remove exactly what install.sh created, and nothing the user owns.
# See docs/CATALOG-CONTRIBUTING.md.
#
# Rules:
#   - Idempotent: every step guarded / best-effort, so a second remove on a missing install
#     exits 0. Prefer `rm -f`, `|| true`, existence checks.
#   - CAT-04: preserve the user's config/credentials. If your entry sets preserve_paths_file,
#     the CLI injects AGENTLINUX_PRESERVE_PATHS on every uninstall — gate deletes with the
#     _should_remove helper below so a `remove` keeps auth/config and only `--purge` wipes it.
#   - Truth-check on the concrete agent-owned install path (NOT PATH-wide `command -v`), so a
#     same-named tool elsewhere on PATH cannot make a correct removal look like a failure.

: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# _should_remove <abs-path> — 0 (proceed) unless <abs-path> is in/under any preserve root
# (colon-separated, HOME-relative; empty → nothing preserved). Copy verbatim from gh/openclaw.
_should_remove() {
  local target=$1
  [[ -z "${AGENTLINUX_PRESERVE_PATHS:-}" ]] && return 0
  local t_strip="${target%/}"
  local IFS=:
  local preserved
  for preserved in $AGENTLINUX_PRESERVE_PATHS; do
    local p_strip="${preserved%/}"
    if [[ "$t_strip" == "${AGENTLINUX_AGENT_HOME}/${p_strip}" ||
      "$t_strip" == "${AGENTLINUX_AGENT_HOME}/${p_strip}/"* ]]; then
      return 1
    fi
  done
  return 0
}

echo "TEMPLATE: remove exactly what install.sh created"

# 1. Remove the installed artifact (mirror your install shape):
#      npm     : npm rm -g "<pkg>" || true
#      binary  : rm -f "${AGENTLINUX_AGENT_HOME}/.local/bin/<tool>"
#      uv tool : source .../uv-bootstrap.sh; al_uv_tool_uninstall <pkg>; al_uv_remove_if_managed_and_unused
#      mcp     : source .../mcp-register.sh; al_mcp_deregister <server>
#      daemon  : source .../daemon-lifecycle.sh; <tool> daemon uninstall; al_daemon_unmark <id>; al_daemon_revert_linger_if_unused

# 2. Config/credentials — preserve per CAT-04 (only delete when NOT preserved):
#      if _should_remove "${AGENTLINUX_AGENT_HOME}/.config/<tool>"; then
#        rm -rf "${AGENTLINUX_AGENT_HOME}/.config/<tool>"
#      fi

# 3. Truth-check on the concrete install path:
#      hash -r
#      [[ -e "${AGENTLINUX_AGENT_HOME}/.local/bin/<tool>" ]] && { echo "still present" >&2; exit 1; }

echo "TEMPLATE: uninstall complete"
