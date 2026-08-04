#!/usr/bin/env bats
# Phase 51 prerequisite regression coverage. These are static contract tests;
# the live apt/dnf and browser launch checks run in the catalog QA environment.

load 'helpers/assertions'

SOURCE_ROOT=${AGENTLINUX_SOURCE_ROOT:-/opt/agentlinux-src}
LOG=/var/log/agentlinux-install.log

@test "K-002: browser prerequisite helper is strict, distro-aware, and agent-first" {
  local helper="$SOURCE_ROOT/plugin/catalog/lib/browser-deps.sh"
  run bash -n "$helper"
  assert_exit_zero "K-002/helper-syntax"
  run grep -En 'apt-get|dnf|sudo -n|al_browser_family|al_browser_ensure_playwright_libs' "$helper"
  assert_exit_zero "K-002/package-manager-dispatch"
  run grep -En 'sudo[[:space:]]+npm|/usr/local/bin' "$helper" "$SOURCE_ROOT/plugin/catalog/agents/playwright-cli/install.sh"
  [[ "$status" -ne 0 ]] || \
    __fail "K-002/no-root-npm" "browser prerequisites never use root npm or /usr/local shims" "$output" "$LOG"
}

@test "B-001: Spec Kit repairs a missing git prerequisite through the shared helper" {
  run grep -En 'browser-deps\.sh|al_browser_ensure_git' \
    "$SOURCE_ROOT/plugin/catalog/agents/spec-kit/install.sh"
  assert_exit_zero "B-001/git-repair"
}

@test "B-002: Chrome DevTools recipe repairs the canonical system Chrome prerequisite" {
  run grep -En 'browser-deps\.sh|al_browser_ensure_chrome|/opt/google/chrome/chrome' \
    "$SOURCE_ROOT/plugin/catalog/agents/chrome-devtools-mcp/install.sh" \
    "$SOURCE_ROOT/plugin/catalog/lib/browser-deps.sh"
  assert_exit_zero "B-002/chrome-repair"
}

@test "OPS-01: Playwright recipe performs a real browser launch probe and reports failure" {
  run grep -En 'al_browser_ensure_chrome|playwright-cli open about:blank|browser launch probe failed|timeout 90' \
    "$SOURCE_ROOT/plugin/catalog/agents/playwright-cli/install.sh"
  assert_exit_zero "OPS-01/browser-probe"
}

@test "OPS-01: Playwright status adapter changes only the structured action error to nonzero" {
  local prefix fake_cli wrapper
  run grep -En 'status-wrapper\.js|install -m 0755' \
    "$SOURCE_ROOT/plugin/catalog/agents/playwright-cli/install.sh"
  assert_exit_zero "OPS-01/adapter-installed"
  prefix=$(mktemp -d)
  fake_cli="$prefix/lib/node_modules/@playwright/cli/playwright-cli.js"
  wrapper="$prefix/bin/playwright-cli"
  mkdir -p "$(dirname "$fake_cli")" "$(dirname "$wrapper")"
  cp "$SOURCE_ROOT/plugin/catalog/agents/playwright-cli/status-wrapper.js" "$wrapper"
  chmod 0755 "$wrapper"
  printf '%s\n' \
    '#!/usr/bin/env node' \
    'if (process.argv.includes("--bad")) { console.log("### Error"); console.log("Error: target missing"); }' \
    'else if (process.argv.includes("--json-bad")) { console.log(JSON.stringify({ isError: true, error: "Error: target missing" })); }' \
    'else { console.log("page text: ### Error"); console.log("Error: not an envelope"); }' \
    > "$fake_cli"
  chmod 0755 "$fake_cli"

  run "$wrapper" --good
  assert_exit_zero "OPS-01/adapter-valid-output"

  run "$wrapper" --bad
  [[ "$status" -ne 0 ]] || \
    __fail "OPS-01" "structured action error returns nonzero" "$output" "$LOG"
  if ! printf '%s' "$output" | grep -qF 'target missing'; then
    __fail "OPS-01" "structured action error remains human-readable" "$output" "$LOG"
  fi

  run "$wrapper" --json-bad
  [[ "$status" -ne 0 ]] || \
    __fail "OPS-01" "JSON action error returns nonzero" "$output" "$LOG"
}
