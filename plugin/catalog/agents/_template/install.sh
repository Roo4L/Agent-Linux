#!/usr/bin/env bash
set -euo pipefail
# _template/install.sh — ENABLE-07 catalog-entry recipe TEMPLATE (copy, do not run).
#
# Copy this directory to plugin/catalog/agents/<your-id>/ and fill it in to add a catalog
# entry WITHOUT touching any CLI TypeScript (CAT-03). The CLI dispatches install/remove
# generically off catalog.json, so a new tool is a catalog entry + this recipe pair.
# See docs/CATALOG-CONTRIBUTING.md for the selection rubric, the category-tag convention,
# and the full step-by-step.
#
# Contract the CLI guarantees your recipe (all exported before it runs):
#   AGENTLINUX_PINNED_VERSION  — the entry's pinned_version (version-lock against it)
#   AGENTLINUX_CATALOG_DIR     — the staged catalog dir (source shared lib/ helpers from here)
#   AGENTLINUX_AGENT_HOME      — the agent user's home (install under here; never /usr/local)
#   AGENTLINUX_PRESERVE_PATHS  — (uninstall only) colon-separated HOME-relative preserve roots
#
# Rules (enforced by review + the behavior suite):
#   - Run as the agent user. NO sudo except the ADR-012 exceptions (e.g. loginctl linger).
#   - NEVER `sudo npm install -g`; NEVER a /usr/local/bin shim — both break self-update.
#   - Install into agent-owned paths (~/.local/bin, ~/.npm-global, ~/.config/<tool>).
#   - NEVER bake a secret. Print a post-install instruction; set requires_secret in the entry.
#   - Version-lock: fail if the installed tool does not report AGENTLINUX_PINNED_VERSION.
#   - Idempotent: a re-install of the same pin is a clean overwrite.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

ver="${AGENTLINUX_PINNED_VERSION}"

# 1. Install the tool at the pinned version into an agent-owned path. Pick the shape that
#    matches your source_kind and reuse the shared helper where one exists:
#      npm     : npm install -g "<pkg>@${ver}"
#      binary  : source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"; al_pb_install …
#      uv tool : source "${AGENTLINUX_CATALOG_DIR}/lib/uv-bootstrap.sh"; al_uv_ensure; al_uv_tool_install …
#      mcp     : source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"; al_mcp_register_http …
#      daemon  : source "${AGENTLINUX_CATALOG_DIR}/lib/daemon-lifecycle.sh"; al_daemon_* …
echo "TEMPLATE: install <tool>@${ver} here (agent-owned path, no /usr/local shim)"

# 2. Version-lock — fail loudly if the installed tool does not report the pinned version.
#    hash -r
#    got="$(<tool> --version 2>&1 | head -1)"
#    printf '%s' "$got" | grep -qF -- "$ver" || { echo "version-lock failed: $got" >&2; exit 1; }

# 3. If the tool needs a credential, print the post-install instruction — NEVER bake it.
echo "TEMPLATE: (if applicable) tell the user how to authenticate; bake no secret."
