#!/usr/bin/env bash
# plugin/provisioner/30-nodejs.sh — Node.js 22 LTS + per-user npm prefix.
#
# Sourced by plugin/bin/agentlinux-install. Inherits strict-mode (errexit /
# nounset / pipefail), the ERR trap, and the tee redirect to
# /var/log/agentlinux-install.log from the entrypoint; this fragment therefore
# MUST NOT set its own strict-mode flags.
#
# Requirements satisfied:
#   RT-01 — Node.js 22 LTS installed; `node --version` returns v22.x
#   RT-04 — ~agent/.npmrc carries `prefix=/home/agent/.npm-global`
#           (belt-and-braces NPM_CONFIG_PREFIX env var is written by
#           40-path-wiring.sh for systemd/cron resilience, Pitfall 5).
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

# Step 1: pre-reqs for NodeSource's setup_22.x script.
# NodeSource's setup script installs these itself, but we pre-install for
# installer-log visibility (per D-02 [CONTEXT Node.js Install Path] + Research
# §Open Questions Q2 recommendation). DEBIAN_FRONTEND=noninteractive prevents
# dpkg from prompting on any conffile change in the CI Docker harness
# (Pitfall 6 mitigation).
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

log_info "30-nodejs: done"
