#!/usr/bin/env bats
# tests/bats/67-catalog-openclaw.bats — v0.3.6 Phase 47 (openclaw 🔧) the AI-assistant
# daemon gate: ENABLE-04 (a catalog entry brings up a PER-USER background service with no
# root and tears it down with no stray daemon/unit/marker) + ASST-01 (openclaw installs
# via npm into the agent-owned prefix, version-locks, and runs its Gateway) + ENABLE-05
# (self-updater frozen so the catalog pin stays authoritative) + an OPS-01 real-operation
# smoke (the Gateway actually serves — a credential-free HTTP + health probe).
#
# THE DOCKER-vs-REAL SPLIT (see plugin/catalog/lib/daemon-lifecycle.sh): openclaw's
# managed daemon uses systemd --user, which the CI container cannot run (masked logind).
# So:
#   - @test 1 verifies the Docker-testable path — install (config-only, graceful when no
#     user systemd) → the Gateway serves via the process-level `openclaw gateway run` →
#     symmetric remove (CAT-04-preserved state) — the every-PR TST-07 gate.
#   - @test 2 verifies the systemd-user daemon lifecycle and SELF-GATES: it `skip`s when
#     the per-user bus is unavailable (Docker) and executes on a real host (QEMU release
#     gate), where the full bats suite is re-run in-guest.
#   - @tests 3-4 are offline (helper trust boundary + entry shape).
#
# Design invariants (from .claude/skills/behavior-test-contract/SKILL.md):
#   - every @test name prefixed with the requirement ID it verifies
#   - failures emit __fail four-line TST-04 diagnostics
#   - the version pin is read from the provisioned catalog via jq — NEVER hardcoded
#   - installs run as the agent user through a login shell (PATH + npm prefix bin)
#   - command strings use ABSOLUTE /home/agent/... paths, never `~` (SC2088)
#
# Refs:
#   - tests/bats/66-catalog-spec-kit.bats (jq-pin + lifecycle driver shape)
#   - plugin/catalog/agents/openclaw/{install,uninstall}.sh
#   - plugin/catalog/lib/daemon-lifecycle.sh (al_daemon_* primitives)
#   - .planning/REQUIREMENTS.md (ASST-01, ENABLE-04, ENABLE-05, OPS-01 + Appendix C: no cred)

load 'helpers/invoke_modes'
load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log
PKG_VERSION=$(jq -r .version /opt/agentlinux-src/plugin/cli/package.json)
CATALOG=/opt/agentlinux/catalog/${PKG_VERSION}/catalog.json

# Absolute agent-owned paths (openclaw installs under the npm prefix + ~/.openclaw).
OC_BIN=/home/agent/.npm-global/bin/openclaw
OC_STATE=/home/agent/.openclaw
OC_CONFIG=/home/agent/.openclaw/openclaw.json
DAEMON_MARKER=/home/agent/.local/share/agentlinux/openclaw.daemon
GW_PORT=18789

# _scrub_openclaw — remove every openclaw + daemon-marker artifact so the lifecycle
# assertions are deterministic (openclaw is the suite's sole daemon consumer). ~/.openclaw
# is CAT-04-preserved by `remove`, so we wipe it explicitly here to reset between runs.
_scrub_openclaw() {
  # Free the gateway test port if a prior run left something on it. Match the LISTENER by
  # port (fuser), never by command string — a `pkill -f "openclaw gateway run"` would also
  # match this very login shell (its argv contains that literal) and kill scrub mid-way.
  sudo -u agent -H bash --login -c '
    fuser -k '"$GW_PORT"'/tcp >/dev/null 2>&1 || true
    npm rm -g openclaw >/dev/null 2>&1 || true
    rm -rf /home/agent/.openclaw /tmp/openclaw
    rm -f  /home/agent/.local/share/agentlinux/openclaw.daemon /home/agent/.local/share/agentlinux/linger.managed
  ' >/dev/null 2>&1 || true
}

# _user_systemd_up — 0 iff the agent user has a reachable per-user systemd bus. The
# Docker harness masks logind → non-zero (@test 2 skips); a real host (QEMU) → zero.
_user_systemd_up() {
  sudo -u agent -H bash --login -c \
    'export XDG_RUNTIME_DIR="/run/user/$(id -u)"; systemctl --user show-environment >/dev/null 2>&1'
}

