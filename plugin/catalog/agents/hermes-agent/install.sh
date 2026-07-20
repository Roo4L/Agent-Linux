#!/usr/bin/env bash
set -euo pipefail
# hermes-agent install.sh — source_kind: script (Phase 48, ASST-02 / reuses ENABLE-04).
#
# Installs Hermes Agent — Nous Research's self-hosted personal-AI-assistant with a per-user
# messaging Gateway — as the agent user (no root, no /usr/local shim, zero EACCES) via the
# OFFICIAL installer, pinned to an immutable commit, non-interactively and WITHOUT baking any
# provider key. The Gateway is then brought up as a per-user daemon through the shared
# ENABLE-04 helper plugin/catalog/lib/daemon-lifecycle.sh (same lifecycle as openclaw).
#
# SOURCE (ASST-02): NousResearch/hermes-agent, MIT, open source, self-hosted, BYO provider
# key, no paid backend. The OFFICIAL channel is the curl installer at
# hermes-agent.nousresearch.com (NOT the unofficial npm `hermes-agent` bridge). A
# daemon-class + third-party-installer tool is NOT an auto-GO under the source policy —
# reviewed and approved by the maintainer alongside openclaw (Phase 47).
#
# SUPPLY-CHAIN POSTURE (honest): the bootstrap install.sh is fetched live over HTTPS with no
# script-level checksum — the realistic bar for an official third-party installer (rustup/uv
# shape). Two mitigations: (1) we DOWNLOAD the installer to a temp file and run it explicitly
# (never a blind `curl | bash`), over pinned TLS; (2) we pin the actual CODE to an immutable
# git commit via the installer's purpose-built `--commit` flag — a content-addressed SHA
# cannot be re-pointed, a stronger anchor than a mutable tag. As a NON-ROOT install the
# installer targets ~/.hermes + ~/.local/bin/hermes (agent-owned, no /usr/local shim).
#
# source_kind = script: the recipe owns the whole flow (pinned installer + daemon lifecycle),
# the same modeling as openclaw/spec-kit. `agentlinux upgrade hermes-agent` re-runs it with a
# new pin; the installer is idempotent (detects an existing checkout and updates it).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/daemon-lifecycle.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/daemon-lifecycle.sh"

ver="${AGENTLINUX_PINNED_VERSION}" # calendar version = the git tag v${ver}

# The catalog pin v2026.6.19 peels to this immutable commit (resolved via `git ls-remote`).
# Pinning to the SHA (not the tag) means a re-pointed tag cannot change what we install; the
# version-lock below still catches a mismatch. Keep this in lockstep with pinned_version.
HERMES_COMMIT="2bd1977d8fad185c9b4be47884f7e87f1add0ce3"
INSTALLER_URL="https://hermes-agent.nousresearch.com/install.sh"

# Pin the install location explicitly so install and uninstall share ONE source of truth.
# As a non-root install the installer defaults HERMES_HOME to ~/.hermes; exporting it keeps
# uninstall.sh's hardcoded ~/.hermes/hermes-agent in lockstep even if a future upstream
# changes that default or honors a pre-existing env value.
export HERMES_HOME="${AGENTLINUX_AGENT_HOME}/.hermes"

# The installer clones the repo, so system git is a hard prerequisite. Fail fast with an
# actionable message rather than a cryptic error deep in the installer.
if ! command -v git >/dev/null 2>&1; then
  echo "hermes-agent install: git is required (the installer clones the repo)." >&2
  echo "hermes-agent install: install it first, e.g.  sudo apt-get install -y git" >&2
  exit 1
fi

# --- 1. install: download the official installer, then run it PINNED + non-interactive ---
# --non-interactive skips the two user-input stages (setup=API keys, gateway=service), so
# NOTHING secret is written and no gateway service is auto-created — we drive the daemon via
# ENABLE-04 below. Download-then-run (never `curl | bash`) over pinned TLS.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "hermes-agent: fetching the official installer (pinned commit ${HERMES_COMMIT})"
curl -fsSL --proto '=https' --tlsv1.2 "$INSTALLER_URL" -o "$tmp/install.sh"

echo "hermes-agent: installing v${ver} (no root, no baked key)"
bash "$tmp/install.sh" --commit "$HERMES_COMMIT" --non-interactive

# --- 2. version-lock: the installed `hermes --version` (which prints "… (2026.6.19) … local
# <sha>") must report BOTH the pinned calendar version AND the pinned commit's short SHA.
# Binding the SHA — not just the calendar version — anchors the installed CODE to the
# immutable pin, closing the gap where a tampered bootstrap installs a DIFFERENT commit that
# still reports the same calendar version. `hermes` resolves under the agent-owned
# ~/.local/bin, on PATH in all six invocation modes. ---
hash -r
got="$(hermes --version 2>&1 | head -1)"
short_sha="${HERMES_COMMIT:0:8}"
if ! printf '%s' "$got" | grep -qF -- "$ver"; then
  echo "hermes-agent install: version-lock failed — pinned=${ver} but 'hermes --version': ${got}" >&2
  exit 1
fi
if ! printf '%s' "$got" | grep -qF -- "$short_sha"; then
  echo "hermes-agent install: commit-lock failed — pinned commit ${short_sha} not in 'hermes --version': ${got}" >&2
  exit 1
fi
echo "hermes-agent: installed (${got})"

# --- 3. ENABLE-04 daemon lifecycle (real host only; QEMU-gated) ---
# The Gateway is a per-user systemd service (`hermes gateway install`), which the CI
# container cannot run (masked logind). Probe first so install succeeds in a container
# (config-only) AND on a real host (managed daemon). Drive daemon commands with stdin from
# /dev/null so a non-interactive run never blocks on a prompt.
if al_daemon_user_systemd_available; then
  echo "hermes-agent: per-user systemd available — installing + starting the Gateway daemon"
  al_daemon_enable_linger || echo "hermes-agent: linger not enabled (non-fatal); daemon may not persist across logout" >&2
  if hermes gateway install </dev/null && hermes gateway start </dev/null; then
    al_daemon_mark hermes-agent
    echo "hermes-agent: Gateway daemon installed + started (per-user systemd)"
  else
    echo "hermes-agent: note — gateway install/start did not complete; the CLI is installed." >&2
    echo "hermes-agent:   start it later with 'hermes gateway install && hermes gateway start'." >&2
  fi
else
  echo "hermes-agent: per-user systemd unavailable (container?) — Gateway NOT auto-started."
  echo "hermes-agent:   run it in the foreground now with 'hermes gateway run', or re-install"
  echo "hermes-agent:   on a host with a per-user systemd session for the managed daemon."
fi

# --- 4. BYO provider key instruction (never baked) ---
echo "hermes-agent: add a provider key + configure a messaging platform in-tool — 'hermes setup'."
echo "hermes-agent:   Hermes is BYO-key; AgentLinux bakes no credential."
