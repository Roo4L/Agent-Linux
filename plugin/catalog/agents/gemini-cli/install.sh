#!/usr/bin/env bash
set -euo pipefail
# gemini-cli install.sh — real body (Phase 24, AGT-06 + ENABLE-08).
#
# npm_package_name: @google/gemini-cli (verified 2026-06-29 via npm view).
#   npm view @google/gemini-cli@0.49.0 bin -> { gemini: 'bundle/gemini.js' }
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
# Binary name is `gemini`, NOT `gemini-cli` (the catalog id) — the bats test
# and post_install_verify invoke `gemini`.
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts) keeps the global
# install agent-owned, no root, no /usr/local shim (RT-02, ADR-004).
# Google auth (OAuth / GEMINI_API_KEY) is supplied post-install — never baked.
#
# ENABLE-08 (passive autoupdate freeze): gemini-cli AUTO-INSTALLS updates on
# startup by default — handleAutoUpdate.ts spawns a detached
# `npm install -g @google/gemini-cli@latest` into the agent-owned npm prefix
# when it sees a newer version (general.enableAutoUpdate defaults to true).
# That is the passive self-update class AgentLinux freezes so the catalog pin
# stays authoritative. We disable it via the settings key
# general.enableAutoUpdate=false in ~/.gemini/settings.json — the
# launch-mode-independent config the CLI reads regardless of how it is started.
# The explicit `npm install -g @google/gemini-cli@latest` /
# `agentlinux upgrade gemini-cli` path is unaffected and still works.
# ~/.gemini/ is in preserve_paths.json, so the freeze (and cached OAuth creds)
# survive REMEDIATE-04 uninstall+reinstall (CAT-04).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "gemini-cli: installing @google/gemini-cli@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@google/gemini-cli@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v gemini || true)
if [[ -z "$bin_path" ]]; then
  echo "gemini-cli install: gemini not on PATH after install" >&2
  exit 1
fi

# `gemini --version` prints the bare version (e.g. "0.49.0").
version_line=$(gemini --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'gemini-cli install: pinned=%s but `gemini --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

# ENABLE-08: freeze gemini-cli's passive background self-update (see header).
# Idempotent deep-merge via node (the provisioned runtime — no jq dependency):
# set general.enableAutoUpdate=false while preserving every other top-level key
# AND every other general.* key the user may have authored. Atomic same-dir
# tmp+rename; a pre-existing non-JSON settings file is left untouched (warn, do
# not clobber). Path is passed via the environment, never interpolated in.
freeze_autoupdate() {
  local config_dir="${AGENTLINUX_AGENT_HOME}/.gemini"
  local config_file="${config_dir}/settings.json"
  mkdir -p "$config_dir"
  AGENTLINUX_GEMINI_SETTINGS="$config_file" node <<'NODE'
const fs = require('fs');
const file = process.env.AGENTLINUX_GEMINI_SETTINGS;
let cfg = {};
let mode = 0o600; // settings.json may reference cached creds — default tight
if (fs.existsSync(file)) {
  try {
    cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    // Omit the parse error text: a malformed settings file may hold cached
    // creds, and V8's SyntaxError embeds the offending input's leading bytes —
    // which would spill into the install transcript. The path is enough.
    console.error(`gemini-cli: existing ${file} is not valid JSON; leaving untouched — autoupdate NOT frozen`);
    process.exit(0);
  }
  if (typeof cfg !== 'object' || cfg === null || Array.isArray(cfg)) {
    console.error(`gemini-cli: existing ${file} is not a JSON object; leaving untouched — autoupdate NOT frozen`);
    process.exit(0);
  }
  mode = fs.statSync(file).mode & 0o777; // preserve the user's original mode
}
if (typeof cfg.general !== 'object' || cfg.general === null || Array.isArray(cfg.general)) {
  cfg.general = {};
}
if (cfg.general.enableAutoUpdate === false) {
  console.log(`gemini-cli: passive autoupdate already disabled in ${file}`);
  process.exit(0);
}
cfg.general.enableAutoUpdate = false;
const tmp = `${file}.agentlinux.tmp`;
try {
  fs.writeFileSync(tmp, `${JSON.stringify(cfg, null, 2)}\n`, { mode });
  fs.chmodSync(tmp, mode);
  fs.renameSync(tmp, file);
} catch (err) {
  try { fs.unlinkSync(tmp); } catch { /* no tmp to clean up */ }
  throw err; // a real write failure fails the install (set -e on the bash side)
}
console.log(`gemini-cli: disabled passive autoupdate in ${file}`);
NODE
}

# freeze_autoupdate logs its own authoritative outcome; the completion line
# below does not restate it, so a malformed-config skip is never misreported.
freeze_autoupdate

echo "gemini-cli: install complete (resolves at ${bin_path}; version matches pin)"
