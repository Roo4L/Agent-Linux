---
phase: 2
slug: installer-foundation-agent-user
verified_date: 2026-04-18
status: passed
must_haves_verified: 41/41
phase_requirements_covered: 13/13
tst07_gate: GREEN
docker_end_to_end:
  ubuntu-22.04: 22/22 PASS
  ubuntu-24.04: 22/22 PASS
  inst05_eacces_count: 0
  inst02_byte_stable: true
overrides:
  - must_have: "run_sudo_u uses bash -c (no login) — BHV-05 plain `sudo -u agent bash -c` invocation"
    reason: "Ubuntu's default sudoers `Defaults secure_path=...` strips PATH via env_reset before bash runs, AND `bash -c` (non-interactive, non-login, stdin not a socket) does not source ~/.bashrc. Fixing this requires a sudoers drop-in or PAM-level change; Phase 2 CONTEXT explicitly locks no default sudoers drop-in. BHV-05's observable-behavior contract (agent binaries findable on PATH under sudo -u agent) is satisfied by the two login variants run_sudo_u (bash --login -c) + run_sudo_u_i (sudo -u -H -i). Deferred to v0.4+ as a PAM/sudoers architectural enhancement. Documented in REQUIREMENTS.md BHV-05 note, ROADMAP.md Phase 2 completion note, and 02-05-SUMMARY.md Deviations §1."
    accepted_by: "Nikita Ivanov"
    accepted_at: "2026-04-18"
---

# Phase 2: Installer Foundation + Agent User — Verification Report

**Phase Goal (ROADMAP §Phase 2):** Running the installer on a clean Ubuntu 22.04 or 24.04 produces an `agent` user who can run commands — with all six BHV invocation modes working (interactive bash login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`) and zero `EACCES` / `permission denied` output — even though no agents are installed yet.

**Verified:** 2026-04-18
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement Summary

All six ROADMAP §Phase 2 success criteria VERIFIED end-to-end inside real systemd-capable Docker containers on both supported Ubuntu LTS versions.

| # | Success Criterion (ROADMAP) | Status | Evidence |
|---|-----------------------------|--------|----------|
| 1 | Installer on fresh Ubuntu 22.04/24.04 Docker: single command, no interactive prompts, exit 0 (INST-01) | ✓ VERIFIED | `bash tests/docker/run.sh ubuntu-{22,24}.04` → exit 0, `agentlinux-install` emits "complete" banner; `@test INST-01: installer log file exists` + `INST-01: installer log contains success banner` both pass on both versions. Independent verification: `docker run ... bash plugin/bin/agentlinux-install` exits 0, final log line is "agentlinux-install complete (transcript: /var/log/agentlinux-install.log)". |
| 2 | Re-run converges — byte-stable (INST-02) | ✓ VERIFIED | `@test INST-02` performs sha256sum across 5 artefacts (`/etc/profile.d/agentlinux.sh`, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`, `/home/agent/.bashrc`, `/home/agent/CLAUDE.md`) BEFORE and AFTER a second installer invocation; diff is empty. Independent re-verification in a fresh container: PRE==POST (`INST-02_PROOF: BYTE_STABLE`). No duplicate PATH lines (single-quoted heredocs + `ensure_marker_block` awk-strip-and-replace). No sudoers breakage (none placed — CONTEXT-locked). `ensure_user` is a no-op on pre-existing agent user. |
| 3 | `grep -E 'EACCES\|permission denied'` on installer transcript → zero hits (INST-05) | ✓ VERIFIED | `@test INST-05: installer log contains no EACCES or 'permission denied' lines` (via `assert_no_eacces` on `/var/log/agentlinux-install.log`) passes on both 22.04 + 24.04. Independent verification: `grep -cE 'EACCES\|permission denied' /var/log/agentlinux-install.log` → **0** inside a fresh container. Entrypoint uses `exec > >(tee -a "$LOG_FILE") 2>&1` so both streams land in one greppable transcript (Pitfall 6 mitigation + `trap 'exec >&-; wait "$TEE_PID"' EXIT` for flush). |
| 4 | Agent user trivial command works across all six invocation modes with correct PATH, UTF-8 locale, bash shell (BHV-01..06) | ✓ VERIFIED | `@test BHV-01` × 4 (getent passwd bash/home, `/etc/default/locale` LANG, `/etc/default/locale` LC_ALL, `locale -a` C.utf8); `@test BHV-02` × 2 (SSH PATH + locale); `@test BHV-03` × 1 (cron PATH via 70s poll); `@test BHV-04` × 2 (systemd `User=agent` PATH + locale via `systemd-run --uid=agent --property=EnvironmentFile=/etc/agentlinux.env`); `@test BHV-05` × 3 (sudo -u login bash, sudo -u -i, sudo -u -i locale); `@test BHV-06` × 2 (`su - agent -c` PATH + locale). **14 @tests, all green on both 22.04 + 24.04.** Four provisioner artefacts: `/etc/profile.d/agentlinux.sh` (BHV-06 + BHV-05 -i), `/home/agent/.bashrc` top-marker block (BHV-02 + BHV-05 bash-c via login), `/etc/agentlinux.env` (BHV-04), `/etc/cron.d/agentlinux` (BHV-03). |
| 5 | `/home/agent/CLAUDE.md` exists + instructs against shim/wrapper workarounds (DOC-02) | ✓ VERIFIED | `@test DOC-02` × 4: file exists, owner=`agent:agent` (`stat -c '%U:%G'`), three canonical anti-pattern strings present (`usr/local/bin`, `sudo npm install -g`, `second Node.js install`). File placed via `ensure_marker_block --top` with stable tag `agentlinux-doc-02` so user content outside the block survives re-runs. |
| 6 | Docker bats matrix (22.04 + 24.04) on every PR, covers every INST-XX + BHV-XX with ≥1 test, failure output identifies requirement (TST-01 partial, TST-02, TST-04) | ✓ VERIFIED | `.github/workflows/test.yml` `bats-docker` job: matrix `[ubuntu-22.04, ubuntu-24.04]`, `fail-fast: false`, `timeout-minutes: 15`, triggers `bash tests/docker/run.sh ${{ matrix.ubuntu }}`. Every Phase 2 req-ID has ≥1 @test with ID-prefixed name (enforced by behavior-coverage-auditor / TST-07 gate). TST-04 shape: `tests/bats/helpers/assertions.bash::__fail` emits `# FAIL: <req-id> / # expected: ... / # observed: ... / # log: ...` as four TAP comments on stderr. Independent YAML parse confirms structure. |

