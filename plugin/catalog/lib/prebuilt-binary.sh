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
# Reuse keystone (CAT-03): generic over <base_url>/<asset>/<checksums>/
# <bin_path_in_archive>/<bin_name>/<dest_dir>/<pinned>, so a binary tool adds only
# a catalog entry + a thin recipe with no further CLI source edits. The recipe
# owns the tool-specific bits — which host serves the release (GitHub or GitLab),
# how the per-arch asset and checksum files are named, and where the binary sits
# inside the archive — because those genuinely differ per upstream (rtk uses Rust
# target triples; gh/glab/trivy/gitleaks use Go-style os_arch names, some nested
# under bin/, and glab is served from gitlab.com rather than github.com). The
# helper owns the security-critical, tool-agnostic core: arch dispatch, the
# verify-BEFORE-extract download, the single-member extract, and the version lock.
#
# Deliberately NOT `set -euo pipefail` at file top: this is sourced into recipes
# that own their own shell options. Each function is individually robust and
# returns non-zero on failure so the sourcing recipe can abort cleanly.

# One-line failure helper. Single-quoted format string keeps any '%' in "$*" inert.
al_pb_die() {
  printf 'prebuilt-binary: %s\n' "$*" >&2
  return 1
}

# al_pb_arch <x86_64_token> <aarch64_token>
# Echo the caller-supplied token that matches the running architecture — the
# recipe splices it into its own asset/bin-path names. Every upstream spells the
# arch differently (rtk: `x86_64-unknown-linux-musl` / `aarch64-unknown-linux-gnu`;
# gh & glab: `amd64` / `arm64`; trivy: `64bit` / `ARM64`; gitleaks: `x64` /
# `arm64`), so the tokens can't live here — but the uname dispatch and the
# unsupported-arch guard (die rather than install a wrong-arch binary) are the same
# for every tool and belong in one place. Only x86_64 and aarch64 are supported;
# any other machine aborts cleanly.
al_pb_arch() {
  local x86="$1" arm="$2"
  case "$(uname -m)" in
    x86_64)
      printf '%s\n' "$x86"
      ;;
    aarch64 | arm64)
      printf '%s\n' "$arm"
      ;;
    *)
      al_pb_die "unsupported architecture '$(uname -m)' (only x86_64, aarch64)"
      return 1
      ;;
  esac
}

