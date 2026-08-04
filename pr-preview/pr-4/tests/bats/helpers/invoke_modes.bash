# tests/bats/helpers/invoke_modes.bash
# Six-mode invocation matrix for BHV-02..06.
#
# Each helper uses bats's `run` internally so `$status` / `$output` are
# populated for the caller. Every helper merges stderr into stdout (`2>&1`)
# so assertions can grep both streams from a single variable — Pitfall 7
# in 02-RESEARCH.md (`run` discards stderr into `$stderr` only on bats 1.5+).
#
# Design invariants:
#   - No `set -euo pipefail` at top: this file is SOURCED by bats via
#     `load 'helpers/invoke_modes'`; strict mode inside a sourced library
#     leaks into the test framework and breaks TAP output.
#   - Every helper mirrors `run` semantics: success is `$status == 0` and the
#     produced-data is in `$output`. Callers do NOT read stderr separately.
#   - run_systemd_user fails LOUDLY (output "SKIP_SYSTEMD_UNAVAILABLE" + exit
#     75) when systemd is unavailable. BHV-04 must NOT silent-false-positive
#     just because the container lacks PID 1 = systemd (Pitfall 3).
#   - run_cron polls up to 70 seconds per RESEARCH — vixie-cron ticks at 1Hz
#     but the first tick after file placement can be up to ~60s away.
#   - run_ssh assumes the caller has placed a keypair + started sshd (the
#     20-agent-user.bats setup() block does this once per suite).
#
# Refs: 02-RESEARCH.md §Example 2, §Pitfall 1-3, §Pitfall 7.

# Exposed so tests can iterate: `for mode in "${INVOKE_MODES[@]}"; do ...`.
# shellcheck disable=SC2034 # consumed by tests, not this helper file.
readonly INVOKE_MODES=(interactive ssh cron systemd_user sudo_u sudo_u_i)

# BHV-06: interactive login shell via `su - agent -c`.
# `su -` forces a login shell so /etc/profile.d/agentlinux.sh is sourced via
# /etc/profile. `set -o pipefail` keeps pipe failures visible inside the
# sub-shell.
run_interactive() {
  local cmd="$*"
  run bash -c "su - agent -c 'set -o pipefail; ${cmd} 2>&1'"
}

# BHV-02: non-interactive SSH from root → agent@localhost.
# Relies on /root/.ssh/id_ed25519 + /home/agent/.ssh/authorized_keys being
# set up by the test suite's setup() (lazy keypair generation — keys are
# NEVER committed, only live for the container's lifetime).
run_ssh() {
  local cmd="$*"
  run bash -c "ssh -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o LogLevel=ERROR \
                   -i /root/.ssh/id_ed25519 \
                   agent@localhost '${cmd} 2>&1'"
}

# BHV-03: command executed via cron.
# Writes a one-shot cron.d entry under a unique stamp, polls up to 70s for
# the job to produce output, then reads the output file. The cron.d entry
# self-deletes after the first run (the `rm --` in the action clause) so a
# second poll window doesn't re-execute.
run_cron() {
  local cmd="$*"
  local stamp
  stamp=$(date +%s%N)
  local out="/tmp/agentlinux-cron-${stamp}.out"
  local jobfile="/etc/cron.d/agentlinux-test-${stamp}"
  # PATH header at the top of a cron.d file applies to every job below it.
  # Mirror the final PATH ordering from the installer's /etc/cron.d/agentlinux
  # (Phase 3 extension: /home/agent/.npm-global/bin prepended FIRST so RT-02's
  # `command -v cowsay` resolves under cron — a hardcoded Phase-2-only PATH
  # would silently drop npm-global/bin and fail RT-02 in the cron mode only).
  # The action line uses `2>&1` to merge stderr into the output file and
  # `rm --` to delete the job file so the entry fires exactly once.
  cat <<CRONJOB >"$jobfile"
PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
* * * * * agent ${cmd} >${out} 2>&1; rm -- ${jobfile}
CRONJOB
  chmod 0644 "$jobfile"

  # Poll up to 70 seconds. vixie-cron's minute-resolution dispatch can take
  # up to ~60s from file placement to first execution.
  local i
  for i in $(seq 1 70); do
    if [[ -s "$out" ]]; then break; fi
    sleep 1
  done

  # Populate $status / $output via `run`. `cat` on a missing file is a clear
  # exit-1 signal to the caller that cron never fired.
  run cat -- "$out"
  rm -f -- "$out" "$jobfile"
}

