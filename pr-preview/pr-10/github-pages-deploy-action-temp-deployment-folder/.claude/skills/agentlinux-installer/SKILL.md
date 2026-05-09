---
name: agentlinux-installer
description: Use when writing or modifying bash code under plugin/bin/, plugin/lib/, or plugin/provisioner/. Codifies AgentLinux's installer conventions — set -euo pipefail, idempotency primitives, as_user helper, distro detection, logging, error propagation, and the PATH-wiring contract across six invocation modes (interactive login, non-interactive SSH, cron, systemd, sudo -u, sudo -u -i). Grows as installer patterns stabilize in Phase 2+.
---

# agentlinux-installer — Bash installer conventions

**Status:** Skeleton. This skill documents the intended shape of the AgentLinux bash installer. Phase 2 lands the real primitives under `plugin/lib/`; this skill will absorb them as they stabilize. For Phase 1 the non-negotiable rules are already fixed and will not drift.

Authoritative spec: `docs/HARNESS.md` §5.2 (skill table) and §1.1 (plugin layout). Decisions: ADR-004 (per-user npm prefix), ADR-005 (NodeSource over version managers). Requirements this skill helps satisfy: INST-01, INST-02, INST-05, BHV-01..BHV-06, RT-01..RT-04.

## When to use this skill

Use when the task touches any `.sh` file under:

- `plugin/bin/` — the `agentlinux-install` entrypoint.
- `plugin/lib/` — shared bash libraries (`log.sh`, `idempotency.sh`, `as_user.sh`, `distro_detect.sh`).
- `plugin/provisioner/` — ordered numbered scripts (`10-agent-user.sh`, `30-nodejs.sh`, `40-path-wiring.sh`, `50-registry-cli.sh`).
- `packaging/curl-installer/install.sh` — the curl-pipe-bash entrypoint.

Skip for bats test files (use the `behavior-test-contract` skill instead).

## Non-negotiable rules (will not drift)

