# Claude Code

Claude Code is Anthropic's published agent CLI — a coding agent that reads
files, edits them, runs commands, and reasons about the result. AgentLinux
ships it as an opt-in catalog entry: `agentlinux install claude-code` runs
the upstream native installer as the agent user, putting Claude Code into
the agent's own home directory tree where the tool's own self-updater
(`claude update`) can rewrite it without `sudo` or EACCES. That
self-update-without-sudo invariant is the canonical AgentLinux
acceptance test.

## The problem

`claude update` is the recommended way to stay current with Claude Code —
and the operation that breaks loudest under the wrong install path. The
naive way to install Claude Code on a fresh Ubuntu host is
`sudo npm install -g @anthropic-ai/claude-code` (or, equivalently, the
upstream `claude.ai/install.sh` piped to `sudo bash`). Either path lands
the install tree under root ownership; the next `claude update` then
fails with EACCES the moment it tries to rewrite itself in place. The
operator reaches for `sudo claude update`, which succeeds once but
corrupts the next layer of files. From that point forward every
interactive operation needs `sudo` and every autonomous loop stalls on
the password prompt that never arrives — see [Agent user](agent-user.md)
for the full bug class.

AgentLinux's release-gate test is the inverse contract: a fresh install
plus `claude update` must succeed with zero `sudo` prompts and zero
EACCES lines in the transcript. It is the loudest acceptance test in the
project — the one whose failure most reliably signals the bug class
AgentLinux exists to eliminate.

## What AgentLinux does

`agentlinux install claude-code` runs the catalog recipe via the agent
user. The recipe pipes Anthropic's official native installer
(`https://claude.ai/install.sh`) to `bash` — but with the running user
already dropped to `agent`, so the install tree lands under
`/home/agent/.local/` instead of root-owned territory. The pinned
version (the one AgentLinux's CI tested against the full Docker + QEMU
matrix in the latest release) is passed as the installer's positional
argument, so the recipe writes the version AgentLinux's release-gate
exercised — not whichever version Anthropic's stable channel happens to
serve at install time.

After install, the binary at `/home/agent/.local/bin/claude` is
agent-owned. Its parent directory is on the agent's PATH across every
invocation mode (interactive shell, `sudo -u agent`, systemd, cron, SSH —
see [Node.js runtime](nodejs-runtime.md)). When the operator later runs
`claude update`, Claude Code's own updater rewrites the binary in place
with no `sudo`, no EACCES, no recursive shim at `/usr/local/bin/`.
AgentLinux gets out of the way; the upstream self-updater Just Works.

AgentLinux also makes the version you installed stay the version you
installed. The recipe drops a small marker in the agent's Claude Code
settings (Anthropic's documented `DISABLE_AUTOUPDATER` flag) that
disables the in-tool background auto-updater, so the binary on disk
doesn't quietly drift off the curated combo the moment the agent first
launches the CLI. Manual `claude update` still works on demand — the
operator stays in control of when to move ahead, and
`agentlinux upgrade` surfaces any divergence between curated, installed,
and upstream-latest.

## Worked example

```
$ agentlinux install claude-code
claude-code: installing version 2.1.98 via native installer
claude-code: installed, reports: 2.1.98 (Claude Code)
claude-code: install complete (version-lock satisfied — installed matches pin)

$ sudo -u agent claude update
✓ Claude Code 2.1.114 installed

$ agentlinux upgrade
Per-agent divergence (report-only):

  claude-code  installed=2.1.114  curated=2.1.98   state=override-ahead
  ...

  Choose per-agent: [keep override] [accept curated] [accept upstream latest]
```

The divergence after `claude update` is intentional. AgentLinux *surfaces*
the gap between the curated combo and what the user has on disk — it
does not silently overwrite the user's choice. The operator picks "keep
override" to mark the entry sticky, or "accept curated" to downgrade
back to the tested combo. Either is defensible; AgentLinux just refuses
to make the call silently.

## Value vs the naive approach

Without AgentLinux, the naive path is `sudo npm install -g
@anthropic-ai/claude-code`. Two problems:

1. **`claude update` breaks on root-owned trees.** Claude Code's own
   self-updater is the recommended way to stay current, and it writes
   in place into the install tree. If that tree is root-owned, the
   updater fails with EACCES on the very first attempt; the operator
   reaches for `sudo claude update`, which succeeds once but corrupts
   another layer of files (`~/.npm/`, `~/.claude/`) along the way. From
   that point forward every operation needs `sudo`, autonomous loops
   stall on missing password prompts, and the only clean recovery path
   is a full reinstall.
2. **Upstream `latest` ships immediately.** The naive `npm install -g`
   path always pulls whichever version Anthropic published most
   recently, including the rare broken one. AgentLinux pins to a
   CI-tested version and lets the user opt past the pin via
   `agentlinux pin claude-code=latest` (sticky) or `=<semver>` (held)
   — `agentlinux upgrade` makes the divergence between installed,
   curated, and upstream visible rather than silent.

**AgentLinux makes Claude Code installable, updatable, and reconcilable
— without root, without surprises.** The agent owns the tree the tool
needs to rewrite; the catalog records what AgentLinux actually tested;
`upgrade` and `pin` give the operator control over when to move ahead
of the curated combo.

## Related

- [Agent user](agent-user.md) — the user that owns the install tree this
  agent's self-updater rewrites.
- [Catalog](catalog.md) — where the `claude-code` entry's
  `pinned_version` lives.
- [Registry CLI](registry-cli.md) — the `agentlinux` command that drives
  install / upgrade / pin against the catalog.
- [../STABILITY-MODEL.md](../STABILITY-MODEL.md) — how curated combos
  and three-way divergence (curated / installed / upstream-latest) work;
  uses Claude Code's `claude update` as its own worked example.