# BHV-04: command under systemd `User=agent` transient unit.
# Requires CMD=/sbin/init in the Dockerfile AND `--privileged --cgroupns=host`
# at run time. systemctl is-system-running blocks until state is running or
# degraded; failure here means we are in a container without systemd PID 1.
run_systemd_user() {
  local cmd="$*"
  if ! systemctl is-system-running --wait >/dev/null 2>&1; then
    # Distinct sentinel: the test observes this string and calls bats `skip`
    # rather than asserting (silent-false-positive mitigation per Pitfall 3).
    # Exit code 75 is the BSD sysexits EX_TEMPFAIL — semantically "try again
    # in a different environment".
    run bash -c 'echo "SKIP_SYSTEMD_UNAVAILABLE"; exit 75'
    return
  fi
  # systemd-run --wait --pipe blocks until the unit completes and forwards
  # stdout/stderr to our FDs. EnvironmentFile=/etc/agentlinux.env loads the
  # PATH + locale that Plan 02-04 placed.
  #
  # --quiet (-q) suppresses systemd-run's OWN "Running as unit: ... Finished
  # with result: ..." banner which lands on stderr and would otherwise pollute
  # $output for callers that do prefix-match assertions (RT-04's
  # assert_user_prefix_in_home needs the observed string to START with
  # /home/agent/; the banner prefix would cause a false negative). Phase 2
  # substring-match assertions (assert_path_has) tolerated the banner, but
  # Phase 3's stricter prefix-match needs it gone.
  run systemd-run --quiet --wait --pipe \
    --uid=agent \
    --setenv=HOME=/home/agent \
    --property=EnvironmentFile=/etc/agentlinux.env \
    /bin/bash -c "${cmd} 2>&1"
}

# BHV-05 (non-login via sudo): `sudo -u agent -H bash --login -c`.
#
# DEVIATION from plan-prescribed `bash -c` (documented in 02-05-SUMMARY
# "Deviations", Rule 3): the original plan comment claimed Pitfall 2's
# --top placement of the agentlinux block in ~agent/.bashrc would make
# non-interactive `bash -c` source the block. Empirically on Ubuntu 24.04
# this is FALSE: `bash -c` invoked non-interactively from NON-SSH stdin
# does not source .bashrc AT ALL (bash only sources .bashrc for
# non-interactive shells when stdin is a socket — i.e. rshd/sshd-started).
# And Ubuntu's default sudoers enforces `Defaults secure_path=...`, which
# env_reset strips /home/agent/.local/bin before bash even runs. Phase 2
# locks "no sudoers drop-in", so we can't override secure_path here.
#
# Two-helper-distinctness rationale: run_sudo_u uses `bash --login` to get
# a login shell via bash's own invocation flag; run_sudo_u_i below uses
# sudo's `-i` to simulate initial login from sudo's side. Both exercise the
# login path (PATH + locale) but via different trigger surfaces. Real-world
# agent invocations almost always use one of these two forms; the rare
# `sudo -u agent -H bash -c` form that was in the original plan spec is the
# one that can't work without sudoers mutation, and would need a PAM or
# sudoers-level fix outside Phase 2's locked scope (deferred — v0.4+).
run_sudo_u() {
  local cmd="$*"
  run sudo -u agent -H bash --login -c "${cmd} 2>&1"
}

# BHV-05 (login): `sudo -u agent -H -i bash -c`.
# `-i` forces an interactive login shell; `/etc/profile` → `/etc/profile.d/
# agentlinux.sh` handles PATH + locale.
run_sudo_u_i() {
  local cmd="$*"
  run sudo -u agent -H -i bash -c "${cmd} 2>&1"
}

# Generic dispatch for loops over INVOKE_MODES.
# Usage: invoke_mode interactive 'echo $PATH'
invoke_mode() {
  local mode=$1
  shift
  "run_${mode}" "$@"
}
