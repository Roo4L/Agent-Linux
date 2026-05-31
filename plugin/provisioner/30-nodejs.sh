#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/provisioner/30-nodejs.sh — Node.js 22 LTS + per-user npm prefix.
#
# Sourced by agentlinux-install. Inherits strict-mode, the ERR trap, and the
# tee redirect — MUST NOT set its own strict-mode flags.
#
# Satisfies RT-01 (Node.js 22 LTS) and RT-04 (~agent/.npmrc carries
# prefix=/home/agent/.npm-global; the belt-and-braces NPM_CONFIG_PREFIX env var
# is written by 40-path-wiring.sh for systemd/cron). Runs after 10-agent-user.sh
# and before 40-path-wiring.sh. Mutations route through idempotency.sh
# primitives so re-runs converge (INST-02).

log_info "30-nodejs: starting"

# Dispatch on the pre-resolved RESOLUTIONS[node] token. On REUSE (a detected
# Node matches ^v?22\. and the install user can write the prefix), skip the
# NodeSource install + .npmrc bootstrap. The Node-install layer has only two
# real tokens (reuse|create) — REMEDIATE-01 lives in the npm-prefix layer at
# the end of this file, not here; remediate/bail are enumerated defensively.
case "${RESOLUTIONS[node]:-create}" in
  reuse)
    reuse::log_nodejs_reuse
    log_info "30-nodejs: REUSE branch — skipping apt-get install nodejs + .npmrc bootstrap"
    # The active npm prefix may still diverge from the reused Node's prefix;
    # the npm-prefix dispatch below (REMEDIATE-01) handles it — warn for
    # transcript visibility.
    if ! detect::npm_prefix_writable_by_install_user; then
      log_warn "30-nodejs: REUSE-02 succeeded but detect::npm_prefix_writable_by_install_user is false — REMEDIATE-01 npm-prefix dispatch follows"
    fi
    NODE_REUSED=true
    ;;
  create)
    NODE_REUSED=false
    ;;
  remediate | bail)
    # No remediate/bail token at this layer; defensive arm. bail is unreachable.
    log_error "30-nodejs: unexpected RESOLUTIONS[node] = ${RESOLUTIONS[node]:-unset} — no remediate/bail token defined at Node-install layer"
    return 1
    ;;
esac

if [[ "${NODE_REUSED:-false}" == "true" ]]; then
  # Block-skip the CREATE-path steps (not an early return) so the npm-prefix
  # REMEDIATE-01 dispatch at the end of the file still fires on REUSE.
  : "skipping CREATE path (Node REUSE) — npm-prefix dispatch at end of file still runs"
else

# Step 1: pre-reqs for NodeSource's setup_22.x. The setup script installs these
# itself, but we pre-install for installer-log visibility. apt-get update first
# — /var/lib/apt/lists may be empty (Docker base images strip it; cloud images
# ship stale lists). Idempotent.
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl gnupg ca-certificates apt-transport-https

