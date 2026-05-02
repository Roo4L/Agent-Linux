#!/usr/bin/env bash
set -euo pipefail
# gsd install.sh — real body (Phase 5 AGT-04).
#
# npm_package_name: get-shit-done-cc (verified 2026-04-19 via npm view).
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
#
# CRITICAL: the binary name is `get-shit-done-cc`, NOT the three-letter slug.
# Verified: `npm view get-shit-done-cc bin` →
#   { 'get-shit-done-cc': 'bin/install.js' }
# AGT-04's bats test invokes `get-shit-done-cc` only. See 05-RESEARCH
# §Open Question 1 — research-locked decision: keep the package-native name,
# no symlink (adding a three-letter symlink would be a hidden shim in the
# spirit of the wrapper-shim anti-pattern).
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global is set by runner.ts (mirrors
# /etc/agentlinux.env) — the global install lands in agent-owned territory
# without privilege escalation (RT-02 keystone, ADR-004).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"

echo "gsd: installing get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"

# --omit=dev skips devDependencies; --no-fund / --no-audit silence npm's
# noise for cleaner transcripts (faster, shorter logs for debugging).
npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "get-shit-done-cc@${AGENTLINUX_PINNED_VERSION}"

# Post-install smoke: binary resolves on PATH AND banner reports pinned version.
# `get-shit-done-cc --help` exits 0 and prints the banner containing
# "Get Shit Done v1.37.1". No --version flag exists (verified via npm view).
bin_path=$(command -v get-shit-done-cc || true)
if [[ -z "$bin_path" ]]; then
  echo "gsd install: get-shit-done-cc not on PATH after install" >&2
  exit 1
fi

# banner grep — the installer prints "Get Shit Done v<version>" before any
# subcommand logic; --help short-circuits cleanly after the banner.
banner=$(get-shit-done-cc --help 2>&1 | head -20)
if ! printf '%s' "$banner" | grep -q -F "v${AGENTLINUX_PINNED_VERSION}"; then
  printf 'gsd install: pinned=%s but banner: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$banner" >&2
  exit 1
fi

## get-shit-done-cc is the BOOTSTRAPPER, not the slash-commands themselves.
## After npm install the binary lives on PATH but Claude Code does not yet
## see any /gsd-* commands or skills. The bootstrapper has to be invoked
## with --global --claude to copy the GSD skill set into ~/.claude/skills/
## (122+ skill dirs, hooks, statusline, settings) — that is what makes
## /gsd-* commands surface inside Claude Code.
##
## Discovered by dogfood: a fresh AgentLinux + `agentlinux install gsd`
## left ~/.claude/skills/gsd-* empty, so the user ran Claude Code and saw
## zero GSD commands. The recipe was technically correct (npm install
## succeeded, binary on PATH, banner matched pin) but the user-visible
## intent ("install GSD") was not satisfied.
echo "gsd: wiring GSD skill set into ~/.claude/ via get-shit-done-cc --global --claude"
get-shit-done-cc --global --claude

echo "gsd: install complete (resolves at ${bin_path}; banner matches pin; skill set wired into ~/.claude/skills/)"