setup_file() {
  # 40-registry-cli.bats's INST-04 --purge @tests run earlier in filename sort and can
  # remove /opt/agentlinux + the agentlinux symlink. Recovery mirrors 53/57/66.
  if [[ ! -L /home/agent/.npm-global/bin/agentlinux ]]; then
    bash /opt/agentlinux-src/plugin/bin/agentlinux-install >/dev/null 2>&1
  fi
  _scrub_openclaw
}

teardown_file() {
  if [[ -L /home/agent/.npm-global/bin/agentlinux ]]; then
    sudo -u agent -H bash --login -c 'agentlinux remove --force openclaw' >/dev/null 2>&1 || true
  fi
  _scrub_openclaw
}

# _openclaw_pin — echo the openclaw pin from the provisioned catalog (jq, never
# hardcoded) and guard it non-empty/non-null (a blank pin makes `grep -F -- ""` match ANY
# output, silently defeating the version-lock).
_openclaw_pin() {
  local req=$1 pinned
  pinned=$(jq -r '.agents[] | select(.id=="openclaw") | .pinned_version' "$CATALOG")
  if [[ -z "$pinned" || "$pinned" == "null" ]]; then
    __fail "$req" "non-empty pinned_version from catalog" "pinned=[${pinned}] CATALOG=${CATALOG}" "$LOG"
  fi
  printf '%s' "$pinned"
}

