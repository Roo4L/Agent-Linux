# Phase 2: Installer Foundation + Agent User — Research

**Researched:** 2026-04-18
**Domain:** Bash installer conventions, Ubuntu agent-user provisioning, six-mode PATH/locale wiring, Docker+bats test harness
**Confidence:** HIGH

## Summary

Phase 2 is AgentLinux's first large bash surface: it turns a clean Ubuntu 22.04 or 24.04 into a system with a correctly-owned `agent` user whose login environment (PATH + UTF-8 locale + bash shell) works identically across six invocation modes — interactive login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, and `sudo -u agent -i`. Node.js, the registry CLI, and agents do not ship in this phase; the measurable outcome is a clean-run installer whose log contains zero `EACCES` / `permission denied` lines and whose idempotent re-run is a no-op.

Three technical facts dominate the plan:

1. **`/etc/profile.d/*.sh` is not sourced by `sudo -u agent <cmd>` (non-login) nor by systemd nor by cron.** Relying on profile.d alone is a false-positive trap the v0.2.0 provisioner learned the hard way. Each mode needs its own wire.
2. **Ubuntu 22.04/24.04 ships `Defaults secure_path` in `/etc/sudoers` by default** — this SHADOWS any `env_keep+=PATH` the agentlinux drop-in adds. The drop-in either needs its own `secure_path` expansion, or the agent's `~/.bashrc` (sourced when `sudo -u agent bash -c '<cmd>'` is used) must populate PATH from scratch.
3. **Ubuntu 24.04 cloud images ship with `C.UTF-8` pre-generated and `/etc/default/locale` pre-seeded to `LANG=C.UTF-8`** (verified on this host). `locale-gen` is therefore a no-op on stock cloud images — but the installer MUST still enforce it because developers may strip locales to shrink images, and Docker slim images omit it entirely.

**Primary recommendation:** Implement a four-file PATH/locale strategy (`/etc/profile.d/agentlinux.sh`, `~agent/.bashrc` guard, `/etc/sudoers.d/agentlinux` with `secure_path` expansion, `/etc/agentlinux.env` for systemd + cron header), an `ensure_line_in_file` idempotency primitive with marker-comment blocks, `assert_no_eacces` + six-mode `invoke_modes.bash` helpers, and a privileged Docker image with `/sbin/init` as CMD for BHV-04 coverage. Ship bats inside the Docker image via `apt install bats` (1.8+ on 22.04, 1.10+ on 24.04 — both adequate).

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Installer UX & Logging**
- Root-privilege check fails fast at top of `plugin/bin/agentlinux-install` with a clear error if `EUID != 0` (no auto-sudo, no lazy failure).
- Structured logging via `plugin/lib/log.sh` — `log_info`, `log_warn`, `log_error`, timestamped — all stdout/stderr tee'd to `/var/log/agentlinux-install.log` so INST-05 can grep `EACCES|permission denied` against the full transcript.
- `set -euo pipefail` plus a top-level `trap ERR` that prints a failure banner naming the failing step and the log path before exit.
- Phase 2 flags: `--help`, `--version`, `--purge` (stub warning — real wire-up lands in Phase 4/6), `--verbose` (sets DEBUG log level).

**PATH & Environment Wiring (six-mode matrix)**
- **Interactive bash login & `sudo -u agent -i`**: `/etc/profile.d/agentlinux.sh` (mode 0644) — single source covering both cases via `/etc/profile` sourcing.
- **Cron**: Write `PATH=...` header into `/etc/cron.d/agentlinux` template; document the same convention for user crontabs.
- **systemd `User=agent`**: Drop `/etc/agentlinux.env` via installer and reference it from units with `EnvironmentFile=/etc/agentlinux.env`. Docs include a sample unit.
- **Non-interactive SSH & `sudo -u agent`**: `/etc/profile.d/agentlinux.sh` plus agent's `~/.bashrc` with a top-of-file guard that sources the profile.d fragment. `/etc/environment` is populated as a last-resort fallback. `.ssh/environment` is rejected (requires `PermitUserEnvironment yes`, too invasive).

**Sudoers & Privilege Posture**
- **Zero sudo for the agent user.** Post-install, the agent owns its home + (in Phase 3) npm prefix; no root-privileged operations performed by agent tooling.
- Any sudoers drop-in lives at `/etc/sudoers.d/agentlinux`, mode 0440, validated with `visudo -cf` before being moved into place. (Phase 2 ships no default drop-in; this is the contract when one is added later.)
- No `agentlinux-users` group or wildcard `sudo -u agent` rule.
- `--purge` uninstall path (wired in Phase 4) removes `/etc/sudoers.d/agentlinux` along with the agent user and home.

**Test Harness & CI Matrix**
- Docker matrix: one `tests/docker/Dockerfile.ubuntu-22.04` + `tests/docker/Dockerfile.ubuntu-24.04`; `tests/docker/run.sh <version>` builds the image, runs the installer inside, then runs the bats suite. Matches HARNESS.md §1.1 layout.
- `tests/bats/helpers/invoke_modes.bash` exposes six helpers — `run_interactive`, `run_ssh`, `run_cron`, `run_systemd_user`, `run_sudo_u`, `run_sudo_u_i` — each returning `$status`/`$output` so bats tests can loop over modes.
- `tests/bats/helpers/assertions.bash`: `assert_no_eacces`, `assert_path_has <bin>`, `assert_exit_zero`; every failure message prints the requirement ID, expected value, observed value, and log file path (satisfies TST-04).
- systemd + cron + openssh-server run inside privileged Docker on every PR (BHV-03..05 covered on PR). Any mode that proves flaky in Docker gets a `@qemu-only` tag.

### Claude's Discretion

- Exact wording/layout of CLAUDE.md placed at `/home/agent/CLAUDE.md` per DOC-02, provided it tells agent tooling NOT to create shim/wrapper workarounds at `/usr/local/bin/` or elsewhere.
- Internal split between `plugin/provisioner/10-agent-user.sh`, `plugin/provisioner/40-path-wiring.sh` (etc.) vs fewer/more numbered steps.
- Shell helper function shapes inside `plugin/lib/log.sh`, `plugin/lib/idempotency.sh`, `plugin/lib/as_user.sh`, `plugin/lib/distro_detect.sh` — any shape that passes `shellcheck --severity=warning --shell=bash --external-sources` and the installer behavior tests.
- Specific `@qemu-only` tags (if any) — Claude picks per test based on Docker reliability during execution.

### Deferred Ideas (OUT OF SCOPE for Phase 2)

- Remote-fetch catalog with embedded fallback (CAT-04) — v0.4+.
- `.deb` distribution as first-class (INF-02) — v0.4+.
- Multi-distro distro detection (DST-01..DST-03) — v0.4+.
- Per-agent sandboxing (USR-05) — v0.4+.
- Fleet / config-management integration.
- Full QEMU reliance in CI (skipping Docker for everything) — ADR-007 locks the dual model.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INST-01 | Installer runs one-command non-interactive on clean Ubuntu 22.04/24.04; non-zero exit on failure | Strict-mode + trap pattern (§Idempotency Primitives), distro-detect (§Distro Detection) |
| INST-02 | Idempotent re-run converges; no dup PATH lines, sudoers entries, skel files | `ensure_line_in_file` marker blocks (§Idempotency), profile.d guard (§Code Examples) |
| INST-05 | Zero `EACCES` / `permission denied` on stdout or stderr | `tee` to log + greppability (§Logging), `assert_no_eacces` helper (§Validation) |
| BHV-01 | Agent user: bash shell, real home, UTF-8 locale (`LANG`, `LC_ALL`) | `useradd -m -s /bin/bash agent` + locale-gen (§Locale Generation) |
| BHV-02 | Non-interactive SSH: command runs, PATH correct | `~/.bashrc` guard sources profile.d (§PATH Wiring Matrix) |
| BHV-03 | Cron: command runs, PATH correct | PATH header in `/etc/cron.d/agentlinux` (§PATH Wiring Matrix) |
| BHV-04 | systemd `User=agent`: command runs, PATH correct | `EnvironmentFile=/etc/agentlinux.env` pattern (§PATH Wiring Matrix, §systemd Docker Testing) |
| BHV-05 | `sudo -u agent` and `sudo -u agent -i`: command runs, PATH correct | sudoers `secure_path` override vs bash re-read of `.bashrc` (§Sudoers Secure Path Trap) |
| BHV-06 | Interactive bash login: command runs, PATH correct | `/etc/profile.d/agentlinux.sh` (§PATH Wiring Matrix) |
| DOC-02 | `/home/agent/CLAUDE.md` placed with guidance against shim workarounds | Anti-pattern list from Claude Code self-update history (§DOC-02 Content Guide) |
| TST-01 | Behavior-test suite covers every BHV/RT/AGT/CLI/CAT/INST requirement (partial for Phase 2) | Bats layout, six-mode matrix helpers (§Validation Architecture) |
| TST-02 | Tests run inside Docker harness on Ubuntu 22.04 + 24.04 every PR | Dockerfile + run.sh skeleton (§Code Examples, §systemd Docker Testing) |
| TST-04 | Failures produce clear diagnostic (req ID, expected, observed, logs) | Assertion-helper diagnostic contract (§Validation Architecture, §Code Examples) |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Root-privilege gate + arg parsing | Installer entrypoint (`plugin/bin/agentlinux-install`) | — | Single entrypoint owns CLI surface; provisioners assume root |
| Structured logging + log tee | `plugin/lib/log.sh` | installer entrypoint | Library sets up FDs; entrypoint installs `exec > >(tee)` pipe once |
| Idempotency primitives | `plugin/lib/idempotency.sh` | every provisioner | Single source of truth for `ensure_*` helpers; forbids raw `echo >>` |
| `as_user` keystone | `plugin/lib/as_user.sh` | every provisioner (Phase 3+) | Phase 2 has no agent-owned commands yet, but the helper ships now so Phase 3/4/5 cannot forget it |
| Distro detection | `plugin/lib/distro_detect.sh` | entrypoint | Fail fast before provisioners run |
| Agent-user creation | `plugin/provisioner/10-agent-user.sh` | — | `useradd`, skel, `/home/agent/CLAUDE.md` (DOC-02) |
| Locale enforcement | `plugin/provisioner/20-locale.sh` OR folded into `10-` | — | `locale-gen C.UTF-8` + `update-locale`; tiny enough to fold |
| Six-mode PATH wiring | `plugin/provisioner/40-path-wiring.sh` | — | The single load-bearing provisioner; writes four artefacts: profile.d, `~agent/.bashrc` guard, sudoers drop-in, `/etc/agentlinux.env` |
| Behavior-test assertions | `tests/bats/10-installer.bats` (INST-01/02/05) + `tests/bats/20-agent-user.bats` (BHV-01..06) | `tests/bats/helpers/*.bash` | One .bats per requirement-group, helpers factor six-mode dispatch |
| Docker harness | `tests/docker/Dockerfile.ubuntu-{22,24}.04` + `tests/docker/run.sh` | CI workflow | Dockerfile: systemd + cron + openssh + bats installed; run.sh drives build+install+bats |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `bash` | 5.x (Ubuntu 22.04 ships 5.1, 24.04 ships 5.2) | Installer + provisioner language | Required by `set -o pipefail`, arrays, `[[ ]]`. POSIX `sh` is insufficient; we explicitly target bash dialect per HARNESS.md §1.2. `[VERIFIED: Ubuntu package index]` |
| `bats-core` | 1.10.0+ (Ubuntu 24.04 apt); 1.8.2 on 22.04 apt | Behavior-test framework | HARNESS.md §1.3 names it. Install via apt inside Docker image. `[VERIFIED: packages.ubuntu.com for "bats"]` |
| `shellcheck` | 0.9.0+ (apt) | Static analysis — pre-commit gate | Already wired in Phase 1 `.pre-commit-config.yaml`. `[VERIFIED: plugin/CLAUDE.md references]` |
| `shfmt` | 3.9.0+ | Formatter (`-i 2 -ci -bn`) | Already wired in Phase 1. `[VERIFIED: .pre-commit-config.yaml]` |
| `visudo` | included in `sudo` package | Sudoers drop-in validation | `visudo -cf <file>` checks syntax before the installer `mv`s into place. `[CITED: man sudoers]` |
| `locale-gen` / `update-locale` | `locales` package | UTF-8 locale enforcement | Debian/Ubuntu standard. `[CITED: help.ubuntu.com/community/Locale]` |
| `useradd`, `usermod`, `chage` | `passwd` package | Agent user creation | Ubuntu default; POSIX-like. `[VERIFIED: /usr/sbin/useradd on this host]` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `bats-support` | 0.3.0 | `fail`, `assert` primitives | Optional — helpful but increases helper footprint. HARNESS.md does not mandate; recommend deferring to Phase 3+ if assertion helpers grow. `[CITED: github.com/bats-core/bats-support]` |
| `bats-assert` | 2.1.0 | `assert_output`, `assert_success`, `refute_output` | Same deferral rationale — Phase 2 hand-rolls minimal helpers to keep the surface small. `[CITED: github.com/bats-core/bats-assert]` |
| `cron` (Ubuntu: `cron` package) | 3.0+ | System cron for BHV-03 | Must be installed in Docker image (`apt install -y cron`) and started (`service cron start` or via `/sbin/init`). `[VERIFIED: Ubuntu 22.04/24.04 apt]` |
| `openssh-server` | 8.9+ | SSH daemon for BHV-02 | Dockerfile must install, generate host keys, `service ssh start`. `[VERIFIED: Ubuntu apt]` |
| `systemd` (`systemd` package, `/sbin/init`) | 249 (22.04) / 255 (24.04) | Systemd daemon for BHV-04 | Privileged Docker + `--tmpfs /run` + `--tmpfs /tmp` + `-v /sys/fs/cgroup:/sys/fs/cgroup:ro` OR `--cgroupns=host`. CMD is `/sbin/init`. `[CITED: docs.docker.com, jrei/systemd-ubuntu]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| apt-installed bats | `npm install --no-save bats` or vendored `bats-core` clone | Phase 1 already supports all three fallback paths in `tests/harness/run.sh`. For Phase 2's Docker image, apt is simplest and matches `tests/docker/Dockerfile.ubuntu-*` being the env. Keep apt unless container build becomes a bottleneck. |
| privileged Docker for BHV-04 | `jrei/systemd-ubuntu` base image | The `jrei` image embeds systemd pre-config but adds a third-party dependency. Build our own FROM `ubuntu:24.04` + `apt install systemd cron openssh-server bats` keeps supply chain short. `[CITED: jrei/systemd-ubuntu on Docker Hub]` |
| PATH via `~/.bashrc` | PATH via `~/.profile` | `~/.bashrc` is sourced for non-interactive bash invocations (including `ssh host 'cmd'` when remote command is bash and no `-l`); `~/.profile` is only read on login shells. CONTEXT.md locks `~/.bashrc` for this reason. `[CITED: Bash manual — INVOCATION section]` |
| `.ssh/environment` for SSH PATH | — | Requires `PermitUserEnvironment yes` in sshd_config, which is default-off and broadly disrecommended; invasive. Already rejected in CONTEXT.md. `[CITED: sshd_config(5)]` |
| nvm/fnm shell-hook node | NodeSource apt package | ADR-005 locks NodeSource. Out of scope for Phase 2 anyway (Phase 3 concern). |

**Installation (inside Docker image):**

```bash
apt-get update
apt-get install -y --no-install-recommends \
  systemd systemd-sysv cron openssh-server \
  bats locales sudo ca-certificates \
  bash coreutils util-linux
