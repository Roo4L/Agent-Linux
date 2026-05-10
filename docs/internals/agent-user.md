# Agent user

AgentLinux provisions a dedicated `agent` user with a per-user npm prefix.
Every agent tool — Claude Code, GSD, Playwright — installs into and updates
from the agent's own home directory. No EACCES, no `sudo` fights, no
recursive shims at `/usr/local/bin/`. The agent owns its tools so it can
update them.

## The problem

The bug class AgentLinux exists to eliminate is the EACCES + recursive-shim
loop that follows from `sudo npm install -g`. The sequence is short and
reliably catastrophic: an operator runs `sudo npm install -g claude-code`,
which writes a root-owned tree under `/usr/lib/node_modules`. The tool then
writes a wrapper at `/usr/local/bin/claude` that `exec`s the binary inside
that tree. So far so good — until the operator runs `claude update`.

`claude update` is Claude Code's own self-updater. It tries to rewrite the
binary in-place. But the running user is not root, the binary is, so the
update fails with EACCES. The operator reaches for `sudo` again. Now the
update succeeds, but every `~/.npm/` cache file the update touched along the
way is root-owned too, and the next non-`sudo` invocation fails for a
*different* reason. The operator climbs the privilege ladder one more rung,
and from this point on every operation needs `sudo` — a permission tax on
every interactive task and a hard stop for any autonomous loop that cannot
prompt for a password.

The same shape breaks every tool that ships its own self-updater into a
root-owned prefix: the wrapper at `/usr/local/bin/` points at the wrong
inode after the next update, or points at a tree the running user cannot
write to, and the tool gradually rots into a state where only `sudo`
unblocks it. AGT-02 — the AgentLinux release-gate test — is the regression
test that catches exactly this: a fresh install plus `claude update` must
succeed with zero EACCES and zero `sudo` prompts in the transcript.

## What AgentLinux does

The installer's first provisioner step creates an `agent` user with a real
home at `/home/agent/`, `/bin/bash` as login shell, and the C.UTF-8 locale
enforced system-wide so non-ASCII output behaves predictably across
Docker, QEMU, cron, and SSH. The same step writes a `/home/agent/CLAUDE.md`
that documents the anti-patterns to any agent that lands in this user — the
forbidden `sudo npm install -g`, the forbidden `/usr/local/bin/` wrapper
shim, the forbidden second Node.js install.

The agent user gets a per-user npm prefix at `~/.npm-global/`, configured
via `~/.npmrc` and re-enforced via `NPM_CONFIG_PREFIX` for systemd and cron
contexts where the `.npmrc` read might regress. PATH is wired across every
invocation mode the agent ever runs in: interactive shell (`/etc/profile.d/`
fragment), non-interactive bash (`~/.bashrc` marker block at the top, before
the skel early-return guard), systemd `User=agent` units (`/etc/agentlinux.env`
consumed via `EnvironmentFile=`), cron jobs (`/etc/cron.d/agentlinux` PATH
header), and `sudo -u agent` / `sudo -u agent -i`. Six modes, four
artifacts, byte-identical PATH literal in each.

Every install routes through an `as_user agent <cmd>` helper that drops to
the agent user before invoking npm, the upstream native installer, or any
other write. The agent ends up owning every file it later needs to update.
`sudo npm install -g` is forbidden everywhere in the codebase; the
`security-engineer` review subagent flags it on every PR.

## Worked example

```
$ curl -fsSL https://agentlinux.org/install.sh | sudo bash
... provisioning ...
agentlinux-install: agentlinux-install complete

$ agentlinux install claude-code
claude-code: install complete (resolves at /home/agent/.local/bin/claude)

$ sudo -u agent claude --version
2.1.98 (Claude Code)

$ sudo -u agent claude update
✓ Claude Code 2.1.114 installed

$ sudo -u agent claude --version
2.1.114 (Claude Code)
```

No `sudo` on `claude update`. No EACCES. No password prompt. The agent owns
its own install tree, so its self-updater Just Works — which is the entire
point.

## Value vs the naive approach

Without a dedicated agent user with its own npm prefix, the naive path is
`sudo npm install -g <tool>`. Two problems:

1. **EACCES on every subsequent non-root operation under `~/.npm/`.** Once
   root has written into the npm cache or global tree, the user that runs
   the agent — typically not root — can no longer install or update without
   `sudo` again. That `sudo` poisons the next file it touches, and the
   user is now locked into climbing the privilege ladder for every tooling
   operation, including ones that have nothing to do with the original
   install.
2. **Self-updaters break, often silently.** Tools like Claude Code that
   ship their own updater (`claude update`) write into a root-owned prefix,
   leave a wrapper at `/usr/local/bin/`, and fail to rewrite themselves on
   the next update. The user reaches for `sudo`, fixes one symptom, creates
   the next one. AGT-02 is the canonical regression test for this exact
   sequence.

**AgentLinux gives agents their own user with their own npm prefix, so
self-update Just Works.** The per-user prefix as the keystone ownership
decision is recorded as ADR-004; it is the single design choice every other
piece of the install layer is downstream of.

## Related

- [Installer](installer.md) — the entrypoint that provisions this user.
- [Node.js runtime](nodejs-runtime.md) — the per-user npm prefix and the
  PATH wiring that backs this user's ownership story.
- [Sudo drop-in](sudo-drop-in.md) — the `/etc/sudoers.d/agentlinux` grant
  that lets this user run privileged commands without password prompts.
- [Claude Code](claude-code.md) — the canonical case study; AGT-02 is its
  release-gate test.