@test "ENABLE-04: openclaw installs (no root/shim/EACCES), freezes its updater, serves its Gateway process-level, and removes symmetrically — ~/.openclaw preserved (CAT-04)" {
  local pinned
  pinned=$(_openclaw_pin "ENABLE-04") || return 1

  # --- install: npm global into the agent prefix + non-interactive no-secret onboard ---
  run sudo -u agent -H bash --login -c 'agentlinux install openclaw'
  assert_exit_zero "ENABLE-04 (install)"
  assert_no_eacces "ENABLE-04 (install)" "$output"

  # openclaw resolves under the agent-owned npm prefix — never a /usr/local shim (the
  # exact anti-pattern that breaks self-update).
  run sudo -u agent -H bash --login -c 'command -v openclaw'
  assert_exit_zero "ASST-01 (resolve)"
  case "${output}" in
    "$OC_BIN") : ;;
    *) __fail "ASST-01" "openclaw resolves at ${OC_BIN} (agent prefix, no /usr/local shim)" "${output:-<empty>}" "$LOG" ;;
  esac

  # ASST-01 version-lock: openclaw --version contains the catalog pin (jq-derived).
  run sudo -u agent -H bash --login -c 'openclaw --version'
  assert_exit_zero "ASST-01 (version)"
  if ! printf '%s' "${output}" | grep -q -F -- "$pinned"; then
    __fail "ASST-01" "openclaw --version contains pinned ${pinned}" "${output:-<empty>}" "$LOG"
  fi

  # onboard wrote config WITHOUT a baked secret (no provider key, --auth-choice skip).
  run sudo -u agent -H bash --login -c 'test -f '"$OC_CONFIG"
  [[ "${status}" -eq 0 ]] \
    || __fail "ASST-01" "onboard wrote ${OC_CONFIG}" "config absent" "$LOG"

  # ENABLE-05: the self-updater is frozen — background auto-update is false in the stored
  # config, so the catalog pin stays authoritative (no silent self-install).
  run sudo -u agent -H bash --login -c 'jq -r ".update.auto.enabled" '"$OC_CONFIG"
  if [[ "${output}" != "false" ]]; then
    __fail "ENABLE-05" "update.auto.enabled == false in ${OC_CONFIG} (pin authoritative)" "${output:-<empty>}" "$LOG"
  fi

  # OPS-01 real operation (assistant category = "the Gateway actually serves"): start the
  # Gateway via the process-level path (Docker cannot run the systemd-user daemon) with
  # loopback auth disabled, then prove it serves with a CREDENTIAL-FREE HTTP probe of the
  # dashboard AND openclaw's own health RPC. This is the daemon liveness proof the TST-07
  # gate rides on.
  run sudo -u agent -H bash --login -c '
    export XDG_RUNTIME_DIR="/run/user/$(id -u)" 2>/dev/null || true
    authset=ok
    openclaw config set gateway.auth.mode none >/dev/null 2>&1 || authset=FAIL
    nohup openclaw gateway run --port '"$GW_PORT"' >/tmp/oc-gw-test.log 2>&1 &
    gwpid=$!
    code=000
    for _ in $(seq 1 30); do
      code=$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:'"$GW_PORT"'/ 2>/dev/null || echo 000)
      [ "$code" = "200" ] && break
      sleep 1
    done
    # health via jq (whitespace/ordering-immune, unlike a grep on the raw JSON).
    hj=$(openclaw health --json --timeout 8000 2>/dev/null || true)
    healthok=$(printf "%s" "$hj" | jq -r ".ok // false" 2>/dev/null || echo parse-error)
    # Reap the gateway robustly: kill the process and any child it forked (by PID / parent
    # PID — NEVER `pkill -f "…gateway run"`, which would also match this very login shell),
    # then wait for the port to actually free so a survivor cannot hold it into a later run.
    kill "$gwpid" 2>/dev/null || true
    pkill -P "$gwpid" 2>/dev/null || true
    wait "$gwpid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      curl -sS -o /dev/null http://127.0.0.1:'"$GW_PORT"'/ 2>/dev/null || break
      sleep 1
    done
    echo "AUTHSET=${authset} DASHBOARD=${code} HEALTHOK=${healthok}"
  '
  # The block ends in an echo (best-effort reap → intentionally exit 0), so it is the
  # summary line below — not an exit code — that gates OPS-01.
  if printf '%s' "${output}" | grep -q 'AUTHSET=FAIL'; then
    __fail "OPS-01" "test could set gateway.auth.mode=none for the credential-free probe" "${output:-<empty>}" "$LOG"
  fi
  if ! printf '%s' "${output}" | grep -q 'DASHBOARD=200'; then
    __fail "OPS-01" "Gateway dashboard answers HTTP 200 (credential-free liveness)" "${output:-<empty>}" "$LOG"
  fi
  if ! printf '%s' "${output}" | grep -q 'HEALTHOK=true'; then
    __fail "OPS-01" "openclaw health reports ok:true against the running Gateway" "${output:-<empty>}" "$LOG"
  fi

  # --- symmetric remove: CLI gone, ~/.openclaw preserved (CAT-04), no stray marker ---
  run sudo -u agent -H bash --login -c 'agentlinux remove --force openclaw'
  assert_exit_zero "ENABLE-04 (remove)"
  assert_no_eacces "ENABLE-04 (remove)" "$output"

  # The agent-owned CLI is gone (assert on the concrete path, not PATH-wide command -v).
  run sudo -u agent -H bash --login -c 'test -e '"$OC_BIN"
  [[ "${status}" -ne 0 ]] \
    || __fail "ASST-01" "openclaw CLI removed from the agent prefix" "${OC_BIN} still exists" "$LOG"

  # CAT-04: the user's ~/.openclaw (token, workspace/persona, sessions, provider creds)
  # MUST survive a `remove` — matching every other authenticated agent; only --purge wipes it.
  run sudo -u agent -H bash --login -c 'test -d '"$OC_STATE"
  [[ "${status}" -eq 0 ]] \
    || __fail "ENABLE-04" "state dir ${OC_STATE} preserved on remove (CAT-04 — user data + keys)" "${OC_STATE} was deleted by remove" "$LOG"

  # No stray daemon marker left behind.
  run sudo -u agent -H bash --login -c 'test -e '"$DAEMON_MARKER"
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-04" "daemon marker removed on uninstall" "${DAEMON_MARKER} still exists" "$LOG"

  # Idempotent re-remove (uninstall.sh guards every step / best-effort).
  run sudo -u agent -H bash --login -c 'agentlinux remove --force openclaw'
  assert_exit_zero "ENABLE-04 (idempotent remove)"
}