# Step 2: idempotent NodeSource repo add. Dual-gate on both the deb822
# (nodesource.sources) and legacy (nodesource.list) filenames so a re-run on a
# partially-migrated host short-circuits.
# Security: curl-pipe-bash from the pinned ADR-005 upstream; HTTPS + curl -f
# cert-verify is the integrity control, with ongoing integrity from the
# GPG-signed apt repo. Script-body SHA-256 is not verified (NodeSource publishes
# none) — accepted per ADR-005. The setup script rm -fs both filenames before
# recreating them, so even a missed gate self-heals without byte drift.
if [[ -f /etc/apt/sources.list.d/nodesource.sources ]] \
  || [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
  log_info "NodeSource apt repo already configured (gate: nodesource.sources/list)"
else
  log_info "NodeSource apt repo absent — running setup_22.x"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
fi

# Step 3: install nodejs. Idempotent — no-op if the installed version satisfies
# the apt-pinning policy set by setup_22.x.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs

# Step 4: post-install verify (RT-01). Hard-fail if major < 22 (pinning broke
# or Ubuntu's built-in nodejs was installed first). `return 1` not `exit 1` —
# this fragment is sourced, so return trips the ERR trap with correct src:line.
node_major=$(node --version 2>/dev/null | sed 's/^v\([0-9]*\)\..*$/\1/')
if [[ "${node_major:-0}" -lt 22 ]]; then
  log_error "node v${node_major:-unset} installed but v22 LTS required (RT-01)"
  return 1
fi
log_info "Node.js $(node --version) installed (RT-01 — v22 LTS)"

# Step 5: per-user npm prefix layout (RT-04). bin/ and lib/ are created
# proactively agent-owned so `npm install -g` never races to create them as
# root.
#
# On RESOLUTIONS[npm-prefix]=reuse-with-warning (TTY operator declined the chown
# remediation), skip the ensure_dir chown so the decline is honored — otherwise
# the CREATE-path ensure_dir would silently chown the prefix back to agent.
if [[ "${RESOLUTIONS[npm-prefix]:-}" != "reuse-with-warning" ]]; then
  ensure_dir /home/agent/.npm-global 0755 agent:agent
  ensure_dir /home/agent/.npm-global/bin 0755 agent:agent
  ensure_dir /home/agent/.npm-global/lib 0755 agent:agent
else
  # 50-registry-cli's later symlink will ensure_dir bin/ (chowning it to agent)
  # — accepted, since the symlink needs an agent-owned bin/; the decline marker
  # already records that the parent prefix was not touched.
  log_warn "30-nodejs: SKIPPING ensure_dir on /home/agent/.npm-global (RESOLUTIONS[npm-prefix]=reuse-with-warning; user declined REMEDIATE-01)"
fi

# Step 6: write ~agent/.npmrc with the prefix line (RT-04). Atomic
# create-if-absent, then ensure_line_in_file's grep-before-append (zero diff on
# re-run; a blind append would duplicate the line).
if [[ ! -f /home/agent/.npmrc ]]; then
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
fi
ensure_line_in_file 'prefix=/home/agent/.npm-global' /home/agent/.npmrc
# ensure_line_in_file runs with root's umask and doesn't chown — re-assert
# agent:agent + 0644 so subsequent agent edits aren't denied.
chown agent:agent /home/agent/.npmrc
chmod 0644 /home/agent/.npmrc
log_info "wrote ~agent/.npmrc (prefix=/home/agent/.npm-global — RT-04)"

fi # end NODE_REUSED guard — CREATE-path block

# npm-prefix layer dispatch (REMEDIATE-01). Runs unconditionally after the
# Node-install/reuse split above — orthogonal to whether Node was reused or
# freshly installed.
#   reuse     — prefix writable by the install user; nothing to do.
#   create    — the CREATE path above bootstrapped the prefix (or no-op).
#   remediate — prefix exists but the user can't write it. Gate already passed
#               (--yes confirmed). chown_or_rebase per the strategy selector.
#   bail      — unreachable; flush_bails_or_continue would have exited 65.
case "${RESOLUTIONS[npm-prefix]:-create}" in
  reuse)
    reuse::log_npm_prefix_reuse
    ;;
  create)
    :
    ;;
  remediate)
    remediate::nodejs::chown_or_rebase || return 1
    ;;
  reuse-with-warning)
    # TTY operator declined chown/rebase; leave ownership as-is and log a marker.
    log_warn "[REUSE-WARN] component=npm-prefix decline_reason=${DECLINED_COMPONENTS[npm-prefix]:-unknown} — skipped (user declined remediation; manual fix needed). npm-global ownership unchanged."
    ;;
  bail)
    log_error "30-nodejs: unreachable bail arm — flush_bails_or_continue should have gated this"
    return 1
    ;;
esac

log_info "30-nodejs: done"
