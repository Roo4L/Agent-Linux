---
phase: 2
slug: installer-foundation-agent-user
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-18
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (black-box behavior tests) + pre-commit (shellcheck/shfmt/biome/JSON-Schema) |
| **Config file** | `.pre-commit-config.yaml` (Phase 1); `tests/docker/run.sh` (Wave 0 installs) |
| **Quick run command** | `shellcheck plugin/**/*.sh plugin/lib/*.sh plugin/provisioner/*.sh && pre-commit run shellcheck shfmt biome-check` |
| **Full suite command** | `./tests/docker/run.sh ubuntu-22.04 && ./tests/docker/run.sh ubuntu-24.04` (runs installer inside each image, then bats against the installed environment) |
| **Estimated runtime** | ~4–6 minutes full matrix (~30s quick lint) |

---

## Sampling Rate

- **After every task commit:** Run `shellcheck plugin/**/*.sh` (quick lint, ≤5s)
- **After every plan wave:** Run `./tests/docker/run.sh ubuntu-24.04` (full installer + bats in one image, ~2–3m)
- **Before `/gsd-verify-work`:** Full matrix (22.04 + 24.04) must be green; `pre-commit run --all-files` must be green
- **Max feedback latency:** 30 seconds for quick lint; 180 seconds for single-image full run

---

## Per-Task Verification Map