# al_pb_fetch_and_verify <base_url> <asset> <checksums> <tmpdir>
# Download <asset> + <checksums> from <base_url> into <tmpdir>, assert the gzip
# magic bytes, then verify the asset's sha256 line. Returns non-zero (so the recipe
# aborts) on ANY failure and NEVER extracts. The verification runs BEFORE any
# caller extracts — this function is the security gate. <checksums> is a parameter
# because upstreams disagree on the name: rtk & glab publish a bare `checksums.txt`,
# while gh/trivy/gitleaks publish a per-version `<tool>_<ver>_checksums.txt`. The
# remote name is normalized to a local `checksums.txt` so the rest of the function
# is uniform regardless of what it was called upstream.
al_pb_fetch_and_verify() {
  local base="$1" asset="$2" checksums="$3" tmp="$4"

  # -f: fail on HTTP errors (non-optional — a stripped -f lets 404-HTML through).
  # -s -S: quiet but still print errors. -L: follow the release CDN redirect.
  # --proto-redir '=https': every REDIRECT hop must be https. A GitHub release
  # download 302s to objects.githubusercontent.com and a GitLab one to its own
  # storage CDN — both https; pinning redirects to https means a hijacked redirect
  # can never silently downgrade the transport to plaintext http (the security goal
  # here). --proto '=https,file' pins the INITIAL request to https (no http/ftp)
  # while still permitting file:// — the production base is always a hardcoded
  # https://github.com/... or https://gitlab.com/... URL (file:// is unreachable
  # from any catalog input), and the file scheme exists solely so the offline
  # verify-before-extract self-test can drive this path without a network.
  curl -fsSL --proto '=https,file' --proto-redir '=https' "${base}/${asset}" -o "${tmp}/${asset}" \
    || {
      al_pb_die "download failed: ${base}/${asset}"
      return 1
    }
  curl -fsSL --proto '=https,file' --proto-redir '=https' "${base}/${checksums}" -o "${tmp}/checksums.txt" \
    || {
      al_pb_die "download failed: ${base}/${checksums}"
      return 1
    }

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

  # Trust anchor: checksums.txt is fetched over the SAME TLS channel as the asset and
  # is NOT independently signed. So the guarantee here is integrity against in-transit
  # tampering given honest TLS-to-github and an honest published release — it is NOT a
  # cryptographic proof of upstream authorship. (Transport + release honesty, not
  # supply-chain authenticity.)
  #
  # Select ONLY the asset's checksum line by an EXACT 2nd-column match — awk's $2==a is
  # a literal string compare, unlike `grep -E` whose `.` in the asset name would match
  # any character (a near-name collision could otherwise slip through). checksums.txt is
  # the standard `<sha256>␣␣<filename>` format (RESEARCH Pitfall 2); awk exits non-zero
  # when no line's filename column equals the asset exactly, preserving the
  # "no checksum line → abort" behavior below. sha256sum -c then resolves the filename
  # column relative to CWD, so chdir into the tmpdir where the asset lives under its
  # exact upstream name.
  awk -v a="$asset" '$2==a {print; found=1} END{exit !found}' "${tmp}/checksums.txt" >"${tmp}/${asset}.sha256" \
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
  # Assert the extracted path is a real regular file, not a symlink — a tarball
  # member could be a symlink pointing outside the tmpdir, which `install` would then
  # follow and copy from an attacker-chosen path. Refuse anything but a plain file.
  [[ -f "${tmp}/${bin_path}" && ! -L "${tmp}/${bin_path}" ]] \
    || {
      al_pb_die "extracted ${bin_path} is not a regular file"
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

# al_pb_install <base_url> <asset> <checksums> <bin_path_in_archive> <bin_name> \
#               <dest_dir> <pinned>
# Public orchestrator: stage a self-cleaning tmpdir, fetch + verify (BEFORE
# extract), extract + install the named binary, then assert the pinned version.
# Any step's failure returns non-zero so the sourcing recipe aborts. Uses
# `trap ... RETURN` (NOT EXIT) because this helper is sourced into a longer-lived
# recipe shell — EXIT would defer cleanup to the recipe's own exit.
al_pb_install() {
  local base="$1" asset="$2" checksums="$3" bin_path="$4" bin_name="$5" dest="$6" pinned="$7"
  local tmp rc=0

  # Under functrace (`set -T`, which bats enables per @test) a RETURN trap is
  # inherited by every called function, so the FIRST nested return (e.g. from
  # al_pb_fetch_and_verify) would fire the trap and delete $tmp before
  # al_pb_extract_install reads it. Disable functrace for this function's scope
  # and restore it before returning; the trap is installed after `set +T` so it
  # captures the disabled state. Mirrors plugin/lib/detect.sh::run_once. In
  # production recipes run in a fresh `bash` subprocess without inherited -T, so
  # this is defense-in-depth for any future in-process (source + direct call)
  # caller — but cheap and precedented, so we apply it here too.
  local _saved_functrace=
  [[ $- == *T* ]] && _saved_functrace=1
  set +T

  tmp=$(mktemp -d -t "agentlinux-${bin_name}.XXXXXX") \
    || {
      al_pb_die "mktemp -d failed; cannot stage download"
      if [[ -n "$_saved_functrace" ]]; then set -T; fi
      return 1
    }
  # shellcheck disable=SC2064
  # Expand $tmp now so the trap keeps the real path even if the var is reassigned.
  trap "rm -rf '${tmp}'" RETURN

  # Single-exit control flow so functrace is restored on exactly one path. Each
  # step's non-zero return aborts the chain with rc=1 (the recipe then aborts).
  if ! al_pb_fetch_and_verify "$base" "$asset" "$checksums" "$tmp"; then
    rc=1
  elif ! al_pb_extract_install "$tmp" "$asset" "$bin_path" "$bin_name" "$dest"; then
    rc=1
  elif ! al_pb_assert_version "$bin_name" "$pinned"; then
    rc=1
  fi

  if [[ -n "$_saved_functrace" ]]; then set -T; fi
  return "$rc"
}
