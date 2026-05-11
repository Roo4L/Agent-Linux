#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/agents.sh — DET-04 catalog agent discovery probe.
#
# Sourced (transitively) by plugin/bin/agentlinux-install via plugin/lib/detect.sh.
# Inherits `set -euo pipefail`, the ERR trap, and the log.sh / as_user.sh
# dependencies from the entrypoint. MUST NOT set its own strict-mode flags.
# Uses `return 1` (not `exit 1`) on any error path — sourced fragment.
#
# Catalog binary mapping (LOCKED — verbatim from plugin/catalog/catalog.json
# + plugin/catalog/agents/*/install.sh; NOT REQUIREMENTS.md prose):
#   claude-code     → claude
#   gsd             → get-shit-done-cc
#   playwright-cli  → playwright-cli
# `test-dummy` is `test_only: true` in catalog.json — explicitly EXCLUDED.
#
# Classification (RESEARCH §Pattern 4):
#   absent  — `as_user agent command -v <binary>` exits non-zero.
#   healthy — binary present + version probe parses something + `--help` exit 0.
#   broken  — binary present BUT (version probe yields empty OR `--help` non-zero).
#
# READ-ONLY contract: never any package-manager mutation, never any write to
# /etc /home /usr/local/bin /opt. Probed binary stdout is NEVER passed to a
# shell evaluator, NEVER passed to source, NEVER passed unquoted to any shell
# — only into jq via --arg (T-12-02 mitigation).
#
# Source-once guard.
[[ -n "${AGENTLINUX_DETECT_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# DETECT_AGENT_BINARIES — catalog ID → binary-on-PATH name.
# Verbatim from plugin/catalog/agents/*/install.sh (NOT REQUIREMENTS.md prose:
# `playwright` was renamed to `playwright-cli` in the Plan 12-01 amendment).
declare -A DETECT_AGENT_BINARIES=(
  [claude-code]=claude
  [gsd]=get-shit-done-cc
  [playwright-cli]=playwright-cli
)

# __det_agent_version_probe <id> <user> <binary>
#
# Emits the version string for the given agent on stdout (or empty string when
# unparseable). Per-agent shape:
#   claude-code    — `claude --version` → semver line ("1.2.3" / "1.2.3 (xyz)").
#   gsd            — `get-shit-done-cc --help | head -1` (no --version flag
#                    exists; banner-grep mode per RESEARCH §Pattern 4).
#   playwright-cli — `playwright-cli --version` → semver line.
#
# Version regex `[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?` is the T-12-02
# mitigation: a malicious binary that tries to inject shell metacharacters or
# ANSI escapes into the version string yields empty (no regex match), which
# the classifier maps to `broken` rather than embedding adversarial bytes
# verbatim into the report. The gsd path is more permissive (banner head -1)
# because gsd has no --version flag; jq --arg still quotes the bytes safely
# so JSON shape is preserved even with adversarial input.
__det_agent_version_probe() {
  local id=$1 user=$2 binary=$3
  case "$id" in
    claude-code)
      as_user "$user" "$binary" --version 2>/dev/null \
        | head -1 \
        | tr -d '\r' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1
      ;;
    gsd)
      as_user "$user" "$binary" --help 2>/dev/null \
        | head -1 \
        | tr -d '\r' \
        | tr -d '\n'
      ;;
    playwright-cli)
      as_user "$user" "$binary" --version 2>/dev/null \
        | head -1 \
        | tr -d '\r' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1
      ;;
  esac
}

# detect::agents_probe <user> <fragment_path>
#
# Iterates the LOCKED catalog binary mapping (test-dummy excluded — its
# `test_only: true` flag means "not a real agent"). For each agent: resolve
# binary on the install user's PATH (Pitfall 4 — must probe AS the user, not
# as root); capture version + ownership; run --help health probe; classify.
# Emits {agents: [...]} fragment + per-agent DETECT_AGENT_<UPPER>_* exports
# (the Phase 13 reader detect::agent_status reads them by name).
detect::agents_probe() {
  local user=$1 fragment_path=$2
  local entries=()

  # Iterate via an explicit ordered list (NOT bash's hash-bucket-order
  # iteration of the associative array) for determinism in renderer output.
  local ids=(claude-code gsd playwright-cli)
  local id binary bin_path ver health_rc owner status upper

  for id in "${ids[@]}"; do
    binary=${DETECT_AGENT_BINARIES[$id]}

    # Pitfall 4: `command -v` AS THE INSTALL USER. Root sees a different PATH
    # (sudo's secure_path); only the install user's PATH is the source of
    # truth for what Phase 13 will see when it invokes the agent.
    bin_path=$(as_user "$user" command -v "$binary" 2>/dev/null || true)

    if [[ -z "$bin_path" ]]; then
      status=absent
      ver=""
      owner=""
    else
      ver=$(__det_agent_version_probe "$id" "$user" "$binary")
      owner=$(stat -c '%U:%G' "$bin_path" 2>/dev/null || echo "unknown")

      # Health probe — independent from version. `--help` should always exit 0
      # for healthy CLIs; failures = broken. Capture the rc explicitly so
      # set -e in the entrypoint doesn't trip on a non-zero exit here.
      if as_user "$user" "$binary" --help >/dev/null 2>&1; then
        health_rc=0
      else
        health_rc=$?
      fi

      if [[ "$health_rc" -eq 0 && -n "$ver" ]]; then
        status=healthy
      else
        status=broken
      fi
    fi

    # JSON entry via jq --arg exclusively (T-12-02 mitigation). Probed binary
    # stdout flows into jq's --arg quoter — never into a shell.
    entries+=("$(jq -n \
      --arg id "$id" \
      --arg binary "$binary" \
      --arg path "$bin_path" \
      --arg version "$ver" \
      --arg owner "$owner" \
      --arg status "$status" \
      '{id: $id, binary: $binary, path: $path, version: $version, owner: $owner, status: $status}')")

    # Per-agent reader exports (Phase 13 consumes via detect::agent_status).
    # ${id^^} uppercases; ${var//-/_} replaces hyphens with underscores so
    # `claude-code` → `CLAUDE_CODE`. Same idiom in the reader below.
    upper=${id^^}
    upper=${upper//-/_}
    export "DETECT_AGENT_${upper}_STATUS"="$status"
    export "DETECT_AGENT_${upper}_PATH"="$bin_path"
    export "DETECT_AGENT_${upper}_VERSION"="$ver"
    export "DETECT_AGENT_${upper}_OWNER"="$owner"
  done

  printf '%s\n' "${entries[@]}" | jq -s '{agents: .}' >"$fragment_path"
  export DETECT_AGENTS_SECTION_STATUS=present
  export DETECT_AGENTS_COUNT=${#entries[@]}
}

# --- Phase 13 reader functions (CONTEXT.md "Phase 12 → Phase 13 contract") ---
#
# detect::agent_status <id> — return one of {healthy, broken, absent} for the
# given catalog ID. Reads the DETECT_AGENT_<UPPER>_STATUS export populated
# by detect::agents_probe; defaults to `absent` when the export is unset
# (the agent wasn't probed, e.g. a future catalog ID not in the locked list).
detect::agent_status() {
  local id=${1:-}
  local upper=${id^^}
  upper=${upper//-/_}
  local var="DETECT_AGENT_${upper}_STATUS"
  printf '%s' "${!var:-absent}"
}
