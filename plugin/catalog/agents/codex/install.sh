#!/usr/bin/env bash
set -euo pipefail
# codex install.sh — real body (Phase 23, AGT-07 + ENABLE-05).
#
# npm_package_name: @openai/codex (verified 2026-06-29 via npm view).
#   npm view @openai/codex@0.142.3 bin -> { codex: 'bin/codex.js' }
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
# The bin/codex.js shim execs a platform-native binary shipped as an
# optionalDependency (@openai/codex-linux-x64 etc.); npm picks the right one.
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global is set by runner.ts (mirrors
# /etc/agentlinux.env) — the global install lands in agent-owned territory
# without privilege escalation (RT-02 keystone, ADR-004). `codex` resolves at
# ${prefix}/bin/codex, NOT a /usr/local shim.
#
# ENABLE-05 (self-updater coexistence — re-exercises the AGT-02 concern):
#   Codex ships a built-in self-updater (`codex update`) and a passive
#   "newer version available" check at startup. Under AgentLinux the catalog
#   pin (this npm install) is authoritative — updates flow through
#   `agentlinux upgrade codex`, NOT `codex update`. We make the pin stick two
#   ways:
#     1. Disable the startup update check by setting
#        `check_for_update_on_startup = false` in ~/.codex/config.toml
#        (idempotent, non-destructive — see ensure_no_startup_update_check).
#     2. The npm shim exports CODEX_MANAGED_PACKAGE_ROOT, so codex's own
#        `update` command detects the install is "managed by npm" and refuses
#        to clobber a different install target — upstream belt to our braces.
#   ~/.codex/ is listed in preserve_paths.json so the config (and the user's
#   auth) survive REMEDIATE-04 uninstall+reinstall (CAT-04).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "codex: installing @openai/codex@${AGENTLINUX_PINNED_VERSION}"

# --omit=dev skips devDependencies; --no-fund / --no-audit silence npm's
# noise for cleaner transcripts (faster, shorter logs for debugging).
npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@openai/codex@${AGENTLINUX_PINNED_VERSION}"

# Post-install smoke: binary resolves on PATH AND reports the pinned version.
bin_path=$(command -v codex || true)
if [[ -z "$bin_path" ]]; then
  echo "codex install: codex not on PATH after install" >&2
  exit 1
fi

# `codex --version` prints "codex-cli <version>" — version-lock against the pin
# to catch a mispin BEFORE the user ever runs it (AGT-02b shape).
version_line=$(codex --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'codex install: pinned=%s but `codex --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

# Codex sandboxes command execution with bubblewrap (`bwrap`). It ships a
# bundled copy but prefers a system one and otherwise nags on every launch:
#   ⚠ Codex could not find bubblewrap on PATH. … Codex will use the bundled
#     bubblewrap in the meantime.
# Install the distro package so codex uses the system sandbox and the warning
# stops. NON-FATAL: agent has NOPASSWD sudo (ADR-012), but a locked-down host
# without apt/sudo still gets a working codex (bundled bwrap fallback), so a
# failure here only logs — it never fails the install.
ensure_bubblewrap() {
  if command -v bwrap >/dev/null 2>&1; then
    echo "codex: bubblewrap already present ($(command -v bwrap))"
    return 0
  fi
  echo "codex: installing bubblewrap (codex's system sandbox) via apt"
  if sudo -n env DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 \
    && sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bubblewrap >/dev/null 2>&1; then
    echo "codex: bubblewrap installed ($(command -v bwrap || echo bwrap))"
  else
    echo "codex install: could not install bubblewrap (no apt/sudo?); codex will use its bundled copy" >&2
  fi
}

ensure_bubblewrap

# ENABLE-05: disable codex's in-app startup update check so the catalog pin
# stays authoritative and the agent is never nudged to self-update out of band.
# Idempotent + non-destructive: only add the key when it is absent, and
# prepend it (TOML top-level keys must precede any [table] header) so we never
# corrupt a user-authored config.toml.
ensure_no_startup_update_check() {
  local config_dir="${AGENTLINUX_AGENT_HOME}/.codex"
  local config_file="${config_dir}/config.toml"
  local marker='# Added by AgentLinux (ENABLE-05): catalog pin is authoritative; update via `agentlinux upgrade codex`.'
  local key='check_for_update_on_startup = false'

  mkdir -p "$config_dir"

  if [[ -f "$config_file" ]] \
    && grep -qE '^[[:space:]]*check_for_update_on_startup[[:space:]]*=' "$config_file"; then
    echo "codex: ~/.codex/config.toml already sets check_for_update_on_startup — leaving as-is"
    return 0
  fi

  if [[ -f "$config_file" ]]; then
    local tmp
    # Create the temp file IN the destination dir so the final `mv` is an
    # atomic same-filesystem rename (a /tmp temp could cross filesystems and
    # degrade to copy+unlink).
    tmp=$(mktemp "${config_dir}/.config.toml.XXXXXX")
    # Self-cleaning on any early exit (set -e) so a failed read/append never
    # leaks a temp file.
    trap 'rm -f "$tmp"' RETURN
    printf '%s\n%s\n\n' "$marker" "$key" >"$tmp"
    cat "$config_file" >>"$tmp"
    # Preserve the user's original config.toml mode — mktemp creates 0600 and a
    # bare `mv` would silently narrow an e.g. 0644 config.
    chmod --reference="$config_file" "$tmp"
    mv "$tmp" "$config_file"
  else
    printf '%s\n%s\n' "$marker" "$key" >"$config_file"
  fi
  echo "codex: disabled in-app startup update check (ENABLE-05) in ${config_file}"
}

ensure_no_startup_update_check

echo "codex: install complete (resolves at ${bin_path}; version matches pin; self-updater coexistence enforced)"
