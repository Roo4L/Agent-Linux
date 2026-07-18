#!/usr/bin/env bats
# tests/bats/69-catalog-growth-kit.bats — v0.3.6 Phase 49 (catalog growth kit): ENABLE-06
# (`agentlinux list --by-category` groups the catalog by category) + ENABLE-07 (a contributor
# recipe template + rubric doc let a new entry be added with ZERO CLI TypeScript edits — the
# CAT-03 contract, proven end-to-end by installing a template-instantiated entry).
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - installs run as the agent user through a login shell
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json
SRC=/opt/agentlinux-src

setup_file() {
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
}

# Unconditional cleanup after every @test — runs even when an assertion aborts mid-test, so
# the ENABLE-07 template demo (temp catalog + its contained state + marker) never leaks into
# a reused container. The install-sentinel lives under $demo/state (temp), so nothing lands
# in the default state dir; this also sweeps any legacy default-state leak defensively.
teardown() {
  rm -rf /tmp/gk-demo-catalog /tmp/agentlinux-gk-demo.marker 2>/dev/null || true
  find /opt/agentlinux/state /home/agent/.local/state -name 'growthkit-demo.json' -delete 2>/dev/null || true
}

@test "ENABLE-06: agentlinux list --by-category groups every catalog entry under its category header" {
  run sudo -u agent -H bash --login -c 'agentlinux list --by-category'
  assert_exit_zero "ENABLE-06 (list --by-category)"

  # All five milestone category headers render (## <label>).
  for header in "## Coding agents" "## MCP servers" "## DevOps & security" "## Token & workflow" "## AI assistants"; do
    if ! printf '%s' "${output}" | grep -qF -- "$header"; then
      __fail "ENABLE-06" "grouped list contains header '${header}'" "${output:-<empty>}" "$LOG"
    fi
  done

  # Headers render in the canonical display order. Pin ABSOLUTE per-header line numbers
  # (Coding < AI < MCP < DevOps < Token) — not a re-sort of the already-rendered order, which
  # would be tautological and would not catch a category-order swap in category.ts.
  local _o
  _o() { printf '%s\n' "${output}" | grep -n "^## $1\$" | head -1 | cut -d: -f1; }
  local ca as mc dv wf
  ca=$(_o "Coding agents"); as=$(_o "AI assistants"); mc=$(_o "MCP servers")
  dv=$(_o "DevOps & security"); wf=$(_o "Token & workflow")
  if ! [[ -n "$ca" && -n "$as" && -n "$mc" && -n "$dv" && -n "$wf" &&
    "$ca" -lt "$as" && "$as" -lt "$mc" && "$mc" -lt "$dv" && "$dv" -lt "$wf" ]]; then
    __fail "ENABLE-06" "headers in canonical order Coding<AI<MCP<DevOps<Token" "ca=$ca as=$as mc=$mc dv=$dv wf=$wf" "$LOG"
  fi

  # Every non-test catalog entry appears in the grouped view (no entry dropped by grouping).
  local id
  while read -r id; do
    if ! printf '%s\n' "${output}" | grep -qE "^${id}([[:space:]]|\$)"; then
      __fail "ENABLE-06" "entry '${id}' appears in the grouped list" "missing from --by-category output" "$LOG"
    fi
  done < <(jq -r '.agents[] | select(.test_only != true) | .id' "$CATALOG")

  # Placement: hermes-agent + openclaw fall STRICTLY BETWEEN the AI-assistants header and the
  # next category header — proving they group there, not merely "somewhere after". (AI
  # assistants is the 2nd group, order 2 — not the last; Browser & automation is last.)
  local ai_next demo_line
  ai_next=$(printf '%s\n' "${output}" | grep -n '^## ' | awk -F: -v a="$as" '$1>a{print $1; exit}')
  for demo in hermes-agent openclaw; do
    demo_line=$(printf '%s\n' "${output}" | grep -n "^${demo}" | head -1 | cut -d: -f1)
    if [[ -z "$demo_line" || "$demo_line" -le "$as" || ( -n "$ai_next" && "$demo_line" -ge "$ai_next" ) ]]; then
      __fail "ENABLE-06" "${demo} grouped under AI assistants (between its header and the next)" "as=$as ${demo}=$demo_line next=$ai_next" "$LOG"
    fi
  done
}