```

**Version verification (run before writing Phase 2 plans):**

```bash
# Ubuntu 22.04 jammy
apt-cache madison bats      # Expect 1.8.2-1
apt-cache madison systemd   # Expect 249.x
# Ubuntu 24.04 noble
apt-cache madison bats      # Expect 1.10.0-1
apt-cache madison systemd   # Expect 255.x
```

## Architecture Patterns

### System Architecture Diagram

```
Clean Ubuntu 22.04/24.04 host (root invocation)
  │
  │  bash plugin/bin/agentlinux-install  [+ optional --verbose, --help, --version]
  ▼
┌──────────────────────────────────────────────────────────────────────┐
│ plugin/bin/agentlinux-install                                         │
│   set -euo pipefail                                                   │
│   trap on_error ERR                                                   │
│   exec > >(tee -a /var/log/agentlinux-install.log) 2>&1              │
│   require_root   ← EUID != 0 fails fast                               │
│   source plugin/lib/{log,distro_detect,idempotency,as_user}.sh        │
│   parse_args    ← --help / --version / --verbose / --purge-stub       │
│   detect_distro ← ubuntu 22.04|24.04 or die                           │
│   run_provisioners_in_order                                           │
└──────────────────────────────────────────────────────────────────────┘
  │
  ├───► plugin/provisioner/10-agent-user.sh
  │         ensure_user agent (useradd -m -s /bin/bash -U agent)
  │         ensure_dir /home/agent 0755 agent:agent
  │         install -m 0644 DOC02_CLAUDE_MD /home/agent/CLAUDE.md (chown agent)
  │         ensure locale-gen C.UTF-8  +  update-locale LANG=C.UTF-8
  │
  ├───► plugin/provisioner/40-path-wiring.sh
  │         write /etc/profile.d/agentlinux.sh        (0644 root:root)
  │         ensure_line_in_file 'source /etc/profile.d/agentlinux.sh'
  │                              /home/agent/.bashrc
  │         write /etc/agentlinux.env                 (0644 root:root)
  │         write /etc/cron.d/agentlinux              (0644 root:root, PATH header only)
  │         # NOTE: no sudoers drop-in in Phase 2 (CONTEXT lock)
  │
  ▼
System state after clean run:
  /home/agent  (UID 1001, shell /bin/bash, bash-shell, UTF-8 locale ready)
  /home/agent/CLAUDE.md        (DOC-02: anti-shim guidance)
  /home/agent/.bashrc          (guarded source of profile.d fragment)
  /etc/profile.d/agentlinux.sh (guarded PATH + locale export)
  /etc/agentlinux.env          (KEY=VALUE lines for systemd EnvironmentFile)
  /etc/cron.d/agentlinux       (PATH=... header; no default jobs)
  /var/log/agentlinux-install.log  (grep-able transcript; no EACCES lines)
  /etc/default/locale          (LANG=C.UTF-8)
  ❌ NO /etc/sudoers.d/agentlinux  (deferred to later phase)
  ❌ NO /usr/local/bin/agentlinux  (no CLI shim — Phase 4)
```

### Component Responsibilities

| File | Responsibility | Size estimate |
|------|----------------|---------------|
| `plugin/bin/agentlinux-install` | Root check, arg parsing, log tee, distro detect, provisioner dispatch | 80-120 lines |
| `plugin/lib/log.sh` | `log_info`/`log_warn`/`log_error` with ISO-8601 timestamp + level tag; colors gated on `[[ -t 2 ]]` | 40-60 lines |
| `plugin/lib/idempotency.sh` | `ensure_user`, `ensure_line_in_file`, `ensure_dir`, `ensure_file` (with marker block helper) | 80-120 lines |
| `plugin/lib/as_user.sh` | `as_user <user> <cmd ...>` wrapping `sudo -u <user> -H -E -- <cmd>` | 15-25 lines |
| `plugin/lib/distro_detect.sh` | Read `/etc/os-release`; assert `ID=ubuntu` + `VERSION_ID ∈ {22.04, 24.04}`; export `AGENTLINUX_DISTRO_VERSION` | 30-50 lines |
| `plugin/provisioner/10-agent-user.sh` | `ensure_user agent` + locale + DOC-02 CLAUDE.md placement | 40-60 lines |
| `plugin/provisioner/40-path-wiring.sh` | Writes 4 artefacts for the six-mode matrix | 80-120 lines |
| `tests/bats/10-installer.bats` | INST-01/02/05 (installer idempotency + exit code + no-EACCES) | 60-100 lines |
| `tests/bats/20-agent-user.bats` | BHV-01..06 (user attrs + six-mode matrix) | 100-150 lines |
| `tests/bats/helpers/invoke_modes.bash` | `run_interactive`, `run_ssh`, `run_cron`, `run_systemd_user`, `run_sudo_u`, `run_sudo_u_i` | 80-120 lines |
| `tests/bats/helpers/assertions.bash` | `assert_no_eacces`, `assert_path_has`, `assert_exit_zero` with TST-04 diagnostic format | 40-60 lines |
| `tests/docker/Dockerfile.ubuntu-22.04` | `FROM ubuntu:22.04` + systemd + cron + openssh + bats | 30-50 lines |
| `tests/docker/Dockerfile.ubuntu-24.04` | Same, FROM 24.04 | 30-50 lines |
| `tests/docker/run.sh` | Build → run installer → run bats; single entrypoint called by CI matrix | 60-90 lines |

### Recommended Project Structure (delta from Phase 1)

```
plugin/
├── bin/agentlinux-install                [REPLACE stub body]
├── lib/
│   ├── log.sh                            [NEW]
│   ├── idempotency.sh                    [NEW]
│   ├── as_user.sh                        [NEW — keystone, usage is Phase 3+]
│   └── distro_detect.sh                  [NEW]
└── provisioner/
    ├── 10-agent-user.sh                  [NEW — user + locale + DOC-02 CLAUDE.md]
    └── 40-path-wiring.sh                 [NEW — four artefacts]

tests/
├── bats/
│   ├── 10-installer.bats                 [NEW — INST-01/02/05]
│   ├── 20-agent-user.bats                [NEW — BHV-01..06]
│   └── helpers/
│       ├── invoke_modes.bash             [NEW]
│       └── assertions.bash               [NEW]
└── docker/
    ├── Dockerfile.ubuntu-22.04           [NEW]
    ├── Dockerfile.ubuntu-24.04           [NEW]
    └── run.sh                            [NEW]
```

### Pattern 1: `set -euo pipefail` + ERR trap + log tee at entrypoint

**What:** The installer sets strict mode once at the top, installs an `ERR` trap that logs the failing step, and redirects stdout+stderr through `tee` so the entire transcript lands in one greppable log file.

**When to use:** Once, in `plugin/bin/agentlinux-install`. Every sourced library + dispatched provisioner inherits the trap and FDs.

**Example:**

```bash
#!/usr/bin/env bash
# plugin/bin/agentlinux-install
# Source: pattern verified in arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/
#         + sipb.mit.edu/doc/safe-shell/
set -euo pipefail

readonly AGENTLINUX_VERSION="0.3.0"
readonly LOG_FILE="/var/log/agentlinux-install.log"
readonly LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
readonly PROV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../provisioner" && pwd)"

# Tee BEFORE sourcing libraries so log_* output lands in the log.
# INST-05 greps this file for EACCES|permission denied across the full run.
exec > >(tee -a "$LOG_FILE") 2>&1

# shellcheck source=../lib/log.sh
. "$LIB_DIR/log.sh"

on_error() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]:-unknown}
  local src=${BASH_SOURCE[1]:-unknown}
  log_error "installer failed at ${src}:${line_no} (exit ${exit_code})"
  log_error "full transcript: ${LOG_FILE}"
  exit "$exit_code"
}
trap on_error ERR

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log_error "agentlinux-install must run as root (EUID != 0). Re-run under sudo."
    exit 64  # EX_USAGE
  fi
}

# shellcheck source=../lib/distro_detect.sh
. "$LIB_DIR/distro_detect.sh"
# shellcheck source=../lib/idempotency.sh
. "$LIB_DIR/idempotency.sh"
# shellcheck source=../lib/as_user.sh
. "$LIB_DIR/as_user.sh"

