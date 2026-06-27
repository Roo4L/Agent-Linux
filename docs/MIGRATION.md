# Brownfield install — what happens on a host that isn't empty

`agentlinux install` is brownfield-aware: it inspects everything it manages
(the install user, Node.js, the npm global prefix, the sudoers drop-in, and
each catalog agent) and decides per component *before touching anything*:

- **Reuse** — already matches; left untouched.
- **Create** — missing; installed fresh.
- **Remediate** — present but fixable (wrong ownership, drifted sudoers, a
  broken agent). Asks first in a terminal, or needs `--yes` non-interactively.
- **Bail** — can't reconcile it (e.g. the existing `agent` user has the wrong
  login shell). Exits `65` with a hint; nothing is changed.

## Preview before you install

```bash
sudo agentlinux install --dry-run
```

Runs the full detection + decision pass, prints what it would do per component,
and **exits 0 without changing anything**. Run it first on any host you're
unsure about. Plain `sudo agentlinux install` (no `--yes`) is safe too: if
anything needs an overwrite it refuses with exit `65` and tells you what,
before touching the host.

## What is preserved

AgentLinux only manages its own surface. It does not touch:

- an existing `agent` user's home, dotfiles, or other configuration;
- other `/etc/sudoers.d/*` files (it owns only `agentlinux`);
- `~/.claude/` and equivalent agent user-data — kept even across a remediation
  reinstall.

## Example: Claude Code installed as root

The bug AgentLinux exists to fix. Claude Code was installed with
`sudo npm install -g`, so the binary is root-owned and `claude update` fails:

```console
$ sudo -u agent -H claude update
npm error code EACCES
npm error path /usr/local/lib/node_modules
```

`--dry-run` flags it; `--yes` fixes it — reinstalls Claude Code under the
`agent` user at its own path, preserving `~/.claude/`:

```console
$ sudo agentlinux install --yes
$ sudo -u agent -H claude update      # now succeeds, no EACCES
```

## Example: you already run NodeSource Node 22

A host already on Node 22 from NodeSource, with an `agent` user, is the easy
case — both are reused untouched, and only the agents you ask for get installed:

```bash
sudo agentlinux install            # Node + user reused; nothing reinstalled
sudo agentlinux install claude-code
```

## Exit codes

| code | meaning |
|------|---------|
| `0`  | success (or `--dry-run` finished) |
| `64` | bad or contradictory flags (e.g. `--dry-run --yes`) |
| `65` | host state can't be reconciled without help — the message names the conflict and suggests `--user=NAME` or a manual fix |
| `1`  | a runtime failure while creating or remediating |
