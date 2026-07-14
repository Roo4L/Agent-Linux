#!/usr/bin/env bash
set -euo pipefail
# openclaw install.sh — source_kind: script (Phase 47, ASST-01 / ENABLE-04 / ENABLE-05).
#
# Installs OpenClaw — a self-hosted, per-user personal-AI-assistant Gateway — as the
# agent user (npm global into the agent-owned prefix; no root, no /usr/local shim, zero
# EACCES), configures it non-interactively WITHOUT baking any provider key, freezes its
# self-updater so the catalog pin stays authoritative, and (on a host with a usable
# per-user systemd) brings up the Gateway as a per-user daemon via the shared ENABLE-04
# helper plugin/catalog/lib/daemon-lifecycle.sh.
#
# SOURCE (ASST-01): openclaw/openclaw (steipete), MIT, self-hosted, BYO provider key, no
# paid backend. A daemon-class tool is NOT an auto-GO under the source-selection policy —
# reviewed and approved by the maintainer alongside hermes-agent (Phase 48).
#
# source_kind = script (not npm): the recipe does far more than a bare `npm install`
# (onboarding + self-updater freeze + daemon lifecycle), so it owns the whole flow — the
# same modeling choice as spec-kit. `agentlinux upgrade openclaw` re-runs this recipe with
# the new pin; every step here is idempotent, so a re-run cleanly re-pins.
#
# THE DOCKER-vs-REAL SPLIT: `openclaw daemon install` uses systemd --user, which the CI
# container cannot run (masked logind). The recipe probes al_daemon_user_systemd_available
# and only drives the daemon path when it is usable, so `agentlinux install openclaw`
# SUCCEEDS in a container (binary + config, no auto-started daemon) AND on a real host
# (full per-user daemon). The systemd-user lifecycle is QEMU-gated (ADR-007).

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_CATALOG_DIR:?AGENTLINUX_CATALOG_DIR not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

# shellcheck source=../../lib/daemon-lifecycle.sh
source "${AGENTLINUX_CATALOG_DIR}/lib/daemon-lifecycle.sh"

ver="${AGENTLINUX_PINNED_VERSION}"
pkg="openclaw"

# --- 1. install: npm global into the agent-owned prefix (no root) ---
echo "openclaw: installing ${pkg}@${ver} (npm global, agent-owned prefix)"
npm install -g "${pkg}@${ver}"

# --- 2. version-lock (parity with the npm cluster + al_pb_assert_version): the installed
# `openclaw` must report the pinned version. It resolves under the agent-owned npm prefix
# bin, which is on PATH in all six invocation modes. ---
hash -r
got="$(openclaw --version 2>&1 | head -1)"
if ! printf '%s' "$got" | grep -qF -- "$ver"; then
  echo "openclaw install: version-lock failed — pinned=${ver} but 'openclaw --version': ${got}" >&2
  exit 1
fi
echo "openclaw: installed (${got})"

# --- 3. non-interactive onboarding, NO baked secret ---
# `--auth-choice skip` provisions config + workspace WITHOUT any provider credential;
# `--skip-health` returns 0 without waiting on a not-yet-running Gateway. The user adds a
# provider key in-tool later (`openclaw configure` / `openclaw onboard`). Nothing secret
# is written by this recipe.
echo "openclaw: onboarding non-interactively (no provider key baked)"
openclaw onboard --non-interactive --accept-risk --auth-choice skip --skip-health

# --- 4. ENABLE-05 self-updater coexistence: keep the catalog pin authoritative ---
# openclaw's background auto-update defaults to OFF (schema key update.auto.enabled,
# default false) and the runtime only NOTIFIES of new versions — so the pin already holds.
# We materialize it false explicitly (belt-and-suspenders against a user config that
# flipped it or a future default change) and silence the startup update-check, in one
# validated patch (the config schema rejects an unknown key, so a validated write is the
# honest freeze). Best-effort: openclaw is already safe-by-default, so a patch failure must
# not fail the install.
echo "openclaw: freezing the self-updater (catalog pin stays authoritative)"
if ! patch_out=$(printf '%s' '{"update":{"auto":{"enabled":false},"checkOnStart":false}}' \
  | openclaw config patch --stdin 2>&1); then
  # Surface the real error instead of swallowing it — a schema rejection here means the
  # freeze silently no-op'd. Non-fatal because openclaw defaults auto-update off anyway
  # (notify-only), so the pin still holds; the bats ENABLE-05 assertion catches a no-op.
  echo "openclaw: note — update-config patch did not apply (auto-update defaults off): ${patch_out}" >&2
fi

# --- 5. ENABLE-04 daemon lifecycle (real host only; QEMU-gated) ---
if al_daemon_user_systemd_available; then
  echo "openclaw: per-user systemd available — installing + starting the Gateway daemon"
  al_daemon_enable_linger || echo "openclaw: linger not enabled (non-fatal); daemon may not persist across logout" >&2
  if openclaw daemon install && openclaw daemon start; then
    al_daemon_mark openclaw
    openclaw daemon status --no-probe >/dev/null 2>&1 || true # best-effort warm-up; QEMU asserts liveness
    echo "openclaw: Gateway daemon installed + started (per-user systemd)"
  else
    echo "openclaw: note — daemon install/start did not complete; the CLI is installed." >&2
    echo "openclaw:   start it later with 'openclaw daemon install && openclaw daemon start'." >&2
  fi
else
  echo "openclaw: per-user systemd unavailable (container?) — Gateway NOT auto-started."
  echo "openclaw:   run it in the foreground now with 'openclaw gateway run', or re-install"
  echo "openclaw:   on a host with a per-user systemd session for the managed daemon."
fi

# --- 6. BYO provider key instruction (never baked) ---
echo "openclaw: add a provider key in-tool to enable inference — 'openclaw configure'."
echo "openclaw:   OpenClaw is BYO-key; AgentLinux bakes no credential."