main() {
  require_root
  parse_args "$@"
  log_info "agentlinux-install v${AGENTLINUX_VERSION} starting"
  detect_distro  # exports AGENTLINUX_DISTRO_VERSION or dies
  for step in "$PROV_DIR"/[0-9][0-9]-*.sh; do
    log_info "running $(basename "$step")"
    # shellcheck disable=SC1090
    . "$step"
  done
  log_info "agentlinux-install complete"
}
main "$@"
```

Sources: [SIPB: safe shell scripts](https://sipb.mit.edu/doc/safe-shell/), [mohanpedala: set -euxo pipefail](https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425)

### Pattern 2: `ensure_line_in_file` idempotency with marker-comment blocks

**What:** Grep-then-append so re-runs do not duplicate lines. For multi-line fragments, use a begin/end marker block and replace the block atomically.

**When to use:** Any time the installer writes to a file it does not own exclusively — `~agent/.bashrc`, `/etc/environment`. For files the installer owns exclusively (`/etc/profile.d/agentlinux.sh`, `/etc/agentlinux.env`), just `install -m 0644` the whole file.

**Example:**

```bash
# plugin/lib/idempotency.sh
# Pattern source: arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/
# Idempotency primitive: append <line> to <file> only if not already present.
ensure_line_in_file() {
  local line=$1
  local file=$2
  # -F: fixed string (no regex); -q: quiet; -x: whole-line match
  if ! grep -Fxq -- "$line" "$file" 2>/dev/null; then
    printf '%s\n' "$line" >>"$file"
    log_info "added line to ${file}"
  fi
}

# Marker-block primitive: replace content between begin/end markers atomically.
# Survives edits to the block between runs (delete old, write new).
# Callers pass the block content on stdin.
ensure_marker_block() {
  local file=$1
  local tag=$2  # e.g. "agentlinux-path-wiring"
  local begin="# >>> ${tag} begin >>>"
  local end="# <<< ${tag} end <<<"
  local content
  content=$(cat)
  local tmp
  tmp=$(mktemp)
  # Remove old block if present, then append new one.
  if [[ -f $file ]]; then
    awk -v b="$begin" -v e="$end" '
      $0 == b { in_block=1; next }
      $0 == e { in_block=0; next }
      !in_block { print }
    ' "$file" >"$tmp"
  fi
  {
    printf '%s\n' "$begin"
    printf '%s\n' "$content"
    printf '%s\n' "$end"
  } >>"$tmp"
  install -m 0644 "$tmp" "$file"
  rm -f "$tmp"
}

ensure_user() {
  local user=$1
  if id "$user" >/dev/null 2>&1; then
    log_info "user ${user} already exists (no-op)"
  else
    useradd --create-home --shell /bin/bash --user-group "$user"
    log_info "created user ${user}"
  fi
}

ensure_dir() {
  local path=$1
  local mode=$2
  local owner=$3
  if [[ ! -d $path ]]; then
    install -d -m "$mode" -o "${owner%:*}" -g "${owner#*:}" "$path"
  else
    chmod "$mode" "$path"
    chown "$owner" "$path"
  fi
}
```

Source: [arslan.io — idempotent bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)

### Pattern 3: Distro detection — read `/etc/os-release`, assert, die fast

**Example:**

```bash
# plugin/lib/distro_detect.sh
# Source: man os-release; Ubuntu guarantees /etc/os-release presence since 16.04.
detect_distro() {
  if [[ ! -r /etc/os-release ]]; then
    log_error "cannot read /etc/os-release; unsupported system"
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ ${ID:-} != "ubuntu" ]]; then
    log_error "unsupported distro: ID=${ID:-unset} (required: ubuntu)"
    exit 1
  fi
  case "${VERSION_ID:-}" in
    22.04 | 24.04)
      export AGENTLINUX_DISTRO_VERSION="$VERSION_ID"
      log_info "detected ubuntu ${VERSION_ID}"
      ;;
    *)
      log_error "unsupported ubuntu version: ${VERSION_ID:-unset} (required: 22.04 or 24.04)"
      exit 1
      ;;
  esac
}
```

Source: [systemd os-release(5)](https://www.freedesktop.org/software/systemd/man/os-release.html)

### Pattern 4: The six-mode PATH/locale wiring — four artefacts

**What:** Every invocation mode reads environment from a different source; four files cover all six.

**When to use:** `plugin/provisioner/40-path-wiring.sh` — the single most load-bearing Phase 2 file.

**Example artefacts:**

```bash
# Artefact 1: /etc/profile.d/agentlinux.sh — BHV-06 (interactive login), BHV-05 (sudo -u -i)
#   Sourced by /etc/profile (login shells).
#   Guard prevents double-append if the file is re-sourced in the same session.
cat <<'PROFILE' > /etc/profile.d/agentlinux.sh
# AgentLinux login environment (generated by agentlinux-install)
# Sourced by interactive login shells and `sudo -u agent -i`.
[ -n "${AGENTLINUX_PROFILE_SOURCED:-}" ] && return
export AGENTLINUX_PROFILE_SOURCED=1
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
# Phase 3 will prepend $HOME/.npm-global/bin here.
case ":${PATH}:" in
  *:/home/agent/.local/bin:*) : ;;
  *) PATH="/home/agent/.local/bin:${PATH}" ;;
esac
export PATH
PROFILE
chmod 0644 /etc/profile.d/agentlinux.sh

# Artefact 2: /home/agent/.bashrc guard — BHV-02 (non-interactive SSH), BHV-05 (sudo -u agent)
#   Non-login bash shells read ~/.bashrc. Guard sources the profile.d fragment
#   so the same PATH expansion applies.
ensure_marker_block /home/agent/.bashrc "agentlinux" <<'BASHRC'
# Sourced for non-login bash shells (ssh host 'cmd', sudo -u agent bash -c 'cmd').
if [ -f /etc/profile.d/agentlinux.sh ]; then
  . /etc/profile.d/agentlinux.sh
fi
BASHRC
chown agent:agent /home/agent/.bashrc

# Artefact 3: /etc/agentlinux.env — BHV-04 (systemd User=agent)
#   systemd units reference this via `EnvironmentFile=/etc/agentlinux.env`.
#   Cron `/etc/cron.d/agentlinux` uses the same values in its header.
#   FORMAT: KEY=VALUE, no export, no shell expansion.
cat <<'ENVFILE' > /etc/agentlinux.env
PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
LANG=C.UTF-8
LC_ALL=C.UTF-8
ENVFILE
chmod 0644 /etc/agentlinux.env

