#!/usr/bin/env bats
# Phase 51 Open GSD migration and Codex integration regression coverage.

load 'helpers/assertions'

SOURCE_ROOT=${AGENTLINUX_SOURCE_ROOT:-/opt/agentlinux-src}
CATALOG=${AGENTLINUX_CATALOG:-/opt/agentlinux/catalog/$(jq -r .version "$SOURCE_ROOT/plugin/catalog/catalog.json")/catalog.json}
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

# The canonical-path map used to be "covered" here by
# `grep -Ern 'gsd-core' main.rs detect_gates.rs reuse.rs; assert_exit_zero` —
# which grep satisfies from a match in ANY of the three files, and the only
# occurrences in the two gate modules are #[cfg(test)] constants. The map could
# have been deleted from both and it stayed green. It now lives where it can be
# asserted: `canonical_path_map_pins_each_id` (rust/crates/agentlinux/src/main.rs)
# pins the map, and `gsd_system_version_path_reuses` (agentlinux-core/src/reuse.rs)
# covers the decision that path drives.

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
