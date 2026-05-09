#!/usr/bin/env bats
# tests/bats/60-curl-installer.bats — INST-03 curl-pipe-bash contract tests.
#
# Exercises packaging/curl-installer/install.sh against a LOCAL HTTP fixture
# served by python3 -m http.server. No live network: the fixture is built in
# setup_file — fake tarball + sha256 sidecar + a plugin/bin/agentlinux-install
# stub that just prints "fake-installer OK" and exits 0. install.sh is invoked
# with AGENTLINUX_RELEASE_BASE overriding the github.com permalink; when set,
# install.sh skips the "latest" redirect entirely and fetches directly from
# http://localhost:<port>/<tag>/.
#
# Tasks covered (per .planning/phases/06-distribution-release-pipeline/06-02-PLAN.md):
#   - 06-02-01 (tampered-sha fail-fast — T-06-02 mitigation)
#   - 06-02-02 (good-sha happy path → exec agentlinux-install)
#   - 06-02-03 (main-wrapper partial-download safety — T-06-04 mitigation)
#
# Every @test name begins with "INST-03:" so the TST-07 req-ID grep passes.
# Failures flow through __fail for the four-line TST-04 diagnostic contract.
#
# Refs: .claude/skills/behavior-test-contract/SKILL.md;
#       tests/bats/40-registry-cli.bats (setup_file/teardown_file precedent);
#       .planning/phases/06-distribution-release-pipeline/06-RESEARCH.md §Pitfall 1.

load 'helpers/assertions'

INSTALL_SH=/opt/agentlinux-src/packaging/curl-installer/install.sh
FIXTURE_PORT=${AGENTLINUX_FIXTURE_PORT:-8889}
FIXTURE_TAG=v9.9.9-test

setup_file() {
  # 1. Build a fake tarball containing a plugin/bin/agentlinux-install stub.
  #    The stub stands in for Phase 2's installer: prints a sentinel + exits 0.
  FIXTURE_TMP=$(mktemp -d -t agentlinux-fixture.XXXXXX)
  export FIXTURE_TMP
  mkdir -p "$FIXTURE_TMP/build/plugin/bin"
  cat > "$FIXTURE_TMP/build/plugin/bin/agentlinux-install" <<'STUB'
#!/usr/bin/env bash
printf 'fake-installer OK\n'
exit 0
STUB
  chmod +x "$FIXTURE_TMP/build/plugin/bin/agentlinux-install"

  local tarball="agentlinux-${FIXTURE_TAG}.tar.gz"
  mkdir -p "$FIXTURE_TMP/releases/${FIXTURE_TAG}"
  (cd "$FIXTURE_TMP/build" \
    && tar --sort=name --owner=0 --group=0 --numeric-owner \
      --create --gzip \
      --file="$FIXTURE_TMP/releases/${FIXTURE_TAG}/${tarball}" \
      plugin/)
  (cd "$FIXTURE_TMP/releases/${FIXTURE_TAG}" \
    && sha256sum "$tarball" > "${tarball}.sha256")

  # 2. Start python3 HTTP server in background on $FIXTURE_PORT.
  # Detach fully via setsid so the python process is its own session leader and
  # no longer a descendant of the controlling pty — without this, the running
  # server keeps `docker exec` from returning after bats finishes (CI hang
  # observed on rc6 gate-2-docker: 71/71 tests green, then 7-min hang to
  # timeout-minutes:20).
  (cd "$FIXTURE_TMP/releases" \
    && setsid -f python3 -m http.server "$FIXTURE_PORT" </dev/null >/dev/null 2>&1)
  # setsid -f forks before exec, so $! does not reflect the python PID.
  # Discover the PID by port instead — matches whoever is actually serving.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(ss -lntpH "sport = :${FIXTURE_PORT}" 2>/dev/null \
      | grep -oE 'pid=[0-9]+' | head -n1 | cut -d= -f2)
    if [[ -n "${pid:-}" ]]; then
      echo "$pid" > "$FIXTURE_TMP/server.pid"
      break
    fi
    sleep 0.2
  done
  # Poll port-ready. Up to 5s (10 * 0.5s) — python3 -m http.server starts fast.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS "http://127.0.0.1:${FIXTURE_PORT}/${FIXTURE_TAG}/${tarball}" \
      -o /dev/null 2>/dev/null; then
      break
    fi
    sleep 0.5
  done

  export FIXTURE_BASE="http://127.0.0.1:${FIXTURE_PORT}"
}

