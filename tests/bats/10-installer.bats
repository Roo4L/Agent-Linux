#!/usr/bin/env bats
# tests/bats/10-installer.bats — INST-01, INST-02, INST-05, DOC-02.
#
# Every @test name starts with the requirement ID (INST-XX: or DOC-XX:) so
# behavior-coverage-auditor's TST-07 gate greps pass.
#
# Preconditions (set up by tests/docker/run.sh before bats runs):
#   - agentlinux-install has already been invoked once, writing
#     /var/log/agentlinux-install.log and placing the four PATH-wiring
#     artefacts + agent user + DOC-02 CLAUDE.md.
#   - The installer sources are staged at /opt/agentlinux-src so INST-02 can
#     re-run the installer from inside the bats test.

load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
INSTALLER=/opt/agentlinux-src/plugin/bin/agentlinux-install

@test "INST-01: installer log file exists after initial run" {
  # The harness (tests/docker/run.sh) runs the installer BEFORE bats, so the
  # log must exist by the time this test fires. Missing log = installer
  # didn't run or run.sh is broken — either way a loud failure is the right
  # signal.
  [[ -f "$LOG" ]] || __fail "INST-01" "$LOG exists" "not found" "$LOG"
}

@test "INST-01: installer log contains success banner" {
  # The entrypoint's final log line is "agentlinux-install complete
  # (transcript: ...)". A truncated log or an error before the banner
  # indicates the installer exited non-zero on the initial run.
  grep -q 'agentlinux-install complete' "$LOG" \
    || __fail "INST-01" "'agentlinux-install complete' present in log" "missing" "$LOG"
}

@test "INST-02: re-running the installer is byte-stable (idempotency)" {
  # Snapshot the PATH-wiring artefacts + DOC-02 CLAUDE.md + .bashrc +
  # Phase 3 npmrc/nodesource + Phase 4 CLI + catalog artefacts BEFORE and
  # AFTER a re-run. Byte-identical output means ensure_* helpers plus
  # single-quoted heredocs plus deterministic cp -R into versioned dirs
  # hit the no-diff contract (Measurement Point 3 in 02-RESEARCH.md).
  local pre post
  pre=$(mktemp)
  post=$(mktemp)
  # shellcheck disable=SC2129 # sequential > is fine; one-shot write.
  #
  # Phase 4 extension (Plan 04-07 Task 2): the idempotency set grows
  # monotonically as each phase adds provisioner artefacts —
  #   Phase 2 (5): profile.d/agentlinux.sh, agentlinux.env, cron.d/agentlinux,
  #                /home/agent/.bashrc, /home/agent/CLAUDE.md.
  #   Phase 3 (+2): /home/agent/.npmrc, /etc/apt/sources.list.d/nodesource.sources.
  #   Phase 4 (+2): /opt/agentlinux/catalog/${AGENTLINUX_VERSION}/catalog.json,
  #                 /opt/agentlinux/catalog/${AGENTLINUX_VERSION}/agents/test-dummy/install.sh.
  #   Phase 4 (+2 SEPARATE byte-stability checks with their own __fail paths):
  #      - symlink TARGET (readlink /home/agent/.npm-global/bin/agentlinux)
  #      - CLI entrypoint SHEBANG (first line of /opt/agentlinux/cli/*/dist/index.js)
  #
  # LOCKED deterministic strategy — four Phase 4 items chosen to avoid
  # whole-tree recursion on /opt/agentlinux/cli/ or /opt/agentlinux/catalog/.
  # tsc output across compilations can vary in mtime / internal file
  # ordering; a find -type f -exec sha256sum on the whole dist/ tree would
  # be flaky. Instead we hash specific files the provisioner produces
  # deterministically:
  #   - catalog.json: cp -R of a checked-in JSON file → byte-stable.
  #   - test-dummy/install.sh: cp -R of a checked-in shell script → byte-stable.
  # And we separately verify:
  #   - readlink target: a string, byte-stable by construction.
  #   - first line of dist/index.js: the #!/usr/bin/env node shebang — stable
  #     regardless of any internal tsc reordering of the generated body.
  local version=${AGENTLINUX_VERSION:-0.3.0}
  find \
    /etc/profile.d/agentlinux.sh \
    /etc/agentlinux.env \
    /etc/cron.d/agentlinux \
    /home/agent/.bashrc \
    /home/agent/CLAUDE.md \
    /home/agent/.npmrc \
    /etc/apt/sources.list.d/nodesource.sources \
    "/opt/agentlinux/catalog/${version}/catalog.json" \
    "/opt/agentlinux/catalog/${version}/agents/test-dummy/install.sh" \
    -type f -exec sha256sum {} + >"$pre" 2>/dev/null

  # Symlink target stability — the provisioner's ln -sfn should be a no-op
  # on re-run. A drift here means the chown -h + ln -sfn sequence raced
  # or the target path changed (Plan 04-06 T-04-15 guard).
  local sym_pre
  sym_pre=$(readlink /home/agent/.npm-global/bin/agentlinux 2>/dev/null || echo MISSING)

  # CLI entrypoint shebang hash — hashes ONLY the first line to avoid
  # tsc-output-ordering false positives. A drift here means the shebang
  # line itself rotated (which would break Node dispatch under the
  # /usr/bin/env node convention).
  local shebang_pre
  shebang_pre=$(head -1 "/opt/agentlinux/cli/${version}/dist/index.js" 2>/dev/null | sha256sum)

  run bash "$INSTALLER"
  assert_exit_zero "INST-02"

  find \
    /etc/profile.d/agentlinux.sh \
    /etc/agentlinux.env \
    /etc/cron.d/agentlinux \
    /home/agent/.bashrc \
    /home/agent/CLAUDE.md \
    /home/agent/.npmrc \
    /etc/apt/sources.list.d/nodesource.sources \
    "/opt/agentlinux/catalog/${version}/catalog.json" \
    "/opt/agentlinux/catalog/${version}/agents/test-dummy/install.sh" \
    -type f -exec sha256sum {} + >"$post" 2>/dev/null

  local sym_post shebang_post
  sym_post=$(readlink /home/agent/.npm-global/bin/agentlinux 2>/dev/null || echo MISSING)
  shebang_post=$(head -1 "/opt/agentlinux/cli/${version}/dist/index.js" 2>/dev/null | sha256sum)

  if ! diff -q "$pre" "$post" >/dev/null 2>&1; then
    local delta
    delta=$(diff -u "$pre" "$post" | head -40)
    rm -f "$pre" "$post"
    __fail "INST-02" "sha256 byte-stable across re-run (9-file set)" "$delta" "$LOG"
  fi
  rm -f "$pre" "$post"

  [[ "$sym_pre" == "$sym_post" ]] \
    || __fail "INST-02" "agentlinux symlink target stable across re-run" \
         "before=${sym_pre} after=${sym_post}" "$LOG"

  [[ "$shebang_pre" == "$shebang_post" ]] \
    || __fail "INST-02" "CLI dist/index.js shebang (first line) stable across re-run" \
         "before=${shebang_pre} after=${shebang_post}" "$LOG"
}