> Task IDs are provisional — planner may collapse/split when creating 02-NN-PLAN.md files. Requirement IDs and file-exists columns are authoritative.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 bash-lib | 1 | INST-01, INST-02 | T-02-01 | log.sh tees stdout+stderr to `/var/log/agentlinux-install.log` with timestamps | unit | `bash -n plugin/lib/log.sh && shellcheck plugin/lib/log.sh` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 bash-lib | 1 | INST-02 | T-02-02 | idempotency.sh exposes `ensure_line_in_file`, `install_if_absent` | unit | `bash -c "source plugin/lib/idempotency.sh && type -t ensure_line_in_file"` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 bash-lib | 1 | INST-05 | T-02-03 | as_user helper runs command as `agent` user with sanitized env; no EACCES path | unit | `bash -c "source plugin/lib/as_user.sh && type -t as_user"` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 bash-lib | 1 | INST-01 | — | distro_detect.sh reads `/etc/os-release`, returns `ubuntu-22.04` or `ubuntu-24.04` on a supported host, non-zero elsewhere | unit | bats asserts `distro_detect` output on a fixture file | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 entry+provisioner | 2 | INST-01 | T-02-04 | `plugin/bin/agentlinux-install` exits 0 on clean Ubuntu 22.04 / 24.04 non-interactively | bats | `tests/docker/run.sh ubuntu-22.04` | ❌ W0 | ⬜ pending |
| 02-02-02 | 02 entry+provisioner | 2 | INST-02 | T-02-05 | Re-running the installer converges — no duplicate PATH lines, no sudoers breakage, no error on pre-existing agent user | bats | `tests/bats/10-installer.bats::INST-02 idempotent re-run` | ❌ W0 | ⬜ pending |
| 02-02-03 | 02 entry+provisioner | 2 | INST-05 | T-02-06 | No line containing `EACCES` or `permission denied` on stdout or stderr for any installer invocation | bats | `grep -E 'EACCES\|permission denied' /var/log/agentlinux-install.log` returns empty | ❌ W0 | ⬜ pending |
| 02-03-01 | 03 agent-user | 2 | BHV-01 | T-02-07 | agent user exists, has bash shell, real home, `LANG=C.UTF-8`, `LC_ALL=C.UTF-8` | bats | `id agent && getent passwd agent \| cut -d: -f7 \| grep -q bash` | ❌ W0 | ⬜ pending |
| 02-03-02 | 03 agent-user | 2 | DOC-02 | T-02-08 | `/home/agent/CLAUDE.md` exists, enumerates anti-patterns (no `/usr/local/bin/` shims, no re-exec-under-sudo, no second Node install) | bats | `test -f /home/agent/CLAUDE.md && grep -q 'usr/local/bin' /home/agent/CLAUDE.md` | ❌ W0 | ⬜ pending |
| 02-04-01 | 04 path-wiring | 2 | BHV-02, BHV-06 | T-02-09 | `/etc/profile.d/agentlinux.sh` + `~agent/.bashrc` top-of-file guard export PATH+UTF-8 on login and non-interactive bash | bats | `run_interactive 'echo $PATH'` + `run_ssh 'echo $PATH'` — both contain /home/agent/.local/bin | ❌ W0 | ⬜ pending |
| 02-04-02 | 04 path-wiring | 2 | BHV-03 | T-02-10 | `/etc/cron.d/agentlinux` has literal `PATH=...` header | bats | `run_cron 'echo $PATH'` contains installer-placed prefixes | ❌ W0 | ⬜ pending |
| 02-04-03 | 04 path-wiring | 2 | BHV-04 | T-02-11 | `/etc/agentlinux.env` exists + sample systemd unit reference | bats | `run_systemd_user 'echo $PATH'` contains installer-placed prefixes | ❌ W0 | ⬜ pending |
| 02-04-04 | 04 path-wiring | 2 | BHV-05 | T-02-12 | `sudo -u agent echo $PATH` returns installer-placed prefixes WITHOUT `env_keep` in sudoers; `.bashrc` top-of-file block handles both interactive and non-interactive sudo -u | bats | `run_sudo_u 'echo $PATH'` + `run_sudo_u_i 'echo $PATH'` | ❌ W0 | ⬜ pending |
| 02-05-01 | 05 test-harness | 3 | TST-01 partial, TST-02, TST-04 | T-02-13 | Docker matrix `Dockerfile.ubuntu-22.04` + `Dockerfile.ubuntu-24.04` + `run.sh` orchestrate installer+bats | integration | `.github/workflows/test.yml` runs both matrix entries green | ❌ W0 | ⬜ pending |
| 02-05-02 | 05 test-harness | 3 | TST-01, TST-04 | T-02-14 | `tests/bats/helpers/invoke_modes.bash` exposes six helpers, each returning `$status`/`$output` with requirement-ID diagnostic on failure | bats | `tests/bats/helpers/00-helpers.bats` sanity-runs each helper | ❌ W0 | ⬜ pending |
| 02-05-03 | 05 test-harness | 3 | TST-04 | T-02-15 | `tests/bats/helpers/assertions.bash` exposes `assert_no_eacces`, `assert_path_has`, `assert_exit_zero` with diagnostic-on-fail | bats | `tests/bats/helpers/00-helpers.bats` sanity-runs each assertion | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `plugin/lib/log.sh` — logging primitives (log_info / log_warn / log_error / tee'd log file)
- [ ] `plugin/lib/idempotency.sh` — ensure_line_in_file, install_if_absent, marker-comment block helpers
- [ ] `plugin/lib/as_user.sh` — run-as-agent helper (keystone anti-shim primitive; Phase 2 ships it with zero Phase 2 callers ahead of Phase 3's npm work)
- [ ] `plugin/lib/distro_detect.sh` — Ubuntu 22.04 / 24.04 detection, fail-fast elsewhere
- [ ] `plugin/provisioner/10-agent-user.sh` — useradd (bash shell, home, UTF-8) + DOC-02 CLAUDE.md placement
- [ ] `plugin/provisioner/40-path-wiring.sh` — the four-file PATH strategy (profile.d / .bashrc / agentlinux.env / cron.d)
- [ ] `plugin/bin/agentlinux-install` — entrypoint that sources lib and dispatches provisioner (replaces Phase 1 stub)
- [ ] `tests/docker/Dockerfile.ubuntu-22.04` + `Dockerfile.ubuntu-24.04` — images with `systemd`, `cron`, `openssh-server`, `bats` pre-installed
- [ ] `tests/docker/run.sh` — build image → run installer inside → run bats → non-zero on failure
- [ ] `tests/bats/helpers/invoke_modes.bash` + `assertions.bash` — the six-mode helpers and diagnostic assertions
- [ ] `tests/bats/10-installer.bats` — INST-01, INST-02, INST-05 coverage
- [ ] `tests/bats/20-agent-user.bats` — BHV-01..06, DOC-02 coverage

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| systemd-in-Docker reliability on GH Actions runners (research Pitfall A3) | TST-02 (BHV-04 arm) | CI-runner variance — may pass locally but flake on GH Actions; Wave 0 empirical check informs whether to tag `@qemu-only` | Run the 24.04 matrix 3× on `.github/workflows/test.yml`; if BHV-04 passes 3/3, leave untagged; if < 3/3, tag the test `@qemu-only` and defer to Phase 6's QEMU suite |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (13 files above)
- [ ] No watch-mode flags (bats is one-shot; shellcheck is one-shot)
- [ ] Feedback latency < 30s for quick lint, < 180s for single-image full run
- [ ] `nyquist_compliant: true` set in frontmatter after Wave 0 completes

**Approval:** pending