**Score: 6/6 ROADMAP success criteria verified.**

## Must-Haves Matrix

Aggregated from all five PLAN frontmatter `must_haves.truths` blocks (41 distinct truths). All verified end-to-end inside systemd Docker container.

### Plan 02-01 (bash library primitives) — 7/7 ✓

| Must-Have | Status | Evidence |
|-----------|--------|----------|
| `log.sh` sources cleanly, exports `log_info/warn/error` with ISO-8601 timestamps | ✓ | `plugin/lib/log.sh:37,40,45,50` — all four primitives present; `__log_ts` returns `date -u +%Y-%m-%dT%H:%M:%SZ`; shellcheck clean. Installer log confirms: `[2026-04-18T15:37:46Z] [INFO] agentlinux-install v0.3.0 starting`. |
| `idempotency.sh` exports `ensure_line_in_file`, `ensure_marker_block`, `ensure_user`, `ensure_dir`, `visudo_validate` | ✓ | `plugin/lib/idempotency.sh:26,49,106,123,142` — all five functions defined; shellcheck clean; argument guards (`$# -lt N`) precede `$1/$2` reads for set-u safety. |
| `as_user.sh` exports `as_user` + `as_user_login` routing through `sudo -u -H -E --` / `sudo -u -H -i --` | ✓ | `plugin/lib/as_user.sh:31,45` — `as_user()` → `sudo -u "$user" -H -E -- "$@"`; `as_user_login()` → `sudo -u "$user" -H -i -- "$@"`. Grep confirms raw `sudo -u` appears only in `as_user.sh` in `plugin/` (all other matches are doc comments). |
| `distro_detect.sh` exports `detect_distro` accepting ubuntu 22.04/24.04 | ✓ | `plugin/lib/distro_detect.sh:28` — reads `/etc/os-release`, case-matches `22.04\|24.04`, exports `AGENTLINUX_DISTRO_VERSION`. Runtime evidence: `[2026-04-18T15:37:46Z] [INFO] detected ubuntu 24.04`. |
| Every library file starts with `#!/usr/bin/env bash` + passes shellcheck `--severity=warning --external-sources` | ✓ | `head -1 plugin/lib/*.sh` → all 4 start with `#!/usr/bin/env bash`. `shellcheck --severity=warning --shell=bash --external-sources plugin/lib/*.sh` exit 0. |
| Every state-mutating helper is grep-before-mutate (idempotent on re-source) | ✓ | `ensure_line_in_file` uses `grep -Fxq -- "$line" "$file"` before append; `ensure_marker_block` awk-strips prior block then re-writes via `install -m 0644`; `ensure_user` wraps `useradd` in `id "$user"` check; `ensure_dir` uses `install -d` if absent / `chmod+chown` otherwise. |
| Re-sourcing any library file twice does not duplicate functions / emit stderr | ✓ | Every lib begins with `[[ -n "${AGENTLINUX_<NAME>_SH_SOURCED:-}" ]] && return 0; readonly AGENTLINUX_<NAME>_SH_SOURCED=1`. |

### Plan 02-02 (installer entrypoint) — 10/10 ✓

| Must-Have | Status | Evidence |
|-----------|--------|----------|
| `plugin/bin/agentlinux-install` replaces Phase 1 stub with real entrypoint | ✓ | 194-line file; has `set -euo pipefail`, root check, log tee, ERR trap, arg parser, provisioner dispatch, `main "$@"`. |
| Running without root → exit 64 + clear error | ✓ | `require_root` function at line 157-162: `log_error "must run as root (EUID != 0)"; exit 64`. Alternate failure path at `install -m 0644 /dev/null "$LOG_FILE"` also exits 64 on permission denial. |
| Running on non-Ubuntu → exit 1 + clear error | ✓ | `detect_distro` returns 1 on non-Ubuntu; ERR trap fires; `on_error` logs failing step + transcript path, exits inherited code. |
| `--help` exits 0 with usage | ✓ | `pre_parse_args` at lines 50-68 handles `-h\|--help` → `usage; exit 0`. Contains literal `Usage: agentlinux-install`. |
| `--version` exits 0 printing 0.3.0 | ✓ | `pre_parse_args` case `-V\|--version` → `printf '%s\n' "$AGENTLINUX_VERSION"; exit 0` where `AGENTLINUX_VERSION="0.3.0"`. |
| `--purge` exits 0 with Phase 4 stub warning | ✓ | `pre_parse_args` case `--purge` → `printf 'agentlinux-install: --purge is a Phase 4 stub...'; exit 0`. Also second handler in `parse_args` (defensive fallthrough). |
| Sources all four libraries in correct order | ✓ | Lines 100 (log.sh), 115 (distro_detect.sh), 117 (idempotency.sh), 119 (as_user.sh). Shellcheck `source=` directives present. |
| stdout+stderr tee'd to `/var/log/agentlinux-install.log` | ✓ | Line 92: `exec > >(tee -a "$LOG_FILE") 2>&1` + `TEE_PID=$!`. INST-05 bats test greps this log and finds 0 matches. |
| `trap ERR` logs failing step + log path | ✓ | Lines 102-112: `on_error()` + `trap on_error ERR` — logs `at $(basename src):line_no (exit N)` + `full transcript: ...`. |
| `trap EXIT` waits for tee child (Pitfall 6) | ✓ | Line 95: `trap 'exec >&- 2>&-; wait "$TEE_PID" 2>/dev/null || true' EXIT`. Closes FDs first so tee gets EOF and flushes. |

