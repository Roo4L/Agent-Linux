#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/agents.sh — DET-04 catalog agent discovery probe.
#
# Sourced fragment: inherits set -euo pipefail / ERR trap / log.sh / as_user.sh
# and uses `return 1` (not `exit 1`).
#
# Catalog binary mapping is DERIVED from the catalog at probe time (see
# __det_agent_rows): every non-mcp, non-test entry whose post_install_verify
# begins `command -v <bin>` is probed on PATH — so the whole catalog is detected,
# not just the original three. MCP entries register into client configs (no PATH
# binary) and are excluded. A malformed/absent catalog degrades to the legacy
# three (claude-code→claude, gsd→gsd-core, playwright-cli→playwright-cli).
#
# Classification:
#   absent  — `command -v <binary>` (as the user) exits non-zero.
#   healthy — binary present + version parses (the original three additionally
#             require `--help` exit 0, preserving their prior contract).
#   broken  — binary present but version unparseable (or, for the original
#             three, `--help` non-zero).
#
# GSD is the exception: its binary is a bootstrapper, so when it's absent gsd is
# also classified from the deployed-system VERSION file (see the fallback branch
# in detect::agents_probe for the full rationale + the symlink-ownership gate).
#
# PATH-resolving probes go through as_user_login (login shell) rather than bare
# as_user: bare as_user uses sudo's secure_path, which omits the agent-owned
# PATH entries (~/.local/bin, ~/.npm-global/bin), so an installed agent would
# misclassify as absent. as_user_login sources /etc/profile.d/agentlinux.sh.
#
# Read-only: no package mutation, no writes. Probed binary stdout reaches jq
# only via --arg — never a shell evaluator.
[[ -n "${AGENTLINUX_DETECT_AGENTS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_AGENTS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/agents.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# The original three carry bespoke version-probe logic (see
# __det_agent_version_probe); every other tool uses the generic probe. Listed
# here so the loop can branch health/version handling without re-hardcoding IDs.
readonly DETECT_AGENT_LEGACY_IDS=" claude-code gsd playwright-cli "

# The legacy id<TAB>binary rows, used verbatim when the catalog is unreadable so a
# malformed/absent catalog degrades to prior behavior rather than reporting none.
readonly DETECT_AGENT_LEGACY_ROWS=$'claude-code\tclaude\ngsd\tgsd-core\nplaywright-cli\tplaywright-cli'

# __det_catalog_path — resolve the catalog.json the probe derives its tool list
# from. Override with AGENTLINUX_CATALOG (test seam); otherwise the source copy
# shipped alongside this lib in the extracted plugin tree. Both provision-time
# and install-time callers see the same file.
__det_catalog_path() {
  if [[ -n "${AGENTLINUX_CATALOG:-}" ]]; then
    printf '%s' "$AGENTLINUX_CATALOG"
    return 0
  fi
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../catalog" 2>/dev/null && pwd)/catalog.json"
}

# __det_agent_rows <catalog> — emit `id<TAB>binary` for every PATH-resolvable
# catalog tool: non-mcp, non-test entries whose post_install_verify begins
# `command -v <bin>` (the universal presence convention). MCP entries
# (registration-based, no PATH binary) are skipped. Falls back to the legacy
# three when the catalog is unreadable. jq is --arg-free: the catalog is trusted
# repo data and `capture` extracts only the binary token. The caller MUST consume
# these rows in a `while read` loop in the current shell (not a subshell) so its
# per-agent exports persist.
__det_agent_rows() {
  local catalog=$1
  if [[ -r "$catalog" ]]; then
    jq -r '
      .agents[]
      | select((.test_only // false) | not)
      | select(.source_kind != "mcp")
      | select((.post_install_verify // "") | test("command -v [^ ]+"))
      | [.id, ((.post_install_verify) | capture("command -v (?<b>[^ ]+)").b)]
      | @tsv
    ' "$catalog" 2>/dev/null && return 0
  fi
  printf '%s\n' "$DETECT_AGENT_LEGACY_ROWS"
}

# __det_agent_version_probe <id> <user> <binary> — emit the agent's version on
# stdout, or empty when unparseable. claude-code / playwright-cli parse a semver
# line; gsd has no --version flag, so it extracts the first semver from its
# --help banner (which begins with blank/ANSI art lines in Open GSD 1.7.0).
#
# The semver regex also hardens against a malicious binary injecting shell
# metacharacters or ANSI escapes: a non-matching version yields empty (→ broken)
# instead of embedding adversarial bytes. The gsd banner path is more permissive,
# but jq --arg still quotes the bytes safely.
__det_agent_version_probe() {
  local id=$1 user=$2 binary=$3
  case "$id" in
    claude-code)
      as_user_login "$user" "$binary" --version </dev/null 2>/dev/null \
        | head -1 \
        | tr -d '\r' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1
      ;;
    gsd)
      as_user_login "$user" "$binary" --help </dev/null 2>/dev/null \
        | tr -d '\r' \
        | grep -Eo '[vV]?[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1 \
        | tr -d 'vV'
      ;;
    playwright-cli)
      as_user_login "$user" "$binary" --version </dev/null 2>/dev/null \
        | head -1 \
        | tr -d '\r' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1
      ;;
    *)
      # Generic probe for the rest of the catalog: most CLIs print a semver on
      # `--version`; a few use a `version` subcommand (gitleaks) or only a
      # `--help` banner. Try each in turn and take the first semver. The regex
      # again neutralizes adversarial output — only digits/dots reach stdout.
      local __v __flag
      for __flag in --version version --help; do
        __v=$(as_user_login "$user" "$binary" "$__flag" </dev/null 2>/dev/null \
          | tr -d '\r' \
          | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
          | head -1)
        if [[ -n "$__v" ]]; then
          printf '%s' "$__v"
          return 0
        fi
      done
      ;;
  esac
}

# detect::agents_probe <user> <fragment_path>
#
# For each catalog agent: resolve the binary on the install user's PATH, capture
# version + ownership, run a --help health probe, and classify. Writes an
# {agents: [...]} fragment and per-agent DETECT_AGENT_<UPPER>_* exports.
detect::agents_probe() {
  local user=$1 fragment_path=$2
  local entries=()

  # Install user's home — used for GSD's deployed-system fallback below.
  local home
  home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)

  # Derive the tool list from the catalog (catalog order → deterministic
  # renderer output), one `id<TAB>binary` row per PATH-resolvable tool.
  local id binary bin_path ver health_rc owner status upper

  # `while read` from a process substitution runs the loop body in THIS shell
  # (only jq runs in the subshell), so the entries[] array and per-agent exports
  # below persist to the caller — a `for` over a subshell-populated map would not.
  while IFS=$'\t' read -r id binary; do
    [[ -n "$id" && -n "$binary" ]] || continue

    # Resolve as the install user via login shell so the agent-owned PATH
    # entries are present; see the header for why bare as_user misclassifies.
    bin_path=$(as_user_login "$user" command -v "$binary" </dev/null 2>/dev/null || true)

    # Open GSD's runtime payload lives at ~user/.claude/gsd-core and contains a
    # VERSION file plus the gsd-* skill set. When the package-native binary is
    # missing, fall back to that VERSION file as a second valid presence signal.
    # The path is reported so reuse/agents.sh + install.ts can treat it as
    # canonical.
    if [[ -z "$bin_path" && "$id" == "gsd" && -n "$home" && -f "$home/.claude/gsd-core/VERSION" ]]; then
      local gsd_ver_file="$home/.claude/gsd-core/VERSION"
      # Security: stat/read follow symlinks, so trust the VERSION file ONLY when
      # it's owned by the install user. An agent-planted symlink to a root-only
      # file (e.g. /etc/shadow) reports root here → refuse to read it as root and
      # treat gsd as absent rather than surfacing foreign bytes into the report.
      local gsd_owner
      gsd_owner=$(stat -c '%U' "$gsd_ver_file" 2>/dev/null || echo "")
      if [[ "$gsd_owner" == "$user" ]]; then
        ver=$(tr -d '[:space:]' <"$gsd_ver_file" 2>/dev/null || true)
        owner=$(stat -c '%U:%G' "$gsd_ver_file" 2>/dev/null || echo "unknown")
        bin_path="$gsd_ver_file"
        # The CLI re-checks the version against the compatibility_window before reusing.
        if [[ -n "$ver" ]]; then
          status=healthy
        else
          status=broken
        fi
      else
        status=absent
        ver=""
        owner=""
      fi
    elif [[ -z "$bin_path" ]]; then
      status=absent
      ver=""
      owner=""
    else
      ver=$(__det_agent_version_probe "$id" "$user" "$binary")
      owner=$(stat -c '%U:%G' "$bin_path" 2>/dev/null || echo "unknown")

      if [[ "$DETECT_AGENT_LEGACY_IDS" == *" $id "* ]]; then
        # Original three: keep the strict `--help`-exit-0 + version gate that
        # their behavior contract (and bats coverage) asserts. Capture the rc
        # explicitly so the entrypoint's set -e doesn't trip on a non-zero exit.
        if as_user_login "$user" "$binary" --help </dev/null >/dev/null 2>&1; then
          health_rc=0
        else
          health_rc=$?
        fi
        if [[ "$health_rc" -eq 0 && -n "$ver" ]]; then
          status=healthy
        else
          status=broken
        fi
      else
        # Generic tools: `--help` conventions vary too widely to gate on (some
        # exit non-zero, some lack it). A parseable version from the probe above
        # is the presence-and-health signal; present-but-unversionable → broken.
        if [[ -n "$ver" ]]; then
          status=healthy
        else
          status=broken
        fi
      fi
    fi

    # JSON entry via jq --arg exclusively — probed stdout never reaches a shell.
    entries+=("$(jq -n \
      --arg id "$id" \
      --arg binary "$binary" \
      --arg path "$bin_path" \
      --arg version "$ver" \
      --arg owner "$owner" \
      --arg status "$status" \
      '{id: $id, binary: $binary, path: $path, version: $version, owner: $owner, status: $status}')")

    # Per-agent reader exports. ${id^^} uppercases, ${var//-/_} swaps hyphens
    # so claude-code → CLAUDE_CODE.
    upper=${id^^}
    upper=${upper//-/_}
    export "DETECT_AGENT_${upper}_STATUS"="$status"
    export "DETECT_AGENT_${upper}_PATH"="$bin_path"
    export "DETECT_AGENT_${upper}_VERSION"="$ver"
    export "DETECT_AGENT_${upper}_OWNER"="$owner"
  done < <(__det_agent_rows "$(__det_catalog_path)")

  printf '%s\n' "${entries[@]}" | jq -s '{agents: .}' >"$fragment_path"
  export DETECT_AGENTS_SECTION_STATUS=present
  export DETECT_AGENTS_COUNT=${#entries[@]}
}

# detect::agent_status <id> — return {healthy, broken, absent} for the catalog
# ID by reading its DETECT_AGENT_<UPPER>_STATUS export; defaults to `absent`
# when the export is unset (agent not probed).
detect::agent_status() {
  local id=${1:-}
  local upper=${id^^}
  upper=${upper//-/_}
  local var="DETECT_AGENT_${upper}_STATUS"
  printf '%s' "${!var:-absent}"
}
