#!/usr/bin/env bash
set -euo pipefail
# rtk install.sh — source_kind: binary (Phase 28, WORK-02 / ENABLE-01).
#
# Installs RTK (Rust Token Killer) from the pinned GitHub release `rtk-ai/rtk` —
# NOT the unrelated crates.io same-named crate (a different Rust tool). The
# crates.io path is NEVER used; that is the canonical naming collision WORK-02
# forbids.
#
# The fetch + checksum-verify-before-extract + arch-detect + install logic lives
# in the shared helper plugin/catalog/lib/prebuilt-binary.sh (ENABLE-01); this
# recipe only sets rtk's repo/tag/asset/bin and calls al_pb_install. The pin is
# read from AGENTLINUX_PINNED_VERSION (ADR-011 single source of truth) — never
# hardcoded here. Release tags are v-prefixed (v<pin>); the binary reports the
# bare <pin>, which the helper's version-lock assert checks.
#
# OPT-IN hook (WORK-02): install does NOT run the rtk hook initializer. Auto-
# mutating ~/.claude without consent would break the opt-in contract, so the
# recipe only PRINTS the instruction for the user to wire rtk into Claude Code
# themselves.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/prebuilt-binary.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"

tool="rtk"
repo="rtk-ai/rtk"
tag="v${AGENTLINUX_PINNED_VERSION}"
bin_in_archive="rtk"
bin_name="rtk"
dest="${AGENTLINUX_AGENT_HOME}/.local/bin"

echo "rtk: installing ${repo}@${tag} (source_kind binary) to ${dest}"

al_pb_install "$tool" "$repo" "$tag" "$bin_in_archive" "$bin_name" "$dest" || {
  echo "rtk install: al_pb_install failed for ${repo}@${tag}" >&2
  exit 1
}

echo "rtk: installed at ${dest}/rtk"
echo "rtk: OPTIONAL — to wire rtk into Claude Code, run:  rtk init -g"