### Plan 02-03 (agent-user provisioner) — 8/8 ✓

| Must-Have | Status | Evidence |
|-----------|--------|----------|
| agent user exists (`getent passwd agent` returns a line) | ✓ | Inside container: `agent:x:1001:1001::/home/agent:/bin/bash`. `@test BHV-01: agent user exists with bash shell and /home/agent home` PASS. |
| shell is `/bin/bash` (passwd ends `:/home/agent:/bin/bash`) | ✓ | Same passwd entry as above. `ensure_user` in `idempotency.sh` calls `useradd --create-home --shell /bin/bash --user-group`. |
| home is `/home/agent`, 0755, agent:agent | ✓ | `ensure_dir /home/agent 0755 agent:agent` in `10-agent-user.sh:29`. `stat -c '%a %U:%G' /home/agent` → `755 agent:agent` inside container. |
| C.UTF-8 locale enforced system-wide in `/etc/default/locale` | ✓ | `update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8` in `10-agent-user.sh:53`. `@test BHV-01: /etc/default/locale has LANG=C.UTF-8` + `LC_ALL=C.UTF-8` + `C.UTF-8 is available in locale -a` — all three PASS. |
| `/home/agent/CLAUDE.md` exists, 0644, agent:agent | ✓ | `chmod 0644 + chown agent:agent` at lines 132-133 after `ensure_marker_block`. `stat -c '%U:%G' /home/agent/CLAUDE.md` → `agent:agent` (confirmed in container). `@test DOC-02: /home/agent/CLAUDE.md exists and is owned by agent:agent` PASS. |
| DOC-02 body contains three anti-patterns | ✓ | Heredoc lines 79-127 include literal strings: "No wrapper shims under `/usr/local/bin/`", "No `sudo npm install -g`", "No second Node.js install". `@test DOC-02` × 3 anti-pattern greps all PASS. |
| Re-run with existing agent user — no error | ✓ | `ensure_user` wraps `useradd` in `id "$user"` guard; emits `user agent already exists (no-op)`. INST-02 byte-stable re-run verified. |
| Re-run preserves user edits outside `agentlinux-doc-02` marker block | ✓ | `ensure_marker_block` uses awk-strip between `# >>> tag begin >>>` / `# <<< tag end <<<` markers; content outside survives (algorithm in `idempotency.sh:49-102`). INST-02 byte-stability test covers this path. |

### Plan 02-04 (path wiring provisioner) — 8/8 ✓

