#!/usr/bin/env bash
set -euo pipefail
# gsd install.sh — official Open GSD distribution (WIRE-01 + Codex support).
# The catalog keeps the user-facing id `gsd`; the package-native command is
# `gsd-core`. No alias or /usr/local shim is created.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

pkg='@opengsd/gsd-core'
bin='gsd-core'
legacy_pkg='get-shit-done-cc'
if npm list -g --depth=0 "$legacy_pkg" >/dev/null 2>&1; then
  echo "gsd: removing legacy ${legacy_pkg} package before Open GSD migration"
  npm uninstall -g --no-fund --no-audit "$legacy_pkg"
fi
echo "gsd: installing ${pkg}@${AGENTLINUX_PINNED_VERSION}"
npm install -g --omit=dev --no-fund --no-audit "${pkg}@${AGENTLINUX_PINNED_VERSION}"

# Resolve the npm-managed bin directory from the same prefix npm just used.
# This keeps the recipe correct in the normal /home/agent prefix and in the
# harness's isolated NPM_CONFIG_PREFIX, without creating a compatibility shim.
npm_global_bin="$(npm prefix -g)/bin"
export PATH="${npm_global_bin}:${PATH}"

bin_path=$(command -v "$bin" || true)
if [[ -z "$bin_path" ]]; then
  echo "gsd install: ${bin} not on PATH after install" >&2
  exit 1
fi
package_root=$(npm root -g)
package_json="${package_root}/${pkg}/package.json"
version_line=$(node -p 'require(process.argv[1]).version' "$package_json" 2>/dev/null || true)
if ! printf '%s' "$version_line" | grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"; then
  printf 'gsd install: pinned=%s but installed package version: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "${version_line:-<unreadable>}" >&2
  exit 1
fi

echo "gsd: wiring Open GSD into Claude Code, OpenCode, Codex, and Qwen"
"$bin" --global --claude --opencode --codex --qwen \
  || echo "gsd install: Open GSD bootstrapper returned non-zero; verifying surfaces" >&2
echo "gsd: Antigravity CLI wiring is not currently provided by upstream; use its migration/import flow manually if needed"

assert_wired() {
  local label=$1 root=$2 name=$3 type=$4
  if ! find "$root" -maxdepth 2 -type "$type" -name "$name" -print -quit 2>/dev/null | grep -q .; then
    printf 'gsd install: no Open GSD content for %s under %s\n' "$label" "$root" >&2
    exit 1
  fi
  echo "gsd: wired into ${label} (${root})"
}

assert_wired 'Claude Code' "${AGENTLINUX_AGENT_HOME}/.claude/skills" 'gsd-*' d
assert_wired 'OpenCode' "${AGENTLINUX_AGENT_HOME}/.config/opencode/skills" 'gsd-*' d
assert_wired 'Codex' "${AGENTLINUX_AGENT_HOME}/.agents/skills" 'gsd-*' d
assert_wired 'Qwen Code' "${AGENTLINUX_AGENT_HOME}/.qwen/skills" 'gsd-*' d
echo "gsd: install complete (resolves at ${bin_path}; version matches pin; Codex wiring enabled)"
