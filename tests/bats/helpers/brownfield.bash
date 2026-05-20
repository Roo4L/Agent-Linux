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
# from the assertions on the installer's own transcript).
log_brownfield() {
  printf '# [brownfield] %s\n' "$*" >&3 2>/dev/null || true
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
