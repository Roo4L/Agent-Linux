# tests/bats/helpers/brownfield.bash
# Plan 13-02 brownfield fixture helper.
#
# setup_brownfield_host prepares the Docker container for the REUSE-03 E2E
# smoke @test. Invoked INSIDE a bats @test BEFORE the @test runs `bash
# /opt/agentlinux-src/plugin/bin/agentlinux-install`. The helper:
#   1. Purges any existing AgentLinux state (idempotent --purge)
#   2. Manually creates the agent user (useradd -m -s /bin/bash agent)
#   3. Drops a NOPASSWD-for-apt-only sudoers fragment
#   4. Ensures NodeSource Node 22 is present (skip if dpkg shows installed)
#   5. Installs claude-code via the official native installer at the
#      canonical path ~/.local/bin/claude
#
# FIXTURE-CHOICE DISCLOSURE: this helper installs claude via the official
# native installer (~/.local/bin/claude — the catalog canonical path for
# REUSE-03). This exercises the CANONICAL-PATH-MATCH case for REUSE-03,
# which fires `reuse`.
#
# The PATH-MISMATCH case (claude installed via `npm install -g
# @anthropic-ai/claude-code` at ~/.npm-global/bin/claude — DIFFERENT path
# → REUSE-03 path-match check FAILS, emits `remediate` not `reuse`) is
# Phase 14 REMEDIATE-04 territory. Do NOT "improve" this helper to use
# npm without ALSO updating the REUSE-03 assertions to expect `remediate`.
#
# Design notes:
#   - NO `set -euo pipefail` — this file is SOURCED via `load 'helpers/brownfield'`
#     and strict-mode inside a sourced library breaks bats TAP output.
#   - Functions emit diagnostic to FD 3 (the bats detail channel) via the
#     log_brownfield helper so transcripts are visible without contaminating
#     `$output` of subsequent `run` invocations.
#   - Idempotent on re-run: `useradd` is wrapped in `id -u agent` guard;
#     curl-pipe-bash installer overwrites in place.

# log_brownfield <message>
# Emits to FD 3 (bats detail channel) with a stable [brownfield] prefix so
# the brownfield smoke @test can awk-split the install log on the "setup
# complete" marker (used to filter out the npm install that ran DURING setup
# from the assertions on the installer's own transcript). Falls back to
# stderr when FD 3 is not open (helper sourced outside bats — e.g. ad-hoc
# debug sessions); the `2>/dev/null || true` guards against `set -e` callers
# tripping when the FD-3 write fails.
log_brownfield() {
  if { true >&3; } 2>/dev/null; then
    printf '# [brownfield] %s\n' "$*" >&3
  else
    printf '# [brownfield] %s\n' "$*" >&2
  fi
}

