#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# packaging/curl-installer/install.sh — AgentLinux v0.3.0 curl-pipe-bash installer (INST-03).
#
# This script is fetched and piped into bash by users:
#
#   curl -fsSL https://agentlinux.org/install.sh | sudo bash
#
# The entire body below is wrapped in `main() { ... }` and invoked at the very
# last line via `main "$@"`. This is the canonical mitigation for the
# "partial-download execution" class of bugs where a truncated curl output
# (connection reset mid-transfer) could otherwise execute half the script.
# With the wrapper, bash parses the full file before executing any logic — a
# truncation yields a syntax error BEFORE any commands fire, so a short-read
# cannot destroy the system. No content may appear after the final `main "$@"`.
#
# References:
#   - https://www.kicksecure.com/wiki/Dev/curl_bash_pipe
#   - https://dev.to/operous/how-to-build-a-trustworthy-curl-pipe-bash-workflow-4bb
#   - .planning/phases/06-distribution-release-pipeline/06-RESEARCH.md §Pitfall 1
#   - .planning/phases/06-distribution-release-pipeline/06-02-PLAN.md §threat_model (T-06-04)
#
# Security envelope (INST-03):
#   - HTTPS-only release URLs (T-06-01)
#   - SHA256 sidecar verified BEFORE tar extraction (T-06-02)
#   - `curl -fsSL` with mandatory `-f` (Pitfall 2) on every remote fetch
#   - `main(){}; main "$@"` wrapper (T-06-04 partial-download safety)
#   - `AGENTLINUX_VERSION` env regex-gated before URL interpolation (T-06-05)
#   - post-download gzip magic check (Pitfall 2 diagnostic)
#   - `mktemp -d` + `trap rm -rf EXIT` for staging cleanup (info-disclosure hygiene)
#   - no `eval`, no command substitution from untrusted remote input

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------------------
# Config (overridable via env). ORG + VERSION are regex-validated before use.
# AGENTLINUX_RELEASE_BASE is the test-mode seam consumed by 60-curl-installer.bats;
# when set it REPLACES the github.com base URL entirely, including the path.
# ------------------------------------------------------------------------------
: "${ORG:=Roo4L}"
: "${AGENTLINUX_ORG:=$ORG}" # alias for readability in docs
: "${AGENTLINUX_RELEASE_BASE:=}"
: "${AGENTLINUX_VERSION:=}"

readonly VERSION_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$'
readonly ORG_REGEX='^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'

# ------------------------------------------------------------------------------
# One-line failure helper. Single-quoted format prevents any "$msg" expansion
# from reinterpreting embedded `%` characters.
# ------------------------------------------------------------------------------
die() {
  printf 'agentlinux-install: %s\n' "$*" >&2
  exit 1
}

# ------------------------------------------------------------------------------
# Require EUID == 0. The installer writes under /opt/agentlinux, /etc, and
# /home/agent — none of which are writable without root.
# ------------------------------------------------------------------------------
check_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die 'must run as root; invoke as: curl -fsSL https://agentlinux.org/install.sh | sudo bash'
  fi
}

