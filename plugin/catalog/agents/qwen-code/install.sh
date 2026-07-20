#!/usr/bin/env bash
set -euo pipefail
# qwen-code install.sh — real body (Phase 26, AGT-08 + ENABLE-08).
#
# npm_package_name: @qwen-code/qwen-code (verified 2026-06-29 via npm view).
#   npm view @qwen-code/qwen-code@0.19.2 bin -> { qwen: 'cli-entry.js' }
# source_kind: npm — per-user global install via Phase 3's .npm-global prefix.
# Binary name is `qwen`, NOT `qwen-code` (the catalog id).
#
# NPM_CONFIG_PREFIX=/home/agent/.npm-global (runner.ts) keeps the install
# agent-owned, no root, no /usr/local shim (RT-02, ADR-004).
# Provider auth (DASHSCOPE_API_KEY / OpenAI-compatible creds) is supplied
# post-install — never baked into the recipe.
#
# ENABLE-08 (passive autoupdate freeze): qwen-code inherits its upstream CLI
# auto-updater — handleAutoUpdate.ts spawns a detached
# `npm install -g @qwen-code/qwen-code@latest` on startup by default
# (general.enableAutoUpdate defaults to true). Freezing this matters doubly
# here: on a non-agent-owned npm prefix qwen's auto-update fails EACCES and
# newer versions SILENTLY re-route to a standalone curl|bash installer,
# migrating the tool off npm — the exact ownership/recursive-install bug class
# AgentLinux exists to prevent. We disable it via general.enableAutoUpdate=false
# in ~/.qwen/settings.json (launch-mode-independent). The explicit
# `npm install -g @qwen-code/qwen-code@latest` / `agentlinux upgrade qwen-code`
# path is unaffected. ~/.qwen/ is in preserve_paths.json so the freeze survives
# REMEDIATE-04 uninstall+reinstall (CAT-04).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "qwen-code: installing @qwen-code/qwen-code@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@qwen-code/qwen-code@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v qwen || true)
if [[ -z "$bin_path" ]]; then
  echo "qwen-code install: qwen not on PATH after install" >&2
  exit 1
fi

# `qwen --version` prints the bare version (e.g. "0.19.2").
version_line=$(qwen --version 2>&1 | head -1)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'qwen-code install: pinned=%s but `qwen --version`: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$version_line" >&2
  exit 1
fi

# ENABLE-08: freeze qwen-code's passive background self-update (see header).
# Idempotent deep-merge via node (the provisioned runtime — no jq dependency):
# set general.enableAutoUpdate=false while preserving every other top-level key
# AND every other general.* key. Atomic same-dir tmp+rename; a pre-existing
# non-JSON settings file is left untouched (warn, do not clobber). Path is
# passed via the environment, never interpolated into the script body.
freeze_autoupdate() {
  local config_dir="${AGENTLINUX_AGENT_HOME}/.qwen"
  local config_file="${config_dir}/settings.json"
  mkdir -p "$config_dir"
  AGENTLINUX_QWEN_SETTINGS="$config_file" node <<'NODE'
const fs = require('fs');
const file = process.env.AGENTLINUX_QWEN_SETTINGS;
let cfg = {};
let mode = 0o600; // settings.json may reference cached creds — default tight
if (fs.existsSync(file)) {
  try {
    cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    // Omit the parse error text: a malformed settings file may hold cached
    // creds, and V8's SyntaxError embeds the offending input's leading bytes —
    // which would spill into the install transcript. The path is enough.
    console.error(`qwen-code: existing ${file} is not valid JSON; leaving untouched — autoupdate NOT frozen`);
    process.exit(0);
  }
  if (typeof cfg !== 'object' || cfg === null || Array.isArray(cfg)) {
    console.error(`qwen-code: existing ${file} is not a JSON object; leaving untouched — autoupdate NOT frozen`);
    process.exit(0);
  }
  mode = fs.statSync(file).mode & 0o777; // preserve the user's original mode
}
if (typeof cfg.general !== 'object' || cfg.general === null || Array.isArray(cfg.general)) {
  cfg.general = {};
}
if (cfg.general.enableAutoUpdate === false) {
  console.log(`qwen-code: passive autoupdate already disabled in ${file}`);
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
console.log(`qwen-code: disabled passive autoupdate in ${file}`);
NODE
}

# freeze_autoupdate logs its own authoritative outcome; the completion line
# below does not restate it, so a malformed-config skip is never misreported.
freeze_autoupdate

echo "qwen-code: install complete (resolves at ${bin_path}; version matches pin)"
