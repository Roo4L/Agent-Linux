# Node.js runtime

AgentLinux installs the system Node.js LTS via apt (NodeSource), then wires
the agent user with a per-user npm prefix at `~/.npm-global/` and a PATH
that resolves the agent's binaries across every invocation mode the agent
ever runs in — interactive shell, non-interactive SSH, cron, systemd user
units, `sudo -u agent`, `sudo -u agent -i`. Two pieces, one runtime
contract: the system owns Node.js, the agent owns its npm globals, and
PATH agrees with both.

## The problem

Two intertwined problems define what an agent-runnable Node.js layer has
to solve.

The first is invocation-mode breakage. Version managers — nvm, asdf, fnm,
volta — install Node.js into a shell-activated prefix and require a shell
hook (`. ~/.nvm/nvm.sh`, `eval "$(fnm env)"`) to wire PATH. The hook only
fires in interactive shells. Cron, systemd, non-interactive SSH (`ssh host
'cmd'`), and `sudo -u agent <cmd>` all skip those hooks, so `node` is
missing in exactly the contexts where automation actually runs. Tests pass
in the developer's terminal and break the moment the agent runs unattended.

The second is ownership corruption. System Node.js installed via apt is
owned by root. `sudo npm install -g <tool>` then writes into
`/usr/lib/node_modules` as root, leaves a wrapper at `/usr/local/bin/`,
and the next non-root operation under `~/.npm/` fails with EACCES — and
worse, every tool that ships its own self-updater can no longer rewrite
itself. AGT-02 is the regression test that catches this: a fresh install
plus `claude update` must succeed without any `sudo` prompt and without
any EACCES.

Both naive paths fail the same invariant from opposite sides: the
version-manager path makes Node.js invisible to non-interactive contexts,
the system-Node-with-`sudo-npm` path makes the agent unable to update its
own tools. Either way, the autonomous loop stalls.

## What AgentLinux does

The runtime layer has two halves and they only work together.

The first half is system Node.js via apt. AgentLinux installs the official
NodeSource apt repository (HTTPS, GPG-signed, the upstream blessed by
ADR-005), then `apt-get install nodejs`. The currently-tracked line is
Node.js LTS (v22 at the v0.3.0 release; future releases follow the LTS
cadence). System Node.js means a stable PATH entry that works in every
invocation mode, no shell-init hooks, no per-user re-activation flow. The
trade-off — Node.js version upgrades follow the distro's apt cadence
rather than a bleeding-edge per-user toggle — is documented in ADR-005
and is acceptable because AgentLinux's job is a correctly-owned runtime,
not bleeding-edge Node features.

The second half is the per-user npm prefix. The installer creates
`~/.npm-global/{bin,lib}` owned by `agent:agent`, writes
`prefix=/home/agent/.npm-global` into `~/.npmrc`, and PATH-wires the
prefix's `bin/` across four artifacts that together cover six invocation
modes: `/etc/profile.d/agentlinux.sh` (interactive login + `sudo -u agent
-i`), the `~/.bashrc` marker block at the top before the skel
early-return guard (non-interactive SSH + `sudo -u agent bash -c`),
`/etc/agentlinux.env` consumed via `EnvironmentFile=` in systemd `User=agent`
units, and `/etc/cron.d/agentlinux` for cron. Belt-and-braces:
`NPM_CONFIG_PREFIX` is also exported so systemd consumers see the prefix
even if `~/.npmrc` reads regress for any reason. The PATH literal is
byte-identical across every artifact — split-brain divergence fails the
acceptance grep.

Path ordering is deliberate. `/home/agent/.npm-global/bin` lands first in
PATH, ahead of `/usr/local/bin` and the system bin directories, so a
stray wrapper shim at `/usr/local/bin/<tool>` (the canonical anti-pattern
the agent-user CLAUDE.md forbids) cannot win against the agent-owned
binary. Every install in the codebase routes through `as_user agent
<cmd>` so the agent ends up owning the global tree it later needs to
update.

## Worked example

```
$ which node
/usr/bin/node

$ node --version
v22.14.0

$ sudo -u agent npm config get prefix
/home/agent/.npm-global

$ sudo -u agent which claude
/home/agent/.local/bin/claude

# Cron entry under /etc/cron.d/agentlinux:
# */5 * * * * agent /home/agent/.npm-global/bin/get-shit-done-cc heartbeat
# claude resolves the same way under cron, systemd, and non-interactive ssh.

$ ssh agent@host 'which claude'
/home/agent/.local/bin/claude

$ sudo -u agent bash -c 'which claude'
/home/agent/.local/bin/claude
```

Every invocation mode resolves the agent's binaries to paths the agent
owns. That is the whole runtime contract, made observable.

## Value vs the naive approach

Without this runtime layer, the two naive paths are "install nvm/asdf for
the agent" or "use system Node.js with `sudo npm install -g`." Two
problems:

1. **Version managers don't survive non-interactive contexts.** nvm,
   asdf, and fnm rely on shell-init hooks that only fire in interactive
   shells. Cron, systemd, ssh -i, and `sudo -u agent` skip those hooks,
   leaving `node` missing exactly where automation runs. Agents that
   work in the developer's terminal silently break the moment they run
   unattended — and the failure mode is "command not found", which the
   agent has no good way to recover from.
2. **`sudo npm install -g` corrupts ownership.** Once root has written
   the global tree under `/usr/lib/node_modules`, the agent can no
   longer self-update; every subsequent operation under `~/.npm/` fails
   with EACCES, and tools like Claude Code that ship their own updater
   end up with a wrapper at `/usr/local/bin/` they cannot rewrite. See
   [Agent user](agent-user.md) for the full bug class — this naive path
   is its origin point.

**AgentLinux uses system Node.js for predictability and a per-user npm
prefix for ownership — and wires PATH so both choices hold across every
shell context the agent ever runs in.** The system-Node decision is
recorded as ADR-005; the per-user prefix as ADR-004. The two together
are the load-bearing decisions everything else in the runtime layer is
downstream of.

## Related

- [Agent user](agent-user.md) — the user that owns the per-user npm
  prefix and the EACCES + recursive-shim bug class this layer prevents.
- [Installer](installer.md) — the entrypoint whose third and fourth
  provisioner steps build this runtime layer.
- [Claude Code](claude-code.md) — the canonical case for why this layer
  matters; AGT-02 is its release-gate test.
- [GSD](gsd.md) — installed via npm into the per-user prefix this layer
  provides.
