# Sudo drop-in

AgentLinux installs a `/etc/sudoers.d/agentlinux` drop-in granting the
`agent` user passwordless sudo for everything — the single line
`agent ALL=(ALL) NOPASSWD: ALL` that lets autonomous coding agents
`apt install`, `systemctl restart`, and reach into the host without ever
stalling on a `[sudo] password for agent:` prompt.

## The problem

An autonomous coding agent that runs for hours without a human in the loop
hits root-required operations constantly. It needs to `apt install` a build
dependency mid-task because the project just added a native module. It
needs to `systemctl restart` a service it just reconfigured. It needs to
edit a file under `/etc/`, install a system font, swap a binary via
`update-alternatives`, or set a kernel parameter. Each of those operations
either succeeds via sudo or wedges the agent's loop indefinitely.

The earlier "zero sudo for the agent user" posture was elegant on paper —
the agent owned its npm prefix and its home, so why would it need root? —
but it predictably blocked too much real agent work.
A long-running agent that hits a `sudo -n true` failure cannot recover; the
shell either prompts for a password (which a non-interactive session never
satisfies) or refuses to run, and the agent's task fails for a reason that
is not a real bug in its code, just an environmental mismatch.

The naive alternatives are both worse than the problem. Hard-coding a
shared root password into the agent's environment is a credential leak
waiting to happen. Adding the agent to `sudoers` with a narrow command
allowlist sounds tidy until the user notices that the allowlist needs
extending every other day — every new tool, every new build dep, every new
service. The maintenance tax falls on whoever maintains AgentLinux,
which is exactly the wrong place for it.

## What AgentLinux does

The installer's second provisioner step writes a single drop-in at
`/etc/sudoers.d/agentlinux` containing exactly `agent ALL=(ALL) NOPASSWD:
ALL`. The file is mode `0440`, ownership `root:root`, validated through
`visudo -cf` on a tmpfile *before* atomic-rename into place — a syntax
error in the written content aborts the installer without ever touching
the system's existing sudoers policy. A post-install `visudo -cf` rehash
catches any TOCTOU corruption between rename and exit. Re-runs produce a
byte-identical file.

Mode `0440` means only root can read the drop-in. The agent observes its
effective policy via `sudo -l` but cannot `cat` the file directly. The
single-line scope means there is nothing to maintain — no allowlist
churn, no per-recipe sudo special cases. The agent is treated as a
trusted coworker, not as an adversary the system needs to defend against.

What the drop-in deliberately does *not* alter: the per-user npm prefix
invariant. `sudo` is a tool the agent uses for legitimately-system-level
operations. It is not the path agents install through. `sudo npm install
-g` remains forbidden across the codebase regardless of whether the
password prompt appears, because that path destroys the agent's ownership
of its own tools — which is the bug class AgentLinux exists to eliminate.
The agent's `as_user agent <cmd>` discipline still draws the line on
which path is correct.

## Worked example

```
$ sudo -u agent sudo -n true && echo ok
ok

$ sudo -u agent sudo apt-get install -y jq
... apt output ...
Setting up jq (1.6-2.1ubuntu3) ...

$ sudo -u agent sudo -l
User agent may run the following commands on this host:
    (ALL) NOPASSWD: ALL
```

A counter-example illustrates the discipline the codebase still holds:

```
$ sudo -u agent sudo npm install -g @anthropic-ai/claude-code
# This WOULD run password-free now — but it's still a bug.
# It writes a root-owned global tree, breaks `claude update`, and
# violates the per-user-prefix invariant. The codebase's `as_user`
# rule and our PR review process reject it on every PR.
```

The lesson: sudo is the right tool for `apt install` and `systemctl
restart`. It is the wrong tool for installing the agent's own software.
AgentLinux trusts the agent with sudo *and* keeps the per-user prefix
invariant intact.

## Value vs the naive approach

Without a sudoers drop-in, the two naive paths are zero-sudo (the agent
runs without root) or shared-root-password (the agent prompts for it). Two
problems:

1. **Zero-sudo blocks legitimate work.** A long-running coding agent that
   needs `apt install <build-dep>` mid-task or `systemctl restart <svc>`
   to validate its config change simply stalls. The agent is correct, the
   environment is the problem; "the agent doesn't need root" was a
   too-optimistic read of how real agents work.
2. **Password prompts stall autonomous loops.** A `[sudo] password for
   agent:` prompt in a non-interactive session never resolves. The agent
   either retries indefinitely against a closed stdin or fails for a
   reason that has nothing to do with the task it was given. Either
   outcome wastes hours.

**AgentLinux drops the sudoers entry so agents work; the codebase's
`as_user` discipline still keeps the per-user prefix invariant intact.**
The trade-off — granting full sudo means any agent-held secret on the
host is effectively a root credential — is documented explicitly in
[the agent-user-full-sudo decision record](../decisions/012-agent-user-full-sudo.md),
which records this decision against the alternatives (narrow apt-only,
medium apt+systemctl, broad ALL).

## Related

- [Agent user](agent-user.md) — the user this drop-in grants sudo to and
  the per-user prefix invariant the drop-in deliberately does not affect.
- [Installer](installer.md) — the entrypoint that runs the provisioner
  step that writes this drop-in.
- [../decisions/012-agent-user-full-sudo.md](../decisions/012-agent-user-full-sudo.md)
  — the full decision record, including considered alternatives (zero
  sudo, narrow allowlist, and a future sandboxing path on our roadmap).
