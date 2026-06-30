#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/catalog/lib/prebuilt-binary.sh — ENABLE-01 shared prebuilt-binary helper.
#
# SOURCED, NOT EXECUTED. A binary catalog recipe (agents/<id>/install.sh) sources
# this file via:
#
#   source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"
#
# and then calls al_pb_install. The provisioner stages this whole `lib/` subdir to
# /opt/agentlinux/catalog/<ver>/lib/ automatically — `50-registry-cli.sh` already
# copies the catalog tree with `cp -R "$CATALOG_SRC"/.` (no provisioner edit).
#
# Security keystone (RESEARCH.md Pattern 1, Common Pitfalls 1-2-3-6): the download
# is staged to a tmpdir, the gzip magic bytes AND the sha256 are verified BEFORE
# any extraction, and a mismatch aborts (non-zero return) BEFORE `tar` runs. This
# mirrors packaging/curl-installer/install.sh's verify-before-extract discipline.
#
# Reuse keystone (CAT-03): generic over <tool>/<repo>/<tag>/<bin_path_in_archive>/
# <bin_name>/<dest_dir>, so phases 29-33 (gh, glab, trivy, gitleaks, sentry-cli)
# add a tool with only a catalog entry + thin recipe, no further CLI source edits.
#
# Deliberately NOT `set -euo pipefail` at file top: this is sourced into recipes
# that own their own shell options. Each function is individually robust and
# returns non-zero on failure so the sourcing recipe can abort cleanly.

# One-line failure helper. Single-quoted format string keeps any '%' in "$*" inert.
al_pb_die() {
  printf 'prebuilt-binary: %s\n' "$*" >&2
  return 1
}

# al_pb_detect_asset <tool>
# Echo the per-arch release asset name for <tool>. rtk (and the phase 29-33 tools)
# publish a musl tarball for x86_64 and a gnu tarball for aarch64 — there is NO
# aarch64-musl asset (RESEARCH Pitfall 3), so gnu is the only aarch64 option. Die
# cleanly on any other architecture rather than install a wrong-arch binary.
al_pb_detect_asset() {
  local tool="$1"
  case "$(uname -m)" in
    x86_64)
      printf '%s\n' "${tool}-x86_64-unknown-linux-musl.tar.gz"
      ;;
    aarch64 | arm64)
      printf '%s\n' "${tool}-aarch64-unknown-linux-gnu.tar.gz"
      ;;
    *)
      al_pb_die "unsupported architecture '$(uname -m)' (only x86_64, aarch64)"
      return 1
      ;;
  esac
}

