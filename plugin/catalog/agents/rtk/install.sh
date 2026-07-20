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
# Cross-agent auto-wiring (WIRE-02, #4 dogfood): install fans rtk's `init` hook
# out to EVERY supported installed coding agent (claude-code, codex, opencode;
# Antigravity CLI and qwen-code have no rtk target). And the CLI's post-install reconcile re-runs
# rtk's rewire.sh whenever an agent is installed LATER, so rtk ends up wired into
# the same set regardless of install order. This supersedes the earlier opt-in
# stance (WORK-02): the maintainer's dogfood feedback is that installing rtk
# should wire the whole fleet, not just print an instruction. The wiring is
# best-effort (see lib/rtk-wire.sh) — a per-agent hiccup never fails the install.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/prebuilt-binary.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/prebuilt-binary.sh"

ver="${AGENTLINUX_PINNED_VERSION}"
# rtk names its assets with Rust target triples: musl for x86_64, gnu for aarch64
# (there is no aarch64-musl asset). Release tags are v-prefixed; the binary reports
# the bare version, which al_pb_assert_version checks.
arch=$(al_pb_arch "x86_64-unknown-linux-musl" "aarch64-unknown-linux-gnu") || exit 1
base="https://github.com/rtk-ai/rtk/releases/download/v${ver}"
asset="rtk-${arch}.tar.gz"
checksums="checksums.txt"
bin_in_archive="rtk"
bin_name="rtk"
dest="${AGENTLINUX_AGENT_HOME}/.local/bin"

echo "rtk: installing rtk-ai/rtk@v${ver} (source_kind binary) to ${dest}"

al_pb_install "$base" "$asset" "$checksums" "$bin_in_archive" "$bin_name" "$dest" "$ver" || {
  echo "rtk install: al_pb_install failed for rtk-ai/rtk@v${ver}" >&2
  exit 1
}

echo "rtk: installed at ${dest}/rtk"

# WIRE-02: auto-wire rtk into every installed coding agent. `hash -r` so the
# just-installed binary resolves on PATH for the wire step (dest is on the
# AgentLinux PATH). The reconcile in the CLI (plugin/cli/src/rewire.ts) handles
# agents installed later via rtk's rewire.sh.
hash -r
# shellcheck source=../../lib/rtk-wire.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/rtk-wire.sh"
al_rtk_wire
