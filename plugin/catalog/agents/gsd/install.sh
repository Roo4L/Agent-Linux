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
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

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
## After npm install the binary lives on PATH but no coding agent yet sees
## any /gsd-* commands or skills. The bootstrapper has to be invoked with
## per-runtime flags to copy the GSD skill set into each agent's config dir
## (122+ skill dirs, hooks, statusline, settings) — that is what makes
## /gsd-* commands surface inside the agent.
##
## WIRE-01 (cross-agent skill wiring): GSD is a skill PROVIDER, and its
## bootstrapper is natively multi-runtime — `--claude --opencode --gemini
## --codex --qwen` each install GSD into that tool's own config dir, with GSD
## owning the per-tool format conversion (Claude skills, opencode `command/`
## markdown, gemini namespaced `commands/gsd/`, codex/qwen `skills/`). So we
## wire GSD into EVERY coding agent AgentLinux ships, not just Claude Code.
## The flags are passed UNCONDITIONALLY (independent of which agents are
## installed right now): GSD writes each tool's config dir regardless, so the
## wiring is install-order-independent — a codex/opencode/gemini/qwen installed
## later already finds the GSD skill set present. Removal is symmetric in
## uninstall.sh.
##
## Discovered by dogfood: a fresh AgentLinux + `agentlinux install gsd`
## left ~/.claude/skills/gsd-* empty, so the user ran Claude Code and saw
## zero GSD commands. The recipe was technically correct (npm install
## succeeded, binary on PATH, banner matched pin) but the user-visible
## intent ("install GSD") was not satisfied.
## Wrap the bootstrapper non-fatally so the recipe stays idempotent on
## re-runs / `--force`. Upstream may exit non-zero on "already installed"
## paths or on partial-state recovery; what we actually care about is that
## the skill set ends up under each agent's config dir — verified below.
agent_home="${AGENTLINUX_AGENT_HOME}"
echo "gsd: wiring GSD skill set into all shipped agents via get-shit-done-cc --global --claude --opencode --gemini --codex --qwen"
get-shit-done-cc --global --claude --opencode --gemini --codex --qwen \
  || echo "gsd install: bootstrapper exited non-zero (re-run / partial-state path); verifying wired dirs anyway" >&2

# Sanity-check that the GSD skill/command surface landed for EACH shipped
# agent. Without these assertions a regression to "binary on PATH but
# bootstrapper never wired an agent" would silently slip through. Paths are the
# per-tool surfaces observed for the pinned GSD (Claude/codex/qwen use a
# `skills/` dir, opencode a `command/` dir, gemini a namespaced `commands/gsd`
# dir); a GSD pin bump re-validates them. Each check is FATAL — WIRE-01 is the
# contract that installing GSD lights up every agent.
# _assert_wired <label> <find-root> <find-args...>
_assert_wired() {
  local label=$1 root=$2
  shift 2
  if ! find "$root" "$@" -print -quit 2>/dev/null | grep -q .; then
    printf 'gsd install: WIRE-01 — no GSD content for %s under %s after bootstrapper run\n' "$label" "$root" >&2
    exit 1
  fi
  echo "gsd: wired into ${label} (${root})"
}

_assert_wired "Claude Code" "${agent_home}/.claude/skills" -maxdepth 1 -type d -name 'gsd-*'
_assert_wired "opencode" "${agent_home}/.config/opencode/command" -maxdepth 1 -type f -name 'gsd-*.md'
_assert_wired "gemini-cli" "${agent_home}/.gemini/commands" -maxdepth 2 -type d -name 'gsd'
_assert_wired "codex" "${agent_home}/.codex/skills" -maxdepth 1 -type d -name 'gsd-*'
_assert_wired "qwen-code" "${agent_home}/.qwen/skills" -maxdepth 1 -type d -name 'gsd-*'

echo "gsd: install complete (resolves at ${bin_path}; banner matches pin; skill set wired into Claude Code + opencode + gemini-cli + codex + qwen-code)"