# al_pb_fetch_and_verify <base_url> <asset> <tmpdir>
# Download <asset> + checksums.txt from <base_url> into <tmpdir>, assert the gzip
# magic bytes, then verify the asset's sha256 line. Returns non-zero (so the recipe
# aborts) on ANY failure and NEVER extracts. The verification runs BEFORE any
# caller extracts — this function is the security gate.
al_pb_fetch_and_verify() {
  local base="$1" asset="$2" tmp="$3"

  # -f: fail on HTTP errors (non-optional — a stripped -f lets 404-HTML through).
  # -s -S: quiet but still print errors. -L: follow the release CDN redirect.
  curl -fsSL "${base}/${asset}" -o "${tmp}/${asset}" \
    || al_pb_die "download failed: ${base}/${asset}" || return 1
  curl -fsSL "${base}/checksums.txt" -o "${tmp}/checksums.txt" \
    || al_pb_die "download failed: ${base}/checksums.txt" || return 1

  # gzip magic guard (404-as-HTML / proxy-rewrite). Read the first two bytes with
  # head + od rather than file(1) — file is not on minimal Ubuntu/Alma/Docker
  # images; head and od are coreutils. gzip magic is 1f 8b (RFC 1952).
  local magic
  magic=$(head -c 2 "${tmp}/${asset}" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [[ "$magic" == "1f8b" ]] \
    || {
      al_pb_die "${asset} is not gzip (magic=${magic:-empty}) — refusing"
      return 1
    }

  # Select ONLY the asset's checksum line (exact two-space form — checksums.txt is
  # the standard `<sha256>␣␣<filename>` format, RESEARCH Pitfall 2) and verify it.
  # sha256sum -c resolves the filename column relative to CWD, so chdir into the
  # tmpdir where the asset lives under its exact upstream name.
  grep -E "  ${asset}\$" "${tmp}/checksums.txt" >"${tmp}/${asset}.sha256" \
    || {
      al_pb_die "no checksum line for ${asset} in checksums.txt"
      return 1
    }
  (cd "$tmp" && sha256sum -c "${asset}.sha256") >/dev/null 2>&1 \
    || {
      al_pb_die "SHA256 verification failed for ${asset} — aborting BEFORE extract"
      return 1
    }

  return 0
}

# al_pb_extract_install <tmpdir> <asset> <bin_path_in_archive> <bin_name> <dest_dir>
# Extract ONLY <bin_path_in_archive> from the (already-verified) <asset> tarball and
# install it 0755 as <dest_dir>/<bin_name>. <bin_path_in_archive> handles per-tool
# archive-layout variety (RESEARCH Pattern 3): rtk is a flat top-level `rtk`; future
# tools may nest (e.g. `gh_2.95.0_linux_amd64/bin/gh`). MUST run only AFTER
# al_pb_fetch_and_verify succeeds. `--no-same-owner` defends against forged owner
# metadata inside the tarball (V10); `install -m 0755` sets an explicit mode.
al_pb_extract_install() {
  local tmp="$1" asset="$2" bin_path="$3" bin_name="$4" dest="$5"

  mkdir -p "$dest" \
    || {
      al_pb_die "could not create dest dir ${dest}"
      return 1
    }
  tar -xzf "${tmp}/${asset}" -C "$tmp" --no-same-owner "$bin_path" \
    || {
      al_pb_die "tar extraction failed for ${bin_path} from ${asset}"
      return 1
    }
  install -m 0755 "${tmp}/${bin_path}" "${dest}/${bin_name}" \
    || {
      al_pb_die "install of ${bin_name} into ${dest} failed"
      return 1
    }

  return 0
}

# al_pb_assert_version <bin_name> <pinned>
# Version-lock assert: refresh the command hash table, then require the installed
# binary's `--version` output to contain the pinned version. Guards against a
# wrong-arch / wrong-tool binary slipping through (T-28-05). <bin_name> must be on
# PATH (the dest_dir is on the agent's PATH in all six invocation modes).
al_pb_assert_version() {
  local bin_name="$1" pinned="$2" got
  hash -r
  got="$("$bin_name" --version 2>&1 | head -1)"
  printf '%s' "$got" | grep -qF -- "$pinned" \
    || {
      al_pb_die "${bin_name}: pinned=${pinned} but --version: ${got}"
      return 1
    }
  printf 'prebuilt-binary: %s installed (%s)\n' "$bin_name" "$got"
  return 0
}

# al_pb_install <tool> <repo> <tag> <bin_path_in_archive> <bin_name> <dest_dir>
# Public orchestrator: detect the per-arch asset, stage a self-cleaning tmpdir,
# fetch + verify (BEFORE extract), extract + install the named binary, then assert
# the pinned version. Any step's failure returns non-zero so the sourcing recipe
# aborts. Uses `trap ... RETURN` (NOT EXIT) because this helper is sourced into a
# longer-lived recipe shell — EXIT would defer cleanup to the recipe's own exit.
al_pb_install() {
  local tool="$1" repo="$2" tag="$3" bin_path="$4" bin_name="$5" dest="$6"
  local asset base tmp

  asset=$(al_pb_detect_asset "$tool") || return 1

  tmp=$(mktemp -d -t "agentlinux-${tool}.XXXXXX") \
    || {
      al_pb_die "mktemp -d failed; cannot stage download"
      return 1
    }
  # shellcheck disable=SC2064
  # Expand $tmp now so the trap keeps the real path even if the var is reassigned.
  trap "rm -rf '${tmp}'" RETURN

  base="https://github.com/${repo}/releases/download/${tag}"

  al_pb_fetch_and_verify "$base" "$asset" "$tmp" || return 1
  al_pb_extract_install "$tmp" "$asset" "$bin_path" "$bin_name" "$dest" || return 1
  al_pb_assert_version "$bin_name" "${AGENTLINUX_PINNED_VERSION:-${tag#v}}" || return 1

  return 0
}
