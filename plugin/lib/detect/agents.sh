#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/agents.sh — DET-04 catalog agent discovery probe.
#
# Sourced fragment: inherits set -euo pipefail / ERR trap / log.sh / as_user.sh
# and uses `return 1` (not `exit 1`).
#
# Catalog binary mapping (verbatim from catalog.json + agents/*/install.sh;
# test-dummy is test_only and excluded):
#   claude-code     → claude
#   gsd             → gsd-core
#   playwright-cli  → playwright-cli
#
# Classification:
#   absent  — `command -v <binary>` (as the user) exits non-zero.
#   healthy — binary present + version parses + `--help` exit 0.
#   broken  — binary present but version empty OR `--help` non-zero.
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

# DETECT_AGENT_BINARIES — catalog ID → binary-on-PATH name.
declare -A DETECT_AGENT_BINARIES=(
  [claude-code]=claude
  [gsd]=gsd-core
  [playwright-cli]=playwright-cli
)

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
      as_user_login "$user" "$binary" --version 2>/dev/null \
        | head -1 \
        | tr -d '\r' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1
      ;;
    gsd)
      as_user_login "$user" "$binary" --help 2>/dev/null \
        | tr -d '\r' \
        | grep -Eo '[vV]?[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1 \
        | tr -d 'vV'
      ;;
    playwright-cli)
      as_user_login "$user" "$binary" --version 2>/dev/null \
        | head -1 \
        | tr -d '\r' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?' \
        | head -1
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

  # Explicit ordered list (not the associative array's hash-bucket order) for
  # deterministic renderer output.
  local ids=(claude-code gsd playwright-cli)
  local id binary bin_path ver health_rc owner status upper

  for id in "${ids[@]}"; do
    binary=${DETECT_AGENT_BINARIES[$id]}

    # Resolve as the install user via login shell so the agent-owned PATH
    # entries are present; see the header for why bare as_user misclassifies.
    bin_path=$(as_user_login "$user" command -v "$binary" 2>/dev/null || true)

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

      # Health probe, independent of version: `--help` should exit 0 for a
      # healthy CLI. Capture the rc explicitly so the entrypoint's set -e
      # doesn't trip on a non-zero exit.
      if as_user_login "$user" "$binary" --help >/dev/null 2>&1; then
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
  done

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
