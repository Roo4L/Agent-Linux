#!/usr/bin/env bash
set -euo pipefail
# claude-code install.sh — real native installer body (Phase 5 AGT-02 / AGT-02b).
#
# Runs as the `agent` user via as_user dispatch from the Node CLI.
# Expected env (injected by plugin/cli/src/runner.ts):
#   AGENTLINUX_PINNED_VERSION  — e.g. 2.1.98 (required; :? guard below)
#   AGENTLINUX_SOURCE_KIND     — "script" for this entry
#   AGENTLINUX_AGENT_HOME      — /home/agent
#   HOME, PATH, NPM_CONFIG_PREFIX inherited from runner.ts per /etc/agentlinux.env
#
# Refs:
#   - docs/decisions/011-stability-first-version-pinning.md (AGT-02b)
#   - code.claude.com/docs/en/setup#install-a-specific-version (positional arg)
#   - Phase 4 RESEARCH §Pitfall 8 (PIPESTATUS guard against curl-404 swallowed by bash)
#   - downloads.claude.ai/claude-code-releases/bootstrap.sh (source of truth, verified 2026-04-19)
#
# Upstream requirement: Claude Code requires at least 4 GB of available RAM.
# The native installer scans the current directory; because this script is
# dispatched as the agent user under `sudo -u agent -H bash --login -c`, the
# starting cwd is ~agent/ which bounds the filesystem scan (RESEARCH §Pitfall 2).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "claude-code: installing version ${AGENTLINUX_PINNED_VERSION} via native installer"

# set -o pipefail at top makes the pipeline inherit the worst exit; we also
# iterate PIPESTATUS so failure messages name both codes (RESEARCH §Pitfall 8).
if ! curl -fsSL https://claude.ai/install.sh | bash -s "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'claude-code install FAILED (PIPESTATUS: %s)\n' "${PIPESTATUS[*]}" >&2
  exit 1
fi

# Post-install smoke: binary exists at agent-owned prefix.
if [[ ! -x "${AGENTLINUX_AGENT_HOME}/.local/bin/claude" ]]; then
  printf 'claude-code install: expected binary at %s/.local/bin/claude, not found\n' \
    "${AGENTLINUX_AGENT_HOME}" >&2
  exit 1
fi

claude_version=$("${AGENTLINUX_AGENT_HOME}/.local/bin/claude" --version 2>&1 | head -1)
printf 'claude-code: installed, reports: %s\n' "$claude_version"

# AGT-02b in-recipe assertion: bootstrap script may drift (stable channel
# moved); catch before the CLI writes a success sentinel.
if ! printf '%s' "$claude_version" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'claude-code install: pinned=%s but --version reports: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$claude_version" >&2
  exit 1
fi

echo "claude-code: install complete (AGT-02b version-lock satisfied)"

# Disable Claude Code's in-tool background auto-updater so ADR-011's
# pinned_version stays honored at runtime, not just at install time.
# Manual `claude update` (AGT-02) still works — only the background path
# is suppressed. jq is available because 30-nodejs.sh pulls it in
# transitively. The merge filter preserves any pre-existing user keys.
settings_dir="${AGENTLINUX_AGENT_HOME}/.claude"
settings_file="${settings_dir}/settings.json"
mkdir -p "${settings_dir}"
tmp="${settings_file}.tmp.$$"
if [[ -f "${settings_file}" ]]; then
  jq '. + {env: ((.env // {}) + {DISABLE_AUTOUPDATER:"1"})}' "${settings_file}" > "${tmp}"
else
  jq -n '{env:{DISABLE_AUTOUPDATER:"1"}}' > "${tmp}"
fi
mv "${tmp}" "${settings_file}"
echo "claude-code: settings.json stamped (DISABLE_AUTOUPDATER=1)"
