#!/usr/bin/env bats
# Phase 51 Open GSD migration and Codex integration regression coverage.

load 'helpers/assertions'

SOURCE_ROOT=${AGENTLINUX_SOURCE_ROOT:-/opt/agentlinux-src}
CATALOG=${AGENTLINUX_CATALOG:-/opt/agentlinux/catalog/$(jq -r .version "$SOURCE_ROOT/plugin/cli/package.json")/catalog.json}
LOG=/var/log/agentlinux-install.log

@test "AGT-04: catalog pins the Open GSD package and its package-native command" {
  run jq -r '.agents[] | select(.id=="gsd") | [.npm_package_name, .pinned_version, .homepage] | @tsv' "$CATALOG"
  assert_exit_zero "AGT-04/catalog"
  [[ "$output" == $'@opengsd/gsd-core\t1.7.0\thttps://github.com/open-gsd/gsd-core' ]] || \
    __fail "AGT-04/catalog" "Open GSD 1.7.0 catalog identity" "${output:-<empty>}" "$LOG"
  run grep -En 'npm install -g|@opengsd/gsd-core|installed package version|--codex|\.agents/skills' \
    "$SOURCE_ROOT/plugin/catalog/agents/gsd/install.sh"
  assert_exit_zero "AGT-04/recipe"
}

@test "AGT-04: Open GSD install and uninstall cover Codex without a /usr/local shim" {
  local install="$SOURCE_ROOT/plugin/catalog/agents/gsd/install.sh"
  local uninstall="$SOURCE_ROOT/plugin/catalog/agents/gsd/uninstall.sh"
  run grep -En -- '--claude|--opencode|--codex|--qwen|Antigravity CLI wiring is not currently provided' "$install" "$uninstall"
  assert_exit_zero "AGT-04/symmetric-runtimes"
  run grep -En '^[^#]*(/usr/local|sudo[[:space:]]+npm[[:space:]]+install[[:space:]]+-g|npm_package_name.*get-shit-done-cc)' "$install" "$uninstall"
  [[ "$status" -ne 0 ]] || \
    __fail "AGT-04/no-shim" "Open GSD recipe has no legacy package or /usr/local shim" "$output" "$LOG"
}

@test "AGT-04: detection, reuse, and Node remediation identify gsd-core as canonical" {
  run grep -En 'gsd-core|@opengsd/gsd-core' \
    "$SOURCE_ROOT/plugin/cli/src/detect.ts" \
    "$SOURCE_ROOT/plugin/lib/detect/agents.sh" \
    "$SOURCE_ROOT/plugin/lib/reuse/agents.sh" \
    "$SOURCE_ROOT/plugin/lib/remediate/nodejs.sh"
  assert_exit_zero "AGT-04/canonical-surfaces"
}

@test "AGT-04: GSD removal preserves Open GSD user-owned dev-preferences" {
  local home
  home=$(mktemp -d)
  mkdir -p "$home/.agents/skills/gsd-dev-preferences" "$home/.agents/skills/gsd-other"
  printf 'user-owned\n' >"$home/.agents/skills/gsd-dev-preferences/SKILL.md"
  printf 'managed\n' >"$home/.agents/skills/gsd-other/SKILL.md"

  run env \
    AGENTLINUX_AGENT_HOME="$home" \
    AGENTLINUX_PRESERVE_PATHS= \
    NPM_CONFIG_PREFIX="$home/.npm-global" \
    PATH="$home/.npm-global/bin:/usr/bin:/bin" \
    bash "$SOURCE_ROOT/plugin/catalog/agents/gsd/uninstall.sh"
  assert_exit_zero "AGT-04/user-owned-preferences"
  [[ -f "$home/.agents/skills/gsd-dev-preferences/SKILL.md" ]] || \
    __fail "AGT-04/user-owned-preferences" "Open GSD dev-preferences survives remove" "missing" "$LOG"
  [[ ! -e "$home/.agents/skills/gsd-other" ]] || \
    __fail "AGT-04/user-owned-preferences" "managed GSD skill is removed" "still present" "$LOG"
  rm -rf "$home"
}
