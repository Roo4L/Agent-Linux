#!/usr/bin/env bash
set -euo pipefail
# opencode install.sh — real body (Phase 25, AGT-05 + ENABLE-08).
#
# npm_package_name: opencode-ai (verified 2026-06-29 via npm view).
#   npm view opencode-ai@1.17.11 bin -> { opencode: 'bin/opencode.exe' }
# The bin/opencode.exe shim is a cross-platform launcher that execs the
# platform-native binary shipped as an optionalDependency; on linux-x64 npm
# resolves opencode-linux-x64 automatically. Binary name is `opencode`.
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts) keeps the install
# agent-owned, no root, no /usr/local shim (RT-02, ADR-004).
# Provider auth is supplied post-install (opencode auth login) — never baked.
#
# ENABLE-08 (passive autoupdate freeze): unlike codex (notify-only), opencode
# AUTO-INSTALLS patch releases in the background on TUI startup — its
# cli/upgrade.ts upgrade() runs `npm install -g opencode-ai@<newer>` into the
# agent-owned npm prefix without the user asking. That is the passive
# self-update class AgentLinux freezes so the catalog pin stays authoritative
# (updates flow through `agentlinux upgrade opencode`, never out of band). We
# disable it via the GLOBAL config key `"autoupdate": false` in
# ~/.config/opencode/opencode.json — the documented, launch-mode-independent
# location (the OPENCODE_DISABLE_AUTOUPDATE env var only covers shells that
# export it, so it would miss cron/systemd starts). The explicit
# `opencode upgrade` path ignores this key, so user-initiated upgrades still
# work. ~/.config/opencode/ is in preserve_paths.json, so the freeze (and the
# user's auth) survive REMEDIATE-04 uninstall+reinstall (CAT-04).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "opencode: installing opencode-ai@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "opencode-ai@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v opencode || true)
if [[ -z "$bin_path" ]]; then
  echo "opencode install: opencode not on PATH after install" >&2
  exit 1
fi

# `opencode --version` prints the bare version (e.g. "1.17.11").
version_line=$(opencode --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'opencode install: pinned=%s but `opencode --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

# ENABLE-08: freeze opencode's passive background self-update (see header).
# Idempotent JSON merge via node (the provisioned runtime — no jq dependency):
# set the top-level "autoupdate" key to false while preserving every other key
# the user may have authored. Atomic same-dir tmp+rename so a crash mid-write
# never leaves a truncated config; a pre-existing non-JSON config is left
# untouched (we warn rather than clobber). Path is passed via the environment,
# never interpolated into the script body.
freeze_autoupdate() {
  local config_dir="${AGENTLINUX_AGENT_HOME}/.config/opencode"
  local config_file="${config_dir}/opencode.json"
  mkdir -p "$config_dir"
  AGENTLINUX_OPENCODE_CONFIG="$config_file" node <<'NODE'
const fs = require('fs');
const file = process.env.AGENTLINUX_OPENCODE_CONFIG;
let cfg = {};
let mode = 0o600; // default for a freshly created config
if (fs.existsSync(file)) {
  try {
    cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    // Omit the parse error text: a malformed settings file may hold cached
    // creds, and V8's SyntaxError embeds the offending input's leading bytes —
    // which would spill into the install transcript. The path (printed) is
    // enough to diagnose.
    console.error(`opencode: existing ${file} is not valid JSON; leaving untouched — autoupdate NOT frozen`);
    process.exit(0);
  }
  if (typeof cfg !== 'object' || cfg === null || Array.isArray(cfg)) {
    console.error(`opencode: existing ${file} is not a JSON object; leaving untouched — autoupdate NOT frozen`);
    process.exit(0);
  }
  mode = fs.statSync(file).mode & 0o777; // preserve the user's original mode
  if (cfg.autoupdate === false) {
    console.log(`opencode: passive autoupdate already disabled in ${file}`);
    process.exit(0);
  }
} else if (cfg.$schema === undefined) {
  cfg.$schema = 'https://opencode.ai/config.json';
}
cfg.autoupdate = false;
const tmp = `${file}.agentlinux.tmp`;
try {
  fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, { mode });
  fs.chmodSync(tmp, mode); // writeFileSync mode is pre-umask; force it exactly
  fs.renameSync(tmp, file);
} catch (err) {
  try { fs.unlinkSync(tmp); } catch { /* no tmp to clean up */ }
  throw err; // a real write failure fails the install (set -e on the bash side)
}
console.log(`opencode: disabled passive autoupdate in ${file}`);
NODE
}

# freeze_autoupdate logs its own authoritative outcome (disabled / already
# disabled / left-untouched); the completion line below deliberately does not
# restate it, so a malformed-config skip is never misreported as "frozen".
freeze_autoupdate

echo "opencode: install complete (resolves at ${bin_path}; version matches pin)"
