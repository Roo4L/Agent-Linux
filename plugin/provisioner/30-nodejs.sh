#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/provisioner/30-nodejs.sh — Node.js 22 LTS + per-user npm prefix.
#
# Sourced by plugin/bin/agentlinux-install. Inherits strict-mode (errexit /
# nounset / pipefail), the ERR trap, and the tee redirect to
# /var/log/agentlinux-install.log from the entrypoint; this fragment therefore
# MUST NOT set its own strict-mode flags.
#
# Requirements: RT-01 (Node.js 22 LTS installed, `node --version` returns
# v22.x) and RT-04 (~agent/.npmrc carries `prefix=/home/agent/.npm-global`;
# belt-and-braces NPM_CONFIG_PREFIX env var is written by 40-path-wiring.sh
# for systemd/cron resilience, Pitfall 5).
#
# Ordering: runs AFTER 10-agent-user.sh (needs /home/agent owned by agent:agent)
# and BEFORE 40-path-wiring.sh — numeric dispatch 10 → 30 → 40. 40-path-wiring
# prepends /home/agent/.npm-global/bin to every PATH literal backed by the
# prefix dir this provisioner creates.
#
# Every state mutation routes through plugin/lib/idempotency.sh primitives
# (ensure_dir / ensure_line_in_file) per agentlinux-installer SKILL §4.
# Re-runs MUST converge (INST-02).

log_info "30-nodejs: starting"

# Phase 13 (REUSE-02) — dispatch on reuse::nodejs_decision before any state
# mutation. When at least one detected Node entry has VERSION matching ^v?22\.
# AND install_user_can_write_prefix=true, skip both the NodeSource apt install
# AND the per-user .npmrc prefix bootstrap. 40-path-wiring.sh still runs
# unconditionally and writes PATH artefacts (NPM_CONFIG_PREFIX in
# /etc/agentlinux.env surfaces the prefix to systemd/cron consumers — Pitfall 5
# belt-and-braces remains in force regardless of REUSE branch).
#
# No remediate branch here — REMEDIATE-01 lives in the npm-prefix layer
# (Phase 14), NOT the Node-install layer. CONTEXT.md Area 1 Q2: "there's no
# Remediate path for 'no compatible Node', just 'install one'". The case
# enumerates {reuse, create} explicitly; the dispatch shape is locked.
# Phase 14 (Plan 14-01): provisioner reads pre-resolved RESOLUTIONS[node]
# instead of calling reuse::nodejs_decision directly. The Node-install layer
# has only two tokens (reuse|create per CONTEXT.md Area 1 Q2 — REMEDIATE-01
# lives in the npm-prefix layer below, NOT here). The case enumerates the
# remediate/bail tokens defensively for forward-compat with future plans.
case "${RESOLUTIONS[node]:-create}" in
  reuse)
    reuse::log_nodejs_reuse
    log_info "30-nodejs: REUSE branch — skipping apt-get install nodejs + .npmrc bootstrap"
    # Defensive log: even when REUSE-02 fires on per-Node-binary writability,
    # the ACTIVE npm prefix (DET-03) may diverge from the reused Node's prefix.
    # Phase 14 REMEDIATE-01 handles the divergence via the npm-prefix dispatch
    # at the end of this file — surface as a warn for transcript visibility.
    if ! detect::npm_prefix_writable_by_install_user; then
      log_warn "30-nodejs: REUSE-02 succeeded but detect::npm_prefix_writable_by_install_user is false — REMEDIATE-01 npm-prefix dispatch follows"
    fi
    # Fall through to the npm-prefix dispatch at the end of the file (which
    # handles REMEDIATE-01 separately). Use a sentinel to skip the CREATE
    # machinery below.
    NODE_REUSED=true
    ;;
  create)
    # Fall through to the existing CREATE path (unchanged from v0.3.0).
    NODE_REUSED=false
    ;;
  remediate | bail)
    # No remediate token at the Node-install layer per CONTEXT.md Area 1 Q2.
    # Defensive arm — if a future plan extends the surface, dispatch lands here.
    # bail) is UNREACHABLE: flush_bails_or_continue should have exited 65.
    log_error "30-nodejs: unexpected RESOLUTIONS[node] = ${RESOLUTIONS[node]:-unset} — no remediate/bail token defined at Node-install layer"
    return 1
    ;;
esac

if [[ "${NODE_REUSED:-false}" == "true" ]]; then
  # Skip the CREATE-path Steps 1-6 and jump straight to the npm-prefix
  # dispatch at the bottom. Use a block-skip rather than an early return so
  # the npm-prefix REMEDIATE-01 dispatch still fires on the REUSE branch.
  : "skipping CREATE path (Node REUSE) — npm-prefix dispatch at end of file still runs"
else

# Step 1: pre-reqs for NodeSource's setup_22.x script.
# NodeSource's setup script installs these itself, but we pre-install for
# installer-log visibility (per D-02 + Research §Open Questions Q2).
# DEBIAN_FRONTEND=noninteractive prevents dpkg conffile prompts in CI
# (Pitfall 6). `apt-get update` is required first on hosts whose
# /var/lib/apt/lists is empty — Ubuntu Docker base images strip lists after
# initial install and cloud images ship with stale lists. Idempotent.
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  curl gnupg ca-certificates apt-transport-https