# ------------------------------------------------------------------------------
# Parse /etc/os-release; die unless it declares Ubuntu 22.04, 24.04 or 26.04.
# Source: 06-RESEARCH.md lines 920-936 (Example: Ubuntu version detection).
# Keep this allowlist in lockstep with plugin/lib/distro_detect.sh — both gate
# the same support matrix and the curl-installer test fixture exercises this
# path before handing off to the staged installer.
# ------------------------------------------------------------------------------
detect_ubuntu_version() {
  local id version
  if [[ ! -r /etc/os-release ]]; then
    die 'cannot detect Ubuntu version: /etc/os-release missing or unreadable'
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  id=${ID:-unknown}
  version=${VERSION_ID:-unknown}
  [[ "$id" == "ubuntu" ]] \
    || die "unsupported distro: ${id} (AgentLinux v0.3.0 supports Ubuntu only)"
  case "$version" in
    22.04 | 24.04 | 26.04) ;;
    *)
      die "unsupported Ubuntu version: ${version} (AgentLinux v0.3.0 supports 22.04, 24.04 and 26.04 only)"
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Resolve the release tag. Priority:
#   1. $AGENTLINUX_VERSION (regex-gated; T-06-05 input validation)
#   2. GitHub Releases "latest" permalink via HEAD-follow redirect
#      (no JSON API → no rate-limit exposure; Pitfall T-06-09)
#
# Returns the tag on stdout (e.g. "v0.3.0"). Dies on failure.
# Source: 06-RESEARCH.md lines 943-958 (Example: Version resolution).
# ------------------------------------------------------------------------------
resolve_version() {
  if [[ -n "${AGENTLINUX_VERSION}" ]]; then
    [[ "$AGENTLINUX_VERSION" =~ $VERSION_REGEX ]] \
      || die "AGENTLINUX_VERSION does not match ${VERSION_REGEX}: '${AGENTLINUX_VERSION}'"
    printf '%s' "$AGENTLINUX_VERSION"
    return 0
  fi
  local redirect tag
  # Read ONLY the FIRST redirect's Location header — do NOT follow with -L.
  # GitHub's releases-latest-download path emits a 302 with Location:
  # /releases/download/<TAG>/<asset>, which contains the tag we need to
  # extract. With -L, curl follows that hop AND the second hop into
  # release-assets.githubusercontent.com — and `%{url_effective}` then
  # reports only the FINAL URL, which is opaque (token-only, no tag).
  # `%{redirect_url}` prints the next-hop Location without following.
  # Dogfood-discovered against v0.3.2-rc2 (AL-31).
  redirect=$(curl -fsS -I -o /dev/null -w '%{redirect_url}' \
    "https://github.com/${ORG}/agent-linux/releases/latest/download/VERSION") \
    || die 'could not resolve latest version (check network connectivity and https://github.com/'"${ORG}"'/agent-linux/releases/latest)'
  tag=$(printf '%s' "$redirect" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?' | head -n 1)
  [[ -n "$tag" ]] || die "could not parse tag from redirect Location header (got: '${redirect:-<empty — server returned 200 instead of a 302 to releases/download/...>}'); set AGENTLINUX_VERSION to override"
  printf '%s' "$tag"
}

main() {
  check_root
  detect_ubuntu_version

  # Org sanity — even though the default is hardcoded, AGENTLINUX_ORG env may
  # override it (e.g. for test forks). Refuse arbitrary path injection.
  [[ "$ORG" =~ $ORG_REGEX ]] \
    || die "ORG fails regex ${ORG_REGEX}: '${ORG}'"

  local tag
  tag=$(resolve_version)

  # Base URL selection: test-mode override (local HTTP fixture) OR the real
  # GitHub Releases permalink. The override is HTTPS-only in production but
  # the bats fixture uses http://localhost:<port> — we guard on the override
  # being explicitly set so a production run cannot accidentally fall back to
  # an http:// URL.
  local base
  if [[ -n "$AGENTLINUX_RELEASE_BASE" ]]; then
    base="${AGENTLINUX_RELEASE_BASE}/${tag}"
  else
    base="https://github.com/${ORG}/agent-linux/releases/download/${tag}"
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t agentlinux-install.XXXXXX) \
    || die 'mktemp -d failed; cannot stage downloads'
  # shellcheck disable=SC2064
  # Intentional: expand tmpdir NOW so the trap retains the real path even if
  # the variable is later unset or reassigned.
  trap "rm -rf '${tmpdir}'" EXIT

  local tarball="agentlinux-${tag}.tar.gz"

  # -f  : fail on HTTP errors (Pitfall 2 — non-optional)
  # -s  : silent (no progress bar in piped contexts)
  # -S  : still show error on failure despite -s
  # -L  : follow redirects (release CDN redirects to storage host)
  printf 'agentlinux-install: downloading %s\n' "${base}/${tarball}"
  curl -fsSL "${base}/${tarball}" -o "${tmpdir}/${tarball}" \
    || die "failed to download tarball ${base}/${tarball}"
  printf 'agentlinux-install: downloading %s.sha256\n' "${tarball}"
  curl -fsSL "${base}/${tarball}.sha256" -o "${tmpdir}/${tarball}.sha256" \
    || die "failed to download sha256 sidecar ${base}/${tarball}.sha256"

  # Pitfall 2 diagnostic: if -f was somehow stripped (proxy rewrite, etc.) an
  # HTTP 404 HTML body would land in the tarball path and sha256sum -c would
  # emit a confusing "FAILED" verdict. Asserting the gzip magic bytes BEFORE
  # sha256 gives a precise error.
  #
  # Read the first two bytes via `head` + `od` rather than `file(1)`: the
  # `file` package is NOT preinstalled on minimal Ubuntu/Debian cloud images
  # (and many Docker base images). `head` and `od` are coreutils, always
  # present. Magic for gzip is 1f 8b (RFC 1952).
  local _magic
  _magic=$(head -c 2 "${tmpdir}/${tarball}" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  if [[ "$_magic" != "1f8b" ]]; then
    die "downloaded ${tarball} is not a gzip archive (magic bytes: ${_magic:-empty}) — possible 404-as-HTML or proxy-rewrite; refusing to proceed"
  fi

  # SHA256 verification BEFORE extraction (T-06-02 — hard security gate).
  # sha256sum -c reads the sidecar's filename column; chdir into tmpdir so
  # the unqualified filename matches.
  if ! (cd "$tmpdir" && sha256sum -c "${tarball}.sha256") >/dev/null 2>&1; then
    die "SHA256 verification failed for ${tarball} — aborting install (possible tampering, proxy corruption, or partial download)."
  fi
  printf 'agentlinux-install: SHA256 verified for %s\n' "$tarball"

  local inst="/opt/agentlinux/install/${tag#v}"
  mkdir -p "$inst"

  # --no-same-owner: defensive against forged owner metadata inside the tarball
  # (reproducible-builds tarball is built with owner=0 so the flag is a no-op
  # in the happy path, but a belt-and-suspenders guard on extraction).
  tar --extract --gzip \
    --file="${tmpdir}/${tarball}" \
    --directory="$inst" \
    --no-same-owner \
    || die "tar extraction failed for ${tarball} into ${inst}"

  local exe="${inst}/plugin/bin/agentlinux-install"
  [[ -x "$exe" ]] \
    || die "extracted tarball missing executable ${exe} — corrupt release?"

  printf 'agentlinux-install: verified and extracted %s — handing off to agentlinux-install\n' "$tarball"
  exec "$exe" "$@"
}

main "$@"
