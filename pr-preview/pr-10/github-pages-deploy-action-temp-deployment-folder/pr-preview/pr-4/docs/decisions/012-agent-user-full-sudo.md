# 012: Agent user gets passwordless sudo (ALL commands)

**Status:** Accepted
**Date:** 2026-04-19
**Supersedes (partially):** Phase 2 CONTEXT §"Sudoers & Privilege Posture" — "No sudo grants for the agent user"

## Context

Phase 2 CONTEXT locked "zero sudo for the agent user" with the reasoning that the agent owns its npm prefix + home and therefore doesn't need root. This held during the installer bootstrap + Node.js runtime phases (Phases 2-3) and the CLI wiring phase (Phase 4) where test-dummy + scaffolded recipes exercised dispatch without needing root.

Phase 5 smart-discuss (2026-04-19) surfaced the wrong assumption. Real coding agents — Claude Code especially — frequently need to:

1. **Install system packages** (`apt-get install` for build tooling, Playwright browser dependencies via `playwright install-deps`, language runtimes, compilers, native libs).
2. **Manage services** (`systemctl restart`, enable, disable) when agents configure local daemons or dev infrastructure.
3. **Modify system state** that's legitimately outside user-owned directories (install system fonts, configure CA certs for internal registries, swap `update-alternatives` binaries, set kernel parameters, etc).

The user's direction (2026-04-19): "The agent will need apt install permissions way more often than just in this [Playwright] example. Make sure our agent user CAN install packages."

After scope review (narrow apt-only → medium apt+systemctl → broad ALL), the user selected **Option C: full passwordless sudo**. Rationale:

- **The agent is a trusted coworker, not an adversary.** If the user grants an agent a system, they're giving it the latitude a human admin would have. Restricting to an allowlist predictably breaks workflows and forces users to escalate to us to extend the list each time.
- **Per-user-ownership invariant still holds.** ADR-004 (agent's npm prefix under `/home/agent/.npm-global`) remains the load-bearing decision: agent tools self-install/self-update into the user-owned prefix. Sudo is for THE OTHER CLASS OF OPERATIONS — ones that would have needed root even for a human user.
- **AGT-02 unchanged.** The canonical acceptance test (Claude Code self-update without sudo / EACCES) is about the user-owned path, not about whether sudo exists on the system. `claude update` still runs in the user-owned prefix; sudo never enters the self-update path.
- **Blast radius is bounded by the user's decision to install AgentLinux.** If you don't trust the agent with root, you don't install AgentLinux. We're not sandboxing against a malicious agent — v0.4+'s USR-05 (sandboxing / rootless container) would be a different product.

## Decision

Install a sudoers drop-in at `/etc/sudoers.d/agentlinux` containing exactly:

```
agent ALL=(ALL) NOPASSWD: ALL
```

File mode `0440`, ownership `root:root`, validated via `visudo -cf` before being moved into place (fail-fast if invalid).

Implementation details:

1. **New provisioner `plugin/provisioner/20-sudoers.sh`** (runs after `10-agent-user.sh` so the agent user exists, before `30-nodejs.sh`/`40-path-wiring.sh`).
2. **Idempotency via `ensure_marker_block`** or equivalent: re-runs produce byte-identical `/etc/sudoers.d/agentlinux` file.
3. **`visudo -cf /etc/sudoers.d/agentlinux`** must return zero before the file is considered installed. If it ever returns non-zero on re-run, installer fails loudly (never ship a file that would break sudoers).
4. **Install log records the grant** explicitly (one-line `log_info` at install time) so audit trails show this happened.
5. **`--purge` removes it** symmetrically (already in the Phase 4 `--purge` 7-step list under "sudoers drop-ins").

## Consequences

- **Phase 2 CONTEXT is partially superseded.** The "zero sudo for agent user" statement is replaced by "agent user has passwordless sudo via `/etc/sudoers.d/agentlinux`, installed at provisioner-time, controlled by the AgentLinux maintainer — not by individual catalog recipes." Historical Phase 2 commits stand; STATE.md + REQUIREMENTS.md are amended to reflect the new reality.
- **Phase 5 recipes can freely `apt install` / `systemctl restart` / etc.** Playwright's `npx playwright install-deps` (which wants `apt install libnss3 libnspr4 ...`) now works without a special case. No per-recipe sudo workarounds needed.
- **BHV-05 Phase 2 deferred note remains valid** (different concern: that's about *another user* becoming agent via `sudo -u agent bash -c`, which is the PAM secure_path issue — unrelated to agent having its own sudo).
- **New requirement IDs** land in `REQUIREMENTS.md`:
  - **INST-06**: After install, `sudo -u agent sudo -n true` returns exit 0 — agent has passwordless sudo.
  - **BHV-07**: `/etc/sudoers.d/agentlinux` exists, mode `0440`, owner `root:root`, passes `visudo -cf`, contains exactly `agent ALL=(ALL) NOPASSWD: ALL`.
- **New threat surface**: any agent-held secret (API keys, SSH keys in the agent's home) effectively becomes a root-equivalent credential on the host. Documented explicitly; mitigations are the user's to choose (hardware-backed credentials, ssh-agent forwarding instead of key storage, etc).
- **v0.4+ USR-05 "sandboxing / rootless container"** becomes a more valuable follow-on — users who want tighter containment can adopt that later without this ADR blocking the path.
- **Phase 5.1 INSERTED** into ROADMAP as a decimal phase between Phase 4 and Phase 5. Delivers: provisioner, ADR-012 (this doc), INST-06 + BHV-07 bats tests, CLAUDE.md awareness update so agents know they have sudo available. One acceptance gate; closes before Phase 5 proper begins.

## References

- ADR-004 — per-user npm prefix (unchanged; still load-bearing for AGT-02).
- ADR-011 — stability-first version pinning (unchanged).
- Phase 2 CONTEXT — `sudoers & privilege posture` section is partially superseded by this ADR.
- REQUIREMENTS.md — adds INST-06, BHV-07; amends BHV-05 note to clarify the PAM/secure_path issue is a separate sudoers-for-impersonation matter, not the passwordless-sudo-for-agent matter.
- v0.4+ USR-05 (sandboxing / rootless container) — the alternative architecture for users who want tighter containment; this ADR does not block that migration path.