# Step 2: idempotent NodeSource repo add.
# Pitfall 1 dual-gate: check BOTH the NEW deb822 filename (`nodesource.sources`)
# AND the legacy (`nodesource.list`) so a re-run on a partially-migrated host
# short-circuits.
# T-03-01 mitigation: curl-pipe-bash acceptable per agentlinux-installer SKILL §6
# ("pinned-URL trusted upstream"); NodeSource is the ADR-005-blessed upstream.
# HTTPS + `curl -f` cert-verify is the primary integrity control; ongoing
# package integrity comes from the GPG-signed apt repo the script installs.
# Script-body SHA-256 is NOT verified (NodeSource publishes no .sha256) —
# accepted trade-off per ADR-005.
# T-03-04 mitigation: the setup script rm -fs both legacy and modern filenames
# before recreating them, so even if our gate misses (stale nodesource.list)
# it self-heals without byte drift; our gate just prevents the wasted re-run.
if [[ -f /etc/apt/sources.list.d/nodesource.sources ]] \
  || [[ -f /etc/apt/sources.list.d/nodesource.list ]]; then
  log_info "NodeSource apt repo already configured (gate: nodesource.sources/list)"
else
  log_info "NodeSource apt repo absent — running setup_22.x"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
fi

# Step 3: install nodejs. Idempotent — apt-get install is a no-op if the
# installed version satisfies the apt-pinning policy (Priority 600, set by
# setup_22.x in /etc/apt/preferences.d/nodejs).
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs

# Step 4: post-install verify (RT-01). Hard-fail if major < 22 — means the
# pinning broke or someone installed Ubuntu's built-in nodejs first.
# `return 1` (not `exit 1`) — this provisioner is SOURCED, so `return` trips
# the entrypoint's strict-mode ERR trap with correct src:line attribution
# (pattern from 10-agent-user.sh).
node_major=$(node --version 2>/dev/null | sed 's/^v\([0-9]*\)\..*$/\1/')
if [[ "${node_major:-0}" -lt 22 ]]; then
  log_error "node v${node_major:-unset} installed but v22 LTS required (RT-01)"
  return 1
fi
log_info "Node.js $(node --version) installed (RT-01 — v22 LTS)"

# Step 5: per-user npm prefix layout (RT-04).
# ensure_dir creates OR re-asserts mode+ownership on re-run, correcting any
# out-of-band drift. bin/ and lib/ subdirs created proactively agent-owned so
# `npm install -g` never has to create them (defense against Pitfall 4
# root-owned-dir races, per D-03 [CONTEXT Per-User npm Prefix Layout]).
ensure_dir /home/agent/.npm-global 0755 agent:agent
ensure_dir /home/agent/.npm-global/bin 0755 agent:agent
ensure_dir /home/agent/.npm-global/lib 0755 agent:agent

# Step 6: write ~agent/.npmrc with the prefix line (RT-04).
# Atomic create-if-absent (install /dev/null), then idempotent
# grep-before-append via ensure_line_in_file.
# T-03-02 mitigation: a raw blind-append primitive would duplicate the line on
# every re-run; ensure_line_in_file's -Fxq grep-then-append produces zero diff.
if [[ ! -f /home/agent/.npmrc ]]; then
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
fi
ensure_line_in_file 'prefix=/home/agent/.npm-global' /home/agent/.npmrc
# ensure_line_in_file runs with root's umask and doesn't chown — re-assert
# agent:agent ownership + 0644 so subsequent agent edits aren't denied.
# Same post-primitive chown pattern as 10-agent-user.sh's DOC-02 block
# (see STATE.md "New decisions from Plan 02-03 execution").
chown agent:agent /home/agent/.npmrc
chmod 0644 /home/agent/.npmrc
log_info "wrote ~agent/.npmrc (prefix=/home/agent/.npm-global — RT-04)"

fi # end NODE_REUSED guard — CREATE-path block

# Phase 14 (Plan 14-01 — REMEDIATE-01): npm-prefix layer dispatch via
# RESOLUTIONS. Runs UNCONDITIONALLY after the Node-install / Node-reuse split
# above — REMEDIATE-01 lives in the npm-prefix layer per CONTEXT.md Area 1 Q1,
# orthogonal to whether Node itself was reused or freshly installed.
#
# Tokens (per reuse::npm_prefix_decision in plugin/lib/reuse/nodejs.sh):
#   reuse     — DETECT_NPM_PREFIX_USER_WRITABLE=true; nothing to do.
#   create    — DETECT_NPM_PREFIX_SECTION_STATUS=absent; the CREATE path above
#               already bootstrapped /home/agent/.npm-global (if Node was
#               freshly installed) or this is a noop (defensive — REUSE+absent
#               is unusual but not catastrophic).
#   remediate — npm prefix exists but install user cannot write to it. Gate
#               already passed (--yes confirmed). Dispatch to stub (Plan 14-02
#               replaces with chown/rebase strategy from CONTEXT.md Area 2).
#   bail      — UNREACHABLE; flush_bails_or_continue would have exited 65.
case "${RESOLUTIONS[npm-prefix]:-create}" in
  reuse)
    reuse::log_npm_prefix_reuse
    ;;
  create)
    # CREATE path above handled npm install + /home/agent/.npm-global
    # bootstrap when needed. Nothing further here.
    :
    ;;
  remediate)
    # Gate passed (YES_FLAG=true confirmed in collect_all_decisions).
    # Plan 14-02 (REMEDIATE-01): chown or rebase per CONTEXT.md Area 2 — the
    # strategy selector chooses chown (prefix under home + trivially salvageable)
    # vs rebase (everything else: system path / non-trivially-salvageable).
    remediate::nodejs::chown_or_rebase || return 1
    ;;
  bail)
    log_error "30-nodejs: unreachable bail arm — flush_bails_or_continue should have gated this"
    return 1
    ;;
esac

log_info "30-nodejs: done"