@test "INST-05: installer log contains no EACCES or 'permission denied' lines" {
  # The tee'd transcript merges stdout + stderr (Pitfall 6 mitigation in the
  # entrypoint). This is the authoritative no-EACCES gate per the
  # behavior-test-contract skill.
  assert_no_eacces "INST-05" "$LOG"
}

@test "DOC-02: /home/agent/CLAUDE.md exists and is owned by agent:agent" {
  [[ -f /home/agent/CLAUDE.md ]] \
    || __fail "DOC-02" "/home/agent/CLAUDE.md exists" "missing" "$LOG"
  local owner
  owner=$(stat -c '%U:%G' /home/agent/CLAUDE.md)
  [[ "$owner" == "agent:agent" ]] \
    || __fail "DOC-02" "owner agent:agent" "$owner" "$LOG"
}

@test "DOC-02: /home/agent/CLAUDE.md warns against /usr/local/bin shims" {
  grep -q 'usr/local/bin' /home/agent/CLAUDE.md \
    || __fail "DOC-02" "contains 'usr/local/bin' anti-pattern" "missing" "$LOG"
}

@test "DOC-02: /home/agent/CLAUDE.md warns against sudo npm install -g" {
  grep -q 'sudo npm install -g' /home/agent/CLAUDE.md \
    || __fail "DOC-02" "contains 'sudo npm install -g' anti-pattern" "missing" "$LOG"
}

@test "DOC-02: /home/agent/CLAUDE.md warns against second Node.js install" {
  # Plan 02-03 wrote "second Node.js install" — match with optional dot-js
  # suffix so a future rewrite to "second Node install" still passes.
  grep -Eq 'second Node(\.js)? install' /home/agent/CLAUDE.md \
    || __fail "DOC-02" "contains 'second Node install' anti-pattern" "missing" "$LOG"
}
