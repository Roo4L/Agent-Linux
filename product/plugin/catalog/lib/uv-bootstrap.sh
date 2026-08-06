#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/catalog/lib/uv-bootstrap.sh — ENABLE-03 shared Python+uv bootstrap helper.
#
# SOURCED, NOT EXECUTED. A uv-backed catalog recipe (agents/<id>/install.sh) sources
# this file via:
#
#   source "${AGENTLINUX_CATALOG_DIR}/lib/uv-bootstrap.sh"
#
# and then calls al_uv_ensure + al_uv_tool_install (install.sh) or
# al_uv_tool_uninstall + al_uv_remove_if_managed_and_unused (uninstall.sh). The
# provisioner stages this whole `lib/` subdir to /opt/agentlinux/catalog/<ver>/lib/
# automatically (50-registry-cli.sh copies the catalog tree with `cp -R`), so no
# provisioner edit is needed to ship it.
#
# Why a helper (CAT-03 reuse): a uv tool needs (a) a per-user uv binary bootstrapped
# with no root, (b) a `uv tool install` from a pinned source, and (c) a SYMMETRIC
# remove that must NOT delete a uv the user brought themselves. That ownership
# bookkeeping is non-trivial and identical for every uv tool, so it lives here once.
# The named future consumer is the Phase 49 ENABLE-07 growth-kit template — a
# contributor adding a uv tool reuses this and never re-derives uv bootstrapping.
#
# Security keystone: the uv binary itself is fetched through the ENABLE-01
# prebuilt-binary helper (al_pb_install) — checksum-verified BEFORE extraction, into
# the agent-owned ~/.local/bin, never a /usr/local shim. uv is a static musl build
# (portable across the Ubuntu + AlmaLinux targets) and manages its own CPython, so
# the host needs no system Python.
#
# Deliberately NOT `set -euo pipefail` at file top: sourced into recipes that own
# their own shell options. Each function returns non-zero on failure so the sourcing
# recipe aborts cleanly.

# The uv binary pin is bootstrap INFRASTRUCTURE (distinct from the catalog entry's
# pinned_version, which pins the tool being installed). Override with AL_UV_PIN.
AL_UV_PIN="${AL_UV_PIN:-0.11.28}"

# Where the "AgentLinux installed this uv" marker lives. Its presence is the sole
# authority for whether uninstall may remove uv (see al_uv_remove_if_managed_and_unused).
_al_uv_marker() { printf '%s/.local/share/agentlinux/uv.managed' "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"; }

# al_uv_ensure [uv_pin]
# Idempotently guarantee a usable `uv` on PATH. If uv is ALREADY present (the user's
# own, or a prior AgentLinux install) it is REUSED untouched — we never clobber a
# user-brought uv. Only when uv is absent do we install the pinned static-musl build
# via the checksum-verified ENABLE-01 path and drop the managed marker so uninstall
# knows AgentLinux owns it.
al_uv_ensure() {
  local pin="${1:-$AL_UV_PIN}"
  local home="${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
  local dest="${home}/.local/bin"

  # Refresh the command hash table so a uv installed earlier in THIS shell (or one
  # just removed) is seen accurately rather than from a stale negative/positive cache.
  hash -r
  if command -v uv >/dev/null 2>&1; then
    printf 'uv-bootstrap: reusing existing uv (%s)\n' "$(uv --version 2>&1 | head -1)"
    return 0
  fi

  # shellcheck source=./prebuilt-binary.sh
  source "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}/lib/prebuilt-binary.sh"

  local arch base asset
  # uv publishes static musl tarballs for both arches (portable, no glibc pin) plus a
  # combined sha256.sum. Tags are NOT v-prefixed. The binary is nested as uv-<triple>/uv.
  arch=$(al_pb_arch "x86_64-unknown-linux-musl" "aarch64-unknown-linux-musl") || return 1
  base="https://github.com/astral-sh/uv/releases/download/${pin}"
  asset="uv-${arch}.tar.gz"

  mkdir -p "$dest"
  printf 'uv-bootstrap: bootstrapping uv %s (%s) into %s\n' "$pin" "$arch" "$dest"
  # Use uv's PER-ASSET checksum file (<asset>.sha256), which is standard
  # `<sha256>␣␣<filename>` — the format al_pb_fetch_and_verify's `$2==asset` awk
  # expects. uv's COMBINED sha256.sum uses BSD-tag form (`<sha256>␣*<filename>`),
  # whose `*` binds to awk's $2 and would never match the bare asset name.
  al_pb_install "$base" "$asset" "${asset}.sha256" "uv-${arch}/uv" "uv" "$dest" "$pin" || {
    printf 'uv-bootstrap: uv %s bootstrap failed\n' "$pin" >&2
    return 1
  }

  local marker
  marker=$(_al_uv_marker)
  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "$pin" >"$marker"
  return 0
}

