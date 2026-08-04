# Phase 2: Installer Foundation + Agent User - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Running the installer on a clean Ubuntu 22.04 or 24.04 produces an `agent` user who can run commands — with all six BHV invocation modes working (interactive bash login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u agent`, `sudo -u agent -i`) and zero `EACCES` / `permission denied` output — even though no agents are installed yet.

Requirements in scope: INST-01, INST-02, INST-05, BHV-01..BHV-06, DOC-02, TST-01 (partial — grows with every subsequent phase), TST-02, TST-04.

Out of scope for Phase 2: Node.js runtime (Phase 3 / RT-XX), registry CLI + catalog (Phase 4), agent tools installability (Phase 5), SHA256 curl-installer + release pipeline (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Installer UX & Logging
- Root-privilege check fails fast at top of `plugin/bin/agentlinux-install` with a clear error if `EUID != 0` (no auto-sudo, no lazy failure).
- Structured logging via `plugin/lib/log.sh` — `log_info`, `log_warn`, `log_error`, timestamped — all stdout/stderr tee'd to `/var/log/agentlinux-install.log` so INST-05 can grep `EACCES|permission denied` against the full transcript.
- `set -euo pipefail` plus a top-level `trap ERR` that prints a failure banner naming the failing step and the log path before exit.
- Phase 2 flags: `--help`, `--version`, `--purge` (stub warning — real wire-up lands in Phase 4/6), `--verbose` (sets DEBUG log level).

### PATH & Environment Wiring (six-mode matrix)
- **Interactive bash login & `sudo -u agent -i`**: `/etc/profile.d/agentlinux.sh` (mode 0644) — single source covering both cases via `/etc/profile` sourcing.
- **Cron**: Write `PATH=...` header into `/etc/cron.d/agentlinux` template; document the same convention for user crontabs so any scheduled agent job inherits PATH without relying on shell profiles.
- **systemd `User=agent`**: Drop `/etc/agentlinux.env` via installer and reference it from units with `EnvironmentFile=/etc/agentlinux.env`. Docs include a sample unit illustrating the pattern.
- **Non-interactive SSH & `sudo -u agent`**: `/etc/profile.d/agentlinux.sh` plus agent's `~/.bashrc` with a top-of-file guard that sources the profile.d fragment. `/etc/environment` is populated as a last-resort fallback. `.ssh/environment` is rejected (requires `PermitUserEnvironment yes`, too invasive).

### Sudoers & Privilege Posture
- **Zero sudo for the agent user.** Post-install, the agent owns its home + (in Phase 3) npm prefix; no root-privileged operations are performed by agent tooling.
- Any sudoers drop-in the installer places lives at `/etc/sudoers.d/agentlinux`, mode 0440, validated with `visudo -cf` before being moved into place. (Phase 2 ships no default drop-in; this is the contract when one is added later.)
- No `agentlinux-users` group or wildcard `sudo -u agent` rule. Callers rely on their existing sudoers entry to invoke `sudo -u agent`.
- `--purge` uninstall path (wired in Phase 4) removes `/etc/sudoers.d/agentlinux` + any installer-placed drop-ins along with the agent user and home.

### Test Harness & CI Matrix
- Docker matrix: one `tests/docker/Dockerfile.ubuntu-22.04` + `tests/docker/Dockerfile.ubuntu-24.04`; `tests/docker/run.sh <version>` builds the image, runs the installer inside, then runs the bats suite. Matches HARNESS.md §1.1 layout.
- `tests/bats/helpers/invoke_modes.bash` exposes six helpers — `run_interactive`, `run_ssh`, `run_cron`, `run_systemd_user`, `run_sudo_u`, `run_sudo_u_i` — each returning `$status`/`$output` so bats tests can loop over modes.
- `tests/bats/helpers/assertions.bash`: `assert_no_eacces`, `assert_path_has <bin>`, `assert_exit_zero`; every failure message prints the requirement ID, expected value, observed value, and log file path (satisfies TST-04).
- systemd + cron + openssh-server run inside privileged Docker on every PR (BHV-03..05 covered on PR). Any mode that proves flaky in Docker gets a `@qemu-only` tag so the Docker PR matrix stays fast while the QEMU release-gate suite (Phase 6) absorbs the slower tests.

### Claude's Discretion
- Exact wording/layout of CLAUDE.md placed at `/home/agent/CLAUDE.md` per DOC-02, provided it tells agent tooling NOT to create shim/wrapper workarounds at `/usr/local/bin/` or elsewhere.
- Internal split between `plugin/provisioner/10-agent-user.sh`, `plugin/provisioner/40-path-wiring.sh` (etc.) vs fewer/more numbered steps — Claude picks the split that matches the per-task atomic-commit pattern used in Phase 1.
- Shell helper function shapes inside `plugin/lib/log.sh`, `plugin/lib/idempotency.sh`, `plugin/lib/as_user.sh`, `plugin/lib/distro_detect.sh` — any shape that passes `shellcheck --severity=warning --shell=bash --external-sources` and the installer behavior tests.
- Specific `@qemu-only` tags (if any) — Claude picks per test based on Docker reliability during execution.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `plugin/bin/agentlinux-install` — stub entrypoint exists (`#!/usr/bin/env bash`, `set -euo pipefail`, prints a "Phase 2+" marker). Replace body with real provisioner orchestration.
- `plugin/lib/` — empty directory already created; receives `log.sh`, `idempotency.sh`, `as_user.sh`, `distro_detect.sh` helpers per HARNESS.md §1.1.
- `plugin/provisioner/` — empty directory already created; receives ordered `10-agent-user.sh`, `40-path-wiring.sh` (etc.) step scripts.
- `plugin/catalog/schema.json` + `plugin/catalog/agents/` — exist as scaffolding for Phase 4; untouched by Phase 2.
- `tests/bats/helpers/` — empty directory; receives `invoke_modes.bash` + `assertions.bash`.
- `tests/docker/` — empty directory; receives `Dockerfile.ubuntu-22.04`, `Dockerfile.ubuntu-24.04`, `run.sh`.
- `tests/harness/run.sh` + 7 bats files — Phase 1's harness meta-test suite; `bash tests/harness/run.sh` exits 0. Do not regress.
- `.pre-commit-config.yaml` — shellcheck + shfmt + biome + JSON-Schema validation all wired; any new bash lands green.
- `.github/workflows/test.yml` — already scaffolded with an empty-plugin guard; Phase 2 populates the matrix so the guard falls through to the real bats run.
- `.claude/skills/agentlinux-installer/SKILL.md` — codifies `set -euo pipefail`, `as_user`, distro detection, logging, error propagation, six-mode PATH matrix. Skeleton body; Phase 2 is its first concrete absorption.
- `.claude/skills/behavior-test-contract/SKILL.md` — codifies how to write BHV/INST tests, shared helpers, no-EACCES contract.

### Established Patterns
- **Per-task atomic commits** via raw `git add <files> && git commit --no-gpg-sign` (not `gsd-tools commit` — see Plan 01-01/01-02/01-03 notes in STATE.md). Each provisioner step ships in its own commit alongside its bats tests.
- **Copy-of-truth** between HARNESS.md §4.2 and project-scoped subagent rubrics; drift is detectable by `diff`. Same principle applies: installer behavior contract lives in `docs/HARNESS.md` + `.claude/skills/agentlinux-installer/SKILL.md`; implementation in `plugin/lib/` reflects it.
- **Fail-closed guards** in CI workflows via `compgen -G` / `[[ -x ... ]]`; Phase 2 populates sources so the guards fall through. No guard is removed.
- **Every behavior-test failure prints the requirement ID it fails** (established pattern in `tests/harness/*.bats` via `# HRN-XX: ...` diagnostic lines).
- **Review loop** on every changed file per `docs/HARNESS.md` §4 + `.claude/skills/review/SKILL.md`. Phase 2 is the first large-surface bash change; expect `bash-engineer`, `security-engineer`, `qa-engineer`, `behavior-coverage-auditor` to all have opinions.

### Integration Points
- Installer entrypoint `plugin/bin/agentlinux-install` sources `plugin/lib/*.sh` (order matters: log → distro_detect → idempotency → as_user) then dispatches `plugin/provisioner/*.sh` in numeric order.
- `tests/docker/run.sh` is called by `.github/workflows/test.yml` with each Ubuntu version; must not assume a host-side bats install (install bats inside the Docker image).
- `tests/bats/helpers/invoke_modes.bash` is sourced by every `tests/bats/*.bats` file that targets the six-mode matrix.
- DOC-02's `/home/agent/CLAUDE.md` is placed by the same provisioner step that creates the agent user; lives under the agent home so agent tooling discovers it.
- STATE.md is updated at phase close with plan-by-plan metrics (continuing Phase 1's pattern).

</code_context>

<specifics>
## Specific Ideas

- Installer log file `/var/log/agentlinux-install.log` must be greppable by INST-05 without the test having to stitch stdout and stderr together — tee both streams to the log with timestamps.
- The `as_user` helper in `plugin/lib/as_user.sh` is the keystone primitive — it's the function that prevents the "sudo npm install -g" anti-pattern. Call sites must always go through it, never raw `sudo -u`.
- `/etc/profile.d/agentlinux.sh` uses a guard (`[[ -n "${AGENTLINUX_PROFILE_SOURCED:-}" ]] && return`) so re-sourcing does not double-append PATH entries — INST-02 idempotency depends on this.
- `/etc/agentlinux.env` has a tiny footprint: `PATH=/home/agent/.local/bin:/home/agent/.npm-global/bin:/usr/local/bin:/usr/bin:/bin` + `LANG=C.UTF-8` + `LC_ALL=C.UTF-8`. Phase 3 extends it with Node's npm-global-prefix path, not Phase 2.
- `tests/bats/helpers/invoke_modes.bash` must handle Docker's lack of systemd gracefully — if `systemctl is-system-running` fails, the `run_systemd_user` helper returns a clearly-tagged skip rather than a misleading pass.
- `DOC-02` CLAUDE.md at `/home/agent/CLAUDE.md` explicitly lists the anti-patterns: no `/usr/local/bin/` shims pointing at agent-owned binaries; no wrapper scripts that re-exec under `sudo`; no creating a second Node.js install to work around permissions.

</specifics>

<deferred>
## Deferred Ideas

- Remote-fetch catalog with embedded fallback (CAT-04) — v0.4+.
- `.deb` distribution as first-class (INF-02) — v0.4+.
- Multi-distro distro detection (DST-01..DST-03) — v0.4+.
- Per-agent sandboxing (USR-05) — v0.4+.
- Fleet / config-management integration — explicitly out of scope per REQUIREMENTS.md.
- Full QEMU reliance in CI (skipping Docker for everything) — ADR-007 locks the Docker fast path + QEMU release gate dual model; changing that is a v0.4 decision.

</deferred>