1. **Strict mode everywhere.** Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`. No exceptions.
2. **Error traps.** Every script installs an `on_error` trap that logs the failing line and exits non-zero. Never swallow errors with `|| true` except at documented skip-paths.
3. **No `sudo npm install -g`. Ever.** Global npm installs always run as the agent user via `as_user agent npm install -g <pkg>` — this is the keystone ownership rule (ADR-004).
4. **Idempotency is mandatory.** Every state-changing operation is wrapped in an `ensure_*` primitive:
   - `ensure_user <name>` — useradd only if absent.
   - `ensure_line_in_file <line> <file>` — grep-then-append; never blind-append.
   - `ensure_npm_prefix <user> <path>` — reads `npm config get prefix` first.
   - `ensure_symlink <src> <dst>` — remove-then-create only if target differs.
   - `ensure_dir <path> <mode> <owner>` — stat-then-create.
   Re-running the installer MUST converge (INST-02).
5. **Structured logging.** Use `log_info`, `log_warn`, `log_error` from `plugin/lib/log.sh`. Colored to stderr. Never `echo` directly for user-facing messages.
6. **No curl-pipe-bash inside provisioners.** Curl-pipe-bash is acceptable at the outermost entrypoint (`packaging/curl-installer/install.sh`) with SHA256 verification; downstream provisioner scripts fetch pinned artifacts only.

## Intended plugin/ layout (copy from HARNESS.md §1.1)

```
plugin/
├── bin/agentlinux-install          # Entrypoint. Parses args, dispatches to provisioners.
├── lib/
│   ├── log.sh                      # log_info / log_warn / log_error
│   ├── idempotency.sh              # ensure_user, ensure_line_in_file, ensure_npm_prefix, ensure_symlink, ensure_dir
│   ├── as_user.sh                  # as_user <user> <cmd ...> — sudo -u -H -E drop-in
│   └── distro_detect.sh            # Read /etc/os-release, enforce ubuntu 22.04|24.04
├── provisioner/
│   ├── 10-agent-user.sh            # useradd agent, home, shell, locale
│   ├── 30-nodejs.sh                # NodeSource APT repo + Node 22 LTS
│   ├── 40-path-wiring.sh           # PATH across six invocation modes (see below)
│   └── 50-registry-cli.sh          # Install the agentlinux CLI into agent's PATH
└── catalog/                        # JSON + per-agent install recipes (see catalog-schema skill)
```

## Distro detection (Phase 2)

Reads `/etc/os-release`. Refuses to run when `ID` ≠ `ubuntu` or `VERSION_ID` ∉ `{22.04, 24.04}`. Emits a clear error naming what was found vs. what was required. Future distros (Fedora, Alma, Arch) land in v0.4+.

## PATH-wiring for all six invocation modes (BHV-01..06)

The single hardest part of the installer. Each invocation mode reads PATH from a different source; all six must see the agent's npm prefix `$HOME/.npm-global/bin` and the agentlinux CLI. This is the mitigation for the entire EACCES / recursive-shim bug class.

| Invocation mode | PATH source | What installer writes |
|---|---|---|
| Interactive bash login shell (BHV-06) | `/etc/profile.d/*.sh` + `~/.bash_profile` / `~/.profile` | `/etc/profile.d/agentlinux.sh` adds `$HOME/.npm-global/bin` |
| Non-interactive SSH (BHV-02) | `~/.bashrc` (bash reads it for non-login shells with `ssh host '<cmd>'`) | Append idempotent PATH export to `~agent/.bashrc` |
| Cron (BHV-03) | `/etc/environment` + cron-specific PATH | Augment `/etc/environment` with the agent npm prefix |
| systemd `User=agent` (BHV-04) | Unit's `Environment=PATH=...` | Any systemd unit template the installer writes ships an explicit `Environment=PATH=...` |
| `sudo -u agent` (BHV-05) | `env_keep` + target user's env | `/etc/sudoers.d/agentlinux` with `Defaults env_keep+=PATH` (mode **0440**, validated by `visudo -cf`) |
| `sudo -u agent -i` (BHV-05) | Target user's login env (`~/.profile`) | Same as BHV-06; also `~agent/.profile` entry |

Every provisioner change that adds a new binary MUST update `40-path-wiring.sh` and the corresponding bats coverage in `tests/bats/20-agent-user.bats`.

## Sudoers minimalism (security-engineer rubric)

- **Mode 0440**, never 0644, never 0755. Validated with `visudo -cf /etc/sudoers.d/agentlinux` before committing the file.
- Minimal rules only: `Defaults env_keep+=PATH` and any specific `NOPASSWD` entries the installer actually needs. No wildcard `ALL=(ALL) NOPASSWD: ALL` — ever.
- The file name matches `^[A-Za-z0-9_-]+$` (sudoers include requirement; no dots or tildes).

## Growth plan

- **Phase 2:** Lands `plugin/lib/{log.sh,idempotency.sh,as_user.sh,distro_detect.sh}` and `plugin/provisioner/10-agent-user.sh` + `40-path-wiring.sh`. This skill absorbs the final primitive signatures and the real PATH-wiring diff.
- **Phase 3:** Adds `30-nodejs.sh` (NodeSource + per-user npm prefix). Extends this skill with the exact Node/npm invocations (RT-01..RT-04).
- **Phase 4:** Adds `50-registry-cli.sh` (installs the agentlinux CLI). Adds the "no wrapper shims" sub-rule here.
- **Phase 6:** Adds `packaging/curl-installer/install.sh` (SHA256 verification). Skill gains the curl-pipe-bash hardening patterns.

## Related

- `docs/HARNESS.md` §1.1 (layout), §5.2 (skill table), §4.2 (bash-engineer + security-engineer rubrics).
- ADRs: 004 (per-user npm prefix), 005 (NodeSource), 007 (Docker + QEMU harness), 010 (review loop).
- Subagents: `bash-engineer`, `security-engineer` — review every change to the files this skill covers.
- Sibling skills: `behavior-test-contract` (bats tests that assert this installer works), `catalog-schema` (recipes consumed by `50-registry-cli.sh`), `qemu-harness` (release-gate run of the installer on a fresh cloud image).