# setup_brownfield_host
# Prepares the container per CONTEXT.md Area 2 Q3. MUST be called inside a
# bats @test body BEFORE invoking the AgentLinux installer; the @test then
# asserts the installer detects + reuses the pre-populated state.
setup_brownfield_host() {
  log_brownfield "purging any existing AgentLinux state (idempotent)"
  # --purge tears down /opt/agentlinux, removes the agent user (userdel -r),
  # and deletes the /etc/sudoers.d/agentlinux drop-in. Node stays (purge does
  # not default to --remove-nodejs). Run as root; bats runs as root in the
  # container per the harness contract. Suppress output — the purge transcript
  # is verbose and not load-bearing for the @test.
  bash /opt/agentlinux-src/plugin/bin/agentlinux-install --purge >/dev/null 2>&1 || true

  # Step 1: Create the agent user manually (NOT via 10-agent-user.sh — that's
  # exactly what we're testing REUSE-01 skips).
  if ! id -u agent >/dev/null 2>&1; then
    log_brownfield "creating agent user (useradd -m -s /bin/bash)"
    useradd -m -s /bin/bash agent
  fi

  # Step 2: NOPASSWD-for-apt sudoers fragment (NARROWER than ADR-012's full
  # sudo grant — exercises REUSE-01 "at least apt" check per CONTEXT.md Area 1
  # Q1 amendment). visudo gate ensures we never install a syntactically-broken
  # sudoers file (would lock root out of sudo).
  if [[ ! -f /etc/sudoers.d/local-agent-apt ]]; then
    log_brownfield "installing NOPASSWD-for-apt sudoers fragment"
    local tmp
    tmp=$(mktemp)
    printf 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt\n' >"$tmp"
    if visudo -cf "$tmp" >/dev/null; then
      install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/local-agent-apt
    fi
    rm -f "$tmp"
  fi

  # Step 3: NodeSource Node 22 (skip if already installed via dpkg).
  if ! dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q "install ok installed"; then
    log_brownfield "installing NodeSource Node 22 (apt-get install -y nodejs)"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1
  fi

  # Step 4: Install claude-code as the agent user via the official native
  # installer. Lands at ~/.local/bin/claude — the catalog canonical path
  # (PATH-MATCH case for REUSE-03). Version 2.1.98 matches the catalog pin
  # and satisfies the compatibility_window >=2.0.0 <3.0.0 set by Task 1.
  if [[ ! -x /home/agent/.local/bin/claude ]]; then
    log_brownfield "installing claude-code 2.1.98 via official native installer (canonical path)"
    sudo -u agent -H bash --login -c \
      'curl -fsSL https://claude.ai/install.sh | bash -s 2.1.98' >/dev/null 2>&1
  fi

  log_brownfield "setup complete"
}

# -----------------------------------------------------------------------------
# Plan 14-02 brownfield fixtures for REMEDIATE-01/02/03 handler @tests.
#
# Each fixture targets ONE remediate class; all OTHER components remain
# REUSE-compatible so the @test asserts only the targeted remediation surfaces
# (fixture isolation invariant carried from Plan 14-01).
#
# Convention: every fixture starts with `bash $INSTALLER --purge` so the
# fixture is a deterministic delta from an empty post-purge state, then builds
# up the canonical sudoers + agent user + Node 22 baseline, then introduces
# the one defect the fixture targets.
# -----------------------------------------------------------------------------

# _brownfield_baseline
# Internal helper. Lays down a host state where REUSE-01 / REUSE-02 / REUSE-03b
# are ALL satisfied:
#   - --purge tears down any prior install
#   - agent user (bash + writable home)
#   - canonical ADR-012 sudoers drop-in
#   - Node 22 from NodeSource (skip if dpkg shows installed)
#   - ~agent/.npm-global + ~agent/.npmrc pointing at it (agent-writable so
#     reuse::npm_prefix_decision returns `reuse`, NOT `remediate`).
#
# Each Plan-14-02 fixture below mutates EXACTLY ONE component on top of this
# baseline to trigger its targeted remediate handler — fixture-isolation
# invariant carried from Plan 14-01.
_brownfield_baseline() {
  bash "$INSTALLER" --purge >/dev/null 2>&1 || true
  useradd -m -s /bin/bash agent >/dev/null 2>&1 || usermod -s /bin/bash agent
  local tmp
  tmp=$(mktemp)
  printf 'agent ALL=(ALL) NOPASSWD: ALL\n' >"$tmp"
  install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/agentlinux
  rm -f "$tmp"
  if ! dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q "install ok installed"; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null 2>&1
  fi
  # npm-prefix REUSE prep: without an agent-writable prefix + ~agent/.npmrc
  # pointing at it, npm config get prefix falls back to /usr (root-owned) →
  # reuse::npm_prefix_decision returns remediate → bail without --yes. The
  # fixtures that target REMEDIATE-02/-03 must NOT trip the npm-prefix bail,
  # so seed the canonical /home/agent/.npm-global + ~agent/.npmrc here.
  install -d -m 0755 -o agent -g agent /home/agent/.npm-global
  install -d -m 0755 -o agent -g agent /home/agent/.npm-global/bin
  install -d -m 0755 -o agent -g agent /home/agent/.npm-global/lib
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
  echo "prefix=/home/agent/.npm-global" >>/home/agent/.npmrc
  chown agent:agent /home/agent/.npmrc
}

