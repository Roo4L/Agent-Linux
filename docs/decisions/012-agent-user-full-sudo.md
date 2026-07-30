# 012: Agent user gets passwordless sudo (ALL commands)

**Status:** Accepted
**Date:** 2026-04-19
**Supersedes (partially):** the earlier "no sudo grants for the agent user" posture

## Context

The project originally locked "zero sudo for the agent user," reasoning that the agent owns its npm prefix and home directory and therefore does not need root. That held while the work was installer bootstrap, the Node.js runtime, and CLI wiring — scaffolded recipes exercised dispatch without ever needing root.

Bringing real agents into the catalog surfaced the wrong assumption. Coding agents — Claude Code especially — frequently need to:

1. **Install system packages** — `apt-get install` for build tooling, Playwright's browser dependencies via `playwright install-deps`, language runtimes, compilers, native libraries.
2. **Manage services** — `systemctl restart`, enable, disable — when agents configure local daemons or dev infrastructure.
3. **Modify system state** legitimately outside user-owned directories: install system fonts, configure CA certificates for internal registries, swap `update-alternatives` binaries, set kernel parameters.

The maintainer's direction (2026-04-19): *"The agent will need apt install permissions way more often than just in this [Playwright] example. Make sure our agent user CAN install packages."*

After reviewing three scopes — narrow apt-only, medium apt plus systemctl, and broad ALL — the maintainer selected **full passwordless sudo**. The rationale:

- **The agent is a trusted coworker, not an adversary.** Granting an agent a system means giving it the latitude a human admin would have. An allowlist predictably breaks workflows and forces users to come back to us to extend it each time.
- **The per-user-ownership invariant still holds.** ADR-004 (the agent's npm prefix under `/home/agent/.npm-global`) remains the load-bearing decision: agent tools self-install and self-update into the user-owned prefix. Sudo is for the *other* class of operations — the ones that would have needed root even for a human user.
- **The self-update acceptance test is unaffected.** Claude Code self-updating without sudo and without EACCES is about the user-owned path, not about whether sudo exists on the system. `claude update` still runs in the user-owned prefix; sudo never enters the self-update path.
- **Blast radius is bounded by the decision to install AgentLinux at all.** If you do not trust the agent with root, you do not install AgentLinux. This is not a sandbox against a malicious agent — that would be a different product.

## Decision

Install a sudoers drop-in at `/etc/sudoers.d/agentlinux` containing exactly:

```
agent ALL=(ALL) NOPASSWD: ALL
```

File mode `0440`, ownership `root:root`, validated with `visudo -cf` before being moved into place — fail fast if invalid.

Implementation requirements:

1. **The drop-in is written by the provisioner**, after the agent user exists and before the Node.js runtime and PATH wiring steps.
2. **Idempotent.** Re-runs produce a byte-identical `/etc/sudoers.d/agentlinux`.
3. **`visudo -cf` must return zero** before the file is considered installed. If it ever returns non-zero on a re-run, the installer fails loudly — never ship a file that would break sudoers.
4. **The install log records the grant** explicitly, so audit trails show it happened.
5. **`--purge` removes it** symmetrically.

## Consequences

- **The "zero sudo for agent user" posture is replaced** by: the agent user has passwordless sudo via `/etc/sudoers.d/agentlinux`, installed by the provisioner and controlled by the AgentLinux maintainer — not by individual catalog recipes.
- **Catalog recipes can freely `apt install`, `systemctl restart`, and so on.** Playwright's `npx playwright install-deps`, which wants `apt install libnss3 libnspr4 …`, works without a special case. No per-recipe sudo workarounds.
- **Two behaviors become testable and are covered by the bats suite:** after install, `sudo -u agent sudo -n true` exits 0; and `/etc/sudoers.d/agentlinux` exists with mode `0440`, owner `root:root`, passes `visudo -cf`, and contains exactly the one grant line.
- **A separate, pre-existing concern is unaffected:** another user becoming the agent via `sudo -u agent bash -c` is a PAM `secure_path` matter, unrelated to the agent having its own sudo.
- **New threat surface.** Any secret the agent holds — API keys, SSH keys in its home directory — effectively becomes a root-equivalent credential on that host. This is documented rather than mitigated; the mitigations are the user's to choose (hardware-backed credentials, ssh-agent forwarding instead of stored keys).
- **Sandboxing or a rootless container becomes a more valuable follow-on.** Users wanting tighter containment can adopt that later; this decision does not block that path.
- **The agent-facing instructions record the grant**, so an agent working on the host knows sudo is available to it.

## References

- ADR-004 — per-user npm prefix. Unchanged, and still the load-bearing decision behind the self-update acceptance test.
- ADR-011 — stability-first version pinning. Unchanged.