teardown_file() {
  if [[ -n "${FIXTURE_TMP:-}" && -f "$FIXTURE_TMP/server.pid" ]]; then
    local pid
    pid=$(cat "$FIXTURE_TMP/server.pid" 2>/dev/null || echo "")
    if [[ -n "$pid" ]]; then
      # Kill the whole session/process group (setsid -f makes pid the leader)
      # then escalate to SIGKILL if still alive after a short grace window.
      kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5 6; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
      done
      kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  # Belt-and-suspenders: kill any leftover http.server on FIXTURE_PORT.
  pkill -KILL -f "http.server ${FIXTURE_PORT}" 2>/dev/null || true
  if [[ -n "${FIXTURE_TMP:-}" && -d "$FIXTURE_TMP" ]]; then
    rm -rf "$FIXTURE_TMP"
  fi
  # Subsequent bats files should see a clean state.
  rm -rf "/opt/agentlinux/install/${FIXTURE_TAG#v}" 2>/dev/null || true
}

@test "INST-03: install.sh is wrapped in main(){}; main \"\$@\" (partial-download safety — Pitfall 1)" {
  # 06-02-03: the bash-engineer review + this @test together verify the
  # canonical kicksecure.com/dev.to-operous curl-pipe-bash pattern. A
  # truncated download MUST fail to execute anything (bash parse error
  # BEFORE dispatch). Two shape invariants: (a) exactly one `main() {`
  # definition, (b) the last non-empty line is literally `main "$@"`.
  local defs
  defs=$(grep -cE '^main\(\) \{' "$INSTALL_SH" || true)
  if [[ "$defs" != "1" ]]; then
    __fail "INST-03" "exactly one 'main() {' definition" \
      "found ${defs}" "$INSTALL_SH"
  fi

  local last
  last=$(grep -vE '^\s*$' "$INSTALL_SH" | tail -n 1)
  if [[ "$last" != 'main "$@"' ]]; then
    __fail "INST-03" 'last non-empty line = `main "$@"`' \
      "last='${last}'" "$INSTALL_SH"
  fi
}

@test "INST-03: good SHA256 -> install.sh extracts + execs agentlinux-install (fake-fixture happy path)" {
  # 06-02-02: Invoke the installer against the local HTTP fixture. On
  # success install.sh must reach `exec "${INST}/plugin/bin/agentlinux-install"`
  # — the fake stub prints "fake-installer OK" so that sentinel in output
  # proves both SHA256 verification passed AND exec fired.
  run env \
    AGENTLINUX_RELEASE_BASE="${FIXTURE_BASE}" \
    AGENTLINUX_VERSION="${FIXTURE_TAG}" \
    ORG=agentlinux \
    bash "$INSTALL_SH"
  if [[ "$status" -ne 0 ]]; then
    __fail "INST-03" "install.sh exits 0 on good SHA256" \
      "exit=${status} output=${output}" "$INSTALL_SH"
  fi
  if ! printf '%s\n' "$output" | grep -q 'fake-installer OK'; then
    __fail "INST-03" "'fake-installer OK' sentinel from exec'd stub" \
      "output=${output}" "$INSTALL_SH"
  fi
}

@test "INST-03: tampered SHA256 -> install.sh aborts with clear error, no extraction (T-06-02)" {
  # 06-02-01: Corrupt the .sha256 sidecar; verify install.sh fails fast with
  # a readable error and refuses to extract into /opt/agentlinux/install/.
  # Restores the sidecar in all code paths (including failure) so teardown_file
  # doesn't inherit a broken fixture.
  local tarball="agentlinux-${FIXTURE_TAG}.tar.gz"
  local shafile="${FIXTURE_TMP}/releases/${FIXTURE_TAG}/${tarball}.sha256"
  cp "$shafile" "${shafile}.bak"
  # Replace the hash column (first field) with a known-wrong all-zero hash.
  printf '%s  %s\n' \
    '0000000000000000000000000000000000000000000000000000000000000000' \
    "$tarball" > "$shafile"

  # Ensure the extraction target is clean before we invoke — we will assert
  # it stays absent.
  rm -rf "/opt/agentlinux/install/${FIXTURE_TAG#v}" 2>/dev/null || true

  run env \
    AGENTLINUX_RELEASE_BASE="${FIXTURE_BASE}" \
    AGENTLINUX_VERSION="${FIXTURE_TAG}" \
    ORG=agentlinux \
    bash "$INSTALL_SH"

  # Restore the sidecar immediately, regardless of assertion outcome.
  mv "${shafile}.bak" "$shafile"

  if [[ "$status" -eq 0 ]]; then
    __fail "INST-03" "install.sh exits non-zero on tampered SHA256" \
      "exit=0 (security gate bypassed!) output=${output}" "$INSTALL_SH"
  fi
  if ! printf '%s\n' "$output" | grep -q 'SHA256 verification failed'; then
    __fail "INST-03" "'SHA256 verification failed' diagnostic in output" \
      "output=${output}" "$INSTALL_SH"
  fi
  if [[ -d "/opt/agentlinux/install/${FIXTURE_TAG#v}/plugin" ]]; then
    __fail "INST-03" \
      "no extraction under /opt/agentlinux/install/${FIXTURE_TAG#v}" \
      "plugin/ dir exists (unsafe!)" "$INSTALL_SH"
  fi
}