# setup_brownfield_for_remediate_01_chown
# Targets REMEDIATE-01 chown branch. Lays the prefix UNDER /home/agent (so the
# under-home check passes) and ensures it is trivially salvageable (only
# allowlisted entries — bin/, lib/, share/, etc/ — all empty, plus the
# package.json scaffold npm bootstraps). Owns it root-and-friends so
# DETECT_NPM_PREFIX_USER_WRITABLE=false → reuse::npm_prefix_decision returns
# remediate; the strategy selector picks `chown`.
setup_brownfield_for_remediate_01_chown() {
  _brownfield_baseline
  rm -rf /home/agent/.npm-global
  install -d -m 0755 -o root -g root /home/agent/.npm-global
  install -d -m 0755 -o root -g root /home/agent/.npm-global/bin
  install -d -m 0755 -o root -g root /home/agent/.npm-global/lib
  # .npmrc points at the prefix so DETECT_NPM_PREFIX_SECTION_STATUS=present
  # and the effective_prefix resolves to /home/agent/.npm-global.
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
  echo "prefix=/home/agent/.npm-global" >>/home/agent/.npmrc
  chown agent:agent /home/agent/.npmrc
}

# setup_brownfield_for_remediate_01_rebase
# Targets REMEDIATE-01 rebase branch via the "prefix outside user home" arm:
# the .npmrc points at /usr/local/agentlinux-old (NOT under /home/agent) so
# the under-home check FAILS and the strategy selector picks `rebase`.
# Also leaves the actual /home/agent/.npm-global ABSENT so the rebase has to
# create it from scratch.
setup_brownfield_for_remediate_01_rebase() {
  _brownfield_baseline
  rm -rf /home/agent/.npm-global
  # Create a fake old prefix under /usr/local (root-owned, not under home).
  install -d -m 0755 -o root -g root /usr/local/agentlinux-old
  install -d -m 0755 -o root -g root /usr/local/agentlinux-old/bin
  install -d -m 0755 -o root -g root /usr/local/agentlinux-old/lib
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
  echo "prefix=/usr/local/agentlinux-old" >>/home/agent/.npmrc
  chown agent:agent /home/agent/.npmrc
}

# setup_brownfield_for_remediate_01_rebase_with_module
# As above, but pre-populates one user-installed module under the OLD prefix's
# lib/node_modules/ so _enumerate_modules will pick it up and the rebase has
# something to migrate.
setup_brownfield_for_remediate_01_rebase_with_module() {
  setup_brownfield_for_remediate_01_rebase
  install -d -m 0755 -o root -g root /usr/local/agentlinux-old/lib/node_modules
  install -d -m 0755 -o root -g root /usr/local/agentlinux-old/lib/node_modules/lodash
  cat >/usr/local/agentlinux-old/lib/node_modules/lodash/package.json <<'JSON'
{ "name": "lodash", "version": "4.17.21" }
JSON
  chown -R root:root /usr/local/agentlinux-old/lib/node_modules/lodash
}

# setup_brownfield_for_remediate_01_rebase_with_catalog_module
# Same as rebase_with_module but the pre-existing module is a CATALOG agent
# (get-shit-done-cc) — the migration loop must FILTER IT OUT (Area 2 Q3).
setup_brownfield_for_remediate_01_rebase_with_catalog_module() {
  setup_brownfield_for_remediate_01_rebase
  install -d -m 0755 -o root -g root /usr/local/agentlinux-old/lib/node_modules
  install -d -m 0755 -o root -g root /usr/local/agentlinux-old/lib/node_modules/get-shit-done-cc
  cat >/usr/local/agentlinux-old/lib/node_modules/get-shit-done-cc/package.json <<'JSON'
{ "name": "get-shit-done-cc", "version": "1.37.1" }
JSON
  chown -R root:root /usr/local/agentlinux-old/lib/node_modules/get-shit-done-cc
}