# Artefact 4: /etc/cron.d/agentlinux — BHV-03 (cron)
#   The PATH= line at the top of a cron.d file applies to every job below it.
#   Phase 2 ships no jobs; the PATH= header is the contract.
cat <<'CRON' > /etc/cron.d/agentlinux
# AgentLinux cron environment (generated by agentlinux-install).
# Any agent cron job placed in this file inherits the PATH/locale below.
PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
LANG=C.UTF-8
LC_ALL=C.UTF-8
# Phase 2 ships no default jobs. Example shape (do not uncomment):
# 0 3 * * * agent /usr/bin/true
CRON
chmod 0644 /etc/cron.d/agentlinux
```

Sources: [systemd.exec(5) EnvironmentFile](https://www.freedesktop.org/software/systemd/man/systemd.exec.html), [cron PATH behavior](https://cronitor.io/guides/cron-environment-variables), [Baeldung: load env in cron](https://www.baeldung.com/linux/load-env-variables-in-cron-job)

### Pattern 5: `as_user` keystone

**What:** Single function routing every agent-owned command through `sudo -u agent -H -E --`. Lives in `plugin/lib/as_user.sh` so every future provisioner, catalog recipe, and CLI command has one place to enforce the rule.

**When to use:** Phase 2 has no agent-owned commands yet, but the helper ships NOW so Phase 3 (`npm install -g`), Phase 4 (CLI install), Phase 5 (agent tool install) physically cannot skip it.

**Example:**

```bash
# plugin/lib/as_user.sh
# Keystone: route all commands that must run as a non-root user through here.
# `-H` forces $HOME=target-user-home; `-E` preserves the environment (overridden
# later by the sudoers secure_path — see Pitfall §Sudoers Secure Path Trap);
# `--` separates sudo options from the user's command+args.
as_user() {
  local user=$1
  shift
  if [[ $# -eq 0 ]]; then
    log_error "as_user: no command given"
    return 64
  fi
  # -i is NOT used here. Use as_user_login() for login-shell semantics.
  sudo -u "$user" -H -E -- "$@"
}

as_user_login() {
  local user=$1
  shift
  sudo -u "$user" -H -i -- "$@"
}
```

Sources: [man sudo(8)](https://manpages.ubuntu.com/manpages/noble/man8/sudo.8.html), [Baeldung: sudo env vars](https://www.baeldung.com/linux/sudo-manage-environment-variables)

### Anti-Patterns to Avoid

- **`echo "export PATH=..." >> /home/agent/.bashrc` (blind append)** — breaks INST-02 idempotency. Use `ensure_line_in_file` or `ensure_marker_block`.
- **`source /etc/profile.d/agentlinux.sh` from within a provisioner** — the installer runs as root; sourcing the agent-targeted profile.d fragment pollutes root's environment. Always `install` the file, never execute it during the installer.
- **`eval $(locale)` or `export LANG=C.UTF-8` only** — passing `LANG=C.UTF-8` without `locale-gen` / `update-locale` leaves the system locale unset. BHV-01 tests assert `LANG` + `LC_ALL` are readable *inside each invocation mode*, not just by root during install.
- **`sudo -u agent <cmd>` (without `-H`)** — leaves `$HOME=/root`. Node looks up `~/.npmrc` via `$HOME`; `sudo npm install -g` (what we ban) and `as_user agent npm install -g` (what we require) both need `$HOME=/home/agent`. `-H` is load-bearing.
- **Relying on `trap ERR` without `set -e`** — `ERR` only fires when `set -e` would exit. Under `set +e`, commands can fail silently without tripping the trap.
- **Running the installer inside a non-systemd Docker container and asserting BHV-04** — `systemd-run --user=agent` fails without PID 1 being `/sbin/init`. Dockerfile must set `CMD ["/sbin/init"]` and `docker run --privileged --tmpfs /run --tmpfs /tmp` (or `--cgroupns=host`). A BHV-04 pass in a non-systemd container is a false positive.
- **Unconditional `|| true`** — hides real failures. Allowed only at documented skip paths (e.g., `locale-gen C.UTF-8 || true` when `C.UTF-8` is a built-in that `locale-gen` may not register — followed by `locale -a | grep -iq c.utf` to verify outcome).
- **Wrapper shims under `/usr/local/bin/`** (DOC-02 anti-pattern) — breaks Claude Code's `claude update` self-update; the canonical bug this entire project exists to eliminate.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idempotent line insertion | Blind `echo >> file` or custom sed logic | `grep -Fxq` before append, or marker-block with awk | Blind append breaks INST-02; sed-in-place has edge cases with newlines, escaping, and atomicity |
| Sudoers validation | Write sudoers drop-in directly without syntax check | `visudo -cf <file>` before `install -m 0440` | A malformed sudoers file can lock the system out of `sudo` entirely; `visudo -cf` is the official pre-check |
| Log tee with timestamps | Roll your own `exec >(awk)` pipeline | `exec > >(tee -a "$LOG")` at entrypoint + `log_info` prepends ISO-8601 timestamp | `tee` subshell handles SIGPIPE; rolling your own needs careful FD dup/close discipline |
| Distro detection | Parse `lsb_release -a` or `/etc/issue` | Source `/etc/os-release` | `/etc/os-release` is standardized by systemd, present on all modern Ubuntus; `lsb_release` is optional (`lsb-release` pkg may not be installed) |
| Systemd in Docker for BHV-04 | Custom `docker init` script | `CMD ["/sbin/init"]` + privileged flags + bind `/sys/fs/cgroup` | Every shortcut is a known false positive; the canonical recipe has been battle-tested in `jrei/systemd-ubuntu` |
| SSH keypair for BHV-02 tests | Hard-code a test keypair in the repo | Generate a per-run keypair inside the test, mode 0600 | Committing private keys is a security-engineer red line; per-run keygen + cleanup is tiny and safe |
| Bats assertion library | Hand-rolled `[[ -z $result ]] && ...` scattered across tests | Shared `tests/bats/helpers/assertions.bash` with TST-04 diagnostic format | Every scattered assertion is a TST-04 failure in waiting; a single helper enforces the diagnostic shape |
| Cron-vs-systemd-vs-SSH invocation | Copy-paste each invocation in every test | `tests/bats/helpers/invoke_modes.bash` with six helpers | CONTEXT decision; factored helpers let bats tests loop over modes cleanly |

**Key insight:** Phase 2 is 80% "use the standard primitive correctly" and 20% "write 200 lines of bash glue." The primitives (`useradd`, `install`, `grep -Fxq`, `visudo -cf`, `sudo -H -E`, `locale-gen`, `update-locale`, `EnvironmentFile=`, `PATH=` cron header) exist and are well-understood. The research budget is spent on discovering which mode breaks each one (see Common Pitfalls) — not on inventing new mechanics.

## Runtime State Inventory

> Phase 2 is greenfield (creates new state, does not rename/migrate). Included here because the provisioner writes into multiple locations; knowing each location is needed for INST-02 idempotency + Phase 4's `--purge` symmetry.

| Category | Items Written by Phase 2 | Action Required |
|----------|--------------------------|------------------|
| Stored data | None — Phase 2 creates no databases or state stores | None |
| Live service config | `/etc/cron.d/agentlinux` (PATH header only, no jobs); `/etc/agentlinux.env` (read by future systemd units); `/etc/profile.d/agentlinux.sh` | Phase 4's `--purge` removes all four |
| OS-registered state | Agent user (UID assigned by `useradd`; expect 1001 on Ubuntu cloud images where `ubuntu` already holds 1000); `~agent` home directory with default skeleton | Phase 4's `--purge` runs `userdel -r agent` |
| Secrets/env vars | None — Phase 2 provisions no secrets | None |
| Build artifacts | None — Phase 2 ships bash sources as-is (per HARNESS.md §1.4: "no build step" for installer). `plugin/cli/dist/` is Phase 3+ concern | None |

**Re-run idempotency contract (INST-02):** Running `agentlinux-install` twice on the same host MUST produce byte-identical filesystem state after the second run. Helpers `ensure_user`, `ensure_line_in_file`, `ensure_marker_block`, `ensure_dir` all enforce this; `install -m` overwriting entire files (profile.d, cron.d, env file) is trivially idempotent because the source content is fixed.

## Environment Availability

| Dependency | Required By | Available on Target | Version | Fallback |
|------------|------------|---------------------|---------|----------|
| `bash` ≥ 5.0 | All installer/lib/provisioner scripts | ✓ Ubuntu 22.04/24.04 | 5.1/5.2 | — |
| `useradd`, `usermod`, `id` | `10-agent-user.sh` | ✓ | — | — |
| `install` (coreutils) | Every provisioner that writes files | ✓ | — | — |
| `grep`, `awk`, `sed` | `idempotency.sh`, `distro_detect.sh` | ✓ | — | — |
| `locale-gen`, `update-locale` | `10-agent-user.sh` (or `20-locale.sh`) | ✓ (`locales` pkg) | — | If missing, `apt install -y locales` as first step |
| `visudo` | Future sudoers drop-in writer (Phase 2 ships no drop-in; validator must still exist) | ✓ (`sudo` pkg) | — | — |
| `/etc/os-release` | `distro_detect.sh` | ✓ | systemd-standard | — |
| `tee` | Installer entrypoint log redirect | ✓ (coreutils) | — | — |
| `bats-core` | `tests/bats/*.bats` execution inside Docker | ✓ inside Docker image (apt) | 1.8.2 on 22.04 / 1.10.0 on 24.04 | Three install paths already supported by Phase 1's `tests/harness/run.sh`: apt/brew/npm-local/vendored |
| `docker` | CI workflow + local `tests/docker/run.sh` | ✓ on GH Actions runners | 24.x+ | — |
| `systemd` + `systemd-sysv` | Docker image for BHV-04 | Install into image via apt | — | Mark test `@qemu-only` if consistently flaky |
| `cron` | Docker image for BHV-03 | Install into image via apt | — | Mark test `@qemu-only` if flaky |
| `openssh-server` | Docker image for BHV-02 | Install into image via apt | — | Mark test `@qemu-only` if flaky |

**Missing dependencies with no fallback:** None. Every dependency is either in Ubuntu's default image or installable via apt during Dockerfile build.

**Missing dependencies with fallback:** None required at runtime. Test-time dependencies (bats, systemd-in-docker) have documented fallbacks.

## Common Pitfalls

### Pitfall 1: Sudoers `secure_path` shadows `env_keep+=PATH`

**What goes wrong:** Adding `Defaults env_keep += "PATH"` to `/etc/sudoers.d/agentlinux` does NOT make `sudo -u agent <cmd>` see the caller's PATH. Ubuntu's `/etc/sudoers` already contains `Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"`. When `secure_path` is set, it REPLACES PATH for the target command — `env_keep` is ignored for PATH specifically.

**Why it happens:** `secure_path` is a hardening default; its whole purpose is to prevent PATH injection. Ubuntu ships it enabled; Debian does not.

**How to avoid:** Three strategies, pick one per invocation mode:

1. **For `sudo -u agent bash -c '<cmd>'`** (what `invoke_modes.bash::run_sudo_u` should use for BHV-05): bash runs `~/.bashrc` on non-login interactive-or-forced invocation. If `~/.bashrc` sources `/etc/profile.d/agentlinux.sh` (our Artefact 2), PATH is populated fresh AFTER sudo applies `secure_path`. This is the CONTEXT-locked strategy. Verified behavior: `.bashrc` is sourced when `$BASH_ENV` is set OR when the shell is interactive; `bash -c '<cmd>'` is non-interactive by default, so the `.bashrc` guard must NOT gate on `PS1` being set. Standard Ubuntu `.bashrc` top has `[ -z "$PS1" ] && return` — our appended block MUST precede that guard or use an explicit unconditional source.
2. **For `sudo -u agent -i <cmd>`** (BHV-05 login variant): login shells source `/etc/profile` which sources `/etc/profile.d/*.sh`. Our Artefact 1 wins; no special sudoers handling needed.
3. **If the agentlinux drop-in is ever needed (future phases):** extend `secure_path` in the drop-in: `Defaults:agent secure_path="/home/agent/.local/bin:/home/agent/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"`. Do NOT try to defeat `secure_path` with `env_keep`.

**Warning signs:** BHV-05 test (`sudo -u agent some-binary`) returns `command not found` even though BHV-06 (`su - agent -c 'some-binary'`) succeeds. Diagnosis: drop a `sudo -u agent /bin/bash -c 'echo PATH=$PATH'` inside the test; if PATH is the `secure_path` value with no agent home in it, this pitfall fired.

Source: [Baeldung: sudo env vars](https://www.baeldung.com/linux/sudo-manage-environment-variables), [sudoers(5)](https://manpages.ubuntu.com/manpages/noble/man5/sudoers.5.html)

### Pitfall 2: `.bashrc` early-return under non-interactive invocation

**What goes wrong:** The default Ubuntu `/home/agent/.bashrc` (copied from `/etc/skel/.bashrc`) starts with:

```bash
case $- in
    *i*) ;;
      *) return;;
esac
```

A `sudo -u agent bash -c 'echo $PATH'` is non-interactive, so the default skel early-returns and our appended agentlinux block never runs.

**Why it happens:** The skeleton `.bashrc` is optimized for interactive shells. Non-interactive bash invocations that don't carry `-i` skip it.

**How to avoid:** Either:

(a) Our `ensure_marker_block` inserts the agentlinux block **BEFORE** the `case $- ... return` guard (top of file), OR

(b) Our six-mode test helper `run_sudo_u` uses `sudo -u agent bash -i -c '<cmd>'` to force interactive mode (sources `.bashrc` fully), OR

(c) The helper passes `$BASH_ENV=/etc/profile.d/agentlinux.sh` through sudo's `env_keep+=BASH_ENV`, which bash honors even in non-interactive mode.

**Recommendation:** Pick (a) — insert the agentlinux block at the very top of `~agent/.bashrc`. `ensure_marker_block` positions content at file-end by default; add a mode parameter or a dedicated `ensure_marker_block_at_top` variant. Document the constraint in `plugin/provisioner/40-path-wiring.sh` comments.

**Warning signs:** Same as Pitfall 1 — PATH inside `sudo -u agent` is `secure_path`-only even though `~agent/.bashrc` contains our block.

Source: [Bash manual — Invocation](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)

### Pitfall 3: Docker container lacks systemd → BHV-04 silent false positives

**What goes wrong:** `ubuntu:24.04` Docker image has PID 1 = `bash` (or whatever CMD). `systemctl` exits with `System has not been booted with systemd as init system (PID 1). Can't operate.` A test that shells out `systemd-run --user=agent echo hi` fails with a misleading error, and worse, a test that guards with `if systemctl is-system-running; then ...` passes vacuously when `systemctl` is absent or errors.

**Why it happens:** Docker favors single-process containers. Systemd as PID 1 requires a specific runtime setup: `--privileged` OR (`--cap-add SYS_ADMIN` + cgroup mount), plus `CMD ["/sbin/init"]`, plus `/sys/fs/cgroup` mounted (or `--cgroupns=host`).

**How to avoid:** Dockerfile sets `CMD ["/sbin/init"]` and `tests/docker/run.sh` invokes with:

```bash
docker run \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  --tmpfs /run \
  --tmpfs /tmp \
  -v "$PWD":/workspace \
  -w /workspace \
  agentlinux-test:"$version" \
  bash -c 'bash plugin/bin/agentlinux-install && bats tests/bats/'
```

Plus the `run_systemd_user` helper must explicitly fail (not skip silently) when `systemctl is-system-running --wait` returns `offline`. If a mode proves unreliable in Docker, tag the specific test `@qemu-only` (bats supports tag filtering via the `--filter-tags` flag since v1.8) and let Phase 6's QEMU harness cover it.

**Warning signs:** BHV-04 test passes in Docker but fails in QEMU (or vice versa); `systemctl status` inside the container says "no daemon"; `ls /run/systemd/system/` is empty.

Sources: [Docker Docs: Linux post-install](https://docs.docker.com/engine/install/linux-postinstall/), [codegenes.net: systemd in Docker](https://www.codegenes.net/blog/how-can-systemd-and-systemctl-be-enabled-and-used-in-ubuntu-docker-containers/), [jrei/systemd-ubuntu](https://hub.docker.com/r/jrei/systemd-ubuntu)

### Pitfall 4: Cron does not expand `$PATH` — literal strings only

**What goes wrong:** Writing `PATH=$PATH:/home/agent/.local/bin` in `/etc/cron.d/agentlinux` stores the literal text `$PATH:/home/agent/.local/bin` in PATH. Some cron implementations (systemd-cron on newer distros) do expand; classical vixie-cron on Ubuntu does NOT.

**Why it happens:** cron's own env-variable parser is strict KEY=VALUE; it is not a shell.

**How to avoid:** Write a fully-expanded, literal PATH in `/etc/cron.d/agentlinux` (and `/etc/agentlinux.env` — systemd's `EnvironmentFile` has the same behavior). Never reference other variables. This is also why `/etc/agentlinux.env` must not contain `PATH=$PATH:...`.

**Warning signs:** BHV-03 test finds a binary via `command -v` inside the cron job but the binary lookup fails; stderr from the cron job shows literal `$PATH` string in error paths.

Source: [Baeldung: cron PATH](https://www.baeldung.com/linux/cron-jobs-path), [cronitor: cron env vars](https://cronitor.io/guides/cron-environment-variables), [systemd.exec(5) §EnvironmentFile](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#EnvironmentFile=)

### Pitfall 5: `locale-gen` no-op on `C.UTF-8`

**What goes wrong:** `locale-gen C.UTF-8` may exit 0 without creating anything because `C.UTF-8` is a **built-in locale** in glibc 2.35+ (Ubuntu 22.04 and later) and is not registered via `/etc/locale.gen` like `en_US.UTF-8` is. A test that asserts "after `locale-gen`, `C.UTF-8` is in `locale -a`" can still pass — but only because glibc ships it built-in, not because `locale-gen` did anything.

**Why it happens:** glibc upstream decided `C.UTF-8` should always work, no generation required. Distros then remove it from `/etc/locale.gen` (Ubuntu 22.04+ does this). `locale-gen C.UTF-8` becomes a no-op in the normal code path.

**How to avoid:** The installer should:

1. `apt install -y locales` (ensures `locale-gen` / `update-locale` exist).
2. `update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8` (writes `/etc/default/locale`).
3. Verify outcome: `locale -a | grep -iq '^c\.utf-\?8$' || log_error "C.UTF-8 not available"`.
4. Do NOT add `C.UTF-8 UTF-8` to `/etc/locale.gen` — the built-in handles it.

On Ubuntu 24.04 cloud images verified on this host: `locale -a` includes `C.utf8`, `POSIX`, `en_US.utf8`; `/etc/default/locale` is pre-seeded `LANG=C.UTF-8`. The installer's locale step is therefore a verify-and-seed operation on a stock cloud image.

**Warning signs:** BHV-01 asserts `LANG=C.UTF-8` and passes interactively, but a cron or systemd job running under `LC_ALL=""` fails with `setlocale: LC_ALL: cannot change locale`.

Source: [help.ubuntu.com/community/Locale](https://help.ubuntu.com/community/Locale), [verified on this Ubuntu 24.04 host: /etc/default/locale = LANG=C.UTF-8]

### Pitfall 6: `exec > >(tee ...)` FD and SIGPIPE behavior

**What goes wrong:** `exec > >(tee -a "$LOG") 2>&1` creates a subshell running `tee`. If the parent's stdout closes abnormally (panic, `kill -9`), the tee subshell may survive briefly and pick up trailing bytes, or — more commonly — the installer's final `exit` runs BEFORE tee's `fsync`, truncating the last log line. INST-05's grep `EACCES|permission denied` against a truncated log can produce false negatives ("no EACCES" because the EACCES line never made it to disk).

**Why it happens:** Process-substitution `>()` spawns an async child; bash doesn't wait for it by default on exit.

**How to avoid:** Two mitigations stacked:

1. Add `trap 'wait' EXIT` to the entrypoint — waits for the tee child before exit.
2. Use `exec 1> >(tee -a "$LOG") 2>&1` + `sync` immediately before `exit` in `on_error`.

Alternative: use `script` (from `bsdextrautils` / `util-linux`) which handles flushing more cleanly — overkill for Phase 2.

**Warning signs:** INST-05 test intermittently passes / fails on the same code; grepping the log file size right before and after installer exit shows bytes still arriving after `agentlinux-install` returned.

Source: [Bash manual — Process Substitution](https://www.gnu.org/software/bash/manual/html_node/Process-Substitution.html), operational experience

### Pitfall 7: Bats `run` swallows stderr unless `run 2>&1` or `BATS_RUN_COMMAND_KEEP_STDERR`

**What goes wrong:** `run some-command` captures stdout into `$output`; stderr goes to the terminal but NOT into `$output` (bats < 1.5 discarded it entirely; 1.5+ preserved it separately in `$stderr`). A test asserting `! echo "$output" | grep -E 'EACCES|permission denied'` checks only stdout — and `EACCES` typically comes on stderr. The test passes despite the bug.

**Why it happens:** Bats designed `run` for exit-code + stdout assertions; stderr capture required opt-in.

**How to avoid:** Two options:

1. `run --separate-stderr some-command`, then assert against `$output` AND `$stderr` (bats 1.5+; Ubuntu 22.04 ships 1.8.2, 24.04 ships 1.10 — both support this).
2. Wrap: `run bash -c 'some-command 2>&1'` — merges streams before capture. Simpler.

For `assert_no_eacces`, strategy 2 is cleaner and works identically across bats versions. The installer log file (`/var/log/agentlinux-install.log`) is the authoritative INST-05 grep target anyway — it already merges stdout+stderr via the `exec > >(tee) 2>&1` pattern.

**Warning signs:** `assert_no_eacces` consistently passes on hand-crafted broken installer runs; manual `bash -c '... 2>&1' | grep EACCES` finds matches.

Source: [bats-core docs — run helper](https://bats-core.readthedocs.io/en/stable/writing-tests.html#run)

## Code Examples

### Example 1: Installer entrypoint (complete skeleton)

```bash
#!/usr/bin/env bash
# plugin/bin/agentlinux-install — AgentLinux installer entrypoint
# Source: HARNESS.md §1.1, skill agentlinux-installer, this phase's RESEARCH.md
set -euo pipefail

readonly AGENTLINUX_VERSION="0.3.0"
readonly LOG_FILE="${AGENTLINUX_LOG:-/var/log/agentlinux-install.log}"
readonly BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="$(cd "$BIN_DIR/../lib" && pwd)"
readonly PROV_DIR="$(cd "$BIN_DIR/../provisioner" && pwd)"

install -m 0644 /dev/null "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'wait' EXIT

# shellcheck source=../lib/log.sh
. "$LIB_DIR/log.sh"

on_error() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]:-unknown}
  local src=${BASH_SOURCE[1]:-unknown}
  log_error "installer failed at ${src}:${line_no} (exit ${exit_code})"
  log_error "full transcript: ${LOG_FILE}"
  exit "$exit_code"
}
trap on_error ERR

usage() {
  cat <<EOF
agentlinux-install — provision an agent user and environment
Usage: agentlinux-install [--help|-h] [--version|-V] [--verbose] [--purge]
  --verbose   enable DEBUG logging
  --purge     (Phase 4 stub) uninstall the agent user + placed files
EOF
}

# shellcheck source=../lib/distro_detect.sh
. "$LIB_DIR/distro_detect.sh"
# shellcheck source=../lib/idempotency.sh
. "$LIB_DIR/idempotency.sh"
# shellcheck source=../lib/as_user.sh
. "$LIB_DIR/as_user.sh"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -V|--version) printf '%s\n' "$AGENTLINUX_VERSION"; exit 0 ;;
      --verbose) export AGENTLINUX_LOG_LEVEL=DEBUG ;;
      --purge)
        log_warn "--purge is a Phase 4 stub; no action taken in v0.3.0 Phase 2"
        exit 0 ;;
      *) log_error "unknown argument: $1"; usage >&2; exit 64 ;;
    esac
    shift
  done
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log_error "agentlinux-install must run as root (EUID != 0). Re-run under sudo."
    exit 64
  fi
}

main() {
  parse_args "$@"
  require_root
  log_info "agentlinux-install v${AGENTLINUX_VERSION} starting"
  detect_distro
  shopt -s nullglob
  local steps=("$PROV_DIR"/[0-9][0-9]-*.sh)
  shopt -u nullglob
  if [[ ${#steps[@]} -eq 0 ]]; then
    log_error "no provisioner scripts found under $PROV_DIR"
    exit 1
  fi
  for step in "${steps[@]}"; do
    log_info "running $(basename "$step")"
    # shellcheck disable=SC1090
    . "$step"
  done
  log_info "agentlinux-install complete (transcript: $LOG_FILE)"
}
main "$@"
```

### Example 2: `tests/bats/helpers/invoke_modes.bash`

```bash
# tests/bats/helpers/invoke_modes.bash
# Six-mode invocation matrix for BHV-02..06.
# Each helper sets $status / $output / $stderr like bats `run` does, so tests
# can loop: `for mode in interactive ssh cron systemd_user sudo_u sudo_u_i; do ...`
# Source: docs/HARNESS.md §1.1 skills, RESEARCH.md Pitfall 1-3.

readonly INVOKE_MODES=(interactive ssh cron systemd_user sudo_u sudo_u_i)

# BHV-06: interactive login via `su - agent -c`.
run_interactive() {
  local cmd="$*"
  run bash -c "su - agent -c 'set -o pipefail; ${cmd} 2>&1'"
}

# BHV-02: non-interactive SSH from root → agent@localhost.
# Assumes Dockerfile installed openssh-server and copied a root-generated
# keypair into /home/agent/.ssh/authorized_keys + /root/.ssh/id_ed25519.
run_ssh() {
  local cmd="$*"
  run bash -c "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                   -i /root/.ssh/id_ed25519 agent@localhost '${cmd} 2>&1'"
}

# BHV-03: command via cron. Writes a one-shot cron.d entry, triggers cron,
# waits for job output, cleans up.
run_cron() {
  local cmd="$*"
  local stamp
  stamp=$(date +%s%N)
  local out="/tmp/agentlinux-cron-${stamp}.out"
  cat <<CRONJOB >"/etc/cron.d/agentlinux-test-${stamp}"
PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin
* * * * * agent ${cmd} >${out} 2>&1; rm -- /etc/cron.d/agentlinux-test-${stamp}
CRONJOB
  chmod 0644 "/etc/cron.d/agentlinux-test-${stamp}"
  # Poll up to 70s for the job to fire.
  for _ in $(seq 1 70); do
    if [[ -s "$out" ]]; then break; fi
    sleep 1
  done
  run cat "$out"
  rm -f "$out"
}

# BHV-04: command under systemd User=agent. Requires CMD=/sbin/init in Dockerfile.
run_systemd_user() {
  local cmd="$*"
  if ! systemctl is-system-running --wait >/dev/null 2>&1; then
    run bash -c "echo 'SKIP_SYSTEMD_UNAVAILABLE'; exit 75"
    return
  fi
  run systemd-run --wait --pipe --uid=agent --setenv=HOME=/home/agent \
                  --property=EnvironmentFile=/etc/agentlinux.env \
                  /bin/bash -c "${cmd} 2>&1"
}

# BHV-05 (non-login): sudo -u agent. Uses `bash -i -c` to force interactive mode
# so /home/agent/.bashrc sources /etc/profile.d/agentlinux.sh (see Pitfall 2).
# Alternative: skip -i and rely on the agentlinux block being placed BEFORE
# the `case $- in *i*) ;; *) return;;` guard in ~agent/.bashrc.
run_sudo_u() {
  local cmd="$*"
  run sudo -u agent -H bash -c "${cmd} 2>&1"
}

# BHV-05 (login): sudo -u agent -i.
run_sudo_u_i() {
  local cmd="$*"
  run sudo -u agent -H -i bash -c "${cmd} 2>&1"
}

# Generic dispatch.
invoke_mode() {
  local mode=$1
  shift
  "run_${mode}" "$@"
}
```

### Example 3: `tests/bats/helpers/assertions.bash`

```bash
# tests/bats/helpers/assertions.bash
# TST-04 diagnostic contract: every failure prints requirement ID, expected,
# observed, and log path.

# Print a TAP-friendly diagnostic line (visible even on passing tests) via FD 3.
__diag() {
  printf '# %s\n' "$*" >&3
}

# Hard-fail the current test with a formatted diagnostic.
__fail() {
  local req_id=$1 expected=$2 observed=$3 log_hint=$4
  {
    printf '# FAIL: %s\n' "$req_id"
    printf '#   expected: %s\n' "$expected"
    printf '#   observed: %s\n' "$observed"
    printf '#   log:      %s\n' "$log_hint"
  } >&2
  return 1
}

# INST-05 gate: input is stdout+stderr merged, or a log file path.
# assert_no_eacces "<req-id>" "<text-or-filepath>"
assert_no_eacces() {
  local req_id=$1
  local src=$2
  local content
  if [[ -f $src ]]; then
    content=$(cat -- "$src")
  else
    content=$src
  fi
  if printf '%s' "$content" | grep -Eq 'EACCES|permission denied'; then
    local hits
    hits=$(printf '%s' "$content" | grep -E 'EACCES|permission denied' | head -5)
    __fail "$req_id" \
      "no 'EACCES' or 'permission denied' in output" \
      "found: $(printf '%s' "$hits" | tr '\n' '|')" \
      "${src}"
    return 1
  fi
}

# BHV-02..06 helper: after invoke_mode ran, assert PATH includes <bin>.
# Expects caller to have just run an invoke helper (status/output populated).
assert_path_has() {
  local req_id=$1 bin=$2
  if ! printf '%s' "${output:-}" | grep -Eq "(^|:)[^:]*${bin}([:[:space:]]|$)"; then
    __fail "$req_id" \
      "PATH contains ${bin}" \
      "PATH=${output:-<empty>}" \
      "/var/log/agentlinux-install.log"
  fi
}

assert_exit_zero() {
  local req_id=$1
  if [[ ${status:-1} -ne 0 ]]; then
    __fail "$req_id" \
      "exit status 0" \
      "exit status ${status:-unset}; output: ${output:-<empty>}" \
      "/var/log/agentlinux-install.log"
  fi
}
```

### Example 4: `tests/docker/Dockerfile.ubuntu-24.04`

```dockerfile
# tests/docker/Dockerfile.ubuntu-24.04
# Systemd-capable Ubuntu 24.04 base for running the full BHV matrix in CI.
# Source: docs.docker.com, ADR-007, jrei/systemd-ubuntu, this phase's RESEARCH.md §Pitfall 3.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Core: systemd + cron + openssh + bats + sudo + locales + coreutils
# --no-install-recommends keeps the image small and minimizes attack surface.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      systemd systemd-sysv \
      cron openssh-server \
      bats locales sudo \
      ca-certificates bash coreutils util-linux \
      shellcheck && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Systemd inside Docker: disable units that fight with containerized PID 1.
RUN rm -f /lib/systemd/system/multi-user.target.wants/*; \
    systemctl mask systemd-logind.service systemd-resolved.service \
                   systemd-networkd.service systemd-tmpfiles-setup.service \
                   systemd-tmpfiles-clean.service systemd-tmpfiles-clean.timer

# SSH: generate host keys; allow pubkey auth; don't run as a daemon at init,
# the systemd unit picks it up after /sbin/init boots.
RUN mkdir -p /run/sshd && ssh-keygen -A

# Locale for BHV-01 — C.UTF-8 is glibc built-in; this is idempotent seed.
RUN locale-gen C.UTF-8 || true && update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8

VOLUME /sys/fs/cgroup
STOPSIGNAL SIGRTMIN+3

# /sbin/init is systemd; Pitfall 3 mitigation.
CMD ["/sbin/init"]
```

### Example 5: `tests/docker/run.sh`

```bash
#!/usr/bin/env bash
# tests/docker/run.sh — build + run the Docker bats harness for one Ubuntu version.
# Invoked by .github/workflows/test.yml and developers locally.
set -euo pipefail

UBUNTU_VERSION=${1:-}
if [[ -z $UBUNTU_VERSION ]]; then
  echo "usage: $0 <ubuntu-22.04|ubuntu-24.04>" >&2
  exit 64
fi
case "$UBUNTU_VERSION" in
  ubuntu-22.04|ubuntu-24.04) ;;
  *) echo "unsupported ubuntu version: $UBUNTU_VERSION" >&2; exit 64 ;;
esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
IMG="agentlinux-test:${UBUNTU_VERSION}"
DF="$HERE/Dockerfile.${UBUNTU_VERSION}"

echo "== build ${IMG} from ${DF} =="
docker build -t "$IMG" -f "$DF" "$REPO_ROOT/tests/docker"

echo "== run installer + bats suite inside ${IMG} =="
# --privileged + cgroup bind: required for BHV-04 (systemd User=agent).
# Background the container (-d), wait for systemd to settle, then `docker exec`
# the installer + bats suite. Avoids the "can't exec before systemd is up" race.
CID=$(docker run --rm -d \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  --tmpfs /run --tmpfs /tmp \
  -v "$REPO_ROOT":/workspace:ro \
  -w /workspace \
  "$IMG")

cleanup() { docker rm -f "$CID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Wait for systemd readiness (BHV-04 precondition).
for _ in $(seq 1 30); do
  if docker exec "$CID" systemctl is-system-running --wait >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Copy sources (image mounted read-only; installer writes to /etc etc. inside).
docker exec "$CID" bash -c 'cp -r /workspace /opt/agentlinux-src && cd /opt/agentlinux-src'
docker exec "$CID" bash /opt/agentlinux-src/plugin/bin/agentlinux-install
docker exec "$CID" bash -c 'cd /opt/agentlinux-src && bats tests/bats/'
```

### Example 6: Example BHV-02 test (pattern for the other five modes)

```bash
#!/usr/bin/env bats
# tests/bats/20-agent-user.bats — BHV-01..BHV-06.

load 'helpers/invoke_modes'
load 'helpers/assertions'

@test "BHV-01: agent user exists with bash shell and home directory" {
  run getent passwd agent
  assert_exit_zero "BHV-01"
  # Shell must be /bin/bash; home must be /home/agent.
  [[ "$output" =~ :/home/agent:/bin/bash$ ]] || {
    __fail "BHV-01" \
      "passwd entry ends :/home/agent:/bin/bash" \
      "$output" \
      "/var/log/agentlinux-install.log"
  }
}

@test "BHV-01: agent sees C.UTF-8 locale (interactive)" {
  run_interactive 'printf "%s\n" "$LANG" "$LC_ALL"'
  assert_exit_zero "BHV-01"
  [[ "$output" == *"C.UTF-8"* ]] || {
    __fail "BHV-01" "LANG=C.UTF-8 in interactive login" "$output" \
      "/var/log/agentlinux-install.log"
  }
}

@test "BHV-02: agent runs command over non-interactive SSH with PATH" {
  run_ssh 'echo "$PATH"'
  assert_exit_zero "BHV-02"
  # /home/agent/.local/bin must be on PATH even in non-login SSH.
  [[ "$output" == *"/home/agent/.local/bin"* ]] || {
    __fail "BHV-02" "PATH contains /home/agent/.local/bin" "$output" \
      "/var/log/agentlinux-install.log"
  }
}

@test "BHV-02: non-interactive SSH sees UTF-8 locale" {
  run_ssh 'printf "%s\n" "$LANG"'
  assert_exit_zero "BHV-02"
  [[ "$output" == *"C.UTF-8"* ]]
}

# ... BHV-03 (cron), BHV-04 (systemd), BHV-05 (sudo -u, sudo -u -i), BHV-06 (interactive)
# follow the same shape — each asserts (a) exit zero, (b) PATH contains the
# agent's .local/bin, (c) LANG is C.UTF-8, (d) log contains no EACCES.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `/etc/locale.gen` + `locale-gen en_US.UTF-8` | glibc built-in `C.UTF-8` (no generation needed) | glibc 2.35 (Ubuntu 22.04+) | Installer can use C.UTF-8 unconditionally; no uncommenting `/etc/locale.gen` lines |
| `bash` script of arbitrary structure | `set -euo pipefail` + ERR trap everywhere | SIPB / arslan.io circa 2019; now universal | Any Phase 2 bash without strict mode fails `bash-engineer` review immediately |
| Per-tool shell-hook version managers (nvm, fnm) | System Node.js from NodeSource (ADR-005) | AgentLinux-specific decision 2026-04-18 | No invocation-mode-dependent PATH bugs (shell hooks don't fire in cron/systemd) |
| Global sudo for npm (the bug AgentLinux fixes) | Per-user npm prefix (ADR-004) — Phase 3 concern | 2026-04-18 (v0.3.0 pivot) | No `/usr/local/lib/node_modules` EACCES; no wrapper shims needed |
| Docker as the only test harness | Docker (fast PR) + QEMU (release gate) (ADR-007) | 2026-04-18 | systemd/locale/cloud-init bugs caught before release; ~40% more real-world signal |
| Rigid implementation requirements ("installer SHALL use apt") | Behavior-contract requirements (ADR-002) | 2026-04-18 | Implementation free to change; tests are the spec |
| `.ssh/environment` for SSH PATH | `~/.bashrc` sourcing `/etc/profile.d/agentlinux.sh` | AgentLinux-specific, 2026-04-18 | No need for `PermitUserEnvironment yes` (default-off, invasive) |

**Deprecated/outdated:**
- `lsb_release -a` for distro detection → superseded by `/etc/os-release`. `[CITED: systemd upstream — os-release(5)]`
- Hand-rolled `append_if_missing` in each script → superseded by centralized `ensure_line_in_file` in `plugin/lib/idempotency.sh`.
- vixie-cron assumptions ("cron expands $PATH") → never true; systemd-cron on newer distros does, but cronie/vixie do not. Always write literal PATH.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core 1.10.0+ (Ubuntu 24.04 apt); 1.8.2 on 22.04 apt — both adequate |
| Config file | none (bats has no global config); `setup_suite.bash` per directory if cross-test state needed |
| Quick run command | `bats tests/bats/10-installer.bats` (single file, fastest feedback) |
| Full suite command | `bash tests/docker/run.sh ubuntu-24.04` (build + installer + full bats) |
| Per-commit harness (Phase 1 meta) | `bash tests/harness/run.sh` — must remain GREEN after Phase 2 lands (do not regress) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INST-01 | Clean-run installer exits 0 on clean Ubuntu | integration | `bats tests/bats/10-installer.bats -f INST-01` | ❌ Wave 0 |
| INST-02 | Idempotent re-run converges | integration | `bats tests/bats/10-installer.bats -f INST-02` | ❌ Wave 0 |
| INST-05 | Zero EACCES/permission denied across stdout+stderr+log | integration | `bats tests/bats/10-installer.bats -f INST-05` | ❌ Wave 0 |
| BHV-01 | agent user, bash shell, UTF-8 locale | integration | `bats tests/bats/20-agent-user.bats -f BHV-01` | ❌ Wave 0 |
| BHV-02 | non-interactive SSH PATH/locale | integration | `bats tests/bats/20-agent-user.bats -f BHV-02` | ❌ Wave 0 |
| BHV-03 | cron PATH/locale | integration | `bats tests/bats/20-agent-user.bats -f BHV-03` | ❌ Wave 0 |
| BHV-04 | systemd User=agent PATH/locale | integration (privileged Docker) | `bats tests/bats/20-agent-user.bats -f BHV-04` | ❌ Wave 0 |
| BHV-05 | sudo -u agent + sudo -u agent -i PATH/locale | integration | `bats tests/bats/20-agent-user.bats -f BHV-05` | ❌ Wave 0 |
| BHV-06 | interactive bash login PATH/locale | integration | `bats tests/bats/20-agent-user.bats -f BHV-06` | ❌ Wave 0 |
| DOC-02 | `/home/agent/CLAUDE.md` exists, ≥ some required content | integration | `bats tests/bats/10-installer.bats -f DOC-02` | ❌ Wave 0 |
| TST-01 | Every BHV/INST requirement has ≥ 1 bats test | meta | behavior-coverage-auditor subagent run at phase close | scaffolded in Phase 1 |
| TST-02 | Docker harness runs on 22.04 + 24.04 every PR | CI | `.github/workflows/test.yml` `bats-docker` matrix job | scaffolded in Phase 1; Phase 2 populates sources so guard falls through |
| TST-04 | Failures print req ID + expected + observed + log path | structural | `bash tests/bats/helpers/assertions.bash` sanity run | ❌ Wave 0 |

### Measurement Points (Nyquist)

The measurable signals every Phase 2 plan must hit. These are the instrumentation points Phase 2 writes and the tests read.

1. **Installer exit code.** `agentlinux-install; echo $?` — 0 on clean run, non-zero on any failure. Captured by `assert_exit_zero`. (INST-01)
2. **Installer log no-EACCES.** `grep -E 'EACCES|permission denied' /var/log/agentlinux-install.log` — must be empty. Captured by `assert_no_eacces`. (INST-05)
3. **Installer idempotency diff.** Snapshot `/etc`, `/home/agent` after first run; re-run installer; snapshot again; `diff -r` the two must be empty (or a documented-noise set like log file growth). (INST-02)
4. **Agent-user attributes.** `getent passwd agent` returns a line ending `:/home/agent:/bin/bash`. `[[ -d /home/agent ]] && stat -c '%U' /home/agent == agent`. (BHV-01)
5. **PATH capture per invocation mode.** For each of six modes, `invoke_mode <m> 'echo $PATH'` captures PATH string; `assert_path_has` grep-asserts `/home/agent/.local/bin` is present. (BHV-02..06)
6. **Locale capture per invocation mode.** Same shape: `invoke_mode <m> 'printf %s $LANG'` → assert `C.UTF-8`. (BHV-01 per mode)
7. **DOC-02 file.** `[[ -f /home/agent/CLAUDE.md ]] && [[ $(stat -c %U /home/agent/CLAUDE.md) == agent ]]`; grep for forbidden-anti-pattern mention (e.g., the file MUST contain the word "shim" or "/usr/local/bin" in an explicit don't-do-this context). (DOC-02)

### Sampling Rate

- **Per task commit:** `bats tests/bats/10-installer.bats` (the single file most likely to regress after a `plugin/lib/*.sh` change; ~3 sec locally outside Docker for non-BHV-04 tests).
- **Per wave merge:** `bash tests/docker/run.sh ubuntu-24.04` (full matrix against 24.04; ~90 sec on laptop with cached image).
- **Phase gate:** `bash tests/docker/run.sh ubuntu-22.04 && bash tests/docker/run.sh ubuntu-24.04 && bash tests/harness/run.sh` all GREEN. Then `gsd-verify-work` can run.

### Wave 0 Gaps

Tests & infra that must exist before any implementation task can be verified:

- [ ] `tests/bats/10-installer.bats` — covers INST-01, INST-02, INST-05, DOC-02
- [ ] `tests/bats/20-agent-user.bats` — covers BHV-01..BHV-06
- [ ] `tests/bats/helpers/invoke_modes.bash` — six-mode dispatch
- [ ] `tests/bats/helpers/assertions.bash` — shared TST-04-compliant helpers
- [ ] `tests/docker/Dockerfile.ubuntu-22.04`
- [ ] `tests/docker/Dockerfile.ubuntu-24.04`
- [ ] `tests/docker/run.sh` — build + installer + bats orchestration
- [ ] Framework install: none (bats installed inside Docker via apt; harness suite uses Phase 1's existing `tests/harness/run.sh` for meta-tests)
- [ ] Decision: whether to adopt `bats-support` + `bats-assert` in Phase 2 or defer. Recommend DEFER — hand-rolled helpers fit Phase 2 surface; revisit Phase 3 when RT tests add complexity.

## Security Domain

Security enforcement is enabled (no `security_enforcement: false` in config). ASVS categories relevant to Phase 2's bash-installer + Ubuntu-provisioning surface:

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 2 does not wire auth — SSH uses OS-level authorized_keys only in tests |
| V3 Session Management | no | No web/API sessions in Phase 2 |
| V4 Access Control | **yes** | `useradd --user-group agent` (non-privileged); sudoers drop-in contract (mode 0440, validated by `visudo -cf`); no wildcard sudo; no `/usr/local/bin` shims |
| V5 Input Validation | yes | Installer arg parsing — whitelist `--help/--version/--verbose/--purge`; reject unknown flags with exit 64 |
| V6 Cryptography | no (for Phase 2) | SHA-256 verification is Phase 6 concern (curl-pipe-bash installer + release tarball) |
| V7 Error Handling & Logging | **yes** | All errors land in `/var/log/agentlinux-install.log` with ISO-8601 timestamps; no secrets in logs (Phase 2 has no secrets); trap ERR prints failing step |
| V8 Data Protection | no | Phase 2 writes no user data |
| V12 Files & Resources | **yes** | File modes: profile.d 0644; cron.d 0644; agentlinux.env 0644; sudoers drop-in 0440 (future); log file 0644 created via `install -m 0644`; `/home/agent` 0755 owned by agent |
| V14 Configuration | **yes** | Every configuration artefact is generated by the installer from a known template; no remote fetches; no curl-pipe-bash inside provisioners |

### Known Threat Patterns for bash + Ubuntu provisioning

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Command injection via unquoted expansion | Tampering | Always quote (`"$var"`), use arrays for command + args, shellcheck `--severity=warning` catches most |
| Sudoers file corruption locking out root | DoS | `visudo -cf <file>` before `install -m 0440`; atomic move |
| Blind append to system files → duplicate lines, unbounded growth | Tampering | `ensure_line_in_file` grep-before-append; `ensure_marker_block` for multi-line |
| Symlink attack on log file (e.g., `/var/log/agentlinux-install.log` → `/etc/shadow`) | Elevation | `install -m 0644 /dev/null "$LOG_FILE"` before tee; `install` refuses if dst is a symlink without `-T` (actually, `install` follows symlinks — use `rm -f "$LOG_FILE"` then `touch`, or open with `O_NOFOLLOW` via `python -c` in paranoid cases). For Phase 2, a root installer on a clean Ubuntu is low-risk; document the attack in a comment |
| Environment variable injection via `sudo` without `env_reset` | Tampering | Ubuntu's `/etc/sudoers` has `Defaults env_reset` on by default (verified on this host); installer MUST NOT add `Defaults env_reset -` anywhere |
| Wrapper-shim under `/usr/local/bin` pointing to agent-owned binary (DOC-02 anti-pattern) | Tampering (breaks self-update) | DOC-02 CLAUDE.md explicitly forbids; `catalog-auditor` + `security-engineer` subagents grep for `/usr/local/bin/` in Phase 4+ |
| TOCTOU between `[[ -f $file ]]` and `install` | Race | `install -m 0644` is atomic for the write; no pre-check needed. For `ensure_user`, useradd is atomic at the passwd DB level |
| `source` of untrusted file in ERR trap | Elevation | All `source`d files are under `$LIB_DIR` / `$PROV_DIR` (installer-owned); never source from user input |

### Phase 2 Security Sign-off Checklist

- [ ] No `sudo npm install -g` anywhere (Phase 2 has no npm, but the rule is pre-enforced via `as_user` keystone — `catalog-auditor` will grep for it every phase)
- [ ] No `/usr/local/bin/` writes (Phase 2 writes zero to that path; Phase 4's CLI will land the CLI there but as a real binary, not a shim)
- [ ] No sudoers drop-in with mode ≠ 0440 (Phase 2 ships zero drop-ins; the helper exists for Phase 3+)
- [ ] Every `.sh` starts with `#!/usr/bin/env bash` and `set -euo pipefail`
- [ ] Every expansion of user-input is quoted
- [ ] Every new file written has an explicit `install -m <mode>` (no default-umask reliance)
- [ ] `visudo -cf` wrapper exists in `idempotency.sh` even though no drop-in uses it in Phase 2 (so Phase 3+ can't forget it)
- [ ] `/var/log/agentlinux-install.log` is root-owned, 0644, created via `install -m 0644 /dev/null <path>` before tee redirects into it

## Project Constraints (from CLAUDE.md)

CLAUDE.md directives that Phase 2 plans MUST honor:

| Directive | Source | Enforcement |
|-----------|--------|-------------|
| Never `sudo npm install -g` anywhere | CLAUDE.md §Critical Rules | `as_user` keystone in `plugin/lib/as_user.sh`; Phase 2 has no npm but the helper ships now |
| Behavior tests in `tests/bats/` are the spec — implementation may change freely | CLAUDE.md §Critical Rules, ADR-002 | Research is prescriptive about behaviors, not specific file/function shapes (left to Claude's Discretion per CONTEXT) |
| No agent installed by default | CLAUDE.md §Critical Rules, ADR-003, CAT-02 | Phase 2 ships no catalog content; CLI lands in Phase 4; trivially compliant |
| Docker-only test runs insufficient — QEMU green before release | CLAUDE.md, ADR-007 | Phase 2 ships Docker only; QEMU is Phase 6. Phase 2's CONTEXT allows `@qemu-only` tagging |
| Every release tarball ships with sibling `.sha256` | CLAUDE.md | Phase 6 concern; Phase 2 does not ship a tarball |
| No wrapper shims at `/usr/local/bin/` pointing to agent-owned binaries | CLAUDE.md, DOC-02 | Phase 2 writes nothing to `/usr/local/bin/`; DOC-02 CLAUDE.md placed at `/home/agent/CLAUDE.md` warns agent tools against doing it |
| Review loop on all changed files before task complete | CLAUDE.md §Review Loop, ADR-010 | Each plan's acceptance criteria must include a review-loop invocation; reviewer dispatch is in `.claude/skills/review/SKILL.md` |
| Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign` | STATE.md (Plan 01-01..01-05 pattern) | Phase 2 plans continue this pattern; not `gsd-tools commit` |
| shellcheck `--severity=warning --shell=bash --external-sources` | HARNESS.md §1.2, `.pre-commit-config.yaml` | All new bash must pass; `# shellcheck source=...` hints on every `.` / `source` |
| shfmt `-i 2 -ci -bn` | HARNESS.md §1.2 | All new bash formatted accordingly |
| Plugin bash is shell-only (no build step) | HARNESS.md §1.4 | Phase 2 ships bash sources directly; no dist/ |

## DOC-02 Content Guide

`/home/agent/CLAUDE.md` placed by `plugin/provisioner/10-agent-user.sh` (chown `agent:agent`, mode 0644). Purpose: agent tools that source a project-local CLAUDE.md discover it and do NOT inflict the shim anti-pattern.

**Required content (minimum; exact wording is Claude's Discretion):**

1. **Identity note:** "This agent user was provisioned by AgentLinux v0.3.0. The environment is intentionally correctly-owned: Node.js runtime, npm prefix, and config paths are writable by this user. You do NOT need sudo for routine agent operations."
2. **Explicit anti-pattern list — "DO NOT do any of these":**
   - Create a wrapper script at `/usr/local/bin/<tool>` that `exec`s the agent-owned tool. Claude Code's self-update re-writes its own binary; a shim at `/usr/local/bin/` breaks that and was the canonical v0.1/v0.2 bug that motivated the entire AgentLinux project.
   - Run `sudo npm install -g` to work around a permission error. If you hit EACCES from `npm install -g`, the environment is broken — file a bug, don't paper over it.
   - Install a second Node.js (via nvm, fnm, volta, or a manual download) to sidestep permission issues. The system Node.js is correctly-owned; a second install creates a PATH race that breaks cron and systemd.
   - Re-exec yourself under sudo (`sudo $0 "$@"`) to "fix" a permission error. If you need a privilege, you don't have it — stop and report.
   - Write into `/usr/local/lib/node_modules`, `/opt`, `/etc/agentlinux.env` (read by systemd, you should not modify), `/etc/profile.d/*.sh`, `/etc/sudoers.d/*`.
3. **Where YOU (the agent tool) SHOULD write:** `$HOME/.npm-global/` (npm globals, arrives Phase 3), `$HOME/.local/bin` (scripts), `$HOME/.config/<tool>/` (config), `$HOME/.cache/<tool>/` (cache).
4. **Signal when you hit a permission error:** exit non-zero, log the error, let the human / AgentLinux maintainer diagnose. Do not "recover" by climbing the privilege ladder.

**Format:** markdown, under ~80 lines, readable by humans and agents equally. Could structure as:

```markdown
# /home/agent/CLAUDE.md

## This environment is correctly owned
...

## DO NOT (anti-patterns)
- No shim under /usr/local/bin/ → self-update breaks
- No sudo npm install -g → that's the bug AgentLinux eliminates
- No second Node.js install → PATH race
- ...

## Where you should write
- $HOME/.npm-global/ (npm globals)
- ...
```

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Ubuntu 22.04 apt ships `bats` 1.8.2 and 24.04 ships 1.10.0 | Standard Stack | LOW — if apt ships an older version lacking `--separate-stderr`, we fall back to `bash -c '... 2>&1'` wrapping (already the recommended approach in Pitfall 7). Version check: `apt-cache madison bats` at Dockerfile build time. |
| A2 | `C.UTF-8` is a glibc built-in on Ubuntu 22.04 | Pitfall 5 | LOW — verified on 24.04 (this host). 22.04 ships glibc 2.35 which has C.UTF-8 built-in per glibc release notes. Fallback: `locale-gen en_US.UTF-8` + switch `C.UTF-8` → `en_US.UTF-8`. |
| A3 | Privileged Docker + `/sbin/init` CMD + cgroup bind successfully runs systemd on GH Actions ubuntu-24.04 runners | Pitfall 3, Validation | MEDIUM — GH Actions runners run Docker in their own environment; nested privileged may be constrained. Empirical check required in Phase 2 Wave 0 (run `tests/docker/run.sh` on a PR to ubuntu-24.04 runner, observe BHV-04 tests). Fallback: tag BHV-04 `@qemu-only`. |
| A4 | `run_cron` helper that waits ~70s for a cron tick is tolerable on CI | Example 2 | LOW — adds ~70s to test run; acceptable given `tests/docker/run.sh` budget is ~90s per version per ADR-007. Alternative: use `systemd-run --on-calendar=+1min` for faster scheduling, but that's systemd-cron, not traditional cron. Phase 2 may explore the faster option. |
| A5 | DOC-02 requirement is satisfied by placing CLAUDE.md with the anti-pattern list above | DOC-02 Content Guide | LOW — REQUIREMENTS.md gives us latitude ("guidance that ... agent tools must NOT create shim/wrapper workarounds"); CONTEXT explicitly marks wording as Claude's Discretion. Risk: a reviewer decides the guidance is too implicit; mitigation: explicit "DO NOT" anti-pattern list above. |
| A6 | The `secure_path` vs `env_keep+=PATH` shadowing is the real behavior on Ubuntu 22.04/24.04 | Pitfall 1 | LOW — verified by reading `/etc/sudoers` on this 24.04 host (secure_path present, env_reset present) + multiple upstream docs (sudoers(5), Baeldung). Verified on this host directly. |
| A7 | `install -m 0644 /dev/null "$LOG_FILE"` is a safe, symlink-aware way to initialize the log file | Security Domain | MEDIUM — `install` follows symlinks by default. A symlink attack on `/var/log/agentlinux-install.log` (requires an attacker with write access to `/var/log/`) could redirect writes. Mitigation: `rm -f "$LOG_FILE" && touch "$LOG_FILE" && chmod 0644 "$LOG_FILE"` is equally simple and also not symlink-safe. For Phase 2 (root installer on clean Ubuntu), acceptable. Document in comment. |
| A8 | `shopt -s nullglob` + `for step in "$PROV_DIR"/[0-9][0-9]-*.sh` correctly orders provisioner scripts lexically | Example 1 | LOW — bash globbing is lexical by default; `10-*` sorts before `40-*`. Verified behavior. |

## Open Questions

1. **Should `as_user` land in Phase 2 even though it has no callers in Phase 2?**
   - What we know: CONTEXT + skill both list it as Phase 2 deliverable.
   - What's unclear: shellcheck-complete helper with zero call sites could be flagged as dead code by a reviewer.
   - Recommendation: **Ship it in Phase 2** with a `# TODO Phase 3: first caller is 30-nodejs.sh` comment. The keystone-rule argument (one place to enforce the `sudo npm install -g` ban) outweighs the "unused helper" aesthetic concern. The `bash-engineer` rubric in HARNESS.md §4.2 implicitly endorses this (idempotency primitives are called out as a Phase 2 concern).

2. **Bats `@qemu-only` tag mechanism — what's the exact shape?**
   - What we know: bats-core 1.8+ supports `bats_test_tags=foo` annotation and `--filter-tags` CLI flag.
   - What's unclear: Whether Phase 2's Dockerfile needs to be systemd-capable at all if BHV-04 moves to QEMU. If BHV-04 works in Docker, it's cheaper on every PR; if it's flaky, pushing to Phase 6 is correct.
   - Recommendation: Write Phase 2 tests WITHOUT `@qemu-only` first. Run the full Docker matrix three times; if BHV-04 is GREEN all three times, keep it on PR cadence. If flaky (any 1 of 3 red), tag `@qemu-only` and document in a phase-level decision note.

3. **Should the installer install `openssh-server` and `cron` itself, or does the test harness install them into the Docker image?**
   - What we know: REQUIREMENTS.md says "installer on a clean Ubuntu produces a working environment." Clean Ubuntu Server (cloud image) already ships openssh-server but NOT cron (cron is not in Ubuntu minimal). Desktop Ubuntu ships neither by default on all variants.
   - What's unclear: Does BHV-03 (cron) require the installer to `apt install cron`, or is the expectation that the operator provides a cron-capable host?
   - Recommendation: **Installer does NOT install cron / openssh-server.** REQUIREMENTS.md BHV-03 says "agent user can run commands via cron" — it's a behavior-of-the-environment assertion, not a install-cron-for-me assertion. The Dockerfile for the test harness installs cron + openssh-server because tests need to observe the behavior; real deployments expect operators to have these already. Phase 2 plan MUST document this in the README/CLAUDE.md flow. If a Phase 2 plan-reviewer disagrees, escalate before implementation.

4. **Should the installer ship a template systemd unit to prove BHV-04 coverage, or does BHV-04 test its own ad-hoc unit via `systemd-run`?**
   - What we know: CONTEXT says "Docs include a sample unit illustrating the pattern."
   - What's unclear: Whether the "sample unit" ships as a real file under `/etc/systemd/system/` or only as documentation in CLAUDE.md or a README.
   - Recommendation: Ship as **documentation only** (embed the sample in `/home/agent/CLAUDE.md` DOC-02 payload OR in a Phase 2 README snippet). Real unit files would be state that INST-04 `--purge` must clean up; avoid creating state Phase 2 doesn't need. Tests use `systemd-run` (ad-hoc transient unit) to exercise BHV-04.

## Sources

### Primary (HIGH confidence)

- Ubuntu 24.04 host (this environment) — `/etc/sudoers` contents verified; `/etc/default/locale` verified; `locale -a` output verified; `useradd`, `visudo`, `locale-gen` presence verified
- `docs/HARNESS.md` §1.1 (layout), §1.3 (testing), §1.2 (pre-commit), §4.2 (subagent rubrics), §5.2 (skills), §6 (CLAUDE.md)
- `docs/decisions/004-per-user-npm-prefix.md`, `005-system-nodejs-over-version-managers.md`, `007-docker-plus-qemu-harness.md`, `002-behavior-contract-framing.md`, `010-review-loop-via-claude-md.md`
- `.claude/skills/agentlinux-installer/SKILL.md` — locks strict mode, idempotency primitives, six-mode matrix
- `.claude/skills/behavior-test-contract/SKILL.md` — locks six invocation modes, assertion helpers, test-ID linkage
- `.claude/skills/review/SKILL.md` — dispatch rules for end-of-task review
- `.planning/REQUIREMENTS.md` — authoritative INST-01..05, BHV-01..06, DOC-02, TST-01/02/04 definitions
- `.planning/phases/02-installer-foundation-agent-user/02-CONTEXT.md` — locked user decisions
- `tests/harness/00-layout.bats` (Phase 1 acceptance pattern — diagnostic shape)
- `tests/harness/run.sh` (bats-locator pattern to reuse)
- [sudoers(5) — Ubuntu manpages](https://manpages.ubuntu.com/manpages/noble/man5/sudoers.5.html)
- [systemd.exec(5) — EnvironmentFile](https://www.freedesktop.org/software/systemd/man/systemd.exec.html)
- [bats-core docs (Read the Docs)](https://bats-core.readthedocs.io/en/stable/)
- [Bash manual — Invocation and startup files](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)
- [systemd os-release(5)](https://www.freedesktop.org/software/systemd/man/os-release.html)

### Secondary (MEDIUM confidence)

- [arslan.io — How to write idempotent Bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/) — pattern for `ensure_line_in_file`
- [SIPB — Safe shell scripts](https://sipb.mit.edu/doc/safe-shell/) — `set -euo pipefail` reasoning
- [Baeldung — sudo environment variables](https://www.baeldung.com/linux/sudo-manage-environment-variables) — `env_keep` vs `secure_path` precedence
- [Baeldung — cron PATH](https://www.baeldung.com/linux/cron-jobs-path) — cron's literal-only env parsing
- [Baeldung — load env in cron](https://www.baeldung.com/linux/load-env-variables-in-cron-job) — `/etc/cron.d` PATH header pattern
- [Cronitor — Crontab environment variables](https://cronitor.io/guides/cron-environment-variables) — cron's minimal default env
- [codegenes.net — systemd in Docker](https://www.codegenes.net/blog/how-can-systemd-and-systemctl-be-enabled-and-used-in-ubuntu-docker-containers/) — privileged Docker recipe
- [Docker Docs — Linux post-install](https://docs.docker.com/engine/install/linux-postinstall/) — cgroup mount guidance
- [jrei/systemd-ubuntu](https://hub.docker.com/r/jrei/systemd-ubuntu) — reference implementation of systemd-in-Docker (consulted for pattern, not used as base image)
- [help.ubuntu.com/community/Locale](https://help.ubuntu.com/community/Locale) — locale-gen / update-locale workflow
- [Linux.org — bash, bash -l, sudo -u, sudo -u -i differences](https://www.linux.org/threads/differences-between-bash-bash-l-su-username-su-username-sudo-s-u-username-sudo-i-u-suername.25963/) — login vs non-login behavior

### Tertiary (LOW confidence — flagged for validation)

- none — every LOW-confidence claim was either dropped or promoted via `[ASSUMED]` tag in the Assumptions Log.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — every library verified either via on-host probe or official Ubuntu manpages
- Architecture: HIGH — pattern is the standard Ubuntu/bash idiom; CONTEXT locks it
- PATH wiring six-mode matrix: HIGH — each mode's env source verified against upstream docs (sudoers, systemd.exec, bash invocation, cron); the `secure_path` shadowing is the most subtle finding and is VERIFIED on host
- Pitfalls: HIGH for 1-5, MEDIUM for 6-7 (operational edge cases surfaced from documentation; not all reproduced locally)
- Docker+systemd testing: MEDIUM — the recipe is well-known but GH Actions-specific behavior requires Phase 2 Wave 0 empirical check (flagged as A3)
- DOC-02 content: MEDIUM — guidance intent is clear, exact wording is Claude's Discretion

**Research date:** 2026-04-18
**Valid until:** 2026-05-18 (30 days — stable domain: Ubuntu LTS + bash + bats, minimal churn expected)

## RESEARCH COMPLETE