# al_uv_tool_install <pkg> <git_url> <tag> [python_version]
# Install a Python CLI tool from a pinned git ref as a uv tool. --force makes it
# idempotent (a re-install of the same pin is a no-op-equivalent overwrite, and it is
# also how spec-kit's own upgrade path re-pins). --python pins a uv-managed CPython so
# the host needs no system Python. The tool executable lands in the agent-owned
# ~/.local/bin (uv's default tool-bin dir), already on PATH in all six invocation modes.
al_uv_tool_install() {
  local pkg="$1" git_url="$2" tag="$3" python="${4:-3.12}"
  command -v uv >/dev/null 2>&1 || {
    printf 'uv-bootstrap: uv not on PATH; call al_uv_ensure first\n' >&2
    return 1
  }
  printf 'uv-bootstrap: uv tool install %s @ %s (python %s)\n' "$pkg" "$tag" "$python"
  uv tool install --force --python "$python" "$pkg" --from "git+${git_url}@${tag}" || {
    printf 'uv-bootstrap: uv tool install %s@%s failed\n' "$pkg" "$tag" >&2
    return 1
  }
  return 0
}

# _al_uv_tool_lines — emit `uv tool list` with color forced off (NO_COLOR, honored by
# uv) AND any residual ANSI SGR stripped, so the awk column parsers below see clean
# `<name> <version>` rows regardless of uv's TTY-detection. Returns non-zero only when
# `uv tool list` itself fails (caller treats that as "unknown", never "empty").
_al_uv_tool_lines() {
  local out
  out=$(NO_COLOR=1 uv tool list 2>/dev/null) || return 1
  printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
}

# al_uv_tool_uninstall <pkg>
# Remove a uv tool if present. Idempotent: a missing uv, or an already-absent tool,
# is a clean success (re-remove must not error). NOTE (intentional ownership choice):
# this removes <pkg> whenever it is present, even a <pkg> the user installed into
# their own uv before AgentLinux ran — consistent with the aggressive-ownership stance
# (`agentlinux remove` fully removes what the entry manages). The managed-uv teardown
# below is stricter (marker-gated); only the tool itself is adopted unconditionally.
al_uv_tool_uninstall() {
  local pkg="$1"
  command -v uv >/dev/null 2>&1 || return 0
  if _al_uv_tool_lines | awk -v p="$pkg" '$1==p{found=1} END{exit !found}'; then
    uv tool uninstall "$pkg" || return 1
  fi
  return 0
}

# al_uv_remove_if_managed_and_unused
# Remove the uv binary + its data ONLY when BOTH hold: (1) AgentLinux installed uv
# (the managed marker exists — a user-brought uv has none and is left untouched), and
# (2) no uv-managed tools remain. This keeps `agentlinux remove` residue-free without
# ever deleting infrastructure the user owns or that another uv tool still needs.
al_uv_remove_if_managed_and_unused() {
  local home="${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
  local marker lines
  marker=$(_al_uv_marker)
  [[ -f "$marker" ]] || return 0

  if command -v uv >/dev/null 2>&1; then
    # Capture the list ONCE. If listing FAILS (non-zero), treat it as "unknown" and
    # KEEP uv — never guess-delete shared infrastructure on an error. A remaining tool
    # is any row whose first column is a real tool name (not the `-` executable
    # continuation line, and not uv's "No tools installed" sentinel).
    if lines=$(_al_uv_tool_lines); then
      if printf '%s\n' "$lines" | awk 'NF>=2 && $1!="-" && $1!="No"{found=1} END{exit !found}'; then
        printf 'uv-bootstrap: uv still has managed tools; keeping uv\n'
        return 0
      fi
    else
      printf 'uv-bootstrap: could not list uv tools; keeping uv (safe default)\n'
      return 0
    fi
  fi

  printf 'uv-bootstrap: removing AgentLinux-managed uv (no tools remain)\n'
  rm -f "${home}/.local/bin/uv" "${home}/.local/bin/uvx"
  rm -rf "${home}/.local/share/uv" "${home}/.cache/uv"
  rm -f "$marker"
  rmdir "${home}/.local/share/agentlinux" 2>/dev/null || true
  return 0
}