@test "ENABLE-04 (QEMU-gated): openclaw brings up a per-user systemd Gateway daemon; remove tears it down + reverts AgentLinux-enabled linger" {
  _user_systemd_up || skip "per-user systemd bus unavailable (Docker masks logind) — QEMU release-gate behavior (ADR-007)"

  # install drives the REAL daemon path: linger + `openclaw daemon install && start`.
  run sudo -u agent -H bash --login -c 'agentlinux install openclaw'
  assert_exit_zero "ENABLE-04 (systemd install)"
  assert_no_eacces "ENABLE-04 (systemd install)" "$output"

  # The managed daemon is installed (systemd --user service loaded).
  run sudo -u agent -H bash --login -c \
    'export XDG_RUNTIME_DIR="/run/user/$(id -u)"; openclaw daemon status --json --no-probe'
  assert_exit_zero "ENABLE-04 (daemon status)"
  if ! printf '%s' "${output}" | grep -q '"loaded": true'; then
    __fail "ENABLE-04" "openclaw daemon reports service.loaded:true after install (per-user systemd)" "${output:-<empty>}" "$LOG"
  fi

  # AgentLinux enabled linger and recorded ownership.
  run sudo -u agent -H bash --login -c 'loginctl show-user "$(id -un)" -p Linger'
  if ! printf '%s' "${output}" | grep -q 'Linger=yes'; then
    __fail "ENABLE-04" "linger enabled for the agent user (daemon persists across logout)" "${output:-<empty>}" "$LOG"
  fi
  run sudo -u agent -H bash --login -c 'test -f '"$DAEMON_MARKER"
  [[ "${status}" -eq 0 ]] \
    || __fail "ENABLE-04" "daemon marker dropped on systemd install" "marker absent at ${DAEMON_MARKER}" "$LOG"

  # --- remove tears down the unit + reverts linger (AgentLinux enabled it, none remain) ---
  run sudo -u agent -H bash --login -c 'agentlinux remove --force openclaw'
  assert_exit_zero "ENABLE-04 (systemd remove)"

  run sudo -u agent -H bash --login -c \
    'export XDG_RUNTIME_DIR="/run/user/$(id -u)"; openclaw daemon status --json --no-probe 2>/dev/null || echo GONE'
  # After remove the CLI is gone, so the status probe cannot report a loaded service.
  if printf '%s' "${output}" | grep -q '"loaded": true'; then
    __fail "ENABLE-04" "no per-user systemd service remains after remove" "still loaded: ${output}" "$LOG"
  fi
  run sudo -u agent -H bash --login -c 'test -e '"$DAEMON_MARKER"
  [[ "${status}" -ne 0 ]] \
    || __fail "ENABLE-04" "daemon marker removed on uninstall" "${DAEMON_MARKER} still exists" "$LOG"
}