# setup_brownfield_for_remediate_01_chown_blocked
# T-14-03 test case: prefix is under /home/agent (under-home passes) BUT a
# third-party module is pre-installed under lib/node_modules/. The strategy
# selector MUST flip to `rebase` because trivially-salvageable returns false.
# Asserts the airtight allowlist gate.
setup_brownfield_for_remediate_01_chown_blocked() {
  _brownfield_baseline
  rm -rf /home/agent/.npm-global
  install -d -m 0755 -o root -g root /home/agent/.npm-global
  install -d -m 0755 -o root -g root /home/agent/.npm-global/bin
  install -d -m 0755 -o root -g root /home/agent/.npm-global/lib
  install -d -m 0755 -o root -g root /home/agent/.npm-global/lib/node_modules
  install -d -m 0755 -o root -g root /home/agent/.npm-global/lib/node_modules/some-user-pkg
  cat >/home/agent/.npm-global/lib/node_modules/some-user-pkg/package.json <<'JSON'
{ "name": "some-user-pkg", "version": "0.0.1" }
JSON
  chown -R root:root /home/agent/.npm-global/lib/node_modules/some-user-pkg
  install -m 0644 -o agent -g agent /dev/null /home/agent/.npmrc
  echo "prefix=/home/agent/.npm-global" >>/home/agent/.npmrc
  chown agent:agent /home/agent/.npmrc
}

# setup_brownfield_for_remediate_02_path_wiring
# Targets REMEDIATE-02 (additive PATH wiring). Baseline + REUSE-compatible
# everything else, but the four PATH-wiring artefacts are absent OR drifted
# in pre-existing ~agent/.bashrc. The post-run assertion verifies all four
# artefacts present AND pre-existing .bashrc content outside the marker block
# survives intact.
setup_brownfield_for_remediate_02_path_wiring() {
  _brownfield_baseline
  # Remove the four artefacts so REMEDIATE-02 has to re-create them.
  rm -f /etc/profile.d/agentlinux.sh
  rm -f /etc/agentlinux.env
  rm -f /etc/cron.d/agentlinux
  # Pre-existing .bashrc with USER content the installer must not touch.
  install -m 0644 -o agent -g agent /dev/null /home/agent/.bashrc
  cat >/home/agent/.bashrc <<'BASHRC'
# USER-PROVIDED .bashrc — agentlinux must preserve this.
alias ll='ls -la'
export PROJECT_DIR=/home/agent/projects
BASHRC
  chown agent:agent /home/agent/.bashrc
}

# setup_brownfield_for_remediate_03_missing
# Targets REMEDIATE-03 missing-file install (additive — no --yes needed).
# Baseline + REUSE-compatible everything else, but /etc/sudoers.d/agentlinux
# is ABSENT (so DETECT_SUDOERS_PRESENT=false → reuse decision = create →
# 20-sudoers.sh's case-branch picks the additive install_or_overwrite call).
setup_brownfield_for_remediate_03_missing() {
  _brownfield_baseline
  rm -f /etc/sudoers.d/agentlinux
}

# setup_brownfield_for_remediate_03_drift
# Targets REMEDIATE-03 drift overwrite (state-overwriting — requires --yes).
# Baseline lays the canonical line, then we OVERWRITE with a narrower
# NOPASSWD-for-apt-only line. DETECT_SUDOERS_PRESENT=true +
# DETECT_SUDOERS_NOPASSWD_OK=false → reuse decision = remediate → drift bail
# without --yes, overwrite with --yes.
setup_brownfield_for_remediate_03_drift() {
  _brownfield_baseline
  local tmp
  tmp=$(mktemp)
  printf 'agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get\n' >"$tmp"
  install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/agentlinux
  rm -f "$tmp"
}
