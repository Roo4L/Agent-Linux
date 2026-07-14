#!/usr/bin/env bash
set -euo pipefail
# spec-kit install.sh — source_kind: script (Phase 44, WORK-03 / ENABLE-03).
#
# Installs GitHub Spec Kit (the `specify` CLI) as a per-user uv tool — no root, no
# /usr/local shim, zero EACCES. Delivers the ENABLE-03 Python+uv capability by way
# of the shared helper plugin/catalog/lib/uv-bootstrap.sh: bootstrap a per-user uv
# (checksum-verified static binary via ENABLE-01), then `uv tool install` the CLI
# from its pinned git tag with a uv-managed CPython (the host has no guaranteed
# Python 3.11+).
#
# SOURCE (WORK-03): GitHub Spec Kit is an official first-party GitHub project, MIT,
# free, actively maintained — a free-first-party auto-GO under the source-selection
# policy (no credential dimension; offline/local dev tool).
#
# Install mechanic (verified against the upstream README + a real end-to-end smoke):
# spec-kit is installed from a GIT TAG, not a PyPI version pin —
#   uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@vX.Y.Z
# The catalog pin is the bare tag (e.g. 0.12.11); the recipe v-prefixes it. The uv
# binary pin is separate bootstrap infrastructure, owned by the helper (AL_UV_PIN).
# A git tag is a MUTABLE ref (a maintainer could re-point it), so this is transport +
# release-honesty integrity, not cryptographic authorship — acceptable for a
# first-party GitHub project, and the version-lock below catches a re-pointed tag that
# no longer reports the expected version.

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/uv-bootstrap.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/uv-bootstrap.sh"

ver="${AGENTLINUX_PINNED_VERSION}" # pin is the bare tag; v-prefixed for the git ref
tag="v${ver}"
pkg="specify-cli"
git_url="https://github.com/github/spec-kit.git"

# spec-kit installs from a git+ source, so `uv tool install` shells out to system git.
# Fail fast with an actionable message rather than a cryptic uv error deep in the build.
if ! command -v git >/dev/null 2>&1; then
  echo "spec-kit install: git is required (uv installs Spec Kit from a git tag)." >&2
  echo "spec-kit install: install it first, e.g.  sudo apt-get install -y git" >&2
  exit 1
fi

echo "spec-kit: ensuring a per-user uv is available"
al_uv_ensure || {
  echo "spec-kit install: uv bootstrap failed" >&2
  exit 1
}

echo "spec-kit: installing ${pkg}@${tag} as a uv tool"
al_uv_tool_install "$pkg" "$git_url" "$tag" "3.12" || {
  echo "spec-kit install: uv tool install ${pkg}@${tag} failed" >&2
  exit 1
}

# Version-lock (T-44 parity with al_pb_assert_version): the installed `specify` must
# report the pinned version. `specify` resolves under the agent-owned ~/.local/bin,
# which is on PATH in all six invocation modes.
hash -r
got="$(specify --version 2>&1 | head -1)"
if ! printf '%s' "$got" | grep -qF -- "$ver"; then
  echo "spec-kit install: version-lock failed — pinned=${ver} but 'specify --version': ${got}" >&2
  exit 1
fi

echo "spec-kit: installed (${got})"
echo "spec-kit: scaffold a project with 'specify init <name>'. The project .specify/ is yours —"
echo "spec-kit:   AgentLinux never removes it on 'agentlinux remove spec-kit'."