| Must-Have | Status | Evidence |
|-----------|--------|----------|
| `/etc/profile.d/agentlinux.sh` mode 0644 root:root with re-source guard | ✓ | `install -m 0644 /dev/stdin /etc/profile.d/agentlinux.sh <<'PROFILE'` at line 60. Re-source guard `[ -n "${AGENTLINUX_PROFILE_SOURCED:-}" ] && return`. Container stat: `644 root:root`. |
| Profile.d exports LANG=C.UTF-8, LC_ALL=C.UTF-8, prepends `/home/agent/.local/bin` to PATH | ✓ | Heredoc body lines 68-77 contains `export LANG="${LANG:-C.UTF-8}"`, `export LC_ALL="${LC_ALL:-C.UTF-8}"`, and case-prepend `PATH="/home/agent/.local/bin:${PATH}"` (only if not already present). BHV-06 + BHV-05 -i bats tests verify observable PATH. |
| `/home/agent/.bashrc` has `agentlinux-path` marker block at TOP | ✓ | `ensure_marker_block /home/agent/.bashrc "agentlinux-path" --top` at line 101. `--top` placement precedes the skel `case $- in *i*) ;; *) return;; esac` early-return (Pitfall 2 mitigation). BHV-02 SSH bats test confirms `/home/agent/.local/bin` on PATH over non-interactive SSH. |
| .bashrc agentlinux block sources `/etc/profile.d/agentlinux.sh` | ✓ | Marker block body: `if [ -f /etc/profile.d/agentlinux.sh ]; then . /etc/profile.d/agentlinux.sh; fi`. |
| `/etc/agentlinux.env` mode 0644 with literal KEY=VALUE PATH/LANG/LC_ALL | ✓ | `install -m 0644 /dev/stdin /etc/agentlinux.env <<'ENVFILE'` at line 124. Body: literal `PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin`, `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`. Single-quoted heredoc → no variable expansion → byte-identical on re-run. Container stat: `644`. |
| `/etc/cron.d/agentlinux` mode 0644 with literal PATH+LANG+LC_ALL header and no default jobs | ✓ | `install -m 0644 /dev/stdin /etc/cron.d/agentlinux <<'CRON'` at line 140. Body has commented example job (`# 0 3 * * * agent ...`) + literal PATH header. Container stat: `644`. BHV-03 cron test passes (agent's `/home/agent/.local/bin` visible in cron-executed `echo $PATH`). |
| Re-run produces byte-identical state (idempotency contract) | ✓ | Independent re-run test: `PRE sha256` == `POST sha256` across 5 artefacts (`INST-02_PROOF: BYTE_STABLE`). All writes atomic via `install -m` (full-file) or `ensure_marker_block` (awk-strip-and-replace). |
| `/etc/sudoers.d/agentlinux` does NOT exist (CONTEXT-locked) | ✓ | Container check: `test -f /etc/sudoers.d/agentlinux` → `NOT-PRESENT-OK`. Grep confirms `plugin/provisioner/40-path-wiring.sh` contains no `sudoers.d` reference. |

### Plan 02-05 (test harness + CI) — 8/8 ✓ (+ override for 1 sub-item)

| Must-Have | Status | Evidence |
|-----------|--------|----------|
| Both Dockerfiles build successfully with systemd+cron+openssh+bats+sudo+locales+dbus | ✓ | `bash tests/docker/run.sh ubuntu-24.04` → Dockerfile builds (cached) + container reaches systemd `running`; same for 22.04. Dockerfile `RUN apt-get install ... systemd systemd-sysv cron openssh-server bats locales sudo dbus ca-certificates bash coreutils util-linux shellcheck`. |
| `run.sh` accepts 22.04/24.04, builds image, runs installer, runs bats, exits 0 on success | ✓ | Both matrix entries exit 0 locally. `tests/docker/run.sh` validates arg (exit 64 on bogus), builds image, runs privileged systemd container, `docker exec bash /opt/agentlinux-src/plugin/bin/agentlinux-install`, then `bats tests/bats/`. Propagates `$BATS_STATUS`. |
| `invoke_modes.bash` exposes six helpers: `run_interactive`, `run_ssh`, `run_cron`, `run_systemd_user`, `run_sudo_u`, `run_sudo_u_i` | ✓ | All six functions present in `tests/bats/helpers/invoke_modes.bash` (lines 33, 42, 56, 89, 130, 138). `readonly INVOKE_MODES=(interactive ssh cron systemd_user sudo_u sudo_u_i)` also exposed. |
| `assertions.bash` exposes `assert_no_eacces`, `assert_path_has`, `assert_exit_zero` with TST-04 diagnostic shape | ✓ | All three public helpers present (lines 49, 73, 86). `__fail` emits four canonical lines to stderr: `# FAIL:`, `#   expected:`, `#   observed:`, `#   log:`. |
| `10-installer.bats` covers INST-01 (exit 0), INST-02 (byte-stable re-run), INST-05 (no-EACCES), DOC-02 (anti-patterns) | ✓ | 8 @tests with ID-prefixed names — 2× INST-01, 1× INST-02, 1× INST-05, 4× DOC-02. All pass on both Ubuntu versions. |
| `20-agent-user.bats` covers BHV-01 (user+locale) + BHV-02..06 (all six modes PATH + C.UTF-8) | ✓ | 14 @tests with ID-prefixed names — 4× BHV-01, 2× BHV-02, 1× BHV-03, 2× BHV-04, 3× BHV-05, 2× BHV-06. All pass on both Ubuntu versions. BHV-05 non-login uses `bash --login -c` (accepted override — see frontmatter `overrides`). |
| Every @test name cites its requirement ID (TST-07) | ✓ | Grep `^@test "(INST-0[125]\|BHV-0[1-6]\|DOC-02):` returns 22 matches (10-installer.bats: 8, 20-agent-user.bats: 14) — 100% of @tests are ID-prefixed. |
| `.github/workflows/test.yml` matrix includes both Ubuntu versions; bats-docker job calls `tests/docker/run.sh` | ✓ | YAML parses; `bats-docker` job at line 61 with `matrix: ubuntu: [ubuntu-22.04, ubuntu-24.04]`, `fail-fast: false`, `timeout-minutes: 15`, `run: bash tests/docker/run.sh ${{ matrix.ubuntu }}`. Empty-plugin guard retained (falls through to real run now). |
| Green run: 0 EACCES in `/var/log/agentlinux-install.log` | ✓ | Independent verification inside a fresh container: `grep -cE 'EACCES\|permission denied' /var/log/agentlinux-install.log` → **0**. |
| `bash tests/harness/run.sh` (Phase 1 gate) remains green | ✓ | 104/104 @tests pass — ran just now; every HRN-XX + TST-06 assertion still green. |

## Required Artefacts

| Artefact | Expected | Status | Details |
|----------|----------|--------|---------|
| `plugin/lib/log.sh` | 40-60 lines; 4 log primitives | ✓ VERIFIED | 53 lines; `log_info/warn/error/debug` all defined; source-guard + ISO-8601 timestamp |
| `plugin/lib/idempotency.sh` | 80+ lines; 5 ensure_* primitives | ✓ VERIFIED | 153 lines; `ensure_line_in_file/marker_block/user/dir` + `visudo_validate` |
| `plugin/lib/as_user.sh` | 15+ lines; 2 as_user* fns | ✓ VERIFIED | 53 lines; `as_user` + `as_user_login`; only place raw `sudo -u` appears in plugin/ |
| `plugin/lib/distro_detect.sh` | 30+ lines; detect_distro | ✓ VERIFIED | 60 lines; reads /etc/os-release, exports `AGENTLINUX_DISTRO_VERSION`; SKIP escape hatch for bats |
| `plugin/bin/agentlinux-install` | 80+ lines; entrypoint | ✓ VERIFIED | 194 lines; wired to all 4 libs, provisioner dispatch, log tee, ERR+EXIT traps |
| `plugin/provisioner/10-agent-user.sh` | 40+ lines; user+locale+DOC-02 | ✓ VERIFIED | 136 lines; `ensure_user`, `ensure_dir`, `update-locale`, `ensure_marker_block agentlinux-doc-02 --top` |
| `plugin/provisioner/40-path-wiring.sh` | 60+ lines; four artefacts | ✓ VERIFIED | 152 lines; writes profile.d (install -m), .bashrc (ensure_marker_block --top), agentlinux.env (install -m), cron.d (install -m) |
| `tests/docker/Dockerfile.ubuntu-22.04` | 25+ lines | ✓ VERIFIED | 59 lines; FROM ubuntu:22.04; CMD [/sbin/init]; apt: systemd systemd-sysv cron openssh-server bats locales sudo dbus; masked logind/resolved/networkd/tmpfiles |
| `tests/docker/Dockerfile.ubuntu-24.04` | 25+ lines | ✓ VERIFIED | 65 lines; identical invariants as 22.04 modulo FROM line |
| `tests/docker/run.sh` | 50+ lines; executable | ✓ VERIFIED | 158 lines; executable; validates arg (exit 64 on bogus), privileged systemd container, staged sources, installer + bats exec, PASS/FAIL banner |
| `tests/bats/helpers/invoke_modes.bash` | 60+ lines; 6 helpers | ✓ VERIFIED | 149 lines; all six helpers exposed; no `set -euo pipefail` (breaks bats); SKIP_SYSTEMD_UNAVAILABLE sentinel for BHV-04 |
| `tests/bats/helpers/assertions.bash` | 40+ lines; 3 assertions + TST-04 | ✓ VERIFIED | 94 lines; `__fail` emits four canonical TST-04 lines; no strict mode |
| `tests/bats/10-installer.bats` | 50+ lines; INST + DOC-02 | ✓ VERIFIED | 103 lines; 8 @tests (2× INST-01, 1× INST-02 sha256 diff, 1× INST-05 assert_no_eacces, 4× DOC-02) |
| `tests/bats/20-agent-user.bats` | 80+ lines; BHV-01..06 | ✓ VERIFIED | 164 lines; 14 @tests across all six modes; lazy SSH keypair in setup(); BHV-04 skip on SKIP_SYSTEMD_UNAVAILABLE |
| `.github/workflows/test.yml` | bats-docker matrix | ✓ VERIFIED | YAML parses; bats-docker job with `matrix: ubuntu: [ubuntu-22.04, ubuntu-24.04]`; empty-plugin guard retained |

## Key Link Verification

All cross-file wiring contracts enforced programmatically.

| From | To | Via | Status |
|------|----|----|--------|
| `plugin/bin/agentlinux-install` | `plugin/lib/log.sh` | `. "$LIB_DIR/log.sh"` (line 100) | ✓ WIRED |
| `plugin/bin/agentlinux-install` | `plugin/lib/distro_detect.sh` | `. "$LIB_DIR/distro_detect.sh"` (line 115) + `detect_distro` call in `main` (line 189) | ✓ WIRED |
| `plugin/bin/agentlinux-install` | `plugin/lib/idempotency.sh` | `. "$LIB_DIR/idempotency.sh"` (line 117) | ✓ WIRED |
| `plugin/bin/agentlinux-install` | `plugin/lib/as_user.sh` | `. "$LIB_DIR/as_user.sh"` (line 119) | ✓ WIRED |
| `plugin/bin/agentlinux-install` | `/var/log/agentlinux-install.log` | `exec > >(tee -a "$LOG_FILE") 2>&1` (line 92) | ✓ WIRED |
| `plugin/bin/agentlinux-install` | `plugin/provisioner/[0-9][0-9]-*.sh` | `compgen -G + mapfile + for ... . "$step"` (`run_provisioners`, lines 164-183) | ✓ WIRED |
| `plugin/provisioner/10-agent-user.sh` | `plugin/lib/idempotency.sh` | calls `ensure_user agent`, `ensure_dir`, `ensure_marker_block` | ✓ WIRED |
| `plugin/provisioner/10-agent-user.sh` | `plugin/lib/log.sh` | `log_info`, `log_warn`, `log_error` calls | ✓ WIRED |
| `plugin/provisioner/10-agent-user.sh` | `/home/agent/CLAUDE.md` | `ensure_marker_block ... "agentlinux-doc-02" --top` | ✓ WIRED |
| `plugin/provisioner/40-path-wiring.sh` | `/etc/profile.d/agentlinux.sh` | `install -m 0644 /dev/stdin /etc/profile.d/agentlinux.sh` | ✓ WIRED |
| `plugin/provisioner/40-path-wiring.sh` | `/home/agent/.bashrc` | `ensure_marker_block /home/agent/.bashrc "agentlinux-path" --top` | ✓ WIRED |
| `plugin/provisioner/40-path-wiring.sh` | `/etc/agentlinux.env` | `install -m 0644 /dev/stdin /etc/agentlinux.env` | ✓ WIRED |
| `plugin/provisioner/40-path-wiring.sh` | `/etc/cron.d/agentlinux` | `install -m 0644 /dev/stdin /etc/cron.d/agentlinux` | ✓ WIRED |
| `tests/docker/run.sh` | `plugin/bin/agentlinux-install` | `docker exec "$CID" bash /opt/agentlinux-src/plugin/bin/agentlinux-install` (line 148) | ✓ WIRED |
| `tests/bats/10-installer.bats` | `tests/bats/helpers/assertions.bash` | `load 'helpers/assertions'` (line 14) | ✓ WIRED |
| `tests/bats/20-agent-user.bats` | `tests/bats/helpers/invoke_modes.bash` + `helpers/assertions.bash` | both `load` lines at 19-20 | ✓ WIRED |
| `.github/workflows/test.yml` | `tests/docker/run.sh` | `run: bash tests/docker/run.sh ${{ matrix.ubuntu }}` (line 93) | ✓ WIRED |

## Data-Flow Trace (Level 4)

Phase 2 produces configuration files + a working installer, not render-dynamic-data components. Data-flow verification is end-to-end: the installer writes artefacts, the bats suite reads them back and asserts observable behavior.

| Artefact | Data consumer | Flow verified | Status |
|----------|--------------|---------------|--------|
| `/var/log/agentlinux-install.log` | `assert_no_eacces` in INST-05 @test | Entrypoint writes via `exec > >(tee -a)`; bats reads file content; grep finds 0 EACCES on green run | ✓ FLOWING |
| `/etc/profile.d/agentlinux.sh` | BHV-06 `run_interactive` (`su - agent -c`) | File contains case-prepend for `/home/agent/.local/bin`; `@test BHV-06` observes the PATH in the login shell | ✓ FLOWING |
| `/home/agent/.bashrc` TOP marker | BHV-02 `run_ssh`, BHV-05 `run_sudo_u` (bash --login) | Block sources `/etc/profile.d/agentlinux.sh`; `@test BHV-02` + `@test BHV-05` non-login observe `/home/agent/.local/bin` on PATH | ✓ FLOWING |
| `/etc/agentlinux.env` | BHV-04 `run_systemd_user` via `EnvironmentFile=` | Literal PATH + LANG + LC_ALL; `@test BHV-04` observes `/home/agent/.local/bin` and `C.UTF-8` inside systemd transient unit | ✓ FLOWING |
| `/etc/cron.d/agentlinux` | BHV-03 `run_cron` | PATH header applies to agent cron jobs; `@test BHV-03` writes a one-shot cron job, waits 70s, observes `/home/agent/.local/bin` in $PATH | ✓ FLOWING |
| `/etc/default/locale` | BHV-01 `grep ^LANG=C\.UTF-8$` | `update-locale` write; bats reads file directly | ✓ FLOWING |
| `/home/agent/CLAUDE.md` | DOC-02 bats greps | `ensure_marker_block --top` write; bats stat + grep | ✓ FLOWING |

## Behavioral Spot-Checks

Ran the Docker harness end-to-end on both Ubuntu LTS versions as an independent verifier run (not the summary's claim).

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Installer runs green on Ubuntu 24.04 | `bash tests/docker/run.sh ubuntu-24.04` | `22/22 PASS`, `== PASS: agentlinux-install + bats on ubuntu-24.04 ==`, exit 0 | ✓ PASS |
| Installer runs green on Ubuntu 22.04 | `bash tests/docker/run.sh ubuntu-22.04` | `22/22 PASS`, `== PASS: agentlinux-install + bats on ubuntu-22.04 ==`, exit 0 | ✓ PASS |
| INST-05 zero-EACCES contract holds | `grep -cE 'EACCES\|permission denied' /var/log/agentlinux-install.log` inside fresh container | `0` | ✓ PASS |
| INST-02 byte-stability holds | PRE vs POST sha256 across 5 artefacts after two installer runs inside fresh container | `INST-02_PROOF: BYTE_STABLE` | ✓ PASS |
| DOC-02 CLAUDE.md owner correct | `stat -c '%U:%G' /home/agent/CLAUDE.md` | `agent:agent` | ✓ PASS |
| BHV-01 agent user passwd entry | `getent passwd agent` | `agent:x:1001:1001::/home/agent:/bin/bash` | ✓ PASS |
| Artefact modes correct | `stat -c %a` on all four config files | all `644` | ✓ PASS |
| No sudoers drop-in | `test -f /etc/sudoers.d/agentlinux` | NOT-PRESENT-OK | ✓ PASS |
| Phase 1 harness still green | `bash tests/harness/run.sh` | `104/104 @tests pass`, exit 0 | ✓ PASS |
| Shellcheck clean on all Phase 2 bash | `shellcheck --severity=warning --shell=bash --external-sources plugin/lib/*.sh plugin/bin/... tests/docker/run.sh tests/bats/helpers/*.bash` | exit 0 | ✓ PASS |
| Shfmt formatting clean | `shfmt -i 2 -ci -bn -d` on all bash files | exit 0, no diff | ✓ PASS |
| Workflow YAML parses | `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/test.yml"))'` | exit 0 | ✓ PASS |

## Requirements Coverage Audit

All 13 Phase 2 requirement IDs cross-referenced against `tests/bats/*.bats` @tests. Every requirement has ≥1 @test or is structurally satisfied by the harness.

| Req ID | Source Plans | Description | @test count | Status | Evidence |
|--------|-------------|-------------|-------------|--------|----------|
| INST-01 | 02-01, 02-02, 02-05 | Installer one-command on clean Ubuntu, exit 0, non-interactive | 2 | ✓ SATISFIED | `@test INST-01: installer log file exists after initial run`, `INST-01: installer log contains success banner`. Passes on 22.04 + 24.04. |
| INST-02 | 02-01, 02-02, 02-05 | Installer is idempotent (converges, byte-stable) | 1 | ✓ SATISFIED | `@test INST-02: re-running the installer is byte-stable (idempotency)` — sha256 diff across 5 artefacts. Passes. |
| INST-05 | 02-01, 02-02, 02-05 | No EACCES/permission-denied in transcript | 1 | ✓ SATISFIED | `@test INST-05: installer log contains no EACCES or 'permission denied' lines`. Passes. |
| BHV-01 | 02-03, 02-05 | Agent user exists with bash, home, UTF-8 locale | 4 | ✓ SATISFIED | `@test BHV-01` × 4 covering passwd entry, /etc/default/locale LANG + LC_ALL, locale -a availability. All pass. |
| BHV-02 | 02-04, 02-05 | Non-interactive SSH sees PATH + locale | 2 | ✓ SATISFIED | `@test BHV-02` × 2 (PATH + locale via `run_ssh`). Passes. |
| BHV-03 | 02-04, 02-05 | Cron sees PATH | 1 | ✓ SATISFIED | `@test BHV-03` (70s poll via `run_cron`). Passes. |
| BHV-04 | 02-04, 02-05 | systemd `User=agent` sees PATH + locale | 2 | ✓ SATISFIED | `@test BHV-04` × 2 (PATH + locale via `systemd-run --uid=agent --property=EnvironmentFile=/etc/agentlinux.env`). Passes on both 22.04 + 24.04 (dbus in Docker image). |
| BHV-05 | 02-04, 02-05 | sudo -u / sudo -u -i sees PATH (both variants) | 3 | ✓ SATISFIED (override) | `@test BHV-05` × 3: `run_sudo_u` (bash --login -c) + `run_sudo_u_i` (-i -c). Non-login `bash -c` variant deferred to v0.4+ (accepted override — see frontmatter). REQUIREMENTS.md BHV-05 note + ROADMAP §Phase 2 explicitly accept this as observable-behavior-satisfied. |
| BHV-06 | 02-04, 02-05 | Interactive bash login sees PATH + locale | 2 | ✓ SATISFIED | `@test BHV-06` × 2 (PATH + locale via `run_interactive` = `su - agent -c`). Passes. |
| DOC-02 | 02-03, 02-05 | /home/agent/CLAUDE.md exists + anti-pattern guidance | 4 | ✓ SATISFIED | `@test DOC-02` × 4: existence+owner, three anti-pattern greps. Passes. |
| TST-01 | 02-05 | Behavior-test suite covers every INST/BHV | structural + 22 @tests | ✓ SATISFIED (partial per milestone scope) | 22 @tests in `tests/bats/10-installer.bats` + `20-agent-user.bats`. Phase 2 portion complete; remaining per-phase coverage (RT/CLI/CAT/AGT) grows in Phases 3–5. Per ROADMAP note. |
| TST-02 | 02-05 | Docker bats matrix on 22.04 + 24.04 every PR | structural | ✓ SATISFIED | `.github/workflows/test.yml` `bats-docker` job: matrix [ubuntu-22.04, ubuntu-24.04], fail-fast=false, timeout=15min. YAML parses. Both matrix entries green locally. |
| TST-04 | 02-05 | Failures produce clear req-ID/expected/observed/log diagnostic | structural | ✓ SATISFIED | `tests/bats/helpers/assertions.bash::__fail` emits four canonical TAP comments. Inspected directly; shape matches contract. |

**13/13 Phase 2 requirement IDs satisfied.** No orphans.

**Orphan check:** REQUIREMENTS.md Traceability table maps the same 13 IDs to Phase 2 as ROADMAP; every one appears in at least one plan's `requirements` field (02-01 has 3, 02-02 has 3, 02-03 has 2, 02-04 has 5, 02-05 has 13 — superset). **Zero orphans.**

## Threat Model Coverage

All 15 Phase 2 STRIDE threats (T-02-01..T-02-15) covered across the plans.

| Threat ID | Category | Covered in Plan | Mitigation Evidence |
|-----------|----------|-----------------|---------------------|
| T-02-01 | Information Disclosure | 02-01, 02-02 | log primitives never iterate env; log.sh has no `env`/`set` dump helper |
| T-02-02 | Tampering | 02-01, 02-04 | `grep -Fxq`, `ensure_marker_block` awk-replace; no blind `echo >>` |
| T-02-03 | EoP | 02-01 | `as_user` enforces `-- "$@"` pattern; shell injection prevented |
| T-02-04 | DoS | 02-02 | `require_root` fails fast with exit 64 before mutations |
| T-02-05 | Tampering | 02-03 | `ensure_user` no-op if user exists; doesn't modify pre-existing agent |
| T-02-06 | Info Disclosure | 02-02 | Log file mode 0644, no secrets written (accept + review gate) |
| T-02-07 | Tampering | 02-03 | `ensure_marker_block` preserves user content outside `agentlinux-doc-02` tag |
| T-02-08 | Info Disclosure / EoP | 02-03, 02-04 | CLAUDE.md 0644 world-readable (policy, not secrets); PATH prefix only agent-owned paths |
| T-02-09 | Tampering | 02-04 | `install -m 0644 /dev/stdin` atomic overwrite + single-quoted heredoc (byte-identical); `AGENTLINUX_PROFILE_SOURCED` runtime guard |
| T-02-10 | Tampering | 02-04 | Literal PATH in cron.d heredoc (author-time, not runtime); atomic `install -m` |
| T-02-11 | Info Disclosure | 02-04 | agentlinux.env 0644 contains no secrets in Phase 2 (accept; Phase 3+ enforcement) |
| T-02-12 | EoP | 02-04 | Zero sudoers drop-in; confirmed `grep -q 'sudoers.d' 40-path-wiring.sh` returns nothing + runtime `test -f /etc/sudoers.d/agentlinux` = NOT-PRESENT |
| T-02-13 | Tampering (supply chain) | 02-05 | Canonical official images (ubuntu:22.04, ubuntu:24.04); apt only; no curl-pipe-bash in Dockerfile |
| T-02-14 | DoS | 02-05 | `trap 'cleanup; final_banner' EXIT` cleans containers; `AGENTLINUX_DOCKER_KEEP_CONTAINER=1` opt-in escape hatch |
| T-02-15 | Info Disclosure | 02-05 | Per-run ephemeral ed25519 SSH keypair; never committed; lives only for container's lifetime |

**15/15 threat IDs covered.**

## Invariant Checks

### Security invariants (CLAUDE.md critical rules)

| Invariant | Check | Result |
|-----------|-------|--------|
| No raw `sudo -u` outside `as_user.sh` | `grep -rn 'sudo -u' plugin/ --include='*.sh'` minus `as_user.sh` + comments | ✓ PASS — 6 matches, all in comments or docstrings describing the anti-pattern |
| No `/usr/local/bin/` writes | `grep -rn '/usr/local/bin/' plugin/` minus DOC-02 anti-pattern text | ✓ PASS — 1 match in `10-agent-user.sh` DOC-02 heredoc (the FORBIDDEN-list text itself) |
| No `sudo npm install -g` calls | `grep -rn 'sudo npm install -g' plugin/` | ✓ PASS — 2 matches both in doc comments / DOC-02 body enumerating the anti-pattern |
| No `/etc/sudoers.d/*` write in Phase 2 | runtime `test -f /etc/sudoers.d/agentlinux` inside clean-installed container | ✓ PASS — file does not exist |
| No TODO/FIXME/XXX in Phase 2 modified files | `grep -rn TODO\|FIXME\|XXX\|HACK\|PLACEHOLDER` in plugin/lib/, plugin/bin/, plugin/provisioner/, tests/bats/, tests/docker/ | ✓ PASS — zero matches (the one TODO in `plugin/cli/scripts/validate-catalog.mjs` belongs to Phase 1 / Plan 01-03, not Phase 2) |

### Style / lint invariants

| Invariant | Check | Result |
|-----------|-------|--------|
| shellcheck clean on all Phase 2 bash | `shellcheck --severity=warning --shell=bash --external-sources` on 10 files | ✓ PASS (exit 0) |
| shfmt formatting clean | `shfmt -i 2 -ci -bn -d` on 10 files | ✓ PASS (exit 0, no diff) |
| `#!/usr/bin/env bash` on every Phase 2 `.sh` / `.bash` / entrypoint | `head -1` check | ✓ PASS on 10/10 |
| `set -euo pipefail` on entrypoint + run.sh (executed scripts); sourced fragments inherit | grep + manual review | ✓ PASS (entrypoint + run.sh have it; libs + provisioners correctly inherit) |
| YAML parses (.github/workflows/test.yml) | `python3 -c 'import yaml; yaml.safe_load(...)'` | ✓ PASS |

### Harness invariants

| Invariant | Check | Result |
|-----------|-------|--------|
| Phase 1 harness meta-tests still green | `bash tests/harness/run.sh` | ✓ PASS — 104/104 @tests pass |
| `tests/docker/run.sh` executable | `test -x` | ✓ PASS |
| YAML matrix has both Ubuntu versions + fail-fast=false + timeout-minutes | grep test.yml | ✓ PASS |
| Every @test name starts with `<REQ-ID>:` (TST-07 gate) | grep `^@test "(INST-0[125]\|BHV-0[1-6]\|DOC-02):` | ✓ PASS — 22/22 matches |

## Gaps Found

**None.**

One documented deviation (BHV-05 plain `sudo -u agent bash -c` without `--login`) is covered by an explicit `overrides:` entry in the frontmatter. The override is well-documented across REQUIREMENTS.md (BHV-05 note with full rationale), ROADMAP.md (Phase 2 completion note), and 02-05-SUMMARY.md Deviations §1. The observable-behavior contract for BHV-05 is satisfied by the two login variants (`run_sudo_u` using `bash --login -c` + `run_sudo_u_i` using `sudo -u -H -i`); the non-login `bash -c` case requires sudoers/PAM work that Phase 2 CONTEXT explicitly locks out ("zero default sudoers drop-in") and is properly deferred to v0.4+.

## Human Verification Required

**None required for Phase 2 closure.**

The VALIDATION §"Manual-Only Verifications" listed one item: "systemd-in-Docker reliability on GH Actions runners (triple-run check)". This is a CI-runner-stability observation, not a phase-closure blocker — the 02-05-SUMMARY notes it is "deferred to the first post-merge workflow execution". The local Docker end-to-end run is 22/22 on both 22.04 and 24.04 inside real systemd-capable privileged containers (identical recipe to the GH Actions matrix); if GH Actions runners prove flaky in practice, the existing `SKIP_SYSTEMD_UNAVAILABLE` sentinel + `@qemu-only` tagging scheme already built into `invoke_modes.bash` + `20-agent-user.bats` handles the mitigation without structural change. No human action required before proceeding to Phase 3.

## Verdict

**passed** — Phase 2 acceptance gate GREEN.

- **6/6** ROADMAP Phase 2 success criteria verified end-to-end in systemd Docker on both Ubuntu 22.04 and 24.04 (22/22 bats tests pass per arm).
- **41/41** must-haves (aggregated across 5 plans' frontmatter) verified.
- **13/13** Phase 2 requirement IDs satisfied (INST-01/02/05, BHV-01..06, DOC-02, TST-01/02/04). Zero orphans.
- **15/15** Phase 2 STRIDE threat IDs (T-02-01..T-02-15) covered across plans.
- **Zero** EACCES/permission-denied lines in installer transcript (INST-05 contract).
- **Byte-stable** re-runs confirmed independently (INST-02 contract).
- **Zero** sudoers drop-in + zero `/usr/local/bin/` shim + zero raw `sudo -u` outside `as_user.sh` (CLAUDE.md invariants).
- **Phase 1 harness still green** — 104/104 meta-tests pass (no regression).
- **TST-07 gate GREEN** — every Phase 2 req-ID has ≥1 ID-prefixed @test.
- **One accepted override** (BHV-05 plain bash-c path → v0.4+ PAM/sudoers work) covered by frontmatter `overrides:` and documented in three separate sources.

Phase 3 (Node.js Runtime + Per-User npm Prefix) may begin on top of this harness. The `invoke_modes.bash` + `assertions.bash` API is stable; extending bats coverage for RT-01..RT-04 follows the same test-ID-prefix pattern and re-uses the same six-mode matrix.

## VERIFICATION COMPLETE

---

_Verified: 2026-04-18_
_Verifier: Claude (gsd-verifier)_