@test "ENABLE-06: the flat default list is unchanged (first line is the NAME header — no grouping)" {
  # Backward-compat guard: `list` without --by-category keeps the flat table (grep-the-table
  # tooling and existing tests depend on the header being the first line).
  run sudo -u agent -H bash --login -c 'agentlinux list | head -1'
  assert_exit_zero "ENABLE-06 (flat default)"
  if ! printf '%s' "${output}" | grep -qE '^NAME[[:space:]]+STATUS[[:space:]]+CURATED'; then
    __fail "ENABLE-06" "flat list first line is the NAME/STATUS/CURATED header" "${output:-<empty>}" "$LOG"
  fi
}

@test "ENABLE-07: the contributor template + rubric doc are published and valid" {
  # This is a repo-CONTENT check (published docs + template recipes), not a runtime-install
  # check. `plugin/` (hence _template/) ships in the release tarball, but `docs/` does not,
  # and the QEMU tests tarball carries only tests/bats + packaging — so the published docs are
  # absent in-guest. Skip there; the assertion is meaningful under Docker (full-repo copy) +
  # pre-commit, and QEMU covers the runtime ENABLE-06/07 behavior (grouping + the
  # template-only-add round trip) in the sibling @tests.
  #
  # Gate on tests/docker/run.sh — a full-repo-only sentinel that QEMU never stages. Do NOT gate
  # on "$SRC/docs" existing: the release-gate test 52 (capture_transcript_to) mkdir's a RELATIVE
  # docs/audits/… path while bats' CWD is /opt/agentlinux-src, so a stray $SRC/docs appears
  # in-guest whenever that CDN-gated test runs — an unreliable, order-dependent sentinel.
  [[ -f "${SRC}/tests/docker/run.sh" ]] ||
    skip "full repo not staged in-guest (QEMU ships only tests/bats + packaging; this published-artifacts check runs under Docker/pre-commit)"

  # The growth-kit deliverables exist.
  run test -f "${SRC}/docs/CATALOG-CONTRIBUTING.md"
  [[ "${status}" -eq 0 ]] || __fail "ENABLE-07" "docs/CATALOG-CONTRIBUTING.md published" "missing" "$LOG"
  run test -f "${SRC}/plugin/catalog/agents/_template/install.sh"
  [[ "${status}" -eq 0 ]] || __fail "ENABLE-07" "_template/install.sh published" "missing" "$LOG"
  run test -f "${SRC}/plugin/catalog/agents/_template/uninstall.sh"
  [[ "${status}" -eq 0 ]] || __fail "ENABLE-07" "_template/uninstall.sh published" "missing" "$LOG"

  # The template recipes are shellcheck-clean (a contributor copies working skeletons).
  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck --severity=warning "${SRC}/plugin/catalog/agents/_template/install.sh" "${SRC}/plugin/catalog/agents/_template/uninstall.sh"
    assert_exit_zero "ENABLE-07 (template shellcheck-clean)"
  fi

  # The rubric doc's category table is in lockstep with the CLI's category keys.
  for cat in "Coding agents" "AI assistants" "MCP servers" "Token & workflow" "DevOps & security"; do
    if ! grep -qF -- "$cat" "${SRC}/docs/CATALOG-CONTRIBUTING.md"; then
      __fail "ENABLE-07" "rubric doc documents category '${cat}'" "absent from CATALOG-CONTRIBUTING.md" "$LOG"
    fi
  done
}