@test "ENABLE-04: the daemon-lifecycle helper never reverts linger it did not enable, nor one another daemon still needs" {
  # Trust-boundary unit test for the shared helper's core safety guarantees — offline, no
  # real systemd needed. Both branches return BEFORE any `sudo loginctl`, so this is safe
  # in a container. Mirrors 66's user-uv-survives guard.
  run sudo -u agent -H bash --login -c '
    set -euo pipefail
    export AGENTLINUX_AGENT_HOME=/home/agent
    export AGENTLINUX_CATALOG_DIR=/opt/agentlinux/catalog/'"${PKG_VERSION}"'
    # shellcheck source=/dev/null
    source "$AGENTLINUX_CATALOG_DIR/lib/daemon-lifecycle.sh"
    dir=/home/agent/.local/share/agentlinux
    mkdir -p "$dir"

    # (a) No linger marker → revert is a clean no-op (a user-brought linger is untouched).
    rm -f "$dir/linger.managed" "$dir"/*.daemon
    al_daemon_revert_linger_if_unused
    echo "NOMARKER_OK"

    # (b) Linger marker present BUT another daemon tool remains → linger is KEPT (never cut
    # out from under a second daemon), and the function returns before any sudo call.
    printf "agent\n" > "$dir/linger.managed"
    touch "$dir/other.daemon"
    out=$(al_daemon_revert_linger_if_unused)
    printf "%s\n" "$out" | grep -q "keeping linger" && test -f "$dir/linger.managed" && echo "KEEP_OK"

    rm -f "$dir/linger.managed" "$dir"/*.daemon   # dont leak sentinels to later @tests
  '
  assert_exit_zero "ENABLE-04 (linger guard)"
  if ! printf '%s' "${output}" | grep -q 'NOMARKER_OK'; then
    __fail "ENABLE-04" "revert is a no-op with no managed marker (user linger untouched)" "${output:-<empty>}" "$LOG"
  fi
  if ! printf '%s' "${output}" | grep -q 'KEEP_OK'; then
    __fail "ENABLE-04" "revert keeps linger while another daemon tool marker remains" "${output:-<empty>}" "$LOG"
  fi
}

@test "ENABLE-04: the daemon-lifecycle helper detects a container and reports an HONEST no-daemon reason (Docker-awareness)" {
  # The install runs inside the Docker CI container, so al_daemon_in_container MUST return
  # true and al_daemon_report_no_daemon MUST print the container-branch copy ("running
  # inside a container … expected in Docker/CI"), NOT the bus-unreachable-host branch. This
  # is the Docker-awareness the recipes use to explain WHY the per-user Gateway is skipped
  # here instead of the old guess-y "(container?)" hedge. Offline, mutation-free.
  run sudo -u agent -H bash --login -c '
    set -euo pipefail
    export AGENTLINUX_AGENT_HOME=/home/agent
    export AGENTLINUX_CATALOG_DIR=/opt/agentlinux/catalog/'"${PKG_VERSION}"'
    # shellcheck source=/dev/null
    source "$AGENTLINUX_CATALOG_DIR/lib/daemon-lifecycle.sh"
    al_daemon_in_container && echo "IN_CONTAINER_OK"
    al_daemon_report_no_daemon openclaw "openclaw gateway run"
  '
  assert_exit_zero "ENABLE-04 (container detection)"
  if ! printf '%s' "${output}" | grep -q 'IN_CONTAINER_OK'; then
    __fail "ENABLE-04" "al_daemon_in_container true inside the Docker CI container" "${output:-<empty>}" "$LOG"
  fi
  if ! printf '%s' "${output}" | grep -qi 'running inside a container'; then
    __fail "ENABLE-04" "report names the container reason, not a '(container?)' guess" "${output:-<empty>}" "$LOG"
  fi
  # The foreground fallback command is surfaced so a container user knows how to run it now.
  if ! printf '%s' "${output}" | grep -q 'openclaw gateway run'; then
    __fail "ENABLE-04" "report surfaces the foreground fallback command" "${output:-<empty>}" "$LOG"
  fi
}

@test "ASST-01: the openclaw recipe onboards non-interactively with stdin from /dev/null so a real interactive install cannot hang on a prompt" {
  # Sibling guard to the hermes-agent wizard-hang regression: openclaw's onboarding runs
  # its own CLI with --non-interactive, but we also pin its stdin to /dev/null so it can
  # never fall back to a terminal prompt and block the way hermes-agent's third-party
  # installer did. Offline contract assertion on the recipe.
  local recipe=/opt/agentlinux-src/plugin/catalog/agents/openclaw/install.sh
  run grep -E 'openclaw onboard .*--non-interactive.*</dev/null' "$recipe"
  assert_exit_zero "ASST-01 (onboard is non-interactive with stdin </dev/null)"
}

@test "ASST-01: the openclaw catalog entry is a script-kind, MIT, daemon assistant with preserved state" {
  # Offline entry-shape assertion — the entry is the contract. Exact tuple guards drift.
  run bash -c "jq -r '.agents[] | select(.id==\"openclaw\") | \"\(.source_kind) \(.license) \(.pinned_version) \(.install_recipe_path) \(.uninstall_recipe_path) \(.requires_secret) \(.preserve_paths_file)\"' '$CATALOG'"
  assert_exit_zero "ASST-01 (entry shape)"
  if [[ "${output}" != "script MIT 2026.6.10 install.sh uninstall.sh true preserve_paths.json" ]]; then
    __fail "ASST-01" "openclaw entry = 'script MIT 2026.6.10 install.sh uninstall.sh true preserve_paths.json'" "${output:-<empty>}" "$LOG"
  fi

  # It carries the assistant + daemon category tags (ENABLE-06 list grouping, Phase 49).
  run bash -c "jq -r '.agents[] | select(.id==\"openclaw\") | .tags | index(\"assistant\") // empty' '$CATALOG'"
  if [[ -z "${output}" ]]; then
    __fail "ASST-01" "openclaw entry carries the 'assistant' category tag" "tags missing 'assistant'" "$LOG"
  fi
  run bash -c "jq -r '.agents[] | select(.id==\"openclaw\") | .tags | index(\"daemon\") // empty' '$CATALOG'"
  if [[ -z "${output}" ]]; then
    __fail "ASST-01" "openclaw entry carries the 'daemon' category tag" "tags missing 'daemon'" "$LOG"
  fi
}
