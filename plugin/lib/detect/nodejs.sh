#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/detect/nodejs.sh — DET-02 Node.js multi-source discovery probe.
#
# Sourced fragment: inherits set -euo pipefail / ERR trap / log.sh and uses
# `return 1` (not `exit 1`).
#
# Enumerates Node.js installations across several sources WITHOUT sourcing any
# manager's shell init. Read-only: no package mutation, no writes.
#
# Sources covered (the distro-package arm branches on AGENTLINUX_DISTRO_FAMILY):
#   1. NodeSource APT  — (debian) dpkg-query Version contains `-1nodesource` AND
#                        nodesource.{sources,list} present (dual-gate)
#   1r. NodeSource RPM — (rhel) rpm RELEASE contains `nodesource` AND a
#                        nodesource_repo_paths file present (dual-gate)
#   2. Distro APT      — (debian) dpkg-query Version present but lacks `-1nodesource`
#   2r. AppStream mod  — (rhel) rpm has nodejs but RELEASE lacks `nodesource`
#   3. Manual          — /usr/local/bin/node real file (readlink -f self)
#   4. nvm             — $HOME/.nvm/versions/node                      (depth 3)
#   5. fnm             — $HOME/.local/share/fnm/node-versions          (depth 4)
#   6. volta           — $HOME/.volta/tools/image/node                  (depth 4)
#   7. mise            — $HOME/.local/share/mise/installs/node          (depth 4)
#   8. asdf-node       — $HOME/.asdf/installs/nodejs                    (depth 4)
#   9. pnpm-managed    — $HOME/.local/share/pnpm/nodejs                 (depth 4)
[[ -n "${AGENTLINUX_DETECT_NODEJS_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_DETECT_NODEJS_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'detect/nodejs.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# __det_nodejs_entry <source> <bin_path> <version> <install_user> <prefix_root>
#
# Emits one JSON object: {source, path, version, install_user_can_write_prefix,
# prefix_root}. Strings reach jq only via --arg/--argjson. Writability is
# computed as the install user — root sees every dir as writable, so probing as
# root would always report true.
__det_nodejs_entry() {
  local source=$1 bin=$2 version=$3 user=$4 prefix_root=$5
  local writable
  if as_user "$user" test -w "$prefix_root"; then
    writable=true
  else
    writable=false
  fi
  jq -n \
    --arg source "$source" \
    --arg path "$bin" \
    --arg version "$version" \
    --arg prefix_root "$prefix_root" \
    --argjson writable "$writable" \
    '{source: $source, path: $path, version: $version, install_user_can_write_prefix: $writable, prefix_root: $prefix_root}'
}

# __det_nodejs_manager <name> <root> <maxdepth> <user> <accumulator-name>
#
# When <root> exists, find node binaries by file existence (never sourcing the
# manager's shell init). Captures `node --version` as the install user (the
# binary may need user env, e.g. HOME) and appends one entry per discovered
# binary to the caller's accumulator via nameref.
__det_nodejs_manager() {
  local name=$1 root=$2 maxdepth=$3 user=$4 acc=$5
  [[ -d "$root" ]] || return 0
  local bin v
  while IFS= read -r bin; do
    [[ -z "$bin" ]] && continue
    v=$(as_user "$user" "$bin" --version 2>/dev/null || echo "unknown")
    declare -n __acc=$acc
    __acc+=("$(__det_nodejs_entry "$name" "$bin" "$v" "$user" "$(dirname "$(dirname "$bin")")")")
  done < <(find "$root" -maxdepth "$maxdepth" -name node -type f 2>/dev/null || true)
}

# detect::nodejs_probe <user> <home> <fragment_path>
#
# Enumerates Node.js across the covered sources and writes a {nodejs: [...]}
# fragment (empty array on a greenfield host). Exports DETECT_NODEJS_COUNT +
# per-index DETECT_NODEJS_${i}_{SOURCE,PATH,VERSION,WRITABLE,PREFIX_ROOT} so the
# renderer and readers consume them by name without re-parsing JSON.
detect::nodejs_probe() {
  local user=$1 home=$2 fragment_path=$3
  local entries=()

  # ---- 1-2. Distro-package Node (NodeSource vs distro module) — family-branched ----
  # The package-manager probe differs by family; classify the real source so a
  # brownfield NodeSource Node is never reported "absent" (the v0.3.4-class
  # misclassification bug). READ-ONLY on both arms: `dpkg-query`/`rpm -q` + file
  # tests only, never a write-path package command (which would touch the package
  # cache and break the 15-detection read-only invariant — Pitfall 5).
  case "${AGENTLINUX_DISTRO_FAMILY:-debian}" in
    rhel)
      # EL9: classify a pre-existing rpm-installed Node by its REAL source.
      #   NodeSource-RPM: the rpm RELEASE carries the `nodesource` substring AND a
      #     NodeSource yum-repo file is present. We key on the `nodesource`
      #     substring (not the deb-specific `-1nodesource`) for robustness across
      #     the nodistro repo layout; the EXACT `%{RELEASE}` string (e.g.
      #     `…nodesource.el9`) is live-verified on almalinux:9 in Phase 19 (Open
      #     Q1). Repo-file presence is probed through nodesource_repo_paths
      #     (pkg.sh) — NOT a hardcoded yum.repos.d path — so this detect gate, the
      #     30-nodejs idempotency gate, and the agentlinux-install purge cleanup
      #     all read the SAME source of truth.
      #   AppStream-module: rpm has nodejs but the RELEASE lacks `nodesource` — a
      #     DISTINCT source class so it is never miscounted as NodeSource.
      local ns_version ns_repo_present=0 repo_file
      ns_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' nodejs 2>/dev/null || true)
      while IFS= read -r repo_file; do
        [[ -f "$repo_file" ]] && ns_repo_present=1
      done < <(nodesource_repo_paths)
      if [[ "$ns_version" == *nodesource* ]] && [[ "$ns_repo_present" -eq 1 ]]; then
        entries+=("$(__det_nodejs_entry nodesource /usr/bin/node "$ns_version" "$user" /usr)")
      elif [[ -n "$ns_version" ]]; then
        entries+=("$(__det_nodejs_entry distro_rpm /usr/bin/node "$ns_version" "$user" /usr)")
      fi
      ;;
    *)
      # ---- 1. NodeSource APT (dual-gate) ----
      # `|| true` because dpkg-query exits 1 when nodejs is absent — expected.
      local ns_version
      ns_version=$(dpkg-query -W -f='${Version}\n' nodejs 2>/dev/null || true)
      if [[ "$ns_version" == *"-1nodesource"* ]]; then
        if [[ -f /etc/apt/sources.list.d/nodesource.sources ]] \
          || [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
          entries+=("$(__det_nodejs_entry nodesource /usr/bin/node "$ns_version" "$user" /usr)")
        fi
      fi

      # ---- 2. Distro APT (dpkg has nodejs but version lacks NodeSource suffix) ----
      if [[ -n "$ns_version" && "$ns_version" != *"-1nodesource"* ]]; then
        entries+=("$(__det_nodejs_entry distro_apt /usr/bin/node "$ns_version" "$user" /usr)")
      fi
      ;;
  esac

  # ---- 3. Manual /usr/local/bin/node ----
  # readlink -f resolves the chain; if it equals self the file is real (a
  # symlink into a manager prefix is reported by that manager block instead, so
  # no double-count).
  if [[ -f /usr/local/bin/node ]]; then
    local resolved
    resolved=$(readlink -f /usr/local/bin/node 2>/dev/null || true)
    if [[ "$resolved" == /usr/local/bin/node ]]; then
      local v
      v=$(as_user "$user" /usr/local/bin/node --version 2>/dev/null || echo "unknown")
      entries+=("$(__det_nodejs_entry manual /usr/local/bin/node "$v" "$user" /usr/local)")
    fi
  fi

  # ---- 4-9. Per-user managers (file existence; no shell init) ----
  __det_nodejs_manager nvm "$home/.nvm/versions/node" 3 "$user" entries
  __det_nodejs_manager fnm "$home/.local/share/fnm/node-versions" 4 "$user" entries
  __det_nodejs_manager volta "$home/.volta/tools/image/node" 4 "$user" entries
  __det_nodejs_manager mise "$home/.local/share/mise/installs/node" 4 "$user" entries
  __det_nodejs_manager asdf "$home/.asdf/installs/nodejs" 4 "$user" entries
  __det_nodejs_manager pnpm "$home/.local/share/pnpm/nodejs" 4 "$user" entries

  if [[ ${#entries[@]} -eq 0 ]]; then
    jq -n '{nodejs: []}' >"$fragment_path"
  else
    printf '%s\n' "${entries[@]}" | jq -s '{nodejs: .}' >"$fragment_path"
  fi

  # Per-entry exports so the renderer can iterate by name without re-parsing.
  local i=0 entry
  for entry in "${entries[@]}"; do
    export "DETECT_NODEJS_${i}_SOURCE"="$(printf '%s' "$entry" | jq -r '.source')"
    export "DETECT_NODEJS_${i}_PATH"="$(printf '%s' "$entry" | jq -r '.path')"
    export "DETECT_NODEJS_${i}_VERSION"="$(printf '%s' "$entry" | jq -r '.version')"
    export "DETECT_NODEJS_${i}_WRITABLE"="$(printf '%s' "$entry" | jq -r '.install_user_can_write_prefix')"
    export "DETECT_NODEJS_${i}_PREFIX_ROOT"="$(printf '%s' "$entry" | jq -r '.prefix_root')"
    i=$((i + 1))
  done

  export DETECT_NODEJS_COUNT=${#entries[@]}
  if [[ ${#entries[@]} -eq 0 ]]; then
    export DETECT_NODEJS_SECTION_STATUS=absent
  else
    export DETECT_NODEJS_SECTION_STATUS=present
  fi
}

# detect::nodejs_satisfies_pin — exit 0 if any enumerated entry's version
# matches Node 22 LTS (leading major `v?22.`).
detect::nodejs_satisfies_pin() {
  local count=${DETECT_NODEJS_COUNT:-0}
  local i v_var v
  for ((i = 0; i < count; i++)); do
    v_var="DETECT_NODEJS_${i}_VERSION"
    v=${!v_var:-}
    if [[ "$v" =~ ^v?22\. ]]; then
      return 0
    fi
  done
  return 1
}

# detect::nodejs_prefix_writable — exit 0 if any enumerated entry has
# install_user_can_write_prefix=true (the install user can write to at least one
# Node prefix root).
detect::nodejs_prefix_writable() {
  local count=${DETECT_NODEJS_COUNT:-0}
  local i w_var
  for ((i = 0; i < count; i++)); do
    w_var="DETECT_NODEJS_${i}_WRITABLE"
    if [[ "${!w_var:-false}" == "true" ]]; then
      return 0
    fi
  done
  return 1
}
