# Choosing the install user

When you install AgentLinux, it provisions a dedicated Linux user to run your
coding agents (such as Claude Code). During an interactive install you are
asked:

```
Install AgentLinux under which user? [default: agent]
```

Press **Enter** to accept the default (`agent`), or type another name.

## What this account is

The user you choose is the home for everything AgentLinux sets up. That account:

- **owns its home directory, Node.js runtime, and npm global packages** — so
  agents self-update and install tools without permission errors or `sudo`
  fights, and nothing lands in system-owned paths;
- **is where `agentlinux install <tool>` places agent tools** — every tool in
  the catalog installs into and updates from this user's home;
- **is granted passwordless `sudo`** (see below).

Your coding agent runs *as* this user.

## Passwordless sudo

AgentLinux writes a `sudo` rule (`/etc/sudoers.d/agentlinux`) that lets the
chosen user run administrative commands **without a password**. This is
deliberate: a coding agent frequently needs to install system packages, restart
services, and manage the machine, and an interactive password prompt would stall
it.

The practical implication: **the user you name here has full administrative
control of the machine.** On a dedicated agent host that is the intended setup.
On a shared machine, choose (or create) an account you are comfortable granting
that level of access — do not point the install at a person's everyday login
unless you mean for it to have passwordless root.

## Creating a new user vs. adopting an existing one

Either kind of name works:

- **A name that does not exist yet is created.** This is the common case — you
  invent a name (e.g. `agent` or `claude`) and AgentLinux creates the account,
  its home, and its runtime from scratch.
- **An existing, compatible user is adopted in place.** If the name already
  exists and is a normal login user, AgentLinux configures it rather than
  replacing it — your files stay put; it adds the runtime, PATH wiring, and the
  `sudo` rule.

Not every existing account can be adopted. System and service accounts (the
low-numbered users your distribution ships) and `root` are rejected, because
granting them the agent's passwordless-sudo rule or repurposing them as a login
would be unsafe. A name must also be lowercase and start with a letter — the
installer rejects anything outside `^[a-z][a-z0-9_-]*$`.

## How the name is chosen

The installer resolves the target user by this order, highest priority first:

1. **`--user=NAME`** on the command line — always wins.
2. **`AGENTLINUX_USER=NAME`** environment variable — used when no flag is given.
   Handy for the piped installer: `curl … | AGENTLINUX_USER=claude sudo bash`.
3. **The interactive prompt** — shown only on a first-time install in a terminal
   when you gave neither of the above.
4. **The default, `agent`** — used by non-interactive installs (the usual
   `curl … | sudo bash`) that pass no flag and no environment variable.

A re-run on a machine that already has AgentLinux does **not** ask again — the
user was chosen the first time and is recorded on the machine. When the name
comes from `--user` or `AGENTLINUX_USER`, an invalid value is rejected up front —
before any account is created or any file is written — so a typo or a hostile
`--user=root` never takes effect.

## Where the choice is recorded

Your choice is saved to `/etc/agentlinux.env` as `AGENTLINUX_USER=<name>`, and
every later AgentLinux command reads it. To switch to a different user, install
fresh under the new name — an in-place rename of an already-installed user is not
supported.