@test "ENABLE-07: a template-instantiated entry installs + removes with ZERO CLI edits (CAT-03)" {
  # Criterion: a new entry added via the template alone (catalog entry + recipe pair, no
  # TypeScript) installs and removes through the generic CLI dispatch. Stage a temp catalog
  # (created here at the bats level, world-readable) and point the CLI at it via the
  # AGENTLINUX_CATALOG_DIR seam — the agent user runs install/remove against it unchanged.
  local demo=/tmp/gk-demo-catalog
  local marker=/tmp/agentlinux-gk-demo.marker
  rm -rf "$demo" "$marker"
  # A dedicated state dir keeps the demo's install-sentinel contained in the temp tree, so a
  # mid-test failure cannot leak a phantom entry into the default state dir (teardown() also
  # cleans up unconditionally).
  mkdir -p "$demo/agents/growthkit-demo" "$demo/state"

  # A filled copy of the template recipe pair (marker-based, offline — the shape a
  # contributor produces; the point is the CLI needs NO code change to run it).
  cat >"$demo/agents/growthkit-demo/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${AGENTLINUX_PINNED_VERSION:?}"
printf 'version=%s\n' "$AGENTLINUX_PINNED_VERSION" >/tmp/agentlinux-gk-demo.marker
echo "growthkit-demo: installed"
EOF
  cat >"$demo/agents/growthkit-demo/uninstall.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
rm -f /tmp/agentlinux-gk-demo.marker
echo "growthkit-demo: removed"
EOF
  cat >"$demo/catalog.json" <<'EOF'
{ "version": "0.3.4", "agents": [ {
  "id": "growthkit-demo",
  "display_name": "Growth Kit Demo",
  "description": "Template-instantiated entry proving the zero-CLI-edit add path.",
  "license": "MIT",
  "source_kind": "script",
  "pinned_version": "1.2.3",
  "install_recipe_path": "install.sh",
  "uninstall_recipe_path": "uninstall.sh",
  "tags": ["workflow"]
} ] }
EOF
  chmod -R a+rX "$demo"
  chmod a+rwX "$demo/state" # the agent user writes its install-sentinel here

  # Install through the CLI pointed at the temp catalog — no TypeScript was touched.
  run sudo -u agent -H bash --login -c 'export AGENTLINUX_CATALOG_DIR='"$demo"'; export AGENTLINUX_STATE_DIR='"$demo"'/state; agentlinux install growthkit-demo'
  assert_exit_zero "ENABLE-07 (template-only install)"
  assert_no_eacces "ENABLE-07 (template-only install)" "$output"

  run sudo -u agent -H bash --login -c 'cat '"$marker"' 2>/dev/null'
  if [[ "${output}" != "version=1.2.3" ]]; then
    __fail "ENABLE-07" "template entry installed at its pinned version (marker=version=1.2.3)" "${output:-<gone>}" "$LOG"
  fi

  # It also groups correctly (workflow tag → Token & workflow) via the same derivation.
  run sudo -u agent -H bash --login -c 'export AGENTLINUX_CATALOG_DIR='"$demo"'; export AGENTLINUX_STATE_DIR='"$demo"'/state; agentlinux list --by-category'
  if ! printf '%s' "${output}" | grep -qF -- "## Token & workflow"; then
    __fail "ENABLE-07" "template entry groups under Token & workflow via its tag" "${output:-<empty>}" "$LOG"
  fi

  # Symmetric remove through the same generic dispatch.
  run sudo -u agent -H bash --login -c 'export AGENTLINUX_CATALOG_DIR='"$demo"'; export AGENTLINUX_STATE_DIR='"$demo"'/state; agentlinux remove --force growthkit-demo'
  assert_exit_zero "ENABLE-07 (template-only remove)"
  run sudo -u agent -H bash --login -c 'test -e '"$marker"
  [[ "${status}" -ne 0 ]] || __fail "ENABLE-07" "template entry removed its marker" "${marker} still exists" "$LOG"

  rm -rf "$demo" "$marker"
}
